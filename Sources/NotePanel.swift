import AppKit
import SwiftUI

/// The notes: note.txt, and a text file each in notes/. They have no names: a note's first line is its title.
let notesDir = configDir.appending(path: "notes")
let mainNoteFile = configDir.appending(path: "note.txt")

/// Every note that exists: note.txt and the .txt files in `folder` (hidden ones aren't notes).
func noteFiles(in folder: URL = notesDir, main: URL = mainNoteFile) -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    return ([main] + files.filter { $0.pathExtension == "txt" }).filter { FileManager.default.fileExists(atPath: $0.path) }
}

/// A note's title: its first line with text, without a heading's `#`s. nil for an empty note.
func noteTitle(_ text: String) -> String? {
    text.split(separator: "\n").lazy
        .map { $0.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
        .first { !$0.isEmpty }.map { String($0.prefix(80)) }
}

/// Where a new note goes: notes/, named by the time (nobody sees it). The file is written once you type.
func newNoteFile(in folder: URL = notesDir, now: Date = .now) -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let stamp = formatter.string(from: now)
    var file = folder.appending(path: stamp + ".txt"), number = 2
    while FileManager.default.fileExists(atPath: file.path) {
        file = folder.appending(path: "\(stamp)-\(number).txt")
        number += 1
    }
    return file
}

/// A note as the launcher lists it.
struct NoteFile: Sendable {
    var url: URL
    var text: String
    var edited: Date
    var title: String { noteTitle(text) ?? "Empty Note" }
    /// The line after the title, for its row.
    var summary: String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.dropFirst().first
            .map { String($0.prefix(80)) } ?? ""
    }
}

/// Every note, last edited first.
func notesByDate(in folder: URL = notesDir, main: URL = mainNoteFile) -> [NoteFile] {
    noteFiles(in: folder, main: main).map { url in
        NoteFile(url: url, text: (try? String(contentsOf: url, encoding: .utf8)) ?? "",
                 edited: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
    }.sorted { $0.edited > $1.edited }
}

/// The first line with `query`'s first word, if the text has every word in it (in any case, accents or not); nil if not.
func matchingLine(_ text: String, _ query: String) -> String? {
    let words = query.split(separator: " ").map(String.init)
    guard let first = words.first, words.allSatisfy({ text.localizedStandardContains($0) }) else { return nil }
    return text.split(separator: "\n").first { $0.localizedStandardContains(first) }.map { String($0.trimmingCharacters(in: .whitespaces).prefix(80)) }
}

extension Verb {
    /// `:delete note milk`: a note, found by its title or what's in it, moved to the Trash after asking. `release` closes
    /// its panel first, saved.
    @MainActor static func notes(folder: URL = notesDir, main: URL = mainNoteFile,
                                 release: @escaping @MainActor @Sendable (URL) -> Void) -> [Verb] {
        [Verb(keyword: "delete note", title: "Delete Note", icon: .symbol("trash"), targets: { filter in
            notesByDate(in: folder, main: main).enumerated().compactMap { index, note in
                let match = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, note.title) ?? matchingLine(note.text, filter).map { _ in 0.5 }
                guard let score = match else { return nil }
                let url = note.url
                return LauncherResult(id: "delete note:\(url.path)", title: "Delete Note: \(note.title)", subtitle: note.summary,
                                      icon: .symbol("trash"), score: score, actionTitle: "Delete",
                                      action: { release(url); moveToTrash(url.path) }, confirm: "Move the note “\(note.title)” to the Trash?")
            }
        })].belonging(to: .notes)
    }
}

/// The title the note's card shows: its first line, as you type it.
@MainActor @Observable final class NoteHeader {
    var title = ""
}

/// A floating note: plain text on a glass card like the launcher's, autosaved to its file (note.txt, or one in notes/). It's a non-activating panel, so typing in it never pulls the app you were in out of the
/// foreground, and hiding it hands keyboard focus straight back to that app. Drag it by its title; resize it from
/// its bottom-right corner.
final class NotePanel: NSPanel, NSTextViewDelegate, NSWindowDelegate {
    private static let stateSection = "windows" // [window name: frame of the card]
    static let minSize = CGSize(width: 240, height: 140)
    /// Clear room around the card for its shadow, as in the launcher.
    static let margin = LauncherPanel.margin

