import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreBluetooth
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
    ("39*8 usd", CurrencyQuery(amount: 312, from: "USD", to: "EUR")), // math first
    ("(10 + 5) * 2 gbp in usd", CurrencyQuery(amount: 30, from: "GBP", to: "USD")),
    ("2^10 jpy", CurrencyQuery(amount: 1024, from: "JPY", to: "EUR")),
])
func currencyParses(_ input: String, _ expected: CurrencyQuery) {
    #expect(parseCurrency(input) == expected)
}

@Test(arguments: [
    "", "25", "usd to eur", "25 us", "25 usd to", "25 usd in", "25 dollars to eur", "25 usd eur extra",
    "1.2.3 usd eur", "25 usd toeur", "25usdeur", ".5 usd eur", "25. usd eur", "-25 usd eur", "2+2",
    "hello usd", "2+ usd", "10-15 usd", "(2 usd",
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

@Test func currencyBand() throws {
    let rates = ["EUR": 1, "USD": 1.1638, "JPY": 170]
    let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12)))
    let rows = currencyRows(CurrencyQuery(amount: 25, from: "USD", to: "EUR"), rates: rates, updated: now - 120, now: now)
    // Enter copies it as money; the number alone a row below, for a spreadsheet.
    #expect(rows.map(\.title) == ["Copy €21.48", "Copy 21.48"] && rows[1].subtitle == "The number alone, for a spreadsheet")
    guard case .currency(let card)? = rows.first?.answer else { Issue.record("no band"); return }
    #expect(card.from == "$25.00" && card.fromName == "US Dollar" && card.to == "€21.48" && card.toName == "Euro")
    #expect(card.rate == "1 USD = 0.8593 EUR" && card.when == "Live rate, 2 min ago" && rows.allSatisfy { $0.answer != nil })
    // A small amount keeps its digits: a yen in euros isn't €0.01.
    let yen = currencyRows(CurrencyQuery(amount: 1, from: "JPY", to: "EUR"), rates: rates, updated: now, now: now)
    if case .currency(let card)? = yen.first?.answer { #expect(card.to == "€0.005882" && yen[1].title == "Copy 0.005882") }
    #expect(currencyRows(CurrencyQuery(amount: 1, from: "XYZ", to: "EUR"), rates: rates, updated: now).isEmpty)
    // How fresh the rate is.
    #expect(rateAge(now - 20, now: now) == "Live rate, just now" && rateAge(now - 4 * 60, now: now) == "Live rate, 4 min ago")
    #expect(rateAge(now - 3 * 3600, now: now) == "Rate from \((now - 3 * 3600).formatted(date: .omitted, time: .shortened))")
    #expect(rateAge(now - 86_400, now: now) == "Rate from yesterday")
    #expect(rateAge(now - 6 * 86_400, now: now) == "Rate from \((now - 6 * 86_400).formatted(.dateTime.month(.abbreviated).day()))")
    // The flags behind it, from the code's first two letters: EUR is the EU's; a currency of no one country has none.
    #expect(flag("USD") == "🇺🇸" && flag("EUR") == "🇪🇺" && flag("BRL") == "🇧🇷")
    #expect(flag("BTC").isEmpty && flag("XAF").isEmpty) // not Bhutan's; Central Africa's, of six countries
    // Drawn whole, cut to the flag itself: wider than tall, with no empty margin around it.
    let picture = try #require(flagPicture("🇺🇸"))
    #expect(Double(picture.width) / Double(picture.height) > 1.2 && flagPicture("") == nil)
}

@Test func liveRates() throws {
    // What api.coinbase.com/v2/exchange-rates?currency=EUR answered (Tests/Fixtures/coinbase-rates.json, trimmed): every
    // currency at once, so it never learns which one you convert; crypto too.
    let data = try Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/coinbase-rates.json"))
    let rates = try #require(parseRates(data))
    #expect(rates["EUR"] == 1 && rates["USD"] == 1.1167694154476033 && rates["BTC"] == 0.0000138151810604)
    #expect(convert(CurrencyQuery(amount: 0.1, from: "BTC", to: "EUR"), rates: rates).map { Int($0) } == 7238)
    #expect(parseRates(Data("{}".utf8)) == nil && parseRates(Data("{\"data\":{\"rates\":{}}}".utf8)) == nil)
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

/// Waits until `condition` holds, looking every 10 ms, for at most `timeout`: a busy CI machine can take a while.
@MainActor func eventually(within timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
}

@MainActor @Test func enterRunsWhatWasJustTyped() async throws {
    let typed = Typed()
    let model = SearchModel(providers: [typed, Echo(delay: .seconds(1))]) // the slow one holds the rows for the wait
    let panel = LauncherPanel(model: model, placeholder: "…")
    model.query = "sa"
    await eventually { model.results.first?.title == "sa" }
    model.query = "saf" // Enter right away, while the list still shows the rows for "sa"
    panel.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                                    isARepeat: false, keyCode: 36)))
    #expect(typed.ran.isEmpty)
    await eventually { !typed.ran.isEmpty }
    #expect(typed.ran == ["saf"]) // not "sa", the row that was showing
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

@MainActor @Test func learnedAbbreviations() async throws {
    let store = StateStore(file: try tempStateFile())
    let rows = Fixed(rows: [("ss-alias", 100), ("Safari", 1), ("Slack", 0.6)])
    let search = { (model: SearchModel, query: String) in
        model.query = query
        try await Task.sleep(for: .milliseconds(100))
        return model.results.map(\.id)
    }
    let model = SearchModel(providers: [rows], frecency: store)
    #expect(try await search(model, "ss").first == "ss-alias")
    model.picked("Slack") // Enter on Slack, with "ss" typed
    // Next time, what you picked for "ss" comes first, even over an exact alias; only for that text.
    #expect(try await search(model, "ss").first == "Slack")
    #expect(try await search(model, "s").first == "ss-alias")
    // Kept in state.json: another launcher knows it, whatever the case and the spaces.
    let again = SearchModel(providers: [rows], frecency: store)
    #expect(try await search(again, " SS ").first == "Slack")
    // Picking another for the same text takes over; long text isn't an abbreviation.
    again.picked("Safari")
    #expect(try await search(again, "ss").first == "Safari")
    _ = try await search(again, "a sentence to translate, much too long")
    again.picked("Slack")
    #expect(store.get(SearchModel.learnedSection, as: Frecency.Table.self)?.keys.sorted() == ["ss\tSafari", "ss\tSlack"])
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
        ("browser", "search", .string("brave"), { $0.browser.search = .brave }),
        ("files", "terminal", .string("Ghostty"), { $0.files.terminal = "Ghostty" }),
        ("notes", "markdown", .bool(false), { $0.notes.markdown = false }),
        ("meetings", "show_on_open", .bool(true), { $0.meetings.showOnOpen = true }),
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
    let builtins = BuiltinProvider(showNote: { _ in }, showClipboard: {}, notesFolder: URL(filePath: "/nonexistent"),
                                   noteFile: URL(filePath: "/nonexistent/note.txt"))
    func top(_ query: String) -> String? { builtins.results(for: query).max { $0.score < $1.score }?.title }
    func score(_ query: String, _ title: String) -> Double { builtins.results(for: query).first { $0.title == title }?.score ?? 0 }
    for query in ["n", "no", "NOT"] {
        #expect(score(query, "Note") > 2, "\(query)") // apps top out at 1.8 (match 1 + running 0.3 + frecency 0.5)
    }
    #expect(builtins.results(for: "note").map(\.title) == ["Note", "Notes"] && score("note", "Notes") > 2) // the list is Tab away
    #expect(builtins.results(for: "notes").allSatisfy { $0.title != "Note" })
    for query in ["cli", "clip", "CLIPBO", "clipboard"] {
        #expect(score(query, "Clipboard History") > 2 && top(query) == "Clipboard History", "\(query)")
    }
    #expect(score("cl", "Clipboard History") < 1.8) // too short: Claude, Clock… keep their place
    #expect(top("welc") == "Welcome to Copperlight" && score("we", "Welcome to Copperlight") < 1.8)
}

@MainActor private final class Opened { var files: [String] = [], created: [String] = [] }

/// Notes have no names: a note's title is its first line. `note` offers the last one and the list (Tab: the Notes chip),
/// which shows only notes, last edited first, with the next line and, beside the list, the text; then New Note. What's
/// typed in the chip finds them by what's in them. Anywhere else, from 3 letters, a note with the words shows below
/// the names.
@MainActor @Test func notesBrowser() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-notes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let main = FileManager.default.temporaryDirectory.appending(path: "note-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: main) }
    try "## Buy milk\nand bread".write(to: folder.appending(path: "work.txt"), atomically: true, encoding: .utf8)
    for name in ["2026-10-28-101010", ".hidden"] { try "".write(to: folder.appending(path: name + ".txt"), atomically: true, encoding: .utf8) }
    try "".write(to: folder.appending(path: "readme.md"), atomically: true, encoding: .utf8)
    try "Call Ana".write(to: main, atomically: true, encoding: .utf8)
    for (url, ago) in [(folder.appending(path: "work.txt"), 0.0), (main, 60), (folder.appending(path: "2026-10-28-101010.txt"), 3600)] {
        try FileManager.default.setAttributes([.modificationDate: Date.now - ago], ofItemAtPath: url.path)
    }
    let opened = Opened()
    let builtins = BuiltinProvider(showNote: { [opened] in opened.files.append($0.lastPathComponent) }, showClipboard: {},
                                   newNote: { [opened] in opened.created.append($0) }, notesFolder: folder, noteFile: main)
    #expect(builtins.modes.map(\.prefix) == ["note "])
    let list = { (typed: String) async in await builtins.modeResults(for: "note " + typed).sorted { $0.score > $1.score } }
    #expect(await list("").map(\.title) == ["Buy milk", "Call Ana", "Empty Note", "New Note"]) // last edited first, then a new one
    let work = try #require(await list("").first)
    #expect(work.subtitle == "and bread" && work.preview == "## Buy milk\nand bread")
    work.action()
    await list("").last?.action() // New Note: made and opened, nothing to name
    #expect(opened.files == ["work.txt"] && opened.created == [""])
    let bread = await list("bread")
    #expect(bread.map(\.title) == ["Buy milk", "New Note"] && bread[0].subtitle == "and bread") // by what's in it
    #expect(bread[1].subtitle == "Starting with “bread”")
    bread[1].action()
    #expect(opened.created == ["", "bread"])

    // Outside the chip, no list mixed with apps: the last note, and the list a Tab away.
    let rows = { (query: String) in builtins.results(for: query).sorted { $0.score > $1.score } }
    #expect(rows("note").map(\.title) == ["Note", "Notes"] && rows("note")[1].completion == "note ")
    #expect(rows("notes").first?.title == "Notes")
    #expect(rows("note bread").first { $0.completion == "note bread" }?.title == "Notes with “bread”")
    #expect(rows("no").map(\.title) == ["Note"]) // the last note edited
    rows("no")[0].action()
    #expect(opened.files.last == "work.txt")
    #expect(rows("new note").first?.title == "New Note")
    let anywhere = builtins.results(for: "bread").filter { $0.id.hasPrefix("note-text:") }
    #expect(anywhere.map(\.title) == ["Buy milk"] && anywhere[0].subtitle == "Note · and bread" && anywhere[0].score < 1)
    #expect(builtins.results(for: "br").allSatisfy { !$0.id.hasPrefix("note-text:") }) // from 3 letters

    let model = SearchModel(providers: [builtins, Fixed(rows: [("Notes app", 1)])])
    model.query = "note"
    try await Task.sleep(for: .milliseconds(100))
    model.complete() // Tab
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.mode?.title == "Notes" && model.rows.map(\.title) == ["Buy milk", "Call Ana", "Empty Note", "New Note"])

    #expect(noteTitle("\n  # Plan  \nmore") == "Plan" && noteTitle(" \n") == nil)
    let fresh = newNoteFile(in: folder, now: Date(timeIntervalSince1970: 0))
    #expect(fresh.pathExtension == "txt" && !FileManager.default.fileExists(atPath: fresh.path)) // written once you type
}

