import AppKit
import UserNotifications

enum TimerCommand: Equatable { case start(seconds: Int, label: String), until(hour: Int, minute: Int, label: String), stop }

/// What follows `timer `: a length, then what it's for (`10 min tea`, `90s`, `1h30m`, `1 hour 30 call mom`), from 1
/// second to 24 hours. A bare number is minutes (after hours too); "for" before the label is dropped. Or a time of day
/// (`until 15:30 standup`, `at 3pm`, `till 9:05am`). Or `stop`, from its first letter, like `pomo s`. nil for anything else.
func parseTimer(_ text: String) -> TimerCommand? {
    var rest = Substring(text.trimmingCharacters(in: .whitespaces))
    if !rest.isEmpty, "stop".hasPrefix(rest.lowercased()) { return .stop }
    if rest.lowercased().firstMatch(of: #/^(until|till|til|at)\b/#) != nil {
        let time = #/(?:until|till|til|at)\s+(\d{1,2})(?:[:.h](\d{2}))?\s*(am|pm)?(?![\w:])\s*/#.ignoresCase()
        guard let match = rest.prefixMatch(of: time), let hour = Int(match.1) else { return nil }
        let minute = match.2.flatMap { Int($0) } ?? 0
        let half = match.3?.lowercased()
        guard (0...59).contains(minute), half == nil ? (0...23).contains(hour) : (1...12).contains(hour) else { return nil }
        let label = rest[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        return .until(hour: half == nil ? hour : hour % 12 + (half == "pm" ? 12 : 0), minute: minute,
                      label: label.lowercased().hasPrefix("for ") ? String(label.dropFirst(4)) : label)
    }
    var seconds = 0.0, last: Double?
    // A number and its unit, not followed by a letter: "1h30m" is two, "10 minutos" a number of minutes and a label.
    let part = #/(\d+(?:[.,]\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)?(?![a-z])\s*/#.ignoresCase()
    while let match = rest.prefixMatch(of: part), let value = Double(match.1.replacing(",", with: ".")) {
        let unit: Double? = switch match.2?.lowercased().first {
        case "h": 3600
        case "m": 60
        case "s": 1
        default: last == nil || last == 3600 ? 60 : nil // a second bare number is the label's
        }
        guard let unit else { break }
        (seconds, last) = (seconds + value * unit, unit)
        rest = rest[match.range.upperBound...]
    }
    guard (1...86_400).contains(seconds) else { return nil }
    var label = rest.trimmingCharacters(in: .whitespaces)
    if label.lowercased().hasPrefix("for ") { label = String(label.dropFirst(4)) }
    return .start(seconds: Int(seconds.rounded()), label: label)
}

/// The next `hour:minute`: today's, or tomorrow's once it's gone.
func nextTime(hour: Int, minute: Int, after now: Date = .now) -> Date {
    Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime) ?? now
}

/// "1:15", "1:02:03": a stopwatch's time.
func elapsedTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(Int(seconds)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

/// "10 minutes", "1 hour, 30 minutes", "1 minute, 30 seconds".
func timerLength(_ seconds: Int) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
}

/// The timer (`timer 10 min tea`), beside the pomodoro and like it: a deadline kept in state.json, so it survives a
/// restart, counting down in the menu bar (click it to stop), and a notification with a sound when it's done.
/// ponytail: one at a time, like the pomodoro; a new one replaces it, after asking. Several if people need them.
@MainActor final class Countdown: NSObject {
    struct Running: Codable, Equatable {
        var deadline: Date
        var seconds: Int
        var label: String
    }

    private static let stateSection = "timer"
    private let store: StateStore
    private(set) var running: Running?
    private var item: NSStatusItem?
    private var ticker: Timer?

    init(store: StateStore = .shared) { self.store = store }

    /// Picks up a timer from before a restart. One that ran out meanwhile ends right away.
    func restore() {
        running = store.get(Self.stateSection, as: Running.self)
        if running != nil { show() }
    }

    /// `deadline`: a time of day (`timer until 15:30`), `seconds` then only naming its length.
    func start(seconds: Int, label: String, deadline: Date? = nil) {
        // Ask about notifications now, while you're here, not when the timer ends and you're away.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        if running != nil { stop() }
        running = Running(deadline: deadline ?? .now + Double(seconds), seconds: seconds, label: label)
        store.set(Self.stateSection, running)
        show()
    }