    /// `[notes] markdown`: draw the Markdown in notes (headings, bold, checkboxes…), or show plain text.
    static var stylesMarkdown = true

    let file: URL
    private let frameKey: String // "note", "note:work"
    private let textView: NSTextView
    private let base: [NSAttributedString.Key: Any] // the note's font, color and spacing
    private let header = NoteHeader()
    private var pendingSave: Task<Void, Never>?

    /// `file`: note.txt, a note in notes/, or a new one there, written once you type.
    init(file: URL) {
        self.file = file
        frameKey = file == mainNoteFile ? "note" : "note:" + file.deletingPathExtension().lastPathComponent
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        let lines = NSMutableParagraphStyle()
        lines.lineSpacing = 3
        base = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: lines]
        let card = NSRect(x: 0, y: 0, width: 360, height: 300)
        super.init(contentRect: card.insetBy(dx: -Self.margin, dy: -Self.margin),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the card draws a soft one; the window's traced it with a gray rim

        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        textView.drawsBackground = false
        textView.isRichText = false
        textView.typingAttributes = base
        textView.linkTextAttributes = [.foregroundColor: NSColor(Color.copper), .cursor: NSCursor.pointingHand] // underlined below, checkboxes not
        textView.insertionPointColor = NSColor(Color.copper)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Color.copper).withAlphaComponent(0.22)]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) // ready to go on writing
        textView.delegate = self

        // As the launcher: a plain view holds the hosting view, which never sizes the window itself.
        let host = NSHostingView(rootView: NoteView(header: header, text: scroll))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.addSubview(host)
        host.frame = container.bounds
        contentView = container

        // Restore the saved card unless a display change left it off every screen.
        if let saved = StateStore.shared.get(Self.stateSection, as: [String: CGRect].self)?[frameKey],
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved) }) {
            setFrame(saved.insetBy(dx: -Self.margin, dy: -Self.margin), display: false)
        } else {
            center()
        }
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { true } // borderless windows can't by default

    /// AppKit keeps a window's top below the menu bar, and this window's top is the clear margin: the card stopped
    /// 60 pt short. The same rule, applied to the card.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        super.constrainFrameRect(frameRect.insetBy(dx: Self.margin, dy: Self.margin), to: screen).insetBy(dx: -Self.margin, dy: -Self.margin)
    }

    func show() {
        reloadIfChanged() // a named note's folder isn't watched: edits made elsewhere show from here
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textView)
    }

    /// The note's text, set in the note's own font and spacing.
    private var text: String {
        get { textView.string }
        set {
            textView.textStorage?.setAttributedString(NSAttributedString(string: newValue, attributes: base))
            restyle()
        }
    }

    /// Draws the note's Markdown, or plain text (`stylesMarkdown`). Only how it looks: the text never changes.
    /// ponytail: the whole note, each keystroke; restyle only the edited paragraphs if long notes ever lag.
    func restyle() {
        header.title = noteTitle(text) ?? "New Note"
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        if Self.stylesMarkdown {
            // Headings set the size, after the inline styles; markers only dim, so they go last.
            let order = { (style: MarkdownStyle) in style == .marker ? 2 : { if case .heading = style { 1 } else { 0 } }() }
            for span in markdownSpans(storage.string).sorted(by: { order($0.style) < order($1.style) }) {
                storage.addAttributes(attributes(span.style, at: span.range), range: span.range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = base
    }

    private func attributes(_ style: MarkdownStyle, at range: NSRange) -> [NSAttributedString.Key: Any] {
        let copper = NSColor(Color.copper)
        switch style {
        case .heading(let level): return [.font: NSFont.systemFont(ofSize: [20, 17, 15][min(max(level, 1), 3) - 1], weight: level < 3 ? .bold : .semibold)]
        case .bold: return [.font: NSFont.systemFont(ofSize: 14, weight: .bold)]
        case .italic: return [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)]
        case .code: return [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07)]
        case .marker: return [.foregroundColor: NSColor.tertiaryLabelColor]
        case .bullet: return [.foregroundColor: copper]
        case .checkbox: return [.foregroundColor: copper, .link: URL(string: "\(checkboxScheme):\(range.location)")!]
        case .done: return [.foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .quote: return [.foregroundColor: NSColor.secondaryLabelColor]
        case .link(let url): return URL(string: url).map { [.link: $0, .underlineStyle: NSUnderlineStyle.single.rawValue] } ?? [:]
        }
    }

    /// A click on a checkbox ticks it (undoable, saved like typing); on a link, the browser opens it.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard (link as? URL)?.scheme == checkboxScheme, let storage = textView.textStorage,
              let toggle = checkboxToggle(storage.string as NSString, at: charIndex)
        else { return false }
        if textView.shouldChangeText(in: toggle.range, replacementString: toggle.replacement) {
            storage.replaceCharacters(in: toggle.range, with: toggle.replacement)
            textView.didChangeText()
        }
        return true
    }

    // Covers Esc.
    override func close() {
        saveNow()
        orderOut(nil)
    }

    /// Writes unsaved edits now. Called on hide and on quit; typing saves after a 500 ms pause.
    func saveNow() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        write()
    }

    /// Adds `line` at the end of the note, on a line of its own, and saves (`add note …`).
    func append(_ line: String) {
        text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + line + "\n"
        undoManager?.removeAllActions() // undo steps point into the text as it was
        write()
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            notify("Couldn't save the note", error.localizedDescription) // the text stays in the panel
        }
    }

    /// Picks up edits made to the file elsewhere, unless the note is being edited here.
    func reloadIfChanged() {
        guard !isKeyWindow, pendingSave == nil,
              let saved = try? String(contentsOf: file, encoding: .utf8), saved != text
        else { return }
        text = saved
        undoManager?.removeAllActions() // old undo steps point into text that's gone
    }

    func textDidChange(_ notification: Notification) {
        restyle()
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { saveNow() }
        }
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        var frames = StateStore.shared.get(Self.stateSection, as: [String: CGRect].self) ?? [:]
        frames[frameKey] = frame.insetBy(dx: Self.margin, dy: Self.margin)
        StateStore.shared.set(Self.stateSection, frames)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 { return close() } // Esc
        if performEditShortcut(event) { return }
        super.sendEvent(event)
    }
}

