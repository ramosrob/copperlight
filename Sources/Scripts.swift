import AppKit

/// An executable in ~/.config/copperlight/scripts/, found by its file name. A comment near the top can set
/// `@title Deploy`, `@icon hammer` (an SF Symbol) and `@output silent|show|copy`.
struct Script: Equatable {
    enum Output: String { case silent, show, copy }
    let path: String
    let name: String // the file name without its extension: what you type
    var title: String
    var icon = "terminal"
    var output = Output.silent
}

/// The scripts in `folder`: executable files, not hidden ones. Their headers are read from the first 30 lines.
func scripts(in folder: URL) -> [Script] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.sorted().compactMap { file in
        let path = folder.appending(path: file).path
        guard !file.hasPrefix("."), FileManager.default.isExecutableFile(atPath: path), !isBrowsableFolder(path) else { return nil }
        let name = (file as NSString).deletingPathExtension
        var script = Script(path: path, name: name, title: name)
        let head = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n", maxSplits: 30).prefix(30) ?? []
        for line in head {
            guard let match = line.firstMatch(of: #/@(title|icon|output)[ \t]+(.+)$/#) else { continue }
            let value = match.2.trimmingCharacters(in: .whitespaces)
            switch match.1 {
            case "title": script.title = value
            case "icon": script.icon = value
            default: script.output = Script.Output(rawValue: value.lowercased()) ?? .silent
            }
        }
        return script
    }
}

/// `value` as one shell word, whatever it holds.
func shellQuoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }

/// Scripts as launcher rows. Typed by name, with text after it as arguments (`deploy staging`), one ranks first;
/// otherwise its name or title matches loosely, like a command. Ids are `script:<name>`, so one named like a
/// built-in replaces it.
struct ScriptProvider: ResultProvider {
    var folder = scriptsDir

    func results(for query: String) -> [LauncherResult] {
        // ponytail: lists the folder and reads each script's head on every keystroke; fine for dozens of scripts.
        scripts(in: folder).compactMap { script in
            if let range = query.range(of: script.name + " ", options: [.caseInsensitive, .anchored]) {
                let arguments = query[range.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
                return row(script, arguments: arguments, score: 100)
            }
            let score = [aliasScore(query, script.name), fuzzyScore(query, script.title).map { $0 + 0.5 }].compactMap { $0 }.max()
            return score.map { row(script, arguments: [], score: $0) }
        }
    }

    private func row(_ script: Script, arguments: [String], score: Double) -> LauncherResult {
        // Through a login shell, so the script gets the PATH a terminal would (Homebrew, ~/.zprofile).
        let line = ([script.path] + arguments).map(shellQuoted).joined(separator: " ")
        let id = "script:\(script.name)", title = ([script.title] + arguments).joined(separator: " ")
        let shown = (script.path as NSString).abbreviatingWithTildeInPath
        switch script.output {
        case .silent:
            return LauncherResult(id: id, title: title, subtitle: shown, icon: .symbol(script.icon), score: score, actionTitle: "Run",
                                  action: { runDetached("/bin/zsh", ["-lc", line], label: script.title) })
        case .show:
            return LauncherResult(id: id, title: title, subtitle: shown, icon: .symbol(script.icon), score: score, actionTitle: "Run",
                                  action: {}, output: { await shellOutputRow(line, id: id, title: title, progress: $0) })
        case .copy:
            return LauncherResult(id: id, title: title, subtitle: shown, icon: .symbol(script.icon), score: score,
                                  actionTitle: "Run and Copy", action: {
                Task {
                    let run = await runShell(line, errors: false)
                    guard run.status == 0, !run.timedOut else { return notify("\(script.title) failed", run.timedOut ? "stopped after \(Int(shellTimeout)) s" : "exit \(run.status)") }
                    copyToClipboard(run.output)
                    notify("Copied", "\(script.title): \(run.output.prefix(80))")
                }
            })
        }
    }
}
