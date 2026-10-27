import AppKit
import UserNotifications

/// An exact alias match (ignoring case) ranks above everything; otherwise fuzzy, a bit ahead of apps.
func aliasScore(_ query: String, _ alias: String) -> Double? {
    if query.caseInsensitiveCompare(alias) == .orderedSame { return 100 }
    return fuzzyScore(query, alias).map { $0 + 0.5 }
}

/// A Chromium browser's profiles, from its `Local State` JSON (`profile.info_cache`): the folder ("Profile 1") and
/// the name the browser shows ("Work").
func chromiumProfiles(localState: Data) -> [(directory: String, name: String)] {
    struct LocalState: Decodable {
        struct Profiles: Decodable {
            let infoCache: [String: Info]
            private enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
        }
        struct Info: Decodable { let name: String }
        let profile: Profiles
    }
    let cache = (try? JSONDecoder().decode(LocalState.self, from: localState))?.profile.infoCache ?? [:]
    return cache.map { ($0.key, $0.value.name) }.sorted { $0.directory < $1.directory }
}

/// The profile directory for a Chromium browser's profile given by display name or by directory name.
func chromiumProfileDirectory(_ profile: String, localState: Data) -> String? {
    let profiles = chromiumProfiles(localState: localState)
    let same = { (a: String) in a.caseInsensitiveCompare(profile) == .orderedSame }
    return profiles.first { same($0.name) }?.directory ?? profiles.first { same($0.directory) }?.directory
}

/// "github.com/x", "https://x.com", "localhost:3000" as a URL to open; nil for anything else.
/// ponytail: a bare "name.tld" counts only for the TLDs below, so file names (readme.md, logo.ai,
/// lib.so) don't look like sites; add TLDs when one is missed.
func webURL(_ text: String) -> URL? {
    guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
    if text.contains("://") { return URL(string: text).flatMap { $0.host() != nil ? $0 : nil } }
    guard !text.contains("@"), // an email address, not a site
          var url = URLComponents(string: "https://" + text), let host = url.host?.lowercased()
    else { return nil }
    if host == "localhost" { url.scheme = "http" } // dev servers rarely have TLS
    else if !host.contains(".") || !commonTLDs.contains(String(host.split(separator: ".").last ?? "")) { return nil }
    return url.url
}

private let commonTLDs: Set<String> = [
    "com", "org", "net", "io", "dev", "app", "co", "me", "gg", "tv", "ly", "to", "xyz", "info", "edu", "gov",
    "eu", "uk", "de", "fr", "es", "pt", "br", "us", "ca",
]

/// `text` safe to put anywhere in a URL: everything but RFC 3986's unreserved characters is escaped.
func percentEncoded(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
}

func googleSearchURL(_ query: String) -> URL {
    URL(string: "https://www.google.com/search?q=" + percentEncoded(query))!
}

/// The text after a command's alias ("gh copperlight" → "copperlight") when its URL takes `{query}`; nil otherwise.
func queryText(_ query: String, for command: Config.Command) -> String? {
    guard case .url(let url, _, _) = command.action, url.contains("{query}"),
          let alias = query.range(of: command.alias + " ", options: [.caseInsensitive, .anchored]) else { return nil }
    return query[alias.upperBound...].trimmingCharacters(in: .whitespaces)
}

/// The browser app: `browser` is an app name ("Firefox") or bundle id, nil for the default browser.
func browserApp(_ browser: String?) -> URL? {
    guard let browser else { return NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser)
        ?? ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(filePath: "\($0)/\(browser).app") }.first { FileManager.default.fileExists(atPath: $0.path) }
}

/// Opens `url` where `[browser]` says (a Meet link or a pull request in the work profile); without it, or for links
/// that aren't web pages (zoommtg:), wherever macOS sends them.
func webOpener(_ url: URL, browser: Config.Browser) -> @MainActor @Sendable () -> Void {
    if browser.name != nil || browser.profile != nil, case .success(let (via, arguments)) =
        browserOpening(url.absoluteString, browser: browser.name, profile: browser.profile) {
        return { runDetached("/usr/bin/open", arguments, label: via) }
    }
    return { _ = NSWorkspace.shared.open(url) }
}

