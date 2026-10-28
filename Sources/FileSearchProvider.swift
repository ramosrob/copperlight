import AppKit
import PDFKit

/// True if any folder or file name along `path` is one of `excluded` ("node_modules", ".git"…).
func isExcluded(_ path: String, by excluded: [String]) -> Bool {
    path.split(separator: "/").contains { excluded.contains(String($0)) }
}

/// Spotlight query for display names with a word starting with each word of `query`, ignoring
/// case and diacritics: "inv 2026" finds "Invoice October 2026.pdf". nil for a blank query.
func spotlightQuery(_ query: String) -> String? {
    let words = query.split(whereSeparator: \.isWhitespace)
    guard !words.isEmpty else { return nil }
    return words.map { word in
        let escaped = word.reduce(into: "") { out, c in
            if "\\\"*?".contains(c) { out.append("\\") } // quotes end the string, * and ? are wildcards
            out.append(c)
        }
        return "kMDItemDisplayName == \"\(escaped)*\"cdw"
    }.joined(separator: " && ")
}

/// The same words in the text inside files, minus the files whose name matches them (listed by name already).
/// Spotlight reads documents, and the text in images and screenshots too: "29.99" finds a photo of a price tag.
/// nil under 3 characters.
func spotlightContentQuery(_ query: String) -> String? {
    guard query.trimmingCharacters(in: .whitespaces).count >= 3, let names = spotlightQuery(query) else { return nil }
    return "(\(names.replacingOccurrences(of: "kMDItemDisplayName", with: "kMDItemTextContent"))) && !(\(names))"
}

/// The lines of a text file or PDF that have `query`'s first word, for the preview; nil for other kinds of file.
func matchingLines(_ path: String, query: String, limit: Int = 30) -> String? {
    let url = URL(filePath: path)
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard let text = path.lowercased().hasSuffix(".pdf") ? PDFDocument(url: url)?.string
            : size < 2_000_000 ? try? String(contentsOf: url, encoding: .utf8) : nil,
          let word = query.split(whereSeparator: \.isWhitespace).first
    else { return nil }
    let lines = text.split(whereSeparator: \.isNewline).filter { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    return lines.isEmpty ? nil : lines.prefix(limit).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
}

/// 3: the name is the query (with or without its extension); 2: it starts with it; 1: a later word does.
func fileMatchQuality(_ query: String, name: String) -> Int {
    let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let (q, n) = (fold(query), fold(name))
    return n == q || fold((name as NSString).deletingPathExtension) == q ? 3 : n.hasPrefix(q) ? 2 : 1
}

/// A file's folder for the subtitle: "~/Code/copperlight/Sources"; deep ones keep their last three names.
func shortParentPath(_ path: String, home: String = NSHomeDirectory()) -> String {
    var parent = (path as NSString).deletingLastPathComponent
    if parent == home || parent.hasPrefix(home + "/") { parent = "~" + parent.dropFirst(home.count) }
    let parts = parent.split(separator: "/", omittingEmptySubsequences: false) // "/a/b" → ["", "a", "b"]
    guard parts.count > 5 else { return parent }
    return String(parts[0]) + "/…/" + parts.suffix(3).joined(separator: "/")
}

/// Files and folders from the Spotlight index, in the `[files]` scopes. Results sort below
/// everything else, and the search never holds up other providers (they're merged as they finish).
actor FileSearchProvider: ResultProvider {
    /// Typed first, it searches files only, with more results.
    static let prefix = "f "
    private var settings = Config.Files()
    nonisolated var modes: [Mode] { [Mode(prefix: Self.prefix, title: "Files", icon: .symbol("doc.text.magnifyingglass"), hint: "A file's name")] }

    func setSettings(_ settings: Config.Files) { self.settings = settings }

    /// Matches by name; typed after "f ", files with the words inside too (the launcher gets those from
    /// FileContentProvider, so the names never wait for the slower content search).
    func results(for query: String) async -> [LauncherResult] {
        let fileOnly = query.hasPrefix(Self.prefix)
        let text = (fileOnly ? String(query.dropFirst(Self.prefix.count)) : query).trimmingCharacters(in: .whitespaces)
        guard fileOnly else { return rows(await hits(for: text, limit: 20), text: text, inside: false) }
        async let named = hits(for: text, limit: 60)
        async let inside = hits(for: text, limit: 30, inside: true)
        return rows(await named, text: text, inside: false) + rows(await inside, text: text, inside: true)
    }

    func contentResults(for text: String) async -> [LauncherResult] {
        rows(await hits(for: text, limit: 10, inside: true), text: text, inside: true)
    }

    /// Below every other kind of result, in this order: by name, then by what's inside.
    private func rows(_ hits: [FileHit], text: String, inside: Bool) -> [LauncherResult] {
        hits.enumerated().map { index, hit in
            let path = hit.path, folder = shortParentPath(path)
            return LauncherResult(
                id: "file:\(path)", title: hit.name, subtitle: folder,
                accessory: inside ? (hit.image ? "Text in image" : "Text inside") : "", // says why, as long names hide the subtitle
                icon: .file(path), score: (inside ? -2 : -1) - Double(index) / 1000,
                action: { _ = NSWorkspace.shared.open(URL(filePath: path)) },
                preview: inside && hit.image ? "" : nil, // the picture, so you see where the text is
                previewStyle: .prose,
                loadPreview: inside && !hit.image ? { @Sendable in matchingLines(path, query: text) ?? "" } : nil,
                previewImage: inside && hit.image ? { @MainActor in
                    (try? Data(contentsOf: URL(filePath: path), options: .mappedIfSafe)).flatMap { thumbnail($0, maxPixels: 1600) }
                        .map { NSImage(cgImage: $0, size: .zero) }
                } : nil)
        }
    }

    /// Files whose name matches `text` (`inside`: whose text does, and name doesn't), best first; none for under 2
    /// characters (3 inside). Also feeds `:reveal`.
    func hits(for text: String, limit: Int, inside: Bool = false) async -> [FileHit] {
        guard text.count >= 2, let format = inside ? spotlightContentQuery(text) : spotlightQuery(text) else { return [] }
        // Debounce: the next keystroke cancels this task, and Spotlight is never asked.
        guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return [] }

        let settings = settings
        let scopes = settings.scopes.map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !scopes.isEmpty else { return [] }
        let search = await SpotlightSearch()
        let hits = await withTaskCancellationHandler {
            await search.run(format, scopes: scopes)
        } onCancel: {
            Task { @MainActor in search.finish(collect: false) }
        }

        // Best match first, then most recently used, then the shallowest path (a project's own
        // README before the ones vendored deep inside it).
        let kept = hits.filter { !isExcluded($0.path, by: settings.exclude) }
        let scored: [(hit: FileHit, quality: Int, used: Date, depth: Int)] = kept.map {
            (hit: $0, quality: fileMatchQuality(text, name: $0.name), used: $0.lastUsed ?? .distantPast,
             depth: $0.path.count { $0 == "/" })
        }
        let ranked = scored.sorted { ($0.quality, $0.used, -$0.depth) > ($1.quality, $1.used, -$1.depth) }
        return ranked.prefix(limit).map(\.hit)
    }
}

