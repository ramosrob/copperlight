import AppKit
import Synchronization

/// One item of an app's menus: the titles from the menu bar down to it (["File", "Export", "PNG"]), its keyboard
/// shortcut ("⇧⌘E"), and how to choose it.
struct MenuCommand: Sendable {
    let path: [String]
    var shortcut = ""
    let choose: @MainActor @Sendable () -> Void
}

/// Keys that come as a control or private-use character, as menus draw them.
private let menuKeys: [Character: String] = ["\u{8}": "⌫", "\u{9}": "⇥", "\u{D}": "↩", "\u{1B}": "⎋", "\u{7F}": "⌦",
                                             "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→"]

/// A menu item's shortcut as the menu shows it. `modifiers` is Accessibility's mask: 1 ⇧, 2 ⌥, 4 ⌃, 8 no ⌘.
/// ponytail: function keys and the rest of the private-use range show no shortcut rather than an empty box.
func menuShortcut(char: String?, modifiers: Int) -> String {
    guard let char, let first = char.first else { return "" }
    let invisible = char.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .privateUse }
    guard let key = menuKeys[first] ?? (invisible ? nil : char.uppercased()) else { return "" }
    return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        + (modifiers & 8 == 0 ? "⌘" : "") + key
}

/// `:export pdf`: menu items whose title, or title with its submenus (Export To › PDF…), is a close match, from 3
/// letters, ranked after the built-in commands. Not with the menu bar's name, or `:file` would be all of File. The
/// subtitle says where the item is (Pages › File › Export To) and the right edge its shortcut; Enter chooses it.
func menuRows(_ items: [MenuCommand], matching text: String, app: String, icon: LauncherResult.Icon) -> [LauncherResult] {
    guard text.count >= 3 else { return [] }
    return items.compactMap { item in
        guard let title = item.path.last,
              let score = [fuzzyScore(text, title), fuzzyScore(text, item.path.dropFirst().joined(separator: " "))].compactMap(\.self).max(),
              score >= 0.6 else { return nil }
        return LauncherResult(id: "menu:\(app):\(item.path.joined(separator: "/"))", title: title,
                              subtitle: ([app] + item.path.dropLast()).joined(separator: " › "), accessory: item.shortcut,
                              icon: icon, score: score - 1, actionTitle: "Choose", action: item.choose)
    }
}

/// The enabled items of an app's menus, but the Apple menu (always the first) and Services. Needs Accessibility.
func readMenus(_ pid: pid_t) -> [MenuCommand] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25) // a hung app can't stall the list
    var bar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
          CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
    let attributes = [kAXTitleAttribute, kAXEnabledAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
                      kAXChildrenAttribute] as CFArray
    var commands: [MenuCommand] = []
    // Menu bar item ("File") → its menu (no title) → items, and an item with a submenu → its menu → items.
    func walk(_ elements: [AXUIElement], _ path: [String]) {
        for element in elements {
            var ref: CFArray?
            AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &ref)
            let values = ref as? [Any] ?? []
            guard values.count == 5 else { continue }
            let title = values[0] as? String ?? "", children = values[4] as? [AXUIElement] ?? []
            if !children.isEmpty {
                if title != "Services" { walk(children, title.isEmpty ? path : path + [title]) }
            } else if !title.isEmpty, values[1] as? Bool == true {
                nonisolated(unsafe) let item = element
                commands.append(MenuCommand(path: path + [title], shortcut: menuShortcut(char: values[2] as? String, modifiers: values[3] as? Int ?? 0),
                                            choose: { AXUIElementPerformAction(item, kAXPressAction as CFString) }))
            }
        }
    }
    var items: CFTypeRef?
    AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items)
    walk(Array((items as? [AXUIElement] ?? []).dropFirst()), [])
    return commands
}

/// The menus last read, and whose. ponytail: read again when another app is in front or after 5 seconds, so typing
/// `:exp`, `:expo`, `:export` reads them once; an item that turns on or off within those seconds shows as it was.
private let lastMenus = Mutex<(pid: pid_t, read: ContinuousClock.Instant, items: [MenuCommand])?>(nil)

/// Menu rows for what's typed after `:`, from the app in front: the launcher never takes focus, so that's the app
/// you were in. Without Accessibility, one row at the bottom says so.
func frontMenuRows(_ text: String) -> [LauncherResult] {
    guard text.count >= 3 else { return [] }
    guard AXIsProcessTrusted() else {
        return [LauncherResult(id: "menu:access", title: "Allow Copperlight in Accessibility to search menus",
                               subtitle: "Privacy & Security → Accessibility", icon: .symbol("lock.shield"), score: -2,
                               actionTitle: "Open System Settings", action: { requestAccessibility() })]
    }
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return [] }
    let pid = app.processIdentifier
    let items = lastMenus.withLock { last in
        if let last, last.pid == pid, ContinuousClock.now - last.read < .seconds(5) { return last.items }
        let items = readMenus(pid)
        last = (pid, .now, items)
        return items
    }
    return menuRows(items, matching: text, app: app.localizedName ?? "App",
                    icon: app.bundleURL.map { .file($0.path) } ?? .symbol("filemenu.and.selection"))
}
