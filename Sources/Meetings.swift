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

/// `meetings` (from 3 letters): the rest of today's events from Calendar, all-day ones aside, soonest first.
/// Enter joins a video call (Meet, Zoom, Teams, Webex), opening web links where `[browser]` says; otherwise it
/// opens Calendar. Reading events needs full Calendars access, asked for from a row, not while typing.
actor MeetingsProvider: ResultProvider {
    private var store: EKEventStore? // made once access is granted: one made before it sees no events
    private var browser = Config.Browser()

    func setBrowser(_ browser: Config.Browser) { self.browser = browser }

    func results(for query: String) async -> [LauncherResult] {
        guard query.count >= 3, "meetings".hasPrefix(query.lowercased()) else { return [] }
        let row = { (title: String, subtitle: String, actionTitle: String, action: @escaping @MainActor @Sendable () -> Void) in
            LauncherResult(id: "builtin:meetings", title: title, subtitle: subtitle, icon: .symbol("calendar"), score: 50,
                           actionTitle: actionTitle, action: action)
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: break
        case .denied, .restricted:
            return [row("Allow Copperlight to see your calendars", "Privacy & Security → Calendars → Copperlight: Full Access", "Open System Settings", {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            })]
        default: // not asked yet, or add-only (for `add event`)
            return [row("See Today's Meetings", "Asks to read your calendars, once", "Allow", {
                Task {
                    guard (try? await EKEventStore().requestFullAccessToEvents()) == true else { return notify("Copperlight can't see your calendars") }
                    notify("Type “meetings” again to see them")
                }
            })]
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        let now = Date.now, endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return [row("No more meetings today", "", "Open Calendar", openCalendar)] }
        let hours = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        return events.enumerated().map { index, event in
            let link = joinLink(in: [event.url?.absoluteString, event.location, event.notes])
            let open = link.map { webOpener($0, browser: browser) } ?? openCalendar
            return LauncherResult(
                id: "meeting:\(event.eventIdentifier ?? "\(index)")", title: event.title ?? "Untitled",
                subtitle: "\(hours(event.startDate))–\(hours(event.endDate)) · \(startsIn(event.startDate, end: event.endDate, now: now))",
                icon: .symbol(link == nil ? "calendar" : "video"), score: 50 - Double(index) / 100,
                actionTitle: link == nil ? "Open Calendar" : "Join", action: open)
        }
    }
}

@MainActor private func openCalendar() {
    NSWorkspace.shared.openApplication(at: URL(filePath: "/System/Applications/Calendar.app"), configuration: .init())
}
