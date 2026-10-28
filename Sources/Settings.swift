import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// The settings window's view of config.toml, which stays the one source of truth: every change is written there
/// at once, as a person would edit it (ConfigFile), and the app picks it up like any other save.
@MainActor @Observable final class SettingsModel {
    private(set) var config = Config()
    private(set) var broken = false // config.toml doesn't parse: it has to be fixed by hand first
    var problem: String?
    var launchAtLogin = false
    private(set) var hotkeyResets = 0 // a cleared recorder is rebuilt, showing the hotkey that stays
    private let file: URL

    init(file: URL = Config.file) {
        self.file = file
        reload()
    }

    func reload() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        do {
            config = try Config.parse(read())
            (broken, problem) = (false, nil)
        } catch {
            (broken, problem) = (true, "config.toml has a mistake (\(Config.describe(error))). Fix it there and these settings come back.")
        }
    }

    /// One change, to the settings (`change`) and to the file's text (`edit`). Written only if the new file reads back
    /// as exactly the settings asked for: a file this can't edit cleanly is left as it is.
    func save(_ change: (inout Config) -> Void, _ edit: (inout ConfigFile) -> Void) {
        let text = read()
        guard var expected = try? Config.parse(text) else { return reload() }
        change(&expected)
        var file = ConfigFile(text)
        edit(&file)
        guard (try? Config.parse(file.text)) == expected else {
            problem = "This change can't be saved without rewriting your config.toml, so it wasn't. Edit the file instead."
            return
        }
        do {
            try file.text.write(to: self.file, atomically: true, encoding: .utf8)
            (config, problem) = (expected, nil)
        } catch {
            problem = "Couldn't save config.toml: \(error.localizedDescription)"
        }
    }

    /// A control bound to one key of config.toml. nil from `value` removes the key (an unset optional).
    func binding<T: Equatable>(_ path: WritableKeyPath<Config, T>, _ table: String, _ key: String,
                               _ value: @escaping (T) -> TOMLValue?) -> Binding<T> {
        Binding(get: { self.config[keyPath: path] }, set: { new in
            guard new != self.config[keyPath: path] else { return }
            self.save({ $0[keyPath: path] = new }, { $0.set(key, in: table, to: value(new)) })
        })
    }

    func strings(_ path: WritableKeyPath<Config, [String]>, _ table: String, _ key: String) -> Binding<[String]> {
        binding(path, table, key) { .strings($0) }
    }

    func text(_ path: WritableKeyPath<Config, String?>, _ table: String, _ key: String) -> Binding<String?> {
        binding(path, table, key) { $0.flatMap { $0.isEmpty ? nil : .string($0) } }
    }

    var hotkey: Binding<KeyboardShortcuts.Shortcut?> {
        Binding(get: { self.config.hotkeys.launcher.shortcut }, set: { shortcut in
            guard let shortcut else { self.hotkeyResets += 1; return } // the launcher always has a hotkey
            let hotkey = Hotkey(keyCode: shortcut.carbonKeyCode, modifiers: shortcut.modifiers.intersection([.command, .option, .control, .shift]))
            guard let text = hotkey.text else {
                self.problem = "That key can't be the hotkey. Use a letter, a number, Space or an F-key, with modifiers."
                return
            }
            self.save({ $0.hotkeys.launcher = hotkey }, { $0.set("launcher", in: "hotkeys", to: .string(text)) })
        })
    }

    /// Replaces the command at `index`, removes it (nil), or adds one (index nil).
    func setCommand(at index: Int?, to command: Config.Command?) {
        save({ config in
            if let index { if let command { config.commands[index] = command } else { config.commands.remove(at: index) } }
            else if let command { config.commands.append(command) }
        }, { $0.setEntry("command", at: index, to: command?.toml) })
    }

    func setSnippet(at index: Int?, to snippet: Config.Snippet?) {
        save({ config in
            if let index { if let snippet { config.snippets[index] = snippet } else { config.snippets.remove(at: index) } }
            else if let snippet { config.snippets.append(snippet) }
        }, { $0.setEntry("snippet", at: index, to: snippet?.toml) })
    }

    private func read() -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
}

final class SettingsWindow: AppWindow {
    let model: SettingsModel

