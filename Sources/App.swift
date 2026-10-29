import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

// The launcher's shortcut comes from config.toml ([hotkeys]); see Config.Hotkeys for the default.
extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self("toggleLauncher")
}

extension Hotkey {
    var shortcut: KeyboardShortcuts.Shortcut { .init(.init(rawValue: keyCode), modifiers: modifiers) }
}

/// Launcher rows for Copperlight's own features.
struct BuiltinProvider: ResultProvider {
    let showNote: @MainActor @Sendable (URL) -> Void // a note's file
    let showClipboard: @MainActor @Sendable () -> Void
    var showWelcome: @MainActor @Sendable () -> Void = {}
    var showSettings: @MainActor @Sendable () -> Void = {}
    var newNote: @MainActor @Sendable (String) -> Void = { _ in } // a new note starting with this text ("": empty)
    var notesFolder = notesDir
    var noteFile = mainNoteFile

    /// The Notes chip (`note` ⇥): your notes alone, without apps or the search row.
    var modes: [Mode] {
        Feature.notes.isOn ? [Mode(prefix: "note ", title: "Notes", icon: .symbol("note.text"), hint: "A word in them, or nothing for all")] : []
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        // The launcher trims the query: the chip alone is "note".
        let lower = query.lowercased()
        return lower == "note" || lower.hasPrefix("note ") ? noteRows(query.dropFirst(4).trimmingCharacters(in: .whitespaces)) : results(for: query)
    }

    func results(for query: String) -> [LauncherResult] {
        var rows: [LauncherResult] = []
        let lower = query.lowercased()
        if Feature.notes.isOn, let score = score(query, prefixOf: "note", title: "Note") {
            let last = notes().first?.url
            rows.append(LauncherResult(id: "builtin:note", title: "Note", subtitle: "Your last note · Esc hides it",
                                       icon: .symbol("note.text"), score: score,
                                       action: { [showNote, newNote] in if let last { showNote(last) } else { newNote("") } }))
        }
        if Feature.notes.isOn {
            rows += notesStartRow(lower).map { [$0] } ?? []
            if lower.count >= 5, "new note".hasPrefix(lower) { rows.append(newNoteRow("", score: 50)) }
            rows += noteTextRows(query)
        }
        // From 3 letters: "c" and "cl" belong to Chrome, Calendar, Claude…
        if Feature.clipboard.isOn, let score = score(query, prefixOf: "clipboard", minLength: 3, title: "Clipboard History") {
            rows.append(LauncherResult(id: "builtin:clipboard", title: "Clipboard History", subtitle: "Search past copies",
                                       icon: .symbol("doc.on.clipboard"), score: score,
                                       action: showClipboard))
        }
        if let score = score(query, prefixOf: "welcome", minLength: 3, title: "Welcome to Copperlight") {
            rows.append(LauncherResult(id: "builtin:welcome", title: "Welcome to Copperlight",
                                       subtitle: "The hotkey, permissions, Open at Login", icon: .symbol("hand.wave"),
                                       score: score, action: showWelcome))
        }
        // "settings" alone is System Settings' too, so only a plain fuzzy match there; "copperlight" goes straight to it.
        if let score = score(query, prefixOf: "copperlight settings", minLength: 3, title: "Copperlight Settings") {
            rows.append(LauncherResult(id: "builtin:settings", title: "Copperlight Settings",
                                       subtitle: "Hotkey, clipboard, files, browser, commands, snippets", icon: .symbol("gearshape"),
                                       score: score, action: showSettings))
        }
        return rows
    }

    /// ponytail: every note is read on every keystroke that asks for them; cache by date if there are many.
    private func notes() -> [NoteFile] { notesByDate(in: notesFolder, main: noteFile) }

    private func noteRow(_ note: NoteFile, id: String, subtitle: String, score: Double) -> LauncherResult {
        let url = note.url
        return LauncherResult(id: id, title: note.title, subtitle: subtitle, accessory: shortAge(note.edited), icon: .symbol("note.text"),
                              score: score, action: { [showNote] in showNote(url) }, preview: note.text.isEmpty ? nil : note.text,
                              previewStyle: .prose)
    }

