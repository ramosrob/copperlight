import AppKit
import UniformTypeIdentifiers

/// Beside a file's actions: where it is, its kind, size and when it changed; a text file's start, a picture or a PDF.
private func filePreview(_ path: String) -> (load: (@Sendable () async -> String)?, image: (@MainActor @Sendable () -> NSImage?)?,
                                             details: [(String, String)]) {
    let url = URL(filePath: path)
    let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
    let type = values?.contentType
    let details = [("Where", shortParentPath(path)), ("Kind", values?.localizedTypeDescription ?? "File"),
                   ("Size", Int64(values?.fileSize ?? 0).formatted(.byteCount(style: .file))),
                   ("Modified", values?.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "–")]
    if type?.conforms(to: .image) == true {
        return (nil, { (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap { thumbnail($0, maxPixels: 1600) }.map { NSImage(cgImage: $0, size: .zero) } },
                details)
    }
    if type?.conforms(to: .pdf) == true { return (nil, { NSImage(contentsOf: url) }, details) } // its first page
    if type?.conforms(to: .text) == true {
        return ({ @Sendable in
            guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 4000) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }, nil, details)
    }
    return (nil, nil, details)
}

/// Tab on a file: open it, with another app (its row fills in `:open with`), reveal it, copy its path or the file itself
/// (to paste in Finder or an email), open its folder in your terminal, or move it to the Trash (asks first). What it
/// is shows beside them.
func fileActionRows(_ path: String, terminal: String?) -> [LauncherResult] {
    let url = URL(filePath: path), name = url.lastPathComponent
    let preview = filePreview(path)
    let opener = NSWorkspace.shared.urlForApplication(toOpen: url).map { FileManager.default.displayName(atPath: $0.path).replacing(#/\.app$/#, with: "") }
    let rows: [(title: String, subtitle: String, symbol: String, action: @MainActor @Sendable () -> Void)] = [
        ("Open", opener.map { "In \($0)" } ?? "", "arrow.up.forward.app", { NSWorkspace.shared.open(url) }),
        ("Open With…", "Another app", "square.grid.2x2", {}),
        ("Reveal in Finder", shortParentPath(path), "folder", { NSWorkspace.shared.activateFileViewerSelecting([url]) }),
        ("Copy Path", (path as NSString).abbreviatingWithTildeInPath, "doc.on.doc", { copyToClipboard(path) }),
        ("Copy File", "To paste in Finder or an email", "doc.on.clipboard", {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }),
        ("Open in Terminal", terminal ?? "Terminal", "terminal", { openInTerminal(path, app: terminal) }),
        ("Move to Trash", "", "trash", { moveToTrash(path) }),
    ]
    return rows.enumerated().map { index, row in
        LauncherResult(id: "actions:\(path):\(row.title)", title: row.title, subtitle: row.subtitle, icon: .symbol(row.symbol),
                       score: 50 - Double(index) / 100, actionTitle: row.title == "Open With…" ? "Choose" : row.title.replacing("…", with: ""),
                       action: row.action, completion: row.title == "Open With…" ? ":open with \(path) " : nil,
                       confirm: row.title == "Move to Trash" ? "Move “\(name)” to the Trash?" : nil,
                       preview: preview.load == nil ? name : nil, // a text file's own text loads in its place
                       previewStyle: .prose, loadPreview: preview.load, previewImage: preview.image, details: preview.details)
    }
}

/// The kinds of file an app says it opens (its Info.plist's document types), as type identifiers.
func documentTypes(_ app: String) -> [String] {
    let types = Bundle(url: URL(filePath: app))?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
    return uniqued(types.flatMap { type in
        (type["LSItemContentTypes"] as? [String] ?? [])
            + (type["CFBundleTypeExtensions"] as? [String] ?? []).compactMap { UTType(filenameExtension: $0)?.identifier }
    })
}

/// Spotlight: files of exactly these kinds that have been opened.
func recentDocumentsQuery(_ types: [String]) -> String {
    "kMDItemLastUsedDate == * && (" + types.map { "kMDItemContentType == \"\($0)\"" }.joined(separator: " || ") + ")"
}

/// An app's recent documents: files in your home folder of the kinds the Mac opens in it, the most recently opened
/// first (the Mac's own Open Recent lists are out of reach without Full Disk Access). Apps' own files in ~/Library are
/// left out, but not your cloud drives there.
@MainActor func recentDocuments(of app: String, limit: Int = 5) async -> [FileHit] {
    guard let id = Bundle(url: URL(filePath: app))?.bundleIdentifier else { return [] }
    // ponytail: by kind, one query; a single file set to open elsewhere (Get Info › Open with) still shows.
    let types = documentTypes(app).filter { type in
        UTType(type).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }.flatMap { Bundle(url: $0)?.bundleIdentifier } == id
    }
    guard !types.isEmpty else { return [] }
    let library = NSHomeDirectory() + "/Library/"
    let hits = await SpotlightSearch().run(recentDocumentsQuery(types), scopes: [.homeDirectory])
    return Array(hits.filter {
        !$0.path.hasPrefix(library) || $0.path.hasPrefix(library + "CloudStorage/") || $0.path.hasPrefix(library + "Mobile Documents/")
    }.prefix(limit))
}

/// Tab on an app: its recent documents (Enter opens one in it), then open it, and while it runs hide, quit, force quit
/// (asks first) or relaunch it; reveal it or copy its path. Its icon, version and where it is show beside them.
@MainActor func appActionRows(_ path: String, recent: [FileHit] = []) -> [LauncherResult] {
    let url = URL(filePath: path), bundle = Bundle(url: url)
    let name = FileManager.default.displayName(atPath: path).replacing(#/\.app$/#, with: "")
    let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == url.path } // a bundle URL ends in "/"
    let pid = running?.processIdentifier
    let app: @Sendable () -> NSRunningApplication? = { pid.flatMap { NSRunningApplication(processIdentifier: $0) } }
    var rows: [(title: String, symbol: String, confirm: String?, action: @MainActor @Sendable () -> Void)] = []
    rows.append(("Open", "arrow.up.forward.app", nil, { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }))
    if running != nil {
        rows.append(("Hide", "eye.slash", nil, { app()?.hide() }))
        rows.append(("Quit", "xmark", nil, { app()?.terminate() }))
        rows.append(("Force Quit", "xmark.octagon", "Force Quit \(name)? Unsaved changes are lost.", { app()?.forceTerminate() }))
        rows.append(("Relaunch", "arrow.clockwise.circle", nil, { app().map(relaunch) }))
    }
    rows.append(("Reveal in Finder", "folder", nil, { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
    rows.append(("Copy Path", "doc.on.doc", nil, { copyToClipboard(path) }))
    let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let details = [("Version", version), ("Where", shortParentPath(path)), ("Running", running.map { _ in "Yes" } ?? "No")]
        .compactMap { label, value in value.map { (label, $0) } }
    let documents = recent.enumerated().map { index, file in
        let preview = filePreview(file.path), document = URL(filePath: file.path)
        return LauncherResult(id: "recent:\(path):\(file.path)", title: file.name, subtitle: shortParentPath(file.path),
                              accessory: file.lastUsed.map { shortAge($0) } ?? "", icon: .file(file.path), score: 51 - Double(index) / 100,
                              actionTitle: "Open in \(name)",
                              action: { NSWorkspace.shared.open([document], withApplicationAt: url, configuration: .init()) },
                              section: "Recent Documents", preview: preview.load == nil ? file.name : nil, previewStyle: .prose,
                              loadPreview: preview.load, previewImage: preview.image, details: preview.details)
    }
    return documents + rows.enumerated().map { index, row in
        LauncherResult(id: "actions:\(path):\(row.title)", title: row.title, subtitle: "", icon: .symbol(row.symbol), score: 50 - Double(index) / 100,
                       actionTitle: row.title, action: row.action, confirm: row.confirm, preview: name, previewStyle: .prose,
                       previewImage: {
                           let icon = NSWorkspace.shared.icon(forFile: path)
                           icon.size = NSSize(width: 256, height: 256) // its largest picture, not the 32-point one
                           return icon
                       }, details: details)
    }
}
