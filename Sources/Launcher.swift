import AppKit
import SwiftUI

protocol ResultProvider: Sendable {
    func results(for query: String) async -> [LauncherResult]
}

typealias OutputStep = @Sendable (_ progress: @escaping @Sendable (LauncherResult) async -> Void) async -> LauncherResult

/// How the preview pane sets its text: code and output monospaced, prose (a definition, a translation, a snippet)
/// in the text font.
enum PreviewStyle: Sendable { case code, prose }

struct LauncherResult: Identifiable, Sendable {
    /// A file's Finder icon (apps), an SF Symbol in a ring, or a picture
    /// loaded off the main thread (clipboard images; the string keys its cache).
    enum Icon: Sendable { case file(String), symbol(String), image(String, @Sendable () -> CGImage?) }

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
    /// Enter puts this in the search field instead of running anything (`:quit` → ":quit ", to pick an app).
    var completion: String? = nil
    /// Enter runs it, drops the row and keeps the panel open, so several can go in a row (`:delete`).
    var staysOpen = false
    /// Ask first: Enter shows a row with this question, and Enter on that row runs `action`.
    var confirm: String? = nil
    /// Rows get a header where this changes (clipboard: Today, Yesterday, Earlier).
    var section: String? = nil
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

@MainActor @Observable
final class SearchModel {
    var query = "" { didSet { search() } }
    /// Pinned above the results, whatever the query, until cleared (e.g. a config error).
    var notice: LauncherResult?
    /// A confirmation question that replaces the list until answered (Enter) or dismissed (Esc, typing).
    var confirming: LauncherResult? { didSet { selection = 0 } }
    private(set) var results: [LauncherResult] = []
    private(set) var selection = 0
    @ObservationIgnored private let providers: [any ResultProvider]
    @ObservationIgnored private let searchesEmptyQuery: Bool
    @ObservationIgnored private let exclusive: [String: any ResultProvider]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// A round has started and its rows aren't shown yet: the list still shows the previous query's.
    @ObservationIgnored private(set) var settling = false
    /// A row's output step while it runs (a shell line): Esc cancels it, which stops the process.
    @ObservationIgnored var run: Task<Void, Never>?
    @ObservationIgnored private let state: StateStore?
    @ObservationIgnored private var frecency: Frecency.Table

    /// `searchesEmptyQuery`: ask providers about "" too (the clipboard lists everything), instead of showing nothing.
    /// `exclusive`: a query starting with one of these prefixes ("f ") goes to that provider alone.
    /// `frecency`: rows picked often rise, counted in this store (the launcher; clipboard history keeps its order).
    init(providers: [any ResultProvider], searchesEmptyQuery: Bool = false, exclusive: [String: any ResultProvider] = [:],
         frecency state: StateStore? = nil) {
        self.providers = providers
        self.searchesEmptyQuery = searchesEmptyQuery
        self.exclusive = exclusive
        self.state = state
        frecency = state?.get(Frecency.stateSection, as: Frecency.Table.self) ?? [:]
    }

    /// Enter on a row: count it, so it ranks higher next time.
    func picked(_ id: String) {
        guard let state else { return }
        frecency = Frecency.picking(id, in: frecency, at: .now)
        state.set(Frecency.stateSection, frecency)
    }

    var rows: [LauncherResult] { confirming.map { [$0] } ?? ((notice.map { [$0] } ?? []) + results) }
    var selected: LauncherResult? { rows.indices.contains(selection) ? rows[selection] : nil }

    func move(_ delta: Int) {
        selection = max(0, min(rows.count - 1, selection + delta))
    }

    func remove(_ id: String) {
        results.removeAll { $0.id == id }
        selection = max(0, min(rows.count - 1, selection))
    }

