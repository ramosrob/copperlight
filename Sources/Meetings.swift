import AppKit
import EventKit

/// The first video call link in an event's URL, location or notes: Google Meet, Zoom, Teams or Webex.
func joinLink(in texts: [String?]) -> URL? {
    let pattern = #/https://(?:meet\.google\.com/[a-z0-9-]+|[\w.-]*zoom\.us/(?:j|my|w)/[^\s<>"]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|[\w.-]*webex\.com/[^\s<>"]+)/#
    for text in texts.compactMap(\.self) {
        if let match = text.firstMatch(of: pattern.ignoresCase()) { return URL(string: String(match.output)) }
    }
    return nil
}

/// "in 15 min", "now", "in 2 h 5 min": how soon a meeting starts.
func startsIn(_ start: Date, end: Date, now: Date = .now) -> String {
    if start <= now { return end > now ? "now" : "ended" }
    let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
    return minutes < 60 ? "in \(minutes) min" : "in \(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
}

/// An event, as the launcher shows it.
struct CalendarItem: Sendable {
    var title: String
    var start: Date
    var end: Date
    var link: URL?
    var calendar = ""
    var location: String?
    var notes: String?
    var people: [String] = []
    var organizer: String?
    var id = ""
}

extension CalendarItem {
    init(_ event: EKEvent) {
        self.init(title: event.title ?? "Untitled", start: event.startDate, end: event.endDate,
                  link: joinLink(in: [event.url?.absoluteString, event.location, event.notes]), calendar: event.calendar?.title ?? "",
                  location: event.location, notes: event.notes, people: (event.attendees ?? []).compactMap(\.name),
                  organizer: event.organizer?.name, id: event.eventIdentifier ?? "")
    }
}

/// The meeting the empty launcher offers: one with a call to join, starting in the next 10 minutes or started in the
/// last 10 and not over; the one about to start before one already going.
func nextMeeting(_ items: [CalendarItem], now: Date = .now) -> CalendarItem? {
    let window: TimeInterval = 10 * 60
    let joinable = items.filter { item in
        let ahead = item.start.timeIntervalSince(now) // negative once it's started
        return item.link != nil && item.end > now && ahead <= window && ahead >= -window
    }
    let upcoming = joinable.filter { $0.start > now }.min { $0.start < $1.start }
    return upcoming ?? joinable.max { $0.start < $1.start }
}

/// The copper badge beside an event that's coming up (within the hour: "in 17 min") or going ("Now"); nil otherwise.
func eventBadge(_ item: CalendarItem, now: Date = .now) -> String? {
    if item.start <= now { return item.end > now ? "Now" : nil }
    return item.start.timeIntervalSince(now) <= 60 * 60 ? startsIn(item.start, end: item.end, now: now) : nil
}

/// The call's service, by its link: "Google Meet", "Zoom", "Teams", "Webex".
func callService(_ link: URL) -> String {
    let host = link.host() ?? ""
    return host.contains("google") ? "Google Meet" : host.contains("zoom") ? "Zoom" : host.contains("teams") ? "Teams" : host.contains("webex") ? "Webex" : "Call"
}

/// What Tab shows beside an event: its title, day and times and notes, and under them its calendar, place, call (and
/// link), who's coming and who asked.
func eventPreview(_ item: CalendarItem, now: Date = .now) -> (text: String, details: [(String, String)]) {
    let hours = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    let day = Calendar.current.isDate(item.start, inSameDayAs: now) ? "Today" : item.start.formatted(.dateTime.weekday(.wide).day().month())
    let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000) ?? ""
    let text = "\(item.title)\n\(day), \(hours(item.start))–\(hours(item.end))" + (notes.isEmpty ? "" : "\n\n\(notes)")
    let place = item.location.flatMap { location in
        location.isEmpty || item.link.map({ location.contains($0.absoluteString) }) == true ? nil : location
    }
    let people = item.people.isEmpty ? nil
        : item.people.prefix(4).joined(separator: ", ") + (item.people.count > 4 ? " +\(item.people.count - 4)" : "")
    let details: [(String, String?)] = [("Calendar", item.calendar.isEmpty ? nil : item.calendar), ("Where", place),
                                        ("Call", item.link.map(callService)), ("Link", item.link?.absoluteString),
                                        ("People", people), ("Organizer", item.organizer)]
    return (text, details.compactMap { label, value in value.map { (label, $0) } })
}

/// The first line of an event's own notes, before any call's invitation (a divider, a link, "Join …"). nil: none.
func eventNote(_ notes: String?) -> String? {
    for line in (notes ?? "").split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
        if line.contains("://") || line.contains(#/^[^\p{L}\d\s]{5,}/#) || line.contains(#/(?i)^(join|microsoft teams|or dial|meeting id)\b/#) {
            return nil
        }
        if line.contains(where: \.isLetter) { return String(line.prefix(80)) }
    }
    return nil
}

