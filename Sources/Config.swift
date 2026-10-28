import AppKit
import Carbon.HIToolbox
import TOMLKit

/// ~/.config/copperlight/config.toml. Every field has a default, so a missing file, an empty file
/// or a missing section all mean "defaults".
struct Config: Decodable, Equatable {
    static let file = configDir.appending(path: "config.toml")

    var hotkeys = Hotkeys()
    var currency = Currency()
    var clipboard = Clipboard()
    var files = Files()
    var apps = Apps()
    var pomodoro = Pomodoro()
    var translate = Translate()
    var browser = Browser()
    var notes = Notes()
    var meetings = Meetings()
    var commands: [Command] = []
    var snippets: [Snippet] = []

    /// Only the launcher has a global hotkey; everything else is reached through it. Older configs'
    /// `clipboard` and `note` keys are ignored.
    struct Hotkeys: Decodable, Equatable {
        var launcher = Hotkey("option+space")!

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            launcher = try c.decodeIfPresent(Hotkey.self, forKey: .launcher) ?? launcher
        }
        private enum CodingKeys: String, CodingKey { case launcher }
    }

    struct Currency: Decodable, Equatable {
        var defaultTarget = "EUR"

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultTarget = try c.decodeIfPresent(String.self, forKey: .defaultTarget)?.uppercased() ?? defaultTarget
            guard defaultTarget.count == 3, defaultTarget.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .defaultTarget, in: c, debugDescription: "expected a 3-letter currency code like \"EUR\"")
            }
        }
        private enum CodingKeys: String, CodingKey { case defaultTarget = "default_target" }
    }

    /// Where `translate bom dia` goes without "to …": a language's English name or code ("german", "de"). nil: the first
    /// of your Mac's languages the text isn't in. One the Mac can't translate is ignored.
    struct Translate: Decodable, Equatable {
        var defaultTarget: String?

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultTarget = try c.decodeIfPresent(String.self, forKey: .defaultTarget)
        }
        private enum CodingKeys: String, CodingKey { case defaultTarget = "default_target" }
    }

    /// The floating notes. `markdown`: style Markdown as you type (headings, bold, checkboxes); the files stay plain text.
    struct Notes: Decodable, Equatable {
        var markdown = true

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            markdown = try c.decodeIfPresent(Bool.self, forKey: .markdown) ?? markdown
        }
        private enum CodingKeys: String, CodingKey { case markdown }
    }

    /// Today's events. `show_on_open`: the empty launcher lists them; otherwise it only shows a meeting about to start.
    struct Meetings: Decodable, Equatable {
        var showOnOpen = false

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showOnOpen = try c.decodeIfPresent(Bool.self, forKey: .showOnOpen) ?? showOnOpen
        }
        private enum CodingKeys: String, CodingKey { case showOnOpen = "show_on_open" }
    }

    struct Clipboard: Decodable, Equatable {
        /// Copies made while one of these apps is in front aren't recorded.
        var ignoreApps = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                          "com.apple.keychainaccess", "com.apple.Passwords"]
        var maxItems = 1000
        var maxDays = 90
        var maxImages = 100 // images are big (a screenshot is 1–5 MB); they also count toward max_items

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ignoreApps = try c.decodeIfPresent([String].self, forKey: .ignoreApps) ?? ignoreApps
            maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? maxItems
            maxDays = try c.decodeIfPresent(Int.self, forKey: .maxDays) ?? maxDays
            maxImages = try c.decodeIfPresent(Int.self, forKey: .maxImages) ?? maxImages
            for (key, value) in [(CodingKeys.maxItems, maxItems), (.maxDays, maxDays)] where value < 1 {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "must be 1 or more")
            }
            guard maxImages >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .maxImages, in: c, debugDescription: "must be 0 (no images) or more")
            }
        }
        private enum CodingKeys: String, CodingKey {
            case ignoreApps = "ignore_apps", maxItems = "max_items", maxDays = "max_days", maxImages = "max_images"
        }
    }

    struct Files: Decodable, Equatable {
        var scopes = ["~/code", "~/Documents", "~/Downloads", "~/Desktop"]
        /// Results with one of these as a folder (or file) name anywhere in their path are dropped.
        var exclude = ["node_modules", ".git", ".venv", "__pycache__", "DerivedData", "build", ".build"]
        var terminal: String? // where `:terminal` opens a folder (an app's name or bundle id); nil: Terminal

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? scopes
            exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? exclude
            terminal = try c.decodeIfPresent(String.self, forKey: .terminal)
        }
        private enum CodingKeys: String, CodingKey { case scopes, exclude, terminal }
    }

    struct Pomodoro: Decodable, Equatable {
        var defaultMinutes = 25
        var breakMinutes = 5

        init() {}
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultMinutes) ?? defaultMinutes
            breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? breakMinutes
            for (key, minutes) in [(CodingKeys.defaultMinutes, defaultMinutes), (.breakMinutes, breakMinutes)] where !(1...240).contains(minutes) {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "must be 1 to 240")
            }
        }
        private enum CodingKeys: String, CodingKey { case defaultMinutes = "default_minutes", breakMinutes = "break_minutes" }
    }

    /// Where web links open when nothing more specific says: typed URLs, the search row, url commands
    /// without their own `browser` or `profile`. Unset, the default browser opens them as it likes.
    struct Browser: Decodable, Equatable, Sendable {
        var name: String? // app name or bundle id; nil: the default browser
        var profile: String?
        var search: SearchEngine? // the search row's engine; nil: Google
    }

    /// Apps are found by what they do too (AppIndex). `online`: descriptions from Homebrew's public app list and,
    /// for apps from the App Store, the App Store.
    struct Apps: Decodable, Equatable, Sendable {
        var online = true
    }


    /// Text you paste by name. `text` may hold {date}, {time}, {clipboard}, {query} and {cursor}.
    struct Snippet: Decodable, Equatable, Sendable {
        var name: String
        var text: String
    }

    struct Command: Decodable, Equatable {
        enum Action: Equatable {
            case url(String, browser: String?, profile: String?) // url may hold {query}
            case app(String) // name or bundle id
            case file(String)
            case shell(String)
        }
        var alias: String
        var action: Action

        init(alias: String, action: Action) {
            self.alias = alias
            self.action = action
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            alias = try c.decode(String.self, forKey: .alias)
            action = switch try c.decode(String.self, forKey: .type) {
            case "url": .url(try c.decode(String.self, forKey: .url), browser: try c.decodeIfPresent(String.self, forKey: .browser),
                             profile: try c.decodeIfPresent(String.self, forKey: .profile))
            case "app": .app(try c.decode(String.self, forKey: .app))
            case "file": .file(try c.decode(String.self, forKey: .path))
            case "shell": .shell(try c.decode(String.self, forKey: .run))
            case let other: throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown type \"\(other)\" (expected url, app, file or shell)")
            }
        }
        private enum CodingKeys: String, CodingKey { case alias, type, url, browser, profile, app, path, run }
    }

    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try c.decodeIfPresent(Hotkeys.self, forKey: .hotkeys) ?? hotkeys
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? currency
        clipboard = try c.decodeIfPresent(Clipboard.self, forKey: .clipboard) ?? clipboard
        files = try c.decodeIfPresent(Files.self, forKey: .files) ?? files
        apps = try c.decodeIfPresent(Apps.self, forKey: .apps) ?? apps
        pomodoro = try c.decodeIfPresent(Pomodoro.self, forKey: .pomodoro) ?? pomodoro
        translate = try c.decodeIfPresent(Translate.self, forKey: .translate) ?? translate
        browser = try c.decodeIfPresent(Browser.self, forKey: .browser) ?? browser
        notes = try c.decodeIfPresent(Notes.self, forKey: .notes) ?? notes
        meetings = try c.decodeIfPresent(Meetings.self, forKey: .meetings) ?? meetings
        commands = try c.decodeIfPresent([Command].self, forKey: .commands) ?? []
        snippets = try c.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
    }
    private enum CodingKeys: String, CodingKey { case hotkeys, currency, clipboard, files, apps, pomodoro, translate, browser, notes, meetings, commands = "command", snippets = "snippet" }

    static func parse(_ text: String) throws -> Config {
        try TOMLDecoder().decode(Config.self, from: text)
    }

    /// One line for the launcher's error row, e.g. "line 3: …" or "command[1].url: missing".
    static func describe(_ error: any Error) -> String {
        func path(_ keys: [any CodingKey]) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingPrefix(".").description
        }
        switch error {
        case let error as TOMLParseError: return "line \(error.source.begin.line): \(error.description)"
        case DecodingError.keyNotFound(let key, let context): // TOMLKit's path already ends in the key
            let keys = context.codingPath.last?.stringValue == key.stringValue ? context.codingPath : context.codingPath + [key]
            return "\(path(keys)): missing"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            return "\(path(context.codingPath)): \(context.debugDescription)"
        default: return "\(error)"
        }
    }

    /// Written on first run. Parses to exactly `Config()`.
    static let example = """
        # Copperlight config. Changes apply on save. A mistake shows as an error row at the top
        # of the launcher, and the last valid config stays in use until it's fixed.
        # Every setting is optional; missing ones use the defaults shown here.

        [hotkeys]
        launcher = "option+space"      # the only hotkey: everything else is a search away

        [currency]
        default_target = "EUR"         # for "25 usd" with no target ("25 eur" converts to USD)

        [clipboard]
        # Copies made while one of these apps is in front aren't recorded (bundle ids).
        ignore_apps = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                       "com.apple.keychainaccess", "com.apple.Passwords"]
        max_items = 1000
        max_days = 90
        max_images = 100               # 0 to keep text only

        [files]
        # Folders searched (Spotlight index). Type 2+ letters, or "f name" for files only.
        scopes = ["~/code", "~/Documents", "~/Downloads", "~/Desktop"]
        # Results with one of these anywhere in their path are hidden.
        exclude = ["node_modules", ".git", ".venv", "__pycache__", "DerivedData", "build", ".build"]
        # terminal = "Ghostty"         # optional: where :terminal opens a folder (iTerm, Ghostty, Warp…); unset: Terminal

        [apps]
        # Apps are found by what they do too ("draw", "noise"), from an index of each app's category, the files it
        # opens and, with Apple Intelligence on, words from the Mac's on-device model. Online, it adds a description:
        # Homebrew's public app list (downloaded whole, so it says nothing about your apps) and, for apps from the
        # App Store, the App Store's. Set false to keep it all on this Mac.
        online = true

        [pomodoro]
        default_minutes = 25           # "pomo" in the launcher; "pomo 50" for another length
        break_minutes = 5              # "pomo break"; "pomo break 15" for another length

        [translate]
        # default_target = "german"    # for "translate bom dia" without "to …"; unset: your Mac's languages

        [meetings]
        show_on_open = false           # true: the empty launcher lists today's events. false: only a meeting with a call,
                                       # from 10 minutes before it starts. Needs Calendars access ("meetings" asks).

        [notes]
        markdown = true                # style Markdown as you type: # headings, **bold**, - [ ] checkboxes, links.
                                       # The files stay plain text.

        [browser]
        # Where web links open: typed URLs ("gmail.com"), the search row, and url commands without their
        # own browser or profile. Unset: the default browser, in whatever profile it picks.
        # name = "Google Chrome"       # optional: another browser than the default (name or bundle id)
        # profile = "Work"             # optional: a profile of it (Chrome, Brave, Edge, Vivaldi, Firefox)
        # search = "duckduckgo"        # optional: the search row's engine: google (default), duckduckgo, bing,
        #                              #   brave, ecosia, kagi

        # Custom commands: type the alias in the launcher. Types: url, app, file, shell.
        #
        # [[command]]
        # alias = "github"
        # type = "url"
        # url = "https://github.com"
        # browser = "Firefox"          # optional: another browser than the default (name or bundle id)
        # profile = "Work"             # optional: a profile of that browser (Chrome, Brave, Edge, Vivaldi, Firefox)
        #
        # [[command]]
        # alias = "gh"                 # "gh copperlight" searches GitHub for "copperlight"
        # type = "url"
        # url = "https://github.com/search?q={query}"
        #
        # [[command]]
        # alias = "slack"
        # type = "app"
        # app = "Slack"                # app name or bundle id
        #
        # [[command]]
        # alias = "budget"
        # type = "file"
        # path = "~/Documents/finance/cashflow.xlsx"
        #
        # [[command]]
        # alias = "dev"
        # type = "shell"
        # run = "cd ~/code/api && docker compose up -d"   # zsh login shell, detached
        #
        # A command named like a built-in replaces it: your own screenshot app, todo list or calendar.
        #
        # [[command]]
        # alias = "screenshot"
        # type = "url"
        # url = "cleanshot://capture-area"
        #
        # [[command]]
        # alias = "add todo"
        # type = "url"
        # url = "things:///add?title={query}"

        # Snippets: type the name, Enter pastes the text. Placeholders: {date}, {time}, {clipboard}, {query}
        # for the text typed after the name ("reply John"), and {cursor} for where the cursor ends up.
        #
        # [[snippet]]
        # name = "sig"
        # text = \"\"\"
        # Best,
        # Alex\"\"\"
        #
        # [[snippet]]
        # name = "reply"
        # text = "Hi {query}, thanks for the note. I'll get back to you by {date}."

        """
}

