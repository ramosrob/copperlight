import AppKit
import SwiftUI

protocol ResultProvider: Sendable {
    func results(for query: String) async -> [LauncherResult]
    /// Names that text after them goes to, and only to this provider once one is a chip.
    var modes: [Mode] { get }
    /// The rows for a query in one of this provider's modes, its chip showing: the same as `results` unless being
    /// asked on purpose changes what it may do (`stock` asks Yahoo Finance only then).
    func modeResults(for query: String) async -> [LauncherResult]
    /// Answers late on purpose (file search waits for a pause in typing): a keystroke's rows show without waiting for
    /// it, and its own merge in when they come.
    var patient: Bool { get }
}

extension ResultProvider {
    var modes: [Mode] { [] }
    func modeResults(for query: String) async -> [LauncherResult] { await results(for: query) }
    var patient: Bool { false }
}

/// A name that text after it goes to (`translate `, `add todo `, `:quit `). Tab (or Enter on a row that fills it in)
/// turns it into a chip at the start of the field, the field holds what comes after it, and the query goes to its
/// provider alone. Typing never does: "stock apple" may be the start of a file's name.
struct Mode: Sendable {
    let prefix: String // lowercase, with the space that ends the name
    let title: String
    let icon: LauncherResult.Icon
    var hint = "" // the empty field's placeholder beside the chip
}

typealias OutputStep = @Sendable (_ progress: @escaping @Sendable (LauncherResult) async -> Void) async -> LauncherResult

/// How the preview pane sets its text: code and output monospaced, prose (a definition, a translation, a snippet)
/// in the text font.
enum PreviewStyle: Sendable { case code, prose }

struct LauncherResult: Identifiable, Sendable {
    /// A file's Finder icon (apps), an SF Symbol in a ring, or a picture
    /// loaded off the main thread (clipboard images; the string keys its cache), or a color's swatch.
    enum Icon: Sendable { case file(String), symbol(String), asset(String), image(String, @Sendable () -> CGImage?), color(RGBColor) }

    let id: String
    let title: String
    var subtitle = ""
    /// Right edge of the row, when it isn't selected (the selected one says what Enter does): a clipboard item's age,
    /// the text tool that made the title.
    var accessory = ""
    let icon: Icon
    var score: Double
    /// What Enter does, named on the selected row ("Open", "Copy"). Empty: no hint.
    var actionTitle = "Open"
    let action: @MainActor @Sendable () -> Void
    /// Tab (or Enter) puts this in the search field instead of running anything (`:quit` → ":quit ", to pick an app);
    /// a name that takes text becomes its chip.
    var completion: String? = nil
    /// The key the selected row shows beside what it does.
    var key: String { completion != nil ? "tab" : "↵" }
    /// Tab goes a step into the row while Enter still runs `action`: this goes in the field, its name becoming a chip
    /// (a person's ways to reach them). The selected row names it beside what Enter does.
    var more: (label: String, fill: String)? = nil
    /// Tab: what you can do with it (a file: open with, reveal, trash…), as rows in place of the list, under its title,
    /// the preview beside them. Esc goes back to the list; typing searches again.
    var actions: (@Sendable () async -> [LauncherResult])? = nil
    /// Something for the pane beside the list: text, text to load, or a picture.
    var hasPreview: Bool { preview != nil || loadPreview != nil || previewImage != nil }
    /// Enter runs it, drops the row and keeps the panel open, so several can go in a row (`:delete`).
    var staysOpen = false
    /// Enter runs it and leaves the panel as it is, for the next press (`:nudge left`).
    var repeats = false
    /// Ask first: Enter shows a row with this question, and Enter on that row runs `action`.
    var confirm: String? = nil
    /// Rows get a header where this changes (clipboard: Today, Yesterday, Earlier).
    var section: String? = nil
    /// A pill in the accent beside the title, for what's coming up ("in 9 min", "Now").
    var badge: String? = nil
    /// A clock in that pill instead, ticking while the row is shown: a timer's time left, a stopwatch's time so far.
    var ticking: Ticking? = nil
    /// Full text for the preview pane beside the list, with label/value lines under it.
    var preview: String? = nil
    var previewStyle = PreviewStyle.code
    /// Text for the preview fetched when the row is selected (a pull request's diff), when `preview` is nil.
    var loadPreview: (@Sendable () async -> String)? = nil
    /// An image for the preview pane instead of the text, loaded when the row is selected.
    var previewImage: (@MainActor @Sendable () -> NSImage?)? = nil
    var details: [(String, String)] = []
    /// Enter runs this with the panel open, a "Running…" row in place of the list, then shows the row it returns
    /// there (a shell line's output). Rows it passes to `progress` replace the running one as it goes (output so
    /// far). Esc stops it. If the panel was hidden or moved on by then, a notification says how it ended.
    var output: OutputStep? = nil
    /// Drawn big in place of the preview pane (a QR code, a stock, a color). Every row of one answer carries it, so it
    /// stays while you move between them.
    var answer: Answer? = nil
    /// Fills itself in: rows that take this one's place when they come (the weather, once Open-Meteo answers). Until
    /// then it shows as it is, its card loading; the next keystroke cancels them.
    var later: (@Sendable () async -> [LauncherResult])? = nil
}

let configDir = URL.homeDirectory.appending(path: ".config/copperlight")

@MainActor func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Non-activating panels never get the main menu's Edit shortcuts, so route them by hand.
@MainActor func performEditShortcut(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown, event.modifierFlags.contains(.command) else { return false }
    let action: Selector? = switch event.charactersIgnoringModifiers?.lowercased() {
    case "a": #selector(NSText.selectAll(_:))
    case "c": #selector(NSText.copy(_:))
    case "v": #selector(NSText.paste(_:))
    case "x": #selector(NSText.cut(_:))
    case "z": event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
    default: nil
    }
    return action.map { NSApp.sendAction($0, to: nil, from: nil) } ?? false
}

/// Plain `1234.5` style: no grouping, `.` decimals, so copied values paste anywhere.
func formatNumber(_ value: Double, decimals: ClosedRange<Int> = 0...10) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(decimals)))
}

/// How often a row was picked: each Enter adds 1, and the count halves every week.
struct Frecency: Codable, Sendable {
    typealias Table = [String: Frecency] // row id → count; an app's id is its path, as M1 stored it
    static let stateSection = "frecency"
    private static let halfLife: TimeInterval = 7 * 24 * 3600

    var score: Double, updated: Date

    func decayed(at now: Date) -> Double { score * pow(0.5, now.timeIntervalSince(updated) / Self.halfLife) }

