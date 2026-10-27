import AppKit
import GRDB
import Photos
import UniformTypeIdentifiers
import Vision

/// photos.sqlite: the text in each photo of the Photos library, read on this Mac with Vision, so "29.99" finds the
/// photo of a price tag. Photos keeps its pictures out of Spotlight's file index, hence this. A photo without text
/// has a row too, so it isn't read again.
struct PhotoTextStore: Sendable {
    static let file = configDir.appending(path: "photos.sqlite")

    struct Hit: Sendable, Equatable {
        let id: String // PHAsset.localIdentifier
        let created: Date?
        let text: String
    }

    private let db: DatabaseQueue

    /// No path: in memory (tests).
    init(path: String? = nil) throws {
        db = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // unicode61 splits "29.99" into 29 and 99; a phrase query puts them back together.
            try db.execute(sql: "CREATE VIRTUAL TABLE photo USING fts5(id UNINDEXED, created UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2')")
        }
        try migrator.migrate(db)
    }

    func ids() throws -> Set<String> {
        try db.read { Set(try String.fetchAll($0, sql: "SELECT id FROM photo")) }
    }

    func add(id: String, created: Date?, text: String) throws {
        try db.write {
            try $0.execute(sql: "INSERT INTO photo (id, created, text) VALUES (?, ?, ?)",
                           arguments: [id, created?.timeIntervalSince1970, text])
        }
    }

    func remove(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        try db.write { db in for id in ids { try db.execute(sql: "DELETE FROM photo WHERE id = ?", arguments: [id]) } }
    }

    /// Newest first: photos with the typed words in that order, the last one as typed so far. "29.99" finds 29.99,
    /// 29,99 and 29 99 alike.
    func search(_ query: String, limit: Int = 10) throws -> [Hit] {
        let phrase = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\" *"
        return try db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, created, text FROM photo WHERE photo MATCH ? ORDER BY created DESC LIMIT ?",
                             arguments: [phrase, limit]).map { row in
                Hit(id: row["id"], created: (row["created"] as Double?).map(Date.init(timeIntervalSince1970:)), text: row["text"])
            }
        }
    }
}

/// The lines Vision reads in a picture, top to bottom.
func recognizedText(in image: CGImage) -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    try? VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

/// Whether Copperlight may read the Photos library (the welcome screen asks).
func hasPhotosAccess() -> Bool {
    [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite))
}

/// A photo from the library at about `size` points, nil if Photos can't give it (offline, for one only in iCloud).
func photoImage(_ id: String, size: CGFloat, network: Bool) async -> CGImage? {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat // one answer, not a blurry one first
    options.isNetworkAccessAllowed = network
    return await withCheckedContinuation { continuation in
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size, height: size), contentMode: .aspectFit,
                                              options: options) { image, _ in
            continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }
}

/// The same, blocking, for the row icon and the preview (both ask from a thread that can wait).
func photoImageNow(_ id: String, size: CGFloat) -> CGImage? {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.isSynchronous = true
    var result: CGImage?
    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size, height: size), contentMode: .aspectFit,
                                          options: options) { image, _ in
        result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    return result
}

/// Opens a copy of the photo in its default app (Preview): Photos has no way for other apps to show one of its own.
@MainActor func openPhoto(_ id: String) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .highQualityFormat
    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, type, _, _ in
        guard let data else { return }
        let name = (PHAssetResource.assetResources(for: asset).first?.originalFilename as NSString?)?.deletingPathExtension ?? "Photo"
        let url = FileManager.default.temporaryDirectory
            .appending(path: name + "." + (type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"))
        guard (try? data.write(to: url)) != nil else { return }
        DispatchQueue.main.async { _ = NSWorkspace.shared.open(url) }
    }
}

/// Reads the text in the photos not read yet, newest first, in the background, with Photos access only. Removed
/// photos leave the index too.
actor PhotoIndexer {
    private let store: PhotoTextStore
    private var running = false

    init(store: PhotoTextStore) { self.store = store }

    func update() async {
        guard !running, hasPhotosAccess() else { return }
        running = true
        defer { running = false }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var all: [(id: String, created: Date?)] = []
        assets.enumerateObjects { asset, _, _ in all.append((asset.localIdentifier, asset.creationDate)) }
        let done = (try? store.ids()) ?? []
        try? store.remove(done.subtracting(all.map(\.id)))
        // ponytail: one photo at a time, a fraction of a second each (plus iCloud downloads); a library of 10,000
        // takes the better part of an hour the first time, then only new photos.
        for photo in all where !done.contains(photo.id) {
            guard !Task.isCancelled else { return }
            // Big enough for a price tag's small print, small enough to read fast.
            guard let image = await photoImage(photo.id, size: 1600, network: true) else { continue } // try again next time
            try? store.add(id: photo.id, created: photo.created, text: recognizedText(in: image))
        }
    }
}

/// Photos with the typed text in them, from 3 characters. Below files found by name, above files with it inside.
struct PhotoTextProvider: ResultProvider {
    let store: PhotoTextStore

    func results(for query: String) async -> [LauncherResult] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3, let hits = try? store.search(text) else { return [] }
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return hits.enumerated().map { index, hit in
            let lines = hit.text.split(whereSeparator: \.isNewline)
            let line = lines.first { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil } ?? lines.first
            let id = hit.id
            return LauncherResult(
                id: "photo:\(id)", title: line.map(String.init) ?? text,
                subtitle: (["Photos"] + [hit.created?.formatted(day)].compactMap { $0 }).joined(separator: " · "),
                accessory: "Text in photo", icon: .image("photo:\(id)") { photoImageNow(id, size: 64) },
                score: -1.5 - Double(index) / 1000, action: { openPhoto(id) },
                preview: "", // the photo, so you see where the text is
                previewImage: { photoImageNow(id, size: 900).map { NSImage(cgImage: $0, size: .zero) } })
        }
    }
}