@MainActor @Test func noteCommands() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-notes-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try "Buy milk".write(to: folder.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "Ideas".write(to: folder.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    let verbs = VerbProvider(verbs: Verb.notes(folder: folder, main: folder.appending(path: "none.txt"), release: { _ in }))
    let delete = try #require(await verbs.results(for: ":delete note milk").first)
    #expect(delete.title == "Delete Note: Buy milk" && delete.confirm == "Move the note “Buy milk” to the Trash?")
    #expect(await verbs.results(for: ":delete note").count == 2)
    #expect(await verbs.results(for: ":rename note").isEmpty) // titles come from the first line: nothing to rename
}

@Test func markdownStyling() {
    let text = "# Title\nSome **bold**, *it* and `code`\n- [ ] milk\n- [x] bread\n> said\n1. first\n[site](https://x.com) and https://y.com"
    let pairs = Set(markdownSpans(text).map { "\((text as NSString).substring(with: $0.range))|\($0.style)" })
    for expected in ["# |marker", "# Title|heading(1)", "bold|bold", "**|marker", "it|italic", "code|code", "`|marker", "- |bullet",
                     "[ ]|checkbox(done: false)", "[x]|checkbox(done: true)", "bread|done", "> |marker", "> said|quote", "1. |bullet",
                     "site|link(\"https://x.com\")", "https://y.com|link(\"https://y.com\")"] {
        #expect(pairs.contains(expected), "\(expected)")
    }
    #expect(!pairs.contains { $0.hasPrefix("https://x.com|") }) // a link's address isn't a link of its own
    #expect(markdownSpans("2 * 3 * 4 and snake_case_name").isEmpty) // not emphasis
    let tick = checkboxToggle("- [ ] milk" as NSString, at: 3)
    #expect(tick?.range == NSRange(location: 2, length: 3) && tick?.replacement == "[x]")
    #expect(checkboxToggle("- [x] milk" as NSString, at: 2)?.replacement == "[ ]")
    #expect(checkboxToggle("plain" as NSString, at: 1) == nil)
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

@MainActor @Test func colonCommands() async {
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
    #expect(await launcher.results(for: ":fq").max { $0.score < $1.score }?.title == "Force Quit Application") // the launcher sorts by score
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
    #expect(await WebProvider().results(for: "github.com").map(\.id).sorted() == ["web:open", "web:search"])
    #expect(await WebProvider().results(for: "zzz").map(\.score) == [-10]) // below everything, files included
}

/// The last row searches the engine Settings › Browser picks, Google unless it says, with the engine's logo.
@Test func searchEngines() async throws {
    #expect(SearchEngine.google.url(for: "c++ & café").absoluteString == "https://www.google.com/search?q=c%2B%2B%20%26%20caf%C3%A9")
    #expect(SearchEngine.duckduckgo.url(for: "a b").absoluteString == "https://duckduckgo.com/?q=a%20b")
    #expect(SearchEngine.allCases.allSatisfy { NSImage(named: $0.logo) != nil })
    let web = WebProvider()
    #expect(try #require(await web.results(for: "hello").first).title == "Search Google for “hello”")
    await web.setBrowser(.init(search: .duckduckgo))
    let row = try #require(await web.results(for: "hello").first)
    #expect(row.title == "Search DuckDuckGo for “hello”")
    guard case .asset(let logo) = row.icon else { Issue.record("no logo"); return }
    #expect(logo == SearchEngine.duckduckgo.logo)
    #expect(try Config.parse("[browser]\nsearch = \"kagi\"").browser.search == .kagi)
    #expect(throws: (any Error).self) { try Config.parse("[browser]\nsearch = \"altavista\"") }
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

// MARK: Colors

@Test func colorsByTheirShape() async {
    let orange = RGBColor(red: 255, green: 136, blue: 0)
    #expect(parseColor("#ff8800")?.color == orange && parseColor("#F80")?.color == orange && parseColor("#ff8800")?.notation == .hex)
    #expect(parseColor("rgb(255, 136, 0)")?.color == orange && parseColor("rgb(255 136 0)")?.notation == .rgb)
    #expect(parseColor("hsl(32, 100%, 50%)")?.color == orange && parseColor("hsl(32 100% 50%)")?.notation == .hsl)
    #expect(parseColor("hsl(120, 100%, 25%)")?.color == RGBColor(red: 0, green: 128, blue: 0))
    #expect(parseColor("ff8800") == nil && parseColor("#ff88") == nil && parseColor("rgb(300, 0, 0)") == nil
            && parseColor("hsl(10, 120%, 50%)") == nil && parseColor("#ff8800 tea") == nil)
    #expect(orange.hex == "#ff8800" && orange.rgb == "rgb(255, 136, 0)" && orange.hsl == "hsl(32, 100%, 50%)")
    #expect(RGBColor(red: 128, green: 128, blue: 128).hsl == "hsl(0, 0%, 50%)")

    // The other notations first, then the one typed, then a step lighter and darker; Enter copies. The color itself is
    // a band over them all.
    let provider = ColorProvider()
    let rows = await provider.results(for: "#ff8800")
    #expect(rows.map(\.title) == ["rgb(255, 136, 0)", "hsl(32, 100%, 50%)", "#ff8800", "#ffa640", "#bf6600"])
    #expect(rows.map(\.accessory) == ["RGB", "HSL", "Hex", "", ""] && rows.suffix(2).map(\.subtitle) == ["A step lighter", "A step darker"])
    #expect(rows.allSatisfy { $0.actionTitle == "Copy" && answerColor($0) == orange })
    #expect(await provider.results(for: "rgb(255, 136, 0)").first?.title == "#ff8800")
    #expect(await provider.results(for: "hello").isEmpty)

    // Picking one from the screen, by its name or another word for it.
    for query in ["pick", "pick color", "color picker", "eyedropper"] {
        #expect(await provider.results(for: query).first?.title == "Pick Color", "\(query)")
    }
}

/// The color a row shows on its band, if it has one.
func answerColor(_ result: LauncherResult?) -> Copperlight.RGBColor? {
    if case .color(let color)? = result?.answer { color } else { nil }
}

@MainActor @Test func answersDrawnBig() async throws {
    let copper = RGBColor(red: 200, green: 117, blue: 51)
    #expect(copper.mixed(0.25).hex == "#d69866" && copper.mixed(-0.25).hex == "#965826")
    #expect(String(format: "%.1f", copper.contrast(with: .white)) == "3.5" && String(format: "%.1f", copper.contrast(with: .black)) == "6.0")
    #expect(RGBColor.white.contrast(with: .black) == 21)

    // The launcher draws the answer of the row you're on, or of the first, in place of the preview pane.
    struct Rows: ResultProvider {
        func results(for query: String) async -> [LauncherResult] {
            [LauncherResult(id: "a", title: "#c87533", icon: .color(copper), score: 2, action: {}, preview: "text", answer: .color(copper)),
             LauncherResult(id: "b", title: "Search", icon: .symbol("magnifyingglass"), score: 1, action: {})]
        }
        let copper: Copperlight.RGBColor
    }
    let model = SearchModel(providers: [Rows(copper: copper)])
    model.query = "#c8"
    try await Task.sleep(for: .milliseconds(100))
    model.previewOpen = true
    #expect(answerColor(model.selected) == copper && !model.showsPreview)
    model.move(1)
    if case .color(let shown)? = model.answer { #expect(shown == copper) } else { Issue.record("the band went away") }
}

// MARK: Date math

@Test func dateMath() {
    var calendar = Calendar(identifier: .gregorian)
    (calendar.timeZone, calendar.firstWeekday, calendar.minimumDaysInFirstWeek) = (.gmt, 2, 4) // weeks as in Europe
    let now = Date(timeIntervalSince1970: 1_793_203_080) // Wednesday, 2026-10-28 15:58 UTC
    let us = Locale(identifier: "en_US"), uk = Locale(identifier: "en_GB")
    let answer = { (query: String) in Copperlight.dateMath(query, now: now, calendar: calendar, locale: us) }
    let says = { (query: String) in answer(query).map { "\($0.title) | \($0.subtitle)" } }

    // How long until, or since
    #expect(says("days until dec 25") == "58 days | Until Friday, December 25, 2026")
    #expect(answer("how many days until christmas?")?.title == "58 days" && answer("days till Dec 25")?.title == "58 days")
    #expect(answer("weeks until dec 25")?.title == "8 weeks, 2 days" && answer("days until tomorrow")?.title == "1 day")
    #expect(says("days since jan 1") == "300 days | Since Thursday, January 1, 2026")
    #expect(answer("days until friday")?.title == "2 days" && answer("days since friday")?.title == "5 days")

    // A date from today, or from another date
    #expect(says("in 3 weeks") == "Wednesday, November 18, 2026 | In 21 days · week 47")
    for query in ["3 weeks from now", "3 weeks from today", "21 days from now"] { #expect(answer(query)?.title == "Wednesday, November 18, 2026") }
    #expect(answer("in a week")?.title == "Wednesday, November 4, 2026" && answer("100 days from today")?.title == "Friday, February 5, 2027")
    #expect(says("3 days ago") == "Sunday, October 25, 2026 | 3 days ago · week 43")
    #expect(answer("in 2 months")?.title == "Monday, December 28, 2026" && answer("in 1 year")?.title == "Thursday, October 28, 2027")
    #expect(answer("30 days after dec 25")?.title == "Sunday, January 24, 2027" && answer("dec 25 + 2 weeks")?.title == "Friday, January 8, 2027")
    #expect(answer("2 weeks before dec 25")?.title == "Friday, December 11, 2026" && answer("dec 25 - 1 day")?.title == "Thursday, December 24, 2026")
    #expect(answer("monday in 3 weeks")?.title == "Monday, November 16, 2026") // that week's Monday

    // A time from now
    let time = { (query: String) in Copperlight.dateMath(query, now: now, calendar: calendar, locale: uk).map { "\($0.title) | \($0.subtitle)" } }
    #expect(time("time in 4 hours") == "19:58 | Today" && time("in 90 minutes") == "17:28 | Today")
    #expect(time("in 10 hours") == "1:58 | Tomorrow" && time("4 hours from now") == "19:58 | Today")

    // A date alone: its weekday, how far, and its week
    #expect(says("dec 25") == "Friday, December 25, 2026 | In 58 days · week 52")
    #expect(answer("25 december 2027")?.title == "Saturday, December 25, 2027" && answer("Dec 25th")?.title == "Friday, December 25, 2026")
    #expect(answer("2026-12-25")?.title == "Friday, December 25, 2026" && answer("2026-12-25")!.score > 10) // over its subtraction
    #expect(says("tomorrow") == "Thursday, October 29, 2026 | Tomorrow · week 44" && answer("yesterday")?.subtitle == "Yesterday · week 44")
    #expect(answer("next friday")?.title == "Friday, November 6, 2026" && answer("last friday")?.title == "Friday, October 23, 2026")
    #expect(answer("friday")?.title == "Friday, October 30, 2026" && answer("friday")!.score < 1) // under an app called Friday
    #expect(answer("jan 1")?.title == "Friday, January 1, 2027") // the next one

    for nothing in ["feb 30", "hello", "dec", "25", "in 3 lightyears", "time in lisbon", "days until", "in weeks", "2026-13-01", "12/25"] {
        #expect(answer(nothing) == nil, "\(nothing)")
    }
    // A phrase on its way: its likely ends, answered already; the start of a question, a Tab away from its rest.
    let suggest = { (query: String) in Copperlight.dateSuggestions(query, now: now, calendar: calendar, locale: us) }
    #expect(suggest("in 3").map(\.accessory) == ["in 3 days", "in 3 weeks", "in 3 months", "in 3 hours"])
    #expect(suggest("in 3")[1].title == "Wednesday, November 18, 2026")
    #expect(suggest("3 weeks").map(\.title) == ["Wednesday, November 18, 2026", "Wednesday, October 7, 2026"])
    #expect(suggest("3 weeks").map(\.accessory) == ["3 weeks from now", "3 weeks ago"])
    #expect(suggest("days").map(\.completion) == ["days until ", "days since "] && suggest("days s").map(\.completion) == ["days since "])
    #expect(suggest("how many weeks").map(\.title) == ["Weeks Until a Date", "Weeks Since a Date"])
    for nothing in ["days until dec 25", "da", "in 3 lightyears", "hello", "3"] { #expect(suggest(nothing).isEmpty, "\(nothing)") }
}

// MARK: QR codes

@Test func qrCodes() async throws {
    let code = try #require(qrCode("https://copperlight.app"))
    #expect(code.width == code.height && code.width >= 600)
    let read = CIDetector(ofType: CIDetectorTypeQRCode, context: nil)?.features(in: CIImage(cgImage: code)).first as? CIQRCodeFeature
    #expect(read?.messageString == "https://copperlight.app") // it scans
    #expect(qrCode(String(repeating: "x", count: 5000)) == nil) // more than a QR code holds

    let provider = QRCodeProvider(clipboard: { "https://copperlight.app" })
    #expect(provider.modes.map(\.prefix) == ["qr "])
    // Typed, a row offers the chip, where the code shows beside the list.
    let offer = await provider.results(for: "qr hello world")
    #expect(offer.map(\.title) == ["QR Code for “hello world”"] && offer[0].completion == "qr hello world")
    for alone in ["qr", "qr code", "QR Co"] {
        #expect(await provider.results(for: alone).first?.completion == "qr ", "\(alone)")
    }
    #expect(await provider.results(for: "qrs").isEmpty)
    #expect(await provider.results(for: "q").isEmpty)

    // In the chip: the code for the text, or for what you copied, big, with what you can do with it beside it: Enter
    // copies the picture.
    let typed = await provider.modeResults(for: "qr hello world")
    #expect(typed.map(\.title) == ["Copy Picture", "Save to Downloads", "Copy Text"] && typed[0].actionTitle == "Copy")
    guard case .picture(_, let kicker, let title, _)? = typed.first?.answer else { Issue.record("no QR code"); return }
    #expect(kicker == "QR code" && title == "hello world")
    #expect(typed.allSatisfy { $0.answer != nil }) // it stays while you move
    let copied = await provider.modeResults(for: "qr")
    #expect(copied.last?.title == "Copy Link") // a web address
    guard case .picture(_, let fromClipboard, let link, _)? = copied.first?.answer else { Issue.record("no QR code"); return }
    #expect(fromClipboard == "QR code · from the clipboard" && link == "https://copperlight.app")
    let nothing = await QRCodeProvider(clipboard: { nil }).modeResults(for: "qr")
    #expect(nothing.first?.title == "Type text or a link" && nothing.first?.answer == nil)
    let long = await provider.modeResults(for: "qr " + String(repeating: "x", count: 5000))
    #expect(long.first?.title == "Too long for a QR code" && long.first?.answer == nil)
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

@MainActor @Test func pathRows() async throws {
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
    let typed = await provider.results(for: "deploy it's live")
    #expect(typed.first?.title == "Deploy App it's live" && typed.first?.score == 100) // the text after the name: arguments
    #expect(await typed.first?.output?({ _ in }).preview == "to it's") // quoted, so it reaches the script as typed
    #expect(await provider.results(for: "dep").first?.title == "Deploy App") // found loosely too
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
    let row = try #require(await provider.results(for: "ask will it ship").first)
    #expect(row.subtitle == "Prints the question back")
    #expect(await row.output?({ _ in }).preview == "[will it ship]") // one declared argument: the whole question
    #expect(await provider.results(for: "restart-dock").first?.confirm == "Run Restart Dock?")
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

@MainActor @Test func otherNamesFindThings() async {
    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(await verbs.results(for: ":turn off").first?.title == "Shut Down")
    #expect(await verbs.results(for: ":reboo").first?.title == "Restart")
    #expect(await verbs.results(for: ":sound 30").map(\.title) == ["Set Volume to 30%"]) // takes targets too
    #expect(await verbs.results(for: ":kill finder").map(\.title) == ["Force Quit Finder"])
    #expect(otherNameScore("tu", "Shut Down") == nil) // from 3 letters

    let builtins = BuiltinProvider(showNote: { _ in }, showClipboard: {}, notesFolder: URL(filePath: "/nonexistent"),
                                   noteFile: URL(filePath: "/nonexistent/note.txt"))
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
    let krisp = HomebrewApp(desc: "Noise cancelling application", homepage: nil, token: "krisp", name: "Krisp")
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

@Test func installAppsYouDontHave() async throws {
    let quillmark = HomebrewApp(desc: "Markdown editor", homepage: nil, token: "quillmark", name: "Quillmark")
    let casks = ["quillmark.app": quillmark, "id:com.example.quillmark": quillmark,
                 "quillmark sync.app": HomebrewApp(desc: "Syncs a Markdown editor", homepage: nil, token: "quillmark-sync", name: "Quillmark Sync"),
                 "chess clock.app": HomebrewApp(desc: "A clock for two players", homepage: nil, token: "chess-clock", name: "Chess Clock")]
    let apps = AppProvider(index: nil, brew: "/opt/homebrew/bin/brew")
    await apps.rescan()
    await apps.setCasks(casks)
    let found = await apps.results(for: "quillm")
    #expect(found.map(\.title) == ["Install Quillmark", "Install Quillmark Sync"]) // once each, the closest name first
    #expect(found.first?.id == "install:quillmark")
    #expect(found.first?.subtitle == "With Homebrew · Markdown editor")
    #expect(found.allSatisfy { $0.output != nil && $0.score < 0 }) // below apps you have; Enter runs brew
    #expect(!(await apps.results(for: "chess")).contains { $0.id.hasPrefix("install:") }) // you have an app by that name
    #expect(await apps.results(for: "qu").allSatisfy { !$0.id.hasPrefix("install:") }) // from 3 letters

    let withoutBrew = AppProvider(index: nil, brew: nil)
    await withoutBrew.setCasks(casks)
    #expect(await withoutBrew.results(for: "quillmark").isEmpty)
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
    #expect(sig.map(\.title) == ["sig"] && sig[0].subtitle == "Best," && sig[0].preview == "Best,\nAlex"
            && sig[0].actionTitle == (AXIsProcessTrusted() ? "Paste" : "Copy")) // CI has no Accessibility
    let reply = await provider.results(for: "reply John")
    #expect(reply.first?.title == "reply John" && reply.first?.subtitle == "Hi John, thanks." && reply.first?.score == 100)
    #expect(await provider.results(for: "sig more").isEmpty) // no {query}: text after the name doesn't belong to it
}

@Test func snippetCursor() async {
    // The text without {cursor}, and how far back from its end the cursor goes: the first one, if there are more.
    let placed = { (text: String) in let split = placeCursor(text); return "\(split.text)|\(split.back)" }
    #expect(placed("Dear {cursor},\nBest") == "Dear ,\nBest|6")
    #expect(placed("a{cursor}b{cursor}c") == "abc|2" && placed("no marker") == "no marker|0" && placed("end{cursor}") == "end|0")
    #expect(placed("👋🏽 {cursor}!") == "👋🏽 !|1") // characters, the way the arrow key moves

    let provider = SnippetProvider()
    await provider.setSnippets([.init(name: "dear", text: "Dear {cursor},\n\nBest,\nAlex")])
    let dear = await provider.results(for: "dear")
    #expect(dear.first?.subtitle == "Dear ," && dear.first?.preview == "Dear ,\n\nBest,\nAlex")
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

@Test func dictionaryEntryCard() {
    // Made-up entries, written the way the Mac's dictionary writes them.
    let simple = parseDefinition("serendip ser·en·dip | ˈserənˌdip | noun finding good things by chance: a happy find | another one. ORIGIN 1754: from a fairy tale.", word: "serendip")
    #expect(simple == DictionaryEntry(word: "serendip", pronunciation: "ˈserənˌdip",
                                      parts: [.init(name: "noun", senses: [.init(meaning: "finding good things by chance", example: "a happy find")])],
                                      origin: "1754: from a fairy tale."))
    // Its forms dropped, numbered meanings and bullets as meanings, grammar labels and notes left out, three at most.
    let run = parseDefinition("run | rən | verb (runs) (past; ran | ran |) 1 [no object] move fast: she ran | he ran. • run as a sport: I run. "
                              + "2 [with object] manage. It is used of shops. • go: the road runs north. noun an act of running. ORIGIN Old English.", word: "run")
    #expect(run.parts.map(\.name) == ["verb", "noun"])
    #expect(run.parts[0].senses == [.init(meaning: "move fast", example: "she ran"), .init(meaning: "run as a sport", example: "I run"),
                                    .init(meaning: "manage", example: nil)])
    #expect(run.parts[1].senses == [.init(meaning: "an act of running", example: nil)] && run.origin == "Old English.")
    #expect(parseDefinition("odd text with no parts", word: "odd").parts.isEmpty)
    // Words made from it aren't meanings of it; a colon in a note after the meaning isn't its example.
    let terse = parseDefinition("terse | tərs | adjective using few words: a terse reply. DERIVATIVES tersely | ˈtərslē | adverb "
                                + "terseness | ˈtərsnəs | noun ORIGIN Latin.", word: "terse")
    #expect(terse.parts.map(\.name) == ["adjective"] && terse.origin == "Latin.")
    let pear = parseDefinition("pear | per | noun 1 a fruit. 2 the tree which bears pears. Genus Pyrus, family Rosaceae: many kinds", word: "pear")
    #expect(pear.parts.first?.senses.last == .init(meaning: "the tree which bears pears", example: nil))

    let row = DefineProvider().row(word: "serendip", entry: "serendip | ˈserənˌdip | noun finding good things by chance.")
    #expect(row.title == "serendip" && row.actionTitle == "Open")
    guard case .entry(let entry)? = row.answer else { Issue.record("no dictionary card"); return }
    #expect(entry.parts.first?.senses.first?.meaning == "finding good things by chance")
}

@Test(.enabled(if: definition(of: "serendipity") != nil)) func defineWithTheMacDictionary() {
    let define = DefineProvider()
    guard case .entry(let entry)? = define.results(for: "define serendipity").first?.answer else { Issue.record("no card"); return }
    #expect(entry.parts.first?.senses.first?.meaning.contains("chance") == true)
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

@MainActor @Test func mediaAndToggleCommands() async {
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

@Test func connectBluetoothDevices() {
    let devices = [PairedDevice(address: "aa-01", name: "AirPods Pro", connected: false, symbol: "headphones"),
                   PairedDevice(address: "aa-02", name: "Magic Keyboard", connected: true, symbol: "keyboard"),
                   PairedDevice(address: "aa-03", name: "Desk Speaker", connected: false, symbol: "hifispeaker")]
    let rows = connectRows("", access: .allowedAlways, devices: devices)
    #expect(rows.map(\.title) == ["AirPods Pro", "Desk Speaker", "Magic Keyboard"]) // the ones to connect first
    #expect(rows.map(\.actionTitle) == ["Connect", "Connect", "Disconnect"])
    #expect(rows.map(\.subtitle) == ["", "", "Connected"])
    #expect(rows[0].output != nil && rows[2].output == nil) // connecting takes a few seconds, and says how it went
    #expect(rows.map(\.score) == rows.map(\.score).sorted(by: >))
    #expect(connectRows("air", access: .allowedAlways, devices: devices).map(\.title) == ["AirPods Pro"])
    #expect(connectRows("", access: .allowedAlways, devices: []).map(\.title) == ["No paired Bluetooth devices"])
    // Typing never asks for Bluetooth: Enter does.
    #expect(connectRows("", access: .notDetermined, devices: devices).map { [$0.title, $0.actionTitle] } == [["Connect Bluetooth Devices", "Allow"]])
    #expect(connectRows("", access: .denied, devices: devices).map { [$0.title, $0.actionTitle] }
        == [["Allow Copperlight to use Bluetooth", "Open System Settings"]])
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
    // One word each, as it's typed after "to" (Norwegian Bokmål is "norwegian"), whichever languages this Mac has.
    #expect(modes.dropFirst().allSatisfy { $0.prefix.wholeMatch(of: #/translate to \p{L}+ /#) != nil })
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

// MARK: Opening on the selection

@Test func selectionAsQuery() {
    #expect(launcherText(fromSelection: nil) == nil)
    #expect(launcherText(fromSelection: " \n\t ") == nil)
    #expect(launcherText(fromSelection: "  bom dia,\n  tudo bem?\t") == "bom dia, tudo bem?") // one line, as the field shows it
    #expect(launcherText(fromSelection: String(repeating: "a", count: 900))?.count == 500)
}

/// Chromium browsers and Electron apps share their text once asked; other apps aren't asked.
@Test func appsThatShareTextWhenAsked() throws {
    #expect(sharesTextWhenAsked(bundleID: "com.google.Chrome", bundleURL: nil))
    #expect(sharesTextWhenAsked(bundleID: "company.thebrowser.Browser", bundleURL: nil)) // Arc
    #expect(!sharesTextWhenAsked(bundleID: "com.apple.TextEdit", bundleURL: URL(filePath: "/System/Applications/TextEdit.app")))
    let electron = FileManager.default.temporaryDirectory.appending(path: "Slack-\(UUID().uuidString).app")
    try FileManager.default.createDirectory(at: electron.appending(path: "Contents/Frameworks/Electron Framework.framework"),
                                            withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: electron) }
    #expect(sharesTextWhenAsked(bundleID: "com.tinyspeck.slackmacgap", bundleURL: electron))
}

@Test func selfAssignedAddressesStayOut() {
    #expect(isUsefulAddress("192.168.1.152") && isUsefulAddress("10.0.0.4"))
    #expect(!isUsefulAddress("169.254.202.116")) // a cable link with nothing to hand out addresses: noise
}

/// Opened on a selection, the field holds it selected: typing replaces it, Enter or Tab use it.
@MainActor @Test func theLauncherOpensOnTheSelection() async throws {
    let model = SearchModel(providers: [Say()])
    let panel = LauncherPanel(model: model, placeholder: "…")
    panel.orderFrontRegardless() // never key: keys pressed meanwhile on this Mac stay where they were going
    defer { panel.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))
    func textField(in view: NSView) -> NSTextField? {
        view as? NSTextField ?? view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
    let input = try #require(panel.contentView.flatMap { textField(in: $0) })
    panel.makeFirstResponder(input)
    let field = try #require(panel.firstResponder as? NSTextView)
    panel.begin(with: "bom dia")
    try await Task.sleep(for: .milliseconds(300))
    #expect(model.query == "bom dia" && field.string == "bom dia")
    #expect(field.selectedRange() == NSRange(location: 0, length: 7))
    field.insertText("x", replacementRange: field.selectedRange())
    try await Task.sleep(for: .milliseconds(100))
    #expect(field.string == "x" && model.query == "x")
    panel.begin(with: nil)
    try await Task.sleep(for: .milliseconds(200))
    #expect(model.query == "" && field.string == "")
}

// MARK: Recent queries

/// ↑ in the empty field brings back what was run, newest first; ↑ again, at the top of its rows, the one before. Each
/// comes back as it was run: in its chip, or typed (`stock apple` may have been a file search).
@MainActor @Test func recentQueries() async throws {
    let state = StateStore(file: try tempStateFile())
    let model = SearchModel(providers: [Say()], frecency: state)
    #expect(!model.recallOlder()) // nothing run yet
    for (text, chip) in [("say hi", true), ("safari", false), ("say hi", true)] { // again: back to the front, once
        if chip { model.fill(text) } else { model.query = text }
        model.remember()
    }
    model.query = ""
    model.query = "say there"
    model.remember() // "say there" typed, not in the chip
    model.query = ""
    #expect(model.recallOlder() && model.query == "say there" && model.mode == nil)
    #expect(model.recallOlder() && model.query == "say hi" && model.mode?.title == "Say")
    #expect(model.recallOlder() && model.query == "safari")
    #expect(model.recallOlder() && model.query == "safari") // the oldest: ↑ does nothing more
    model.query = "saf"
    #expect(!model.recallOlder()) // typed: ↑ moves in the list again
    let next = SearchModel(providers: [], frecency: state) // kept for the next launch
    #expect(next.recallOlder() && next.query == "say there")
    #expect(!SearchModel(providers: []).recallOlder()) // clipboard history keeps no queries
}

@MainActor @Test func enterRemembersAndUpRecalls() async throws {
    let model = SearchModel(providers: [Fixed(rows: [("row", 1)])], frecency: StateStore(file: try tempStateFile()))
    let panel = LauncherPanel(model: model, placeholder: "…")
    model.query = "row"
    try await Task.sleep(for: .milliseconds(100))
    panel.sendEvent(keyDown(36, "\r"))
    model.query = ""
    panel.sendEvent(keyDown(126, ""))
    #expect(model.query == "row")
}

// MARK: Lookups

@Test func listeningPorts() {
    let lsof = "p812\ncnode\nn*:3000\nn[::1]:3000\nn*:9229\np90\ncpostgres\nn127.0.0.1:5432\n"
    #expect(parseListeners(lsof) == [Listener(pid: 812, command: "node", ports: [3000, 9229]),
                                     Listener(pid: 90, command: "postgres", ports: [5432])])
    #expect(parseListeners("") == [])
}

@Test func portRows() async {
    let lookups = LookupProvider(listeners: { [Listener(pid: 812, command: "node", ports: [3000, 9229]),
                                              Listener(pid: 90, command: "postgres", ports: [5432])] })
    #expect(await lookups.results(for: "port").map(\.title) == ["node", "postgres"])
    let node = await lookups.results(for: "port 3000")
    #expect(node.map(\.title) == ["node"] && node[0].subtitle == "Listening on 3000, 9229 · pid 812")
    #expect(node[0].confirm == "End node (pid 812)? It’s listening on port 3000." && node[0].actionTitle == "End Process")
    #expect(await lookups.results(for: "port 30").map(\.title) == ["node"]) // narrows as you type
    #expect(await lookups.results(for: "port post").map(\.title) == ["postgres"]) // or by name
    #expect(await lookups.results(for: "port 8080").map(\.title) == ["Nothing is listening on port 8080"])
    #expect(await lookups.results(for: "por").first?.completion == "port ") // Tab: the Port chip
    #expect(await lookups.results(for: "portal").isEmpty)
}

@Test func batteryTitles() {
    #expect(batteryTitle(BatteryStatus(percent: 87, charging: true, onPower: true, minutes: 65)) == "87%, charging, 1:05 to full")
    #expect(batteryTitle(BatteryStatus(percent: 87, charging: false, onPower: false, minutes: 192)) == "87%, 3:12 left")
    #expect(batteryTitle(BatteryStatus(percent: 100, charging: false, onPower: true)) == "100%, charged")
    #expect(batteryTitle(BatteryStatus(percent: 80, charging: false, onPower: true)) == "80%, on power, not charging")
    #expect(batteryTitle(BatteryStatus(percent: 40, charging: true, onPower: true)) == "40%, charging") // still estimating
}

@Test func lookupRows() async {
    let lookups = LookupProvider(
        battery: { BatteryStatus(percent: 87, charging: false, onPower: false, minutes: 192, health: "Good", cycles: 312) },
        volumes: { [VolumeSpace(name: "Macintosh HD", path: "/", free: 245_000_000_000, total: 994_000_000_000)] },
        addresses: { [(address: "192.168.1.23", interface: "Wi-Fi")] })
    let battery = await lookups.results(for: "battery")
    #expect(battery.map(\.title) == ["87%, 3:12 left"] && battery[0].subtitle == "Battery · health Good · 312 cycles")
    #expect(battery[0].score == 50) // its name, whole: above the Battery settings page
    let disk = await lookups.results(for: "disk")
    #expect(disk.map(\.title) == ["245 GB free of 994 GB"] && disk[0].subtitle == "Macintosh HD · 75% used")
    #expect(await lookups.results(for: "dis").allSatisfy { $0.score < 1 }) // under Discord: "disk usage" is only another name
    let ip = await lookups.results(for: "ip")
    #expect(ip.map(\.title) == ["192.168.1.23", "Public IP"] && ip[0].subtitle == "Local IP · Wi-Fi" && ip[0].actionTitle == "Copy")
    #expect(ip[1].output != nil) // asks only on Enter
    #expect(await lookups.results(for: "my ip").count == 2) // other names
    #expect(await LookupProvider(battery: { nil }).results(for: "battery").map(\.title) == ["This Mac has no battery"])
}

// MARK: Quarters, nudging, saved layouts

@Test func quarters() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800), size = CGSize(width: 300, height: 200)
    #expect(layoutFrame(.topLeft, size: size, visible: screen) == CGRect(x: 0, y: 400, width: 500, height: 400))
    #expect(layoutFrame(.topRight, size: size, visible: screen) == CGRect(x: 500, y: 400, width: 500, height: 400))
    #expect(layoutFrame(.bottomLeft, size: size, visible: screen) == CGRect(x: 0, y: 0, width: 500, height: 400))
    #expect(layoutFrame(.bottomRight, size: size, visible: screen) == CGRect(x: 500, y: 0, width: 500, height: 400))
}

@Test func nudging() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800), window = CGRect(x: 100, y: 100, width: 400, height: 300)
    #expect(nudgedFrame(window, .left, visible: screen) == CGRect(x: 50, y: 100, width: 400, height: 300)) // 5% of the screen
    #expect(nudgedFrame(window, .right, visible: screen).minX == 150)
    #expect(nudgedFrame(window, .up, visible: screen).minY == 140) // AppKit: y grows up
    #expect(nudgedFrame(window, .down, visible: screen).minY == 60)
    #expect(nudgedFrame(CGRect(x: 20, y: 0, width: 400, height: 300), .left, visible: screen).minX == 0) // stops at the edge
    #expect(nudgedFrame(CGRect(x: 580, y: 0, width: 400, height: 300), .right, visible: screen).minX == 600)
}