    /// Added to a row's score: up to 0.5, reached after 5 recent picks.
    static func bonus(_ table: Table, _ id: String, at now: Date) -> Double { min(0.5, 0.1 * (table[id]?.decayed(at: now) ?? 0)) }

    /// `table` after one more pick of `id`. Rows unused for about a month are dropped, so it stays small.
    static func picking(_ id: String, in table: Table, at now: Date) -> Table {
        var table = table.filter { $0.value.decayed(at: now) >= 0.05 }
        table[id] = Frecency(score: (table[id]?.decayed(at: now) ?? 0) + 1, updated: now)
        return table
    }
}

/// A query run with Enter, as it was: in its chip, or typed. The launcher keeps the last 50 for ↑.
struct RecentQuery: Codable, Equatable, Sendable {
    static let stateSection = "recent"
    static let limit = 50
    var query: String
    var chip: Bool
}

@MainActor @Observable
final class SearchModel {
    var query = "" {
        didSet {
            if let mode, !query.lowercased().hasPrefix(mode.prefix) { modeMatch = nil } // replaced, not typed after the chip
            search()
        }
    }
    /// Pinned above the results, whatever the query, until cleared (e.g. a config error).
    var notice: LauncherResult?
    /// A confirmation question that replaces the list until answered (Enter) or dismissed (Esc, typing).
    var confirming: LauncherResult? { didSet { selection = 0 } }
    /// What you can do with the row Tab stepped into, in place of the list, and where that row was (Esc goes back to it).
    private(set) var stepped: (rows: [LauncherResult], from: Int)?
    private(set) var results: [LauncherResult] = []
    private(set) var selection = 0
    @ObservationIgnored private let providers: [any ResultProvider]
    @ObservationIgnored private let searchesEmptyQuery: Bool
    @ObservationIgnored private let exclusive: [String: any ResultProvider]
    @ObservationIgnored private let modeProviders: [any ResultProvider]
    /// Asked each time: a provider's names can change (Translate's languages arrive after launch).
    private var modes: [(mode: Mode, provider: any ResultProvider)] {
        modeProviders.flatMap { provider in provider.modes.map { ($0, provider) } }
    }
    @ObservationIgnored private var task: Task<Void, Never>?
    /// A round has started and its rows aren't shown yet: the list still shows the previous query's.
    @ObservationIgnored private(set) var settling = false
    /// A row's output step while it runs (a shell line): Esc cancels it, which stops the process.
    @ObservationIgnored var run: Task<Void, Never>?
    @ObservationIgnored private let state: StateStore?
    @ObservationIgnored private var frecency: Frecency.Table
    /// What was picked for what: "ss\t/Applications/Slack.app" → its picks, fading like frecency. That row comes first
    /// for that text next time, over anything else, so a few letters you use become an abbreviation with no setup.
    @ObservationIgnored private var learned: Frecency.Table
    static let learnedSection = "learned"
    @ObservationIgnored private var recent: [RecentQuery]
    /// What the empty field shows (the next meeting, a few minutes before it starts); nothing once you type.
    @ObservationIgnored private let idle: (@Sendable () async -> [LauncherResult])?
    /// The query ↑ brought back, and where it is in `recent`: ↑ again goes on from there.
    @ObservationIgnored private var recalled: (index: Int, query: String)?
    /// `[learning]`: off, picks and queries are neither kept nor used (what's kept stays, for when it's on again).
    @ObservationIgnored var learning = Config.Learning()
    /// `[apps] suggestions`: the apps opened from here are kept, with the time, only for those.
    @ObservationIgnored var keepsAppOpens = true
    /// `[answers] cards`: off, an answer is a plain row like the rest.
    var showsCards = true
    /// How many times the panel came up: each one springs the view in.
    var opens = 0
    /// `[keywords]`: your words for the built-in ones, "t" → "translate", ";" → ":".
    @ObservationIgnored var keywords: [String: String] = [:]

    /// `searchesEmptyQuery`: ask providers about "" too (the clipboard lists everything), instead of showing nothing.
    /// `exclusive`: a query starting with one of these prefixes ("f ") goes to that provider alone.
    /// `frecency`: rows picked often rise, counted in this store (the launcher; clipboard history keeps its order).
    init(providers: [any ResultProvider], searchesEmptyQuery: Bool = false, exclusive: [String: any ResultProvider] = [:],
         frecency state: StateStore? = nil, idle: (@Sendable () async -> [LauncherResult])? = nil) {
        self.idle = idle
        self.providers = providers
        self.searchesEmptyQuery = searchesEmptyQuery
        self.exclusive = exclusive
        modeProviders = providers + exclusive.values
        self.state = state
        frecency = state?.get(Frecency.stateSection, as: Frecency.Table.self) ?? [:]
        learned = state?.get(Self.learnedSection, as: Frecency.Table.self) ?? [:]
        recent = state?.get(RecentQuery.stateSection, as: [RecentQuery].self) ?? []
    }

    /// Enter ran a row: keep its query for ↑, newest first, once. Only the launcher's (clipboard history has no store).
    func remember() {
        guard let state, learning.recent, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        recent = Array(([RecentQuery(query: query, chip: mode != nil)] + recent.filter { $0.query != query }).prefix(RecentQuery.limit))
        state.set(RecentQuery.stateSection, recent)
    }

    /// ↑. In the empty field: the last query run. On one ↑ brought back, its top row selected: the one before it (at
    /// the oldest, nothing). false: ↑ moves in the list instead.
    func recallOlder() -> Bool {
        let next: Int
        if query.isEmpty { next = 0 }
        else if let recalled, recalled.query == query, selection == 0 { next = recalled.index + 1 }
        else { return false }
        guard learning.recent else { return false }
        guard recent.indices.contains(next) else { return !query.isEmpty }
        let entry = recent[next]
        if entry.chip { fill(entry.query) } else { modeMatch = nil; query = entry.query }
        recalled = (next, query)
        return true
    }

    /// Enter on a row: count it, so it ranks higher next time, and first for what's typed. An app's (its id is its
    /// path) is kept with the time too, for the empty launcher's suggestions.
    func picked(_ id: String) {
        guard let state else { return }
        if learning.picked {
            frecency = Frecency.picking(id, in: frecency, at: .now)
            state.set(Frecency.stateSection, frecency)
            // A few letters, not a sentence to translate: those would never come back the same.
            if case let typed = Self.learnedKey(query), !typed.isEmpty, typed.count <= 15 {
                learned = Frecency.picking("\(typed)\t\(id)", in: learned, at: .now)
                state.set(Self.learnedSection, learned)
            }
        }
        guard keepsAppOpens, id.hasPrefix("/"), id.hasSuffix(".app") else { return }
        let opens = (state.get(AppOpen.stateSection, as: [AppOpen].self) ?? []) + [AppOpen(app: id, at: .now)]
        state.set(AppOpen.stateSection, Array(opens.suffix(AppOpen.limit)))
    }

