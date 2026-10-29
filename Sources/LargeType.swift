import AppKit
import SwiftUI

/// `large 555-0100`: the text across the screen, as big as it fits, to show someone across the desk; `large` alone
/// shows what you copied. Any key, a click or switching apps puts it away.
struct LargeTypeProvider: ResultProvider {
    private static let icon = LauncherResult.Icon.symbol("textformat.size")
    private let clipboard: @Sendable () async -> String?
    var modes: [Mode] { [Mode(prefix: "large ", title: "Large Type", icon: Self.icon, hint: "Text, or nothing for what you copied")] }

    init(clipboard: @escaping @Sendable () async -> String? = { @MainActor in Clip.current(withHTML: false).text }) {
        self.clipboard = clipboard
    }

    func results(for query: String) async -> [LauncherResult] {
        if let start = startRow(query, keyword: "large", title: "Large Type", hint: "Type text to show it big: large 555-0100",
                                symbol: "textformat.size") {
            return [start]
        }
        return query.lowercased().hasPrefix("large ") ? await modeResults(for: query) : []
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        let typed = query.dropFirst(5).trimmingCharacters(in: .whitespaces)
        let text = typed.isEmpty ? await clipboard()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : typed
        guard !text.isEmpty else {
            return [LauncherResult(id: "large", title: "Type the text to show", subtitle: "Or copy some first", icon: Self.icon, score: 50,
                                   actionTitle: "", action: {})]
        }
        return [LauncherResult(id: "large", title: oneLine(text), subtitle: "Large Type" + (typed.isEmpty ? " · from the clipboard" : ""),
                               icon: Self.icon, score: 50, actionTitle: "Show", action: { showLargeType(text) })]
    }
}

@MainActor private var largeType: LargeTypeWindow?

/// On the screen the pointer is on.
@MainActor func showLargeType(_ text: String) {
    largeType?.close()
    largeType = LargeTypeWindow(text: text, screen: NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
    largeType?.makeKeyAndOrderFront(nil)
}

/// The whole screen, clear but for the text on a dark card in the middle. Like the launcher it never takes focus
/// from the app you were in, but it gets the keys: any of them closes it.
final class LargeTypeWindow: NSPanel {
    init(text: String, screen: NSScreen? = NSScreen.main) {
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Inside a plain view, as the launcher does: as the content view, NSHostingView would size the window to fit.
        let host = NSHostingView(rootView: LargeTypeView(text: text))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        host.frame = container.bounds
        container.addSubview(host)
        contentView = container
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { close() }
    override func mouseDown(with event: NSEvent) { close() }
    override func resignKey() {
        super.resignKey()
        close()
    }
}

private struct LargeTypeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 320, weight: .semibold, design: .rounded)).minimumScaleFactor(0.02)
            .lineLimit(text.count <= 24 ? 1 : nil) // a number or a code on one line, smaller, rather than broken
            .multilineTextAlignment(.center).foregroundStyle(.white)
            .padding(.horizontal, 64).padding(.vertical, 40)
            .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(.black.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).strokeBorder(Color.copper.opacity(0.45), lineWidth: 1.5))
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