@MainActor @Test func windowCommandGroups() async {
    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    #expect(Set(await verbs.results(for: ":top").map(\.title)) == ["Top Half", "Top Left Quarter", "Top Right Quarter"])
    #expect(Set(await verbs.results(for: ":nudge").map(\.title)) == ["Nudge Left", "Nudge Right", "Nudge Up", "Nudge Down"])
    #expect(await verbs.results(for: ":nudge left").first?.repeats == true)
}

@MainActor private final class Counter { var count = 0 }

/// A row that repeats (`:nudge left`): Enter runs it and the panel stays as it is, for the next press.
@MainActor @Test func repeatingRowsStay() async throws {
    let counter = Counter()
    struct Nudge: ResultProvider {
        let counter: Counter
        func results(for query: String) async -> [LauncherResult] {
            [LauncherResult(id: "nudge", title: "Nudge", icon: .symbol("arrow.left"), score: 1, action: { [counter] in counter.count += 1 },
                            repeats: true)]
        }
    }
    let model = SearchModel(providers: [Nudge(counter: counter)])
    let panel = LauncherPanel(model: model, placeholder: "…")
    model.query = "nudge"
    try await Task.sleep(for: .milliseconds(100))
    panel.sendEvent(keyDown(36, "\r"))
    panel.sendEvent(keyDown(36, "\r"))
    #expect(counter.count == 2 && model.rows.map(\.id) == ["nudge"])
}

@Test func layoutWindowsMatch() {
    #expect(matchWindows(saved: ["Inbox", "Draft", "Draft"], current: ["Draft", "Notes", "Inbox"]) == [0: 2, 1: 0, 2: 1])
    #expect(matchWindows(saved: ["A", "B"], current: ["X"]) == [0: 0]) // fewer windows now: the first go back
}

@Test func layoutScreens() {
    let laptop = CGRect(x: 0, y: 0, width: 1500, height: 900), monitor = CGRect(x: 1500, y: 0, width: 2500, height: 1400)
    let frame = CGRect(x: 1500, y: 0, width: 1250, height: 1400) // the monitor's left half
    #expect(restoredFrame(frame, screen: monitor, screens: [laptop, monitor]) == frame)
    let unplugged = restoredFrame(frame, screen: monitor, screens: [laptop]) // the same share of what's left
    #expect(unplugged.origin == .zero && abs(unplugged.width - 750) < 0.01 && abs(unplugged.height - 900) < 0.01)
}

@MainActor private final class Applied { var names: [String] = [] }

@MainActor @Test func layoutCommands() async throws {
    let store = StateStore(file: try tempStateFile())
    let window = SavedWindow(app: "com.apple.Safari", title: "Docs", frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800))
    let applied = Applied()
    let verbs = VerbProvider(verbs: Verb.layouts(store: store, capture: { [window, window] }, apply: { [applied] in applied.names.append($0.name) }))
    #expect(await verbs.results(for: ":layout").map(\.title).contains("No layouts yet: :layout save work"))
    #expect(await verbs.results(for: ":layout save").map(\.title) == ["Type a name: :layout save work"])
    #expect(await verbs.results(for: ":layout save delete").first?.actionTitle == "") // a word the commands use
    let save = try #require(await verbs.results(for: ":layout save Work").first)
    #expect(save.title == "Save Layout “Work”" && save.confirm == nil)
    let saved = try #require(await save.output?({ _ in }))
    #expect(saved.title == "Saved “Work”" && saved.subtitle == "2 windows in 1 app · :layout work puts them back")
    let restore = try #require(await verbs.results(for: ":layout wo").first { $0.id == "layout:work" })
    #expect(restore.title == "Work" && restore.subtitle == "Layout · 2 windows in 1 app")
    restore.action()
    #expect(applied.names == ["Work"])
    #expect(await verbs.results(for: ":layout save work").first?.confirm == "Replace the layout “Work”?") // any case
    let delete = try #require(await verbs.results(for: ":layout delete").first { $0.id == "layout-delete:work" })
    #expect(delete.staysOpen && delete.title == "Delete Layout “Work”")
    delete.action()
    #expect(await verbs.results(for: ":layout").allSatisfy { $0.id != "layout:work" })
    let none = VerbProvider(verbs: Verb.layouts(store: store, capture: { nil }, apply: { _ in }))
    #expect(await none.results(for: ":layout save x").first?.output?({ _ in }).title == "Allow Copperlight in Accessibility to save layouts")
}

// MARK: More of the Mac, file commands, Shortcuts with input

@MainActor @Test func moreMacCommands() async {
    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    let titles = Set(await verbs.results(for: ":").map(\.title))
    for title in ["Quit All Apps", "Quit Other Apps", "Unhide All Apps", "Log Out", "Start Screen Saver", "Show Desktop", "Open Trash",
                  "Open With", "Move to Trash", "Open in Terminal"] {
        #expect(titles.contains(title), "\(title)")
    }
    #expect(await verbs.results(for: ":quit all").first?.confirm == "Quit every app? Apps with unsaved changes ask first.")
    #expect(await verbs.results(for: ":quit others").first?.confirm == "Quit every app but the one in front? Apps with unsaved changes ask first.")
    #expect(await verbs.results(for: ":log out").first?.confirm == "Log out? Apps with unsaved changes ask first.")
    #expect(Set(await verbs.results(for: ":mute").map(\.subtitle)) == [":mute", ":mute mic"]) // one group: the sound, then the mic
    #expect(Set(await verbs.results(for: ":open").map(\.subtitle)) == [":open with", ":open trash"])
}

@Test func shortcutInput() {
    let names = ["Translate", "Translate Text", "Log Water"]
    #expect(shortcutAndInput("translate text hola", names: names).map { [$0.name, $0.input] } == ["Translate Text", "hola"]) // longest name
    #expect(shortcutAndInput("Log water 500 ml", names: names).map { [$0.name, $0.input] } == ["Log Water", "500 ml"])
    #expect(shortcutAndInput("translate", names: names) == nil) // no text: the plain row
    #expect(shortcutAndInput("trans", names: names) == nil)
    let rows = shortcutRows("log water 500 ml", names: names)
    #expect(rows.map(\.title) == ["Run Shortcut: Log Water"] && rows[0].subtitle == "With “500 ml”")
    #expect(shortcutRows("log", names: names).map(\.title) == ["Run Shortcut: Log Water"]) // narrowing, as before
}

@MainActor @Test func fileCommands() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "open-with-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "a b.txt")
    try "hi".write(to: file, atomically: true, encoding: .utf8)
    #expect(existingPathPrefix("\(file.path) text").map { [$0.path, $0.rest] } == [file.path, "text"]) // a space in its name
    #expect(existingPathPrefix(file.path).map { [$0.path, $0.rest] } == [file.path, ""])
    #expect(existingPathPrefix("readme") == nil)
    let files = FileSearchProvider()
    #expect(await openWithRows(file.path, files: files).contains { $0.title == "TextEdit" })
    #expect(await openWithRows("\(file.path) textedi", files: files).first?.title == "TextEdit")
    #expect(terminalFolder(for: file.path) == folder.path && terminalFolder(for: folder.path) == folder.path)
    let verbs = VerbProvider(verbs: Verb.launcher(files: files))
    let trash = try #require(await verbs.results(for: ":trash \(file.path)").first { $0.id == "trash:\(file.path)" })
    #expect(trash.title == "Move to Trash: a b.txt" && trash.confirm == "Move “a b.txt” to the Trash?")
    let pick = try #require(await verbs.results(for: ":open with \(folder.path)/a").first { $0.id == "open with:\(file.path)" })
    #expect(pick.completion == ":open with \(file.path) ") // Tab or Enter: then the apps
}