    enum Learned { case picks, queries, appOpens }

    /// Settings › Launcher's Forget: deletes what was kept, here and in state.json.
    func forget(_ what: Learned) {
        switch what {
        case .picks:
            (frecency, learned) = ([:], [:])
            state?.set(Frecency.stateSection, frecency)
            state?.set(Self.learnedSection, learned)
        case .queries:
            (recent, recalled) = ([], nil)
            state?.set(RecentQuery.stateSection, recent)
        case .appOpens: state?.set(AppOpen.stateSection, [AppOpen]())
        }
    }

    /// The chip showing, and whose: set by Tab or Enter only (`fill`, `complete`), never by typing.
    private var modeMatch: (mode: Mode, provider: any ResultProvider)?

    var mode: Mode? { modeMatch?.mode }

    /// The longest name `text` starts with (`:force quit ` over `:quit `).
    private func named(_ text: String) -> (mode: Mode, provider: any ResultProvider)? {
        let lower = text.lowercased()
        return modes.filter { lower.hasPrefix($0.mode.prefix) }.max { $0.mode.prefix.count < $1.mode.prefix.count }
    }

    /// `text` with your word for a keyword spelled the built-in way: "t bom dia" → "translate bom dia", ";left" →
    /// ":left". A word with letters counts alone or before a space; one of symbols, stuck to what follows too.
    func expanded(_ text: String) -> String {
        guard modeMatch == nil else { return text }
        let lower = text.lowercased()
        for (word, keyword) in keywords.sorted(by: { $0.key.count > $1.key.count }) {
            let symbols = !word.contains { $0.isLetter || $0.isNumber }
            guard lower == word || lower.hasPrefix(word + " ") || (symbols && lower.hasPrefix(word)) else { continue }
            let space = lower == word || !keyword.contains(where: \.isLetter) ? "" : " "
            return keyword + space + text.dropFirst(word.count).drop { $0 == " " }
        }
        return text
    }

    /// Puts `text` in the field as Tab or Enter fills it in: the name it starts with, if any, becomes its chip.
    func fill(_ text: String) {
        modeMatch = named(text)
        query = text
    }

    /// The field's text: the query, or what follows the mode's name while its chip shows.
    var typed: String {
        get { mode.map { String(query.dropFirst($0.prefix.count).drop(while: \.isWhitespace)) } ?? query }
        set { query = (mode?.prefix ?? "") + newValue }
    }

    /// Tab. A name typed with text after it becomes its chip, keeping the text (`stock aapl` → Stock, `aapl`); then, or
    /// already in a chip, an ending that names a longer one moves into it (`hello world to ger` → Translate to German).
    /// Otherwise: what the selected row fills in (Translate → "translate "), or the name that starts with what's typed
    /// (`translate`, with a translation selected). Nothing to fill in: nothing happens.
    func complete() {
        // Your word for a keyword becomes it first, a chip if the keyword has one: "t" → Translate, as "translate" would.
        if case let full = expanded(query), full != query {
            if named(full) == nil, named(full + " ") != nil { return fill(full + " ") }
            query = full
        }
        let entered = named(query).flatMap { $0.mode.prefix.count > (mode?.prefix.count ?? 0) ? $0 : nil }
        if let entered {
            modeMatch = entered
            search() // the same text, now for its provider alone
        }
        if moveEnding() || entered != nil { return }
        if let row = selected, let fill = row.completion ?? row.more?.fill {
            picked(row.id)
            return self.fill(fill)
        }
        if stepped == nil, let row = selected, let actions = row.actions {
            let from = selection
            Task {
                let rows = await actions().map { var action = $0; action.section = action.section ?? row.title; return action }
                guard self.selected?.id == row.id, !rows.isEmpty else { return } // typed on, or moved, meanwhile
                stepped = (rows, from)
                selection = 0
            }
            return
        }
        // A row with something to show: Tab opens it beside the list (and closes it again).
        if let row = selected, row.hasPreview, !previewsByDefault { return previewOpen.toggle() }
        // The shortest name that starts with it, when every other one goes on from it ("translate " before
        // "translate to german "); "add" could be several things, so it fills in nothing.
        let lower = query.lowercased()
        let names = modes.map(\.mode.prefix).filter { !lower.isEmpty && $0.hasPrefix(lower) && $0 != lower }.sorted { $0.count < $1.count }
        if let shortest = names.first, names.allSatisfy({ $0.hasPrefix(shortest) }) { fill(shortest) }
    }

    /// In a chip, the end of the text naming a longer one moves into it, the rest staying in the field. Longest ending
    /// first; one that fits several names does nothing.
    private func moveEnding() -> Bool {
        guard let mode else { return false }
        let longer = Set(modes.map(\.mode.prefix).filter { $0.hasPrefix(mode.prefix) && $0 != mode.prefix }).map { $0.dropFirst(mode.prefix.count) }
        let text = typed
        for start in text.indices where start == text.startIndex || text[text.index(before: start)] == " " {
            let fits = longer.filter { $0.hasPrefix(text[start...].lowercased()) }
            if fits.count > 1 { return false }
            if let extra = fits.first {
                fill(mode.prefix + extra + text[..<start].trimmingCharacters(in: .whitespaces))
                return true
            }
        }
        return false
    }

    /// Delete in the empty field after a chip: the chip turns back into its name, as if the space was deleted (Translate
    /// to German goes back to Translate, with "to german" in the field).
    func leaveMode() {
        if let mode, typed.isEmpty { fill(String(mode.prefix.dropLast())) }
    }

    var rows: [LauncherResult] { confirming.map { [$0] } ?? stepped?.rows ?? ((notice.map { [$0] } ?? []) + results) }

    /// Esc after Tab stepped into a row: back to the list, that row selected. false: there's nothing to back out of.
    func stepOut() -> Bool {
        guard let stepped else { return false }
        self.stepped = nil
        selection = min(stepped.from, max(0, rows.count - 1))
        return true
    }

    /// The preview beside the list, opened with Tab in the general search, for the selected row, until the query changes.
    var previewOpen = false
    /// Where reading is the point it's open from the start: clipboard history, a chip, a command's output.
    var previewsByDefault: Bool { searchesEmptyQuery || mode != nil || confirming != nil || stepped != nil }
    /// Only for a row with something to show: never an empty pane, and never beside an answer.
    var showsPreview: Bool { answer == nil && (selected?.hasPreview ?? false) && (previewsByDefault || previewOpen) }
    /// The answer of the row you're on, or else of the first row: moving to the search row under a color keeps its band.
    var answer: Answer? { showsCards ? selected?.answer ?? rows.first?.answer : nil }
    var selected: LauncherResult? { rows.indices.contains(selection) ? rows[selection] : nil }

