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

    /// `index` nil: names only (tests, which mustn't go online or write apps.json).
    init(index: AppIndex? = AppIndex()) { self.index = index }

    func setOnline(_ online: Bool) { self.online = online }
    func setInfos(_ infos: [String: AppInfo]) { self.infos = infos }

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
        if infos.isEmpty { infos = await index.infos }
        // In the background: new and updated apps are read, looked up and described, then searched by what they do.
        let (listed, online) = (apps.map { (path: $0.path, name: $0.name) }, online)
        Task.detached(priority: .utility) { [self] in
            await index.update(listed, online: online) { await self.setInfos($0) }
        }
    }

    /// Every match: the launcher adds frecency (the id is the path) and sorts, so cutting here could drop a favorite.
    func results(for query: String) -> [LauncherResult] {
        apps.compactMap { app in
            // By what it does, the matching word says why: "draw" → Illustrator, "draw".
            let named = fuzzyScore(query, app.name) ?? otherNameScore(query, app.name)
            let described = named == nil ? infos[app.path].flatMap { appInfoMatch(query, $0) } : nil
            guard let match = named ?? described?.score else { return nil }
            let path = app.path
            return LauncherResult(
                id: path, title: app.name,
                subtitle: [app.running ? "Running" : nil, described?.term].compactMap { $0 }.joined(separator: " · "),
                icon: .file(path), score: match + (app.running ? 0.3 : 0),
                action: { NSWorkspace.shared.openApplication(at: URL(filePath: path), configuration: .init()) })
        }
    }
}
