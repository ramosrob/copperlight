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

/// Tab on an app: open it, and while it runs hide, quit, force quit (asks first) or relaunch it; reveal it or copy its
/// path. Its icon, version and where it is show beside them.
@MainActor func appActionRows(_ path: String) -> [LauncherResult] {
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
    return rows.enumerated().map { index, row in
        LauncherResult(id: "actions:\(path):\(row.title)", title: row.title, subtitle: "", icon: .symbol(row.symbol), score: 50 - Double(index) / 100,
                       actionTitle: row.title, action: row.action, confirm: row.confirm, preview: name, previewStyle: .prose,
                       previewImage: {
                           let icon = NSWorkspace.shared.icon(forFile: path)
                           icon.size = NSSize(width: 256, height: 256) // its largest picture, not the 32-point one
                           return icon
                       }, details: details)
    }
}