/// The meeting to join now on a band (how soon, its title, times and call, who's coming, a line of its notes), and
/// its rows under it: Join, then Open in Calendar.
func joinRows(_ item: CalendarItem, now: Date = .now, browser: Config.Browser, score: Double) -> [LauncherResult] {
    let hours = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    let service = item.link.map(callService)
    let people = item.people.prefix(4).map { String($0.split(separator: "@").first ?? "") } // an address alone: its name part
    let card = MeetingCard(soon: eventBadge(item, now: now) ?? startsIn(item.start, end: item.end, now: now), calendar: item.calendar,
                           title: item.title, when: "\(hours(item.start))–\(hours(item.end))" + (service.map { " · \($0)" } ?? ""),
                           initials: people.map(initials),
                           names: people.map { String($0.split(separator: " ").first ?? "") }.joined(separator: ", ")
                               + (item.people.count > 4 ? " +\(item.people.count - 4)" : ""),
                           note: eventNote(item.notes))
    return [LauncherResult(id: "meeting:\(item.id)", title: "Join " + (service ?? "Call"),
                           subtitle: item.link.map { ($0.host() ?? "") + $0.path() } ?? "", icon: .symbol("video"), score: score,
                           actionTitle: "Join", action: item.link.map { webOpener($0, browser: browser) } ?? openCalendar, answer: .meeting(card)),
            LauncherResult(id: "meeting:\(item.id):calendar", title: "Open in Calendar", icon: .symbol("calendar"), score: score - 0.001,
                           actionTitle: "Open", action: openCalendar, answer: .meeting(card))]
}

/// `meetings`, `agenda`, `events` (and `calendar`, below the Calendar app): the rest of today's events from Calendar,
/// all-day ones aside, soonest first, a copper badge on one that's soon or going, its details a Tab away. Enter joins a
/// video call (Meet, Zoom, Teams, Webex), opening web links where `[browser]` says; otherwise it opens Calendar. Reading
/// events needs full Calendars access, asked for from a row, not while typing. The meeting to join now (`nextMeeting`)
/// comes first, on its band. The empty launcher shows it (`upNext`), or with `[meetings] show_on_open`, the day's events.
actor MeetingsProvider: ResultProvider {
    private var store: EKEventStore? // made once access is granted: one made before it sees no events
    private var browser = Config.Browser()
    private var showsOnOpen = false
    private var showsNext = true

    func setBrowser(_ browser: Config.Browser) { self.browser = browser }
    func setShowsOnOpen(_ on: Bool, next: Bool) { (showsOnOpen, showsNext) = (on, next) }

    /// The events left today, and the ones started in the last 10 minutes (still worth joining). Only with access.
    private func today(now: Date) -> [CalendarItem]? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let store = self.store ?? EKEventStore()
        self.store = store
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        return store.events(matching: store.predicateForEvents(withStart: now - 600, end: endOfDay, calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.map(CalendarItem.init)
    }

    private func row(_ item: CalendarItem, score: Double, now: Date) -> LauncherResult {
        let hours = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        let badge = eventBadge(item, now: now)
        let preview = eventPreview(item, now: now)
        return LauncherResult(
            id: "meeting:\(item.id)", title: item.title,
            subtitle: "\(hours(item.start))–\(hours(item.end))" + (badge == nil ? " · \(startsIn(item.start, end: item.end, now: now))" : "")
                + (item.link.map { " · \(callService($0))" } ?? ""),
            icon: .symbol(item.link == nil ? "calendar" : "video"), score: score,
            actionTitle: item.link == nil ? "Open Calendar" : "Join", action: item.link.map { webOpener($0, browser: browser) } ?? openCalendar,
            badge: badge, preview: preview.text, previewStyle: .prose, details: preview.details)
    }

    /// The meeting to join now on its band, then the other events.
    private func rows(_ items: [CalendarItem], base: Double, now: Date) -> [LauncherResult] {
        guard let next = nextMeeting(items, now: now) else { return items.enumerated().map { row($1, score: base - Double($0) / 100, now: now) } }
        let others = items.filter { $0.id != next.id || $0.start != next.start }
        return joinRows(next, now: now, browser: browser, score: base) + others.enumerated().map { row($1, score: base - Double($0 + 1) / 100, now: now) }
    }

    /// For the empty launcher: the meeting to join now, if any; with `show_on_open`, the day's next events. Never asks
    /// for access: opening the launcher shouldn't.
    func upNext() -> [LauncherResult] {
        let now = Date.now
        guard showsOnOpen || showsNext, let items = today(now: now) else { return [] }
        if showsOnOpen { return rows(Array(items.prefix(5)), base: 100, now: now) }
        return nextMeeting(items, now: now).map { joinRows($0, now: now, browser: browser, score: 100) } ?? []
    }

    func results(for query: String) async -> [LauncherResult] {
        let lower = query.lowercased()
        let base: Double
        if lower.count >= 3, "meetings".hasPrefix(lower) || "agenda".hasPrefix(lower) { base = 50 }
        else if lower == "event" || lower == "events" { base = 50 }
        else if lower == "calendar" { base = 1 } // the app first: it's what "calendar" opens
        else { return [] }
        let message = { (title: String, subtitle: String, actionTitle: String, action: @escaping @MainActor @Sendable () -> Void) in
            LauncherResult(id: "builtin:meetings", title: title, subtitle: subtitle, icon: .symbol("calendar"), score: base,
                           actionTitle: actionTitle, action: action)
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: break
        case .denied, .restricted:
            return [message("Allow Copperlight to see your calendars", "Privacy & Security → Calendars → Copperlight: Full Access", "Open System Settings", {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            })]
        default: // not asked yet, or add-only (for `add event`)
            return [message("See Today's Meetings", "Asks to read your calendars, once", "Allow", {
                Task {
                    guard (try? await EKEventStore().requestFullAccessToEvents()) == true else { return notify("Copperlight can't see your calendars") }
                    notify("Type “meetings” again to see them")
                }
            })]
        }
        let now = Date.now
        let items = today(now: now) ?? []
        guard !items.isEmpty else { return [message("No more meetings today", "", "Open Calendar", openCalendar)] }
        return rows(items, base: base, now: now)
    }
}

@MainActor private func openCalendar() {
    NSWorkspace.shared.openApplication(at: URL(filePath: "/System/Applications/Calendar.app"), configuration: .init())
}