// MARK: The preview pane

/// In the general search the list keeps its width: Tab on a row with something to show opens the preview beside it,
/// and a row with nothing to show never leaves an empty pane. Where reading is the point (clipboard history, a chip), it's
/// open from the start.
@MainActor @Test func previewWaitsForTab() async throws {
    struct Mixed: ResultProvider {
        func results(for query: String) async -> [LauncherResult] {
            [LauncherResult(id: "note", title: "Note", icon: .symbol("note.text"), score: 2, action: {}, preview: "what it says"),
             LauncherResult(id: "app", title: "App", icon: .symbol("app"), score: 1, action: {})]
        }
    }
    let model = SearchModel(providers: [Mixed()])
    model.query = "x"
    try await Task.sleep(for: .milliseconds(100))
    #expect(!model.showsPreview) // the list keeps its width
    model.complete() // Tab
    #expect(model.showsPreview)
    model.move(1)
    #expect(!model.showsPreview) // nothing to show: no empty pane
    model.move(-1)
    #expect(model.showsPreview)
    model.complete()
    #expect(!model.showsPreview) // Tab again closes it
    model.complete()
    model.query = "y"
    try await Task.sleep(for: .milliseconds(100))
    #expect(!model.showsPreview) // a new search starts with the list alone
    let clipboard = SearchModel(providers: [Mixed()], searchesEmptyQuery: true)
    clipboard.query = ""
    try await Task.sleep(for: .milliseconds(100))
    #expect(clipboard.showsPreview)
}

// MARK: The next meeting

/// The meeting the empty launcher offers: one with a call to join, from 10 minutes before it starts to 10 after.
@Test func nextMeetingWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000), call = URL(string: "https://meet.google.com/abc-defg-hij")!
    func item(_ title: String, in minutes: Double, for length: Double = 30, link: URL? = call) -> CalendarItem {
        CalendarItem(title: title, start: now + minutes * 60, end: now + (minutes + length) * 60, link: link)
    }
    #expect(nextMeeting([item("Later", in: 25), item("Soon", in: 8)], now: now)?.title == "Soon")
    #expect(nextMeeting([item("Later", in: 25)], now: now) == nil) // more than 10 minutes away: not yet
    #expect(nextMeeting([item("Late", in: -4)], now: now)?.title == "Late") // started 4 minutes ago: still worth joining
    #expect(nextMeeting([item("Long ago", in: -20, for: 60)], now: now) == nil)
    #expect(nextMeeting([item("No call", in: 5, link: nil)], now: now) == nil) // nothing to join
    #expect(nextMeeting([item("Late", in: -4), item("Soon", in: 3)], now: now)?.title == "Soon") // the one about to start
    #expect(callService(call) == "Google Meet" && callService(URL(string: "https://acme.zoom.us/j/123")!) == "Zoom")
}

/// An event soon (15 minutes) or going gets a copper badge; Tab shows its details: the call and its link among them.
@Test func eventBadgesAndDetails() {
    let now = Date(timeIntervalSince1970: 1_000_000), call = URL(string: "https://meet.google.com/abc-defg-hij")!
    func item(in minutes: Double, for length: Double = 60) -> CalendarItem {
        CalendarItem(title: "Meet kids at school", start: now + minutes * 60, end: now + (minutes + length) * 60, link: nil)
    }
    #expect(eventBadge(item(in: 9), now: now) == "in 9 min")
    #expect(eventBadge(item(in: 17), now: now) == "in 17 min") // within the hour: coming up
    #expect(eventBadge(item(in: 90), now: now) == nil) // not soon yet
    #expect(eventBadge(item(in: -20), now: now) == "Now")
    #expect(eventBadge(item(in: -90, for: 60), now: now) == nil) // over
    var party = item(in: 9)
    (party.calendar, party.location, party.link, party.notes) = ("Family", "School gate", call, "Bring the bikes")
    (party.people, party.organizer) = (["Ana", "Mario", "Bia", "Rui", "Leo"], "Ana")
    let preview = eventPreview(party, now: now)
    #expect(preview.text.hasPrefix("Meet kids at school\n") && preview.text.hasSuffix("Bring the bikes"))
    #expect(preview.details.map(\.0) == ["Calendar", "Where", "Call", "Link", "People", "Organizer"])
    #expect(preview.details.first { $0.0 == "People" }?.1 == "Ana, Mario, Bia, Rui +1")
    #expect(preview.details.first { $0.0 == "Call" }?.1 == "Google Meet")
    #expect(preview.details.first { $0.0 == "Link" }?.1 == call.absoluteString)
}

/// The meeting to join now, on a band over its rows: how soon, its title, times and call, who's coming and a line of
/// its notes; Join and Open in Calendar under it.
@Test func meetingBand() {
    let now = Date(timeIntervalSince1970: 1_000_000), call = URL(string: "https://meet.google.com/abc-defg-hij")!
    var review = CalendarItem(title: "Design review", start: now + 6 * 60, end: now + 36 * 60, link: call, calendar: "Work", id: "e1")
    review.people = ["Ana Ribeiro", "Mario Costa", "bia@northwind.example", "Rui Lopes", "Leo Dias"]
    review.notes = "The new onboarding flow, first pass\n\n-::~:~::~:~:~:~:~:~:~:~:~\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: (US) +1 555-0100"
    let rows = joinRows(review, now: now, browser: Config.Browser(), score: 100)
    #expect(rows.map(\.title) == ["Join Google Meet", "Open in Calendar"] && rows[0].subtitle == "meet.google.com/abc-defg-hij")
    #expect(rows[0].actionTitle == "Join" && rows.allSatisfy { $0.answer != nil && !$0.hasPreview })
    guard case .meeting(let card)? = rows.first?.answer else { Issue.record("no band"); return }
    let hours = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    #expect(card.soon == "in 6 min" && card.calendar == "Work" && card.title == "Design review")
    #expect(card.when == "\(hours(review.start))–\(hours(review.end)) · Google Meet")
    #expect(card.initials == ["AR", "MC", "B", "RL"] && card.names == "Ana, Mario, bia, Rui +1")
    #expect(card.note == "The new onboarding flow, first pass")
    review.start = now - 120
    if case .meeting(let going)? = joinRows(review, now: now, browser: Config.Browser(), score: 100).first?.answer { #expect(going.soon == "Now") }
    // The notes' own first line, never a call's invitation.
    #expect(eventNote("Join Zoom Meeting\nhttps://acme.zoom.us/j/123") == nil && eventNote(nil) == nil)
    #expect(eventNote("________________\nMicrosoft Teams meeting") == nil && eventNote("\n  Bring the bikes  \nand helmets") == "Bring the bikes")
}

/// `meetings`, `agenda`, `events`: today's events. `calendar`, typed whole, too, but under the Calendar app.
@Test func eventWords() async {
    let meetings = MeetingsProvider()
    for word in ["mee", "meetings", "age", "agenda", "events", "event"] { #expect(!(await meetings.results(for: word)).isEmpty, "\(word)") }
    #expect(await meetings.results(for: "calendar").allSatisfy { $0.score < 1.5 })
    #expect(!(await meetings.results(for: "calendar")).isEmpty)
    #expect(await meetings.results(for: "cal").isEmpty) // the Calendar app's, and Evernote's
    #expect(await meetings.results(for: "eve").isEmpty)
    for word in ["wee", "week", "this week", "next week"] { #expect(!(await meetings.results(for: word)).isEmpty, "\(word)") }
    #expect(await meetings.results(for: "weekly").isEmpty)
    #expect(await meetings.results(for: "we").isEmpty)
}

/// `week`: the week you're in, each day's events (all day first, then by time), 5 a day at most; today and the days
/// before it marked. `next week`: the one after.
@Test func weekCardDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
    calendar.firstWeekday = 2 // Monday
    let at = { (day: Int, hour: Double) in calendar.date(from: DateComponents(year: 2026, month: 10, day: day))! + hour * 3600 }
    let now = at(30, 14.5) // Friday afternoon
    var items = [CalendarItem(title: "Standup", start: at(26, 9.5), end: at(26, 10), link: nil, id: "s"),
                 CalendarItem(title: "Review", start: at(30, 15.5), end: at(30, 16), link: nil, id: "r"),
                 CalendarItem(title: "Demo", start: at(30, 11), end: at(30, 12), link: nil, id: "d"),
                 CalendarItem(title: "Night flight", start: at(31, 22), end: at(31, 30), link: nil, id: "f"), // into Sunday
                 CalendarItem(title: "Holiday", start: at(30, 0), end: at(31, 0), link: nil, allDay: true, id: "h")]
    items += (0..<7).map { CalendarItem(title: "Slot \($0)", start: at(28, 9 + Double($0)), end: at(28, 9.5 + Double($0)), link: nil, id: "x") }
    let card = weekCard(items, now: now, calendar: calendar)
    #expect(card.days.count == 7 && card.days.map(\.today) == [false, false, false, false, true, false, false])
    #expect(card.days.map(\.past) == [true, true, true, true, false, false, false])
    #expect(card.days[4].events.map(\.title) == ["Holiday", "Demo", "Review"] && card.days[4].events[0].time == "All day")
    #expect(card.days[4].events.map(\.past) == [false, true, false])
    #expect(card.days[2].events.count == 5 && card.days[2].more == 2) // a repeating event's occurrences share an id
    #expect(card.days[5].events.map(\.title) == ["Night flight"] && card.days[6].events.first?.time.hasPrefix("until ") == true)
    #expect(card.count == 12 && card.kicker == "This week" && card.days.map(\.number).first == "26" && card.days.map(\.number).last == "1")
    let next = weekCard([], now: now, calendar: calendar, next: true)
    #expect(next.kicker == "Next week" && next.days.first?.number == "2")
    #expect(next.days.allSatisfy { !$0.past && !$0.today && $0.events.isEmpty })
}

/// `month`: the month you're in as a grid of whole weeks from your first weekday, each day with how many events it
/// has (the view draws up to 3 dots); today, the days before it and the days of the months around it marked.
/// `next month`: the one after.
@Test func monthCardDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
    calendar.firstWeekday = 2 // Monday
    calendar.locale = Locale(identifier: "en_US")
    let at = { (month: Int, day: Int, hour: Double) in calendar.date(from: DateComponents(year: 2026, month: month, day: day))! + hour * 3600 }
    let now = at(10, 14, 10) // a Wednesday morning
    var items: [CalendarItem] = [CalendarItem(title: "Standup", start: at(10, 14, 9), end: at(10, 14, 9.5), link: nil, id: "s"),
                 CalendarItem(title: "Review", start: at(10, 14, 15), end: at(10, 14, 16), link: nil, id: "r"),
                 CalendarItem(title: "Night flight", start: at(10, 22, 23), end: at(10, 23, 1), link: nil, id: "f"), // into the next day
                 CalendarItem(title: "Holiday", start: at(10, 5, 0), end: at(10, 6, 0), link: nil, allDay: true, id: "h"),
                 CalendarItem(title: "Gym", start: at(9, 29, 18), end: at(9, 29, 19), link: nil, id: "g")] // September's, in the first row
    for hour in 9..<14 { items.append(CalendarItem(title: "Slot", start: at(10, 20, Double(hour)), end: at(10, 20, Double(hour) + 0.5), link: nil, id: "x")) }
    let card = monthCard(items, now: now, calendar: calendar)
    #expect(card.kicker == "This month" && card.range == "October 2026" && card.weekdays == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    #expect(card.weeks.count == 5 && card.weeks.allSatisfy { $0.count == 7 })
    let days = card.weeks.flatMap { $0 }
    #expect(days[0].number == "28" && !days[0].inMonth && days[3].number == "1" && days[3].inMonth)
    #expect(days.last?.number == "1" && days.last?.inMonth == false)
    let day = { (number: String) in days.first { $0.inMonth && $0.number == number }! }
    #expect(day("14").today && !day("14").past && day("13").past && days.filter(\.today).count == 1)
    #expect(day("14").events == 2 && day("22").events == 1 && day("23").events == 1)
    #expect(day("5").events == 1 && day("6").events == 0)
    #expect(day("20").events == 5 && days[1].events == 1) // September's gym shows in its row, faded
    #expect(card.count == 9) // October's: a repeating event's occurrences share an id, not a start
    let next = monthCard([], now: now, calendar: calendar, next: true)
    #expect(next.kicker == "Next month" && next.range == "November 2026" && next.weeks.count == 6)
    #expect(next.weeks.flatMap { $0 }.allSatisfy { !$0.past && !$0.today && $0.events == 0 })
}

@MainActor @Test func theEmptyFieldShowsWhatsUpNext() async throws {
    let model = SearchModel(providers: [Fixed(rows: [("x", 1)])],
                            idle: { [LauncherResult(id: "meeting:next", title: "Design review", icon: .symbol("video"), score: 100, action: {})] })
    model.query = ""
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.rows.map(\.title) == ["Design review"])
    model.query = "x"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.rows.map(\.title) == ["x"]) // typing: it steps aside
    #expect(SearchModel(providers: []).rows.isEmpty)
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
    let asked = await provider.modeResults(for: "stock mglu3.sa")
    // At once, the card's shape with its ticker, loading; the price fills it in.
    guard case .stock(let loading)? = asked.first?.answer else { Issue.record("no card while loading"); return }
    #expect(loading.loading && loading.kicker == "MGLU3.SA" && asked.first?.later != nil)
    let row = await settled(asked).first
    #expect(row?.title == "R$5.75")
    #expect(row?.subtitle == "MGLU3.SA · Magazine Luiza S.A. · +8.49% today")
    #expect(row?.actionTitle == "Open")
    // Across the whole card: the price, today's change, the 7 days' chart and the numbers under it.
    guard case .stock(let card)? = row?.answer else { Issue.record("no stock card"); return }
    #expect(card.kicker == "MGLU3.SA · Magazine Luiza S.A." && card.price == "R$5.75" && card.change == "▲ 8.49% today" && card.up)
    #expect(card.facts.map(\.0) == ["Previous close", "7 days"] && card.facts[1].1 == "-57.28%") // since the chart's first close
    #expect(card.closes.count > 1 && card.previousClose != nil && card.action == "Open in Yahoo Finance")
    #expect(await provider.modeResults(for: "stock MGLU3.SA").first?.title == "R$5.75") // within a minute: kept, at once
    #expect(fetches.withLock { $0 } == 1)
    #expect(await settled(provider.modeResults(for: "stock nope")).first?.title == "No stock called NOPE")
    #expect(await settled(provider.modeResults(for: "stock offl")).first?.title == "Couldn't reach Yahoo Finance")
    #expect(await provider.modeResults(for: "stock apple inc").first?.title == "Type a ticker, like AAPL")
    #expect(await provider.modeResults(for: "stock ").isEmpty) // the chip's hint says what to type
}

// MARK: Timers

@Test func timerCommands() {
    #expect(parseTimer("10") == .start(seconds: 600, label: ""))
    #expect(parseTimer("10 min tea") == .start(seconds: 600, label: "tea"))
    #expect(parseTimer("10m for the laundry") == .start(seconds: 600, label: "the laundry"))
    #expect(parseTimer("90s") == .start(seconds: 90, label: ""))
    #expect(parseTimer("90 seconds eggs") == .start(seconds: 90, label: "eggs"))
    #expect(parseTimer("1h30m") == .start(seconds: 5400, label: ""))
    #expect(parseTimer("1 hour 30 call mom") == .start(seconds: 5400, label: "call mom")) // a bare number after hours: minutes
    #expect(parseTimer("10 20") == .start(seconds: 600, label: "20"))
    #expect(parseTimer("2,5 min") == .start(seconds: 150, label: ""))
    #expect(parseTimer("24h") == .start(seconds: 86400, label: ""))
    #expect(parseTimer("stop") == .stop)
    #expect(parseTimer("s") == .stop)
    for none in ["", "tea", "0", "0 min", "25h", "stopp", "-5"] { #expect(parseTimer(none) == nil, "\(none)") }
}

@MainActor @Test func timerRows() async throws {
    let store = StateStore(file: try tempStateFile())
    let timer = TimerProvider(clock: Countdown(store: store))
    #expect(timer.modes.map(\.prefix) == ["timer "])
    #expect(await timer.results(for: "tim").first?.completion == "timer ") // Tab: the Timer chip
    let start = await timer.results(for: "timer 10 min tea").first
    #expect(start?.title == "Start Timer" && start?.subtitle == "10 minutes · tea" && start?.confirm == nil && start?.score == 50)
    #expect(await timer.results(for: "timer 1h30m").first?.subtitle == "1 hour, 30 minutes")
    #expect(await timer.results(for: "timer tea").first?.title == "Type a length, like 10 min")
    #expect(await timer.results(for: "timer stop").first?.title == "No timer running")
    #expect(await timer.results(for: "timer ").isEmpty) // the chip's hint says what to type
    #expect(await timer.results(for: "time in tokyo").isEmpty) // the time zones'
    #expect(await PomodoroProvider(pomodoro: Pomodoro()).results(for: "timer").isEmpty) // "timer" is the timer's now

    // One running, kept in state.json like the pomodoro: "timer" offers to stop it, a new one asks first.
    let deadline = Date(timeIntervalSince1970: (Date.now + 300).timeIntervalSince1970.rounded(.down)) // state.json keeps seconds
    store.set("timer", Countdown.Running(deadline: deadline, seconds: 600, label: "tea"))
    let countdown = Countdown(store: store)
    countdown.restore()
    let running = TimerProvider(clock: countdown)
    let stop = await running.results(for: "timer").max { $0.score < $1.score }
    #expect(stop?.title == "Stop Timer" && stop?.subtitle.hasPrefix("tea · ends ") == true)
    #expect(stop?.ticking == .down(to: deadline)) // the time left ticks, like the menu bar's
    #expect(await running.results(for: "timer 5").first?.confirm?.hasPrefix("Replace the running timer") == true)
    countdown.stop()
    #expect(store.get("timer", as: Countdown.Running.self) == nil)
}

@MainActor @Test func pomodoroWhileRunning() async throws {
    let store = StateStore(file: try tempStateFile())
    let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)) // state.json keeps seconds
    store.set("pomodoro", Pomodoro.Running(deadline: now + 600, minutes: 25))
    let pomodoro = Pomodoro(store: store)
    pomodoro.restore()
    let provider = PomodoroProvider(pomodoro: pomodoro)
    let rows = await provider.results(for: "pomo").sorted { $0.score > $1.score }
    #expect(rows.map(\.title) == ["Stop Pomodoro", "Take a Break"]) // not another one: it's running
    #expect(rows.first?.ticking == .down(to: now + 600)) // the time left ticks, like the menu bar's
    #expect(await provider.results(for: "pomo 50").first?.confirm != nil) // asked for by length: replaces it, after asking
    pomodoro.stop()

    store.set("pomodoro", Pomodoro.Running(deadline: now + 300, minutes: 5, isBreak: true))
    pomodoro.restore()
    #expect(await provider.results(for: "pomo").sorted { $0.score > $1.score }.map(\.title) == ["Stop Break", "Start Pomodoro"])
    pomodoro.stop()
}

