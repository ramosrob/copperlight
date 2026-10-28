import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import Testing
@testable import Copperlight
import GRDB
import Synchronization

// MARK: Fuzzy matcher

@Test func fuzzyMatchesSubsequencesIgnoringCaseAndAccents() {
    #expect(fuzzyScore("saf", "Safari") != nil)
    #expect(fuzzyScore("SAF", "safari") != nil)
    #expect(fuzzyScore("cafe", "Café") != nil)
    #expect(fuzzyScore("vs code", "Visual Studio Code") != nil)
    #expect(fuzzyScore("xyz", "Safari") == nil)
    #expect(fuzzyScore("safarii", "Safari") == nil)
    #expect(fuzzyScore("", "Safari") == nil)
    #expect(fuzzyScore("fas", "Safari") == nil) // order matters
}

@Test func fuzzyRanksBetterMatchesHigher() {
    func score(_ q: String, _ t: String) -> Double { fuzzyScore(q, t) ?? -1 }
    #expect(score("safari", "Safari") > score("safari", "Safari Technology Preview"))
    #expect(score("code", "Visual Studio Code") > score("code", "Xcode"))
    #expect(score("vsc", "Visual Studio Code") > score("vsc", "Avast Security")) // word starts beat scattered
    #expect(score("term", "Terminal") > score("term", "Remote Terminal Manager"))
    #expect(score("ff", "Firefox") > score("ff", "Microsoft Office"))
    #expect(score("chr", "Google Chrome") > score("chr", "Character Viewer"))
    #expect(score("saf", "Safari") > 0.9)
}

// MARK: Calculator

@Test(arguments: [
    ("2+3*4", 14.0), ("(1 + 2) / 4", 0.75), ("2^10", 1024), ("sqrt(16)", 4),
    ("-3 + 1", -2), ("10 % 3", 1), ("0.1 + 0.2", 0.1 + 0.2), ("2 * pi", 2 * Double.pi),
    ("20% of 150", 30), ("150 + 20%", 180), ("150 - 20%", 120), ("10 - 5 + 20%", 6), ("0xff + 1", 256), ("0b1010 * 2", 20),
])
func calculatorEvaluatesMath(_ input: String, _ expected: Double) {
    #expect(calculate(input) == expected)
}

@Test(arguments: [
    "", "  ", "42", "-5", "3.14", "1e3", "pi", "safari", "2+", "(", ")(", "2 +* 3", "sqrt(", "sqrt()",
    "1/0", "0/0", "9^9999", "foo(1)", "x + 1", "25 usd to eur", "1,5+2", "[1]", "2 ? 3 : 4", "%%%",
    "((((((((((1))))))))))", "1..2", "\"a\"", "'", "\\", "😀+1",
    "x 2()", "1 2()", "x 2( )", "s 0()1^7b", // crashed Expression 0.13.9
])
func calculatorRejectsNonMath(_ input: String) {
    #expect(calculate(input) == nil)
}

@Test func calculatorExtras() {
    #expect(calculate("ans * 2", ans: 21) == 42)
    #expect(calculate("ans * 2") == nil) // nothing taken yet
    #expect(calculate("0xff") == nil && calculate("20%") == nil)
    #expect(convertBase("255 in hex") == "0xFF")
    #expect(convertBase("0xff in dec") == "255")
    #expect(convertBase("(2^8 - 1) to binary") == "0b11111111")
    #expect(convertBase("-10 in hex") == "-0xA")
    #expect(convertBase("0xff") == "255" && convertBase("0b1010") == "10")
    #expect(convertBase("ans in hex", ans: 16) == "0x10")
    #expect(convertBase("1.5 in hex") == nil && convertBase("255") == nil && convertBase("10 km in mi") == nil)
}

@Test func calculatorSurvivesRandomInput() {
    let alphabet = Array("0123456789+-*/%^()., abcpisqrtxof[]?:!=<>&|\"'\\")
    for _ in 0..<5000 {
        let input = String((0..<Int.random(in: 0...12)).map { _ in alphabet.randomElement()! })
        if let value = calculate(input) { #expect(value.isFinite) }
    }
}

@Test func numberFormatting() {
    #expect(formatNumber(0.1 + 0.2) == "0.3")
    #expect(formatNumber(1_000_000) == "1000000")
    #expect(formatNumber(-2.5) == "-2.5")
    #expect(formatNumber(22.314, decimals: 2...2) == "22.31")
    #expect(formatNumber(5, decimals: 2...2) == "5.00")
}

// MARK: Currency

@Test(arguments: [
    ("25USD to EUR", CurrencyQuery(amount: 25, from: "USD", to: "EUR")),
    ("25 usd in eur", CurrencyQuery(amount: 25, from: "USD", to: "EUR")),
    ("25usd eur", CurrencyQuery(amount: 25, from: "USD", to: "EUR")),
    ("12,50 gbp to usd", CurrencyQuery(amount: 12.5, from: "GBP", to: "USD")),
    ("12.5 GBP USD", CurrencyQuery(amount: 12.5, from: "GBP", to: "USD")),
    ("  100 Jpy   TO  brl ", CurrencyQuery(amount: 100, from: "JPY", to: "BRL")),
    ("25 usd inr", CurrencyQuery(amount: 25, from: "USD", to: "INR")), // INR, not "in r"
    ("25 usd to try", CurrencyQuery(amount: 25, from: "USD", to: "TRY")),
    ("25 usd", CurrencyQuery(amount: 25, from: "USD", to: "EUR")), // no target → default
    ("25usd", CurrencyQuery(amount: 25, from: "USD", to: "EUR")),
])
func currencyParses(_ input: String, _ expected: CurrencyQuery) {
    #expect(parseCurrency(input) == expected)
}

@Test(arguments: [
    "", "25", "usd to eur", "25 us", "25 usd to", "25 usd in", "25 dollars to eur", "25 usd eur extra",
    "1.2.3 usd eur", "25 usd toeur", "25usdeur", ".5 usd eur", "25. usd eur", "-25 usd eur", "2+2",
])
func currencyRejects(_ input: String) {
    #expect(parseCurrency(input) == nil)
}

@Test func currencyConverts() {
    let rates = ["EUR": 1, "USD": 1.25, "GBP": 0.8]
    #expect(convert(CurrencyQuery(amount: 25, from: "USD", to: "EUR"), rates: rates) == 20)
    #expect(convert(CurrencyQuery(amount: 8, from: "GBP", to: "USD"), rates: rates) == 12.5)
    #expect(convert(CurrencyQuery(amount: 5, from: "EUR", to: "EUR"), rates: rates) == 5)
    #expect(convert(CurrencyQuery(amount: 1, from: "XYZ", to: "EUR"), rates: rates) == nil)
}

// MARK: Search merging

private struct Echo: ResultProvider {
    let delay: Duration
    func results(for query: String) async -> [LauncherResult] {
        try? await Task.sleep(for: delay)
        return [LauncherResult(id: "\(delay)", title: query, icon: .symbol("circle"), score: 1, action: {})]
    }
}

@MainActor @Test func rowsShowTogetherAndSlowOnesMergeLater() async throws {
    let model = SearchModel(providers: [Echo(delay: .seconds(1)), Echo(delay: .zero), Fixed(rows: [])])
    model.query = "a"
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.results.map(\.title) == ["a"]) // the wait is over: fast rows shown, the slow provider still running

    model.query = "ab" // cancels the round for "a"
    try await Task.sleep(for: .milliseconds(10))
    #expect(model.settling && model.results.map(\.title) == ["a"]) // not emptied by the provider with nothing to say
    try await Task.sleep(for: .milliseconds(200))
    #expect(!model.settling && model.results.map(\.title) == ["ab"])
    try await Task.sleep(for: .milliseconds(1300))
    #expect(model.results.map(\.title) == ["ab", "ab"]) // the slow one merged in

    let slow = SearchModel(providers: [Echo(delay: .milliseconds(300))])
    slow.query = "a"
    try await Task.sleep(for: .milliseconds(500))
    slow.query = "ab"
    try await Task.sleep(for: .milliseconds(150)) // the wait is over with nothing in: the rows for "a" stay
    #expect(slow.settling && slow.results.map(\.title) == ["a"])
}

/// Rows named after the query; Enter on one records that name.
@MainActor private final class Typed: ResultProvider {
    var ran: [String] = []
    nonisolated func results(for query: String) async -> [LauncherResult] {
        [LauncherResult(id: query, title: query, icon: .symbol("circle"), score: 1, action: { [weak self] in self?.ran.append(query) })]
    }
}

@MainActor @Test func enterRunsWhatWasJustTyped() async throws {
    let typed = Typed()
    let model = SearchModel(providers: [typed, Echo(delay: .seconds(1))]) // the slow one holds the rows for the wait
    let panel = LauncherPanel(model: model, placeholder: "…")
    model.query = "sa"
    try await Task.sleep(for: .milliseconds(200))
    model.query = "saf" // Enter right away, while the list still shows the rows for "sa"
    panel.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                                    isARepeat: false, keyCode: 36)))
    #expect(typed.ran.isEmpty)
    try await Task.sleep(for: .milliseconds(200))
    #expect(typed.ran == ["saf"])
}

private struct Fixed: ResultProvider {
    let rows: [(id: String, score: Double)]
    func results(for query: String) async -> [LauncherResult] {
        rows.map { LauncherResult(id: $0.id, title: $0.id, icon: .symbol("circle"), score: $0.score, action: {}) }
    }
}

@MainActor @Test func pickedRowsRise() async throws {
    let store = StateStore(file: try tempStateFile())
    let rows = Fixed(rows: [("a", 1), ("b", 0.95)])
    let model = SearchModel(providers: [rows], frecency: store)
    model.query = "x"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.id) == ["a", "b"])
    model.picked("b")
    model.query = "y"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.id) == ["b", "a"]) // 0.95 + 0.1 for one pick
    #expect(store.get(Frecency.stateSection, as: Frecency.Table.self)?["b"]?.score == 1)

    let clipboard = SearchModel(providers: [rows]) // no store: keeps its order
    clipboard.picked("b")
    clipboard.query = "x"
    try await Task.sleep(for: .milliseconds(100))
    #expect(clipboard.results.map(\.id) == ["a", "b"])
}

@Test func frecencyDecaysAndForgets() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000), week: TimeInterval = 7 * 24 * 3600
    let table: Frecency.Table = ["old": Frecency(score: 1, updated: now - 5 * week), "recent": Frecency(score: 2, updated: now - week)]
    #expect(Frecency.bonus(table, "recent", at: now) == 0.1) // 2, halved once
    #expect(Frecency.bonus(table, "never", at: now) == 0)
    #expect(Frecency.bonus(["x": Frecency(score: 50, updated: now)], "x", at: now) == 0.5) // capped
    let picked = Frecency.picking("recent", in: table, at: now)
    #expect(picked.keys.sorted() == ["recent"]) // "old" has 1/32 left: forgotten
    #expect(picked["recent"]?.score == 2 && picked["recent"]?.updated == now)
}

@Test func currencyDefaultTarget() {
    #expect(parseCurrency("25 eur")?.to == "USD") // source is the default → USD
    #expect(parseCurrency("25 usd", defaultTarget: "GBP")?.to == "GBP")
    #expect(parseCurrency("25 gbp", defaultTarget: "GBP")?.to == "USD")
    #expect(parseCurrency("25 usd", defaultTarget: "USD")?.to == "EUR") // default is USD itself
    #expect(parseCurrency("25 usd to jpy", defaultTarget: "GBP")?.to == "JPY") // explicit target wins
}

// MARK: State store

@MainActor private func tempStateFile(_ json: String? = nil) throws -> URL {
    let file = FileManager.default.temporaryDirectory.appending(path: "copperlight-test-\(UUID().uuidString)/state.json")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let json { try json.write(to: file, atomically: true, encoding: .utf8) }
    return file
}

@MainActor @Test func stateSectionsDontOverwriteEachOther() throws {
    let file = try tempStateFile()
    let store = StateStore(file: file)
    store.set("frecency", ["/Applications/Safari.app": Frecency(score: 2, updated: .now)])
    store.set("windows", ["note": CGRect(x: 10, y: 20, width: 300, height: 200)])
    store.set("frecency", ["/Applications/Xcode.app": Frecency(score: 1, updated: .now)])
    store.flush()

    let reloaded = StateStore(file: file)
    #expect(reloaded.get("windows", as: [String: CGRect].self)?["note"] == CGRect(x: 10, y: 20, width: 300, height: 200))
    #expect(reloaded.get("frecency", as: Frecency.Table.self)?.keys.sorted() == ["/Applications/Xcode.app"])
}

