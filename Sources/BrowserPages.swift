import AppKit
import GRDB

/// A page from a browser: one of its bookmarks, or one from its history.
struct BrowserPage: Equatable, Sendable {
    var title: String
    var url: String
    var profile: String? = nil // the profile it came from, as the browser names it; nil for Safari
    var bookmark = false
    var lastVisit: Date? = nil // history only
}

/// Every bookmark in a Chromium `Bookmarks` file: the "url" nodes under its roots, folders walked.
func chromiumBookmarks(_ data: Data) -> [BrowserPage] {
    guard let roots = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["roots"] as? [String: Any] else { return [] }
    var pages: [BrowserPage] = []
    func walk(_ node: Any) {
        guard let node = node as? [String: Any] else { return }
        if node["type"] as? String == "url", let url = node["url"] as? String {
            pages.append(BrowserPage(title: node["name"] as? String ?? url, url: url, bookmark: true))
        }
        (node["children"] as? [Any])?.forEach(walk)
    }
    roots.values.forEach(walk)
    return pages
}

/// Every bookmark in Safari's `Bookmarks.plist` (the reading list included): the leaves, folders walked.
func safariBookmarks(_ data: Data) -> [BrowserPage] {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
    var pages: [BrowserPage] = []
    func walk(_ node: Any) {
        guard let node = node as? [String: Any] else { return }
        if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
            pages.append(BrowserPage(title: (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? url, url: url, bookmark: true))
        }
        (node["Children"] as? [Any])?.forEach(walk)
    }
    walk(plist)
    return pages
}

/// Pages from a browser's history database. It reads a copy, the browser keeps the original locked, with the
/// copy's -wal or -journal beside it: a journal left by an unfinished write (Chrome quit mid-write) is what turns
/// the half-written file back into a database. `sql` selects `url`, `title` and `visited` (seconds since 1970).
func historyPages(at path: String, sql: String, profile: String?) -> [BrowserPage] {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    guard FileManager.default.fileExists(atPath: path), (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
    else { return [] }
    let copy = folder.appending(path: "history.sqlite").path
    for suffix in ["", "-wal", "-journal"] where FileManager.default.fileExists(atPath: path + suffix) {
        try? FileManager.default.copyItem(atPath: path + suffix, toPath: copy + suffix)
    }
    guard let db = try? DatabaseQueue(path: copy) else { return [] }
    return (try? db.read { db in
        try Row.fetchAll(db, sql: sql).compactMap { row -> BrowserPage? in
            guard let url: String = row["url"] else { return nil }
            let visited: Double? = row["visited"]
            return BrowserPage(title: row["title"] ?? "", url: url, profile: profile, lastVisit: visited.map { Date(timeIntervalSince1970: $0) })
        }
    }) ?? []
}

/// How many recent pages are read from each profile's history.
private let historyLimit = 3000

/// The bookmarks and recent history of the browser at `app`, in `profile` or, without one, in all its profiles.
/// Chromium browsers and Firefox read as they are; Safari's files need Full Disk Access, and without it there's
/// nothing. Other browsers (Arc…) have nothing either.
func browserPages(app: URL, profile: String?) -> [BrowserPage] {
    let bundleID = Bundle(url: app)?.bundleIdentifier ?? ""
    let same = { (a: String) in profile.map { a.caseInsensitiveCompare($0) == .orderedSame } ?? true }
    if let folder = chromiumFolders[bundleID] {
        let base = URL.applicationSupportDirectory.appending(path: folder)
        guard let localState = try? Data(contentsOf: base.appending(path: "Local State")) else { return [] }
        return chromiumProfiles(localState: localState).filter { same($0.name) || same($0.directory) }.flatMap { directory, name in
            let folder = base.appending(path: directory)
            let bookmarks = (try? Data(contentsOf: folder.appending(path: "Bookmarks"))).map(chromiumBookmarks) ?? []
            // last_visit_time: microseconds since 1601.
            let history = historyPages(at: folder.appending(path: "History").path, sql: """
                SELECT url, title, last_visit_time / 1000000.0 - 11644473600 AS visited FROM urls
                WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT \(historyLimit)
                """, profile: name)
            return bookmarks.map { var page = $0; page.profile = name; return page } + history
        }
    }
    if bundleID == "org.mozilla.firefox" {
        let base = URL.applicationSupportDirectory.appending(path: "Firefox")
        return firefoxProfiles(base).filter { same($0.name) }.flatMap { name, folder in
            let places = folder.appending(path: "places.sqlite").path
            // A bookmark (type 1) points at a page in moz_places; dates are microseconds since 1970.
            let bookmarks = historyPages(at: places, sql: """
                SELECT p.url, COALESCE(b.title, p.title) AS title, NULL AS visited FROM moz_bookmarks b
                JOIN moz_places p ON p.id = b.fk WHERE b.type = 1 AND p.url LIKE 'http%'
                """, profile: name).map { var page = $0; page.bookmark = true; return page }
            let history = historyPages(at: places, sql: """
                SELECT url, title, last_visit_date / 1000000.0 AS visited FROM moz_places
                WHERE hidden = 0 AND last_visit_date IS NOT NULL ORDER BY last_visit_date DESC LIMIT \(historyLimit)
                """, profile: name)
            return bookmarks + history
        }
    }
    if bundleID == "com.apple.Safari" {
        let safari = URL.homeDirectory.appending(path: "Library/Safari")
        let bookmarks = (try? Data(contentsOf: safari.appending(path: "Bookmarks.plist"))).map(safariBookmarks) ?? []
        // visit_time: seconds since 2001.
        return bookmarks + historyPages(at: safari.appending(path: "History.db").path, sql: """
            SELECT i.url, v.title, MAX(v.visit_time) + 978307200 AS visited FROM history_items i
            JOIN history_visits v ON v.history_item = i.id GROUP BY i.id ORDER BY visited DESC LIMIT \(historyLimit)
            """, profile: nil)
    }
    return []
}

/// Firefox's profiles from `profiles.ini`: the name (`about:profiles`) and its folder.
func firefoxProfiles(_ base: URL) -> [(name: String, folder: URL)] {
    guard let ini = try? String(contentsOf: base.appending(path: "profiles.ini"), encoding: .utf8) else { return [] }
    var profiles: [(String, URL)] = [], name: String?, path: String?, relative = true
    for line in (ini + "\n[end]").split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
        if line.hasPrefix("[") {
            if let name, let path { profiles.append((name, relative ? base.appending(path: path) : URL(filePath: path))) }
            (name, path, relative) = (nil, nil, true)
        } else if line.hasPrefix("Name=") { name = String(line.dropFirst(5)) }
        else if line.hasPrefix("Path=") { path = String(line.dropFirst(5)) }
        else if line == "IsRelative=0" { relative = false }
    }
    return profiles
}