    func move(_ delta: Int) {
        selection = max(0, min(rows.count - 1, selection + delta))
    }

    func remove(_ id: String) {
        results.removeAll { $0.id == id }
        selection = max(0, min(rows.count - 1, selection))
    }

    /// Every provider runs concurrently, and the rows are shown together once all have answered (a patient one, file
    /// search, aside: waiting for it held every keystroke 50 ms) or `wait` has passed with something to show; the
    /// previous query's rows stay until then. Showing each provider's rows as
    /// it answered emptied the list on every keystroke (the quick ones with nothing to say came first) and regrew
    /// it over 300 ms. Whatever answers after the wait merges in when it does: files (after their own 150 ms) and
    /// the other slow ones rank at the bottom, so the rows above don't move. A new keystroke cancels the round.
    private func search() {
        task?.cancel()
        confirming = nil
        stepped = nil
        previewOpen = false
        selection = 0
        let query = expanded(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || searchesEmptyQuery else {
            (results, settling) = ([], false)
            if let idle { task = Task { let rows = await idle(); if !Task.isCancelled { results = rows } } }
            return
        }
        // A chip's provider alone; else the longest prefix wins: ":!" (shell) over ":" (commands).
        let inMode = modeMatch != nil
        let providers = modeMatch.map { [$0.provider] }
            ?? exclusive.filter { query.hasPrefix($0.key) }.max { $0.key.count < $1.key.count }.map { [$0.value] } ?? providers
        let (frecency, learned, now, typed) = learning.picked ? (frecency, learned, Date.now, self.query.lowercased())
            : ([:], [:], Date.now, self.query.lowercased())
        let learnedKey = Self.learnedKey(self.query)
        settling = true
        // The rows show once the quick providers have answered, without waiting for a patient one (files); with
        // only patient ones (the files chip), once they have, or the wait is over.
        let quick = providers.filter { !$0.patient }.count
        task = Task {
            await withTaskGroup(of: (rows: [LauncherResult], patient: Bool)?.self) { group in
                for provider in providers {
                    group.addTask { (inMode ? await provider.modeResults(for: query) : await provider.results(for: query), provider.patient) }
                }
                // ponytail: one fixed wait, under what reads as instant; per-provider deadlines if one ever needs more.
                group.addTask { try? await Task.sleep(for: Self.wait); return nil } // nil: the wait is over
                var merged: [LauncherResult] = []
                var (pending, quickPending, waiting) = (providers.count, quick, true)
                for await answer in group {
                    guard !Task.isCancelled else { return }
                    if let (batch, patient) = answer {
                        pending -= 1
                        if !patient { quickPending -= 1 }
                        let boosted = batch.map { row in
                            var row = row
                            row.score += Frecency.bonus(frecency, row.id, at: now) + Self.learnedBonus(learned, learnedKey, row.id, at: now)
                            return row
                        }
                        merged = (merged + boosted).sorted { $0.score > $1.score }
                    } else {
                        waiting = false
                    }
                    // Nothing yet when the wait is over: keep the previous rows rather than an empty list.
                    guard pending == 0 || ((!waiting || quick > 0 && quickPending == 0) && !merged.isEmpty) else { continue }
                    // A [[command]] or script named like a built-in replaces it: "command:screenshot" hides "builtin:screenshot".
                    let replaced = Set(merged.compactMap { row in
                        ["command:", "script:"].first { row.id.hasPrefix($0) }.map { "builtin:" + row.id.dropFirst($0.count).lowercased() }
                    })
                    // A row whose Enter would type what's already there ("translate " beside its chip) does nothing.
                    results = merged.filter { !replaced.contains($0.id) && $0.completion?.lowercased() != typed }
                    selection = min(selection, max(0, rows.count - 1))
                    settling = false
                    if pending == 0 { return group.cancelAll() } // ends the wait early
                }
            }
            // Rows that fill themselves in take their places as they come, in this round: a keystroke cancels them.
            await withTaskGroup(of: (id: String, rows: [LauncherResult]).self) { group in
                for row in results { if let later = row.later { group.addTask { (row.id, await later()) } } }
                for await (id, rows) in group where !Task.isCancelled {
                    withAnimation(Motion.at(.easeOut(duration: 0.2))) { results = results.flatMap { $0.id == id ? rows : [$0] } }
                    selection = min(selection, max(0, self.rows.count - 1))
                }
            }
        }
    }

    static let wait = Duration.milliseconds(50)

    /// The text as learned: lowercased, its spaces trimmed.
    private static func learnedKey(_ query: String) -> String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    /// Above everything for the text it was picked for (an exact alias is 100), the most picked first.
    private static func learnedBonus(_ learned: Frecency.Table, _ typed: String, _ id: String, at now: Date) -> Double {
        let picks = learned["\(typed)\t\(id)"]?.decayed(at: now) ?? 0
        return picks > 0 ? 100 + picks : 0
    }
}

final class LauncherPanel: NSPanel {
    static let maxHeight: CGFloat = 480
    /// Clear room around the pieces for their shadows.
    static let margin: CGFloat = 60
    let model: SearchModel

    init(model: SearchModel, placeholder: String) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680 + 2 * Self.margin, height: Self.maxHeight + 2 * Self.margin),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the window's shadow traced each piece with a hard gray rim; the pieces draw soft ones
        // The window keeps its full height, clear below the card (clicks there go through): the card grows and
        // shrinks inside it. Resizing the window as results changed showed the pill jumping for a frame, and
        // animating back when an animation was running.
        let host = NSHostingView(rootView: LauncherView(model: model, placeholder: placeholder))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        // Inside a plain view, not as the content view: as the content view, NSHostingView sizes the window to fit
        // after each layout, and AppKit once aborted the app over it ("needing another Update Constraints in
        // Window pass").
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.addSubview(host)
        host.frame = container.bounds
        contentView = container
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { true }

