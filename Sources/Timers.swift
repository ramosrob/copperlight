import AppKit
import UserNotifications

enum TimerCommand: Equatable { case start(seconds: Int, label: String), stop }

/// What follows `timer `: a length, then what it's for (`10 min tea`, `90s`, `1h30m`, `1 hour 30 call mom`), from 1
/// second to 24 hours. A bare number is minutes (after hours too); "for" before the label is dropped. Or `stop`, from
/// its first letter, like `pomo s`. nil for anything else.
func parseTimer(_ text: String) -> TimerCommand? {
    var rest = Substring(text.trimmingCharacters(in: .whitespaces))
    if !rest.isEmpty, "stop".hasPrefix(rest.lowercased()) { return .stop }
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

    func start(seconds: Int, label: String) {
        // Ask about notifications now, while you're here, not when the timer ends and you're away.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        if running != nil { stop() }
        running = Running(deadline: .now + Double(seconds), seconds: seconds, label: label)
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
            LauncherResult(id: "timer:stop", title: "Stop Timer", subtitle: [running.label, "\(left ?? "") left"].filter { !$0.isEmpty }
                .joined(separator: " · "), icon: .symbol("stop.fill"), score: 51, actionTitle: "Stop", action: { clock.stop() })
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
        case .stop:
            return [stop ?? LauncherResult(id: "timer:stop", title: "No timer running", icon: .symbol("hourglass"), score: 51,
                                           actionTitle: "", action: {})]
        case nil:
            return [LauncherResult(id: "timer:start", title: "Type a length, like 10 min", subtitle: "timer 10 min tea, 90s, 1h 30m",
                                   icon: .symbol("hourglass"), score: 50, actionTitle: "", action: {})]
        }
    }
}
