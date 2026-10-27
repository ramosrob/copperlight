import AppKit
import UserNotifications

enum PomodoroCommand: Equatable { case start(minutes: Int), startBreak(minutes: Int), stop }

/// What `pomo …` in the launcher offers. The first word is any start of "pomodoro" from 3 letters:
/// alone it offers starting the default length, a break, and stopping; "pomo 50" starts 50 minutes;
/// "pomo b…" through "pomo break" starts a break, "pomo break 10" a 10-minute one; "pomo s…" through "pomo stop"
/// stops. Lengths outside 1…240 minutes offer nothing.
func parsePomodoro(_ query: String, defaultMinutes: Int, breakMinutes: Int = 5) -> [PomodoroCommand] {
    let words = query.lowercased().split(whereSeparator: \.isWhitespace)
    guard let first = words.first, first.count >= 3, "pomodoro".hasPrefix(first) else { return [] }
    let length = { (word: Substring) in Int(word).flatMap { (1...240).contains($0) ? $0 : nil } }
    switch words.count {
    case 1:
        return [.start(minutes: defaultMinutes), .startBreak(minutes: breakMinutes), .stop]
    case 2:
        if Int(words[1]) != nil { return length(words[1]).map { [.start(minutes: $0)] } ?? [] }
        if "break".hasPrefix(words[1]) { return [.startBreak(minutes: breakMinutes)] }
        return "stop".hasPrefix(words[1]) ? [.stop] : []
    case 3 where words[1] == "break":
        return length(words[2]).map { [.startBreak(minutes: $0)] } ?? []
    default:
        return []
    }
}

/// Seconds until `deadline`, never negative.
func remaining(until deadline: Date, now: Date = .now) -> TimeInterval {
    max(0, deadline.timeIntervalSince(now))
}

/// "24:59". Rounds up, so a fresh 25-minute timer shows 25:00 and the last second shows 00:01.
func countdown(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// The one pomodoro timer. It's a deadline, not a tick count, so sleep doesn't skew it, and the
/// deadline is kept in state.json so a running timer survives a restart. While it runs, a menu
/// bar item counts down (click it to stop); when idle that item is removed, not left as an icon.
@MainActor final class Pomodoro: NSObject {
    struct Running: Codable, Equatable {
        var deadline: Date
        var minutes: Int
        var isBreak: Bool? = nil // nil in state.json from before breaks: a pomodoro

        var title: String { isBreak == true ? "Break" : "Pomodoro" }
    }

    private static let stateSection = "pomodoro"
    var defaultMinutes = 25 // [pomodoro] default_minutes
    var breakMinutes = 5 // [pomodoro] break_minutes
    private(set) var running: Running?
    private var item: NSStatusItem?
    private var timer: Timer?

    /// Picks up a timer from before a restart. One that ran out meanwhile ends right away.
    func restore() {
        running = StateStore.shared.get(Self.stateSection, as: Running.self)
        if running != nil { show() }
    }

    func start(minutes: Int, isBreak: Bool = false) {
        // Ask about notifications now, while you're here, not when the timer ends and you're away.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        if running != nil { stop() } // a break replacing a pomodoro gets its own icon and menu
        running = Running(deadline: .now + Double(minutes) * 60, minutes: minutes, isBreak: isBreak ? true : nil)
        StateStore.shared.set(Self.stateSection, running)
        show()
    }

    func stop() {
        running = nil
        StateStore.shared.set(Self.stateSection, running)
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func show() {
        if item == nil, let running {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: running.isBreak == true ? "cup.and.saucer" : "timer",
                                         accessibilityDescription: running.title)
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let menu = NSMenu()
            menu.addItem(withTitle: "Stop \(running.title)", action: #selector(stopFromMenu), keyEquivalent: "").target = self
            item.menu = menu
            self.item = item
        }
        if timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common) // keeps counting while a menu is open
            self.timer = timer
        }
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
        if running.isBreak == true {
            notify("Break's over", "\(running.minutes) minutes are up.", sound: true)
        } else {
            notify("Pomodoro done", "\(running.minutes) minutes are up. Time for a break: pomo break", sound: true)
        }
    }

    @objc private func stopFromMenu() { stop() }
}

/// `pomo`, `pomo 50`, `pomo stop` in the launcher.
struct PomodoroProvider: ResultProvider {
    let pomodoro: Pomodoro

    func results(for query: String) async -> [LauncherResult] {
        let pomodoro = pomodoro // before the first closure that uses it: Xcode 26 rejects a capture of a later declaration
        let (running, defaultMinutes, breakMinutes) = await MainActor.run { (pomodoro.running, pomodoro.defaultMinutes, pomodoro.breakMinutes) }
        // "timer" (another name) is "pomo".
        let commands = parsePomodoro(otherNameScore(query, "Pomodoro") != nil ? "pomo" : query, defaultMinutes: defaultMinutes, breakMinutes: breakMinutes)
        let left = running.map { countdown(remaining(until: $0.deadline)) }
        // Scores above apps (they top out at 1.8): typing "pomo" means this.
        return commands.compactMap { command in
            switch command {
            case .start(let minutes):
                return LauncherResult(
                    id: "pomodoro:start", title: "Start Pomodoro", subtitle: "\(minutes) minutes",
                    icon: .symbol("timer"), score: 50, actionTitle: "Start", action: { pomodoro.start(minutes: minutes) },
                    confirm: left.map { "Replace the running \(running!.title.lowercased()) (\($0) left) with \(minutes) minutes?" })
            case .startBreak(let minutes):
                return LauncherResult(
                    id: "pomodoro:break", title: "Take a Break", subtitle: "\(minutes) minutes",
                    icon: .symbol("cup.and.saucer"), score: 50, actionTitle: "Start", action: { pomodoro.start(minutes: minutes, isBreak: true) },
                    confirm: left.map { "Replace the running \(running!.title.lowercased()) (\($0) left) with a \(minutes)-minute break?" })
            case .stop:
                if let left, let running {
                    return LauncherResult(
                        id: "pomodoro:stop", title: "Stop \(running.title)", subtitle: "\(left) left",
                        icon: .symbol("stop.fill"), score: 51, actionTitle: "Stop", action: { pomodoro.stop() })
                }
                // "pomo stop" with nothing running says so; plain "pomo" just offers to start.
                return commands.count > 1 ? nil : LauncherResult(
                    id: "pomodoro:stop", title: "No pomodoro running",
                    icon: .symbol("timer"), score: 51, actionTitle: "", action: {})
            }
        }
    }
}
