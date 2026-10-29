import AppKit

/// Fuzzy subsequence match, case- and diacritic-insensitive; spaces in the query are ignored.
/// Returns nil when there's no match, about 1 for a prefix or word-initials match, less for
/// scattered matches. Shorter texts win ties. Picks the best alignment, not the first one, so
/// "vsc" hits the word starts in "Visual Studio Code".
func fuzzyScore(_ query: String, _ text: String) -> Double? {
    let fold = { (c: Character) in String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let q = query.filter { $0 != " " }.map(fold)
    let t = Array(text), folded = t.map(fold)
    guard !q.isEmpty, q.count <= t.count else { return nil }

    func isWordStart(_ j: Int) -> Bool {
        j == 0 || !(t[j - 1].isLetter || t[j - 1].isNumber) || (t[j].isUppercase && t[j - 1].isLowercase)
    }
    // Per matched char: 1, +3 at a word start, else +2 if it follows the previous match; -1 per gap.
    // best[j] = best score so far with the current query char matched at text position j.
    var best = [Double](repeating: -.infinity, count: t.count)
    for i in q.indices {
        var next = [Double](repeating: -.infinity, count: t.count)
        var bestBeforeGap = -Double.infinity // max of best[k] for k < j - 1
        for j in i..<t.count {
            if j >= 2 { bestBeforeGap = max(bestBeforeGap, best[j - 2]) }
            guard folded[j] == q[i] else { continue }
            let wordStart = isWordStart(j) ? 3.0 : 0
            next[j] = i == 0 ? 1 + wordStart : max(best[j - 1] + 1 + max(wordStart, 2), bestBeforeGap + wordStart)
        }
        best = next
    }
    guard let score = best.max(), score > -.infinity else { return nil }
    let perfect = 4 + 3 * Double(q.count - 1)
    return score / perfect - 0.001 * Double(t.count - q.count)
}

actor AppProvider: ResultProvider {
    private struct App { let name: String, path: String, running: Bool }
    private var apps: [App] = []
    private var names: [String: String] = [:] // path → Finder display name, cached across rescans
    /// What each app is for (AppIndex), by path: found by what it does when its name doesn't match.
    private var infos: [String: AppInfo] = [:]
    private let index: AppIndex?
    private var online = true
    private let brew: String?
    /// Homebrew's apps, to install one you don't have: with Homebrew there and `[apps] online` on.
    private var casks: [(token: String, name: String, desc: String, key: String)] = []
    private var loadingCasks = false

    /// `index` nil: names only (tests, which mustn't go online or write apps.json).
    init(index: AppIndex? = AppIndex(), brew: String? = brewPath) {
        self.index = index
        self.brew = brew
    }

    func setOnline(_ online: Bool) { self.online = online }
    func setInfos(_ infos: [String: AppInfo]) { self.infos = infos }
    func setCasks(_ list: [String: HomebrewApp]) {
        var seen = Set<String>()
        casks = list.values.compactMap { app in
            guard let token = app.token, let name = app.name, seen.insert(token).inserted else { return nil }
            return (token, name, app.desc, name.lowercased())
        }
        loadingCasks = false
    }

    /// Re-lists the app folders (and one level of subfolders like Utilities). Only names of
    /// newly seen bundles are looked up, so this stays cheap enough to run on every panel open.
    func rescan() async {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                let path = dir + "/" + entry
                if entry.hasSuffix(".app") {
                    paths.append(path)
                } else if let children = try? fm.contentsOfDirectory(atPath: path) {
                    paths += children.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                }
            }
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap {
            $0.activationPolicy == .regular ? $0.bundleURL?.path : nil
        })
        var seen = Set<String>()
        apps = (paths + running).compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            let name = names[path] ?? fm.displayName(atPath: path)
            names[path] = name
            return App(name: name, path: path, running: running.contains(path))
        }
        guard let index else { return }
        if casks.isEmpty, !loadingCasks, online, brew != nil { // once; offline, the next open tries again
            loadingCasks = true
            Task.detached(priority: .utility) { [self] in await setCasks(await homebrewDescriptions()) }
        }
        if infos.isEmpty { infos = await index.infos }
        // In the background: new and updated apps are read, looked up and described, then searched by what they do.
        let (listed, online) = (apps.map { (path: $0.path, name: $0.name) }, online)
        Task.detached(priority: .utility) { [self] in
            await index.update(listed, online: online) { await self.setInfos($0) }
        }
    }

    /// Every match: the launcher adds frecency (the id is the path) and sorts, so cutting here could drop a favorite.
    func results(for query: String) -> [LauncherResult] {
        let installed: [LauncherResult] = apps.compactMap { app in
            // By what it does, the matching word says why: "draw" → Illustrator, "draw".
            let named = fuzzyScore(query, app.name) ?? otherNameScore(query, app.name)
            let described = named == nil ? infos[app.path].flatMap { appInfoMatch(query, $0) } : nil
            guard let match = named ?? described?.score else { return nil }
            let path = app.path
            return LauncherResult(
                id: path, title: app.name,
                subtitle: [app.running ? "Running" : nil, described?.term].compactMap { $0 }.joined(separator: " · "),
                icon: .file(path), score: match + (app.running ? 0.3 : 0),
                action: { NSWorkspace.shared.openApplication(at: URL(filePath: path), configuration: .init()) },
                actions: { await MainActor.run { appActionRows(path) } })
        }
        return installed + installRows(query)
    }

    /// Apps you don't have, by the start of their name, when it isn't the start of one you have: two at most, the
    /// closest first, below everything you have.
    private func installRows(_ query: String) -> [LauncherResult] {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard let brew, typed.count >= 3, !apps.contains(where: { $0.name.lowercased().hasPrefix(typed) }) else { return [] }
        return casks.filter { $0.key.hasPrefix(typed) }.sorted { ($0.key.count, $0.key) < ($1.key.count, $1.key) }.prefix(2)
            .enumerated().map { index, cask in installRow(cask.token, name: cask.name, desc: cask.desc, brew: brew, score: -0.5 - Double(index) / 100) }
    }
}

