import AppKit
import EventKit

/// A reminder with a due date, as the launcher shows it.
struct ReminderItem: Equatable, Sendable {
    var id: String
    var title: String
    var due: Date
    var allDay: Bool // due on a day, with no time
    var list: String
}

extension ReminderItem {
    init?(_ reminder: EKReminder) {
        guard let parts = reminder.dueDateComponents, let due = Calendar.current.date(from: parts) else { return nil }
        self.init(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled", due: due, allDay: parts.hour == nil,
                  list: reminder.calendar?.title ?? "")
    }
}

/// When it has to be done by: its time, or the end of its day.
private func deadline(_ item: ReminderItem, calendar: Calendar) -> Date {
    item.allDay ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: item.due))! : item.due
}

/// What the empty launcher shows: overdue, due within the hour, or due today with no time; the soonest deadline first.
func dueNow(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
    items.filter { deadline($0, calendar: calendar) <= now + 3600 || ($0.allDay && calendar.isDate($0.due, inSameDayAs: now)) }
        .sorted { deadline($0, calendar: calendar) < deadline($1, calendar: calendar) }
}

/// The copper badge: "Overdue", "in 20 min", or "Today" for a day's reminder.
func reminderBadge(_ item: ReminderItem, now: Date, calendar: Calendar = .current) -> String {
    let end = deadline(item, calendar: calendar)
    if end <= now { return "Overdue" }
    return item.allDay ? "Today" : startsIn(item.due, end: end, now: now)
}

/// Incomplete reminders due by the end of today, with full Reminders access (`add todo` asks for it); nil without it.
/// Never asks.
func fetchDueReminders() async -> [ReminderItem]? {
    guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
    // ponytail: a new store per look, when the launcher opens; keep one if that ever shows.
    let store = EKEventStore()
    let end = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    return await withCheckedContinuation { done in
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)) {
            done.resume(returning: ($0 ?? []).compactMap(ReminderItem.init))
        }
    }
}

@MainActor private func complete(_ id: String) {
    let store = EKEventStore()
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
    reminder.isCompleted = true
    do { try store.save(reminder, commit: true) } catch { notify("Couldn't complete the reminder", error.localizedDescription) }
}

/// Reminders that are due: the empty launcher shows what's overdue, due within the hour or due today with no time,
/// below a meeting about to start and what's running; `due` (or `overdue`, `todos`) lists the rest of today's too.
/// Enter completes one and keeps the launcher open for the next. Reading them needs full Reminders access, which
/// `add todo` asks for, or the row `due` shows; opening the launcher never asks.
struct RemindersProvider: ResultProvider {
    var calendar = Calendar.current
    var fetch: @Sendable () async -> [ReminderItem]? = fetchDueReminders

    private func row(_ item: ReminderItem, score: Double, now: Date) -> LauncherResult {
        let when = item.allDay ? (calendar.isDate(item.due, inSameDayAs: now) ? "Today" : item.due.formatted(.dateTime.weekday().day().month()))
            : calendar.isDate(item.due, inSameDayAs: now) ? item.due.formatted(date: .omitted, time: .shortened)
            : item.due.formatted(.dateTime.weekday().day().month().hour().minute())
        let id = item.id
        return LauncherResult(id: "reminder:\(id)", title: item.title, subtitle: [item.list, when].filter { !$0.isEmpty }.joined(separator: " · "),
                              icon: .symbol("checklist"), score: score, actionTitle: "Complete", action: { complete(id) }, staysOpen: true,
                              badge: reminderBadge(item, now: now, calendar: calendar))
    }

    /// For the empty launcher. Nothing without access.
    func upNext(now: Date = .now) async -> [LauncherResult] {
        dueNow(await fetch() ?? [], now: now, calendar: calendar).enumerated().map { row($1, score: 99.5 - Double($0) / 100, now: now) }
    }

    func results(for query: String) async -> [LauncherResult] { await results(for: query, now: .now) }

    func results(for query: String, now: Date) async -> [LauncherResult] {
        guard ["due", "overdue", "todos"].contains(query.lowercased().trimmingCharacters(in: .whitespaces)) else { return [] }
        guard let items = await fetch() else {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return [status == .denied || status == .restricted
                ? LauncherResult(id: "builtin:due", title: "Allow Copperlight to see your reminders", subtitle: "Privacy & Security → Reminders",
                                 icon: .symbol("checklist"), score: 50, actionTitle: "Open System Settings", action: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                })
                : LauncherResult(id: "builtin:due", title: "See Due Reminders", subtitle: "Asks to read your reminders, once", icon: .symbol("checklist"),
                                 score: 50, actionTitle: "Allow", action: {
                    Task {
                        guard (try? await EKEventStore().requestFullAccessToReminders()) == true else { return notify("Copperlight can't see your reminders") }
                        notify("Type “due” again to see them")
                    }
                })]
        }
        let due = items.sorted { deadline($0, calendar: calendar) < deadline($1, calendar: calendar) }
        guard !due.isEmpty else {
            return [LauncherResult(id: "builtin:due", title: "Nothing due today", icon: .symbol("checklist"), score: 50, actionTitle: "", action: {})]
        }
        return due.enumerated().map { row($1, score: 50 - Double($0) / 100, now: now) }
    }
}
