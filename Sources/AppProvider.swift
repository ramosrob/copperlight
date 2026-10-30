import AppKit

/// Fuzzy subsequence match, case- and diacritic-insensitive; spaces in the query are ignored.
/// Returns nil when there's no match, about 1 for a prefix or word-initials match, less for
/// scattered matches. Shorter texts win ties. Picks the best alignment, not the first one, so
/// "vsc" hits the word starts in "Visual Studio Code". With nothing in order, a slip is forgiven (`typoScore`).
func fuzzyScore(_ query: String, _ text: String) -> Double? { inOrderScore(query, text) ?? typoScore(query, text) }

private func inOrderScore(_ query: String, _ text: String) -> Double? {
    // Most names can't match: when both are plain ASCII, a byte scan for the letters in order says so before the
    // folding below, a string per character, does (that took 30 ms for 2,000 names).
    if query.utf8.allSatisfy({ $0 < 128 }), text.utf8.allSatisfy({ $0 < 128 }) {
        let wanted = Array(query.lowercased().utf8.filter { $0 != 32 })
        var found = 0
        for byte in text.lowercased().utf8 where found < wanted.count && byte == wanted[found] { found += 1 }
        if found < wanted.count { return nil }
    }
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

/// A slip forgiven: a letter wrong, extra or missing, or two swapped ("slcak" → Slack, "calender" → Calendar); two
/// from 8 letters ("photsohop" → Photoshop). Compared with the text from its start or a word's, spaces left out. The
/// first letter has to be right, typing past the end isn't a slip ("notes" isn't Note), and it scores under any real
/// match, so it only leads when nothing else does.
private func typoScore(_ query: String, _ text: String) -> Double? {
    // Most names are no: shorter than what's typed, or no word in them starts with its first letter. Said by a byte
    // scan for plain ASCII, before any folding: folding the query for every name took 20 ms.
    if query.utf8.allSatisfy({ $0 < 128 }), text.utf8.allSatisfy({ $0 < 128 }) {
        let typed = Array(query.lowercased().utf8.filter { $0 != 32 }), bytes = Array(text.lowercased().utf8)
        let wordy = { (b: UInt8) in (48...57).contains(b) || (97...122).contains(b) }
        guard typed.count >= 4, bytes.count >= typed.count,
              bytes.indices.contains(where: { bytes[$0] == typed[0] && ($0 == 0 || !wordy(bytes[$0 - 1])) }) else { return nil }
    }
    let fold = { (s: String) in Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    let q = fold(query).filter { $0 != " " }
    guard q.count >= 4, q.count <= 30, text.count >= q.count else { return nil }
    let t = fold(text), slips = q.count >= 8 ? 2 : 1
    for start in t.indices where t[start] == q[0] && (start == 0 || !t[start - 1].isLetter && !t[start - 1].isNumber) {
        let rest = t[start...].filter { $0 != " " }
        guard rest.count >= q.count else { continue }
        if let count = slipsBetween(q, Array(rest.prefix(q.count + slips)), most: slips) {
            return 0.05 / Double(max(count, 1)) - 0.0001 * Double(t.count)
        }
    }
    return nil
}

/// The fewest slips (a letter wrong, extra or missing, two swapped) that make `typed` the start of `text`, if at most
/// `most`: optimal string alignment.
private func slipsBetween(_ typed: [Character], _ text: [Character], most: Int) -> Int? {
    let (n, m) = (typed.count, text.count)
    guard m >= n - most else { return nil }
    var d = (0...n).map { i in (0...m).map { j in i == 0 ? j : j == 0 ? i : 0 } }
    for i in 1...n {
        for j in 1...m {
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (typed[i - 1] == text[j - 1] ? 0 : 1))
            if i > 1, j > 1, typed[i - 1] == text[j - 2], typed[i - 2] == text[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
        }
    }
    let fewest = d[n][max(0, n - most)...min(m, n + most)].min() ?? .max
    return fewest <= most ? fewest : nil
}

actor AppProvider: ResultProvider {
    private struct App { let name: String, path: String, running: Bool }
    private var apps: [App] = []
    private var names: [String: String] = [:] // path → Finder display name, cached across rescans
    /// What each app is for (AppIndex), by path: found by what it does when its name doesn't match.
    private var infos: [String: AppInfo] = [:] { didSet { terms = infos.mapValues(AppTerms.init) } }
    private var terms: [String: AppTerms] = [:] // infos, ready to search
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
        let words = appQueryWords(query)
        let installed: [LauncherResult] = apps.compactMap { app in
            // By what it does, the matching word says why: "draw" → Illustrator, "draw".
            let named = fuzzyScore(query, app.name) ?? otherNameScore(query, app.name)
            let described = named == nil && !words.isEmpty ? terms[app.path].flatMap { appInfoMatch(words, $0) } : nil
            guard let match = named ?? described?.score else { return nil }
            let path = app.path
            return LauncherResult(
                id: path, title: app.name,
                subtitle: [app.running ? "Running" : nil, described?.term].compactMap { $0 }.joined(separator: " · "),
                icon: .file(path), score: match + (app.running ? 0.3 : 0),
                action: { NSWorkspace.shared.openApplication(at: URL(filePath: path), configuration: .init()) },
                actions: {
                    let recent = await recentDocuments(of: path)
                    return await MainActor.run { appActionRows(path, recent: recent) }
                })
        }
        return installed + installRows(query)
    }

    /// Apps you don't have, by the start of their name, when it isn't the start of one you have: two at most, the
    /// closest first, below everything you have.
    private func installRows(_ query: String) -> [LauncherResult] {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard Feature.homebrew.isOn, let brew, typed.count >= 3, !apps.contains(where: { $0.name.lowercased().hasPrefix(typed) }) else { return [] }
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