    init(showWelcome: @escaping @MainActor () -> Void) {
        let model = SettingsModel()
        self.model = model
        super.init(title: "Copperlight Settings", style: .miniaturizable, content: SettingsView(model: model, showWelcome: showWelcome))
        // A real toolbar holds the pane's title, and content scrolling under it fades out instead of running behind it.
        toolbar = NSToolbar()
        toolbarStyle = .unified
        titlebarAppearsTransparent = false
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case general = "General", clipboard = "Clipboard", search = "Files", browser = "Browser",
         commands = "Commands", snippets = "Snippets", about = "About"

    var id: Self { self }

    /// The panes of the features that are on (Features.swift).
    static var shown: [Pane] {
        allCases.filter { [.clipboard: Feature.clipboard, .commands: .commands, .snippets: .snippets][$0]?.isOn ?? true }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .search: "folder.fill"
        case .browser: "globe"
        case .commands: "command"
        case .snippets: "text.quote"
        case .about: "info"
        }
    }
}

private struct SettingsView: View {
    let model: SettingsModel
    let showWelcome: @MainActor () -> Void
    @State private var pane = Pane.general

    var body: some View {
        NavigationSplitView {
            List(Pane.shown, selection: $pane) { pane in
                Label { Text(pane.rawValue) } icon: { Tile(symbol: pane.symbol) }.tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if let problem = model.problem { Problem(text: problem, broken: model.broken) }
                Form {
                    switch pane {
                    case .general: GeneralPane(model: model, showWelcome: showWelcome)
                    case .clipboard: ClipboardPane(model: model)
                    case .search: FilesPane(model: model)
                    case .browser: BrowserPane(model: model)
                    case .commands: CommandsPane(model: model)
                    case .snippets: SnippetsPane(model: model)
                    case .about: AboutPane()
                    }
                }
                .formStyle(.grouped)
                .disabled(model.broken)
            }
            .navigationTitle(pane.rawValue)
        }
        .frame(width: 800, height: 580)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in model.reload() }
    }
}

/// A pane's glyph on the icon's copper.
private struct Tile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(LinearGradient(colors: [.copper, .copperDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 6, style: .continuous))
    }
}

private struct Problem: View {
    let text: String
    let broken: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open config.toml") { NSWorkspace.shared.open(Config.file) }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.orange.opacity(0.1))
    }
}

// MARK: Panes

private struct GeneralPane: View {
    let model: SettingsModel
    let showWelcome: @MainActor () -> Void

    /// The currencies the ECB publishes rates for.
    private static let currencies = ["AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS",
                                     "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD",
                                     "THB", "TRY", "USD", "ZAR"]

    var body: some View {
        Section {
            LabeledContent("Open Copperlight") {
                // The library's conflict alerts are app-modal: hidden behind another window, they froze the whole app.
                // Our menu only exists while a window is open, so its shortcuts can't clash; a macOS one shows below.
                KeyboardShortcuts.Recorder(shortcut: model.hotkey)
                    .keyboardShortcutsConflictPolicy(.init(menuItem: .allow, systemShortcut: .allow))
                    .id(model.hotkeyResets)
            }
            Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = setLaunchAtLogin($0) }))
        } footer: {
            if model.config.hotkeys.launcher.shortcut.isTakenBySystem {
                Note("macOS uses this shortcut too, and it wins. Turn it off in System Settings › Keyboard › Keyboard Shortcuts, or record another one.")
                    .foregroundStyle(.orange)
            } else {
                Note("The only global shortcut. Everything else is typed in the launcher.")
            }
        }
        Section {
            Picker("Convert to", selection: model.binding(\.currency.defaultTarget, "currency", "default_target") { .string($0) }) {
                ForEach(Self.currencies, id: \.self) { code in
                    Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                }
            }
        } header: { Text("Currency") } footer: {
            Note("For an amount without a target, like “25 usd”.")
        }
        if !TranslateProvider.languageChoices.isEmpty { // macOS 26, once the Mac has said which languages it translates
            Section {
                Picker("Translate to", selection: model.text(\.translate.defaultTarget, "translate", "default_target")) {
                    Text("Automatic").tag(String?.none)
                    ForEach(TranslateProvider.languageChoices, id: \.key) { Text($0.name).tag(Optional($0.key)) }
                }
            } header: { Text("Translate") } footer: {
                Note("For text without “to …”, like “translate bom dia”. Automatic: the first of your Mac’s languages the text isn’t in, which is also used when the text is already in this one.")
            }
        }
        Section("Pomodoro") {
            Minutes(title: "Focus", value: model.binding(\.pomodoro.defaultMinutes, "pomodoro", "default_minutes") { .int($0) })
            Minutes(title: "Break", value: model.binding(\.pomodoro.breakMinutes, "pomodoro", "break_minutes") { .int($0) })
        }
        Section {
            LabeledContent("Welcome screen") { Button("Show", action: showWelcome) }
            LabeledContent("config.toml") {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Config.file]) }
                Button("Open") { NSWorkspace.shared.open(Config.file) }
            }
        } footer: {
            Note("Everything here is saved in ~/.config/copperlight/config.toml, with your comments kept. Edit it by hand any time: changes apply when you save.")
        }
    }
}