    /// `text`: the selection in the app you were in, typed and selected, so typing replaces it.
    func show(typing text: String? = nil) {
        var instantly = Transaction()
        instantly.disablesAnimations = true // the last time's rows don't shrink away as it comes in
        withTransaction(instantly) { begin(with: text) }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            // Top edge where a full-height panel centered on the screen would have it.
            let area = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: area.midX - frame.width / 2, y: area.midY + Self.maxHeight / 2 + Self.margin))
        }
        guard !isVisible else { return makeKeyAndOrderFront(nil) }
        // It fades in while the view springs up from a touch smaller. Hiding stays instant: fading out, it would
        // still take the keys you type next.
        model.opens += 1
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// A new search: an empty field, or `text` in it, selected.
    func begin(with text: String?) {
        model.query = text ?? ""
        guard text != nil else { return }
        // The field shows the query a turn or two later (LauncherView keeps its own copy), and on the first show only
        // once it has focus: select it then.
        // ponytail: polls every 10 ms, for up to half a second; a callback from the field if that ever falls short.
        Task { [weak self] in
            for _ in 0..<50 {
                if let self, let editor = firstResponder as? NSTextView, editor.string == model.typed, !editor.string.isEmpty {
                    return editor.selectAll(nil)
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    // Focus loss hides the panel.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { return super.sendEvent(event) }
        switch event.keyCode {
        case 53: // Esc: stop what's running and back out of it (or of a question, or of a row's actions), else hide
            guard model.confirming != nil else { return model.stepOut() ? () : orderOut(nil) }
            model.run?.cancel()
            model.confirming = nil
        case 51 where model.mode != nil && model.typed.isEmpty: model.leaveMode() // Delete
        case 48: // Tab, never out of the field: fills in a name that takes text, once this query's rows are in
            if model.settling {
                return DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.sendEvent(event) }
            }
            model.complete()
        case 125: model.move(1) // ↓
        case 126: if !model.recallOlder() { model.move(-1) } // ↑: in the empty field, what you ran before
        case 36, 76: // Return, keypad Enter. Every action has its own row, so modifiers change nothing.
            // Typed and pressed Enter before the rows were in: wait for them (at most SearchModel.wait), so Enter
            // runs what this query finds, not the previous query's top row.
            if model.settling {
                return DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.sendEvent(event) }
            }
            guard let result = model.selected else { return }
            if result.completion == nil { model.remember() } // for ↑ next time
            if result.confirm == nil { model.picked(result.id) } // a question counts once answered
            if let completion = result.completion { return model.fill(completion) }
            if let question = result.confirm {
                model.confirming = LauncherResult(
                    id: result.id, title: question, subtitle: "Esc to cancel", icon: .symbol("exclamationmark.triangle"),
                    score: .infinity, actionTitle: "Confirm", action: result.action, output: result.output) // a check out runs once confirmed
                return
            }
            if let output = result.output {
                model.confirming = LauncherResult(id: result.id, title: result.title, subtitle: "Running… Esc stops it",
                                                  icon: result.icon, score: .infinity, actionTitle: "Hide", action: {})
                // Hiding the panel (Enter on "Hide", the hotkey) lets it finish; a notification says how it ended.
                let showing = { @MainActor [weak self] in self?.isVisible == true && self?.model.confirming?.id == result.id }
                model.run = Task {
                    let done = await output { partial in
                        await MainActor.run { [weak self] in if showing() { self?.model.confirming = partial } }
                    }
                    guard !Task.isCancelled else { return } // Esc: stopped on purpose, nothing to say
                    if showing() { return model.confirming = done }
                    notify(done.title, [done.subtitle, done.preview?.split(separator: "\n").suffix(4).joined(separator: "\n")]
                        .compactMap(\.self).joined(separator: "\n"))
                }
                return
            }
            if result.repeats { return result.action() }
            if result.staysOpen {
                result.action()
                return model.remove(result.id)
            }
            orderOut(nil)
            result.action()
        default:
            if performEditShortcut(event) { return }
            super.sendEvent(event)
        }
    }
}

extension NSImage {
    /// A stretchable rounded rectangle for `NSVisualEffectView.maskImage`.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = 2 * radius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// `[look] accent`: the color of the field's edge, the selection, chips and answers' titles. Copper, the icon's, unless
/// you'd rather your Mac's accent color (System Settings › Appearance) or one of your own.
enum Accent: Equatable, Sendable {
    case copper, system, color(RGBColor)

    /// Three shades: a light one, the main one, and a deep one that holds white text.
    struct Shades: Equatable, Sendable { var light, main, deep: RGBColor }

    /// The icon's C, top to side to bottom.
    static let copperShades = Shades(light: RGBColor(red: 254, green: 186, blue: 122), main: RGBColor(red: 222, green: 151, blue: 96),
                                     deep: RGBColor(red: 179, green: 110, blue: 66))

    /// `system`: the Mac's accent color; copper when there's none to follow.
    func shades(system: RGBColor?) -> Shades {
        switch self {
        case .copper: Self.copperShades
        case .system: system.map(Self.shades(around:)) ?? Self.copperShades
        case .color(let color): Self.shades(around: color)
        }
    }

    /// Lighter and more vivid, and deeper and quieter, as copper's are.
    private static func shades(around main: RGBColor) -> Shades {
        let (hue, saturation, lightness) = main.components
        return Shades(light: RGBColor(hue: hue, saturation: min(1, saturation * 1.3), lightness: min(0.88, lightness + 0.12)), main: main,
                      deep: RGBColor(hue: hue, saturation: saturation * 0.75, lightness: max(0.16, lightness - 0.14)))
    }

    /// As config.toml writes it; nil for copper, the default.
    var toml: String? {
        switch self {
        case .copper: nil
        case .system: "system"
        case .color(let color): color.hex
        }
    }
}

/// The accent in use, which every view reads, so a change in config.toml shows at once; with `system`, it follows the
/// Mac's accent color as it changes.
@MainActor @Observable final class Palette {
    static let shared = Palette()
    private(set) var shades = Accent.copperShades
    @ObservationIgnored private var accent = Accent.copper

    private init() {
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Palette.shared.update() }
        }
    }

    func use(_ accent: Accent) {
        self.accent = accent
        update()
    }

    private func update() {
        let shades = accent.shades(system: RGBColor(NSColor.controlAccentColor))
        if shades != self.shades { self.shades = shades }
    }
}

extension Color {
    /// The accent's shades (Palette): light, main, and the deep end under white text.
    @MainActor static var accentLight: Color { Color(Palette.shared.shades.light) }
    @MainActor static var accent: Color { Color(Palette.shared.shades.main) }
    @MainActor static var accentDeep: Color { Color(Palette.shared.shades.deep) }
}

extension LinearGradient {
    /// The accent, side to bottom (the icon's copper, unless you chose another): the search field's edge, the welcome
    /// screen's title and button.
    @MainActor static var brand: LinearGradient { LinearGradient(colors: [.accent, .accentDeep], startPoint: .leading, endPoint: .trailing) }
}