/// The note's card: its title (drag it there) over the text, a corner to resize it by.
private struct NoteView: View {
    let header: NoteHeader
    let text: NSView

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(height: 16)
                Text(header.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Keycap(label: "esc").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .overlay(WindowGrip(resizes: false))
            Hosted(view: text).padding(.leading, 13).padding(.trailing, 6).padding(.bottom, 12)
        }
        .modifier(Card(radius: 22))
        .overlay(alignment: .bottomTrailing) { WindowGrip(resizes: true).frame(width: 18, height: 18) }
        .padding(NotePanel.margin)
    }
}

private struct Hosted: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Dragging it moves the window, or resizes it from the bottom-right corner, keeping the top left in place.
private struct WindowGrip: NSViewRepresentable {
    let resizes: Bool

    final class Grip: NSView {
        var resizes = false
        private var start: (mouse: NSPoint, frame: NSRect)?

        // The first click drags, even with another app in front; without this it only brought the note forward.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (window.convertPoint(toScreen: event.locationInWindow), window.frame) // where it was pressed, not where it is now
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let mouse = NSEvent.mouseLocation
            if !resizes {
                // Moved here, not by performDrag: the window server stops a dragged window's top at the menu bar, and
                // this window's top is the clear margin. setFrameOrigin goes through constrainFrameRect, which knows.
                return window.setFrameOrigin(NSPoint(x: start.frame.minX + mouse.x - start.mouse.x, y: start.frame.minY + mouse.y - start.mouse.y))
            }
            let margin = 2 * NotePanel.margin
            let width = max(NotePanel.minSize.width + margin, start.frame.width + mouse.x - start.mouse.x)
            let height = max(NotePanel.minSize.height + margin, start.frame.height - (mouse.y - start.mouse.y))
            window.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
        }

        override func mouseUp(with event: NSEvent) { start = nil }

        override func resetCursorRects() {
            if resizes { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) }
        }
    }

    func makeNSView(context: Context) -> Grip {
        let grip = Grip()
        grip.resizes = resizes
        return grip
    }

    func updateNSView(_ grip: Grip, context: Context) {}
}