@MainActor @Test func timerUntil() async throws {
    #expect(parseTimer("until 15:30 standup") == .until(hour: 15, minute: 30, label: "standup"))
    #expect(parseTimer("until 3pm") == .until(hour: 15, minute: 0, label: ""))
    #expect(parseTimer("at 9:05am call mom") == .until(hour: 9, minute: 5, label: "call mom"))
    #expect(parseTimer("till 12am") == .until(hour: 0, minute: 0, label: ""))
    #expect(parseTimer("until 12:15 pm") == .until(hour: 12, minute: 15, label: ""))
    for none in ["until", "until 25:00", "until 13pm", "until 9:75", "until noon"] { #expect(parseTimer(none) == nil, "\(none)") }
    let four = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 16)))
    #expect(nextTime(hour: 16, minute: 30, after: four) == four + 1800)
    #expect(nextTime(hour: 15, minute: 30, after: four) == four + 23.5 * 3600) // gone today: tomorrow's

    let timer = TimerProvider(clock: Countdown(store: StateStore(file: try tempStateFile())))
    let start = try #require(await timer.results(for: "timer until 23:59 standup").first)
    #expect(start.title == "Start Timer" && start.subtitle.hasPrefix("Until ") && start.subtitle.hasSuffix(" · standup"))
}

@MainActor @Test func stopwatch() async throws {
    #expect(elapsedTime(75) == "1:15")
    #expect(elapsedTime(3723) == "1:02:03")
    let store = StateStore(file: try tempStateFile())
    let rows = StopwatchProvider(watch: Stopwatch(store: store))
    #expect(await rows.results(for: "stopw").first?.title == "Start Stopwatch")
    #expect(await rows.results(for: "sto").isEmpty) // "stop" stops things

    // Running, kept in state.json: "stopwatch" stops it, its time counting up on the row.
    let started = Date(timeIntervalSince1970: (Date.now - 75).timeIntervalSince1970.rounded(.down)) // state.json keeps seconds
    store.set("stopwatch", started)
    let watch = Stopwatch(store: store)
    watch.restore()
    let stop = try #require(await StopwatchProvider(watch: watch).results(for: "stopwatch").first)
    #expect(stop.title == "Stop Stopwatch" && stop.ticking == .up(from: started))
    #expect(try #require(watch.stop()) >= 75)
    #expect(store.get("stopwatch", as: Date.self) == nil && watch.stop() == nil)
}

@MainActor @Test func runningClocksWaitInTheEmptyLauncher() throws {
    let store = StateStore(file: try tempStateFile())
    let (pomodoro, timer, watch) = (Pomodoro(store: store), Countdown(store: store), Stopwatch(store: store))
    #expect(runningClocks(pomodoro: pomodoro, timer: timer, stopwatch: watch).isEmpty)

    let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)) // state.json keeps seconds
    store.set("pomodoro", Pomodoro.Running(deadline: now + 600, minutes: 25))
    store.set("timer", Countdown.Running(deadline: now + 120, seconds: 300, label: "tea"))
    store.set("stopwatch", now - 60)
    for clock in [pomodoro.restore, timer.restore, watch.restore] { clock() }
    let rows = runningClocks(pomodoro: pomodoro, timer: timer, stopwatch: watch)
    #expect(rows.map(\.title) == ["Pomodoro", "tea", "Stopwatch"])
    #expect(rows.map(\.ticking) == [.down(to: now + 600), .down(to: now + 120), .up(from: now - 60)])
    #expect(rows.allSatisfy { $0.actionTitle == "Stop" && $0.confirm != nil }) // Enter on opening asks first
    // After the first event and before the rest: the meeting about to start keeps Enter.
    #expect(rows.allSatisfy { $0.score < 100 && $0.score > 99.99 })
    for clock in [pomodoro.stop, timer.stop] { clock() }
    _ = watch.stop()
}

// MARK: Translate to

@Test func translateTargetSetting() throws {
    #expect(Config().translate.defaultTarget == nil) // automatic: the first of your Mac's languages the text isn't in
    #expect(try Config.parse("[translate]\ndefault_target = \"german\"").translate.defaultTarget == "german")
    #expect(try Config.parse(Config.example) == Config())
}

@Test(.enabled(if: macOS26)) func translateToTheChosenLanguage() async {
    _ = await TranslateProvider.languages()
    #expect(TranslateProvider.languageChoices.contains { $0.key == "german" && $0.name == "German" })
    let translate = TranslateProvider(clipboard: { nil })
    translate.setDefaultTarget("german")
    let row = await translate.results(for: "translate good morning, how are you").first
    #expect(row?.subtitle == "English → German" || row?.title == "Download English → German to translate here")
    let already = await translate.results(for: "translate guten Morgen, wie geht es dir").first // already German: automatic
    #expect(already.map { !$0.subtitle.hasSuffix("→ German") && !$0.title.hasSuffix("→ German to translate here") } == true)
    translate.setDefaultTarget("klingon") // not one the Mac translates: automatic
    #expect(await translate.results(for: "translate good morning, how are you").first?.subtitle != "English → Klingon")
}

// MARK: Contacts

@MainActor @Test func contacts() async throws {
    let ana = Person(id: "1", name: "Ana Silva", organization: "Acme", jobTitle: "Product Designer", phones: [.init(label: "mobile", value: "+351 912 345 678")],
                     emails: [.init(label: "work", value: "ana@acme.com")], birthday: DateComponents(month: 3, day: 4))
    let bob = Person(id: "2", name: "Bob Stone", nickname: "Bobby", emails: [.init(label: "home", value: "bob@example.com")])
    let carla = Person(id: "3", name: "Carla Dias")
    let contacts = ContactsProvider(people: [ana, bob, carla], whatsApp: true)

    // Every word typed starts a word of the name, the nickname or the company, from 2 letters.
    #expect(await contacts.results(for: "ana").map(\.title) == ["Ana Silva"])
    #expect(await contacts.results(for: "silva an").map(\.title) == ["Ana Silva"])
    #expect(await contacts.results(for: "bobby").map(\.title) == ["Bob Stone"])
    #expect(await contacts.results(for: "acme").map(\.title) == ["Ana Silva"])
    #expect(await contacts.results(for: "a").isEmpty)
    #expect(await contacts.results(for: "ilva").isEmpty) // not inside a word
    let row = try #require(await contacts.results(for: "ana").first)
    #expect(row.subtitle == "+351 912 345 678 · ana@acme.com" && row.actionTitle == "Message")
    #expect(row.more?.fill == "contact Ana Silva" && row.more?.label == "Actions")
    #expect(row.score < 1 && row.score > -0.4) // below apps, above browser pages and files
    // Enter messages: a phone, else an email, else it opens the card.
    #expect(messageURL(ana)?.absoluteString == "sms:+351912345678")
    #expect(messageURL(bob)?.absoluteString == "imessage:bob@example.com")
    #expect(messageURL(carla) == nil)
    #expect(await contacts.results(for: "carla").first?.actionTitle == "Open in Contacts")
    #expect(contactCardURL("410FE041-5C4E-48DA-B4DE-04C15EA3DBAC:ABPerson") != nil)

    // Tab: the person's chip, every way to reach them, the card beside them.
    let actions = await contacts.modeResults(for: "contact Ana Silva")
    #expect(actions.map(\.title) == ["Message", "Call", "FaceTime", "WhatsApp", "Email", "Copy +351 912 345 678",
                                     "Copy ana@acme.com", "Open in Contacts"])
    #expect(actions[0].subtitle == "+351 912 345 678 · mobile" && actions[4].subtitle == "ana@acme.com · work")
    // The card beside them, on every row of theirs; a person among other results keeps the list as it is.
    guard case .person(let card)? = actions.first?.answer else { Issue.record("no card beside the actions"); return }
    #expect(card.initials == "AS" && card.name == "Ana Silva" && card.job == "Product Designer" && card.company == "Acme")
    #expect(card.details.map(\.0) == ["mobile", "work", "birthday"] && card.details[2].1 == "March 4")
    #expect(actions.allSatisfy { $0.answer != nil && !$0.hasPreview } && row.answer == nil)
    let company = personCard(Person(id: "4", name: "Northwind", organization: "Northwind")) // a company's own card
    #expect(company.initials == "N" && company.company.isEmpty)
    // Their photo, when Contacts has one, in place of the initials.
    #expect(card.photo == nil && personCard(Person(id: "5", name: "Ana Silva", photo: testPNG(width: 4, height: 4))).photo?.width == 4)
    #expect(personCard(Person(id: "5", name: "Ana Silva", photo: Data("not a picture".utf8))).photo == nil)
    #expect(await ContactsProvider(people: [ana], whatsApp: false).modeResults(for: "contact ana").allSatisfy { $0.title != "WhatsApp" })
    // In the chip: nothing typed lists everyone; a name that fits one person, their actions.
    #expect(await contacts.modeResults(for: "contact").map(\.title) == ["Ana Silva", "Bob Stone", "Carla Dias"])
    #expect(await contacts.modeResults(for: "contact bob").map(\.title) == ["Message", "Email", "Copy bob@example.com", "Open in Contacts"])

    let model = SearchModel(providers: [contacts])
    model.query = "ana"
    try await Task.sleep(for: .milliseconds(100))
    model.complete() // Tab steps into the row; Enter would have messaged
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.mode?.title == "Contact" && model.typed == "Ana Silva" && model.rows.first?.title == "Message")
}

// MARK: Browser tabs

@Test func browserTabs() async throws {
    let (us, rs) = ("\u{1F}", "\u{1E}")
    let output = ["1\(us)1\(us)Copperlight on GitHub\(us)https://github.com/example/copperlight",
                  "1\(us)2\(us)Inbox\(us)https://mail.example.com/inbox", "7\(us)1\(us)\(us)about:blank"].joined(separator: rs) + "\n"
    let tabs = parseTabs(output, browser: "com.google.Chrome")
    #expect(tabs.count == 3 && tabs[1] == BrowserTab(title: "Inbox", url: "https://mail.example.com/inbox", window: "1", index: 2,
                                                       browser: "com.google.Chrome"))
    #expect(parseTabs("", browser: "com.apple.Safari").isEmpty)

    // Enter switches to it: its window comes forward with it showing.
    #expect(switchScript(tabs[1])?.contains("set active tab index of w to 2") == true)
    #expect(switchScript(BrowserTab(title: "", url: "", window: "3", index: 4, browser: "com.apple.Safari"))?
        .contains("set current tab of w to tab 4 of w") == true)
    #expect(switchScript(BrowserTab(title: "", url: "", window: "1 \" & do shell script \"x", index: 1, browser: "com.google.Chrome")) == nil)

    // Like bookmarks: every word typed starts a word of the title or the address, from 2 letters; above them.
    let provider = BrowserTabsProvider(tabs: tabs, apps: ["com.google.Chrome": URL(filePath: "/Applications/Google Chrome.app")])
    let row = try #require(await provider.results(for: "copper git").first)
    #expect(row.title == "Copperlight on GitHub" && row.subtitle == "github.com · Tab" && row.actionTitle == "Switch to Tab")
    #expect(row.score > -0.4 && row.score < 0.5) // above browser pages, below contacts and apps
    #expect(await provider.results(for: "inbox").map(\.title) == ["Inbox"])
    #expect(await provider.results(for: "i").isEmpty)
    #expect(await provider.results(for: "tabs").first?.completion == "tabs ") // the chip, a Tab away
    // In the chip: every tab, in window order; typing narrows them.
    #expect(await provider.modeResults(for: "tabs").map(\.title) == ["Copperlight on GitHub", "Inbox", "about:blank"])
    #expect(await provider.modeResults(for: "tabs mail").map(\.title) == ["Inbox"])
}

// MARK: Text from the screen

@MainActor @Test func textFromTheScreen() async throws {
    // A picture of some text, as a region of the screen would be.
    let picture = NSImage(size: NSSize(width: 900, height: 260), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        let font = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
        ("Invoice 2041 is due" as NSString).draw(at: NSPoint(x: 30, y: 150), withAttributes: font)
        ("Total 129.90" as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: font)
        return true
    }
    let image = try #require(picture.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let read = readScreenshot(image)
    #expect(read.text == "Invoice 2041 is due\nTotal 129.90" && read.codes.isEmpty) // top to bottom
    #expect(readScreenshot(try #require(qrCode("https://copperlight.app"))).codes == ["https://copperlight.app"])

    let rows = ScreenTextProvider()
    #expect(await rows.results(for: "copy text").first?.title == "Copy Text from Screen")
    #expect(await rows.results(for: "ocr").first?.title == "Copy Text from Screen")
    #expect(await rows.results(for: "text from").first?.actionTitle == "Select")
    #expect((await rows.results(for: "cop").first?.score ?? 0) < 50) // below Copperlight Settings
}

// MARK: Spelling

@MainActor @Test func spelling() async throws {
    #expect(spellings(of: "definately", language: "en").first == "definitely") // a word: its guesses, the best first
    #expect(spellings(of: "definitely", language: "en").isEmpty)
    // Words: the text, corrected. Misspellings with one fix: which guess comes first for "leter" (letter, later, Peter)
    // differs from Mac to Mac.
    #expect(spellings(of: "I recieved it seperately", language: "en") == ["I received it separately"])

    let rows = SpellProvider(language: "en")
    let row = try #require(await rows.results(for: "spell definately").first)
    #expect(row.title == "definitely" && row.subtitle == "Spelling of “definately”" && row.actionTitle == "Copy")
    #expect(await rows.results(for: "spell definitely").first?.subtitle == "Spelled right")
    #expect(await rows.results(for: "spell qzxvbnmq").first?.title == "No spelling for “qzxvbnmq”")
    #expect(await rows.results(for: "spel").first?.completion == "spell ")
    #expect(await rows.results(for: "definately").isEmpty) // only after its name
}

// MARK: Suggestions in the empty launcher

@MainActor @Test func appSuggestions() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_793_203_080) // Wednesday 2026-10-28, 15:58 UTC
    let opened = { (app: String, days: [Double], minutes: Double) in
        days.map { AppOpen(app: "/System/Applications/\(app).app", at: now - $0 * 86_400 + minutes * 60) }
    }
    let opens = opened("Mail", [1, 2, 3], -20) + opened("Notes", [1, 2, 3, 4], 30) // on 3 days or more, within the hour
        + opened("Music", [1, 2, 2], 5) // on 2 days only: not a habit yet
        + opened("Maps", [1, 2, 3, 4], 180) // another time of day
        + opened("Books", [40, 41, 42], 0) // more than 4 weeks ago
    #expect(suggestedApps(opens, now: now, calendar: calendar) == ["/System/Applications/Notes.app", "/System/Applications/Mail.app"])
    let midnight = now + 8 * 3600 + 12 * 60 // 00:10: 23:50 is 20 minutes before it
    #expect(suggestedApps(opened("Mail", [1, 2, 3], 8 * 60 - 8), now: midnight, calendar: calendar) == ["/System/Applications/Mail.app"])

    // The rows: the app in front is already open; one that's gone isn't shown.
    let rows = suggestionRows(opens + opened("Gone", [1, 2, 3], 0), now: now, calendar: calendar, front: "/System/Applications/Notes.app")
    #expect(rows.map(\.title) == ["Mail"] && rows[0].id == "/System/Applications/Mail.app" && rows[0].subtitle == "Often around this time")
    #expect(rows[0].score < 99) // after a meeting about to start and what's running

    // Opening an app from the launcher is what they learn from; other rows aren't.
    let store = StateStore(file: try tempStateFile())
    let model = SearchModel(providers: [], frecency: store)
    model.picked("/System/Applications/Mail.app")
    model.picked("builtin:clipboard")
    #expect(store.get(AppOpen.stateSection, as: [AppOpen].self)?.map(\.app) == ["/System/Applications/Mail.app"])
    #expect(try Config.parse("[apps]\nsuggestions = false").apps.suggestions == false && Config().apps.suggestions)
}

// MARK: Large Type