    /// Every provider runs concurrently, and the rows are shown together once all have answered or `wait` has
    /// passed with something to show; the previous query's rows stay until then. Showing each provider's rows as
    /// it answered emptied the list on every keystroke (the quick ones with nothing to say came first) and regrew
    /// it over 300 ms. Whatever answers after the wait merges in when it does: files (after their own 150 ms) and
    /// the other slow ones rank at the bottom, so the rows above don't move. A new keystroke cancels the round.
    private func search() {
        task?.cancel()
        confirming = nil
        selection = 0
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || searchesEmptyQuery else { results = []; settling = false; return }
        // The longest prefix wins: ":!" (shell) over ":" (commands).
        let providers = exclusive.filter { query.hasPrefix($0.key) }.max { $0.key.count < $1.key.count }.map { [$0.value] } ?? providers
        let (frecency, now) = (frecency, Date.now)
        settling = true
        task = Task {
            await withTaskGroup(of: [LauncherResult]?.self) { group in
                for provider in providers {
                    group.addTask { await provider.results(for: query) }
                }
                // ponytail: one fixed wait, under what reads as instant; per-provider deadlines if one ever needs more.
                group.addTask { try? await Task.sleep(for: Self.wait); return nil } // nil: the wait is over
                var merged: [LauncherResult] = []
                var (pending, waiting) = (providers.count, true)
                for await batch in group {
                    guard !Task.isCancelled else { return }
                    if let batch {
                        pending -= 1
                        let boosted = batch.map { var row = $0; row.score += Frecency.bonus(frecency, row.id, at: now); return row }
                        merged = (merged + boosted).sorted { $0.score > $1.score }
                    } else {
                        waiting = false
                    }
                    // Nothing yet when the wait is over: keep the previous rows rather than an empty list.
                    guard pending == 0 || (!waiting && !merged.isEmpty) else { continue }
                    // A [[command]] or script named like a built-in replaces it: "command:screenshot" hides "builtin:screenshot".
                    let replaced = Set(merged.compactMap { row in
                        ["command:", "script:"].first { row.id.hasPrefix($0) }.map { "builtin:" + row.id.dropFirst($0.count).lowercased() }
                    })
                    results = merged.filter { !replaced.contains($0.id) }
                    selection = min(selection, max(0, rows.count - 1))
                    settling = false
                    if pending == 0 { return group.cancelAll() } // ends the wait early
                }
            }
        }
    }

    static let wait = Duration.milliseconds(50)
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

    func show() {
        model.query = ""
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            // Top edge where a full-height panel centered on the screen would have it.
            let area = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: area.midX - frame.width / 2, y: area.midY + Self.maxHeight / 2 + Self.margin))
        }
        makeKeyAndOrderFront(nil)
    }

    // Focus loss hides the panel.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { return super.sendEvent(event) }
        switch event.keyCode {
        case 53: // Esc: stop what's running and back out of it (or of a question), else hide
            guard model.confirming != nil else { return orderOut(nil) }
            model.run?.cancel()
            model.confirming = nil
        case 125: model.move(1) // ↓
        case 126: model.move(-1) // ↑
        case 36, 76: // Return, keypad Enter. Every action has its own row, so modifiers change nothing.
            // Typed and pressed Enter before the rows were in: wait for them (at most SearchModel.wait), so Enter
            // runs what this query finds, not the previous query's top row.
            if model.settling {
                return DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.sendEvent(event) }
            }
            guard let result = model.selected else { return }
            if result.confirm == nil { model.picked(result.id) } // a question counts once answered
            if let completion = result.completion { return model.query = completion }
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

extension Color {
    /// The icon's C, top to side to bottom: its light copper, the main accent, and the deep end under white text.
    static let copperLight = Color(red: 254 / 255, green: 186 / 255, blue: 122 / 255)
    static let copper = Color(red: 222 / 255, green: 151 / 255, blue: 96 / 255)
    static let copperDeep = Color(red: 179 / 255, green: 110 / 255, blue: 66 / 255)
}

extension LinearGradient {
    /// The icon's copper, side to bottom: the search field's edge, the welcome screen's title and button.
    static var brand: LinearGradient { LinearGradient(colors: [.copper, .copperDeep], startPoint: .leading, endPoint: .trailing) }
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

    @Bindable var model: SearchModel
    let placeholder: String
    @FocusState private var focused: Bool
    @State private var moreBeyond = ScrollEdges()

