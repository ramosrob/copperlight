import AppKit
import FoundationModels
import OSLog
import UniformTypeIdentifiers

/// What Copperlight knows about an installed app besides its name, so "draw" finds Illustrator and "noise" Krisp.
/// From the app itself: its App Store category, publisher and the documents it opens. Online, unless `[apps] online`
/// is off: Homebrew's one-line description and its homepage's own summary, or the App Store's description for apps
/// installed from it. Then, with Apple Intelligence on, the Mac's on-device model writes what kind of app it is, what
/// people do with it and other words for it. Kept in apps.json and redone when an app's version changes.
struct AppInfo: Codable, Sendable, Equatable {
    var version = ""
    var category: String?
    var publisher: String?
    var opens: [String] = []
    var about: String?
    var site: String? // the homepage's summary: for the model only, too wordy to match on
    var lookedUp = false // online, whether or not it found anything
    var words: [String] = []
    var described = false // by the model

    /// What a search compares against, best first: what it does, then what it is, then what it opens.
    var terms: [(terms: [String], score: Double)] { [(words, 0.8), ([category, about].compactMap { $0 }, 0.78), (opens, 0.75)] }
}

/// What in `info` the words of `query` start words of ("draw" → "draw", "editing" → "edit images"), and a score
/// under a match on the app's own name or other names: 0.8 for what it does, less for what it is or opens, 0.7 when
/// the words are spread over several ("photo editor" → "photo, image editing"). Too-common words ("app") are left out.
func appInfoMatch(_ query: String, _ info: AppInfo) -> (term: String, score: Double)? {
    let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let typed = fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        .filter { $0.count >= 2 && !appStopWords.contains($0) }
    guard query.count >= 3, !typed.isEmpty else { return nil }
    let has = { (term: String, q: String) in
        // ponytail: prefix both ways stands in for stemming ("drawing" → "draw"); NLTagger lemmas if it falls short.
        fold(term).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) || ($0.count >= 4 && q.hasPrefix($0)) }
    }
    for (terms, score) in info.terms {
        if let term = terms.first(where: { term in typed.allSatisfy { has(term, $0) } }) { return (term, score) }
    }
    let all = info.terms.flatMap(\.terms)
    let found = typed.compactMap { q in all.first { has($0, q) } }
    return found.count == typed.count ? (uniqued(found).joined(separator: ", "), 0.7) : nil
}

/// Words that would match half the apps.
private let appStopWords: Set<String> = ["app", "apps", "application", "mac", "macos", "apple", "software", "tool", "tools",
                                         "the", "and", "for", "with", "your", "you"]

// MARK: Reading an app

/// What an app says about itself in its bundle and in Spotlight.
func appFacts(_ path: String) -> AppInfo {
    let plist = Bundle(url: URL(filePath: path))?.infoDictionary ?? [:]
    var info = AppInfo(version: plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "")
    // Spotlight has the App Store's name for it ("Graphics & Design"); the bundle only an id, made readable.
    info.category = NSMetadataItem(url: URL(filePath: path))?.value(forAttribute: "kMDItemAppStoreCategory") as? String
        ?? (plist["LSApplicationCategoryType"] as? String).map {
            $0.replacingOccurrences(of: "public.app-category.", with: "").replacingOccurrences(of: "-", with: " ")
        }
    info.publisher = (plist["NSHumanReadableCopyright"] as? String).flatMap(publisher)
    var types: [String] = []
    for type in plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? [] {
        let ids = type["LSItemContentTypes"] as? [String] ?? []
        types += ids.compactMap { UTType($0)?.localizedDescription }
        if let name = type["CFBundleTypeName"] as? String { types.append(name) }
    }
    info.opens = Array(uniqued(types.filter { !["Folder", "All", "Document"].contains($0) }).prefix(12))
    return info
}

/// "Serif (Europe) Ltd." from "Copyright © 2025 Serif (Europe) Ltd. All rights reserved."
func publisher(_ copyright: String) -> String? {
    var text = copyright.replacingOccurrences(of: #"(?i)copyright|©|\(c\)|all rights reserved\.?|\b\d{4}(\s*[-–]\s*\d{4})?\b,?"#,
                                              with: "", options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: ".)")))
    return text.isEmpty || text.count > 60 ? nil : text
}

/// Installed from the App Store: Apple already knows about it, so asking the App Store tells it nothing new.
func isFromAppStore(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt")
}

// MARK: Online

struct HomebrewApp: Codable, Equatable, Sendable {
    let desc: String
    let homepage: String?
}

