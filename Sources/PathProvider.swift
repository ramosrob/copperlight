import AppKit

/// A typed path: the folder to list, as typed (ending in "/"), and the start of a name in it.
struct PathQuery: Equatable {
    let folder: String
    let filter: String
    var url: URL { URL(filePath: NSString(string: folder).expandingTildeInPath, directoryHint: .isDirectory) }
}

/// "~/code/he" → "~/code/" and "he"; a folder that exists ("/Applications") → its own contents. nil for text
/// that isn't shaped like a path.
func pathQuery(_ text: String, isFolder: (String) -> Bool = isBrowsableFolder) -> PathQuery? {
    guard text == "~" || text.hasPrefix("~/") || text.hasPrefix("/") else { return nil }
    if text == "~" || text.hasSuffix("/") { return PathQuery(folder: text == "~" ? "~/" : text, filter: "") }
    // A lone "." starts a hidden name (`~/.co` → .config), not "this folder".
    if !text.hasSuffix("/."), isFolder(NSString(string: text).expandingTildeInPath) { return PathQuery(folder: text + "/", filter: "") }
    let slash = text.lastIndex(of: "/")!
    return PathQuery(folder: String(text[...slash]), filter: String(text[text.index(after: slash)...]))
}

/// A folder to go into: a directory (or a link to one) that isn't a package. An app opens; it isn't browsed.
func isBrowsableFolder(_ path: String) -> Bool {
    let values = try? URL(filePath: path).resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    return values?.isDirectory == true && values?.isPackage != true
}

struct PathEntry: Equatable {
    let path: String
    let name: String
    let shown: String // the path as typed: "~/code/copperlight"
    let isFolder: Bool
}

/// The folder's entries: A to Z, or the best matches for the filter first. Hidden ones only when the filter
/// starts with ".". nil when there's no such folder (or it can't be read).
func pathEntries(_ query: PathQuery, limit: Int = 200) -> [PathEntry]? {
    let folder = query.url
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
    let hidden = query.filter.hasPrefix(".")
    let matches = names.compactMap { name -> (name: String, score: Double)? in
        guard hidden || !name.hasPrefix(".") else { return nil }
        return query.filter.isEmpty ? (name, 0) : fuzzyScore(query.filter, name).map { (name, $0) }
    }
    let sorted = query.filter.isEmpty ? matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        : matches.sorted { $0.score > $1.score }
    return sorted.prefix(limit).map { match in
        let path = folder.appending(path: match.name).path
        return PathEntry(path: path, name: match.name, shown: query.folder + match.name, isFolder: isBrowsableFolder(path))
    }
}

/// `~/code/copperlight`, `/Applications`: the folder's entries, and with no name typed the folder itself on top (Enter
/// opens it in Finder). Enter on a folder goes into it, on a file opens it. Queries starting with "~" or "/"
/// come here alone.
struct PathProvider: ResultProvider {
    static let prefixes = ["~", "/"]

    func results(for query: String) -> [LauncherResult] {
        guard let path = pathQuery(query) else { return [] }
        guard let entries = pathEntries(path) else {
            return [LauncherResult(id: "path:none", title: "No folder at \(path.folder)", icon: .symbol("questionmark.folder"),
                                   score: 0, actionTitle: "", action: {})]
        }
        var rows: [LauncherResult] = []
        if path.filter.isEmpty {
            let folder = path.url
            rows.append(LauncherResult(id: "file:\(folder.path)", title: folder.path == "/" ? "/" : folder.lastPathComponent,
                                       subtitle: path.folder, icon: .file(folder.path), score: 100, actionTitle: "Open in Finder",
                                       action: { NSWorkspace.shared.open(folder) }))
        }
        return rows + entries.enumerated().map { index, entry in
            LauncherResult(id: "file:\(entry.path)", title: entry.name, icon: .file(entry.path), score: 50 - Double(index) / 1000,
                           actionTitle: entry.isFolder ? "Browse" : "Open", action: { NSWorkspace.shared.open(URL(filePath: entry.path)) },
                           completion: entry.isFolder ? entry.shown + "/" : nil)
        }
    }
}
