import AppKit
import SwiftUI

/// Named notes (`note work`), one text file each.
let notesDir = configDir.appending(path: "notes")

/// The names of the notes in `folder` (work.txt → "work"), A–Z.
func noteNames(in folder: URL = notesDir) -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    return files.filter { $0.pathExtension == "txt" }.map { $0.deletingPathExtension().lastPathComponent }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// A floating note: plain text on a glass card like the launcher's, autosaved to note.txt, or to notes/<name>.txt
/// for a named one. It's a non-activating panel, so typing in it never pulls the app you were in out of the
/// foreground, and hiding it hands keyboard focus straight back to that app. Drag it by its title; resize it from
/// its bottom-right corner.
final class NotePanel: NSPanel, NSTextViewDelegate, NSWindowDelegate {
    private static let stateSection = "windows" // [window name: frame of the card]
    static let minSize = CGSize(width: 240, height: 140)
    /// Clear room around the card for its shadow, as in the launcher.
    static let margin = LauncherPanel.margin

    let file: URL
    private let frameKey: String // "note", "note:work"
    private let textView: NSTextView
    private var pendingSave: Task<Void, Never>?

    /// `name`: nil for the note, else a named one.
    init(name: String? = nil) {
        file = name.map { notesDir.appending(path: $0 + ".txt") } ?? configDir.appending(path: "note.txt")
        frameKey = name.map { "note:" + $0 } ?? "note"
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
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
        let lines = NSMutableParagraphStyle()
        lines.lineSpacing = 3
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor, .paragraphStyle: lines]
        textView.insertionPointColor = NSColor(Color.copper)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Color.copper).withAlphaComponent(0.22)]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        textView.delegate = self

        // As the launcher: a plain view holds the hosting view, which never sizes the window itself.
        let host = NSHostingView(rootView: NoteView(title: name ?? "Note", text: scroll))
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
        set { textView.textStorage?.setAttributedString(NSAttributedString(string: newValue, attributes: textView.typingAttributes)) }
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
    let title: String
    let text: NSView

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(height: 16)
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
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