/// App file name, lowercased ("krisp.app") → Homebrew's description and homepage, from the public cask list
/// (formulae.brew.sh). The whole list is downloaded, about 19 MB, so the request says nothing about which apps you
/// have; kept for a week.
func homebrewDescriptions(cache: URL = configDir.appending(path: "homebrew-apps.json")) async -> [String: HomebrewApp] {
    let saved = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([String: HomebrewApp].self, from: $0) }
    let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { -$0.timeIntervalSinceNow }
    if let saved, let age, age < 7 * 24 * 3600 { return saved }
    guard let (data, response) = try? await URLSession.shared.data(from: URL(string: "https://formulae.brew.sh/api/cask.json")!),
          (response as? HTTPURLResponse)?.statusCode == 200
    else { return saved ?? [:] }
    let parsed = homebrewDescriptions(caskJSON: data)
    guard !parsed.isEmpty else { return saved ?? [:] }
    try? JSONEncoder().encode(parsed).write(to: cache, options: .atomic)
    return parsed
}

/// The cask list's `desc` and `homepage`, lowercased, by the `.app` each cask installs (`"artifacts": [{"app":
/// ["Krisp.app"]}]`), else by the bundle id it quits on uninstall (`"id:ai.krisp.krispmac"`: apps installed by a
/// .pkg name no .app), else by its name plus ".app".
func homebrewDescriptions(caskJSON: Data) -> [String: HomebrewApp] {
    guard let casks = (try? JSONSerialization.jsonObject(with: caskJSON)) as? [[String: Any]] else { return [:] }
    var apps: [String: HomebrewApp] = [:], ids: [String: HomebrewApp] = [:], names: [String: HomebrewApp] = [:]
    let strings = { (value: Any?) in (value as? [Any] ?? [value as Any]).compactMap { $0 as? String } }
    for cask in casks {
        guard let desc = cask["desc"] as? String, !desc.isEmpty else { continue }
        let entry = HomebrewApp(desc: desc, homepage: cask["homepage"] as? String)
        for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
            for name in strings(artifact["app"]) { apps[name.lowercased()] = entry }
            for uninstall in artifact["uninstall"] as? [[String: Any]] ?? [] {
                for id in strings(uninstall["quit"]) { ids["id:" + id.lowercased()] = entry }
            }
        }
        for name in strings(cask["name"]) { names[name.lowercased() + ".app"] = entry }
    }
    return names.merging(ids) { $1 }.merging(apps) { $1 }
}

/// A web page's own summary of itself (`<meta name="description">`, or `og:description`), at most 300 characters.
func pageDescription(html: String) -> String? {
    let patterns = [#"<meta[^>]+(?:name|property)=["'](?:og:)?description["'][^>]*content=["']([^"']+)"#,
                    #"<meta[^>]+content=["']([^"']+)["'][^>]*(?:name|property)=["'](?:og:)?description"#]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { continue }
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        let text = entities.reduce(String(html[range])) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }
    return nil
}

/// What an app's homepage says it is. As Safari: some sites send other browsers an "unsupported browser" page.
func siteDescription(_ homepage: String) async -> String? {
    guard let url = URL(string: homepage) else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return pageDescription(html: String(decoding: data.prefix(300_000), as: UTF8.self))
}

/// The App Store's description of an app, its first paragraph, by bundle id.
func appStoreDescription(bundleID: String) async -> String? {
    var url = URLComponents(string: "https://itunes.apple.com/lookup")!
    url.queryItems = [.init(name: "bundleId", value: bundleID), .init(name: "entity", value: "macSoftware")]
    struct Lookup: Decodable { struct App: Decodable { let description: String? }; let results: [App] }
    guard let (data, _) = try? await URLSession.shared.data(from: url.url!),
          let text = (try? JSONDecoder().decode(Lookup.self, from: data))?.results.first?.description
    else { return nil }
    return text.split(separator: "\n", omittingEmptySubsequences: true).first.map { String($0.prefix(400)) }
}

// MARK: Apple Intelligence

@available(macOS 26, *)
@Generable struct AppWords {
    @Guide(description: "What kind of app it is, in a few words.")
    var kind: String
    @Guide(description: "Everyday verbs and short phrases for what people do with it.", .maximumCount(10))
    var tasks: [String]
    @Guide(description: "Other words people use for this kind of app or what it works with.", .maximumCount(10))
    var related: [String]
}

private let log = Logger(subsystem: "app.copperlight", category: "apps")

/// Whether the Mac's on-device model can be asked: Apple Intelligence is on, on macOS 26.
func appModelAvailable() -> Bool {
    guard #available(macOS 26, *), case .available = SystemLanguageModel.default.availability else { return false }
    return true
}