    /// `not`, `note`, `notes`: the list, a Tab away (the Notes chip); `note milk`: the list, already searching.
    private func notesStartRow(_ lower: String) -> LauncherResult? {
        let typed = lower.hasPrefix("note ") ? lower.dropFirst(5).trimmingCharacters(in: .whitespaces) : ""
        let score: Double
        if !typed.isEmpty { score = 50 }
        else if lower.count >= 3, "notes".hasPrefix(lower) { score = lower.hasPrefix("notes") ? 50.01 : 49.99 }
        else if let other = otherNameScore(lower, "All Notes") { score = other }
        else { return nil }
        return LauncherResult(id: "builtin:notes", title: typed.isEmpty ? "Notes" : "Notes with “\(typed)”",
                              subtitle: typed.isEmpty ? "All your notes, the last edited first" : "Your notes that say it",
                              icon: .symbol("list.bullet.rectangle"), score: score, actionTitle: "List",
                              action: {}, completion: "note " + typed)
    }

    private func newNoteRow(_ text: String, score: Double) -> LauncherResult {
        LauncherResult(id: "note:new", title: "New Note", subtitle: text.isEmpty ? "An empty one" : "Starting with “\(text)”",
                       icon: .symbol("square.and.pencil"), score: score, actionTitle: "Create", action: { [newNote] in newNote(text) })
    }

    /// In the Notes chip: every note by its first line, last edited first, with the next line and, beside the list,
    /// its text; then New Note. `milk`: the notes with "milk" in them, and a new one starting with it.
    private func noteRows(_ typed: String) -> [LauncherResult] {
        notes().enumerated().compactMap { index, note -> LauncherResult? in
            let line = typed.isEmpty ? nil : matchingLine(note.text, typed)
            guard typed.isEmpty || line != nil else { return nil }
            return noteRow(note, id: "note:\(note.url.lastPathComponent)", subtitle: line ?? note.summary, score: 49 - Double(index) / 100)
        } + [newNoteRow(typed, score: 0)]
    }

    /// The notes with `query`'s words in them, anywhere, from 3 letters: below what matches by name, with the line.
    private func noteTextRows(_ query: String) -> [LauncherResult] {
        let lower = query.lowercased()
        guard query.count >= 3, lower != "note", !lower.hasPrefix("note ") else { return [] }
        return notes().compactMap { note in
            matchingLine(note.text, query).map {
                noteRow(note, id: "note-text:\(note.url.lastPathComponent)", subtitle: "Note · \($0)", score: 0.3)
            }
        }
    }

    /// A prefix of `keyword` (at least `minLength` long) ranks first: above apps, fuzzy commands and
    /// math; only an exact command alias (100) beats it. Anything else is a plain fuzzy match on the title.
    private func score(_ query: String, prefixOf keyword: String, minLength: Int = 1, title: String) -> Double? {
        query.count >= minLength && keyword.hasPrefix(query.lowercased()) ? 50 : fuzzyScore(query, title) ?? otherNameScore(query, title)
    }
}

@main
struct CopperlightApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var launchAtLogin = false

    var body: some Scene {
        MenuBarExtra("Copperlight", image: "Mark") { // the icon's C
            Button("Settings…") { delegate.showSettings() }.keyboardShortcut(",")
            Button("Welcome to Copperlight") { delegate.showWelcome() }
            Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = setLaunchAtLogin($0) }))
                // The menu is built once, so ask again each time it opens: System Settings → Login Items may have
                // changed it. onAppear covers the first open, before onReceive is listening.
                .onAppear(perform: readLaunchAtLogin)
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in readLaunchAtLogin() }
            Divider()
            Button("Quit Copperlight") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }

    private func readLaunchAtLogin() { launchAtLogin = SMAppService.mainApp.status == .enabled }
}

