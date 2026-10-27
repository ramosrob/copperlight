import AppKit

/// An executable in ~/.config/copperlight/scripts/, found by its file name. A comment near the top can set
/// `@title Deploy`, `@icon hammer` (an SF Symbol) and `@output silent|show|copy`. Community script commands'
/// `@raycast.*` headers work too (title, mode, an SF Symbol icon, needsConfirmation, description, argument1…), so
/// those scripts run as they are; where both are set, Copperlight's own headers win.
struct Script: Equatable {
    enum Output: String { case silent, show, copy }
    let path: String
    let name: String // the file name without its extension: what you type
    var title: String
    var icon = "terminal"
    var output = Output.silent
    var subtitle: String? // its description; the script's path otherwise
    var needsConfirmation = false
    var argumentCount: Int? // the arguments it declares; nil: each word typed after its name is one
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
        var own: [String: String] = [:], community: [String: String] = [:]
        for line in head {
            if let match = line.firstMatch(of: #/@raycast\.(\w+)[ \t]+(.+)$/#) {
                community[String(match.1)] = match.2.trimmingCharacters(in: .whitespaces)
            } else if let match = line.firstMatch(of: #/@(title|icon|output)[ \t]+(.+)$/#) {
                own[String(match.1)] = match.2.trimmingCharacters(in: .whitespaces)
            }
        }
        // A community icon is often an emoji or an image file; only an SF Symbol name can be a row's icon.
        let communityIcon = community["icon"].flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil }
        let communityOutput: Script.Output? = switch community["mode"] {
        case "fullOutput", "inline": .show
        case "silent", "compact": .silent
        default: nil
        }
        script.title = own["title"] ?? community["title"] ?? name
        script.icon = own["icon"] ?? communityIcon ?? script.icon
        script.output = own["output"].map { Script.Output(rawValue: $0.lowercased()) ?? .silent } ?? communityOutput ?? .silent
        script.subtitle = community["description"]
        script.needsConfirmation = community["needsConfirmation"] == "true"
        let declared = (1...3).filter { community["argument\($0)"] != nil }.count
        script.argumentCount = declared > 0 ? declared : nil
        return script
    }
}

/// What a script gets for the words typed after its name: each word, or, when it declares how many arguments it
/// takes, that many, the last one holding the rest of the text ("ask will it ship" → "will it ship").
func scriptArguments(_ words: [String], declared: Int?) -> [String] {
    guard let declared, declared > 0, words.count > declared else { return words }
    return Array(words.prefix(declared - 1)) + [words.dropFirst(declared - 1).joined(separator: " ")]
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
                let words = query[range.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
                let arguments = scriptArguments(words, declared: script.argumentCount)
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
        let shown = script.subtitle ?? (script.path as NSString).abbreviatingWithTildeInPath
        var result = outputRow(script, line: line, id: id, title: title, subtitle: shown, score: score)
        if script.needsConfirmation { result.confirm = "Run \(script.title)?" }
        return result
    }

    /// The row for its output mode: run in the background, show what it prints, or copy it.
    private func outputRow(_ script: Script, line: String, id: String, title: String, subtitle shown: String, score: Double) -> LauncherResult {
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