/// The blur behind one piece of the panel. Its mask rounds the glass and, through the window's alpha, the
/// shadow; clipping the view instead left light corners.
private struct Glass: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.state = .active
        view.maskImage = .roundedMask(radius: radius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A piece of the panel's background: the blur, a veil over it (the blur alone mixes in gray: a cool near-white in
/// light mode, ink in dark), and a soft shadow under it.
struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let veil = scheme == .dark ? Color(red: 30 / 255, green: 32 / 255, blue: 38 / 255).opacity(0.6)
            : Color(red: 250 / 255, green: 251 / 255, blue: 253 / 255).opacity(0.8)
        content
            .background(veil, in: shape)
            .background(Glass(radius: radius))
            .background(SoftShadow(shape: shape, dark: scheme == .dark))
    }
}

/// A shadow around `shape`, drawn outside it only so nothing shows through the glass.
private struct SoftShadow<S: InsettableShape>: View {
    let shape: S
    let dark: Bool

    var body: some View {
        let reach = LauncherPanel.margin
        shape.inset(by: 1).fill(.black) // 1 pt in, so the mask's edge never shows a dark fringe
            .shadow(color: Color(red: 16 / 255, green: 24 / 255, blue: 40 / 255).opacity(dark ? 0.45 : 0.18), radius: 20, y: 12)
            .mask { Outside(shape: shape, reach: reach).fill(style: FillStyle(eoFill: true)).padding(-reach) }
    }
}

/// Everything within `reach` of `shape` but not in it (even-odd fill).
private struct Outside<S: Shape>: Shape {
    let shape: S
    let reach: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(shape.path(in: rect.insetBy(dx: reach, dy: reach)))
        return path
    }
}

/// Two floating pieces, like the icon: the search field as a pill, and the results in a card under it.
private struct LauncherView: View {
    static let rowHeight: CGFloat = 46
    private static let fieldHeight: CGFloat = 62, gap: CGFloat = 10, cardPadding: CGFloat = 8, cardRadius: CGFloat = 22
    private static let sectionHeight: CGFloat = 30
    /// The panel's max height minus the field, the gap between the pieces and the card's padding.
    private static let maxListHeight = LauncherPanel.maxHeight - fieldHeight - gap - 2 * cardPadding
    private static let previewWidth: CGFloat = 360
    private static let pictureSize: CGFloat = 232, bandHeight: CGFloat = 132, personWidth: CGFloat = 236