/// The `open` arguments that show `url` in the browser `app`, in `profile` when given, with a label for the
/// row ("Firefox", "Google Chrome: Work"); or why it can't be done. Chromium browsers name profiles in
/// `Local State` and take the folder; Firefox takes the name.
func openArguments(_ url: String, in app: URL, profile: String?) -> Result<(via: String, arguments: [String]), BrowserError> {
    let name = app.deletingPathExtension().lastPathComponent
    guard let profile else { return .success((name, ["-a", app.path, url])) }
    let bundleID = Bundle(url: app)?.bundleIdentifier ?? ""
    if let folder = chromiumFolders[bundleID] {
        // ponytail: reads Local State on every matching keystroke; cache by mtime if it ever feels slow.
        let localState = URL.applicationSupportDirectory.appending(path: "\(folder)/Local State")
        guard let data = try? Data(contentsOf: localState), let directory = chromiumProfileDirectory(profile, localState: data)
        else { return .failure(BrowserError(message: "unknown \(name) profile \"\(profile)\"")) }
        return .success(("\(name): \(profile)", ["-na", app.path, "--args", "--profile-directory=\(directory)", url]))
    }
    // ponytail: no check that the profile exists; Firefox shows its profile manager for a name it doesn't know.
    if bundleID == "org.mozilla.firefox" { return .success(("\(name): \(profile)", ["-na", app.path, "--args", "-P", profile, url])) }
    return .failure(BrowserError(message: "\(name) can't be opened in a profile"))
}

struct BrowserError: Error { let message: String }

/// `openArguments` in `browser` (nil: the default one).
func browserOpening(_ url: String, browser: String?, profile: String?) -> Result<(via: String, arguments: [String]), BrowserError> {
    browserApp(browser).map { openArguments(url, in: $0, profile: profile) }
        ?? .failure(BrowserError(message: browser.map { "no browser named \"\($0)\"" } ?? "no default browser"))
}

/// Where each Chromium browser keeps its `Local State`, under ~/Library/Application Support.
let chromiumFolders = [
    "com.google.Chrome": "Google/Chrome", "com.brave.Browser": "BraveSoftware/Brave-Browser",
    "com.microsoft.edgemac": "Microsoft Edge", "com.vivaldi.Vivaldi": "Vivaldi", "org.chromium.Chromium": "Chromium",
]

/// Fallback rows: "Open …" when the query looks like a URL, and "Search Google for …" always, last,
/// so it's what Enter does when nothing else matches. Both open where `[browser]` says.
actor WebProvider: ResultProvider {
    private var browser = Config.Browser()

    func setBrowser(_ browser: Config.Browser) { self.browser = browser }

    func results(for query: String) -> [LauncherResult] {
        let search = opener(googleSearchURL(query))
        var rows = [LauncherResult(
            id: "web:google", title: "Search Google for “\(query)”", subtitle: search.via,
            icon: .symbol("magnifyingglass"), score: -10, actionTitle: "Search", action: search.open)]
        if let url = webURL(query) {
            let site = opener(url)
            rows.append(LauncherResult(
                id: "web:open", title: "Open \(query)", subtitle: ([url.absoluteString] + (site.via.isEmpty ? [] : [site.via])).joined(separator: " · "),
                icon: .symbol("globe"), score: 10, actionTitle: "Open in Browser", action: site.open))
        }
        return rows
    }

    /// Opens `url` in `[browser]`, labeled "Google Chrome: Work"; unset, in the default browser, unlabeled. When its
    /// browser or profile can't be used, the default browser opens it anyway and the label says why.
    private func opener(_ url: URL) -> (via: String, open: @MainActor @Sendable () -> Void) {
        let fallback: @MainActor @Sendable () -> Void = { _ = NSWorkspace.shared.open(url) }
        guard browser.name != nil || browser.profile != nil else { return ("", fallback) }
        switch browserOpening(url.absoluteString, browser: browser.name, profile: browser.profile) {
        case .success(let (via, arguments)): return (via, { runDetached("/usr/bin/open", arguments, label: via) })
        case .failure(let error): return ("\(error.message), so the default browser", fallback)
        }
    }
}