    var body: some View {
        VStack(spacing: Self.gap) {
            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 21))
                .focused($focused)
                .padding(.horizontal, 26)
                .frame(height: Self.fieldHeight)
                .modifier(GlassBackground(shape: Capsule(), radius: Self.fieldHeight / 2 - 0.5)) // a mask 2r + 1 tall: exactly the field
                .overlay(Capsule().strokeBorder(LinearGradient.brand, lineWidth: 1.5))
            if let selected = model.selected {
                // A list with previews (clipboard) keeps its full height so the preview has room.
                let hasPreview = model.rows.contains { $0.preview != nil || $0.loadPreview != nil }
                HStack(spacing: Self.cardPadding) {
                    list
                    if hasPreview { PreviewPane(result: selected).frame(width: Self.previewWidth) }
                }
                .frame(height: hasPreview ? Self.maxListHeight : min(Self.maxListHeight, listHeight))
                .padding(Self.cardPadding)
                .modifier(Card(radius: Self.cardRadius))
            }
        }
        .fixedSize(horizontal: false, vertical: true) // its natural height, at the top of the window
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
                            ResultRow(result: result, selected: index == model.selection)
                        }
                        .id(result.id)
                    }
                }
            }
            // Rows fade out at an edge with more beyond it, instead of being cut.
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(top: geometry.contentOffset.y > 1,
                            bottom: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1)
            } action: { _, edges in
                withAnimation(.easeOut(duration: 0.15)) { moreBeyond = edges }
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
                if rows.indices.contains(index) { proxy.scrollTo(rows[min(max(ahead, 0), rows.count - 1)].id) }
            }
        }
    }

    /// The header above row `index`: its section, if the row before is in a different one.
    private func sectionStarting(at index: Int) -> String? {
        guard let section = model.rows[index].section, index == 0 || model.rows[index - 1].section != section else { return nil }
        return section
    }

    private var listHeight: CGFloat {
        let headers = model.rows.indices.filter { sectionStarting(at: $0) != nil }.count
        return CGFloat(model.rows.count) * Self.rowHeight + CGFloat(headers) * Self.sectionHeight
    }
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

/// The icon's C, in its copper, in the note's title and on the welcome screen.
struct BrandMark: View {
    var height: CGFloat = 24

    var body: some View {
        Image("Mark").renderingMode(.template).resizable().scaledToFit().frame(height: height)
            .foregroundStyle(LinearGradient(colors: [.copperLight, .copper], startPoint: .topLeading, endPoint: .bottomTrailing))
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
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.copper.opacity(0.25), lineWidth: 0.5))
    }
}

/// Title and subtitle; on the right, an item's age (clipboard). The selected row is washed in the icon's
/// colors and says what Enter does, in place of the age.
private struct ResultRow: View {
    let result: LauncherResult
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 13) {
            IconView(icon: result.icon, size: 26)
            Text(result.title).font(.system(size: 14.5)).lineLimit(1).layoutPriority(1)
            if !result.subtitle.isEmpty {
                ViewThatFits(in: .horizontal) { // whole or not at all: cut to a letter or two, it said nothing
                    Text(result.subtitle).font(.system(size: 13)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            Spacer(minLength: 8)
            if selected, !result.actionTitle.isEmpty {
                HStack(spacing: 7) {
                    Text(result.actionTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    Keycap(label: "↵")
                }
                .fixedSize()
            } else if !result.accessory.isEmpty {
                Text(result.accessory).font(.system(size: 12).monospacedDigit()).foregroundStyle(.tertiary).fixedSize()
                    .padding(.trailing, 18 + 7) // ends where the selected row's action does, before its ↵ key
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LauncherView.rowHeight)
        .background {
            if selected {
                let dark = scheme == .dark
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.copper.opacity(dark ? 0.24 : 0.13), .copperDeep.opacity(dark ? 0.15 : 0.10)],
                                         startPoint: .leading, endPoint: .trailing))
                    .strokeBorder(Color.copper.opacity(dark ? 0.35 : 0.22), lineWidth: 0.5)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        case .image(let key, let load):
            Thumbnail(key: key, load: load).frame(width: size, height: size)
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