private struct Minutes: View {
    let title: String
    let value: Binding<Int>

    var body: some View {
        Stepper(value: value, in: 1...240, step: 5) {
            LabeledContent(title) { Text("\(value.wrappedValue) min").monospacedDigit() }
        }
    }
}

private struct ClipboardPane: View {
    let model: SettingsModel

    var body: some View {
        Section {
            NumberRow(title: "Keep up to", unit: "items", value: model.binding(\.clipboard.maxItems, "clipboard", "max_items") { .int($0) }, range: 1...100_000)
            NumberRow(title: "For", unit: "days", value: model.binding(\.clipboard.maxDays, "clipboard", "max_days") { .int($0) }, range: 1...3650)
            NumberRow(title: "Images", unit: "at most", value: model.binding(\.clipboard.maxImages, "clipboard", "max_images") { .int($0) }, range: 0...10_000)
        } header: { Text("History") } footer: {
            Note("Older items are deleted. Images take room (a screenshot is 1–5 MB); 0 keeps text only.")
        }
        let apps = model.strings(\.clipboard.ignoreApps, "clipboard", "ignore_apps")
        Section {
            ForEach(apps.wrappedValue, id: \.self) { id in
                Removable { AppName(app: id) } remove: { apps.wrappedValue.removeAll { $0 == id } }
            }
            Button("Add App…") {
                Task {
                    if let id = await chooseApp().flatMap({ Bundle(url: $0)?.bundleIdentifier }), !apps.wrappedValue.contains(id) {
                        apps.wrappedValue.append(id)
                    }
                }
            }
        } header: { Text("Don't record copies made in") } footer: {
            Note("Password managers are on the list from the start. Copies marked as passwords are never recorded.")
        }
    }
}

private struct FilesPane: View {
    let model: SettingsModel
    @State private var name = ""

    var body: some View {
        let scopes = model.strings(\.files.scopes, "files", "scopes")
        Section {
            ForEach(scopes.wrappedValue, id: \.self) { path in
                Removable { FolderName(path: path) } remove: { scopes.wrappedValue.removeAll { $0 == path } }
            }
            Button("Add Folder…") { Task { if let path = await chooseFolder(), !scopes.wrappedValue.contains(path) { scopes.wrappedValue.append(path) } } }
        } header: { Text("Search in") } footer: {
            Note("From 2 letters, or “f” and a name for files only. Uses Spotlight's index, so what Spotlight skips is skipped too.")
        }
        let exclude = model.strings(\.files.exclude, "files", "exclude")
        Section {
            ForEach(exclude.wrappedValue, id: \.self) { item in
                Removable { Text(item).monospaced() } remove: { exclude.wrappedValue.removeAll { $0 == item } }
            }
            TextField("Add a name", text: $name).onSubmit {
                let item = name.trimmingCharacters(in: .whitespaces)
                if !item.isEmpty, !exclude.wrappedValue.contains(item) { exclude.wrappedValue.append(item) }
                name = ""
            }
        } header: { Text("Hide results inside") } footer: {
            Note("Whole folder or file names, anywhere in the path, like node_modules.")
        }
        Section {
            Toggle("Look up app descriptions online", isOn: model.binding(\.apps.online, "apps", "online") { .bool($0) })
        } header: { Text("Apps") } footer: {
            Note("Apps are found by what they do too: “draw”, “noise”. Copperlight indexes each app's category and the files it opens, and with Apple Intelligence on, the Mac's own model adds words. Online, it adds Homebrew's public description (the whole list is downloaded, so nothing about your apps is sent) and the App Store's for apps you got there.")
        }
    }
}

private struct BrowserPane: View {
    let model: SettingsModel

