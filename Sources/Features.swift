import Synchronization

/// What can be turned off, in Settings › Features or config.toml's `[features]` (`currency = false`). Off means off:
/// no rows, no chip, no `:` commands, no background work, no network, no permission asks. Everything is on until
/// config.toml says otherwise. Finding apps, the search row and Copperlight's own rows can't be turned off.
enum Feature: String, CaseIterable, Sendable {
    // Answers
    case calculator, currency, units, timeZones = "time_zones", dates, colors, qr, stocks, weather, define, spelling,
         translate, emoji, textTools = "text_tools", largeType = "large_type", macInfo = "mac_info", speedTest = "speed_test",
         processes
    // Yours
    case clipboard, notes, snippets, scripts, commands, contacts, calendar, reminders, files, browserTabs = "browser_tabs",
         bookmarks, systemSettings = "system_settings", menus, timers, pomodoro, stopwatch, screenText = "screen_text"
    // Windows and the Mac
    case windows, runningApps = "running_apps", mac, sound, keepAwake = "keep_awake", bluetooth, shortcuts, shell, homebrew
    // Not offered yet
    case fileContent = "file_content", photoText = "photo_text"

    /// Built and tested but not offered yet: always off, and not in Settings or config.toml.
    static let parked: Set<Feature> = [.fileContent, .photoText]
    /// What Settings lists, in this order.
    static var listed: [Feature] { allCases.filter { !parked.contains($0) } }

    /// config.toml's `[features]`, set each time it loads.
    private static let config = Mutex(Config.Features())
    static func use(_ features: Config.Features) { config.withLock { $0 = features } }
    var isOn: Bool { Self.config.withLock { $0.isOn(self) } }

    enum Group: String, CaseIterable { case answers = "Answers", yours = "Yours", mac = "Windows and the Mac" }

    var group: Group {
        switch self {
        case .calculator, .currency, .units, .timeZones, .dates, .colors, .qr, .stocks, .weather, .define, .spelling,
             .translate, .emoji, .textTools, .largeType, .macInfo, .speedTest, .processes: .answers
        case .windows, .runningApps, .mac, .sound, .keepAwake, .bluetooth, .shortcuts, .shell, .homebrew: .mac
        default: .yours
        }
    }

    var name: String { info.name }
    /// One line for Settings: what you type, or what it does.
    var about: String { info.about }

    /// The words that start it, which config.toml's `[keywords]` can add your own to (`translate = "t"`).
    var keywords: [String] {
        switch self {
        case .colors: ["colors", "pick color"]
        case .qr: ["qr"]
        case .stocks: ["stock"]
        case .weather: ["weather"]
        case .define: ["define"]
        case .spelling: ["spell"]
        case .translate: ["translate"]
        case .emoji: ["emoji"]
        case .largeType: ["large"]
        case .speedTest: ["speed"]
        case .processes: ["cpu", "memory", "port"]
        case .clipboard: ["clip"]
        case .notes: ["note", "add note"]
        case .contacts: ["contact"]
        case .calendar: ["meetings", "week", "add event"]
        case .reminders: ["due", "add todo"]
        case .files: ["f"]
        case .browserTabs: ["tabs"]
        case .timers: ["timer"]
        case .pomodoro: ["pomo"]
        case .stopwatch: ["stopwatch"]
        case .screenText: ["copy text"]
        case .shell: [":!"]
        default: []
        }
    }

