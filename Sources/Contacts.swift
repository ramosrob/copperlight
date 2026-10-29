import AppKit
import Contacts

/// Someone in Contacts, as the launcher finds and shows them.
struct Person: Equatable, Sendable {
    struct Handle: Equatable, Sendable {
        var label: String // "mobile", "work", as Contacts names it
        var value: String
    }

    var id: String
    var name: String
    var nickname = ""
    var organization = ""
    var jobTitle = ""
    var phones: [Handle] = []
    var emails: [Handle] = []
    var birthday: DateComponents? = nil
    var photo: Data? = nil // read only for the card on show, not kept for everyone
}

/// A number as links take it: "+351 912 345 678" → "+351912345678".
private func dialable(_ phone: String) -> String { phone.filter { $0.isNumber || $0 == "+" } }

/// Messages with them: their first mobile number (else their first number), else their first email. nil: neither.
func messageURL(_ person: Person) -> URL? {
    let phone = person.phones.first { ["mobile", "iphone"].contains($0.label.lowercased()) } ?? person.phones.first
    if let phone { return URL(string: "sms:" + dialable(phone.value)) }
    return person.emails.first.flatMap { URL(string: "imessage:" + $0.value) }
}

private let actionIcons = ["Message": "message", "Call": "phone", "FaceTime": "video", "WhatsApp": "bubble.left", "Email": "envelope",
                           "Open in Contacts": "person.crop.circle"]

/// Their card in the Contacts app.
func contactCardURL(_ id: String) -> URL? { URL(string: "addressbook://" + id) }

/// The card beside a person's rows: their initials, name, job and company, and under them each number, email and their
/// birthday.
func personCard(_ person: Person) -> PersonCard {
    let birthday = person.birthday.flatMap { day in
        Calendar.current.date(from: DateComponents(year: 2000, month: day.month, day: day.day))?.formatted(.dateTime.month(.wide).day())
    }
    let details = (person.phones + person.emails).map { ($0.label.isEmpty ? "other" : $0.label, $0.value) }
        + (birthday.map { [("birthday", $0)] } ?? [])
    let words = person.name.split(separator: " ")
    let initials = String([words.first?.first, words.count > 1 ? words.last?.first : nil].compactMap(\.self)).uppercased()
    let company = person.organization == person.name ? "" : person.organization // a company's own card
    let photo = person.photo.flatMap { NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    return PersonCard(initials: initials, name: person.name, job: person.jobTitle, company: company, details: details, photo: photo)
}

/// Their photo in Contacts, small. nil: none, or no access.
private func contactPhoto(_ id: String) -> Data? {
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
    return try? CNContactStore().unifiedContact(withIdentifier: id, keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor])
        .thumbnailImageData
}

/// Everyone in Contacts, by name. Empty without access.
func loadPeople() -> [Person] {
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }
    let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        + ([CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey] as [CNKeyDescriptor])
    let label = { (raw: String?) in raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "" }
    var people: [Person] = []
    try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
        guard !name.isEmpty else { return }
        people.append(Person(id: contact.identifier, name: name, nickname: contact.nickname, organization: contact.organizationName, jobTitle: contact.jobTitle,
                             phones: contact.phoneNumbers.map { .init(label: label($0.label), value: $0.value.stringValue) },
                             emails: contact.emailAddresses.map { .init(label: label($0.label), value: $0.value as String) },
                             birthday: contact.birthday))
    }
    return people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// People from Contacts, from 2 letters: every word typed starts a word of their name, nickname or company. Enter