@MainActor @Test func stateKeepsUnknownSections() throws {
    let file = try tempStateFile(#"{"pomodoro": {"running": true, "ends": "2026-10-12T10:00:00Z"}, "frecency": {}}"#)
    let store = StateStore(file: file)
    store.set("windows", ["note": CGRect(x: 0, y: 0, width: 1, height: 1)])
    store.flush()

    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
    let pomodoro = json?["pomodoro"] as? [String: Any]
    #expect(pomodoro?["running"] as? Bool == true)
    #expect(pomodoro?["ends"] as? String == "2026-10-12T10:00:00Z")
    #expect(json?["windows"] != nil)
}

@MainActor @Test func stateWritesAreDebounced() async throws {
    let file = try tempStateFile()
    let store = StateStore(file: file)
    store.set("windows", ["note": CGRect.zero])
    #expect(!FileManager.default.fileExists(atPath: file.path))
    try await Task.sleep(for: .milliseconds(1500))
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@MainActor @Test func stateReadsMilestone1File() throws {
    // Byte-for-byte what M1's AppProvider wrote (JSONEncoder: pretty, sorted, ISO 8601, escaped slashes).
    let file = try tempStateFile(#"""
        {
          "frecency" : {
            "\/Applications\/Safari.app" : {
              "score" : 3.5,
              "updated" : "2026-10-01T09:30:00Z"
            }
          }
        }
        """#)
    let frecency = StateStore(file: file).get(Frecency.stateSection, as: Frecency.Table.self)
    #expect(frecency?["/Applications/Safari.app"]?.score == 3.5)
    #expect(frecency?["/Applications/Safari.app"]?.updated == ISO8601DateFormatter().date(from: "2026-10-01T09:30:00Z"))
}

@MainActor @Test func stateSetsAsideAnUnreadableFile() throws {
    let file = try tempStateFile("{ not json")
    #expect(StateStore(file: file).get("frecency", as: Frecency.Table.self) == nil)
    #expect(FileManager.default.fileExists(atPath: file.path + ".bad"))
}

// MARK: Config

@Test func configParsesAFullFile() throws {
    let config = try Config.parse("""
        [hotkeys]
        launcher = "cmd+shift+space"
        clipboard = "cmd+shift+v"    # hotkeys older configs had: ignored now
        note = "ctrl+option+n"

        [currency]
        default_target = "brl"

        [clipboard]
        ignore_apps = ["com.example.vault"]
        max_items = 50
        max_days = 7

        [files]
        scopes = ["~/code"]
        exclude = ["build"]

        [pomodoro]
        default_minutes = 50

        [browser]
        name = "Google Chrome"
        profile = "Personal"

        [future]                     # sections the app doesn't know are ignored
        x = 1

        [[command]]
        alias = "github"
        type = "url"
        url = "https://github.com"
        browser = "Google Chrome"
        profile = "Work"

        [[command]]
        alias = "docs"
        type = "url"
        url = "https://developer.apple.com"

        [[command]]
        alias = "slack"
        type = "app"
        app = "com.tinyspeck.slackmacgap"

        [[command]]
        alias = "budget"
        type = "file"
        path = "~/Documents/cashflow.xlsx"

        [[command]]
        alias = "dev"
        type = "shell"
        run = "cd ~/code/api && docker compose up -d"
        """)
    #expect(config.hotkeys.launcher == Hotkey(keyCode: kVK_Space, modifiers: [.command, .shift]))
    #expect(config.currency.defaultTarget == "BRL")
    #expect(config.files.scopes == ["~/code"] && config.files.exclude == ["build"])
    #expect(config.pomodoro.defaultMinutes == 50)
    #expect(config.browser == Config.Browser(name: "Google Chrome", profile: "Personal"))
    #expect(config.clipboard == {
        var c = Config.Clipboard()
        (c.ignoreApps, c.maxItems, c.maxDays) = (["com.example.vault"], 50, 7)
        return c
    }())
    #expect(config.commands == [
        .init(alias: "github", action: .url("https://github.com", browser: "Google Chrome", profile: "Work")),
        .init(alias: "docs", action: .url("https://developer.apple.com", browser: nil, profile: nil)),
        .init(alias: "slack", action: .app("com.tinyspeck.slackmacgap")),
        .init(alias: "budget", action: .file("~/Documents/cashflow.xlsx")),
        .init(alias: "dev", action: .shell("cd ~/code/api && docker compose up -d")),
    ])
}

@Test func configFillsInDefaults() throws {
    #expect(try Config.parse("") == Config())
    #expect(try Config.parse(Config.example) == Config())
    let partial = try Config.parse("[hotkeys]\nnote = \"option+m\"") // an old key, ignored
    #expect(partial.hotkeys == Config().hotkeys)
    #expect(partial.currency.defaultTarget == "EUR")
    #expect(partial.commands.isEmpty)
    #expect(partial.clipboard == Config.Clipboard())
    #expect(Config().hotkeys.launcher == Hotkey(keyCode: kVK_Space, modifiers: .option))
    #expect(Config().clipboard.maxItems == 1000 && Config().clipboard.maxDays == 90)
    #expect(Config().clipboard.ignoreApps.contains("com.1password.1password"))
    #expect(Config().clipboard.maxImages == 100)
    #expect(Config().files.scopes == ["~/code", "~/Documents", "~/Downloads", "~/Desktop"])
    #expect(Config().files.exclude.contains("node_modules"))
    #expect(Config().pomodoro.defaultMinutes == 25)
}

@Test(arguments: [
    ("[hotkeys\nlauncher = \"option+space\"", "line 1"),                      // TOML syntax
    ("launcher = \"a\"\nlauncher = \"b\"", "line 2"),                          // duplicate key
    ("[hotkeys]\nlauncher = \"hyper+space\"", "hotkeys.launcher"),             // unknown modifier
    ("[hotkeys]\nlauncher = 5", "hotkeys.launcher"),                            // wrong type
    ("[currency]\ndefault_target = \"EURO\"", "currency.default_target"),
    ("[[command]]\nalias = \"x\"\ntype = \"url\"", "command[0].url: missing"),
    ("[[command]]\nalias = \"x\"\ntype = \"ftp\"\nurl = \"ftp://x\"", "command[0].type"),
    ("[[command]]\ntype = \"app\"\napp = \"Slack\"", "command[0].alias: missing"),
    ("[clipboard]\nmax_items = 0", "clipboard.max_items: must be 1 or more"),
    ("[clipboard]\nmax_days = -1", "clipboard.max_days: must be 1 or more"),
    ("[clipboard]\nmax_images = -1", "clipboard.max_images: must be 0 (no images) or more"),
    ("[clipboard]\nignore_apps = \"com.x\"", "clipboard.ignore_apps"),
    ("[files]\nscopes = \"~/code\"", "files.scopes"),
    ("[pomodoro]\ndefault_minutes = 0", "pomodoro.default_minutes: must be 1 to 240"),
    ("[pomodoro]\nbreak_minutes = 300", "pomodoro.break_minutes: must be 1 to 240"),
])
func configRejectsInvalidFiles(_ toml: String, _ messageContains: String) {
    #expect {
        try Config.parse(toml)
    } throws: { error in
        Config.describe(error).contains(messageContains)
    }
}

@Test func hotkeyParsing() {
    #expect(Hotkey("option+space") == Hotkey(keyCode: kVK_Space, modifiers: .option))
    #expect(Hotkey("Cmd + Shift + K") == Hotkey(keyCode: kVK_ANSI_K, modifiers: [.command, .shift]))
    #expect(Hotkey("alt+f5") == Hotkey(keyCode: kVK_F5, modifiers: .option))
    #expect(Hotkey("ctrl+;") == Hotkey(keyCode: kVK_ANSI_Semicolon, modifiers: .control))
    #expect(Hotkey("f12") == Hotkey(keyCode: kVK_F12, modifiers: []))
    for bad in ["", "option+", "+space", "option+foo", "hyper+k", "option+space+", "space+option"] {
        #expect(Hotkey(bad) == nil, "\(bad)")
    }
}

/// The welcome screen's keycaps: one per modifier, in macOS's order, then the key's name.
@MainActor @Test func hotkeyKeycaps() {
    #expect(Hotkey("cmd+space")!.shortcut.keycaps == ["⌘", "Space"])
    #expect(Hotkey("shift+ctrl+f5")!.shortcut.keycaps == ["⌃", "⇧", "F5"])
}

// MARK: Settings: config.toml edited in place

@Test func configFileEditsKeepEverythingElse() throws {
    var file = ConfigFile(#"""
        # Copperlight config.

        [currency]
        default_target = "EUR"         # for "25 usd"

        [clipboard]
        ignore_apps = ["a",
                       "b"]
        max_items = 1000

        [git]
        repos = []
        # editor = "Visual Studio Code"  # optional: what Open uses

        # Custom commands
        [[command]]
        alias = "github"
        type = "url"
        url = "https://github.com"   # home
        # a note about what follows

        [[command]]
        alias = "slack"
        type = "app"
        app = "Slack"

        """#)
    file.set("default_target", in: "currency", to: .string("USD")) // its comment stays where it was
    file.set("ignore_apps", in: "clipboard", to: .strings(["c"])) // two lines become one
    file.set("max_items", in: "clipboard", to: nil)
    file.set("editor", in: "git", to: .string("Cursor")) // takes its commented-out example's place
    file.set("name", in: "browser", to: .string("Firefox")) // a new table, at the end
    file.setEntry("command", at: 0, to: Config.Command(alias: "gh", action: .url("https://github.com/search?q={query}", browser: nil, profile: nil)).toml)
    file.setEntry("command", at: 1, to: nil)
    file.setEntry("snippet", at: nil, to: Config.Snippet(name: "sig", text: "Best,\n\"Alex\" \\o/").toml)
    #expect(file.text == #"""
        # Copperlight config.

        [currency]
        default_target = "USD"         # for "25 usd"

        [clipboard]
        ignore_apps = ["c"]

        [git]
        repos = []
        editor = "Cursor"                # optional: what Open uses

        # Custom commands
        [[command]]
        alias = "gh"
        type = "url"
        url = "https://github.com/search?q={query}"
        # a note about what follows

        [browser]
        name = "Firefox"

        [[snippet]]
        name = "sig"
        text = """
        Best,
        \"Alex\" \\o/"""

        """#)
    let config = try Config.parse(file.text)
    #expect(config.snippets == [Config.Snippet(name: "sig", text: "Best,\n\"Alex\" \\o/")] && config.clipboard.maxItems == 1000)

    let before = file.text // adding an entry and deleting it leaves the file as it was
    file.setEntry("command", at: nil, to: Config.Command(alias: "hn", action: .app("Safari")).toml)
    file.setEntry("command", at: 1, to: nil)
    #expect(file.text == before)
}

/// Every setting the window changes, on the file new users get: the result must read back as exactly what was set.
@Test func configFileEditsTheExample() throws {
    var file = ConfigFile(Config.example), expected = Config()
    let edits: [(String, String, TOMLValue, (inout Config) -> Void)] = [
        ("hotkeys", "launcher", .string("cmd+shift+space"), { $0.hotkeys.launcher = Hotkey("cmd+shift+space")! }),
        ("currency", "default_target", .string("BRL"), { $0.currency.defaultTarget = "BRL" }),
        ("clipboard", "ignore_apps", .strings(["x.y"]), { $0.clipboard.ignoreApps = ["x.y"] }),
        ("clipboard", "max_images", .int(0), { $0.clipboard.maxImages = 0 }),
        ("files", "scopes", .strings(["~/a b"]), { $0.files.scopes = ["~/a b"] }),
        ("pomodoro", "default_minutes", .int(50), { $0.pomodoro.defaultMinutes = 50 }),
        ("browser", "name", .string("Firefox"), { $0.browser.name = "Firefox" }),
        ("browser", "profile", .string("Work"), { $0.browser.profile = "Work" }),
    ]
    for (table, key, value, change) in edits {
        file.set(key, in: table, to: value)
        change(&expected)
    }
    let command = Config.Command(alias: "dev", action: .shell("cd ~/x && make"))
    file.setEntry("command", at: nil, to: command.toml)
    expected.commands = [command]
    #expect(try Config.parse(file.text) == expected)
    #expect(file.text.contains("\nname = \"Firefox\"") && !file.text.contains("# name = \"Google Chrome\"")) // the example, filled in
}

/// The window writes a change through, keeping the file's comments, and refuses one it can't make cleanly.
@MainActor @Test func settingsSaveOrRefuse() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    model.binding(\.pomodoro.defaultMinutes, "pomodoro", "default_minutes") { .int($0) }.wrappedValue = 50
    model.setSnippet(at: nil, to: Config.Snippet(name: "sig", text: "Best,\nAlex"))
    let saved = try String(contentsOf: file, encoding: .utf8)
    #expect(saved.contains("default_minutes = 50           # \"pomo\" in the launcher") && saved.hasPrefix("# Copperlight config."))
    #expect(try Config.parse(saved).snippets.count == 1 && model.config.pomodoro.defaultMinutes == 50 && model.problem == nil)

    // A dotted key: adding a [currency] table would define it twice, so nothing is written.
    let dotted = "currency.default_target = \"USD\"\n"
    try dotted.write(to: file, atomically: true, encoding: .utf8)
    model.reload()
    model.binding(\.currency.defaultTarget, "currency", "default_target") { .string($0) }.wrappedValue = "BRL"
    #expect(try String(contentsOf: file, encoding: .utf8) == dotted && model.problem != nil && model.config.currency.defaultTarget == "USD")
}

@Test func hotkeyText() {
    for text in ["option+space", "ctrl+option+shift+cmd+k", "f12", "cmd+;", "shift+return"] {
        #expect(Hotkey(Hotkey(text)!.text!) == Hotkey(text), "\(text)")
    }
    #expect(Hotkey("Cmd + Shift + K")!.text == "shift+cmd+k" && Hotkey("alt+escape")!.text == "option+esc")
    #expect(Hotkey(keyCode: 0x69, modifiers: .command).text == nil) // F13 has no name in config.toml
}

// MARK: Commands

@Test func chromiumProfileResolution() throws {
    let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/chrome-local-state.json")
    let localState = try Data(contentsOf: fixture)
    #expect(chromiumProfileDirectory("Work", localState: localState) == "Profile 1")
    #expect(chromiumProfileDirectory("work", localState: localState) == "Profile 1")
    #expect(chromiumProfileDirectory("Personal", localState: localState) == "Default")
    #expect(chromiumProfileDirectory("Profile 4", localState: localState) == "Profile 4") // directory name
    #expect(chromiumProfileDirectory("Default", localState: localState) == "Default")
    #expect(chromiumProfileDirectory("Gaming", localState: localState) == nil)
    #expect(chromiumProfileDirectory("Work", localState: Data("{}".utf8)) == nil)
    #expect(chromiumProfileDirectory("Work", localState: Data("garbage".utf8)) == nil)
}

@Test func aliasMatching() {
    #expect(aliasScore("pr", "pr") == 100)
    #expect(aliasScore("PR", "pr") == 100)
    #expect(aliasScore("xyz", "pr") == nil)
    let fuzzy = aliasScore("pr", "prod")
    #expect(fuzzy != nil && fuzzy! < 100)
    #expect(aliasScore("gh", "github")! > fuzzyScore("gh", "GitHub Desktop")!) // commands edge out apps
}

@Test func commandsRankExactAliasFirst() async {
    let provider = CommandProvider()
    await provider.setCommands([
        .init(alias: "prod", action: .url("https://prod.example", browser: nil, profile: nil)),
        .init(alias: "pr", action: .url("https://github.com/pulls", browser: nil, profile: nil)),
        .init(alias: "budget", action: .file("~/b.xlsx")),
    ])
    let titles = await provider.results(for: "pr").sorted { $0.score > $1.score }.map(\.title)
    #expect(titles == ["pr", "prod"])
}

@Test func quicklinksTakeTheTextAfterTheirAlias() async {
    let provider = CommandProvider()
    await provider.setCommands([
        .init(alias: "gh", action: .url("https://github.com/search?q={query}", browser: nil, profile: nil)),
        .init(alias: "ghost", action: .url("https://ghost.org", browser: nil, profile: nil)),
    ])
    let rows = await provider.results(for: "GH  c++ & más").sorted { $0.score > $1.score }
    #expect(rows.map(\.title) == ["gh c++ & más"] && rows[0].score == 100)
    #expect(rows[0].subtitle == "https://github.com/search?q=c%2B%2B%20%26%20m%C3%A1s")
    #expect(await provider.results(for: "gh").first?.subtitle == "https://github.com/search?q=") // no text yet
    #expect(await provider.results(for: "ghost town").isEmpty) // only URLs with {query} take text
}

@Test func browsersAndProfiles() {
    let safari = URL(filePath: "/Applications/Safari.app"), url = "https://example.com"
    #expect(browserApp("Safari") == safari && browserApp("com.apple.Safari") != nil && browserApp("Netscape") == nil)
    guard case .success(let (via, arguments)) = openArguments(url, in: safari, profile: nil) else { Issue.record(); return }
    #expect(via == "Safari" && arguments == ["-a", safari.path, url])
    guard case .failure(let error) = openArguments(url, in: safari, profile: "Work") else { Issue.record(); return }
    #expect(error.message == "Safari can't be opened in a profile")
}

@Test func builtinsRankFirstOnPrefix() {
    let builtins = BuiltinProvider(showNote: { _ in }, showClipboard: {}, notesFolder: URL(filePath: "/nonexistent"))
    func top(_ query: String) -> String? { builtins.results(for: query).max { $0.score < $1.score }?.title }
    func score(_ query: String, _ title: String) -> Double { builtins.results(for: query).first { $0.title == title }?.score ?? 0 }
    for query in ["n", "no", "NOT", "note"] {
        #expect(score(query, "Note") > 2, "\(query)") // apps top out at 1.8 (match 1 + running 0.3 + frecency 0.5)
    }
    #expect(builtins.results(for: "notes").allSatisfy { $0.title != "Note" })
    for query in ["cli", "clip", "CLIPBO", "clipboard"] {
        #expect(score(query, "Clipboard History") > 2 && top(query) == "Clipboard History", "\(query)")
    }
    #expect(score("cl", "Clipboard History") < 1.8) // too short: Claude, Clock… keep their place
    #expect(top("welc") == "Welcome to Copperlight" && score("we", "Welcome to Copperlight") < 1.8)
}

@Test func namedNotes() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-notes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["work", "Groceries", ".hidden"] { try "".write(to: folder.appending(path: name + ".txt"), atomically: true, encoding: .utf8) }
    try "".write(to: folder.appending(path: "readme.md"), atomically: true, encoding: .utf8)
    #expect(noteNames(in: folder) == ["Groceries", "work"])
    let builtins = BuiltinProvider(showNote: { _ in }, showClipboard: {}, notesFolder: folder)
    let titles = { (query: String) in builtins.results(for: query).sorted { $0.score > $1.score }.map(\.title) }
    #expect(titles("note") == ["Note", "Groceries", "work"])
    #expect(titles("note wo") == ["work", "wo"]) // and a new note named "wo"
    #expect(titles("note WORK") == ["work"]) // it exists: no new one
    #expect(titles("note a/b").isEmpty && titles("note .x").isEmpty)
    #expect(titles("no") == ["Note"]) // the named ones from "note" on
}

// MARK: Clipboard

@MainActor @Test func clipboardSkipsMarkedItemsAndIgnoredApps() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    func put(_ text: String, marker: String? = nil) {
        pasteboard.declareTypes([.string] + (marker.map { [NSPasteboard.PasteboardType($0)] } ?? []), owner: nil)
        pasteboard.setString(text, forType: .string)
    }
    let content = { (app: String?, ignore: [String]) in clipboardContent(pasteboard, app: app, ignoreApps: ignore) }
    put("hello")
    #expect(content("com.apple.Safari", ["com.1password.1password"]) == .text("hello"))
    #expect(content(nil, []) == .text("hello"))
    #expect(content("com.1password.1password", ["com.1password.1password"]) == nil)
    for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
        put("secret", marker: marker)
        #expect(content(nil, []) == nil, "\(marker)")
    }
    put(" \n\t ")
    #expect(content(nil, []) == nil) // whitespace only

    let png = testPNG(width: 3, height: 2)
    pasteboard.declareTypes([.png], owner: nil)
    pasteboard.setData(png, forType: .png)
    #expect(content(nil, []) == .image(png))
    pasteboard.declareTypes([.png, .string], owner: nil) // e.g. cells from a spreadsheet: text wins
    pasteboard.setData(png, forType: .png)
    pasteboard.setString("A1\tB1", forType: .string)
    #expect(content(nil, []) == .text("A1\tB1"))
    pasteboard.declareTypes([.tiff], owner: nil) // TIFF only: kept as PNG
    pasteboard.setData(NSImage(data: png)!.tiffRepresentation!, forType: .tiff)
    guard case .image(let converted)? = content(nil, []) else { Issue.record("TIFF not recorded"); return }
    #expect(imagePixelSize(converted)! == (3, 2))
    pasteboard.declareTypes([.png, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
    pasteboard.setData(png, forType: .png)
    #expect(content(nil, []) == nil) // markers apply to images too
}

private func testPNG(width: Int, height: Int, red: CGFloat = 1) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<width { for y in 0..<height { rep.setColor(NSColor(red: red, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
    return rep.representation(using: .png, properties: [:])!
}

@Test func clipboardStoresImages() throws {
    let store = try ClipboardStore()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let red = testPNG(width: 40, height: 30), blue = testPNG(width: 40, height: 30, red: 0)
    try store.record(image: red, width: 40, height: 30, app: "com.apple.screencaptureui", at: t0)
    try store.record("some text", app: nil, at: t0 + 1)
    try store.record(image: red, width: 40, height: 30, app: "com.google.Chrome", at: t0 + 2) // same image again
    var items = try store.items()
    #expect(items.map(\.text) == ["Image 40×30", "some text"]) // deduped and moved to the top
    let image = try #require(items.first)
    #expect(image.imageSize! == (40, 30) && image.length == red.count && image.app == "com.google.Chrome")
    #expect(try store.content(image.id) == .image(red))
    #expect(try store.image(image.id) == red)
    #expect(try store.content(items[1].id) == .text("some text"))
    #expect(try store.image(items[1].id) == nil)
    let thumb = try #require(thumbnail(red, maxPixels: 16))
    #expect((thumb.width, thumb.height) == (16, 12))

    #expect(try store.items(matching: "image").map(\.text) == ["Image 40×30"])
    #expect(try store.items(matching: "IMA").count == 1)
    #expect(try store.items(matching: "text").map(\.text) == ["some text"])
    #expect(try store.items(matching: "image:").isEmpty) // the dedupe key isn't searchable

    try store.record(image: blue, width: 40, height: 30, app: nil, at: t0 + 3)
    try store.prune(maxItems: 1000, maxDays: 90_000, maxImages: 1, now: t0 + 4)
    items = try store.items()
    #expect(items.count == 2 && items.first?.length == blue.count) // only the newest image is kept; text untouched
}

@Test func colonCommands() async {
    let verbs = VerbProvider(verbs: [
        Verb(keyword: "minimize", title: "Minimize Window", icon: .symbol("minus"), run: {}),
        Verb(keyword: "quit", title: "Quit Application", icon: .symbol("xmark"), targets: { filter in
            [LauncherResult(id: "t", title: "target:\(filter)", icon: .symbol("app"), score: 0, action: {})]
        }),
        Verb(keyword: "quit all", title: "Quit All", icon: .symbol("xmark"), run: {}),
    ])
    #expect(await verbs.results(for: "saf").isEmpty) // no colon, not a command
    #expect(await verbs.results(for: ":").map(\.title) == ["Minimize Window", "Quit Application", "Quit All"])
    #expect(await verbs.results(for: ":min").map(\.title) == ["Minimize Window"])
    #expect(await verbs.results(for: ":minimize").first?.completion == nil) // Enter runs it right away
    let quit = await verbs.results(for: ":qu").first
    #expect(quit?.title == "Quit Application" && quit?.completion == ":quit ") // Enter fills in the keyword
    #expect(await verbs.results(for: ":quit").map(\.title) == ["Quit All", "target:"])
    #expect(await verbs.results(for: ":Quit  safari").map(\.title) == ["target:safari"])
    #expect(await verbs.results(for: ":quit al").map(\.title) == ["Quit All", "target:al"]) // extends `quit`: offered first

    let launcher = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(await launcher.results(for: ":fq").first?.title == "Force Quit Application")
    #expect(await launcher.results(for: ":force quit zzzzzzzz").isEmpty) // no running app matches
    #expect(await launcher.results(for: ":hide oth").first?.title == "Hide Others")
    #expect(await launcher.results(for: ":left").first?.subtitle == ":left")
    let restart = await launcher.results(for: ":restart").first
    #expect(restart?.title == "Restart" && restart?.confirm != nil) // asks first
    #expect(await launcher.results(for: ":volume 30").map(\.title) == ["Set Volume to 30%"])
    #expect(await launcher.results(for: ":volume loud").first?.actionTitle == "") // says what to type, does nothing
    #expect(await launcher.results(for: ":volume 101").first?.actionTitle == "")
}

@Test func windowLayouts() {
    let visible = CGRect(x: 0, y: 25, width: 1000, height: 800)
    #expect(layoutFrame(.maximize, size: .zero, visible: visible) == visible)
    #expect(layoutFrame(.leftHalf, size: .zero, visible: visible) == CGRect(x: 0, y: 25, width: 500, height: 800))
    #expect(layoutFrame(.rightHalf, size: .zero, visible: visible) == CGRect(x: 500, y: 25, width: 500, height: 800))
    #expect(layoutFrame(.center, size: CGSize(width: 400, height: 200), visible: visible) == CGRect(x: 300, y: 325, width: 400, height: 200))
    #expect(layoutFrame(.center, size: CGSize(width: 2000, height: 200), visible: visible).width == 1000) // shrunk to fit
    #expect(layoutFrame(.topHalf, size: .zero, visible: visible) == CGRect(x: 0, y: 425, width: 1000, height: 400)) // y grows up
    #expect(layoutFrame(.bottomHalf, size: .zero, visible: visible) == CGRect(x: 0, y: 25, width: 1000, height: 400))
    let wide = CGRect(x: 0, y: 0, width: 1200, height: 600)
    #expect(layoutFrame(.centerThird, size: .zero, visible: wide) == CGRect(x: 400, y: 0, width: 400, height: 600))
    #expect(layoutFrame(.rightTwoThirds, size: .zero, visible: wide) == CGRect(x: 400, y: 0, width: 800, height: 600))

    // Next display: same place, scaled to the other screen's usable area (here one to its right, twice the size).
    let left = CGRect(x: 0, y: 0, width: 1000, height: 500), right = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
    #expect(movedFrame(CGRect(x: 0, y: 0, width: 500, height: 500), from: left, to: right) == CGRect(x: 1000, y: 0, width: 1000, height: 1000))
    #expect(movedFrame(CGRect(x: 250, y: 100, width: 100, height: 50), from: left, to: right) == CGRect(x: 1500, y: 200, width: 200, height: 100))
}

@Test func clipboardCommands() async throws {
    let store = try ClipboardStore()
    try store.record("hello world", app: nil, at: .now)
    try store.record("other", app: nil, at: .now + 1)
    let provider = ClipboardProvider(store: store, paste: { _ in }, copy: { _ in })
    let verbs = VerbProvider(verbs: provider.verbs)
    #expect(await verbs.results(for: ":copy").map(\.actionTitle) == ["Copy", "Copy"])
    #expect(await provider.results(for: "").allSatisfy { !$0.staysOpen })
    let delete = try #require(await verbs.results(for: ":delete hello").first)
    #expect(delete.title == "hello world" && delete.actionTitle == "Delete" && delete.staysOpen)
    await MainActor.run { delete.action() }
    #expect(try store.items().map(\.text) == ["other"])
    let clear = try #require(await verbs.results(for: ":clear").first)
    #expect(clear.title == "Clear History" && clear.confirm != nil)
    await MainActor.run { clear.action() }
    #expect(try store.items().isEmpty)
}

@Test func webFallbacks() async {
    #expect(webURL("github.com/swiftlang")?.absoluteString == "https://github.com/swiftlang")
    #expect(webURL("https://example.org/a?b=1")?.absoluteString == "https://example.org/a?b=1")
    #expect(webURL("localhost:3000")?.absoluteString == "http://localhost:3000")
    for text in ["readme.md", "logo.ai", "libfoo.so", "1.5", "safari", "me@example.com", "two words.com", "file:///tmp", ""] {
        #expect(webURL(text) == nil, "\(text)")
    }
    #expect(googleSearchURL("c++ & café").absoluteString == "https://www.google.com/search?q=c%2B%2B%20%26%20caf%C3%A9")
    #expect(await WebProvider().results(for: "github.com").map(\.id).sorted() == ["web:google", "web:open"])
    #expect(await WebProvider().results(for: "zzz").map(\.score) == [-10]) // below everything, files included
}

@Test func defaultBrowserAndProfile() async {
    let web = WebProvider()
    #expect(await web.results(for: "gmail.com").first { $0.id == "web:open" }?.subtitle == "https://gmail.com") // unset: as before
    await web.setBrowser(.init(name: "Safari"))
    #expect(await web.results(for: "gmail.com").first { $0.id == "web:open" }?.subtitle == "https://gmail.com · Safari")
    #expect(await web.results(for: "zzz").first?.subtitle == "Safari") // the search too
    await web.setBrowser(.init(name: "Safari", profile: "Work"))
    #expect(await web.results(for: "zzz").first?.subtitle == "Safari can't be opened in a profile, so the default browser")

    let commands = CommandProvider()
    await commands.setCommands([.init(alias: "mail", action: .url("https://gmail.com", browser: nil, profile: nil)),
                                .init(alias: "chat", action: .url("slack://open", browser: nil, profile: nil))],
                               browser: .init(name: "Safari"))
    #expect(await commands.results(for: "mail").first?.subtitle == "https://gmail.com · Safari") // a web link follows [browser]
    #expect(await commands.results(for: "chat").first?.subtitle == "slack://open") // other schemes go to their app
}

@Test func clipboardDedupeMovesToTop() throws {
    let store = try ClipboardStore()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    try store.record("a", app: "com.apple.Safari", at: t0)
    try store.record("b", app: "com.apple.Terminal", at: t0 + 1)
    try store.record("a", app: "com.apple.Notes", at: t0 + 2)
    let items = try store.items()
    #expect(items.map(\.text) == ["a", "b"])
    #expect(items.first?.app == "com.apple.Notes")
}

@Test func clipboardPrunesByAgeAndCount() throws {
    let store = try ClipboardStore()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (text, daysAgo) in [("ancient", 100.0), ("old", 30), ("recent", 2), ("new", 1), ("newest", 0)] {
        try store.record(text, app: nil, at: now - daysAgo * 86_400)
    }
    try store.prune(maxItems: 1000, maxDays: 90, now: now)
    #expect(try store.items().map(\.text) == ["newest", "new", "recent", "old"])
    try store.prune(maxItems: 2, maxDays: 90, now: now)
    #expect(try store.items().map(\.text) == ["newest", "new"])
}

@Test func clipboardSearch() throws {
    let store = try ClipboardStore()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let texts = ["git checkout origin/main", "Hello World", "say hello\nto everyone", "big tacos", "x"]
    for (i, text) in texts.enumerated() { try store.record(text, app: nil, at: t0 + Double(i)) }
    #expect(try store.items(matching: "HELLO").map(\.text) == ["say hello\nto everyone", "Hello World"]) // newest first
    #expect(try store.items(matching: "gco").map(\.text) == ["git checkout origin/main"]) // word starts; "big tacos" only scatters
    #expect(try store.items(matching: "zzz").isEmpty)
    #expect(try store.items().count == 5)
    #expect(try store.items(limit: 2).map(\.text) == ["x", "big tacos"])

    let long = String(repeating: "y", count: ClipboardStore.previewLength + 5)
    try store.record(long, app: nil, at: t0 + 10)
    let item = try #require(try store.items().first)
    #expect(item.text.count == ClipboardStore.previewLength && item.length == long.count)
    #expect(try store.content(item.id) == .text(long))
    try store.delete(item.id)
    #expect(try store.items().count == 5)
    try store.clear()
    #expect(try store.items().isEmpty)
}

@Test func clipboardAgesAndSections() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(shortAge(now - 5, now: now) == "now")
    #expect(shortAge(now + 5, now: now) == "now") // clock skew
    #expect(shortAge(now - 125, now: now) == "2m")
    #expect(shortAge(now - 3 * 3600, now: now) == "3h")
    #expect(shortAge(now - 49 * 3600, now: now) == "2d")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    #expect(clipboardSection(noon - 11 * 3600, now: noon, calendar: calendar) == "Today")      // 01:00 today
    #expect(clipboardSection(noon - 13 * 3600, now: noon, calendar: calendar) == "Yesterday")  // 23:00 yesterday
    #expect(clipboardSection(noon - 40 * 3600, now: noon, calendar: calendar) == "Earlier")
}

// MARK: File search

@Test func fileSearchExcludesByPathComponent() {
    let excluded = Config.Files().exclude
    #expect(isExcluded("/Users/me/code/app/node_modules/react/index.js", by: excluded))
    #expect(isExcluded("/Users/me/code/app/.git/HEAD", by: excluded))
    #expect(isExcluded("/Users/me/Library/Developer/Xcode/DerivedData/x", by: excluded))
    #expect(isExcluded("/Users/me/code/copperlight/build/SourcePackages/checkouts/GRDB.swift/README.md", by: excluded))
    #expect(isExcluded("/Users/me/code/tool/.build/checkouts/x/README.md", by: excluded))
    #expect(!isExcluded("/Users/me/code/app/src/node_modules_notes.md", by: excluded)) // whole names only
    #expect(!isExcluded("/Users/me/code/app/.github/workflows/ci.yml", by: excluded))
    #expect(!isExcluded("/Users/me/Documents/invoice.pdf", by: []))
}

@Test func fileSearchQueryAndRanking() throws {
    #expect(spotlightQuery("inv") == #"kMDItemDisplayName == "inv*"cdw"#)
    #expect(spotlightQuery("  inv  2026 ") == #"kMDItemDisplayName == "inv*"cdw && kMDItemDisplayName == "2026*"cdw"#)
    #expect(spotlightQuery(#"a"b*c?\"#) == #"kMDItemDisplayName == "a\"b\*c\?\\*"cdw"#) // can't break out of the string
    #expect(spotlightQuery("   ") == nil)
    #expect(NSPredicate(fromMetadataQueryString: spotlightQuery(#"it's "x" 50%"#)!) != nil)

    // Inside files: the same words in their text, minus files already found by name; from 3 characters.
    #expect(spotlightContentQuery("29.99") == #"(kMDItemTextContent == "29.99*"cdw) && !(kMDItemDisplayName == "29.99*"cdw)"#)
    #expect(spotlightContentQuery("ab") == nil)
    #expect(NSPredicate(fromMetadataQueryString: spotlightContentQuery("price tag")!) != nil)
    let notes = FileManager.default.temporaryDirectory.appending(path: "copperlight-\(UUID()).txt")
    try "milk\nTotal: 29.99 EUR\neggs".write(to: notes, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: notes) }
    #expect(matchingLines(notes.path, query: "29.99") == "Total: 29.99 EUR")

    #expect(fileMatchQuality("readme", name: "README.md") == 3)
    #expect(fileMatchQuality("invoice", name: "Invoice") == 3)
    #expect(fileMatchQuality("inv", name: "Invoice October.pdf") == 2)
    #expect(fileMatchQuality("oct", name: "Invoice October.pdf") == 1)
    #expect(fileMatchQuality("cafe", name: "Café menu.txt") == 2) // diacritics ignored

    let home = "/Users/me"
    #expect(shortParentPath("/Users/me/Code/copperlight/Sources/App.swift", home: home) == "~/Code/copperlight/Sources")
    #expect(shortParentPath("/Users/me/notes.txt", home: home) == "~")
    #expect(shortParentPath("/Users/me/a/b/c/d/e/f.txt", home: home) == "~/…/c/d/e")
    #expect(shortParentPath("/Volumes/Data/a/b/c/d/f.txt", home: home) == "/…/b/c/d")
    #expect(shortParentPath("/Users/meg/x.txt", home: home) == "/Users/meg") // not under home
}

// MARK: Pomodoro

@Test func pomodoroCommands() {
    #expect(parsePomodoro("pomo", defaultMinutes: 25) == [.start(minutes: 25), .startBreak(minutes: 5), .stop])
    #expect(parsePomodoro("pom", defaultMinutes: 30, breakMinutes: 10) == [.start(minutes: 30), .startBreak(minutes: 10), .stop])
    #expect(parsePomodoro("Pomodoro", defaultMinutes: 25) == [.start(minutes: 25), .startBreak(minutes: 5), .stop])
    #expect(parsePomodoro("pomo b", defaultMinutes: 25) == [.startBreak(minutes: 5)])
    #expect(parsePomodoro("pomo break 15", defaultMinutes: 25) == [.startBreak(minutes: 15)])
    #expect(parsePomodoro("pomo 50", defaultMinutes: 25) == [.start(minutes: 50)])
    #expect(parsePomodoro("pomo  5", defaultMinutes: 25) == [.start(minutes: 5)])
    #expect(parsePomodoro("pomo stop", defaultMinutes: 25) == [.stop])
    #expect(parsePomodoro("pomo s", defaultMinutes: 25) == [.stop])
    for none in ["", "po", "pomx", "pomodoros", "pomo 0", "pomo 241", "pomo -5", "pomo 2.5", "pomo start",
                 "pomo 25 extra", "pomo stopp", "pizza", "pomo break 0", "pomo break x", "pomo breaks"] {
        #expect(parsePomodoro(none, defaultMinutes: 25).isEmpty, "\(none)")
    }
}

@Test func pomodoroDeadlineMath() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let deadline = start + 25 * 60
    #expect(countdown(remaining(until: deadline, now: start)) == "25:00")
    #expect(countdown(remaining(until: deadline, now: start + 0.4)) == "25:00") // rounds up
    #expect(countdown(remaining(until: deadline, now: start + 61)) == "23:59")
    #expect(countdown(remaining(until: deadline, now: deadline - 0.5)) == "00:01")
    #expect(remaining(until: deadline, now: deadline) == 0)
    #expect(remaining(until: deadline, now: deadline + 3600) == 0) // slept through it: done, not negative
    #expect(countdown(remaining(until: start + 120 * 60, now: start)) == "120:00")
}

@MainActor @Test func pomodoroStateRoundTrips() throws {
    let file = try tempStateFile()
    let running = Pomodoro.Running(deadline: Date(timeIntervalSince1970: 1_800_000_000), minutes: 25)
    let store = StateStore(file: file)
    store.set("pomodoro", running)
    store.flush()
    #expect(StateStore(file: file).get("pomodoro", as: Pomodoro.Running.self) == running)
    store.set("pomodoro", Pomodoro.Running?.none) // stopped
    store.flush()
    #expect(StateStore(file: file).get("pomodoro", as: Pomodoro.Running.self) == nil)
}

// MARK: Text tools

@Test func textTools() {
    let clip = Clip(text: #"{"b": [1, {}], "a": "x, y"}"#)
    func run(_ name: String, _ typed: String? = nil) -> String? {
        runTextTool(name, typed: typed, clip: clip, now: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .gmt)
    }
    #expect(run("json") == "{\n  \"b\": [\n    1,\n    {}\n  ],\n  \"a\": \"x, y\"\n}") // key order kept
    #expect(run("json min") == #"{"b":[1,{}],"a":"x, y"}"#)
    #expect(run("json", "nope") == nil)
    #expect(run("b64", "héllo") == "aMOpbGxv" && run("b64 decode", "aMOpbGxv") == "héllo")
    #expect(run("b64 decode", "aGk") == "hi") // padding left out
    #expect(run("url encode", "a b&c") == "a%20b%26c" && run("url decode", "a%20b") == "a b")
    #expect(run("upper", "straße") == "STRASSE" && run("lower", "ABC") == "abc")
    #expect(run("snake", "fooBar baz-qux HTTPServer") == "foo_bar_baz_qux_http_server")
    #expect(run("camel", "foo_bar HTTP server\nnext-line") == "fooBarHttpServer\nnextLine")
    #expect(run("sort lines", "b\na10\nA\na9\n") == "A\na9\na10\nb")
    #expect(run("sha256", "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(run("count", "two words\nthree") == "3 words · 15 characters · 2 lines")
    #expect(run("count", "one") == "1 word · 3 characters · 1 line")
    #expect(run("unix") == "1700000000") // the clipboard isn't a timestamp: now
    #expect(run("unix", "1700000000") == "2023-11-14T22:13:20Z" && run("unix", "1700000000000") == "2023-11-14T22:13:20Z")
    #expect(run("hex", "#ff8800") == "rgb(255, 136, 0)" && run("hex", "f80") == "rgb(255, 136, 0)")
    #expect(run("hex", "rgb(255, 136, 0)") == "#ff8800" && run("hex", "255 136 0") == "#ff8800")
    #expect(run("hex", "300 0 0") == nil && run("hex", "f") == nil)
    #expect(run("uuid")?.count == 36 && run("password")?.count == 20 && run("password", "32")?.count == 32)
    #expect(run("password", "x") == nil && run("lorem", "2")?.components(separatedBy: "\n\n").count == 2)
    #expect(runTextTool("upper", typed: nil, clip: Clip(text: nil)) == nil) // nothing to work on
}

@Test func pasteAsMarkdown() {
    let html = """
        <meta charset='utf-8'><h2 style="color:red">Title &amp; more</h2><p>Some <b>bold</b>, <i>it</i> and \
        <a href="https://x.com">a link</a>.<br>Next</p><ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul>\
        <ol><li><p>first</p></li><li>second</li></ol><pre><code>let x = 1\n  y</code></pre>\
        <blockquote><p>quoted</p><p>two</p></blockquote>\
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2 | 3</td></tr></table>
        """
    #expect(markdown(fromHTML: html) == """
        ## Title & more

        Some **bold**, *it* and [a link](https://x.com).
        Next

        - one
        - two
          - nested

        1. first
        2. second

        ```
        let x = 1
          y
        ```

        > quoted
        >
        > two

        | A | B |
        | --- | --- |
        | 1 | 2 \\| 3 |
        """)
    let googleDocs = #"<b style="font-weight:normal;" id="docs-internal-guid-1"><p dir="ltr"><span style="font-weight:700;">Bold</span><span> plain </span><span style="font-style:italic;">ital</span></p></b>"#
    #expect(markdown(fromHTML: googleDocs) == "**Bold** plain *ital*")
    #expect(runTextTool("paste markdown", typed: nil, clip: Clip(text: "just text")) == "just text") // no HTML on the clipboard
}

@Test func textToolRows() async {
    let provider = TextToolProvider()
    let upper = await provider.results(for: "UPPER hello")
    #expect(upper.map(\.title) == ["HELLO"] && upper[0].score == 50 && upper[0].actionTitle == "Copy")
    #expect(await provider.results(for: "json min {\"a\": 1}").first?.title == #"{"a":1}"#)
    #expect(await provider.results(for: "hex f").isEmpty) // typed input it can't use: nothing, so Hex Fiend stays on top
    #expect(await provider.results(for: "uppercase").isEmpty)
    let start = await provider.results(for: "uui")
    #expect(start.map(\.accessory) == ["New UUID"] && start[0].score < 1) // a name's beginning: below good app matches
    let lorem = await provider.results(for: "lorem 2")
    #expect(lorem.map(\.title) == ["Lorem Ipsum"] && lorem[0].preview != nil) // in the preview pane: the row names the tool
}

// MARK: Capture

@Test func captureDates() throws {
    let calendar = Calendar.current
    let friday = try #require(captureDate("fri 10am dentist"))
    #expect(friday.title == "dentist" && !friday.allDay && friday.duration == 0)
    #expect(calendar.component(.weekday, from: friday.date) == 6 && calendar.component(.hour, from: friday.date) == 10)
    let october = try #require(captureDate("dentist on Oct 20 at 14:00"))
    #expect(october.title == "dentist") // not "dentist on"
    #expect(calendar.dateComponents([.month, .day, .hour], from: october.date) == DateComponents(month: 10, day: 20, hour: 14))
    #expect(captureDate("dentist friday")?.allDay == true) // no time typed
    #expect(captureDate("review 10-11am")?.duration == 3600)
    #expect(captureDate("call mom tomorrow 5pm")?.title == "call mom")
    #expect(captureDate("pay rent") == nil)
}

@MainActor @Test func captureRows() async {
    final class Lines: @unchecked Sendable { var added: [String] = [] }
    let lines = Lines()
    let capture = CaptureProvider(addToNote: { lines.added.append($0) })
    #expect(capture.results(for: "add").map(\.completion) == ["add note ", "add todo ", "add event "])
    #expect(capture.results(for: "ADD t").map(\.title) == ["Add Reminder"])
    #expect(capture.results(for: "address").isEmpty)
    let note = capture.results(for: "add note buy milk")
    #expect(note.map(\.title) == ["buy milk"] && note[0].score == 50)
    note[0].action()
    #expect(lines.added == ["buy milk"])
    #expect(capture.results(for: "add todo pay rent").first?.subtitle == "Reminder · no date")
    #expect(capture.results(for: "add event pay rent").first?.actionTitle == "") // no date: a hint, nothing to add
    #expect(capture.results(for: "add event fri 10am dentist").first?.title == "dentist")
    #expect(capture.results(for: "screenshot").map(\.id) == ["builtin:screenshot"])
    #expect(capture.results(for: "rec").first?.title == "Record Screen")
}

@MainActor @Test func commandsReplaceBuiltins() async throws {
    let commands = CommandProvider()
    await commands.setCommands([.init(alias: "Screenshot", action: .url("cleanshot://capture-area", browser: nil, profile: nil))])
    let model = SearchModel(providers: [commands, CaptureProvider(addToNote: { _ in })])
    model.query = "screenshot"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.id) == ["command:Screenshot"])
    model.query = "record"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.id) == ["builtin:record"]) // no command by that name
}

// MARK: Shell

@Test func shellRuns() async {
    let run = await runShell("echo out; echo err >&2; printf '\\033[31mred\\033[0m'; exit 3")
    #expect(run.output == "out\nerr\nred" && run.status == 3 && !run.timedOut) // interleaved, no color codes
    #expect(await runShell("echo $PATH").output.split(separator: ":").contains { $0 == scriptsDir.path }) // login profiles reorder it
    let slow = await runShell("sleep 5", timeout: 0.3)
    #expect(slow.timedOut && slow.seconds < 2)
}

@MainActor @Test func shellRows() async throws {
    let state = StateStore(file: try tempStateFile())
    let shell = ShellProvider(state: state)
    #expect(await shell.results(for: ":!").map(\.id) == ["shell:hint"]) // nothing run yet
    state.set(Frecency.stateSection, ["shell:git status": Frecency(score: 1, updated: .now),
                                      "shell:ls -la": Frecency(score: 3, updated: .now), "/Applications/Safari.app": Frecency(score: 9, updated: .now)])
    #expect(await shell.results(for: ":!").map(\.title) == ["ls -la", "git status"]) // most used first, shell lines only
    let typed = await shell.results(for: ":! git st")
    #expect(typed.map(\.title) == ["git st", "git status"] && typed[0].output != nil) // what's typed, then lines like it
    #expect(await shell.results(for: ":!git status").map(\.title) == ["git status"]) // not twice

    // ":!" goes to the shell alone, ":" to the commands alone.
    let verbs = VerbProvider(verbs: [Verb(keyword: "lock", title: "Lock Screen", icon: .symbol("lock"), run: {})])
    let model = SearchModel(providers: [], exclusive: [VerbProvider.prefix: verbs, ShellProvider.prefix: shell])
    model.query = ":!ls"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.first?.title == "ls")
    model.query = ":lock"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.title) == ["Lock Screen"])

    let done = await shellOutputRow("echo hi; exit 1")
    #expect(done.preview == "hi" && done.subtitle.hasPrefix("exit 1") && done.actionTitle == "Copy")
    #expect(await shellOutputRow("true").actionTitle == "") // nothing to copy
}

// MARK: Paths

@Test func pathQueries() {
    let none = { (_: String) in false }
    #expect(pathQuery("saf") == nil && pathQuery("~foo") == nil)
    #expect(pathQuery("~") == PathQuery(folder: "~/", filter: ""))
    #expect(pathQuery("/") == PathQuery(folder: "/", filter: ""))
    #expect(pathQuery("~/code/he", isFolder: none) == PathQuery(folder: "~/code/", filter: "he"))
    #expect(pathQuery("/Applications/Saf", isFolder: none) == PathQuery(folder: "/Applications/", filter: "Saf"))
    #expect(pathQuery("/Applications", isFolder: { $0 == "/Applications" }) == PathQuery(folder: "/Applications/", filter: ""))
    #expect(pathQuery("~/code", isFolder: { $0 == NSHomeDirectory() + "/code" }) == PathQuery(folder: "~/code/", filter: ""))
    #expect(pathQuery("~/.", isFolder: { _ in true }) == PathQuery(folder: "~/", filter: "."))
}

@Test func pathRows() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "copperlight-paths-\(UUID().uuidString)")
    for folder in ["alpha", "Tool.app"] { try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true) }
    for file in ["Beta.txt", ".hidden"] { try "x".write(to: root.appending(path: file), atomically: true, encoding: .utf8) }
    defer { try? FileManager.default.removeItem(at: root) }
    let typed = root.path // under /var, a link to /private/var

    let all = PathProvider().results(for: typed)
    #expect(all.map(\.title) == [root.lastPathComponent, "alpha", "Beta.txt", "Tool.app"]) // the folder, then A to Z, no hidden
    #expect(all[0].actionTitle == "Open in Finder")
    #expect(all[1].completion == typed + "/alpha/" && all[1].actionTitle == "Browse") // Enter goes in
    #expect(all[3].completion == nil && all[3].actionTitle == "Open") // an app opens
    #expect(PathProvider().results(for: typed + "/be").first?.title == "Beta.txt")
    #expect(PathProvider().results(for: typed + "/.").first?.title == ".hidden") // hidden ones once the name starts with "."
    #expect(PathProvider().results(for: typed + "/nope/x").map(\.id) == ["path:none"])

    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(await verbs.results(for: ":copy path \(typed)/al").map(\.title) == ["Copy Path: alpha"])
    #expect(await verbs.results(for: ":reveal \(typed)/").first?.title == "Reveal in Finder: \(root.lastPathComponent)")
}

// MARK: Panel

private struct Sized: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        (0..<(query.count * 3 % 14)).map { LauncherResult(id: "\(query)\($0)", title: "Row \($0)", icon: .symbol("doc"), score: -Double($0), action: {}) }
    }
}

@MainActor private func effectViews(_ view: NSView) -> [NSVisualEffectView] {
    view.subviews.flatMap { ($0 as? NSVisualEffectView).map { [$0] } ?? effectViews($0) }
}

/// The window stays put while results change; only the card inside it grows and shrinks. When the window followed
/// the results, the pill jumped for a frame (and slid back while an animation ran), and SwiftUI resizing it too
/// once made AppKit abort the app. This burst of animated changes showed both every time.
@MainActor @Test func panelStaysPutWhileResultsChange() async throws {
    let model = SearchModel(providers: [Sized()])
    let panel = LauncherPanel(model: model, placeholder: "…")
    panel.setFrameOrigin(NSPoint(x: 100, y: 300))
    panel.alphaValue = 0.01 // on screen, so it lays out for real, but invisible
    panel.orderFrontRegardless()
    defer { panel.orderOut(nil) }
    let frame = panel.frame
    try await Task.sleep(for: .milliseconds(300))
    let queries = ["a", "abcd", "ab", "abcdefg", "", "abc", "abcdef", "a", "abcdefgh"]
    for round in 0..<600 {
        withAnimation(.easeOut(duration: 0.1)) { model.query = queries[round % queries.count] }
        try await Task.sleep(for: .milliseconds(round % 5 == 0 ? 20 : 1))
        // The pill is the highest glass: it sits the margin below the window's top, always.
        let pillTop = effectViews(panel.contentView!).map { $0.convert($0.bounds, to: nil).maxY }.max() ?? 0
        #expect(panel.frame == frame && panel.contentView!.bounds.height - pillTop == LauncherPanel.margin)
    }
}

// MARK: Scripts

@MainActor @Test func scriptsFolder() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-scripts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = [
        "deploy.sh": "#!/bin/sh\n# @title Deploy App\n# @icon hammer\n# @output show\necho \"to $1\"\n",
        "quiet": "#!/bin/sh\ntrue\n", "screenshot": "#!/bin/sh\ntrue\n",
        ".hidden": "#!/bin/sh\ntrue\n", "notes.txt": "not a script",
    ]
    for (name, text) in files {
        try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        if name != "notes.txt" { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: name).path) }
    }

    let found = scripts(in: folder)
    #expect(found.map(\.name) == ["deploy", "quiet", "screenshot"]) // executables only, not hidden ones
    #expect(found[0].title == "Deploy App" && found[0].icon == "hammer" && found[0].output == .show && found[1].output == .silent)

    let provider = ScriptProvider(folder: folder)
    let typed = provider.results(for: "deploy it's live")
    #expect(typed.first?.title == "Deploy App it's live" && typed.first?.score == 100) // the text after the name: arguments
    #expect(await typed.first?.output?({ _ in }).preview == "to it's") // quoted, so it reaches the script as typed
    #expect(provider.results(for: "dep").first?.title == "Deploy App") // found loosely too
    #expect(shellQuoted("it's") == #"'it'\''s'"#)

    let model = SearchModel(providers: [provider, CaptureProvider(addToNote: { _ in })])
    model.query = "screenshot"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.results.map(\.id) == ["script:screenshot"]) // a script named like a built-in replaces it
}

/// Community script commands (`@raycast.*` headers) work as they are: title, mode, a symbol icon, confirmation,
/// description, and the declared arguments, the last one taking the rest of what's typed.
@MainActor @Test func communityScriptHeaders() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-community-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = [
        "ask.sh": """
            #!/bin/bash
            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title Ask the Oracle
            # @raycast.mode fullOutput
            # Optional parameters:
            # @raycast.icon 🔮
            # @raycast.argument1 { "type": "text", "placeholder": "Question" }
            # @raycast.description Prints the question back
            echo "[$1]"
            """,
        "restart-dock.sh": """
            #!/bin/bash
            # @raycast.schemaVersion 1
            # @raycast.title Restart Dock
            # @raycast.mode silent
            # @raycast.icon dock.rectangle
            # @raycast.needsConfirmation true
            true
            """,
        "both.sh": "#!/bin/sh\n# @raycast.title Theirs\n# @raycast.mode compact\n# @title Mine\n# @output show\ntrue\n",
    ]
    for (name, text) in files {
        try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: name).path)
    }

    let found = Dictionary(uniqueKeysWithValues: scripts(in: folder).map { ($0.name, $0) })
    let ask = try #require(found["ask"]), dock = try #require(found["restart-dock"]), both = try #require(found["both"])
    #expect(ask.title == "Ask the Oracle" && ask.output == .show && ask.icon == "terminal") // an emoji isn't a symbol: the default
    #expect(ask.argumentCount == 1 && ask.subtitle == "Prints the question back")
    #expect(dock.title == "Restart Dock" && dock.output == .silent && dock.icon == "dock.rectangle" && dock.needsConfirmation)
    #expect(both.title == "Mine" && both.output == .show) // Copperlight's own headers win

    let provider = ScriptProvider(folder: folder)
    let row = try #require(provider.results(for: "ask will it ship").first)
    #expect(row.subtitle == "Prints the question back")
    #expect(await row.output?({ _ in }).preview == "[will it ship]") // one declared argument: the whole question
    #expect(provider.results(for: "restart-dock").first?.confirm == "Run Restart Dock?")
    #expect(scriptArguments(["a", "b", "c"], declared: 2) == ["a", "b c"] && scriptArguments(["a", "b"], declared: nil) == ["a", "b"])
}

// MARK: Menus

@Test func menuShortcuts() {
    #expect(menuShortcut(char: "S", modifiers: 0) == "⌘S")
    #expect(menuShortcut(char: "S", modifiers: 1) == "⇧⌘S")
    #expect(menuShortcut(char: "P", modifiers: 3) == "⌥⇧⌘P")
    #expect(menuShortcut(char: "A", modifiers: 12) == "⌃A") // 8: no ⌘
    #expect(menuShortcut(char: nil, modifiers: 0) == "")
    #expect(menuShortcut(char: "\u{8}", modifiers: 1) == "⇧⌘⌫") // keys that aren't characters, as the menu draws them
    #expect(menuShortcut(char: "\u{9}", modifiers: 12) == "⌃⇥")
    #expect(menuShortcut(char: "\u{F702}", modifiers: 0) == "⌘←")
    #expect(menuShortcut(char: "\u{F704}", modifiers: 0) == "") // one it can't draw (F1): none rather than a box
}

/// `:export pdf` finds the front app's menu item after the built-in commands, with its menu and shortcut;
/// `:` alone and a command that takes targets (`:quit saf`) don't list menus.
@MainActor @Test func menuSearch() async {
    let items = [
        MenuCommand(path: ["File", "Export as PDF…"], shortcut: "", choose: {}),
        MenuCommand(path: ["File", "Export", "PNG"], shortcut: "", choose: {}),
        MenuCommand(path: ["File", "Export To", "PDF…"], shortcut: "", choose: {}),
        MenuCommand(path: ["File", "New Tab"], shortcut: "⌘T", choose: {}),
        MenuCommand(path: ["Window", "Minimize"], shortcut: "⌘M", choose: {}),
        MenuCommand(path: ["Edit", "Copy"], shortcut: "⌘C", choose: {}),
    ]
    let rows = menuRows(items, matching: "export pdf", app: "Pages", icon: .symbol("doc"))
    #expect(rows.map(\.title) == ["Export as PDF…", "PDF…"]) // close matches only: not P-N-G
    #expect(rows.last?.subtitle == "Pages › File › Export To") // found with its submenu: Export To › PDF…
    #expect(menuRows(items, matching: "file", app: "Pages", icon: .symbol("doc")).isEmpty) // not everything in File
    #expect(rows.first?.subtitle == "Pages › File")
    #expect(menuRows(items, matching: "png", app: "Pages", icon: .symbol("doc")).first?.subtitle == "Pages › File › Export")
    #expect(menuRows(items, matching: "co", app: "Pages", icon: .symbol("doc")).isEmpty) // from 3 letters

    let minimize = Verb(keyword: "minimize", title: "Minimize Window", icon: .symbol("minus"), run: {})
    let quit = Verb(keyword: "quit", title: "Quit App", icon: .symbol("xmark"), targets: { _ in [] })
    let verbs = VerbProvider(verbs: [minimize, quit], more: { menuRows(items, matching: $0, app: "Pages", icon: .symbol("doc")) })
    let found = await verbs.results(for: ":minimize").sorted { $0.score > $1.score }
    #expect(found.map(\.title) == ["Minimize Window", "Minimize"]) // the built-in command first
    #expect(found.last?.accessory == "⌘M")
    #expect(await verbs.results(for: ":").count == 2)
    #expect(await verbs.results(for: ":quit copy").isEmpty)
}

/// Without Accessibility, `:export pdf` says what menu search needs instead of finding nothing, after everything else.
@MainActor @Test(.enabled(if: !AXIsProcessTrusted())) func menuSearchAsksForAccessibility() {
    let rows = frontMenuRows("export pdf")
    #expect(rows.map(\.id) == ["menu:access"] && rows[0].score < -1)
    #expect(frontMenuRows("ex").isEmpty) // from 3 letters, like the menus themselves
}

/// The menus of a real app, read through Accessibility: runs where the test host is allowed (Privacy & Security).
@MainActor @Test(.enabled(if: AXIsProcessTrusted())) func finderMenus() async throws {
    let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    let paths = readMenus(finder.processIdentifier).map(\.path)
    #expect(paths.contains(["File", "New Finder Window"]))
    #expect(!paths.contains { $0.first == "Apple" }) // not the Apple menu
}

// MARK: Other names

@Test func otherNamesFindThings() async {
    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(await verbs.results(for: ":turn off").first?.title == "Shut Down")
    #expect(await verbs.results(for: ":reboo").first?.title == "Restart")
    #expect(await verbs.results(for: ":sound 30").map(\.title) == ["Set Volume to 30%"]) // takes targets too
    #expect(await verbs.results(for: ":kill finder").map(\.title) == ["Force Quit Finder"])
    #expect(otherNameScore("tu", "Shut Down") == nil) // from 3 letters

    let builtins = BuiltinProvider(showNote: { _ in }, showClipboard: {}, notesFolder: URL(filePath: "/nonexistent"))
    #expect(builtins.results(for: "paste hist").map(\.id) == ["builtin:clipboard"])
    let apps = AppProvider(index: nil)
    await apps.rescan()
    #expect(await apps.results(for: "task manager").map(\.title) == ["Activity Monitor"])
    #expect(EmojiProvider().results(for: "smiley").first?.completion == "emoji ")
}

// MARK: App index

@Test func appIndexMatching() throws {
    var illustrator = AppInfo(category: "Graphics & Design", opens: ["SVG image"])
    illustrator.words = ["graphic design", "draw", "create illustrations", "design logos"]
    #expect(appInfoMatch("draw", illustrator)?.term == "draw")
    #expect(appInfoMatch("drawing", illustrator)?.term == "draw") // a longer form of the word
    #expect(appInfoMatch("logo", illustrator)?.term == "design logos")
    #expect(appInfoMatch("svg", illustrator)?.term == "SVG image")
    #expect(appInfoMatch("graphics", illustrator)?.term == "graphic design") // its own words come first
    #expect(appInfoMatch("dr", illustrator) == nil) // from 3 letters
    #expect(appInfoMatch("app", illustrator) == nil) // too common to mean anything
    #expect(appInfoMatch("drawing app", illustrator)?.term == "draw") // so it's left out of longer queries
    #expect(appInfoMatch("svg logo", illustrator).map { [$0.term, "\($0.score)"] } == ["SVG image, design logos", "0.7"]) // spread out
    #expect(appInfoMatch("svg", illustrator)?.score == 0.75) // what it opens counts less than what it does
    #expect(appInfoMatch("spreadsheet", illustrator) == nil)

    #expect(publisher("Copyright © 2025 Serif (Europe) Ltd. All rights reserved.") == "Serif (Europe) Ltd.")
    #expect(publisher("© 2016-2026 Krisp Technologies, Inc.") == "Krisp Technologies, Inc.")

    let casks = #"[{"token":"krisp","desc":"Noise cancelling application","artifacts":[{"app":["Krisp.app"]},{"zap":[]}]},"#
        + #"{"token":"x","desc":null,"artifacts":[{"app":["X.app"]}]}]"#
    let krisp = HomebrewApp(desc: "Noise cancelling application", homepage: nil)
    #expect(homebrewDescriptions(caskJSON: Data(casks.utf8)) == ["krisp.app": krisp])
    let pkg = #"[{"token":"krisp","name":["Krisp"],"desc":"Noise cancelling application","artifacts":"#
        + #"[{"uninstall":[{"quit":"ai.krisp.krispMac"}]},{"pkg":["Krisp.pkg"]}]}]"# // installed by a .pkg: no .app named
    #expect(homebrewDescriptions(caskJSON: Data(pkg.utf8)) == ["id:ai.krisp.krispmac": krisp, "krisp.app": krisp])
    #expect(pageDescription(html: #"<head><meta property="og:description" content="Clear calls &amp; smarter meetings"></head>"#)
        == "Clear calls & smarter meetings")
    #expect(pageDescription(html: #"<meta content='Fast terminal' name="description">"#) == "Fast terminal")
    #expect(pageDescription(html: "<title>No summary</title>") == nil)

    let calculator = appFacts("/System/Applications/Calculator.app")
    #expect(!calculator.version.isEmpty)
}

// MARK: Photo text

@Test func photoTextSearch() throws {
    let store = try PhotoTextStore()
    try store.add(id: "a", created: Date(timeIntervalSince1970: 100), text: "MILK\nTotal 29,99 €")
    try store.add(id: "b", created: Date(timeIntervalSince1970: 200), text: "Café menu\nEspresso 1.20")
    try store.add(id: "c", created: Date(timeIntervalSince1970: 300), text: "")
    #expect(try store.search("29.99").map(\.id) == ["a"]) // 29,99 on the tag
    #expect(try store.search("29,9").map(\.id) == ["a"]) // as typed so far
    #expect(try store.search("9.99").isEmpty) // whole words, not the middle of one
    #expect(try store.search("cafe").map(\.id) == ["b"]) // accents don't matter
    #expect(try store.search("\"").isEmpty) // no syntax error from what's typed
    #expect(try store.ids() == ["a", "b", "c"])
    try store.remove(["a"])
    #expect(try store.search("milk").isEmpty)

    // Vision reads a price drawn into a picture.
    let context = CGContext(data: nil, width: 600, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "PRICE 29.99", attributes: [.font: NSFont.boldSystemFont(ofSize: 64)]))
    context.textPosition = CGPoint(x: 30, y: 70)
    CTLineDraw(line, context)
    #expect(recognizedText(in: context.makeImage()!).contains("29.99"))
}

// MARK: Snippets

@Test @MainActor func snippetPasteKeepsTheClipboard() async {
    let pasteboard = NSPasteboard(name: .init("copperlight-test-\(UUID())"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("copied", forType: .string)
    var pasted: String?
    await pasteKeepingClipboard("snippet", pasteboard: pasteboard, paste: { pasted = pasteboard.string(forType: .string) }, wait: .zero)
    #expect(pasted == "snippet")
    #expect(pasteboard.string(forType: .string) == "copied") // so the next {clipboard} is still what you copied

    // A copy made while the paste was going on stays.
    await pasteKeepingClipboard("snippet", pasteboard: pasteboard, paste: {
        pasteboard.clearContents()
        pasteboard.setString("newer", forType: .string)
    }, wait: .zero)
    #expect(pasteboard.string(forType: .string) == "newer")
}

@Test func snippets() async throws {
    let noon = Date(timeIntervalSince1970: 1_760_356_800) // 2025-10-13 12:00 UTC
    #expect(expandSnippet("{date} {time}: {clipboard} for {query} {other}", query: "John", clipboard: "x", now: noon, timeZone: .gmt)
        == "2025-10-13 12:00: x for John {other}") // unknown placeholders stay

    let config = try Config.parse("""
        [[snippet]]
        name = "sig"
        text = \"\"\"
        Best,
        Alex\"\"\"

        [[snippet]]
        name = "reply"
        text = "Hi {query}, thanks."
        """)
    #expect(config.snippets == [.init(name: "sig", text: "Best,\nAlex"), .init(name: "reply", text: "Hi {query}, thanks.")])

    let provider = SnippetProvider()
    await provider.setSnippets(config.snippets)
    let sig = await provider.results(for: "sig")
    #expect(sig.map(\.title) == ["sig"] && sig[0].subtitle == "Best," && sig[0].preview == "Best,\nAlex" && sig[0].actionTitle == "Paste")
    let reply = await provider.results(for: "reply John")
    #expect(reply.first?.title == "reply John" && reply.first?.subtitle == "Hi John, thanks." && reply.first?.score == 100)
    #expect(await provider.results(for: "sig more").isEmpty) // no {query}: text after the name doesn't belong to it
}

// MARK: Units and time zones

@Test func units() {
    let convert = { (query: String) -> String? in
        parseUnits(query).map { "\(formatNumber(Measurement(value: $0.value, unit: $0.from).converted(to: $0.to).value, decimals: 0...2)) \($0.to.symbol)" }
    }
    #expect(convert("10 km in mi") == "6.21 mi")
    #expect(convert("10km mi") == "6.21 mi")
    #expect(convert("30c") == "86 °F") // no target: metric and US convert to each other
    #expect(convert("100 F to c") == "37.78 °C")
    #expect(convert("10 in in cm") == "25.4 cm" && convert("10 in cm") == "25.4 cm") // "in", the unit and the word
    #expect(convert("2,5 kg") == "5.51 lb")
    #expect(convert("1 gb in mb") == "1000 MB")
    #expect(convert("90 min in h") == "1.5 hr")
    #expect(convert("1 day in hours") == "24 hr")
    for text in ["10 km in kg", "10 km in km", "10 apples", "km", "25 usd to eur", "3 s"] { #expect(parseUnits(text) == nil, "\(text)") }
}

@Test func timeZones() {
    let lisbon = TimeZone(identifier: "Europe/Lisbon")!, noon = Date(timeIntervalSince1970: 1_760_356_800) // 13:00 in Lisbon (summer)
    #expect(timeZoneNamed("Tokyo")?.identifier == "Asia/Tokyo" && timeZoneNamed("new york")?.identifier == "America/New_York")
    #expect(timeZoneNamed("sf")?.identifier == "America/Los_Angeles" && timeZoneNamed("UTC") != nil && timeZoneNamed("narnia") == nil)

    let now = parseTimeZones("now in tokyo", now: noon, here: lisbon)
    #expect(now?.date == noon && now?.to.identifier == "Asia/Tokyo" && now?.fromName == nil)
    let three = parseTimeZones("3pm lisbon in sf", now: noon, here: .gmt)
    #expect(three?.from.identifier == "Europe/Lisbon" && three?.to.identifier == "America/Los_Angeles")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    #expect(three.map { calendar.component(.hour, from: $0.date) } == 7) // 3pm in Lisbon is 7am in SF
    #expect(parseTimeZones("15:30 in new york", now: noon, here: lisbon).map { calendar.component(.minute, from: $0.date) } == 30)
    for text in ["13pm in tokyo", "now in narnia", "dinner in tokyo", "3pm narnia in sf", "in tokyo"] {
        #expect(parseTimeZones(text, now: noon, here: lisbon) == nil, "\(text)")
    }
}

// MARK: Browser bookmarks and history

@Test func browserPageReaders() throws {
    let chrome = #"{"roots": {"bookmark_bar": {"type": "folder", "children": [{"type": "url", "name": "Copperlight", "url": "https://github.com/copperlight/copperlight"},"#
        + #" {"type": "folder", "children": [{"type": "url", "name": "Docs", "url": "https://developer.apple.com"}]}]}, "other": {"type": "folder", "children": []}}}"#
    #expect(chromiumBookmarks(Data(chrome.utf8)).map(\.title).sorted() == ["Copperlight", "Docs"]) // folders walked

    let safari: [String: Any] = ["Children": [
        ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://swift.org", "URIDictionary": ["title": "Swift"]],
        ["WebBookmarkType": "WebBookmarkTypeList", "Children": [["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com"]]],
    ]]
    let plist = try PropertyListSerialization.data(fromPropertyList: safari, format: .binary, options: 0)
    #expect(safariBookmarks(plist).map(\.title) == ["Swift", "https://apple.com"]) // no title: the address

    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-pages-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let history = folder.appending(path: "History").path
    try DatabaseQueue(path: history).write { db in
        try db.execute(sql: "CREATE TABLE urls (url TEXT, title TEXT, last_visit_time INTEGER, hidden INTEGER)")
        try db.execute(sql: "INSERT INTO urls VALUES ('https://a.com', 'A', 13400000000000000, 0), ('https://b.com', 'B', 13300000000000000, 0), ('https://h.com', 'H', 1, 1)")
    }
    let pages = historyPages(at: history, sql: """
        SELECT url, title, last_visit_time / 1000000.0 - 11644473600 AS visited FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC
        """, profile: "Work")
    #expect(pages.map(\.title) == ["A", "B"] && pages[0].profile == "Work" && pages[0].lastVisit! > pages[1].lastVisit!)

    try "[Profile0]\nName=default-release\nIsRelative=1\nPath=Profiles/abc.default-release\n\n[General]\nVersion=2\n"
        .write(to: folder.appending(path: "profiles.ini"), atomically: true, encoding: .utf8)
    #expect(firefoxProfiles(folder).map(\.name) == ["default-release"] && firefoxProfiles(folder)[0].folder.lastPathComponent == "abc.default-release")
}

@Test func browserPageSearch() async {
    let now = Date.now
    let provider = BrowserPagesProvider(pages: [
        BrowserPage(title: "Copperlight on GitHub", url: "https://github.com/copperlight/copperlight", bookmark: true),
        BrowserPage(title: "Old copperlight issue", url: "https://github.com/copperlight/copperlight/issues/1", lastVisit: now - 86_400),
        BrowserPage(title: "Copperlight on GitHub", url: "https://github.com/copperlight/copperlight", lastVisit: now), // also a bookmark: shown once
        BrowserPage(title: "New copperlight PR", url: "https://github.com/copperlight/copperlight/pull/2", lastVisit: now - 60),
        BrowserPage(title: "Something else", url: "https://example.com", lastVisit: now),
        BrowserPage(title: "Printer HP30138C", url: "http://192.168.1.20/status", lastVisit: now),
        BrowserPage(title: "Pitch Meeting", url: "https://youtube.com/watch?v=1", lastVisit: now),
        BrowserPage(title: "Pitch Meeting", url: "https://youtube.com/watch?v=1&t=30", lastVisit: now - 1),
    ], app: URL(filePath: "/Applications/Safari.app"))
    let rows = await provider.results(for: "copperlight git")
    #expect(rows.map(\.title) == ["Copperlight on GitHub", "New copperlight PR", "Old copperlight issue"]) // bookmarks, then most recent first
    #expect(rows[0].id.hasPrefix("bookmark:") && rows[0].subtitle == "github.com" && rows[0].score < 0 && rows[0].score > -1)
    #expect(await provider.results(for: "h").isEmpty) // from 2 letters
    #expect(await provider.results(for: "30c").isEmpty) // a word's start only: not inside "HP30138C"
    #expect(await provider.results(for: "meetings").isEmpty)
    #expect(await provider.results(for: "pitch meet").count == 1) // a title on a site once
}

// MARK: Meetings

@Test func meetingLinks() {
    #expect(joinLink(in: [nil, "Room 4", "Join: https://meet.google.com/abc-defg-hij please"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    #expect(joinLink(in: ["https://us02web.zoom.us/j/123456789?pwd=xyz"])?.host() == "us02web.zoom.us")
    #expect(joinLink(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0>"])?.host() == "teams.microsoft.com")
    #expect(joinLink(in: ["https://example.com/meet", "no link"]) == nil)
    let now = Date.now
    #expect(startsIn(now + 14 * 60 + 5, end: now + 3600, now: now) == "in 15 min")
    #expect(startsIn(now + 125 * 60, end: now + 3 * 3600, now: now) == "in 2 h 5 min")
    #expect(startsIn(now - 60, end: now + 60, now: now) == "now")
}

// MARK: System Settings

/// Tests that read what only some Macs have skip themselves elsewhere (a CI runner, an older macOS), so the suite
/// passes on any Mac: macOS 26's Settings ids and Translation, the dictionaries, the emoji picker's names file.
private let macOS26 = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))

@Test(.enabled(if: macOS26)) func settingsPagesExist() throws {
    // Every page is a Settings extension on this Mac, under its id, and every symbol exists.
    let folder = URL(filePath: "/System/Library/ExtensionKit/Extensions")
    let ids = Set(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).compactMap {
        Bundle(url: $0)?.bundleIdentifier
    })
    for page in settingsPages {
        #expect(ids.contains(page.id), "\(page.title)")
        #expect(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil, "\(page.symbol)")
    }
}

@Test func settingsPageSearch() {
    let settings = SettingsProvider()
    #expect(settings.results(for: "bluetooth").first?.title == "Bluetooth")
    #expect(settings.results(for: "dark mode").map(\.title) == ["Appearance"])
    #expect(settings.results(for: "night").map(\.title) == ["Displays"])
    #expect(settings.results(for: "bl").isEmpty) // from 3 letters
    #expect(settings.results(for: "note").isEmpty) // not n-o-t-e scattered through "Control Center"
    for query in ["wifi", "blue", "disp", "sec", "notif", "keyb", "login"] { #expect(!settings.results(for: query).isEmpty, "\(query)") }
}

/// System Settings pages are rows in the launcher (turned on for v0.2).
@Test func systemSettingsIsOn() {
    #expect(Feature.systemSettings.isOn)
}

// MARK: Emoji

@Test(.enabled(if: FileManager.default.fileExists(atPath: emojiNamesFile))) func emojiSearch() {
    #expect(emojiNames.count > 1000) // the system's names file is still where we read it
    #expect(emojiMatches("party pop").first?.emoji == "🎉")
    #expect(emojiMatches("flag portugal").map(\.emoji) == ["🇵🇹"])
    #expect(emojiMatches("thumbs").contains { $0.emoji == "👍" })
    #expect(emojiMatches("zzzqqq").isEmpty && emojiMatches(" ").isEmpty)
    let emoji = EmojiProvider()
    #expect(emoji.results(for: "emo").first?.completion == "emoji ")
    #expect(emoji.results(for: "emoji rocket").first?.title == "Rocket")
    #expect(emoji.results(for: "rocket").isEmpty) // only after "emoji"
}

// MARK: Define and translate

@Test func defineWords() {
    let (pronunciation, body) = formatDefinition("run | rən | verb (runs) 1 move fast: she ran. • run as a sport: I run. noun an act of running. ORIGIN Old English.")
    #expect(pronunciation == "rən")
    #expect(body == "verb (runs) 1 move fast: she ran.\n• run as a sport: I run.\n\nnoun an act of running.\n\nORIGIN Old English.")
    #expect(formatDefinition("no bars here").body == "no bars here")
    let define = DefineProvider()
    #expect(define.results(for: "defi").first?.completion == "define ")
    #expect(define.results(for: "define").first?.completion == "define ") // the trailing space is trimmed away
}

@Test(.enabled(if: definition(of: "serendipity") != nil)) func defineWithTheMacDictionary() {
    let define = DefineProvider()
    #expect(define.results(for: "define serendipity").first?.preview?.contains("chance") == true)
    #expect(define.results(for: "define xyzzyq").first?.title == "No definition for “xyzzyq”")
}

@Test func translateStartRow() async {
    #expect(await TranslateProvider().results(for: "trans").first?.completion == "translate ")
}

@Test(.enabled(if: macOS26)) func translateRows() async {
    let translate = TranslateProvider()
    // No language is downloaded on a fresh Mac, so the row is the download one or the translation itself.
    let row = await translate.results(for: "translate good morning to portuguese").first
    #expect(row?.subtitle == "English → Portuguese" || row?.title == "Download English → Portuguese to translate here")
    // Without "to …", English goes to your first other language in System Settings; with none, there's no row.
    let other = Locale.preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }.first { $0 != "en" }
    let untargeted = await translate.results(for: "translate how to cook").first
    if let other, let name = Locale(identifier: "en").localizedString(forLanguageCode: other) {
        #expect(untargeted.map { $0.title.contains(name) || $0.subtitle.contains(name) } == true)
    } else {
        #expect(untargeted == nil)
    }
}

// MARK: Command groups

@Test func commandGroups() async {
    let verb = { (keyword: String, title: String) in Verb(keyword: keyword, title: title, icon: .symbol("x"), run: {}) }
    let verbs = VerbProvider(verbs: [verb("left", "Left Half"), verb("left third", "Left Third"), verb("right", "Right Half"),
                                     verb("volume", "Set Volume"), verb("volume mute", "Mute")])
    #expect(Set(await verbs.results(for: ":volume").map(\.title)) == ["Set Volume", "Mute"]) // the group, nothing fuzzy
    #expect(Set(await verbs.results(for: ":left").map(\.title)) == ["Left Half", "Left Third"])
    #expect(await verbs.results(for: ":ri").map(\.title).contains("Right Half")) // not a group name: fuzzy as before
}

// MARK: Acknowledgements

/// Every package in project.yml is credited in Settings › About (MIT asks for its notice in the app), toml++ too
/// (TOMLKit bundles it), each with its copyright line, and the MIT text is there whole.
@Test func acknowledgementsCreditEveryPackage() throws {
    let projectYML = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../project.yml"), encoding: .utf8)
    let packagesBlock = projectYML.components(separatedBy: "\npackages:\n")[1].components(separatedBy: "\nsettings:")[0]
    let packages = packagesBlock.split(separator: "\n").filter { $0.hasPrefix("  ") && !$0.hasPrefix("    ") }
        .map { $0.trimmingCharacters(in: .whitespaces).dropLast() } // "  GRDB:" → "GRDB"
    #expect(packages.count == 4)
    let credited = Set(acknowledgements.map(\.package))
    for package in packages { #expect(credited.contains(String(package)), "\(package) has no acknowledgement") }
    #expect(credited.contains("toml++"))
    for credit in acknowledgements {
        #expect(credit.copyright.hasPrefix("Copyright"), "\(credit.package)")
        #expect(credit.url.scheme == "https", "\(credit.package)")
    }
    #expect(mitLicense.hasPrefix("Permission is hereby granted, free of charge"))
    #expect(mitLicense.contains("The above copyright notice and this permission notice shall be included"))
    #expect(mitLicense.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
}

// MARK: Media and toggles

@Test func togglesSayWhatEnterDoes() async {
    let verbs = VerbProvider(verbs: [Verb(keyword: "wifi", title: "Toggle Wi-Fi", icon: .symbol("wifi"), showing: { "Turn Wi-Fi Off" }, run: {})])
    #expect(await verbs.results(for: ":wifi").map(\.title) == ["Turn Wi-Fi Off"])
    #expect(await verbs.results(for: ":toggle wi").map(\.title) == ["Turn Wi-Fi Off"]) // still found by its title
}

@Test func mediaAndToggleCommands() async {
    let launcher = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    let first = { (query: String) async in await launcher.results(for: query).max { $0.score < $1.score } } // as the list shows them
    #expect(await first(":play")?.title == "Play or Pause")
    #expect(await first(":pause")?.title == "Play or Pause") // another name
    #expect(Set(await launcher.results(for: ":next").map(\.title)) == ["Next Track", "Move to Next Display"]) // the group
    #expect(await first(":previous")?.title == "Previous Track")
    #expect(["Mute", "Unmute"].contains(await first(":mute")?.title ?? ""))
    #expect(await first(":unmute")?.subtitle == ":mute")
    #expect(["Turn Wi-Fi On", "Turn Wi-Fi Off"].contains(await first(":wifi")?.title ?? ""))
    #expect(["Turn Dark Mode On", "Turn Dark Mode Off"].contains(await first(":dark")?.title ?? ""))
    #expect(await first(":outp")?.completion == ":output ") // Enter lists the Mac's sound outputs
}

@MainActor @Test func keepAwake() async {
    let launcher = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(await launcher.results(for: ":awake").first?.title == "Keep Awake")
    KeepAwake.shared.toggle()
    #expect(KeepAwake.isOn)
    #expect(await launcher.results(for: ":awake").first?.title == "Stop Keeping Awake")
    KeepAwake.shared.toggle()
    #expect(!KeepAwake.isOn)
    #expect(await launcher.results(for: ":caffeinate").first?.title == "Keep Awake")
}

@Test func soundOutputRows() {
    let outputs = [SoundOutput(id: 1, name: "MacBook Pro Speakers"), SoundOutput(id: 2, name: "AirPods Pro"), SoundOutput(id: 3, name: "U27B3M")]
    let rows = outputRows("", outputs: outputs, current: 2)
    #expect(rows.map(\.title) == ["AirPods Pro", "MacBook Pro Speakers", "U27B3M"]) // the one playing now first
    #expect(rows.map(\.subtitle) == ["Current output", "", ""])
    #expect(rows.map(\.score) == rows.map(\.score).sorted(by: >))
    #expect(outputRows("mac", outputs: outputs, current: 2).map(\.title) == ["MacBook Pro Speakers"])
}

@Test(.enabled(if: macOS26)) func translateTheClipboard() async {
    let row = await TranslateProvider(clipboard: { "bom dia, tudo bem?" }).results(for: "translate").first
    #expect(row?.subtitle == "Portuguese → English · from the clipboard" || row?.title == "Download Portuguese → English to translate here")
    let spanish = await TranslateProvider(clipboard: { "good morning" }).results(for: "translate to spanish").first
    #expect(spanish?.subtitle == "English → Spanish · from the clipboard" || spanish?.title == "Download English → Spanish to translate here")
    #expect(await TranslateProvider(clipboard: { nil }).results(for: "translate").first?.completion == "translate ") // nothing copied
    #expect(await TranslateProvider(clipboard: { "bom dia" }).results(for: "trans").first?.completion == "translate ")
}

// MARK: Mode chips

private struct Say: ResultProvider {
    var modes: [Mode] { [Mode(prefix: "say ", title: "Say", icon: .symbol("quote.bubble"), hint: "Something to say")] }
    func results(for query: String) async -> [LauncherResult] {
        [LauncherResult(id: "say", title: "said: " + query, icon: .symbol("circle"), score: 1, action: {}),
         LauncherResult(id: "start", title: "Say", icon: .symbol("circle"), score: 0, action: {}, completion: "say ")]
    }
}

private func keyDown(_ code: UInt16, _ characters: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}

@MainActor @Test func modeChips() async throws {
    let model = SearchModel(providers: [Say(), Fixed(rows: [("other", 2)])])
    let panel = LauncherPanel(model: model, placeholder: "…")
    model.typed = "say hi" // typed, a name and its space are only text: everything answers, as for "stock_Apple.pdf"
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.mode == nil && model.results.map(\.title) == ["other", "said: say hi", "Say"])
    panel.sendEvent(keyDown(48, "\t")) // Tab: the name becomes the chip, and what follows it stays in the field
    #expect(model.mode?.title == "Say" && model.typed == "hi" && model.query == "say hi")
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.results.map(\.title) == ["said: say hi", "Say"]) // its provider alone
    model.typed = ""
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.results.map(\.title) == ["said: say"]) // not the row whose Enter types what's already there
    panel.sendEvent(keyDown(51, "\u{7F}"))
    #expect(model.query == "say" && model.mode == nil) // Delete in the empty field: the chip is its text again
    model.typed = "say there"
    #expect(model.mode == nil) // its space typed again doesn't bring it back

    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider())).modes.map(\.prefix)
    #expect(verbs.contains(":quit ") && verbs.contains(":output ") && !verbs.contains(":left ")) // commands that take a name
    #expect(!verbs.contains(":! ")) // the shell's chip is ShellProvider's (":!")
    #expect(TranslateProvider().modes.first?.title == "Translate")
    #expect(CaptureProvider(addToNote: { _ in }).modes.map(\.prefix) == ["add note ", "add todo ", "add event "])
    #expect(PomodoroProvider(pomodoro: Pomodoro()).modes.map(\.prefix) == ["pomo "])
}

@MainActor @Test func tabFillsInANameAsAChip() async throws {
    let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                             context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    let translate = SearchModel(providers: [TranslateProvider(clipboard: { nil })])
    let panel = LauncherPanel(model: translate, placeholder: "…")
    translate.query = "tra"
    try await Task.sleep(for: .milliseconds(200))
    #expect(translate.selected?.key == "tab") // a row that fills in a name says Tab, not ↵
    panel.sendEvent(tab)
    #expect(translate.query == "translate " && translate.mode?.title == "Translate")

    let say = SearchModel(providers: [Say()])
    let sayPanel = LauncherPanel(model: say, placeholder: "…")
    say.query = "say"
    try await Task.sleep(for: .milliseconds(200))
    #expect(say.selected?.title == "said: say" && say.selected?.key == "↵") // the top row runs; its name is typed whole
    sayPanel.sendEvent(tab)
    #expect(say.query == "say ") // the mode whose name it is
    say.query = "zzz"
    try await Task.sleep(for: .milliseconds(200))
    sayPanel.sendEvent(tab)
    #expect(say.query == "zzz") // nothing to fill in
}

private struct Speak: ResultProvider {
    var modes: [Mode] {
        [Mode(prefix: "say ", title: "Say", icon: .symbol("x")), Mode(prefix: "say to bob ", title: "Say to Bob", icon: .symbol("x")),
         Mode(prefix: "say to ann ", title: "Say to Ann", icon: .symbol("x"))]
    }
    func results(for query: String) async -> [LauncherResult] { [] }
}

@MainActor @Test func tabMovesALongerNameIntoTheChip() async throws {
    let model = SearchModel(providers: [Speak()])
    let panel = LauncherPanel(model: model, placeholder: "…")
    let press = { (query: String) async throws -> String in
        model.query = query
        try await Task.sleep(for: .milliseconds(100))
        panel.sendEvent(keyDown(48, "\t"))
        return model.query
    }
    #expect(try await press("say") == "say " && model.mode?.title == "Say") // the shortest name: the others go on from it
    #expect(try await press("say to b") == "say to bob ") // the start of a name
    #expect(model.mode?.title == "Say to Bob" && model.typed.isEmpty)
    #expect(try await press("say hi there to b") == "say to bob hi there") // its end moves into the chip
    #expect(model.mode?.title == "Say to Bob" && model.typed == "hi there")
    #expect(try await press("say hi to bob") == "say to bob hi")
    #expect(try await press("say hi to") == "say hi to" && model.mode?.title == "Say") // Bob or Ann: the Say chip alone
    #expect(try await press("say to b") == "say to bob ")
    model.leaveMode()
    #expect(model.mode?.title == "Say" && model.typed == "to bob") // Delete takes the longer name apart, a step at a time
}

@Test(.enabled(if: macOS26)) func translateToALanguageChip() async {
    _ = await TranslateProvider.languages()
    let modes = TranslateProvider().modes
    #expect(modes.first { $0.prefix == "translate to german " }?.title == "Translate to German")
    #expect(Set(modes.map(\.prefix)).count == modes.count) // English and Chinese once each
    #expect(modes.contains { $0.prefix == "translate to norwegian " }) // one word, as it's typed
    let row = await TranslateProvider().results(for: "translate to german hello world").first // the language first
    #expect(row?.subtitle == "English → German" || row?.title == "Download English → German to translate here")
}

@MainActor @Test func theFieldFollowsTheChip() async throws {
    let model = SearchModel(providers: [Say()])
    let panel = LauncherPanel(model: model, placeholder: "…")
    // On screen but never key, so keys pressed meanwhile on this Mac stay where they were going.
    panel.orderFrontRegardless()
    defer { panel.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))
    func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
    let input = try #require(panel.contentView.flatMap { textField(in: $0) })
    panel.makeFirstResponder(input)
    let field = try #require(panel.firstResponder as? NSTextView) // its field editor, what typing goes through
    let type = { (text: String) async throws in
        field.insertText(text, replacementRange: field.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
    }
    try await type("say")
    try await type(" ")
    #expect(model.mode == nil && field.string == "say ") // a typed space is only a space
    try await type("hi")
    panel.sendEvent(keyDown(48, "\t"))
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.mode?.title == "Say" && field.string == "hi") // the name left the field for its chip
    try await type(" there")
    #expect(model.query == "say hi there" && field.string == "hi there")
}

// MARK: Stocks

private let mglu = Data("""
{"chart":{"result":[{"meta":{"currency":"BRL","symbol":"MGLU3.SA","fullExchangeName":"São Paulo","regularMarketPrice":5.75,
"regularMarketTime":1793131551,"longName":"Magazine Luiza S.A.","shortName":"MAGAZ LUIZA ON      NM","chartPreviousClose":13.58,
"previousClose":5.3},"timestamp":[1,2,3,4],"indicators":{"quote":[{"close":[13.46,null,6.1,5.75]}]}}],"error":null}}
""".utf8)
private let unknownTicker = Data(#"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#.utf8)

@Test func stockSymbols() {
    #expect(stockSymbol("aapl") == "AAPL")
    #expect(stockSymbol(" mglu3.sa ") == "MGLU3.SA")
    for symbol in ["^BVSP", "BRL=X", "BTC-USD"] { #expect(stockSymbol(symbol.lowercased()) == symbol) }
    for text in ["", "apple inc", "AAPL/", String(repeating: "A", count: 16)] { #expect(stockSymbol(text) == nil, "\(text)") }
}

@Test func stockQuotes() throws {
    let quote = try #require(parseStockChart(mglu))
    #expect(quote.symbol == "MGLU3.SA" && quote.name == "Magazine Luiza S.A." && quote.currency == "BRL")
    #expect(quote.price == 5.75 && quote.previousClose == 5.3 && quote.closes == [13.46, 6.1, 5.75]) // gaps left out
    #expect(parseStockChart(unknownTicker) == nil)
    #expect(parseStockChart(Data("<html>".utf8)) == nil)
}

@Test func stockRows() async {
    let fetches = Mutex(0)
    let provider = StockProvider(pause: .zero, locale: Locale(identifier: "en_US")) { symbol in
        fetches.withLock { $0 += 1 }
        return symbol == "MGLU3.SA" ? mglu : symbol == "NOPE" ? unknownTicker : nil
    }
    #expect(provider.modes.map(\.prefix) == ["stock "])
    #expect(await provider.results(for: "sto").first?.completion == "stock ") // Tab: the Stock chip
    #expect(await provider.results(for: "stock").first?.completion == "stock ")
    let offer = await provider.results(for: "stock aapl") // typed, not the chip: Yahoo isn't asked, a row offers it
    #expect(offer.map(\.title) == ["Stock Price of AAPL"] && offer.first?.key == "tab" && offer.first?.completion == "stock aapl")
    #expect(offer.first.map { $0.score < 0 } == true) // under files ("stock_Apple.pdf"), above Search Google
    #expect(await provider.results(for: "stock apple inc").isEmpty)
    #expect(fetches.withLock { $0 } == 0)
    let row = await provider.modeResults(for: "stock mglu3.sa").first
    #expect(row?.title == "R$5.75")
    #expect(row?.subtitle == "MGLU3.SA · Magazine Luiza S.A. · +8.49% today")
    #expect(row?.details.map(\.0) == ["MGLU3.SA", "Today", "7 days", "Previous close", "Exchange", "Updated"])
    #expect(row?.details[0].1 == "Magazine Luiza S.A.")
    #expect(row?.details[2].1 == "-57.28%") // since the chart's first close
    #expect(row?.previewImage != nil && row?.actionTitle == "Open")
    _ = await provider.modeResults(for: "stock MGLU3.SA")
    #expect(fetches.withLock { $0 } == 1) // asked again within a minute: from the cache
    #expect(await provider.modeResults(for: "stock nope").first?.title == "No stock called NOPE")
    #expect(await provider.modeResults(for: "stock offl").first?.title == "Couldn't reach Yahoo Finance")
    #expect(await provider.modeResults(for: "stock apple inc").first?.title == "Type a ticker, like AAPL")
    #expect(await provider.modeResults(for: "stock ").isEmpty) // the chip's hint says what to type
}

@MainActor @Test func stockChartImage() {
    #expect(stockChart([3, 1, 2])?.size == CGSize(width: 330, height: 190))
    #expect(stockChart([3]) == nil) // one point is no line
}