    var body: some View {
        let name = model.config.browser.name
        let browsers = installedBrowsers()
        let profiles = browserProfiles(name)
        Section {
            Picker("Open links in", selection: Binding(get: { name }, set: { new in
                // Another browser's profiles are other names: start it without one.
                model.save({ $0.browser.name = new; $0.browser.profile = nil },
                           { $0.set("name", in: "browser", to: new.map(TOMLValue.string)); $0.set("profile", in: "browser", to: nil) })
            })) {
                Text("Default Browser").tag(String?.none)
                ForEach(browsers + (name.map { browsers.contains($0) ? [] : [$0] } ?? []), id: \.self) { AppName(app: $0).tag(String?.some($0)) }
            }
            let profile = model.text(\.browser.profile, "browser", "profile")
            Picker("Profile", selection: profile) {
                Text("Any (the browser decides)").tag(String?.none)
                let current = profile.wrappedValue.map { profiles.contains($0) ? [] : [$0] } ?? []
                ForEach(profiles + current, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .disabled(profiles.isEmpty && profile.wrappedValue == nil)
        } footer: {
            Note("Typed addresses, the search row, and link commands without their own browser. Profiles work in Chrome, Brave, Edge, Vivaldi and Firefox.")
        }
        Section {
            Picker("Search engine", selection: Binding(get: { model.config.browser.search ?? .google }, set: { new in
                let search = new == .google ? nil : new // the default: no line for it
                model.save({ $0.browser.search = search }, { $0.set("search", in: "browser", to: search.map { .string($0.rawValue) }) })
            })) {
                ForEach(SearchEngine.allCases, id: \.self) { EngineName(engine: $0).tag($0) }
            }
        } footer: {
            Note("The last row of every search, so Enter on something nothing else matches searches the web.")
        }
    }
}

private struct EngineName: View {
    let engine: SearchEngine

    var body: some View {
        Label {
            Text(engine.name)
        } icon: {
            Image(engine.logo).resizable().scaledToFit().clipShape(.rect(cornerRadius: 4)).frame(width: 18, height: 18)
        }
    }
}

// MARK: Commands and snippets

private struct CommandsPane: View {
    let model: SettingsModel
    @State private var editing: CommandDraft?

    var body: some View {
        Section {
            if model.config.commands.isEmpty { Text("No commands yet.").foregroundStyle(.secondary) }
            ForEach(Array(model.config.commands.enumerated()), id: \.offset) { index, command in
                EntryRow(title: command.alias, detail: CommandDraft(command).summary, symbol: CommandDraft(command).kind.symbol) {
                    editing = CommandDraft(command, index: index)
                }
            }
            Button("Add Command…") { editing = CommandDraft() }
        } header: { Text("Commands") } footer: {
            Note("Type a command's name in the launcher. One named like a built-in (screenshot, add todo) replaces it.")
        }
        Section {
            LabeledContent("Scripts folder") { Button("Open") { NSWorkspace.shared.open(scriptsDir) } }
        } footer: {
            Note("Every executable file in ~/.config/copperlight/scripts is a command too, found by its file name.")
        }
        .sheet(item: $editing) { draft in
            CommandEditor(draft: draft) { model.setCommand(at: draft.index, to: $0); editing = nil } cancel: { editing = nil }
        }
    }
}

/// A command being edited, with a field for each kind so switching kinds keeps what was typed.
private struct CommandDraft: Identifiable {
    enum Kind: String, CaseIterable { case url = "Link", app = "App", file = "File", shell = "Shell"
        var symbol: String { switch self { case .url: "link"; case .app: "app"; case .file: "doc"; case .shell: "terminal" } }

        var hint: String {
            switch self {
            case .url: "{query} in the address takes the text typed after the name: “gh copperlight” searches for copperlight."
            case .app: "Launches the app, or brings it forward."
            case .file: "Opens the file in its default app."
            case .shell: "Runs in your login shell (zsh -l), in your home folder. A failure shows as a notification."
            }
        }
    }

    let id = UUID()
    var index: Int?
    var alias = "", kind = Kind.url, url = "", browser: String?, profile = "", app = "", path = "", run = ""

    init() {}

    init(_ command: Config.Command, index: Int? = nil) {
        (self.index, alias) = (index, command.alias)
        switch command.action {
        case .url(let url, let browser, let profile): (kind, self.url, self.browser, self.profile) = (.url, url, browser, profile ?? "")
        case .app(let app): (kind, self.app) = (.app, app)
        case .file(let path): (kind, self.path) = (.file, path)
        case .shell(let run): (kind, self.run) = (.shell, run)
        }
    }

    var summary: String {
        switch kind {
        case .url: url
        case .app: app
        case .file: path
        case .shell: run
        }
    }

    /// nil until it has a name and something to do.
    var command: Config.Command? {
        let name = alias.trimmingCharacters(in: .whitespaces), target = summary.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !target.isEmpty else { return nil }
        let action: Config.Command.Action = switch kind {
        case .url: .url(target, browser: browser, profile: profile.isEmpty ? nil : profile)
        case .app: .app(target)
        case .file: .file(target)
        case .shell: .shell(target)
        }
        return Config.Command(alias: name, action: action)
    }
}

private struct CommandEditor: View {
    @State var draft: CommandDraft
    let save: (Config.Command?) -> Void
    let cancel: () -> Void

    var body: some View {
        Editor(title: draft.index == nil ? "New Command" : "Edit Command", canSave: draft.command != nil,
               save: { save(draft.command) }, delete: draft.index == nil ? nil : { save(nil) }, cancel: cancel) {
            Section {
                TextField("Name", text: $draft.alias, prompt: Text("what you type, like github"))
                Picker("Opens", selection: $draft.kind) {
                    ForEach(CommandDraft.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                switch draft.kind {
                case .url:
                    TextField("Address", text: $draft.url, prompt: Text("https://github.com/search?q={query}"))
                    Picker("Browser", selection: $draft.browser) {
                        Text("Where links open").tag(String?.none)
                        ForEach(installedBrowsers(), id: \.self) { AppName(app: $0).tag(String?.some($0)) }
                    }
                    TextField("Profile", text: $draft.profile, prompt: Text("optional, like Work"))
                case .app:
                    AppChooser(title: "App", none: "Choose an app", app: Binding(get: { draft.app.isEmpty ? nil : draft.app },
                                                                                set: { draft.app = $0 ?? "" }))
                case .file:
                    LabeledContent("File") {
                        Text(draft.path.isEmpty ? "None" : draft.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { Task { if let path = await chooseFile() { draft.path = path } } }
                    }
                case .shell:
                    TextField("Runs", text: $draft.run, prompt: Text("cd ~/code/api && docker compose up -d")).monospaced()
                }
            } footer: {
                Note(draft.kind.hint)
            }
        }
    }
}

private struct SnippetsPane: View {
    let model: SettingsModel
    @State private var editing: SnippetDraft?

    var body: some View {
        Section {
            if model.config.snippets.isEmpty { Text("No snippets yet.").foregroundStyle(.secondary) }
            ForEach(Array(model.config.snippets.enumerated()), id: \.offset) { index, snippet in
                EntryRow(title: snippet.name, detail: snippet.text.replacingOccurrences(of: "\n", with: " ⏎ "), symbol: "text.quote") {
                    editing = SnippetDraft(index: index, name: snippet.name, text: snippet.text)
                }
            }
            Button("Add Snippet…") { editing = SnippetDraft() }
        } header: { Text("Snippets") } footer: {
            Note("Type a snippet's name in the launcher and press Enter to paste its text into the app you were in.")
        }
        .sheet(item: $editing) { draft in
            SnippetEditor(draft: draft) { model.setSnippet(at: draft.index, to: $0); editing = nil } cancel: { editing = nil }
        }
    }
}

private struct SnippetDraft: Identifiable {
    let id = UUID()
    var index: Int?
    var name = "", text = ""
}

private struct SnippetEditor: View {
    @State var draft: SnippetDraft
    let save: (Config.Snippet?) -> Void
    let cancel: () -> Void

    var body: some View {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        Editor(title: draft.index == nil ? "New Snippet" : "Edit Snippet", canSave: !name.isEmpty && !draft.text.isEmpty,
               save: { save(Config.Snippet(name: name, text: draft.text)) }, delete: draft.index == nil ? nil : { save(nil) },
               cancel: cancel) {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("what you type, like sig"))
            }
            Section {
                TextEditor(text: $draft.text).font(.body).frame(minHeight: 120).scrollContentBackground(.hidden)
            } header: { Text("Text") } footer: {
                HStack(spacing: 6) {
                    Text("Insert:").foregroundStyle(.secondary)
                    ForEach(["{date}", "{time}", "{clipboard}", "{query}"], id: \.self) { token in
                        Button(token) { draft.text += token }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .font(.caption)
            }
        }
    }
}

/// A sheet with a form, and Delete, Cancel and Save under it.
private struct Editor<Fields: View>: View {
    let title: String
    let canSave: Bool
    let save: () -> Void
    let delete: (() -> Void)?
    let cancel: () -> Void
    var height: CGFloat? = nil // a long form scrolls in this much
    @ViewBuilder let fields: Fields

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline).padding(.top, 18)
            Form { fields }.formStyle(.grouped).scrollDisabled(height == nil).frame(height: height)
            HStack {
                if let delete { Button("Delete", role: .destructive, action: delete) }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: 520)
    }
}

// MARK: Rows

/// Version, license and links, then the open source Copperlight is built with (Acknowledgements.swift).
private struct AboutPane: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            LabeledContent("License") { Link("GNU GPL v3", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) }
            LabeledContent("Website") { Link("copperlight.app", destination: URL(string: "https://copperlight.app")!) }
            LabeledContent("Source code") { Link("github.com/ramosrob/copperlight", destination: URL(string: "https://github.com/ramosrob/copperlight")!) }
        } footer: {
            Note("Copperlight is free and open source. © 2026 Robson Ramos.")
        }
        Section {
            ForEach(acknowledgements) { credit in
                LabeledContent {
                    Link("Website", destination: credit.url)
                } label: {
                    Text(credit.package)
                    Text(credit.copyright)
                }
            }
        } header: {
            Text("Acknowledgements")
        } footer: {
            Note("Copperlight is built with these, each under the MIT License:")
        }
        Section {
            Text(mitLicense).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

private struct NumberRow: View {
    let title: String
    let unit: String
    let value: Binding<Int>
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Removable<Content: View>: View {
    @ViewBuilder let content: Content
    let remove: () -> Void

    var body: some View {
        HStack {
            content
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Remove")
        }
    }
}

/// A command or snippet: name, what it does, and Edit.
private struct EntryRow: View {
    let title: String
    let detail: String
    let symbol: String
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Edit…", action: edit)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }
}

/// An app by name or bundle id, with its icon.
private struct AppName: View {
    let app: String

    var body: some View {
        let url = browserApp(app)
        Label {
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? app)
        } icon: {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
                .resizable().frame(width: 18, height: 18)
        }
    }
}

private struct FolderName: View {
    let path: String

    var body: some View {
        Label {
            Text(path).lineLimit(1).truncationMode(.middle)
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: (path as NSString).expandingTildeInPath)).resizable().frame(width: 18, height: 18)
        }
    }
}

/// An optional app setting: its name and icon, Choose…, and a way back to the default.
private struct AppChooser: View {
    let title: String
    let none: String
    let app: Binding<String?>