/// messages them (a number, else an email, else their card opens); Tab goes into the Contact chip, every way to reach
/// them (message, call, FaceTime, WhatsApp when it's installed, email, copy) beside their card. Read on the Mac
/// when the launcher opens, at most every 2 minutes, kept in memory only; reading them needs access, asked for from a
/// row (`contacts`), never while typing.
actor ContactsProvider: ResultProvider {
    static let prefix = "contact "
    private var people: [Person] = [] { didSet { keys = people.map(Self.searchKey) } }
    private var keys: [String] = []
    private var loaded = Date.distantPast
    private let access: @Sendable () -> CNAuthorizationStatus
    private var whatsApp: Bool

    init() {
        access = { CNContactStore.authorizationStatus(for: .contacts) }
        whatsApp = false
    }

    /// Tests: these people, with access.
    init(people: [Person], whatsApp: Bool) {
        (self.people, self.whatsApp) = (people, whatsApp)
        access = { .authorized }
        keys = people.map(Self.searchKey) // didSet doesn't run in init
    }

    nonisolated var modes: [Mode] {
        [Mode(prefix: Self.prefix, title: "Contact", icon: .symbol("person"), hint: "A name, or nothing for everyone")]
    }

    func refresh(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(loaded) > 120, access() == .authorized else { return }
        loaded = .now
        whatsApp = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "whatsapp://send")!) != nil
        people = loadPeople()
    }

    private static func searchKey(_ person: Person) -> String { wordStarts([person.name, person.nickname, person.organization].joined(separator: " ")) }

    private func matching(_ text: String) -> [Person] {
        let words = typedWords(text)
        return zip(people, keys).filter { _, key in words.allSatisfy { key.contains($0) } }.map(\.0)
    }

    func results(for query: String) -> [LauncherResult] {
        guard !Task.isCancelled else { return [] }
        let lower = query.lowercased()
        // `contacts`: below the Contacts app, the chip a Tab away, or the question that gives access.
        var rows: [LauncherResult] = []
        if lower.count >= 4, "contacts".hasPrefix(lower) || "people".hasPrefix(lower) {
            rows.append(access() == .authorized
                ? LauncherResult(id: "builtin:contacts", title: "Search Contacts", subtitle: "Message, call or email someone",
                                 icon: .symbol("person"), score: 0.95, actionTitle: "Search", action: {}, completion: Self.prefix)
                : accessRow())
        }
        guard query.count >= 2 else { return rows }
        return rows + matching(query).prefix(5).enumerated().map { personRow($1, score: 0.5 - Double($0) / 100) }
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        let text = query.dropFirst(Self.prefix.count - 1).trimmingCharacters(in: .whitespaces)
        guard access() == .authorized else { return [accessRow()] }
        let found = text.isEmpty ? people : matching(text)
        let exact = found.filter { $0.name.caseInsensitiveCompare(text) == .orderedSame }
        if let one = exact.first ?? (found.count == 1 ? found.first : nil) { return actionRows(one) }
        return found.enumerated().map { personRow($1, score: 50 - Double($0) / 10_000) }
    }

    private func accessRow() -> LauncherResult {
        if access() == .notDetermined {
            return LauncherResult(id: "builtin:contacts", title: "Search Your Contacts", subtitle: "Asks to read your contacts, once",
                                  icon: .symbol("person"), score: 0.95, actionTitle: "Allow", action: {
                Task {
                    guard (try? await CNContactStore().requestAccess(for: .contacts)) == true else { return notify("Copperlight can't see your contacts") }
                    notify("Type a name to find them")
                }
            })
        }
        return LauncherResult(id: "builtin:contacts", title: "Allow Copperlight to see your contacts", subtitle: "Privacy & Security → Contacts",
                              icon: .symbol("person"), score: 0.95, actionTitle: "Open System Settings", action: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!)
        })
    }

    private func personRow(_ person: Person, score: Double) -> LauncherResult {
        let open = messageURL(person) ?? contactCardURL(person.id)
        return LauncherResult(id: "contact:\(person.id)", title: person.name,
                              subtitle: [person.phones.first?.value, person.emails.first?.value].compactMap(\.self).joined(separator: " · "),
                              icon: .symbol("person"), score: score, actionTitle: messageURL(person) == nil ? "Open in Contacts" : "Message",
                              action: { if let open { NSWorkspace.shared.open(open) } }, more: ("Actions", Self.prefix + person.name))
    }

    /// In the chip: each way to reach them, by number, then by email, then copying them, then their card.
    private func actionRows(_ person: Person) -> [LauncherResult] {
        var shown = person
        if shown.photo == nil { shown.photo = contactPhoto(person.id) }
        let card = personCard(shown)
        var rows: [(title: String, subtitle: String, url: URL?, copy: String?)] = []
        for phone in person.phones {
            let number = dialable(phone.value), subtitle = [phone.value, phone.label].filter { !$0.isEmpty }.joined(separator: " · ")
            rows += [("Message", subtitle, URL(string: "sms:" + number), nil), ("Call", subtitle, URL(string: "tel:" + number), nil),
                     ("FaceTime", subtitle, URL(string: "facetime:" + number), nil)]
            if whatsApp { rows.append(("WhatsApp", subtitle, URL(string: "whatsapp://send?phone=" + number.filter(\.isNumber)), nil)) }
        }
        for email in person.emails {
            let subtitle = [email.value, email.label].filter { !$0.isEmpty }.joined(separator: " · ")
            // Without a number, Messages reaches them by email.
            if person.phones.isEmpty { rows.append(("Message", subtitle, URL(string: "imessage:" + email.value), nil)) }
            rows.append(("Email", subtitle, URL(string: "mailto:" + email.value), nil))
        }
        rows += (person.phones + person.emails).map { ("Copy \($0.value)", $0.label, nil, $0.value) }
        rows.append(("Open in Contacts", "", contactCardURL(person.id), nil))
        return rows.enumerated().map { index, row in
            LauncherResult(id: "contact:\(person.id):\(row.title):\(row.subtitle)", title: row.title, subtitle: row.subtitle,
                           icon: .symbol(actionIcons[row.title] ?? (row.copy != nil ? "doc.on.doc" : "person")), score: 50 - Double(index) / 100,
                           actionTitle: row.copy != nil ? "Copy" : row.title == "Open in Contacts" ? "Open" : row.title, action: {
                if let copy = row.copy { return copyToClipboard(copy) }
                if let url = row.url { NSWorkspace.shared.open(url) }
            }, answer: .person(card))
        }
    }
}