    func stop() {
        running = nil
        store.set(Self.stateSection, running)
        ticker?.invalidate()
        ticker = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func show() {
        if item == nil, let running {
            item = countdownItem(symbol: "hourglass", name: "Timer", stop: running.label.isEmpty ? "Stop Timer" : "Stop Timer: \(running.label)",
                                 target: self, action: #selector(stopFromMenu))
        }
        if ticker == nil { ticker = everySecond { [weak self] in self?.tick() } }
        tick()
    }

    private func tick() {
        guard let running else { return }
        let left = remaining(until: running.deadline)
        guard left == 0 else {
            item?.button?.title = " " + countdown(left)
            return
        }
        stop()
        notify("Timer done", ([running.label] + [timerLength(running.seconds)]).filter { !$0.isEmpty }.joined(separator: " · "), sound: true)
    }

    @objc private func stopFromMenu() { stop() }
}

/// `timer 10 min tea`, `timer stop` in the launcher. `tim` offers the Timer chip (Tab), and stopping the one running.
struct TimerProvider: ResultProvider {
    let clock: Countdown
    var modes: [Mode] { [Mode(prefix: "timer ", title: "Timer", icon: .symbol("hourglass"), hint: "10 min tea, 90s, 1h 30m")] }

    func results(for query: String) async -> [LauncherResult] {
        let clock = clock // before the first closure that uses it: Xcode 26 rejects a capture of a later declaration
        let running = await MainActor.run { clock.running }
        let left = running.map { countdown(remaining(until: $0.deadline)) }
        // Scores above apps (they top out at 1.8), like the pomodoro's: typing "timer" means this.
        let stop = running.map { running in
            LauncherResult(id: "timer:stop", title: "Stop Timer", subtitle: [running.label, "ends \(running.deadline.formatted(date: .omitted, time: .shortened))"]
                .filter { !$0.isEmpty }.joined(separator: " · "), icon: .symbol("stop.fill"), score: 51, actionTitle: "Stop", action: { clock.stop() },
                ticking: .down(to: running.deadline))
        }
        if let start = startRow(query, keyword: "timer", title: "Timer", hint: "Type a length: timer 10 min tea", symbol: "hourglass") {
            return [start] + (stop.map { [$0] } ?? [])
        }
        guard query.lowercased().hasPrefix("timer ") else { return [] }
        let text = query.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return stop.map { [$0] } ?? [] }
        switch parseTimer(text) {
        case .start(let seconds, let label):
            let length = timerLength(seconds)
            return [LauncherResult(
                id: "timer:start", title: "Start Timer", subtitle: ([length] + (label.isEmpty ? [] : [label])).joined(separator: " · "),
                icon: .symbol("hourglass"), score: 50, actionTitle: "Start", action: { clock.start(seconds: seconds, label: label) },
                confirm: left.map { "Replace the running timer (\($0) left) with \(length)?" })]
        case .until(let hour, let minute, let label):
            let end = nextTime(hour: hour, minute: minute)
            let seconds = Int((end.timeIntervalSinceNow / 60).rounded(.up)) * 60
            let at = end.formatted(date: .omitted, time: .shortened)
            return [LauncherResult(
                id: "timer:start", title: "Start Timer", subtitle: (["Until \(at)", timerLength(seconds)] + (label.isEmpty ? [] : [label])).joined(separator: " · "),
                icon: .symbol("hourglass"), score: 50, actionTitle: "Start", action: { clock.start(seconds: seconds, label: label, deadline: end) },
                confirm: left.map { "Replace the running timer (\($0) left) with one until \(at)?" })]
        case .stop:
            return [stop ?? LauncherResult(id: "timer:stop", title: "No timer running", icon: .symbol("hourglass"), score: 51,
                                           actionTitle: "", action: {})]
        case nil:
            return [LauncherResult(id: "timer:start", title: "Type a length, like 10 min", subtitle: "timer 10 min tea, 90s, 1h 30m",
                                   icon: .symbol("hourglass"), score: 50, actionTitle: "", action: {})]
        }
    }
}

/// The stopwatch (`stopwatch`): when it started, kept in state.json so it survives a restart, counting up in the menu
/// bar (click it to stop). Stopping says the time in a notification. ponytail: no laps; add them if people ask.
@MainActor final class Stopwatch: NSObject {
    private static let stateSection = "stopwatch"
    private let store: StateStore
    private(set) var started: Date?
    private var item: NSStatusItem?
    private var ticker: Timer?

    init(store: StateStore = .shared) { self.store = store }

    func restore() {
        started = store.get(Self.stateSection, as: Date.self)
        if started != nil { show() }
    }

    func start() {
        guard started == nil else { return }
        started = .now
        store.set(Self.stateSection, started)
        show()
    }