    @Bindable var model: SearchModel
    let placeholder: String
    @Environment(\.accessibilityReduceMotion) private var still
    @FocusState private var focused: Bool
    @State private var moreBeyond = ScrollEdges()
    /// The field's text, kept apart from `model.typed`: bound to it directly, the field ignored a change its own typing
    /// caused, so "translate " stayed in it beside the Translate chip it had become. Such a change is put back in the
    /// field a turn later, once the field is done with the keystroke.
    @State private var text = ""

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: 10) {
                if let mode = model.mode {
                    ModeChip(mode: mode).transition(still ? .opacity : .scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }
                TextField(model.mode?.hint ?? placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .focused($focused)
                    .onChange(of: text) {
                        guard text != model.typed else { return }
                        model.typed = text
                        if text != model.typed { Task { text = model.typed } } // a name became its chip: what follows it stays
                    }
                    .onChange(of: model.typed) { Task { if text != model.typed { text = model.typed } } } // Tab, Enter, a new show
            }
            // A chip sits as far in as it is round, so its curve follows the field's.
            .padding(.leading, model.mode == nil ? 26 : Self.fieldHeight / 2 - ModeChip.height / 2)
            .padding(.trailing, 26)
            .animation(still ? Motion.at(.easeOut(duration: 0.15)) : Motion.at(.spring(duration: 0.3, bounce: 0.25)), value: model.mode?.prefix)
            .frame(height: Self.fieldHeight)
                .modifier(GlassBackground(shape: Capsule(), radius: Self.fieldHeight / 2 - 0.5)) // a mask 2r + 1 tall: exactly the field
                .overlay(Capsule().strokeBorder(LinearGradient.brand, lineWidth: 1.5))
            if let selected = model.selected {
                Group {
                    switch model.answer {
                    case .picture(let image, let kicker, let title, let subtitle)?: // the picture, with its actions beside it
                        HStack(alignment: .top, spacing: 20) {
                            PictureTile(image: image).frame(width: Self.pictureSize, height: Self.pictureSize)
                            VStack(alignment: .leading, spacing: 0) {
                                AnswerHeading(kicker: kicker, title: title, subtitle: subtitle).padding(.horizontal, 12).padding(.top, 4)
                                Spacer(minLength: 12)
                                list.frame(height: listHeight)
                            }
                        }
                        .frame(height: Self.pictureSize)
                        .padding(14)
                    case .person(let card)?: // their card, with every way to reach them beside it
                        HStack(alignment: .top, spacing: 14) {
                            PersonTile(card: card).frame(width: Self.personWidth)
                            list.frame(height: min(Self.maxListHeight + 2 * Self.cardPadding - 28, listHeight))
                        }
                        .fixedSize(horizontal: false, vertical: true) // as tall as the taller: the card, or the rows
                        .padding(14)
                    case .stock(let card)?: StockCardView(card: card).padding(18) // the whole card: its one row is Enter
                    case .weather(let card)?: WeatherCardView(card: card).padding(18) // the whole card: its one row is Enter
                    case .week(let card)?: WeekCardView(card: card).padding(18) // the whole card: its one row is Enter
                    case .speed(let test, let tested, let running)?: SpeedCardView(test: test, tested: tested, running: running).padding(18)
                    case .entry(let entry)?: DictionaryCardView(entry: entry).padding(.horizontal, 22).padding(.vertical, 18)
                    case .calculation(let typed, let result, let note)?: // a band over its rows
                        VStack(spacing: 6) {
                            CalculationBand(typed: typed, result: result, note: note)
                            list.frame(height: min(Self.maxListHeight - Self.bandHeight - 6, listHeight))
                        }
                        .padding(Self.cardPadding)
                    case .currency(let card)?: // a band over its rows
                        VStack(spacing: 6) {
                            CurrencyBand(card: card)
                            list.frame(height: min(Self.maxListHeight - Self.bandHeight - 6, listHeight))
                        }
                        .padding(Self.cardPadding)
                    case .meeting(let card)?: // a band over its rows
                        VStack(spacing: 6) {
                            MeetingBand(card: card)
                            list.frame(height: min(Self.maxListHeight - 176 - 6, listHeight))
                        }
                        .padding(Self.cardPadding)
                    case .color(let color)?: // a band over its rows
                        VStack(spacing: 6) {
                            ColorBand(color: color).frame(height: Self.bandHeight)
                            list.frame(height: min(Self.maxListHeight - Self.bandHeight - 6, listHeight))
                        }
                        .padding(Self.cardPadding)
                    case nil:
                        // With the preview showing, the card takes its full height so the preview has room.
                        let hasPreview = model.showsPreview
                        HStack(spacing: Self.cardPadding) {
                            list
                            if hasPreview { PreviewPane(result: selected).frame(width: Self.previewWidth) }
                        }
                        .frame(height: hasPreview ? Self.maxListHeight : min(Self.maxListHeight, listHeight))
                        .padding(Self.cardPadding)
                    }
                }
                .modifier(Card(radius: Self.cardRadius))
                .transition(still ? .opacity : .reveal)
            }
        }
        .fixedSize(horizontal: false, vertical: true) // its natural height, at the top of the window
        // The card grows and shrinks to its rows instead of snapping; the rows themselves change at once (`list`).
        .animation(Motion.at(.smooth(duration: 0.2), still: still), value: CardShape(height: listHeight, preview: model.showsPreview, answer: model.answer != nil))
        .keyframeAnimator(initialValue: 1.0, trigger: model.opens) { content, scale in
            content.scaleEffect(scale, anchor: .top)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(Motion.opening(still: still))
                SpringKeyframe(1, duration: 0.3 / Motion.pace, spring: Spring(duration: 0.3 / Motion.pace, bounce: 0.15))
            }
        }
        .padding(LauncherPanel.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Only this view's own panel: hearing another one (the note, clipboard history) set `focused` while this
        // panel was hidden, and the next show's `focused = true` then changed nothing, leaving the field unfocused.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            if ($0.object as? LauncherPanel)?.model === model { focused = true }
        }
        // First show: the panel became key before this view existed to hear it, and focusing right away, before
        // the field is in the window, did nothing. A turn of the run loop later it takes.
        .onAppear { Task { focused = true } }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, result in
                        VStack(spacing: 0) {
                            if let section = sectionStarting(at: index) {
                                Text(section)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 6)
                                    .frame(maxWidth: .infinity, minHeight: Self.sectionHeight, alignment: .bottomLeading)
                            }
                            let selected = index == model.selection
                            ResultRow(result: result, selected: selected,
                                      offersPreview: selected && result.hasPreview && result.completion == nil && result.more == nil
                                          && result.actions == nil && !model.showsPreview)
                        }
                        .id(result.id)
                    }
                }
                .transaction { $0.animation = nil } // typing never waits on an animation: only the card and the wash move
                .background(alignment: .top) {
                    if model.selected != nil {
                        SelectionWash().frame(height: Self.rowHeight).offset(y: offset(of: model.selection))
                            .animation(Motion.at(.snappy(duration: 0.16), still: still), value: model.selection)
                    }
                }
            }
            // Rows fade out at an edge with more beyond it, instead of being cut.
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(top: geometry.contentOffset.y > 1,
                            bottom: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1)
            } action: { _, edges in
                withAnimation(Motion.at(.easeOut(duration: 0.15))) { moreBeyond = edges }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: moreBeyond.top ? 24 : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: moreBeyond.bottom ? 36 : 0)
                }
            }
            .onChange(of: model.selection) { old, index in
                // One row past the selection in the direction it moved, so the selected row never sits in the fade.
                let rows = model.rows, ahead = index + (index > old ? 1 : index < old ? -1 : 0)
                guard rows.indices.contains(index) else { return }
                // A row at a time glides, with the wash; a jump (a new search, back to the top) doesn't.
                withAnimation(abs(index - old) == 1 ? Motion.at(.snappy(duration: 0.16), still: still) : nil) { proxy.scrollTo(rows[min(max(ahead, 0), rows.count - 1)].id) }
            }
        }
    }

    /// The header above row `index`: its section, if the row before is in a different one.
    private func sectionStarting(at index: Int) -> String? {
        guard let section = model.rows[index].section, index == 0 || model.rows[index - 1].section != section else { return nil }
        return section
    }

    /// Where row `index` starts in the list, below the rows and headers before it (and its own header).
    private func offset(of index: Int) -> CGFloat {
        guard model.rows.indices.contains(index) else { return 0 }
        let headers = (0...index).filter { sectionStarting(at: $0) != nil }.count
        return CGFloat(index) * Self.rowHeight + CGFloat(headers) * Self.sectionHeight
    }

    private var listHeight: CGFloat {
        let headers = model.rows.indices.filter { sectionStarting(at: $0) != nil }.count
        return CGFloat(model.rows.count) * Self.rowHeight + CGFloat(headers) * Self.sectionHeight
    }
}

/// How fast the launcher moves: 1 in the app. Recording the README's animation slows it (0.05: twenty times slower), so
/// offscreen captures, slow as they are, catch every frame of it.
@MainActor enum Motion {
    static var pace = 1.0
    static func at(_ animation: Animation) -> Animation { animation.speed(pace) }
    /// With Reduce Motion on (`still`), things change in place: no glide, no spring.
    static func at(_ animation: Animation, still: Bool) -> Animation? { still ? nil : at(animation) }
    /// How big the launcher starts as it opens: a touch smaller, springing up; with Reduce Motion, its size (it fades).
    static func opening(still: Bool) -> CGFloat { still ? 1 : 0.96 }
}

extension AnyTransition {
    /// The card coming out of the field: shown from its top down as the panel grows, its shadow too, and folding back
    /// up into the field as it goes.
    static var reveal: AnyTransition { .modifier(active: Reveal(shown: 0), identity: Reveal(shown: 1)) }
}

private struct Reveal: ViewModifier {
    var shown: CGFloat

    func body(content: Content) -> some View {
        content.mask(alignment: .top) {
            // A soft lower edge, so it comes out of the field rather than being cut.
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
            }
            .padding(-LauncherPanel.margin).scaleEffect(x: 1, y: max(shown, 0.001), anchor: .top)
        }
    }
}

/// What the card's size follows: a change animates it.
private struct CardShape: Equatable {
    var height: CGFloat, preview: Bool, answer: Bool
}

/// Whether the list has rows hidden above or below what's in view.
private struct ScrollEdges: Equatable {
    var top = false, bottom = false
}

/// A card on the glass (the results, the note), with light catching its top edge and fading out down the sides.
struct Card: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: radius), radius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.14 : 0.9), .white.opacity(0)],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)), lineWidth: 1)
                .allowsHitTesting(false)
            }
    }
}

/// The icon's C, in its copper whatever the accent (it's the icon), in the note's title and on the welcome screen.
struct BrandMark: View {
    var height: CGFloat = 24

