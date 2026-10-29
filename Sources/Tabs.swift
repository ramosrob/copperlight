import AppKit

/// A tab open in a browser.
struct BrowserTab: Equatable, Sendable {
    var title: String
    var url: String
    var window: String // the window's id, as the browser's AppleScript gives it
    var index: Int // 1-based, in its window
    var browser: String // its bundle id
}

/// The browsers whose tabs AppleScript can list and switch to, by bundle id. Firefox can't.
private enum TabScripting { case chromium, safari, arc }
private let tabBrowsers: [String: TabScripting] = [
    "com.google.Chrome": .chromium, "com.google.Chrome.beta": .chromium, "com.brave.Browser": .chromium,
    "com.microsoft.edgemac": .chromium, "com.vivaldi.Vivaldi": .chromium, "org.chromium.Chromium": .chromium,
    "company.thebrowser.Browser": .arc, "com.apple.Safari": .safari,
]

/// Lists every tab of every window but private ones, a tab a record (character 30), its window, place, title and
/// address a field each (character 31). A window that won't say is skipped.
private func listScript(_ bundleID: String) -> String {
    """
    tell application id "\(bundleID)"
        set out to {}
        repeat with w in windows
            try
                set skip to false
                try
                    if mode of w is "incognito" then set skip to true
                end try
                try
                    if incognito of w then set skip to true
                end try
                if not skip then
                    set wid to (id of w) as text
                    set titles to \(tabBrowsers[bundleID] == .safari ? "name" : "title") of tabs of w
                    set urls to URL of tabs of w
                    repeat with i from 1 to count of titles
                        set end of out to wid & (character id 31) & i & (character id 31) & (item i of titles) & (character id 31) & (item i of urls)
                    end repeat
                end if
            end try
        end repeat
        set AppleScript's text item delimiters to (character id 30)
        return out as text
    end tell
    """
}

/// `listScript`'s output, read back.
func parseTabs(_ output: String, browser: String) -> [BrowserTab] {
    output.trimmingCharacters(in: .newlines).split(separator: "\u{1E}").compactMap { record in
        let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, let index = Int(fields[1]) else { return nil }
        return BrowserTab(title: fields[2], url: fields[3], window: fields[0], index: index, browser: browser)
    }
}

/// Brings the tab's window forward with the tab showing. nil for a window id that isn't one (it goes in the script).
func switchScript(_ tab: BrowserTab) -> String? {
    guard let scripting = tabBrowsers[tab.browser], !tab.window.isEmpty,
          tab.window.allSatisfy({ scripting == .arc ? $0.isLetter || $0.isNumber || $0 == "-" : $0.isNumber }) else { return nil }
    return switch scripting {
    case .chromium: """
        tell application id "\(tab.browser)"
            set w to first window whose id is \(tab.window)
            set active tab index of w to \(tab.index)
            set index of w to 1
            activate
        end tell
        """
    case .safari: """
        tell application id "\(tab.browser)"
            set w to first window whose id is \(tab.window)
            set current tab of w to tab \(tab.index) of w
            set index of w to 1
            activate
        end tell
        """
    case .arc: """
        tell application id "\(tab.browser)"
            tell (first window whose id is "\(tab.window)") to tell tab \(tab.index) to select
            activate
        end tell
        """
    }
}

/// Whether Copperlight may control the app: `noErr` yes, `errAEEventWouldRequireUserConsent` not asked yet. With
/// `ask`, macOS asks, and this waits for the answer.
func automationPermission(_ bundleID: String, ask: Bool) -> OSStatus {
    AEDeterminePermissionToAutomateTarget(NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc, typeWildCard, typeWildCard, ask)
}

/// What a look at the browsers found.
private struct OpenTabs: Sendable {
    var tabs: [BrowserTab] = [] { didSet { keys = tabs.map { wordStarts($0.title + " " + $0.url) } } }
    var keys: [String] = []
    var apps: [String: URL] = [:] // bundle id → the app, for its icon and name
    var unasked: [String] = [] // running browsers Copperlight hasn't asked to control yet
}

