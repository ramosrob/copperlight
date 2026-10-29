import AppKit

/// An executable in ~/.config/copperlight/scripts/, found by its file name. A comment near the top can set
/// `@title Deploy`, `@icon hammer` (an SF Symbol) and `@output silent|show|copy|rows` (rows: a script filter, below). Community script commands'
/// `@raycast.*` headers work too (title, mode, an SF Symbol icon, needsConfirmation, description, argument1…), so
/// those scripts run as they are; where both are set, Copperlight's own headers win.
struct Script: Equatable {
    enum Output: String { case silent, show, copy, rows }
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

/// A script filter's output: a row a line, its title, then after tabs a subtitle and the value Enter uses (the title
/// without one). Blank lines are skipped; the first 100 rows are kept.
func scriptRows(_ output: String) -> [(title: String, subtitle: String, value: String)] {
    output.split(whereSeparator: \.isNewline).prefix(100).compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !fields[0].isEmpty else { return nil }
        return (fields[0], fields.count > 1 ? fields[1] : "", fields.count > 2 && !fields[2].isEmpty ? fields[2] : fields[0])
    }
}

/// What Enter does with a script filter's row: a file or folder (`/…`, `~/…`) opens, so does a link an app takes
/// (`https://…`, `obsidian://…`); anything else is copied.
private func scriptRowAction(_ value: String) -> (title: String, run: @MainActor @Sendable () -> Void) {
    let path = (value as NSString).expandingTildeInPath
    if value.hasPrefix("/") || value.hasPrefix("~/"), FileManager.default.fileExists(atPath: path) {
        return ("Open", { NSWorkspace.shared.open(URL(filePath: path)) })
    }
    if value.wholeMatch(of: #/[a-zA-Z][a-zA-Z0-9+.-]*:\S+/#) != nil, let url = URL(string: value),
       NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
        return ("Open", { NSWorkspace.shared.open(url) })
    }
    return ("Copy", { copyToClipboard(value) })
}

/// Scripts as launcher rows. Typed by name, with text after it as arguments (`deploy staging`), one ranks first;
/// otherwise its name or title matches loosely, like a command. Ids are `script:<name>`, so one named like a
/// built-in replaces it. A script filter (`@output rows`) lists what it prints instead: its name is a chip (Tab),
/// and the script runs with what's typed after it as its one argument, once typing pauses, its rows replacing the
/// list.
struct ScriptProvider: ResultProvider {
    var folder = scriptsDir

    var modes: [Mode] {
        scripts(in: folder).filter { $0.output == .rows }.map { script in
            Mode(prefix: script.name.lowercased() + " ", title: script.title, icon: .symbol(script.icon), hint: script.subtitle ?? "Type to filter")
        }
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        guard let script = scripts(in: folder).first(where: { $0.output == .rows && (query.lowercased() + " ").hasPrefix($0.name.lowercased() + " ") })
        else { return [] }
        return await filterRows(script, text: query.dropFirst(script.name.count).trimmingCharacters(in: .whitespaces))
    }

    /// Runs a script filter with `text` once typing pauses (a keystroke in the meantime cancels it, stopping the
    /// script), and lists what it prints, in its order.
    private func filterRows(_ script: Script, text: String) async -> [LauncherResult] {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return [] }
        let run = await runShell(([script.path, text]).map(shellQuoted).joined(separator: " "), errors: false)
        guard !Task.isCancelled else { return [] }
        let note = { (title: String, subtitle: String) in
            [LauncherResult(id: "script:\(script.name):note", title: title, subtitle: subtitle, icon: .symbol(script.icon), score: 100,
                            actionTitle: "", action: {})]
        }
        guard run.status == 0, !run.timedOut else {
            return note("\(script.title) failed", run.timedOut ? "Stopped after \(Int(shellTimeout)) s" : "Exit \(run.status)")
        }
        let rows = scriptRows(run.output)
        guard !rows.isEmpty else { return note("Nothing for “\(text)”", script.title) }
        return rows.enumerated().map { index, row in
            let action = scriptRowAction(row.value)
            return LauncherResult(id: "script:\(script.name):\(row.value)", title: row.title, subtitle: row.subtitle, icon: .symbol(script.icon),
                                  score: 100 - Double(index) / 1000, actionTitle: action.title, action: action.run)
        }
    }

    func results(for query: String) async -> [LauncherResult] {
        // ponytail: lists the folder and reads each script's head on every keystroke; fine for dozens of scripts.
        var rows: [LauncherResult] = []
        for script in scripts(in: folder) {
            if let range = query.range(of: script.name + " ", options: [.caseInsensitive, .anchored]) {
                if script.output == .rows {
                    rows += await filterRows(script, text: query[range.upperBound...].trimmingCharacters(in: .whitespaces))
                    continue
                }
                let words = query[range.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
                let arguments = scriptArguments(words, declared: script.argumentCount)
                rows.append(row(script, arguments: arguments, score: 100))
                continue
            }
            let score = [aliasScore(query, script.name), fuzzyScore(query, script.title).map { $0 + 0.5 }].compactMap { $0 }.max()
            if let score { rows.append(row(script, arguments: [], score: score)) }
        }
        return rows
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
        case .rows: // its chip, where it lists what it prints
            return LauncherResult(id: id, title: title, subtitle: shown, icon: .symbol(script.icon), score: score, actionTitle: "List",
                                  action: {}, completion: script.name + " ")
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
