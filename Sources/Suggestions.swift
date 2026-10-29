import AppKit

/// An app opened from the launcher, and when: what the empty launcher's suggestions learn from. Kept in state.json,
/// the last 500.
struct AppOpen: Codable, Equatable, Sendable {
    static let stateSection = "opened"
    static let limit = 500
    var app: String // its path, the id of its row
    var at: Date
}

/// The apps you open around this time of day: opened from the launcher within an hour of it on 3 days or more of the
/// last 4 weeks, the most often first (a recent day counting more). Up to `count`.
func suggestedApps(_ opens: [AppOpen], now: Date, calendar: Calendar = .current, count: Int = 3) -> [String] {
    let minute = { (date: Date) in calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
    let current = minute(now)
    var weight: [String: Double] = [:], days: [String: Set<Date>] = [:]
    for open in opens where open.at <= now && now.timeIntervalSince(open.at) < 28 * 86_400 {
        let apart = abs(minute(open.at) - current)
        guard min(apart, 24 * 60 - apart) <= 60 else { continue } // 23:50 is 20 minutes before 00:10
        weight[open.app, default: 0] += pow(0.5, now.timeIntervalSince(open.at) / (14 * 86_400))
        days[open.app, default: []].insert(calendar.startOfDay(for: open.at))
    }
    return weight.filter { days[$0.key, default: []].count >= 3 }.sorted { $0.value > $1.value }.prefix(count).map(\.key)
}

/// The empty launcher's suggestions, below a meeting about to start and what's running: the apps you open around
/// now, but the one in front (you're in it) and any that's gone. Enter opens it, like its row in a search.
@MainActor func suggestionRows(_ opens: [AppOpen], now: Date = .now, calendar: Calendar = .current,
                               front: String? = NSWorkspace.shared.frontmostApplication?.bundleURL?.path) -> [LauncherResult] {
    suggestedApps(opens.filter { $0.app != front }, now: now, calendar: calendar).filter { FileManager.default.fileExists(atPath: $0) }
        .enumerated().map { index, path in
            LauncherResult(id: path, title: FileManager.default.displayName(atPath: path).replacing(#/\.app$/#, with: ""),
                           subtitle: "Often around this time", icon: .file(path), score: 50 - Double(index) / 100,
                           action: { NSWorkspace.shared.openApplication(at: URL(filePath: path), configuration: .init()) })
        }
}