/// Homebrew, if it's installed: where it goes on Apple silicon, then on Intel.
let brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// Enter installs it with `brew install --cask`, its output beside it as it goes (Enter again hides the launcher and
/// lets it finish); then Enter opens it. An app that needs your password to install can't ask for it here: the row
/// says so, and Enter copies the command for a terminal.
func installRow(_ token: String, name: String, desc: String, brew: String, score: Double) -> LauncherResult {
    let id = "install:\(token)", icon = LauncherResult.Icon.symbol("arrow.down.app")
    return LauncherResult(id: id, title: "Install \(name)", subtitle: "With Homebrew · \(desc)", icon: icon, score: score,
                          actionTitle: "Install", action: {}, output: { progress in
        let run = await runTool(URL(filePath: brew), ["install", "--cask", token], mergeErrors: true, timeout: 1800) { soFar in
            await progress(LauncherResult(id: id, title: "Installing \(name)…", subtitle: "Esc stops it", icon: icon, score: .infinity,
                                          actionTitle: "Hide", action: {}, preview: soFar))
        }
        guard run.succeeded else {
            let command = "brew install --cask \(token)"
            let reason = run.output.contains("sudo:") ? "It needs your password: Enter copies the command for a terminal"
                : run.message.split(separator: "\n").last.map(String.init) ?? ""
            return LauncherResult(id: id, title: "Couldn’t install \(name)", subtitle: reason, icon: .symbol("exclamationmark.triangle"),
                                  score: .infinity, actionTitle: "Copy Command", action: { copyToClipboard(command) }, preview: run.output)
        }
        let app = URL(filePath: "/Applications/\(name).app")
        let there = FileManager.default.fileExists(atPath: app.path)
        return LauncherResult(id: id, title: "\(name) is installed", subtitle: "With Homebrew", icon: icon, score: .infinity,
                              actionTitle: there ? "Open" : "", action: { if there { NSWorkspace.shared.open(app) } }, preview: run.output)
    })
}
