import AppKit
import EventKit

/// A date read from typed text ("fri 10am dentist"): the rest of the text is the title.
struct CaptureDate: Equatable {
    var title: String
    var date: Date
    var duration: TimeInterval // 0 unless a range was typed ("10-11am")
    var allDay: Bool // no time typed ("friday"): the detector says noon, which nobody meant
}

/// The first date in `text`, with the words around it as the title; nil when there's no date.
func captureDate(_ text: String) -> CaptureDate? {
    let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    guard let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let date = match.date,
          let range = Range(match.range, in: text) else { return nil }
    let phrase = text[range].lowercased()
    let allDay = phrase.firstMatch(of: #/\d\s*(am|pm|h\b)|\d:\d|noon|midnight/#) == nil
    // "dentist on Oct 20" → "dentist", not "dentist on".
    let title = (text[..<range.lowerBound] + " " + text[range.upperBound...])
        .replacing(#/(?i)\s+(on|at|by)\s*$|^\s*(on|at|by)\s+/#, with: "")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return CaptureDate(title: title, date: date, duration: match.duration, allDay: allDay)
}

/// "Fri 16 Oct, 10:00–11:00", "Fri 16 Oct" (all day), "Wed 14 Oct, 17:00" (no end).
func whenText(_ when: CaptureDate, end: Bool) -> String {
    let day = when.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    guard !when.allDay else { return day }
    let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    return "\(day), \(time(when.date))" + (end ? "–\(time(when.date + eventLength(when)))" : "")
}

private func eventLength(_ when: CaptureDate) -> TimeInterval { when.duration > 0 ? when.duration : 3600 }

/// `add note|todo|event …`, `screenshot`, `record`. Each one's id is `builtin:<name>`, so a `[[command]]`
/// with the same name replaces it (SearchModel drops the built-in row).
struct CaptureProvider: ResultProvider {
    let addToNote: @MainActor @Sendable (String) -> Void

    private struct Target { let name, title, icon: String }
    private static let targets = [
        Target(name: "note", title: "Add to Note", icon: "note.text"),
        Target(name: "todo", title: "Add Reminder", icon: "checklist"),
        Target(name: "event", title: "Add Calendar Event", icon: "calendar"),
    ]

    func results(for query: String) -> [LauncherResult] {
        if let rest = words(after: "add", in: query) { return addRows(rest) }
        let tools = [("screenshot", "Screenshot", "Screenshot toolbar (⌘⇧5)", "camera.viewfinder", false),
                     ("record", "Record Screen", "Screenshot toolbar, ready to record", "record.circle", true)]
        return tools.compactMap { name, title, subtitle, icon, video in
            let score: Double? = query.caseInsensitiveCompare(name) == .orderedSame ? 50
                : query.count >= 3 && name.hasPrefix(query.lowercased()) ? 0.5 : nil
            return score.map { score in
                LauncherResult(id: "builtin:\(name)", title: title, subtitle: subtitle,
                               icon: .symbol(icon), score: score, action: { openScreenshotToolbar(video: video) })
            }
        }
    }

    /// `rest` is what follows "add": a target and its text, or the start of a target's name.
    private func addRows(_ rest: String) -> [LauncherResult] {
        if let target = Self.targets.first(where: { words(after: $0.name, in: rest) != nil }), let text = words(after: target.name, in: rest),
           !text.isEmpty {
            return [row(target, text: text)]
        }
        // "add", "add t", "add todo": the targets, and Enter types the name ("add todo ").
        return Self.targets.filter { $0.name.hasPrefix(rest.lowercased()) }.map { target in
            LauncherResult(id: "builtin:add \(target.name)", title: target.title, subtitle: "add \(target.name) " + example(target.name),
                           icon: .symbol(target.icon), score: 50, actionTitle: "Choose",
                           action: {}, completion: "add \(target.name) ")
        }
    }

    private func example(_ name: String) -> String {
        ["note": "buy milk", "todo": "call mom tomorrow 5pm", "event": "fri 10am dentist"][name] ?? ""
    }

    private func row(_ target: Target, text: String) -> LauncherResult {
        let id = "builtin:add \(target.name)", icon = LauncherResult.Icon.symbol(target.icon)
        switch target.name {
        case "note":
            return LauncherResult(id: id, title: text, subtitle: "Add to Note", icon: icon, score: 50,
                                  actionTitle: "Add", action: { [addToNote] in addToNote(text) })
        case "todo":
            let when = captureDate(text)
            let title = when.map { $0.title.isEmpty ? "New Reminder" : $0.title } ?? text
            return LauncherResult(id: id, title: title, subtitle: "Reminder · " + (when.map { whenText($0, end: false) } ?? "no date"),
                                  icon: icon, score: 50, actionTitle: "Add", action: { addReminder(title, due: when) })
        default: // event
            guard let when = captureDate(text) else {
                return LauncherResult(id: id, title: target.title, subtitle: "Needs a day or time: add event fri 10am dentist",
                                      icon: icon, score: 50, actionTitle: "", action: {})
            }
            let title = when.title.isEmpty ? "New Event" : when.title
            return LauncherResult(id: id, title: title, subtitle: "Calendar · " + whenText(when, end: true),
                                  icon: icon, score: 50, actionTitle: "Add", action: { addEvent(title, when) })
        }
    }
}

/// The text after `name` and a space ("add todo x" → "todo x"), "" for `name` alone; nil if `query` isn't `name`.
private func words(after name: String, in query: String) -> String? {
    guard let range = query.range(of: name, options: [.caseInsensitive, .anchored]) else { return nil }
    let rest = query[range.upperBound...]
    return rest.isEmpty || rest.first == " " ? rest.trimmingCharacters(in: .whitespaces) : nil
}

/// The ⌘⇧5 toolbar. The Screenshot app opens it through SystemUIServer, which has the Screen Recording
/// permission (running screencapture from Copperlight would need it for Copperlight). The toolbar starts in the mode
/// its `video` setting says, which is what the app's last use left there.
@MainActor func openScreenshotToolbar(video: Bool) {
    CFPreferencesSetAppValue("video" as CFString, NSNumber(value: video ? 1 : 0), "com.apple.screencapture" as CFString)
    CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
    NSWorkspace.shared.openApplication(at: URL(filePath: "/System/Applications/Utilities/Screenshot.app"), configuration: .init())
}

/// Adds a reminder to the default list, due (and alerting) at `due`. Asks for Reminders access the first time:
/// EventKit has no add-only access for reminders.
@MainActor func addReminder(_ title: String, due: CaptureDate?) {
    Task {
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToReminders() else {
                return notify("Allow Copperlight in Reminders to add reminders", "Privacy & Security → Reminders")
            }
            guard let list = store.defaultCalendarForNewReminders() else { return notify("Couldn't add the reminder", "There's no Reminders list") }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = list
            if let due {
                let parts: Set<Calendar.Component> = due.allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
                reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due.date)
                if !due.allDay { reminder.addAlarm(EKAlarm(absoluteDate: due.date)) }
            }
            try store.save(reminder, commit: true)
            notify("Reminder added", [title, due.map { whenText($0, end: false) }].compactMap(\.self).joined(separator: " · "))
        } catch {
            notify("Couldn't add the reminder", error.localizedDescription)
        }
    }
}

/// Adds an event to the default calendar. Asks for add-only Calendar access the first time: Copperlight never reads it.
@MainActor func addEvent(_ title: String, _ when: CaptureDate) {
    Task {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                return notify("Allow Copperlight in Calendars to add events", "Privacy & Security → Calendars")
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.isAllDay = when.allDay
            event.startDate = when.date
            event.endDate = when.date + eventLength(when)
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent, commit: true)
            notify("Event added", "\(title) · \(whenText(when, end: true))")
        } catch {
            notify("Couldn't add the event", error.localizedDescription)
        }
    }
}