@MainActor @Test func largeType() async throws {
    let large = LargeTypeProvider(clipboard: { "Wi-Fi: copper-guest" })
    let row = try #require(await large.results(for: "large 555-0100").first)
    #expect(row.title == "555-0100" && row.subtitle == "Large Type" && row.actionTitle == "Show")
    #expect(await large.results(for: "large").first?.completion == "large ") // its chip, a Tab away
    #expect(await large.modeResults(for: "large").first?.title == "Wi-Fi: copper-guest") // nothing typed: what you copied
    #expect(await large.results(for: "big text").first?.title == "Large Type")
    #expect(await LargeTypeProvider(clipboard: { nil }).modeResults(for: "large").first?.actionTitle == "")

    let window = LargeTypeWindow(text: "555-0100")
    #expect(window.canBecomeKey && window.frame == (NSScreen.main?.frame ?? window.frame))
}

// MARK: Due reminders

@MainActor @Test func dueReminders() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_793_203_080) // Wednesday 2026-10-28, 15:58 UTC
    let today = calendar.startOfDay(for: now)
    let items = [
        ReminderItem(id: "a", title: "Call the bank", due: now - 3600, allDay: false, list: "Errands"),
        ReminderItem(id: "b", title: "Water the plants", due: today, allDay: true, list: "Home"),
        ReminderItem(id: "c", title: "Send the invoice", due: now + 20 * 60, allDay: false, list: "Work"),
        ReminderItem(id: "d", title: "Book flights", due: now + 3 * 3600, allDay: false, list: "Travel"), // later today
        ReminderItem(id: "e", title: "Renew passport", due: today - 2 * 86_400, allDay: true, list: "Travel"),
    ]
    // The empty launcher: what's overdue, due within the hour, or due today with no time (by the end of it); the
    // soonest deadline first.
    let due = dueNow(items, now: now, calendar: calendar)
    #expect(due.map(\.id) == ["e", "a", "c", "b"])
    #expect(due.map { reminderBadge($0, now: now, calendar: calendar) } == ["Overdue", "Overdue", "in 20 min", "Today"])

    let provider = RemindersProvider(calendar: calendar, fetch: { items })
    let rows = await provider.upNext(now: now)
    #expect(rows.map(\.title) == ["Renew passport", "Call the bank", "Send the invoice", "Water the plants"])
    #expect(rows[0].actionTitle == "Complete" && rows[0].staysOpen && rows[0].badge == "Overdue" && rows[0].subtitle.hasPrefix("Travel"))
    #expect(rows.allSatisfy { $0.score < 99.99 && $0.score > 50 }) // after a meeting and what's running, before suggestions
    // `due`: the same, and the rest of today's.
    #expect(await provider.results(for: "due", now: now).map(\.title) == ["Renew passport", "Call the bank", "Send the invoice",
                                                                           "Book flights", "Water the plants"])
    #expect(await provider.results(for: "du", now: now).isEmpty)
}

// MARK: Calculator phrases

@Test func calculatorPhrasesAndKeepingGoing() async throws {
    #expect(calculate("20% off 80") == 64)
    #expect(calculate("30 is what % of 150") == 20)
    #expect(calculate("30 is what percent of 150") == 20)
    #expect(calculate("10k * 3") == 30_000)
    #expect(calculate("2.5k + 1") == 2501)
    #expect(calculate("10k") == nil) // a shorthand alone isn't math: it may be a file's name
    #expect(calculate("0x10 + 1") == 17) // hex keeps its letters

    let calculator = CalculatorProvider()
    #expect(await calculator.results(for: "30 is what % of 150").first?.title == "Copy 20%")
    // Tab puts the result in the field, to keep calculating with it; Enter still copies it.
    let row = try #require(await calculator.results(for: "20% off 80").first)
    #expect(row.title == "Copy 64" && row.actionTitle == "Copy" && row.more?.fill == "64" && row.more?.label == "Keep Going")

    // On a band: what was typed = the answer, and what a percentage hid beside it.
    guard case .calculation(let typed, let result, let note)? = row.answer else { Issue.record("no band"); return }
    #expect(typed == "20% off 80" && result == "64" && note == "You save 16")
    #expect(percentNote("150 + 20%") == "20% of 150 is 30" && percentNote("150 - 20%") == "20% of 150 is 30")
    #expect(percentNote("(100 + 50) + 10%") == "10% of 150 is 15")
    #expect(percentNote("2 + 3") == nil && percentNote("20% of 150") == nil && percentNote("20% of 150 + 10%") == nil)
    let hex = try #require(await calculator.results(for: "255 in hex").first)
    guard case .calculation(let typed, let result, let note)? = hex.answer else { Issue.record("no band"); return }
    #expect(typed == "255 in hex" && result == "0xFF" && note == nil && hex.title == "Copy 0xFF")
}

// MARK: Script filters

@MainActor @Test func scriptFilters() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-filters-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let script = folder.appending(path: "links.sh")
    try """
        #!/bin/sh
        # @title Team Links
        # @output rows
        printf 'Docs\\tThe handbook\\thttps://example.com/docs\\nWiki\\t\\thttps://example.com/wiki\\nOn-call: %s\\n' "$1"
        """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    // Each line a row: its title, then a subtitle and the value Enter uses, after tabs.
    #expect(scriptRows("a\tb\tc\n\nplain\n").map(\.title) == ["a", "plain"] && scriptRows("a\tb\tc\nplain").map(\.value) == ["c", "plain"])

    let provider = ScriptProvider(folder: folder)
    #expect(provider.modes.map(\.prefix) == ["links "] && provider.modes[0].title == "Team Links") // its chip
    let offer = try #require(await provider.results(for: "links").first)
    #expect(offer.title == "Team Links" && offer.completion == "links ")
    // In its chip, or typed after its name: the script prints the rows for the text.
    let rows = await provider.modeResults(for: "links ana")
    #expect(rows.map(\.title) == ["Docs", "Wiki", "On-call: ana"])
    #expect(rows[0].subtitle == "The handbook" && rows[0].actionTitle == "Open" && rows[2].actionTitle == "Copy") // a link opens
    #expect(await provider.results(for: "links ana").map(\.title) == ["Docs", "Wiki", "On-call: ana"])
}

// MARK: Processes by CPU and memory

@MainActor @Test func processesByCPUAndMemory() async throws {
    let output = """
        90001  23.8 2218656 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
        90002  14.0  708624 node
        90003   0.4 2279200 /Applications/Xcode.app/Contents/MacOS/Xcode
        bad line
        """
    let processes = parseProcesses(output)
    #expect(processes.map(\.pid) == [90001, 90002, 90003] && processes[0].cpu == 23.8 && processes[0].memory == 2_218_656 * 1024)
    #expect(processes[0].name == "Google Chrome Helper (Renderer)" && processes[0].app == "/Applications/Google Chrome.app")
    #expect(processes[1].name == "node" && processes[1].app == nil)

    let lookups = LookupProvider(processes: { processes })
    let cpu = await lookups.results(for: "cpu")
    #expect(cpu.map(\.title) == ["Google Chrome Helper (Renderer)", "node", "Xcode"]) // the busiest first
    #expect(cpu[0].subtitle.hasPrefix("23.8% CPU · ") && cpu[0].subtitle.hasSuffix(" · pid 90001"))
    #expect(cpu[0].actionTitle == "End Process" && cpu[0].confirm == "End Google Chrome Helper (Renderer) (pid 90001)?")
    #expect(cpu[2].actionTitle == "Quit" && cpu[2].confirm == "Quit Xcode?") // an app itself quits, asking to save
    let memory = await lookups.results(for: "memory")
    #expect(memory.map(\.title) == ["Xcode", "Google Chrome Helper (Renderer)", "node"] && memory[0].subtitle.hasSuffix("0.4% CPU · pid 90003"))
    #expect(await lookups.results(for: "cpu chrome").map(\.title) == ["Google Chrome Helper (Renderer)"]) // narrowed by name
    #expect(await lookups.modeResults(for: "memory no").map(\.title) == ["node"])
    #expect(await lookups.results(for: "mem").first?.completion == "memory ")
    #expect(await lookups.results(for: "kill process").first?.completion == "cpu ")
    #expect(await lookups.results(for: "ram").first?.completion == "memory ")
    let live = readProcesses() // from ps, Copperlight (which runs these tests) left out
    #expect(!live.isEmpty && !live.contains { $0.pid == getpid() })
}

// MARK: Tab actions

@MainActor @Test func tabStepsIntoWhatYouCanDoWithARow() async throws {
    struct Item: ResultProvider {
        func results(for query: String) async -> [LauncherResult] {
            [LauncherResult(id: "file", title: "report.pdf", icon: .symbol("doc"), score: 2, action: {}, actions: {
                [LauncherResult(id: "file:open", title: "Open", icon: .symbol("doc"), score: 0, action: {}),
                 LauncherResult(id: "file:reveal", title: "Reveal in Finder", icon: .symbol("folder"), score: 0, action: {})]
            }),
             LauncherResult(id: "other", title: "Other", icon: .symbol("circle"), score: 1, action: {})]
        }
    }
    let model = SearchModel(providers: [Item()])
    model.query = "rep"
    try await Task.sleep(for: .milliseconds(100))
    model.complete() // Tab: what you can do with it, in place of the list, under its name
    try await Task.sleep(for: .milliseconds(50))
    #expect(model.rows.map(\.title) == ["Open", "Reveal in Finder"] && model.rows.allSatisfy { $0.section == "report.pdf" })
    #expect(model.previewsByDefault && model.query == "rep") // the field keeps what you typed
    model.move(1)
    #expect(model.stepOut()) // Esc: back to the list, the item still selected
    #expect(model.rows.map(\.title) == ["report.pdf", "Other"] && model.selected?.id == "file")
    #expect(!model.stepOut()) // nothing to back out of: Esc hides
    model.complete()
    try await Task.sleep(for: .milliseconds(50))
    model.query = "repo" // typing searches again
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.rows.first?.title == "report.pdf")
}

@MainActor @Test func fileAppAndClipboardActions() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-actions-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "notes.txt")
    try "first line\nsecond".write(to: file, atomically: true, encoding: .utf8)

    let rows = fileActionRows(file.path, terminal: nil)
    #expect(rows.map(\.title) == ["Open", "Open With…", "Reveal in Finder", "Copy Path", "Copy File", "Open in Terminal", "Move to Trash"])
    #expect(rows[1].completion == ":open with \(file.path) " && rows.last?.confirm == "Move “notes.txt” to the Trash?")
    #expect(rows.allSatisfy { $0.details.map(\.0) == ["Where", "Kind", "Size", "Modified"] })
    #expect(await rows[0].loadPreview?() == "first line\nsecond") // a text file's text beside them
    // A folder's listing has them on each file (Tab on a folder still goes into it).
    let listed = PathProvider().results(for: folder.path + "/").first { $0.title == "notes.txt" }
    #expect(listed?.actions != nil)

    // An app: what you can do depends on whether it's running.
    #expect(appActionRows("/System/Applications/Chess.app").map(\.title) == ["Open", "Reveal in Finder", "Copy Path"])
    #expect(appActionRows(Bundle.main.bundlePath).map(\.title) // these tests run inside Copperlight
        == ["Open", "Hide", "Quit", "Force Quit", "Relaunch", "Reveal in Finder", "Copy Path"])
    let apps = AppProvider(index: nil)
    await apps.rescan()
    let found = await apps.results(for: "chess")
    #expect(!found.isEmpty && found.allSatisfy { $0.actions != nil })

    // A clipboard item: paste or copy it, and for text a link to open, Large Type, a QR code beside the list.
    let store = try ClipboardStore()
    try store.record("https://copperlight.app", app: nil, at: .now)
    let clipboard = ClipboardProvider(store: store, paste: { _ in }, copy: { _ in })
    let item = try #require(await clipboard.results(for: "").first)
    let actions = try #require(await item.actions?()).map(\.title)
    #expect(Array(actions.suffix(4)) == ["Open Link", "Large Type", "QR Code", "Delete from History"])
    #expect(actions.contains("Copy Without Pasting") == AXIsProcessTrusted()) // without Accessibility, Enter copies already
}

@MainActor @Test func appRecentDocuments() async throws {
    #expect(documentTypes("/System/Applications/Preview.app").contains("com.adobe.pdf"))
    #expect(documentTypes("/System/Applications/Calculator.app").isEmpty)
    let query = recentDocumentsQuery(["com.adobe.pdf", "public.png"])
    // Those very kinds: a .swift file is plain text too, but it opens in a code editor, not in TextEdit.
    #expect(query == #"kMDItemLastUsedDate == * && (kMDItemContentType == "com.adobe.pdf" || kMDItemContentType == "public.png")"#)
    #expect(NSPredicate(fromMetadataQueryString: query) != nil)
    #expect(await recentDocuments(of: "/System/Applications/Calculator.app").isEmpty) // it opens no documents

    let folder = FileManager.default.temporaryDirectory.appending(path: "copperlight-recent-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let path = folder.appending(path: "Quarterly report.pdf").path
    try Data("%PDF-1.4".utf8).write(to: URL(filePath: path))
    let file = FileHit(path: path, name: "Quarterly report.pdf", lastUsed: .now - 7200)
    struct App: ResultProvider {
        let file: FileHit
        func results(for query: String) async -> [LauncherResult] {
            [LauncherResult(id: "/System/Applications/Preview.app", title: "Preview", icon: .symbol("doc"), score: 1, action: {},
                            actions: { [file] in await MainActor.run { appActionRows("/System/Applications/Preview.app", recent: [file]) } })]
        }
    }
    let model = SearchModel(providers: [App(file: file)])
    model.query = "prev"
    try await Task.sleep(for: .milliseconds(100))
    model.complete() // Tab: its recent documents first, then what you can do with it
    try await Task.sleep(for: .milliseconds(50))
    let first = try #require(model.rows.first)
    #expect(first.title == "Quarterly report.pdf" && first.section == "Recent Documents" && first.actionTitle == "Open in Preview")
    #expect(first.accessory == "2h") // when it was last opened
    #expect(model.rows.dropFirst().first.map { [$0.title, $0.section] } == ["Open", "Preview"])
}

// MARK: Speed test

@Test func speedTest() async throws {
    // What `networkQuality -c` printed (Tests/Fixtures/network-quality.json, a recording trimmed to what's read).
    let json = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/network-quality.json"),
                          encoding: .utf8)
    let test = try #require(parseSpeedTest(json))
    #expect(test == SpeedTest(down: 327_886_304, up: 252_750_960, idle: 50.329254150390625, loaded: 60_000 / 194.52857971191406,
                              connection: "Wi-Fi"))
    #expect(speedText(327_886_304) == "328 Mbps" && speedText(1_250_000_000) == "1.25 Gbps" && speedText(850_000) == "850 Kbps")
    let (title, subtitle) = speedSummary(test)
    #expect(title == "328 Mbps down · 253 Mbps up" && subtitle == "Latency 50 ms, 308 ms under load · Wi-Fi")
    #expect(parseSpeedTest("") == nil && parseSpeedTest("{}") == nil)
    #expect(speedParts(327_886_304) == ("328", "Mbps") && speedParts(1_250_000_000) == ("1.25", "Gbps"))

    // The result, big: download and upload, the latency, how it was connected and when; Enter copies it.
    let tested = Date(timeIntervalSince1970: 1_793_203_080)
    let result = speedResult(test, at: tested)
    #expect(result.title == "328 Mbps down · 253 Mbps up" && result.actionTitle == "Copy")
    guard case .speed(let shown, let at, let running)? = result.answer else { Issue.record("no speed card"); return }
    #expect(shown == test && at == tested && running == nil)

    // While it runs: the card already, with the speeds so far, as networkQuality shows them to a terminal.
    let live = "\r\u{1B}[2K\rDownlink: 14.669 Mbps, 0 RPM - Uplink: 33.076 Mbps, 0 RPM\r\u{1B}[2K\rDownlink: 216.861 Mbps, 552 RPM - Uplink: 1.2 Gbps, 552 RPM"
    let soFar = try #require(parseSpeedProgress(live))
    #expect(abs(soFar.down - 216_861_000) < 1 && abs(soFar.up - 1_200_000_000) < 1 && soFar.loaded == 60_000 / 552.0 && soFar.idle == 0)
    #expect(parseSpeedProgress("") == nil && parseSpeedProgress("Downlink: 0.000 Mbps, 0 RPM - Uplink: 0.000 Mbps, 0 RPM")?.loaded == 0)
    let testing = speedTestingRow(soFar, seconds: 3)
    #expect(testing.title == "Testing internet speed…" && testing.subtitle == "3 s · Esc stops it")
    guard case .speed(let climbing, _, let seconds)? = testing.answer else { Issue.record("no card while testing"); return }
    #expect(climbing == soFar && seconds == 3)
    guard case .speed(let none, _, 0)? = speedTestingRow(nil, seconds: 0).answer else { Issue.record("no card before the first speeds"); return }
    #expect(none.down == 0 && none.up == 0)

    let row = try #require(await LookupProvider().results(for: "speed").first)
    #expect(row.title == "Test Internet Speed" && row.actionTitle == "Test" && row.output != nil) // runs on Enter only
    #expect(await LookupProvider().results(for: "speedtest").first?.title == "Test Internet Speed")
}

@Test func toolInATerminal() async {
    // Some tools only show their progress to a terminal: there, they see one.
    let check = ["-c", "if [ -t 1 ]; then echo terminal; else echo file; fi"]
    #expect(await runTool(URL(filePath: "/bin/sh"), check, terminal: true).output.trimmingCharacters(in: .whitespacesAndNewlines) == "terminal")
    #expect(await runTool(URL(filePath: "/bin/sh"), check).output.trimmingCharacters(in: .whitespacesAndNewlines) == "file")
}

// MARK: Keep awake for a while