    var body: some View {
        LabeledContent(title) {
            if let name = app.wrappedValue {
                AppName(app: name)
                Button { app.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Use \(none)")
            } else {
                Text(none).foregroundStyle(.secondary)
            }
            Button("Choose…") { Task { if let url = await chooseApp() { app.wrappedValue = url.deletingPathExtension().lastPathComponent } } }
        }
    }
}

// MARK: Pickers

/// Shows `panel` as a sheet on the front window. A sheet only blocks its window; runModal blocks the whole app,
/// launcher and notes included, and looks frozen once it ends up behind another app.
@MainActor private func choose(_ panel: NSOpenPanel) async -> URL? {
    guard let window = NSApp.keyWindow else { return panel.runModal() == .OK ? panel.url : nil }
    return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
}

@MainActor private func chooseApp() async -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(filePath: "/Applications")
    return await choose(panel)
}

@MainActor private func chooseFolder() async -> String? {
    let panel = NSOpenPanel()
    (panel.canChooseDirectories, panel.canChooseFiles) = (true, false)
    return await choose(panel).map { ($0.path as NSString).abbreviatingWithTildeInPath }
}

/// Folders, several at once.
@MainActor private func chooseFile() async -> String? {
    await choose(NSOpenPanel()).map { ($0.path as NSString).abbreviatingWithTildeInPath }
}

/// Apps that open web links, by name.
private func installedBrowsers() -> [String] {
    let names = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).map { $0.deletingPathExtension().lastPathComponent }
    return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// The profile names of a browser (nil: the default one), for those Copperlight can open in a profile.
private func browserProfiles(_ browser: String?) -> [String] {
    guard let app = browserApp(browser), let id = Bundle(url: app)?.bundleIdentifier else { return [] }
    if let folder = chromiumFolders[id],
       let data = try? Data(contentsOf: URL.applicationSupportDirectory.appending(path: "\(folder)/Local State")) {
        return chromiumProfiles(localState: data).map(\.name)
    }
    if id == "org.mozilla.firefox" { return firefoxProfiles(URL.applicationSupportDirectory.appending(path: "Firefox")).map(\.name) }
    return []
}