/// `text`'s words, lowercased and without accents, each after a space: " copperlight on github https github com".
/// A typed word (`typedWords`) matches where it's in it, so at the start of a word ("30c" isn't in "HP30138C").
func wordStarts(_ text: String) -> String {
    " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
}

/// The words typed, each after a space, to look for in `wordStarts`.
func typedWords(_ query: String) -> [String] {
    query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { " " + $0 }
}

private func searchKey(_ page: BrowserPage) -> String { wordStarts(page.title + " " + page.url) }

/// Bookmarks and recent history from the browser links open in (`[browser]`, else the default), searched from 2
/// letters: every word typed must start a word of the title or the address. Bookmarks come first, then the most
/// recently visited pages, a title on a site once. They rank just above files. Loaded in the background when the
/// launcher opens, at most every 2 minutes, and kept in memory only.
actor BrowserPagesProvider: ResultProvider {
    private var pages: [BrowserPage] = [] { didSet { keys = pages.map(searchKey) } }
    private var keys: [String] = []
    private var app: URL?
    private var browser = Config.Browser()
    private var loaded = Date.distantPast

    init(pages: [BrowserPage] = [], app: URL? = nil) {
        (self.pages, self.app) = (pages, app)
        keys = pages.map(searchKey) // didSet doesn't run in init
    }

    func setBrowser(_ browser: Config.Browser) {
        self.browser = browser
        loaded = .distantPast
    }

    func refresh() {
        // ponytail: copies each profile's history (15–20 MB) per refresh; read Chrome's file in place if it ever drags.
        guard Date.now.timeIntervalSince(loaded) > 120, let app = browserApp(browser.name) else { return }
        loaded = .now
        self.app = app
        pages = browserPages(app: app, profile: browser.profile)
    }

    func results(for query: String) -> [LauncherResult] {
        // Calls wait their turn on the actor: one for a keystroke since typed over would hold up the current one.
        guard !Task.isCancelled else { return [] }
        let words = typedWords(query)
        guard query.count >= 2, !words.isEmpty, let app else { return [] }
        let matches = zip(pages, keys).filter { _, key in words.allSatisfy { key.range(of: $0, options: .literal) != nil } }.map(\.0)
        // Once per address, and once per title on a site (the same video with another &t=).
        var seen = Set<String>()
        let new = { (page: BrowserPage) in
            seen.insert(page.url).inserted && seen.insert("\(URL(string: page.url)?.host() ?? "") \(page.title)").inserted
        }
        let bookmarks = matches.filter { $0.bookmark && new($0) }.prefix(4)
        let history = matches.filter { !$0.bookmark }.sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
            .filter(new).prefix(4)
        let profiles = Set(pages.compactMap(\.profile)).count
        return (Array(bookmarks) + Array(history)).enumerated().map { index, page in
            let host = URL(string: page.url)?.host() ?? page.url
            let opening = openArguments(page.url, in: app, profile: page.profile)
            return LauncherResult(
                id: "\(page.bookmark ? "bookmark" : "history"):\(page.url)", title: page.title.isEmpty ? page.url : page.title,
                subtitle: ([host] + (profiles > 1 ? page.profile.map { [$0] } ?? [] : [])).joined(separator: " · "),
                icon: .symbol(page.bookmark ? "bookmark" : "clock.arrow.circlepath"), score: -0.4 - Double(index) / 100, action: {
                    if case .success(let (via, arguments)) = opening { return runDetached("/usr/bin/open", arguments, label: via) }
                    if let url = URL(string: page.url) { NSWorkspace.shared.open(url) }
                })
        }
    }
}
