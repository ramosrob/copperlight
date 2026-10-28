import Foundation

/// `:!git status`: runs the line in a login shell on Enter, never while typing, and shows what it printed in
/// place of the list (Enter copies it). `:!` alone lists lines run before, most used first.
struct ShellProvider: ResultProvider {
    static let prefix = ":!"
    /// The lines run before are the launcher's frecency entries ("shell:<line>"): no history file of their own.
    let state: StateStore
    var modes: [Mode] { [Mode(prefix: Self.prefix, title: "Shell", icon: .symbol("terminal"), hint: "A shell line: git status")] }

    func results(for query: String) async -> [LauncherResult] {
        let line = query.dropFirst(Self.prefix.count).trimmingCharacters(in: .whitespaces)
        let now = Date.now
        let recent = (await state.get(Frecency.stateSection, as: Frecency.Table.self) ?? [:])
            .filter { $0.key.hasPrefix("shell:") }
            .sorted { $0.value.decayed(at: now) > $1.value.decayed(at: now) }
            .map { String($0.key.dropFirst(6)) }
        guard !line.isEmpty else {
            if recent.isEmpty {
                return [LauncherResult(id: "shell:hint", title: "Type a shell line", subtitle: ":!git status · runs on Enter",
                                       icon: .symbol("terminal"), score: 0, actionTitle: "", action: {})]
            }
            return recent.prefix(20).enumerated().map { row($1, score: -0.01 * Double($0)) }
        }
        let earlier = recent.filter { $0 != line }.compactMap { old in fuzzyScore(line, old).map { row(old, score: $0) } }
        return [row(line, score: 100)] + earlier
    }

    private func row(_ line: String, score: Double) -> LauncherResult {
        LauncherResult(id: "shell:\(line)", title: line, subtitle: "zsh", icon: .symbol("terminal"),
                       score: score, actionTitle: "Run", action: {}, output: { await shellOutputRow(line, progress: $0) })
    }
}

/// The finished line: its output in the preview pane, and Enter copies it. While it runs, `progress` gets the same
/// row with the output so far. A script passes its own row's id and title, so its runs don't count as `:!` lines.
func shellOutputRow(_ line: String, id: String? = nil, title: String? = nil,
                    progress: (@Sendable (LauncherResult) async -> Void)? = nil) async -> LauncherResult {
    let row = { @Sendable (output: String, subtitle: String, done: Bool) in
        // ponytail: the preview shows the first 20k characters (SwiftUI Text crawls on more); Enter copies it all.
        // While it runs, Enter hides the panel and lets it finish.
        LauncherResult(id: id ?? "shell:\(line)", title: title ?? line, subtitle: subtitle, icon: .symbol("terminal"), score: .infinity,
                       actionTitle: !done ? "Hide" : output.isEmpty ? "" : "Copy", action: { if done, !output.isEmpty { copyToClipboard(output) } },
                       preview: output.isEmpty ? "No output" : output.count > 20_000 ? String(output.prefix(20_000)) + "\n…" : output)
    }
    let run = await runShell(line, progress: progress.map { progress in
        { @Sendable soFar in await progress(row(soFar, "Running… Esc stops it", false)) }
    })
    let status = run.timedOut ? "stopped after \(Int(shellTimeout)) s" : run.status == 0 ? "done" : "exit \(run.status)"
    return row(run.output, "\(status) · \(formatNumber(run.seconds, decimals: 1...1)) s", true)
}

let shellTimeout: TimeInterval = 30
/// On every shell line's PATH (after the system folders: path_helper reorders it at login), so `:!deploy staging` finds ~/.config/copperlight/scripts/deploy.
let scriptsDir = configDir.appending(path: "scripts")

/// Runs `line` with `zsh -lc` in the home folder. stdout and stderr come back interleaved, as a terminal
/// shows them, without color codes (`errors: false` drops stderr). After `timeout` seconds it's stopped, and
/// cancelling the calling task (Esc) stops it too. `progress` gets the output so far while it runs.
func runShell(_ line: String, errors: Bool = true, timeout: TimeInterval = shellTimeout,
              progress: (@Sendable (String) async -> Void)? = nil) async -> (output: String, status: Int32, timedOut: Bool, seconds: Double) {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = scriptsDir.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
    let clean = { @Sendable (text: String) in
        text.replacing(#/\u{1B}\[[0-9;?]*[A-Za-z]/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let start = Date.now
    // ponytail: SIGTERM to zsh only; a child it forked (rather than exec'd) can outlive it.
    let run = await runTool(URL(filePath: "/bin/zsh"), ["-lc", line], mergeErrors: errors, environment: environment, timeout: timeout,
                            progress: progress.map { progress in { @Sendable text in await progress(clean(text)) } })
    return (clean(run.output), run.status, run.timedOut, Date.now.timeIntervalSince(start))
}
