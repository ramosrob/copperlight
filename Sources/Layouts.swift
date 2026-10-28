import AppKit

/// A window as `:layout save` found it: its app, title, frame and the usable area of its screen (AppKit coordinates).
struct SavedWindow: Codable, Equatable, Sendable {
    var app: String // bundle id
    var title: String
    var frame: CGRect
    var screen: CGRect
}

/// The windows on screen, kept by name in state.json: their frames belong to this Mac's screens, so they don't travel
/// with config.toml.
struct SavedLayout: Codable, Equatable, Sendable {
    static let stateSection = "layouts"
    var name: String
    var windows: [SavedWindow]
    var saved: Date

    /// "5 windows in 3 apps".
    var summary: String {
        let apps = Set(windows.map(\.app)).count
        return "\(windows.count) window\(windows.count == 1 ? "" : "s") in \(apps) app\(apps == 1 ? "" : "s")"
    }
}

/// Which window now each saved one goes to (saved index → current index): the same title first, then the rest in order.
func matchWindows(saved: [String], current: [String]) -> [Int: Int] {
    var pairs: [Int: Int] = [:], free = Array(current.indices)
    for (index, title) in saved.enumerated() where !title.isEmpty {
        if let match = free.firstIndex(where: { current[$0] == title }) { pairs[index] = free.remove(at: match) }
    }
    for index in saved.indices where pairs[index] == nil && !free.isEmpty { pairs[index] = free.removeFirst() }
    return pairs
}

/// Where a saved window goes now: where it was, if its screen is still there; else the same share of the main screen.
func restoredFrame(_ frame: CGRect, screen: CGRect, screens: [CGRect]) -> CGRect {
    screens.isEmpty || screens.contains(screen) ? frame : movedFrame(frame, from: screen, to: screens[0])
}

/// An app's own windows (not panels or sheets), asked briefly, so a hung app can't stall the rest.
@MainActor private func standardWindows(of app: NSRunningApplication) -> [AXUIElement] {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.25)
    var windows: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
    return (windows as? [AXUIElement] ?? []).filter { axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
}

/// The windows on screen now, what `:layout save` keeps. Hidden apps, minimized and full-screen windows stay out, and
/// so does Copperlight. nil without Accessibility. ponytail: the current Space's windows, as `:window` sees them.
@MainActor func captureWindows() -> [SavedWindow]? {
    guard hasAccessibility("save window layouts") else { return nil }
    let apps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid() && $0.bundleIdentifier != nil }
    return apps.flatMap { app in
        standardWindows(of: app).compactMap { window -> SavedWindow? in
            guard !axBool(window, kAXMinimizedAttribute), !axBool(window, "AXFullScreen"), let frame = windowFrame(window),
                  let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
            else { return nil }
            return SavedWindow(app: app.bundleIdentifier!, title: axString(window, kAXTitleAttribute) ?? "", frame: frame, screen: screen.visibleFrame)
        }
    }
}

/// Puts a layout's windows back, each app's matched by title, then in order. Apps that aren't running stay out, and a
/// notification names them. ponytail: doesn't open them; launching them and waiting for their windows if people ask.
@MainActor func applyLayout(_ layout: SavedLayout) {
    guard hasAccessibility("arrange windows") else { return }
    let screens = NSScreen.screens.map(\.visibleFrame)
    var missing: [String] = []
    for (bundle, saved) in Dictionary(grouping: layout.windows, by: \.app) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            missing.append(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundle)
            continue
        }
        if app.isHidden { app.unhide() }
        let current = standardWindows(of: app)
        for (savedIndex, currentIndex) in matchWindows(saved: saved.map(\.title), current: current.map { axString($0, kAXTitleAttribute) ?? "" }) {
            let window = current[currentIndex], was = saved[savedIndex]
            if axBool(window, kAXMinimizedAttribute) { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            setFrame(window, restoredFrame(was.frame, screen: was.screen, screens: screens))
        }
    }
    if !missing.isEmpty { notify("\(layout.name): some apps aren’t open", "Open \(missing.sorted().joined(separator: ", ")), then run it again") }
}