/// A global hotkey as written in config.toml: "option+space", "cmd+shift+k", "ctrl+f1".
struct Hotkey: Equatable, Sendable, Decodable {
    var keyCode: Int // Carbon virtual key code (kVK_*), what KeyboardShortcuts.Key wraps
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        (self.keyCode, self.modifiers) = (keyCode, modifiers)
    }

    init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.popLast(), let code = Self.keyCodes[key] else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts {
            guard let modifier = Self.modifierNames[part] else { return nil }
            modifiers.insert(modifier)
        }
        self.init(keyCode: code, modifiers: modifiers)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let text = try c.decode(String.self)
        guard let hotkey = Hotkey(text) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "can't read hotkey \"\(text)\" (try \"option+space\")")
        }
        self = hotkey
    }

    /// How config.toml writes it ("option+space"), for the settings window; nil for a key it has no name for.
    var text: String? {
        let names = Self.keyCodes.filter { $0.value == keyCode }.map(\.key)
        guard let key = names.min(by: { ($0.count, $0) < ($1.count, $1) }) else { return nil } // "esc", not "escape"
        let order: [(NSEvent.ModifierFlags, String)] = [(.control, "ctrl"), (.option, "option"), (.shift, "shift"), (.command, "cmd")]
        return (order.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: "+")
    }

    private static let modifierNames: [String: NSEvent.ModifierFlags] = [
        "command": .command, "cmd": .command, "option": .option, "opt": .option, "alt": .option,
        "control": .control, "ctrl": .control, "shift": .shift,
    ]

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
        "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}

/// Calls `onChange` on the main thread whenever anything in `directory` changes. FSEvents tracks
/// paths rather than open files, so in-place writes and atomic-rename saves (vim) look the same.
/// Runs for the rest of the app's life: it's never stopped, and the stream keeps it alive.
@MainActor final class DirectoryWatcher {
    private let onChange: () -> Void

    init(_ directory: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passRetained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let stream = FSEventStreamCreate(
            nil, { _, info, _, _, _, _ in
                let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info!).takeUnretainedValue()
                MainActor.assumeIsolated { watcher.onChange() } // the stream is scheduled on .main below
            },
            &context, [directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }
}