/// The `[[command]]` entries from config.toml.
actor CommandProvider: ResultProvider {
    private var commands: [Config.Command] = []
    private var browser = Config.Browser()

    /// `browser`: where web links go when a command doesn't say.
    func setCommands(_ commands: [Config.Command], browser: Config.Browser = .init()) {
        self.commands = commands
        self.browser = browser
    }

    func results(for query: String) -> [LauncherResult] {
        commands.compactMap { command in
            if let text = queryText(query, for: command) { return row(command, text: text, score: 100) }
            return aliasScore(query, command.alias).map { row(command, text: "", score: $0) }
        }
    }

    private func row(_ command: Config.Command, text: String, score: Double) -> LauncherResult {
        let alias = command.alias
        let id = "command:\(alias)"
        switch command.action {
        case .url(let template, var browser, var profile):
            let url = template.replacingOccurrences(of: "{query}", with: percentEncoded(text))
            let title = text.isEmpty ? alias : "\(alias) \(text)"
            if browser == nil, profile == nil, url.hasPrefix("https://") || url.hasPrefix("http://") {
                (browser, profile) = (self.browser.name, self.browser.profile) // a web link without its own: [browser]
            }
            guard browser != nil || profile != nil else { // any scheme (slack://, obsidian://) goes to its own app
                return LauncherResult(id: id, title: title, subtitle: url, icon: .symbol("link"), score: score, action: {
                    if let link = URL(string: url), NSWorkspace.shared.open(link) { return }
                    notify("\(alias): can't open \(url)")
                })
            }
            switch browserOpening(url, browser: browser, profile: profile) {
            case .failure(let error):
                return LauncherResult(id: id, title: "\(alias): \(error.message)", subtitle: "Check browser and profile",
                                      icon: .symbol("exclamationmark.triangle"), score: score,
                                      actionTitle: "Open config.toml", action: { NSWorkspace.shared.open(Config.file) })
            case .success(let (via, arguments)):
                return LauncherResult(id: id, title: title, subtitle: "\(url) · \(via)",
                                      icon: .symbol("link"), score: score, action: {
                    runDetached("/usr/bin/open", arguments, label: alias)
                })
            }
        case .app(let app):
            return LauncherResult(id: id, title: alias, subtitle: app, icon: .symbol("app"), score: score, action: {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                } else {
                    runDetached("/usr/bin/open", ["-a", app], label: alias) // by name; fails visibly if unknown
                }
            })
        case .file(let path):
            let expanded = NSString(string: path).expandingTildeInPath
            return LauncherResult(id: id, title: alias, subtitle: path, icon: .file(expanded), score: score, action: {
                if !NSWorkspace.shared.open(URL(filePath: expanded)) { notify("\(alias): can't open \(path)") }
            })
        case .shell(let script):
            return LauncherResult(id: id, title: alias, subtitle: script, icon: .symbol("terminal"),
                                  score: score, actionTitle: "Run", action: {
                runDetached("/bin/zsh", ["-lc", script], label: alias)
            })
        }
    }
}

/// Starts a program without waiting for it. A non-zero exit posts a notification with the last
/// lines of stderr. stderr goes to a temp file, not a pipe, so a daemonized child that keeps it
/// open can't block anything.
@MainActor func runDetached(_ executable: String, _ arguments: [String], label: String) {
    let log = FileManager.default.temporaryDirectory.appending(path: "copperlight-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = .homeDirectory
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = try? FileHandle(forWritingTo: log)
    process.terminationHandler = { process in
        let status = process.terminationStatus
        let stderr = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: log)
        guard status != 0 else { return }
        let tail = stderr.split(separator: "\n").suffix(5).joined(separator: "\n")
        Task { @MainActor in notify("\(label) failed (exit \(status))", tail) }
    }
    do {
        try process.run()
    } catch {
        try? FileManager.default.removeItem(at: log)
        notify("\(label) failed to start", error.localizedDescription)
    }
}

/// `sound`: with the default sound; if notifications aren't allowed, the sound plays anyway.
@MainActor func notify(_ title: String, _ body: String = "", sound: Bool = false) {
    Task {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            if sound { NSSound(named: "Glass")?.play() }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
