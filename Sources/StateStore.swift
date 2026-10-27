import Foundation

/// The only owner of state.json. Each feature reads and writes its own top-level section
/// ("frecency", "windows", …); sections it doesn't know about are kept as-is.
/// Writes are debounced and atomic (temp file + rename).
@MainActor final class StateStore {
    static let shared = StateStore(file: configDir.appending(path: "state.json"))

    private let file: URL
    private var root: [String: Any]
    private var pendingWrite: Task<Void, Never>?

    private static let encoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(file: URL) {
        self.file = file
        guard let data = try? Data(contentsOf: file) else { root = [:]; return }
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            self.root = root
        } else {
            // Unreadable (hand-edit gone wrong?): set it aside rather than overwrite it.
            try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("bad"))
            root = [:]
        }
    }

    func get<T: Decodable>(_ section: String, as type: T.Type) -> T? {
        guard let value = root[section],
              let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }

    func set(_ section: String, _ value: some Encodable) {
        guard let data = try? Self.encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else { return }
        root[section] = object
        pendingWrite?.cancel()
        pendingWrite = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { flush() }
        }
    }

    /// Writes pending changes now. Call on quit.
    func flush() {
        guard pendingWrite != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