/// Words for an app from the Mac's on-device model: nil when it can't answer now (off, or limited: the Mac caps a
/// background app's requests), none when it won't for this app (its guardrails turn some down). One worked example
/// keeps the small model on task; without one it repeated itself or copied the instructions.
func appWords(name: String, _ info: AppInfo) async -> [String]? {
    guard #available(macOS 26, *), appModelAvailable() else { return nil }
    let session = LanguageModelSession(instructions: """
        You write the search index of a Mac app launcher, so people find apps by what they do. Stick to the facts \
        given and what is well known about the app. Example, for Pages (Category: Productivity, opens Word \
        documents): kind: word processor; tasks: write, type a letter, format text, make a flyer, edit documents; \
        related: text editor, word, docs, resume, report.
        """)
    let facts = [name + ".", info.category.map { "Category: \($0)." }, info.publisher.map { "By \($0)." },
                 info.about.map { "Description: \($0)" }, info.site.map { "Its website says: \($0)" }, info.opens.isEmpty ? nil : "Opens: \(info.opens.joined(separator: ", "))."]
    let words: AppWords
    do {
        words = try await session.respond(to: facts.compactMap { $0 }.joined(separator: " "), generating: AppWords.self,
                                          options: GenerationOptions(temperature: 0.3)).content
    } catch {
        log.info("No words for \(name, privacy: .public): \(String(describing: error), privacy: .public)")
        switch error as? LanguageModelSession.GenerationError {
        case .rateLimited, .concurrentRequests, .assetsUnavailable: return nil
        default: return []
        }
    }
    return uniqued(([words.kind] + words.tasks + words.related).map { $0.lowercased() }.filter { !$0.isEmpty && $0 != name.lowercased() })
}

// MARK: The index

/// apps.json, filled in the background: the facts at once, then descriptions, then the model's words, saving and
/// handing the index to search after each step.
actor AppIndex {
    private let file: URL
    private(set) var infos: [String: AppInfo]
    private var updating = false

    init(file: URL = configDir.appending(path: "apps.json")) {
        self.file = file
        infos = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: AppInfo].self, from: $0) } ?? [:]
    }

    /// `apps`: path and name of every installed app. Only new and updated ones are read again.
    func update(_ apps: [(path: String, name: String)], online: Bool, changed: @Sendable ([String: AppInfo]) async -> Void) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        let paths = Set(apps.map(\.path))
        var dirty = infos.keys.contains { !paths.contains($0) }
        infos = infos.filter { paths.contains($0.key) }
        for app in apps {
            let version = Bundle(url: URL(filePath: app.path))?.infoDictionary?["CFBundleShortVersionString"] as? String
            guard infos[app.path] == nil || (version != nil && infos[app.path]?.version != version) else { continue }
            infos[app.path] = appFacts(app.path)
            dirty = true
        }
        if dirty { await save(changed) }

        // Offline (no Homebrew list, saved or downloaded): nothing is marked looked up, so the next update tries again.
        if online, infos.values.contains(where: { !$0.lookedUp }), case let homebrew = await homebrewDescriptions(), !homebrew.isEmpty {
            for (path, info) in infos where !info.lookedUp {
                var info = info
                let id = Bundle(url: URL(filePath: path))?.bundleIdentifier
                let cask = homebrew[(path as NSString).lastPathComponent.lowercased()] ?? id.flatMap { homebrew["id:" + $0.lowercased()] }
                info.about = cask?.desc
                if let homepage = cask?.homepage { info.site = await siteDescription(homepage) }
                if info.about == nil, isFromAppStore(path), let id {
                    info.about = await appStoreDescription(bundleID: id)
                }
                info.lookedUp = true
                infos[path] = info
            }
            await save(changed)
        }

        // One app at a time, a second or two each. The Mac limits how often a background app may ask, so the first
        // run over ~150 apps pauses now and then and takes a while; after that only new and updated apps are asked.
        let names = Dictionary(apps.map { ($0.path, $0.name) }, uniquingKeysWith: { first, _ in first })
        var pending = infos.filter { !$0.value.described && ($0.value.category != nil || $0.value.about != nil) }.map(\.key).sorted()
        var done = 0
        while let path = pending.first, let info = infos[path] {
            guard let words = await appWords(name: names[path] ?? "", info) else {
                guard appModelAvailable() else { break } // off: the next update tries again
                if done > 0 { await save(changed); done = 0 }
                try? await Task.sleep(for: .seconds(120)) // limited: wait, then carry on
                continue
            }
            infos[path]?.words = words
            infos[path]?.described = true
            pending.removeFirst()
            done += 1
            if done % 10 == 0 { await save(changed) }
        }
        if done > 0 { await save(changed) }
    }

    private func save(_ changed: @Sendable ([String: AppInfo]) async -> Void) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(infos).write(to: file, options: .atomic)
        await changed(infos)
    }
}

/// `items` without repeats, in order.
private func uniqued(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { seen.insert($0).inserted }
}