extension Verb {
    /// `:layout save work` keeps the windows on screen, `:layout work` puts them back, `:layout delete work` forgets it.
    /// `:layout` lists them. The longer commands come first, so `:layout save x` isn't a layout called "save x".
    @MainActor static func layouts(store: StateStore = .shared,
                                   capture: @escaping @MainActor @Sendable () -> [SavedWindow]? = captureWindows,
                                   apply: @escaping @MainActor @Sendable (SavedLayout) -> Void = applyLayout) -> [Verb] {
        let all = { @MainActor in store.get(SavedLayout.stateSection, as: [SavedLayout].self) ?? [] }
        let keep = { @MainActor (layouts: [SavedLayout]) in
            store.set(SavedLayout.stateSection, layouts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
        let same: @Sendable (SavedLayout, String) -> Bool = { $0.name.caseInsensitiveCompare($1) == .orderedSame }
        return [
            Verb(keyword: "layout save", title: "Save Layout", icon: .symbol("square.and.arrow.down"), targets: { name in
                guard !name.isEmpty else {
                    return [LauncherResult(id: "layout-save", title: "Type a name: :layout save work", icon: .symbol("square.and.arrow.down"),
                                           score: 50, actionTitle: "", action: {})]
                }
                guard !["save", "delete"].contains(name.lowercased()) else {
                    return [LauncherResult(id: "layout-save", title: "“\(name)” is a command’s word: pick another name",
                                           icon: .symbol("square.and.arrow.down"), score: 50, actionTitle: "", action: {})]
                }
                let existing = await all().first { same($0, name) }
                return [LauncherResult(
                    id: "layout-save", title: "Save Layout “\(name)”", subtitle: "The windows on screen, where they are now",
                    icon: .symbol("square.and.arrow.down"), score: 50, actionTitle: "Save", action: {},
                    confirm: existing.map { "Replace the layout “\($0.name)”?" },
                    output: { _ in
                        await MainActor.run {
                            guard let windows = capture() else {
                                return LauncherResult(id: "layout-save", title: "Allow Copperlight in Accessibility to save layouts",
                                                      subtitle: "Privacy & Security → Accessibility", icon: .symbol("lock.shield"),
                                                      score: .infinity, actionTitle: "", action: {})
                            }
                            guard !windows.isEmpty else {
                                return LauncherResult(id: "layout-save", title: "No windows to save", subtitle: "Open the ones to keep, then save again",
                                                      icon: .symbol("macwindow"), score: .infinity, actionTitle: "", action: {})
                            }
                            let layout = SavedLayout(name: existing?.name ?? name, windows: windows, saved: .now)
                            keep(all().filter { !same($0, name) } + [layout])
                            return LauncherResult(id: "layout-save", title: "Saved “\(layout.name)”",
                                                  subtitle: "\(layout.summary) · :layout \(layout.name.lowercased()) puts them back",
                                                  icon: .symbol("checkmark.circle"), score: .infinity, actionTitle: "", action: {})
                        }
                    })]
            }),
            Verb(keyword: "layout delete", title: "Delete Layout", icon: .symbol("trash"), targets: { filter in
                await all().enumerated().compactMap { index, layout in
                    guard let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, layout.name) else { return nil }
                    return LauncherResult(id: "layout-delete:\(layout.name.lowercased())", title: "Delete Layout “\(layout.name)”",
                                          subtitle: "Layout · \(layout.summary)", icon: .symbol("trash"), score: score, actionTitle: "Delete",
                                          action: { keep(all().filter { !same($0, layout.name) }) }, staysOpen: true)
                }
            }),
            Verb(keyword: "layout", title: "Layout", icon: .symbol("rectangle.3.group"), targets: { filter in
                let layouts = await all()
                guard !layouts.isEmpty || !filter.isEmpty else {
                    return [LauncherResult(id: "layout:none", title: "No layouts yet: :layout save work", icon: .symbol("rectangle.3.group"),
                                           score: 0, actionTitle: "", action: {})]
                }
                return layouts.enumerated().compactMap { index, layout in
                    guard let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, layout.name) else { return nil }
                    return LauncherResult(id: "layout:\(layout.name.lowercased())", title: layout.name, subtitle: "Layout · \(layout.summary)",
                                          icon: .symbol("rectangle.3.group"), score: score, actionTitle: "Arrange", action: { apply(layout) })
                }
            }),
        ]
    }
}