@MainActor @Test func keepAwakeForAWhile() async throws {
    let now = Date(timeIntervalSince1970: 1_793_203_080)
    #expect(awakeDeadline("2h", now: now) == now + 7200)
    #expect(awakeDeadline("for 90 min", now: now) == now + 5400)
    #expect(awakeDeadline("30", now: now) == now + 1800) // minutes, like a timer
    let evening = try #require(awakeDeadline("until 18:00", now: now))
    #expect(Calendar.current.component(.hour, from: evening) == 18 && evening > now)
    #expect(awakeDeadline("forever", now: now) == nil && awakeDeadline("2h tea", now: now) == nil)

    let verbs = VerbProvider(verbs: Verb.launcher(files: FileSearchProvider()))
    let alone = await verbs.results(for: ":awake")
    #expect(alone.first?.title == "Keep Awake" && alone.first?.completion == nil) // Enter still turns it on
    #expect(alone.map(\.title).contains("Keep Awake for 2 hours"))
    let timed = try #require(await verbs.results(for: ":awake 2h").first)
    #expect(timed.title == "Keep Awake for 2 hours" && timed.subtitle.hasPrefix("Until "))
    #expect(await verbs.results(for: ":awake until 6pm").first?.title.hasPrefix("Keep Awake until ") == true)
    #expect(await verbs.results(for: ":aw").first { $0.id == "verb:awake" }?.completion == nil) // runs, doesn't fill in

    // On for a while: a row in the empty launcher ticks down to when it lets go, which it does by itself.
    let store = StateStore(file: try tempStateFile())
    KeepAwake.shared.start(until: .now + 1)
    defer { KeepAwake.shared.stop() }
    let until = try #require(KeepAwake.shared.until)
    #expect(KeepAwake.isOn)
    let row = runningClocks(pomodoro: Pomodoro(store: store), timer: Countdown(store: store), stopwatch: Stopwatch(store: store))
        .first { $0.id == "clock:awake" }
    #expect(row?.ticking == .down(to: until) && row?.actionTitle == "Stop")
    #expect(await verbs.results(for: ":awake").first?.title == "Stop Keeping Awake")
    try await Task.sleep(for: .milliseconds(1500))
    #expect(!KeepAwake.isOn)
}

// MARK: Your colors

@MainActor @Test func pickedColorsAreKept() async throws {
    let store = StateStore(file: try tempStateFile())
    let colors = ColorProvider(store: store)
    let empty = try #require(await colors.results(for: "colors").first)
    #expect(empty.title == "Pick Color" && empty.subtitle == "Your colors show here once you’ve picked some")

    let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)) // state.json keeps seconds
    rememberColor(RGBColor(red: 200, green: 117, blue: 51), in: store, at: now - 7200)
    rememberColor(RGBColor(red: 0, green: 0, blue: 0), in: store, at: now - 60)
    rememberColor(RGBColor(red: 200, green: 117, blue: 51), in: store, at: now) // again: back on top, once
    let rows = await colors.results(for: "colors")
    #expect(rows.map(\.title) == ["#c87533", "#000000"]) // newest first
    #expect(rows[0].subtitle == "rgb(200, 117, 51)" && rows[0].accessory == "now" && rows[0].actionTitle == "Copy")
    #expect(answerColor(rows[0]) == RGBColor(red: 200, green: 117, blue: 51)) // the one you're on, on a band over the list
    #expect(await colors.results(for: "colours").count == 2)
    #expect(await colors.results(for: "my colors").count == 2)
    for gray in 0..<40 { rememberColor(RGBColor(red: gray, green: gray, blue: gray), in: store, at: now) }
    #expect(store.get(PickedColor.stateSection, as: [PickedColor].self)?.count == PickedColor.limit) // the last 30
}

// MARK: Weather

@Test func weather() async throws {
    // What Open-Meteo answered for Lisbon (Tests/Fixtures/open-meteo-*.json, its hours trimmed to two days).
    let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
    let forecastData = try Data(contentsOf: fixtures.appending(path: "open-meteo-forecast.json"))
    let placeData = try Data(contentsOf: fixtures.appending(path: "open-meteo-geocode.json"))
    let forecast = try #require(parseForecast(forecastData))
    #expect(forecast.now.temperature == 18.6 && forecast.now.code == 0 && !forecast.now.isDay && forecast.days.count == 6)
    let place = try #require(parsePlace(placeData))
    #expect(place.name == "Lisbon" && place.latitude == 38.72509 && place.longitude == -9.1498)
    #expect(parseForecast(Data("{}".utf8)) == nil && parsePlace(Data("{}".utf8)) == nil && parsePlace(Data("{\"results\":[]}".utf8)) == nil)

    // The card: now big, the next hours, and five days with how warm each gets.
    let updated = Date(timeIntervalSince1970: 1_793_303_100)
    let card = weatherCard(forecast, place: "Lisbon", updated: updated, fahrenheit: false)
    #expect(card.place == "Lisbon" && card.temperature == "19°" && card.conditions == "Clear" && card.symbol == "moon.stars.fill")
    #expect(card.details == "H 26° · L 12° · Feels like 18° · Wind 5 km/h")
    #expect(card.hours.count == 8 && card.hours[0].label == "Now" && card.hours[0].temperature == "19°")
    #expect(card.days.count == 5 && card.days.map(\.label).prefix(2) == ["Today", "Fri"] && card.days[0].high == 25.8)
    #expect(card.updated == "Open-Meteo · updated \(updated.formatted(date: .omitted, time: .shortened))")
    let us = weatherCard(forecast, place: "Lisbon", updated: updated, fahrenheit: true)
    #expect(us.temperature == "65°" && us.details == "H 78° · L 54° · Feels like 65° · Wind 3 mph")
    #expect(weatherConditions(61, day: true).text == "Light rain" && weatherConditions(2, day: true).symbol == "cloud.sun.fill")
    #expect(weatherConditions(2, day: false).symbol == "cloud.moon.fill" && weatherConditions(95, day: true).text == "Thunderstorm")

    // The chip, a city typed: asked once typing pauses; Enter opens Weather.
    let asked = Mutex<[String]>([])
    func provider(_ status: LocationStatus, city: String = "", here: Place? = nil, fahrenheit: Bool = false) -> WeatherProvider {
        WeatherProvider(pause: .zero, city: city, status: { status }, locate: { here }, fahrenheit: fahrenheit, fetch: { url in
            asked.withLock { $0.append(url.absoluteString) }
            return url.host()?.hasPrefix("geocoding") == true ? placeData : forecastData
        })
    }
    let asking = await provider(.refused).modeResults(for: "weather lisbon")
    // At once, the card's shape with the place, loading; the forecast fills it in.
    guard case .weather(let loading)? = asking.first?.answer else { Issue.record("no card while loading"); return }
    #expect(loading.loading && loading.place == "Lisbon" && asking.first?.later != nil)
    let typed = await settled(asking)
    #expect(typed.first?.title == "19° · Clear" && typed.first?.subtitle == "Lisbon · H 26° L 12°" && typed.first?.actionTitle == "Open")
    guard case .weather(let shown)? = typed.first?.answer else { Issue.record("no weather card"); return }
    #expect(shown.place == "Lisbon")
    // °F where the Mac uses US units, whatever this machine uses (CI's does).
    #expect(await provider(.refused, fahrenheit: true).modeResults(for: "weather lisbon").first?.title == "65° · Clear")
    // Only a rounded place goes to the forecast: about a kilometer.
    #expect(asked.withLock { $0.last }?.contains("latitude=38.73&longitude=-9.15") == true)

    // Nothing typed: where you are; else the city from Settings; neither, a row says how.
    let here = Place(name: "Alfama", latitude: 38.7115, longitude: -9.1300)
    let local = await settled(provider(.allowed, here: here).modeResults(for: "weather "))
    if case .weather(let card)? = local.first?.answer { #expect(card.place == "Alfama") } else { Issue.record("no weather where you are") }
    let unasked = await provider(.unasked).modeResults(for: "weather ")
    #expect(unasked.first?.title == "Weather Where You Are" && unasked.first?.actionTitle == "Allow" && unasked.first?.answer == nil)
    let refused = await provider(.refused).modeResults(for: "weather ")
    #expect(refused.first?.title == "Type a city, or set yours in Settings" && refused.first?.answer == nil)
    let city = await settled(provider(.refused, city: "Lisbon").modeResults(for: "weather "))
    if case .weather(let card)? = city.first?.answer { #expect(card.place == "Lisbon") } else { Issue.record("no weather for the Settings city") }
    #expect(await settled(WeatherProvider(pause: .zero, city: "", status: { .refused }, locate: { nil }, fetch: { _ in nil })
        .modeResults(for: "weather porto")).first?.title == "Couldn't reach Open-Meteo") // Lisbon's is kept 10 minutes

    // `weather` offers the chip; `[weather] city` is the city when Location Services is off.
    #expect(await provider(.refused).results(for: "weather").first?.completion == "weather ")
    #expect(try Config.parse("[weather]\ncity = \"Lisbon\"").weather.city == "Lisbon" && Config().weather.city == nil)
}

// MARK: Turning features off

@Test func featuresInConfig() throws {
    #expect(Config().features.off.isEmpty && Config().features.isOn(.currency))
    let config = try Config.parse("[features]\ncurrency = false\nweather = true\nkeep_awake = false\n")
    #expect(config.features.off == [.currency, .keepAwake] && !config.features.isOn(.currency) && config.features.isOn(.weather))
    // A name that isn't a feature says so, typos and features not offered yet alike.
    for wrong in ["curency", "photo_text"] {
        #expect(throws: (any Error).self) { try Config.parse("[features]\n\(wrong) = false\n") }
        do { _ = try Config.parse("[features]\n\(wrong) = false\n") } catch { #expect(Config.describe(error).hasPrefix("features.\(wrong): ")) }
    }
}

/// Every feature Settings lists has a name, a line saying what it is, and a key docs/configuration.md explains.
@Test func featureList() throws {
    let docs = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../docs/configuration.md"), encoding: .utf8)
    for feature in Feature.listed {
        #expect(!feature.name.isEmpty && !feature.about.isEmpty)
        #expect(docs.contains("`\(feature.rawValue)`"), "\(feature.rawValue) isn't in docs/configuration.md")
    }
    #expect(!Feature.listed.contains(.photoText) && !Feature.photoText.isOn && !Config().features.isOn(.fileContent)) // not offered yet
    #expect(Feature.Group.allCases.allSatisfy { group in Feature.listed.contains { $0.group == group } })
}

@Test func offFeaturesAnswerNothing() async {
    let off = Gated(.calculator, CalculatorProvider(), isOn: { _ in false })
    #expect(await off.results(for: "2+2").isEmpty)
    #expect(await off.modeResults(for: "2+2").isEmpty)
    #expect(!(await Gated(.calculator, CalculatorProvider(), isOn: { _ in true }).results(for: "2+2")).isEmpty)
    #expect(Gated(.emoji, EmojiProvider(), isOn: { $0 != .emoji }).modes.isEmpty) // no chip either
    #expect(!Gated(.emoji, EmojiProvider(), isOn: { _ in true }).modes.isEmpty)
}

@MainActor @Test func offFeaturesLoseTheirCommands() async {
    let launcher = Verb.launcher(files: FileSearchProvider())
    let feature = { (keyword: String) in launcher.first { $0.keyword == keyword }?.feature }
    #expect(feature("left") == .windows && feature("window") == .windows && feature("layout") == .windows)
    #expect(feature("quit") == .runningApps && feature("reveal") == .files && feature("lock") == .mac && feature("hidden files") == .mac)
    #expect(feature("play") == .sound && feature("awake") == .keepAwake && feature("connect") == .bluetooth)
    #expect(feature("shortcut") == .shortcuts && feature("!") == .shell)
    #expect(launcher.contains { $0.keyword == "config" } && feature("config") == nil) // Copperlight's own, always there
    #expect(Verb.notes(release: { _ in }).allSatisfy { $0.feature == .notes })

    let verbs = VerbProvider(verbs: launcher, isOn: { $0 != .windows })
    #expect(!(await verbs.results(for: ":left")).contains { $0.id == "verb:left" })
    #expect(await verbs.results(for: ":qui").contains { $0.id == "verb:quit" })
    #expect(!verbs.modes.contains { $0.prefix == ":window " } && verbs.modes.contains { $0.prefix == ":quit " })

    let menu = LauncherResult(id: "menu:export", title: "Export…", icon: .symbol("doc"), score: 1, action: {})
    #expect(await VerbProvider(verbs: [], more: { _ in [menu] }, isOn: { $0 != .menus }).results(for: ":export").isEmpty)
    #expect(await VerbProvider(verbs: [], more: { _ in [menu] }, isOn: { _ in true }).results(for: ":export").count == 1)
}

@Test func offLookupsAndCaptures() async {
    let lookups = LookupProvider(battery: { BatteryStatus(percent: 87, charging: false, onPower: false) },
                                 listeners: { [Listener(pid: 812, command: "node", ports: [3000])] },
                                 isOn: { ![.speedTest, .processes].contains($0) })
    #expect(await lookups.results(for: "speed").isEmpty)
    #expect(await lookups.results(for: "port").isEmpty)
    #expect(await lookups.results(for: "cpu").isEmpty && lookups.modes.isEmpty)
    #expect(await lookups.results(for: "battery").count == 1)
    #expect(await LookupProvider(battery: { BatteryStatus(percent: 87, charging: false, onPower: false) }, isOn: { $0 != .macInfo })
        .results(for: "battery").isEmpty)

    let capture = CaptureProvider(addToNote: { _ in }, isOn: { ![.reminders, .mac].contains($0) })
    #expect(capture.modes.map(\.prefix) == ["add note ", "add event "])
    #expect(capture.results(for: "add").map(\.title) == ["Add to Note", "Add Calendar Event"])
    #expect(capture.results(for: "add todo milk").isEmpty && capture.results(for: "screenshot").isEmpty)
}

@MainActor @Test func offClocksLeaveTheEmptyLauncher() throws {
    let store = StateStore(file: try tempStateFile())
    let (pomodoro, timer, watch) = (Pomodoro(store: store), Countdown(store: store), Stopwatch(store: store))
    let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    store.set("pomodoro", Pomodoro.Running(deadline: now + 600, minutes: 25))
    store.set("stopwatch", now - 60)
    for clock in [pomodoro.restore, watch.restore] { clock() }
    #expect(runningClocks(pomodoro: pomodoro, timer: timer, stopwatch: watch, isOn: { $0 != .pomodoro }).map(\.title) == ["Stopwatch"])
    pomodoro.stop()
    _ = watch.stop()
}

/// Settings writes `name = false` under [features], and removes it when it's on again (on is the default).
@MainActor @Test func settingsTurnFeaturesOff() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    model.feature(.currency).wrappedValue = false
    let off = try String(contentsOf: file, encoding: .utf8)
    #expect(off.contains("[features]\n") && off.contains("\ncurrency = false"))
    #expect(try Config.parse(off).features.off == [.currency] && !model.feature(.currency).wrappedValue)
    model.feature(.currency).wrappedValue = true
    let on = try String(contentsOf: file, encoding: .utf8)
    #expect(try Config.parse(on).features.off.isEmpty && !on.contains("\ncurrency = false") && model.problem == nil)
}

// MARK: What the empty launcher shows, learning, answer cards

@Test func launcherSettingsInConfig() throws {
    let defaults = Config()
    #expect(defaults.meetings.showNext && defaults.reminders.showDue && defaults.timers.showRunning)
    #expect(defaults.learning.picked && defaults.learning.recent && defaults.answers.cards)
    let config = try Config.parse("""
        [meetings]
        show_next = false
        [reminders]
        show_due = false
        [timers]
        show_running = false
        [learning]
        picked = false
        recent = false
        [answers]
        cards = false
        """)
    #expect(!config.meetings.showNext && !config.reminders.showDue && !config.timers.showRunning)
    #expect(!config.learning.picked && !config.learning.recent && !config.answers.cards)
}

/// Off, what you picked is neither counted nor used (it's kept, for when it's on again); Forget deletes it.
@MainActor @Test func learningOffAndForgotten() async throws {
    let store = StateStore(file: try tempStateFile())
    let model = SearchModel(providers: [Fixed(rows: [("Safari", 1), ("Slack", 0.6)])], frecency: store)
    let first = { (query: String) in
        model.query = query
        try await Task.sleep(for: .milliseconds(100))
        return model.results.first?.id
    }
    _ = try await first("ss")
    model.picked("Slack")
    #expect(try await first("ss") == "Slack")
    model.learning.picked = false
    #expect(try await first("ss") == "Safari")
    model.picked("/Applications/Slack.app")
    #expect(store.get(Frecency.stateSection, as: Frecency.Table.self)?.keys.sorted() == ["Slack"])
    model.learning.picked = true
    #expect(try await first("ss") == "Slack")
    model.forget(.picks)
    #expect(try await first("ss") == "Safari")
    #expect(store.get(Frecency.stateSection, as: Frecency.Table.self)?.isEmpty == true && store.get(SearchModel.learnedSection, as: Frecency.Table.self)?.isEmpty == true)

    model.query = "safari"
    model.remember()
    model.learning.recent = false
    model.query = "slack"
    model.remember() // not kept
    model.query = ""
    #expect(!model.recallOlder())
    model.learning.recent = true
    #expect(model.recallOlder() && model.query == "safari")
    model.forget(.queries)
    model.query = ""
    #expect(!model.recallOlder())

    // The apps you open, for suggestions: kept only while suggestions are on, whatever learning says (Slack.app above).
    #expect(store.get(AppOpen.stateSection, as: [AppOpen].self)?.count == 1)
    model.forget(.appOpens)
    model.keepsAppOpens = false
    model.picked("/Applications/Safari.app")
    #expect(store.get(AppOpen.stateSection, as: [AppOpen].self)?.isEmpty == true)
    model.keepsAppOpens = true
    model.picked("/Applications/Safari.app")
    #expect(store.get(AppOpen.stateSection, as: [AppOpen].self)?.count == 1)
}