    var body: some View {
        let copper = Accent.copperShades
        Image("Mark").renderingMode(.template).resizable().scaledToFit().frame(height: height)
            .foregroundStyle(LinearGradient(colors: [Color(copper.light), Color(copper.main)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// A key to press, drawn as a small keycap: the selected row's ↵, the note's esc.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accent.opacity(0.25), lineWidth: 0.5))
    }
}

/// Title and subtitle; on the right, an item's age (clipboard). The selected row says what Enter does, in place of
/// the age (its wash is the list's, `SelectionWash`).
private struct ResultRow: View {
    let result: LauncherResult
    let selected: Bool
    var offersPreview = false // "Preview ⇥": Tab opens the pane beside the list
    @Environment(\.colorScheme) private var scheme // the badge's shade: a deep one doesn't read on dark in every accent

    var body: some View {
        HStack(spacing: 13) {
            IconView(icon: result.icon, size: 26)
            Text(result.title).font(.system(size: 14.5)).lineLimit(1).layoutPriority(1)
            if let pill {
                ViewThatFits(in: .horizontal) { // the title comes first: with the preview open, the badge steps aside
                    pill.font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(scheme == .dark ? Color.accentLight : Color.accentDeep)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.accent.opacity(0.18), in: Capsule())
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            if !result.subtitle.isEmpty {
                ViewThatFits(in: .horizontal) { // whole or not at all: cut to a letter or two, it said nothing
                    Text(result.subtitle).font(.system(size: 13)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            Spacer(minLength: 8)
            if selected, !result.actionTitle.isEmpty || offersPreview || result.more != nil || result.actions != nil {
                HStack(spacing: 7) {
                    if let tab = offersPreview ? "Preview" : result.more?.label ?? (result.actions != nil && result.completion == nil ? "Actions" : nil) {
                        Text(tab).font(.system(size: 12)).foregroundStyle(.secondary)
                        Keycap(label: "tab").padding(.trailing, 6)
                    }
                    if !result.actionTitle.isEmpty {
                        Text(result.actionTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        Keycap(label: result.key)
                    }
                }
                .fixedSize()
            } else if !result.accessory.isEmpty {
                Text(result.accessory).font(.system(size: 12).monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                    .padding(.trailing, 18 + 7) // ends where the selected row's action does, before its ↵ key
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LauncherView.rowHeight)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The badge, or the clock: SwiftUI's timer text updates itself, so the row needs no refresh to tick.
    private var pill: Text? {
        switch result.ticking {
        case .down(let end): Text(timerInterval: Date.now...max(end, .now), countsDown: true)
        case .up(let start): Text(timerInterval: start...Date.distantFuture, countsDown: false)
        case nil: result.badge.map { Text(verbatim: $0) }
        }
    }
}

/// The selected row's wash in the icon's colors, under the rows: one for the list, so it glides from row to row.
private struct SelectionWash: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [.accent.opacity(dark ? 0.24 : 0.13), .accentDeep.opacity(dark ? 0.15 : 0.10)],
                                 startPoint: .leading, endPoint: .trailing))
            .strokeBorder(Color.accent.opacity(dark ? 0.35 : 0.22), lineWidth: 0.5)
    }
}

enum Ticking: Equatable, Sendable { case down(to: Date), up(from: Date) }

/// A mode's name at the start of the field (`translate ` → Translate), in the selected row's accent.
private struct ModeChip: View {
    static let height: CGFloat = 34
    let mode: Mode
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 7) {
            switch mode.icon {
            case .symbol(let name): Image(systemName: name).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            default: IconView(icon: mode.icon, size: 18)
            }
            Text(mode.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: Self.height)
        .background {
            Capsule()
                .fill(LinearGradient(colors: [.accent.opacity(dark ? 0.24 : 0.13), .accentDeep.opacity(dark ? 0.15 : 0.10)],
                                     startPoint: .leading, endPoint: .trailing))
                .strokeBorder(Color.accent.opacity(dark ? 0.35 : 0.22), lineWidth: 0.5)
        }
        .fixedSize()
        .accessibilityLabel(mode.title)
    }
}

private struct IconView: View {
    let icon: LauncherResult.Icon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .file(let path):
            // Finder icons have a transparent margin; drawn a bit bigger they match the glyph rings.
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                .frame(width: size * 1.15, height: size * 1.15).frame(width: size, height: size)
        case .symbol(let name):
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .overlay { Image(systemName: name).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.secondary) }
                .frame(width: size, height: size)
        case .asset(let name): // a logo from Assets, in the same ring as the glyphs
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .overlay { Image(name).resizable().scaledToFit().clipShape(.rect(cornerRadius: size * 0.12)).frame(width: size * 0.56) }
                .frame(width: size, height: size)
        case .image(let key, let load):
            Thumbnail(key: key, load: load).frame(width: size, height: size)
        case .color(let color): // the swatch in the same ring, with an edge of its own for white on white
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .overlay {
                    Circle().fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                        .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                        .padding(size * 0.2)
                }
                .frame(width: size, height: size)
        }
    }
}

/// A row's picture, loaded off the main thread once per key and kept for the next show.
private struct Thumbnail: View {
    @MainActor private static let cache = NSCache<NSString, CGImage>()
    let key: String
    let load: @Sendable () -> CGImage?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFit().clipShape(.rect(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
            }
        }
        .task(id: key) {
            image = Self.cache.object(forKey: key as NSString)
            guard image == nil, let loaded = await Task.detached(operation: load).value else { return }
            Self.cache.setObject(loaded, forKey: key as NSString)
            image = loaded
        }
    }
}

/// The selected row's full text, and its details under it, on a tinted panel of its own.
private struct PreviewPane: View {
    let result: LauncherResult
    @State private var image: NSImage?
    @State private var loaded: (id: String, text: String)?

    var body: some View {
        VStack(spacing: 0) {
            if result.previewImage != nil {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFit() } else { Color.clear }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: result.id) {
                    image = nil
                    image = result.previewImage?()
                }
            } else {
                let text = result.preview ?? loaded.flatMap { $0.id == result.id ? $0.text : nil }
                    ?? (result.loadPreview == nil ? "" : "Loading…")
                ScrollView {
                    let prose = result.previewStyle == .prose
                    Text(text)
                        .font(prose ? .system(size: 13) : .system(size: 12, design: .monospaced))
                        .lineSpacing(prose ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                .id(result.id) // back to the top for each item
                .task(id: result.id) {
                    guard result.preview == nil, let load = result.loadPreview else { return }
                    let text = await load()
                    if !Task.isCancelled { loaded = (result.id, text) }
                }
            }
            if !result.details.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(result.details.enumerated()), id: \.offset) { _, detail in
                        HStack {
                            Text(detail.0).foregroundStyle(.tertiary)
                            Spacer()
                            Text(detail.1).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }
}