    private var info: (name: String, about: String) {
        switch self {
        case .calculator: ("Calculator", "150 + 20%, 30 is what % of 150, 255 in hex")
        case .currency: ("Currency", "25 usd to eur, 0.1 btc in eur. Rates from Coinbase")
        case .units: ("Units", "5 km in miles, 72 f in c")
        case .timeZones: ("Time zones", "time in tokyo")
        case .dates: ("Date math", "days until dec 25, in 3 weeks")
        case .colors: ("Colors", "#c87533, pick color, colors")
        case .qr: ("QR codes", "qr and a link or any text")
        case .stocks: ("Stocks", "stock aapl. Prices from Yahoo Finance")
        case .weather: ("Weather", "weather lisbon. Forecasts from Open-Meteo")
        case .define: ("Dictionary", "define serendipity")
        case .spelling: ("Spelling", "spell recieve")
        case .translate: ("Translate", "translate bom dia, on this Mac")
        case .emoji: ("Emoji", "emoji heart")
        case .textTools: ("Text tools", "uuid, password, lowercase, paste plain")
        case .largeType: ("Large Type", "large and any text, across the screen")
        case .macInfo: ("Your Mac", "ip, battery, disk")
        case .speedTest: ("Speed test", "speed, against Apple's servers")
        case .processes: ("Processes", "cpu, memory, port 3000")
        case .clipboard: ("Clipboard history", "clip: what you copied, kept on this Mac")
        case .notes: ("Notes", "note, add note")
        case .snippets: ("Snippets", "Text you paste by name")
        case .scripts: ("Scripts", "The scripts folder, as rows")
        case .commands: ("Your commands", "The links, apps, files and shell lines in config.toml")
        case .contacts: ("Contacts", "contact ana")
        case .calendar: ("Calendar", "The next meeting, meetings, week, add event")
        case .reminders: ("Reminders", "Reminders that are due, add todo")
        case .files: ("Files", "f invoice, ~/code, :reveal, :trash")
        case .browserTabs: ("Browser tabs", "Your open tabs, by title")
        case .bookmarks: ("Bookmarks and history", "Pages from your browser, by title")
        case .systemSettings: ("System Settings", "Its pages, as rows: wi-fi, displays")
        case .menus: ("Menu search", "The menus of the app in front, after :")
        case .timers: ("Timers", "timer 10m, timer until 15:00")
        case .pomodoro: ("Pomodoro", "pomo, pomo break")
        case .stopwatch: ("Stopwatch", "stopwatch")
        case .screenText: ("Copy text from the screen", "copy text")
        case .windows: ("Windows", ":left, :maximize, :window, saved layouts")
        case .runningApps: ("Running apps", ":quit, :hide, :relaunch")
        case .mac: ("Mac commands", ":lock, :sleep, :dark, :wifi, screenshot")
        case .sound: ("Sound", ":play, :volume 30, :mute, :output")
        case .keepAwake: ("Keep awake", ":awake 2h")
        case .bluetooth: ("Bluetooth", ":connect airpods")
        case .shortcuts: ("Shortcuts", ":shortcut and a shortcut's name")
        case .shell: ("Shell", ":! and a command")
        case .homebrew: ("Install with Homebrew", "Apps you don't have, installed from their row")
        case .fileContent: ("Text inside files", "")
        case .photoText: ("Text in photos", "")
        }
    }
}

/// The built-in keywords, which config.toml's `[keywords]` adds your own words to: `translate = "t"`, `commands = ";"`.
/// They keep working. A keyword's key there is the word, `_` for its spaces; `:` is `commands`, `:!` is `shell`.
enum Keyword {
    static var all: [String] { [":"] + Feature.listed.flatMap(\.keywords) }
    static func key(_ word: String) -> String { [":": "commands", ":!": "shell"][word] ?? word.replacingOccurrences(of: " ", with: "_") }
}

/// A provider that answers only while its feature is on: no rows and no chips while it's off.
struct Gated: ResultProvider {
    let feature: Feature
    let provider: any ResultProvider
    var isOn: @Sendable (Feature) -> Bool = { $0.isOn }

    init(_ feature: Feature, _ provider: any ResultProvider, isOn: @escaping @Sendable (Feature) -> Bool = { $0.isOn }) {
        (self.feature, self.provider, self.isOn) = (feature, provider, isOn)
    }

    var modes: [Mode] { isOn(feature) ? provider.modes : [] }
    var patient: Bool { provider.patient }
    func results(for query: String) async -> [LauncherResult] { isOn(feature) ? await provider.results(for: query) : [] }
    func modeResults(for query: String) async -> [LauncherResult] { isOn(feature) ? await provider.modeResults(for: query) : [] }
}