/// Registers this copy of the app (wherever it is now) as a login item, or removes it.
/// Returns whether it ends up enabled.
@MainActor func setLaunchAtLogin(_ on: Bool) -> Bool {
    let service = SMAppService.mainApp
    do {
        if on { try service.register() } else { try service.unregister() }
    } catch {
        notify("Couldn't change Launch at Login", error.localizedDescription)
    }
    if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    return service.status == .enabled
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let apps = AppProvider()
    private let currency = CurrencyProvider()
    private let commands = CommandProvider()
    private let web = WebProvider()
    private let snippets = SnippetProvider()
    private let pages = BrowserPagesProvider()
    private let meetings = MeetingsProvider()
    private let contacts = ContactsProvider()
    private let tabs = BrowserTabsProvider()
    private let reminders = RemindersProvider()
    private let translate = TranslateProvider()
    private let files = FileSearchProvider()
    private let photoText = Feature.photoText.isOn ? try? PhotoTextStore(path: PhotoTextStore.file.path) : nil
    private lazy var photoIndexer = photoText.map(PhotoIndexer.init)
    private let pomodoro = Pomodoro()
    private let countdown = Countdown()
    private let stopwatch = Stopwatch()
    private lazy var builtins = BuiltinProvider(showNote: { [unowned self] in showNote($0) },
                                                showClipboard: { [unowned self] in showClipboard() },
                                                showWelcome: { [unowned self] in showWelcome() },
                                                showSettings: { [unowned self] in showSettings() },
                                                newNote: { [unowned self] in newNote($0) })
    private lazy var capture = CaptureProvider(addToNote: { [unowned self] in addToNote($0) })
    private lazy var verbs = VerbProvider(
        verbs: Verb.launcher(files: files)
            + (Feature.notes.isOn ? Verb.notes(release: { [unowned self] in releaseNote($0) }) : []),
        more: { frontMenuRows($0) })
    // Each provider with the feature it belongs to (none: always on); Features.swift says which are on.
    private lazy var model = SearchModel(
        providers: ([(commands, .commands), (ScriptProvider(), .scripts), (snippets, .snippets), (builtins, nil),
                     (EmojiProvider(), .quickTools), (DefineProvider(), .quickTools), (SpellProvider(), .quickTools),
                     (translate, .quickTools), (StockProvider(), .quickTools), (meetings, nil), (reminders, nil), (contacts, nil), (TextToolProvider(), .quickTools),
                     (ColorProvider(show: { [unowned self] in panel.show(typing: $0) }), .quickTools), (QRCodeProvider(), .quickTools), (LargeTypeProvider(), .quickTools),
                     (ScreenTextProvider(show: { [unowned self] in panel.show(typing: $0) }), .quickTools), (capture, .notes), (apps, nil),
                     (SettingsProvider(), .systemSettings), (CalculatorProvider(), nil), (currency, .quickTools), (UnitProvider(), .quickTools),
                     (TimeZoneProvider(), .quickTools), (DateMathProvider(), .quickTools), (PomodoroProvider(pomodoro: pomodoro), .quickTools),
                     (TimerProvider(clock: countdown), .quickTools),
                     (StopwatchProvider(watch: stopwatch), .quickTools), (LookupProvider(), .quickTools), (files, nil),
                     (FileContentProvider(files: files), .fileContent), (tabs, nil), (pages, nil), (web, nil)] as [(any ResultProvider, Feature?)])
            .compactMap { $0.1?.isOn == false ? nil : $0.0 } + (photoText.map { [PhotoTextProvider(store: $0)] } ?? []),
        exclusive: [FileSearchProvider.prefix: files, VerbProvider.prefix: verbs,
                    ShellProvider.prefix: ShellProvider(state: .shared),
                    "~": PathProvider(terminal: Self.terminal(files)), "/": PathProvider(terminal: Self.terminal(files))],
        frecency: .shared, idle: Self.upNext(meetings, reminders, clocks: { [unowned self] in
            runningClocks(pomodoro: pomodoro, timer: countdown, stopwatch: stopwatch)
                + (suggestsApps ? suggestionRows(StateStore.shared.get(AppOpen.stateSection, as: [AppOpen].self) ?? []) : [])
        }))
    private var suggestsApps = true
    private lazy var panel: LauncherPanel = LauncherPanel(model: model, placeholder: "Type anything")

    /// `[files] terminal`, asked when a file's Open in Terminal row is made.
    nonisolated private static func terminal(_ files: FileSearchProvider) -> @Sendable () async -> String? { { await files.terminalApp() } }

    /// What the empty launcher shows: the meeting to join, a few minutes before it starts, what's counting, reminders
    /// that are due, and the apps you open around now.
    nonisolated private static func upNext(_ meetings: MeetingsProvider, _ reminders: RemindersProvider,
                                           clocks: @escaping @MainActor @Sendable () -> [LauncherResult]) -> @Sendable () async -> [LauncherResult] {
        { (await meetings.upNext() + reminders.upNext() + MainActor.run { clocks() }).sorted { $0.score > $1.score } }
    }
    private var history: ClipboardHistory? // nil if clipboard.sqlite can't be opened
    private var historyError: String?
    private lazy var clipboardProvider = history.map {
        ClipboardProvider(store: $0.store, paste: { [unowned self] in paste($0) }, copy: { [unowned self] in history?.restore($0) })
    }
    private lazy var clipboardModel = SearchModel(
        providers: clipboardProvider.map { [$0] } ?? [], searchesEmptyQuery: true,
        exclusive: clipboardProvider.map { [VerbProvider.prefix: VerbProvider(verbs: $0.verbs)] } ?? [:])
    private lazy var clipboardPanel = LauncherPanel(model: clipboardModel, placeholder: "Search clipboard history, : for commands…")
    private var notes: [String: NotePanel] = [:] // by the file's path
    private var welcome: WelcomeWindow?
    private var settings: SettingsWindow?
    private var watcher: DirectoryWatcher?
    private var configText: String? // last config.toml contents seen; nil = no file
    private var configUpdate: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests launch the app too: don't grab hotkeys, touch files or hit the network there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true) // and configDir
        if !FileManager.default.fileExists(atPath: Config.file.path) {
            try? Config.example.write(to: Config.file, atomically: true, encoding: .utf8)
        }
        apply(Config()) // the "last valid config" if the file is broken from the start
        if Feature.clipboard.isOn {
            do {
                // After the defaults above, so retention only prunes with a config that actually loaded.
                history = ClipboardHistory(store: try ClipboardStore(path: ClipboardStore.file.path))
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ClipboardStore.file.path)
            } catch {
                historyError = error.localizedDescription
            }
        }
        reloadConfig()
        if Feature.quickTools.isOn {
            pomodoro.restore()
            countdown.restore()
            stopwatch.restore()
            Task { _ = await TranslateProvider.languages() } // its language chips
        }
        watcher = DirectoryWatcher(configDir) { [unowned self] in
            reloadConfig()
            notes[mainNoteFile.path]?.reloadIfChanged()
        }
        KeyboardShortcuts.onKeyDown(for: .toggleLauncher) { [unowned self] in
            welcome?.model.triedHotkey = true
            toggleLauncher()
        }
        refresh()
        if StateStore.shared.get("welcomed", as: Bool.self) != true {
            StateStore.shared.set("welcomed", true)
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.values.forEach { $0.saveNow() }
        StateStore.shared.flush()
    }

    private func toggleLauncher() {
        if panel.isVisible { return panel.orderOut(nil) }
        let selection = frontSelection() // before the panel takes the keys, so it's still the app's
        refresh()
        panel.show(typing: selection)
        // A browser asked to share its text just now answers a moment later: in time, unless you've typed already.
        guard selection == nil else { return }
        Task { [panel] in
            try? await Task.sleep(for: .milliseconds(250))
            if panel.isVisible, panel.model.query.isEmpty, let late = frontSelection() { panel.begin(with: late) }
        }
    }

    /// Brings the welcome screen forward, or builds it again if it was closed (so it plays its entrance again).
    func showWelcome() {
        if welcome?.isVisible != true {
            welcome = WelcomeWindow { [unowned self] in
                welcome?.close()
                refresh()
                panel.show()
            }
        }
        welcome?.model.keycaps = KeyboardShortcuts.getShortcut(for: .toggleLauncher)?.keycaps ?? []
        welcome?.show()
    }

    func showSettings() {
        if settings?.isVisible != true { settings = SettingsWindow(showWelcome: { [unowned self] in showWelcome() }) }
        settings?.show()
    }

    private func showClipboard() {
        clipboardModel.notice = historyError.map { error in
            LauncherResult(id: "clipboard-error", title: "Clipboard history is off: can't open clipboard.sqlite",
                           subtitle: error, icon: .symbol("exclamationmark.triangle"), score: .infinity,
                           actionTitle: "", action: {})
        }
        clipboardPanel.show()
    }

    /// Enter in the clipboard panel. Without Accessibility it can only copy, so it says how to fix that.
    private func paste(_ content: ClipboardContent) {
        history?.restore(content)
        if AXIsProcessTrusted() { return sendPaste() }
        clipboardModel.notice = LauncherResult(
            id: "accessibility", title: "Copied. To paste it too, allow Copperlight in Accessibility",
            subtitle: "Privacy & Security → Accessibility", icon: .symbol("lock.shield"), score: .infinity,
            actionTitle: "Open System Settings", action: { requestAccessibility() })
        clipboardPanel.show()
    }

    private func note(_ file: URL) -> NotePanel {
        if let panel = notes[file.path] { return panel }
        let panel = NotePanel(file: file)
        notes[file.path] = panel
        return panel
    }

    private func showNote(_ file: URL) { note(file).show() }

    /// A new note, opened: empty (its file is written once you type), or starting with `text` on its first line.
    private func newNote(_ text: String) {
        let file = newNoteFile()
        if !text.isEmpty {
            try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
            try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        showNote(file)
    }

    /// Closes a note's panel, saved, before it goes to the Trash.
    private func releaseNote(_ file: URL) {
        guard let panel = notes.removeValue(forKey: file.path) else { return }
        panel.saveNow()
        panel.orderOut(nil)
    }

    /// Through the panel, open or not, so text being typed in it isn't overwritten by the file.
    private func addToNote(_ line: String) { note(mainNoteFile).append(line) }

    /// Re-reads config.toml if it changed. A broken file keeps the current config and pins an
    /// error row to the launcher until it parses again.
    private func reloadConfig() {
        let text = try? String(contentsOf: Config.file, encoding: .utf8)
        guard text != configText else { return }
        configText = text
        do {
            apply(try text.map(Config.parse) ?? Config())
            model.notice = nil
        } catch {
            model.notice = LauncherResult(
                id: "config-error", title: "config.toml: \(Config.describe(error))",
                subtitle: "Using the last valid config", icon: .symbol("exclamationmark.triangle"),
                score: .infinity, actionTitle: "Open config.toml",
                action: { NSWorkspace.shared.open(Config.file) })
        }
        settings?.model.reload() // an edit by hand shows in the settings window too
    }

    private func apply(_ config: Config) {
        KeyboardShortcuts.setShortcut(config.hotkeys.launcher.shortcut, for: .toggleLauncher)
        history?.settings = config.clipboard
        NotePanel.stylesMarkdown = config.notes.markdown
        notes.values.forEach { $0.restyle() }
        pomodoro.defaultMinutes = config.pomodoro.defaultMinutes
        pomodoro.breakMinutes = config.pomodoro.breakMinutes
        suggestsApps = config.apps.suggestions
        // Chained so back-to-back reloads reach the providers in order.
        configUpdate = Task { [previous = configUpdate, commands, currency, translate, files, apps, web, snippets] in
            await previous?.value
            await commands.setCommands(config.commands, browser: config.browser)
            await snippets.setSnippets(config.snippets)
            await web.setBrowser(config.browser)
            await pages.setBrowser(config.browser)
            await meetings.setBrowser(config.browser)
            await meetings.setShowsOnOpen(config.meetings.showOnOpen)
            await pages.refresh()
            await currency.setDefaultTarget(config.currency.defaultTarget)
            translate.setDefaultTarget(config.translate.defaultTarget)
            await files.setSettings(config.files)
            await apps.setOnline(config.apps.online)
        }
    }

    private func refresh() {
        // Hours the first time, for a big library: on its own, and only one at a time (it says when it's busy).
        Task.detached(priority: .utility) { [photoIndexer] in await photoIndexer?.update() }
        Task { [apps, currency, pages, contacts, tabs] in
            await tabs.refresh()
            await apps.rescan()
            if Feature.quickTools.isOn { await currency.refreshIfStale() }
            await pages.refresh()
            await contacts.refresh()
        }
    }
}