private struct Carded: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        [LauncherResult(id: "calc", title: "2", subtitle: "1 + 1", icon: .symbol("equal"), score: 1, action: {},
                        answer: .calculation("1 + 1", result: "2", note: nil))]
    }
}

/// Off, an answer is a plain row like the rest: no card, and its preview may show.
@MainActor @Test func answerCardsOff() async throws {
    let model = SearchModel(providers: [Carded()])
    model.query = "1+1"
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.answer != nil)
    model.showsCards = false
    #expect(model.answer == nil && model.results.first?.title == "2")
}

/// The Calendar picker: today's events, a meeting about to start, or nothing, in two keys.
@MainActor @Test func settingsMeetingsOnOpen() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    #expect(model.meetingsOnOpen.wrappedValue == .next)
    for choice in [SettingsModel.OnOpen.nothing, .today, .next] {
        model.meetingsOnOpen.wrappedValue = choice
        let meetings = try Config.parse(String(contentsOf: file, encoding: .utf8)).meetings
        #expect((meetings.showOnOpen, meetings.showNext) == (choice == .today, choice != .nothing), "\(choice)")
        #expect(model.meetingsOnOpen.wrappedValue == choice && model.problem == nil)
    }
}

// MARK: Your keywords

@Test func keywordsInConfig() throws {
    #expect(Config().keywords.words.isEmpty && Config().keywords.expansions.isEmpty)
    let config = try Config.parse("[keywords]\ntranslate = \"T\"\ncommands = [\";\", \">\"]\nadd_todo = \"todo\"\nshell = \"$\"\n")
    #expect(config.keywords.words == ["translate": ["t"], "commands": [";", ">"], "add_todo": ["todo"], "shell": ["$"]])
    #expect(config.keywords.expansions == ["t": "translate", ";": ":", ">": ":", "todo": "add todo", "$": ":!"])
    // Not a keyword, a word that's taken (a keyword, another's, a path's start), one with a space, or nothing: it says so.
    for wrong in ["transl = \"t\"", "translate = \"define\"", "translate = \"t\"\nstock = \"t\"", "translate = \"t r\"",
                  "commands = \"/\"", "translate = \"\""] {
        #expect(throws: (any Error).self, "\(wrong)") { try Config.parse("[keywords]\n\(wrong)\n") }
    }
    do { _ = try Config.parse("[keywords]\ntranslate = \"t\"\nstock = \"t\"\n") } catch { #expect(Config.describe(error).contains("\"t\"")) }
}

/// Every keyword is a chip's name or a word a feature answers to, and docs/configuration.md has its key.
@MainActor @Test func keywordList() throws {
    let store = StateStore(file: try tempStateFile())
    let docs = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../docs/configuration.md"), encoding: .utf8)
    for word in Keyword.all { #expect(docs.contains("`\(Keyword.key(word))`"), "\(Keyword.key(word)) isn't in docs/configuration.md") }
    #expect(Set(Keyword.all).count == Keyword.all.count)
    let providers: [any ResultProvider] = [TranslateProvider(), DefineProvider(), SpellProvider(), EmojiProvider(), StockProvider(),
                                           QRCodeProvider(), LargeTypeProvider(), TimerProvider(clock: Countdown(store: store)),
                                           PomodoroProvider(pomodoro: Pomodoro()), LookupProvider(), CaptureProvider(addToNote: { _ in }),
                                           ShellProvider(state: store), FileSearchProvider()]
    let chips = providers.flatMap(\.modes).map { $0.prefix.trimmingCharacters(in: .whitespaces) }.filter { !$0.hasPrefix("translate to ") }
    #expect(Set(chips).isSubset(of: Keyword.all), "\(Set(chips).subtracting(Keyword.all))")
    #expect(Keyword.key(":") == "commands" && Keyword.key(":!") == "shell" && Keyword.key("add todo") == "add_todo")
}

/// Your word for a keyword means it: alone, before a space, or stuck to what follows for one of symbols (`;left`).
/// Tab makes its chip, as the keyword would.
@MainActor @Test func yourKeywords() async throws {
    let commands = Typed()
    let model = SearchModel(providers: [Say(), Typed()], exclusive: [":": commands])
    model.keywords = ["s": "say", ";": ":"]
    let titles = { (query: String) in
        model.query = query
        try await Task.sleep(for: .milliseconds(100))
        return model.results.map(\.title)
    }
    #expect(try await titles("s hi").contains("said: say hi"))
    #expect(try await titles("s").contains("said: say"))
    #expect(try await titles("sx").contains("said: sx")) // only the word itself
    #expect(try await titles(";left") == [":left"]) // the commands' provider alone, as for ":left"
    model.query = "s hi"
    model.complete() // Tab
    #expect(model.mode?.title == "Say" && model.typed == "hi" && model.query == "say hi")
    model.query = "s"
    model.complete()
    #expect(model.mode?.title == "Say" && model.typed.isEmpty)
}

/// Your words, as one line: one is a string, several a list, none removes the key. A word that's taken isn't saved.
@MainActor @Test func settingsKeywords() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    model.keyword("translate").wrappedValue = "t, TR"
    var text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("[keywords]") && text.contains("\ntranslate = [\"t\", \"tr\"]"))
    #expect(try Config.parse(text).keywords.words == ["translate": ["t", "tr"]] && model.keyword("translate").wrappedValue == "t, tr")
    model.keyword(":").wrappedValue = ";"
    #expect(try String(contentsOf: file, encoding: .utf8).contains("\ncommands = \";\""))
    text = try String(contentsOf: file, encoding: .utf8)
    model.keyword("stock").wrappedValue = "t"
    let unchanged = try String(contentsOf: file, encoding: .utf8)
    #expect(model.problem?.contains("\"t\"") == true && unchanged == text)
    model.keyword("translate").wrappedValue = ""
    let removed = try String(contentsOf: file, encoding: .utf8)
    #expect(!removed.contains("\ntranslate = "))
}

// MARK: The settings window

/// An empty field is no value: the City field's "" on opening Settings, with no city set, changes nothing.
@MainActor @Test func settingsEmptyTextIsNoValue() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    model.text(\.weather.city, "weather", "city").wrappedValue = ""
    let after = try String(contentsOf: file, encoding: .utf8)
    #expect(model.problem == nil && after == Config.example)
    model.text(\.weather.city, "weather", "city").wrappedValue = "Lisbon"
    model.text(\.weather.city, "weather", "city").wrappedValue = ""
    #expect(model.problem == nil && model.config.weather.city == nil)
}

/// A problem's banner sits over the pane: the pane still fits the window and scrolls, nothing pushed out of sight.
@MainActor @Test func settingsFitTheirWindow() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let window = SettingsWindow(showWelcome: {}, forget: { _ in }, file: file)
    window.model.problem = "config.toml has a mistake (line 3). Fix it there and these settings come back."
    window.setFrameOrigin(NSPoint(x: -6000, y: -6000)) // off every screen
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(400))
    let content = try #require(window.contentView)
    func tallest(_ view: NSView, depth: Int = 0) -> CGFloat {
        depth > 4 ? 0 : view.subviews.map { max($0.frame.height, tallest($0, depth: depth + 1)) }.max() ?? 0
    }
    #expect(tallest(content) <= content.frame.height, "a view inside is taller than the window")
}

// MARK: Reduce Motion

/// With Reduce Motion on, the launcher changes in place: no spring, glide or scale. A fade stays.
@MainActor @Test func reduceMotion() {
    #expect(Motion.at(.smooth(duration: 0.2), still: true) == nil)
    #expect(Motion.at(.smooth(duration: 0.2), still: false) != nil)
    #expect(Motion.opening(still: true) == 1 && Motion.opening(still: false) < 1)
}

// MARK: Speed

/// Answers late on purpose, like file search waiting for a pause in typing.
private struct Patient: ResultProvider {
    var patient: Bool { true }
    func results(for query: String) async -> [LauncherResult] {
        try? await Task.sleep(for: .milliseconds(300))
        return [LauncherResult(id: "late", title: "late", icon: .symbol("doc"), score: 0, action: {})]
    }
}

/// A keystroke's rows show within a frame once the quick providers have answered; one that answers late on purpose
/// merges in when it does. On its own (a chip), the rows wait for it as before, so the list never empties.
@MainActor @Test func rowsDontWaitForPatientProviders() async throws {
    let model = SearchModel(providers: [Fixed(rows: [("a", 1)]), Patient()])
    model.query = "x"
    let start = ContinuousClock.now
    while model.settling, start.duration(to: .now) < .milliseconds(200) { try await Task.sleep(for: .microseconds(200)) }
    #expect(start.duration(to: .now) < .milliseconds(16), "\(start.duration(to: .now))")
    #expect(model.results.map(\.id) == ["a"])
    await eventually { model.results.count == 2 }
    #expect(model.results.map(\.id) == ["a", "late"])
    #expect(Gated(.files, FileSearchProvider()).patient && !Gated(.calculator, CalculatorProvider()).patient)

    let alone = SearchModel(providers: [Patient()])
    alone.query = "x"
    try await Task.sleep(for: .milliseconds(20))
    #expect(alone.settling && alone.results.isEmpty) // waits, rather than showing nothing
}

/// Matching a name is quick when it can't match (most can't): more names than a Mac has apps, against a long query,
/// within a frame even in a debug build (folding a character at a time took 30 ms for 2,000 optimized).
@Test func matchingIsQuick() {
    let names = (0..<500).map { "Application Number \($0) Pro" }
    let fastest = (0..<3).map { _ in // the fastest of three: the suite runs in parallel, and a busy moment isn't the matcher
        let start = ContinuousClock.now
        #expect(names.allSatisfy { fuzzyScore("time in tokyo", $0) == nil })
        return start.duration(to: .now)
    }.min()!
    #expect(fastest < .milliseconds(16), "\(fastest)")
    #expect(fuzzyScore("vsc", "Visual Studio Code") != nil && fuzzyScore("SAF", "Safari") != nil && fuzzyScore("cafe", "Café Menu") != nil)
}

// MARK: Typos

/// One slip still finds it: a letter wrong, extra, or two swapped (a missing one already does, in order); two in a
/// long name. At the start of the name or of a word in it, the first letter right, and always under a real match.
@Test func typos() {
    for (typed, name) in [("slcak", "Slack"), ("safaro", "Safari"), ("saffar", "Safari"), ("crhome", "Google Chrome"),
                          ("spotifu", "Spotify"), ("photsohop", "Adobe Photoshop 2026"), ("visualstudo", "Visual Studio Code"),
                          ("teminal", "Terminal"), ("calender", "Calendar"), ("slak", "Slack")] {
        #expect(fuzzyScore(typed, name) != nil, "\(typed) → \(name)")
    }
    #expect(fuzzyScore("slcak", "Slack")! < fuzzyScore("sk", "Slack")!) // under a real match, however scattered
    #expect(fuzzyScore("photsohop", "Adobe Photoshop 2026")! > fuzzyScore("photsohop", "Photo Booth Shop") ?? 0)
    #expect(fuzzyScore("xlack", "Slack") == nil) // the first letter has to be right
    #expect(fuzzyScore("scl", "Slack") == nil) // too short to guess
    #expect(fuzzyScore("safarii", "Safari") == nil && fuzzyScore("notes", "Note") == nil) // typed past its end: another word
    #expect(fuzzyScore("sfaaro", "Safari") == nil) // two slips in a short name
    #expect(fuzzyScore("tume", "Safari") == nil && fuzzyScore("time in tokyo", "Tide") == nil)
}

// MARK: Rows that fill themselves in

/// What the launcher shows a moment after: each row that fills itself in (`later`), filled in.
func settled(_ rows: [LauncherResult]) async -> [LauncherResult] {
    var out: [LauncherResult] = []
    for row in rows { if let later = row.later { out += await later() } else { out.append(row) } }
    return out
}

private struct Asking: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        [LauncherResult(id: "ask", title: "Asking…", icon: .symbol("circle"), score: 1, action: {}, later: {
            try? await Task.sleep(for: .milliseconds(150))
            return [LauncherResult(id: "answer:\(query)", title: "Answer for \(query)", icon: .symbol("circle"), score: 1, action: {})]
        })]
    }
}

/// A row that fills itself in shows at once, as it is (its card loading), and its rows take its place when they come;
/// the next keystroke cancels them, so an old answer never lands on a new query.
@MainActor @Test func rowsFillThemselvesIn() async throws {
    let model = SearchModel(providers: [Asking()])
    model.query = "a"
    try await Task.sleep(for: .milliseconds(60))
    #expect(model.results.map(\.title) == ["Asking…"])
    await eventually { model.results.first?.id == "answer:a" }
    #expect(model.results.map(\.title) == ["Answer for a"])
    model.query = "b"
    try await Task.sleep(for: .milliseconds(60))
    model.query = "c" // before b's answer
    await eventually { model.results.first?.id == "answer:c" }
    #expect(model.results.map(\.id) == ["answer:c"])
}

// MARK: At rest

/// The clipboard is looked at twice a second while you're at the Mac, and every 2 s once there's been no key or mouse
/// for a minute: away, it lets the Mac sleep more. Copying takes a key, so nothing copied is missed.
@Test func clipboardRestsWhileYoureAway() {
    #expect(ClipboardHistory.pollInterval(idle: 0) == 0.5 && ClipboardHistory.pollInterval(idle: 59) == 0.5)
    #expect(ClipboardHistory.pollInterval(idle: 61) == 2)
}

// MARK: Your accent color

@Test func accentInConfig() throws {
    #expect(Config().look.accent == .copper)
    #expect(try Config.parse("[look]\naccent = \"system\"").look.accent == .system)
    #expect(try Config.parse("[look]\naccent = \"#3478F6\"").look.accent == .color(RGBColor(red: 52, green: 120, blue: 246)))
    #expect(try Config.parse("[look]\naccent = \"copper\"").look.accent == .copper)
    #expect(throws: (any Error).self) { try Config.parse("[look]\naccent = \"bluish\"") }
}

/// Copper is the icon's three shades exactly; any other color gets its own, a lighter one and a deeper one.
@Test func accentShades() {
    let copper = Accent.copper.shades(system: nil)
    #expect(copper.main == RGBColor(red: 222, green: 151, blue: 96) && copper.light == RGBColor(red: 254, green: 186, blue: 122))
    #expect(copper.deep == RGBColor(red: 179, green: 110, blue: 66))
    let blue = RGBColor(red: 52, green: 120, blue: 246)
    let shades = Accent.color(blue).shades(system: nil)
    #expect(shades.main == blue && shades.light.lightness > blue.lightness && shades.deep.lightness < blue.lightness)
    #expect(Accent.system.shades(system: blue).main == blue)
    #expect(Accent.system.shades(system: nil) == copper) // nothing to follow: copper
}

/// The Look section writes `[look] accent`; copper, the default, removes it.
@MainActor @Test func settingsAccent() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).toml")
    defer { try? FileManager.default.removeItem(at: file) }
    try Config.example.write(to: file, atomically: true, encoding: .utf8)
    let model = SettingsModel(file: file)
    model.accent.wrappedValue = .color(RGBColor(red: 52, green: 120, blue: 246))
    var text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("[look]") && text.contains("\naccent = \"#3478f6\"") && model.problem == nil)
    model.accent.wrappedValue = .system
    text = try String(contentsOf: file, encoding: .utf8)
    #expect(try Config.parse(text).look.accent == .system)
    model.accent.wrappedValue = .copper
    text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("\naccent = ") && model.config.look.accent == .copper)
}

// MARK: Camera

/// `camera`: you, mirrored, across the card. Enter joins the meeting about to start, if there is one, else opens
/// Photo Booth. Without access it asks from a row, once; a Mac without a camera says so.
@Test func camera() async throws {
    let camera = CameraProvider(status: { .authorized }, device: { "FaceTime HD Camera" }, join: { nil })
    let row = try #require(await camera.results(for: "camera").first)
    guard case .camera(let card)? = row.answer else { Issue.record("no camera card"); return }
    #expect(card.name == "FaceTime HD Camera" && card.enter == "Open Photo Booth" && card.meeting == nil && row.actionTitle == "Open Photo Booth")
    #expect(await camera.results(for: "came").count == 1)
    #expect(await camera.results(for: "cam").isEmpty) // Calendar's, Camtasia's
    // Before a call, Enter joins it.
    let call = CalendarItem(title: "Weekly sync", start: .now + 240, end: .now + 2040, link: URL(string: "https://meet.google.com/abc-defg-hij"))
    let meeting = joinRows(call, browser: Config.Browser(), score: 100)[0]
    let before = try #require(await CameraProvider(status: { .authorized }, device: { "FaceTime HD Camera" }, join: { meeting }).results(for: "camera").first)
    guard case .camera(let joining)? = before.answer else { Issue.record("no camera card"); return }
    #expect(joining.enter == "Join Google Meet" && joining.meeting == "Weekly sync · in 4 min" && before.actionTitle == "Join")
    // No camera, not asked yet, refused.
    #expect(await CameraProvider(status: { .authorized }, device: { nil }, join: { nil }).results(for: "camera").map(\.title) == ["This Mac has no camera"])
    #expect(await CameraProvider(status: { .notDetermined }, device: { "FaceTime HD Camera" }, join: { nil }).results(for: "camera").map(\.actionTitle) == ["Allow"])
    #expect(await CameraProvider(status: { .denied }, device: { "FaceTime HD Camera" }, join: { nil }).results(for: "camera").map(\.actionTitle) == ["Open System Settings"])
}