/// The tabs open in the running browsers (Chrome, Brave, Edge, Vivaldi, Arc, Safari), found like bookmarks: every word
/// typed starts a word of the title or the address, from 2 letters, ranked just above them. Enter switches to the tab
/// instead of opening the page again. `tabs` ⇥ is the Tabs chip, every tab. Read through AppleScript when the launcher
/// opens, from the browsers Copperlight may control (asked from the chip, once per browser), kept in memory only.
actor BrowserTabsProvider: ResultProvider {
    static let prefix = "tabs "
    private var open: Task<OpenTabs, Never>

    init() { open = Task { OpenTabs() } }

    /// Tests: these tabs, from these apps.
    init(tabs: [BrowserTab], apps: [String: URL]) {
        var found = OpenTabs(apps: apps)
        found.tabs = tabs
        open = Task { [found] in found }
    }

    nonisolated var modes: [Mode] {
        [Mode(prefix: Self.prefix, title: "Tabs", icon: .symbol("square.on.square"), hint: "A word in its title or address, or nothing for all")]
    }

    /// Reads the tabs again: each time the launcher opens, a moment's work in the background that the first search waits for.
    func refresh() {
        open = Task.detached(priority: .userInitiated) {
            var found = OpenTabs()
            let running = NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleIdentifier.flatMap { tabBrowsers[$0] == nil ? nil : ($0, app.bundleURL) }
            }
            for (id, app) in running {
                found.apps[id] = app
                switch automationPermission(id, ask: false) {
                case noErr:
                    let run = await runTool(URL(filePath: "/usr/bin/osascript"), ["-e", listScript(id)], timeout: 3)
                    found.tabs += parseTabs(run.output, browser: id)
                case OSStatus(errAEEventWouldRequireUserConsent): found.unasked.append(id)
                default: break // said no: System Settings › Privacy & Security › Automation
                }
            }
            return found
        }
    }

    private func name(_ id: String, in found: OpenTabs) -> String {
        found.apps[id].map { FileManager.default.displayName(atPath: $0.path).replacing(".app", with: "") } ?? id
    }

    private func row(_ tab: BrowserTab, found: OpenTabs, score: Double) -> LauncherResult {
        let browsers = Set(found.tabs.map(\.browser)).count
        let script = switchScript(tab)
        return LauncherResult(id: "tab:\(tab.browser):\(tab.url)", title: tab.title.isEmpty ? tab.url : tab.title,
                              subtitle: ([URL(string: tab.url)?.host() ?? tab.url, "Tab"] + (browsers > 1 ? [name(tab.browser, in: found)] : []))
                                .joined(separator: " · "),
                              icon: found.apps[tab.browser].map { .file($0.path) } ?? .symbol("square.on.square"), score: score,
                              actionTitle: "Switch to Tab", action: { if let script { osascript(script, label: "Switch to Tab") } })
    }

    private func matching(_ query: String, in found: OpenTabs) -> [BrowserTab] {
        let words = typedWords(query)
        return zip(found.tabs, found.keys).filter { _, key in words.allSatisfy { key.contains($0) } }.map(\.0)
    }

    func results(for query: String) async -> [LauncherResult] {
        let found = await open.value
        guard !Task.isCancelled else { return [] }
        let lower = query.lowercased()
        var rows: [LauncherResult] = []
        if lower.count >= 4, "tabs".hasPrefix(lower) || "browser tabs".hasPrefix(lower) || "open tabs".hasPrefix(lower) {
            rows.append(LauncherResult(id: "builtin:tabs", title: "Browser Tabs", subtitle: "Every tab open in your browsers",
                                       icon: .symbol("square.on.square"), score: 50, actionTitle: "List", action: {}, completion: Self.prefix))
        }
        guard query.count >= 2 else { return rows }
        return rows + matching(query, in: found).prefix(4).enumerated().map { row($1, found: found, score: 0.4 - Double($0) / 100) }
    }

    /// In the chip: a row asking each browser not asked yet, then every tab, in window order.
    func modeResults(for query: String) async -> [LauncherResult] {
        let found = await open.value
        let text = query.dropFirst(Self.prefix.count - 1).trimmingCharacters(in: .whitespaces)
        let asks = found.unasked.map { id in
            LauncherResult(id: "tabs:ask:\(id)", title: "See \(name(id, in: found))’s Tabs", subtitle: "Asks to control it, once",
                           icon: found.apps[id].map { .file($0.path) } ?? .symbol("square.on.square"), score: 51, actionTitle: "Allow", action: {
                Task.detached {
                    guard automationPermission(id, ask: true) == noErr else { return }
                    await MainActor.run { notify("Type “tabs” again to see them") }
                }
            })
        }
        let tabs = text.isEmpty ? found.tabs : matching(text, in: found)
        guard !tabs.isEmpty || !asks.isEmpty else {
            return [LauncherResult(id: "tabs:none", title: text.isEmpty ? "No tabs open" : "No tab says “\(text)”",
                                   subtitle: "Chrome, Brave, Edge, Vivaldi, Arc and Safari", icon: .symbol("square.on.square"),
                                   score: 50, actionTitle: "", action: {})]
        }
        return asks + tabs.enumerated().map { row($1, found: found, score: 50 - Double($0) / 10_000) }
    }
}