    /// Stops it and returns how long it ran; nil if it wasn't running.
    @discardableResult func stop() -> TimeInterval? {
        guard let started else { return nil }
        self.started = nil
        store.set(Self.stateSection, self.started)
        ticker?.invalidate()
        ticker = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        return Date.now.timeIntervalSince(started)
    }

    /// Stops it and says the time.
    func stopAndSay() {
        if let time = stop() { notify("Stopwatch", elapsedTime(time)) }
    }

    private func show() {
        if item == nil { item = countdownItem(symbol: "stopwatch", name: "Stopwatch", stop: "Stop Stopwatch", target: self, action: #selector(stopFromMenu)) }
        if ticker == nil { ticker = everySecond { [weak self] in self?.tick() } }
        tick()
    }

    private func tick() {
        if let started { item?.button?.title = " " + elapsedTime(Date.now.timeIntervalSince(started)) }
    }

    @objc private func stopFromMenu() { stopAndSay() }
}

/// `stopwatch` (from `stopw`: `stop` stops things) starts it, or stops the one running, its time ticking on the row.
struct StopwatchProvider: ResultProvider {
    let watch: Stopwatch

    func results(for query: String) async -> [LauncherResult] {
        let lower = query.lowercased()
        guard lower.count >= 5, "stopwatch".hasPrefix(lower) else { return [] }
        let watch = watch
        guard let started = await MainActor.run(body: { watch.started }) else {
            return [LauncherResult(id: "stopwatch:start", title: "Start Stopwatch", subtitle: "Counts up in the menu bar",
                                   icon: .symbol("stopwatch"), score: 50, actionTitle: "Start", action: { watch.start() })]
        }
        return [LauncherResult(id: "stopwatch:stop", title: "Stop Stopwatch", subtitle: "Started \(started.formatted(date: .omitted, time: .shortened))",
                               icon: .symbol("stop.fill"), score: 51, actionTitle: "Stop", action: { watch.stopAndSay() }, ticking: .up(from: started))]
    }
}

/// What's running, for the empty launcher: the pomodoro (or break), the timer and the stopwatch, each ticking. Enter
/// stops one after asking, since it's the first key pressed on opening. They come after the first event and before
/// the rest (events score 100, 99.99, …), so a meeting about to start keeps Enter.
@MainActor func runningClocks(pomodoro: Pomodoro, timer: Countdown, stopwatch: Stopwatch,
                              isOn: (Feature) -> Bool = { $0.isOn }) -> [LauncherResult] {
    let at = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    var rows: [LauncherResult] = []
    if isOn(.pomodoro), let running = pomodoro.running {
        rows.append(LauncherResult(
            id: "clock:pomodoro", title: running.title, subtitle: "\(running.minutes) minutes · ends \(at(running.deadline))",
            icon: .symbol(running.isBreak == true ? "cup.and.saucer" : "timer"), score: 99.997, actionTitle: "Stop",
            action: { pomodoro.stop() }, confirm: "Stop the \(running.title.lowercased())?", ticking: .down(to: running.deadline)))
    }
    if isOn(.timers), let running = timer.running {
        rows.append(LauncherResult(
            id: "clock:timer", title: running.label.isEmpty ? "Timer" : running.label,
            subtitle: "\(timerLength(running.seconds)) · ends \(at(running.deadline))", icon: .symbol("hourglass"), score: 99.996,
            actionTitle: "Stop", action: { timer.stop() }, confirm: "Stop the timer?", ticking: .down(to: running.deadline)))
    }
    if isOn(.stopwatch), let started = stopwatch.started {
        rows.append(LauncherResult(
            id: "clock:stopwatch", title: "Stopwatch", subtitle: "Started \(at(started))", icon: .symbol("stopwatch"), score: 99.995,
            actionTitle: "Stop", action: { stopwatch.stopAndSay() }, confirm: "Stop the stopwatch?", ticking: .up(from: started)))
    }
    if isOn(.keepAwake), KeepAwake.isOn { // `:awake`: counting down when it's for a while
        let until = KeepAwake.shared.until
        rows.append(LauncherResult(
            id: "clock:awake", title: "Keeping Awake", subtitle: until.map { "Until \(at($0))" } ?? "Until you stop it", icon: .symbol("sun.max"),
            score: 99.994, actionTitle: "Stop", action: { KeepAwake.shared.stop() }, confirm: "Stop keeping the Mac awake?",
            ticking: until.map { .down(to: $0) }))
    }
    return rows
}