struct FileHit: Sendable {
    let path: String, name: String, lastUsed: Date?
    var image = false
}

/// Files with the typed words inside, as their own provider: Spotlight takes longer for content than for names.
struct FileContentProvider: ResultProvider {
    let files: FileSearchProvider
    func results(for query: String) async -> [LauncherResult] {
        await files.contentResults(for: query.trimmingCharacters(in: .whitespaces))
    }
}

/// One NSMetadataQuery, run until its first full set of results is in. NSMetadataQuery delivers
/// through the main run loop, hence the main actor.
@MainActor private final class SpotlightSearch {
    /// Spotlight hands back the most recently used first; ranking looks at this many.
    private static let candidates = 500
    private let query = NSMetadataQuery()
    private var continuation: CheckedContinuation<[FileHit], Never>?
    private var observer: (any NSObjectProtocol)?

    func run(_ format: String, scopes: [URL]) async -> [FileHit] {
        guard let predicate = NSPredicate(fromMetadataQueryString: format) else { return [] }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            query.predicate = predicate
            query.searchScopes = scopes
            query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(collect: true) }
            }
            if !query.start() { finish(collect: false) }
        }
    }

    /// Stops the query and hands back what it found (or nothing, when cancelled). Safe to call twice.
    func finish(collect: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        var hits: [FileHit] = []
        for i in 0..<(collect ? min(query.resultCount, Self.candidates) : 0) {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            hits.append(FileHit(
                path: path,
                name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? (path as NSString).lastPathComponent,
                lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                image: (item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String])?.contains("public.image") ?? false))
        }
        continuation.resume(returning: hits)
    }
}
