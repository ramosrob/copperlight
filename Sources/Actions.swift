import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

/// A `:` command. Typing `:` lists them all and `:min` narrows them down. One without targets acts
/// right away (on the window in front); one with targets takes a filter after its keyword
/// (`:quit saf`) and lists a row per target. Enter on such a command fills in its keyword.
struct Verb: Sendable {
    let keyword: String // what you type after ":" ("quit", "copy path")
    let title: String
    let icon: LauncherResult.Icon
    var confirm: String? = nil // ask first (`:shut down`)
    var showing: (@Sendable () -> String)? = nil // a toggle's row says what Enter does now ("Turn Wi-Fi Off")
    var repeats = false // Enter keeps the panel open, for the next press (`:nudge left`)
    var run: (@MainActor @Sendable () -> Void)? = nil
    var targets: (@Sendable (String) async -> [LauncherResult])? = nil
}

/// The `:` commands of one panel. It gets every query that starts with `:`, and only those.
struct VerbProvider: ResultProvider {
    static let prefix = ":"
    let verbs: [Verb]
    /// More rows for what's typed after `:` (the menus of the app in front), after the commands' own.
    var more: @Sendable (String) async -> [LauncherResult] = { _ in [] }
    /// The commands that take a name (`:quit `); `:!` is the shell's.
    var modes: [Mode] {
        verbs.filter { $0.targets != nil && $0.keyword != "!" }.map { Mode(prefix: ":\($0.keyword) ", title: $0.title, icon: $0.icon) }
    }

    func results(for query: String) async -> [LauncherResult] {
        guard query.hasPrefix(Self.prefix) else { return [] }
        let text = query.dropFirst().trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        // Another name takes targets too: `:kill slack` is `:force quit slack`.
        let named = verbs.lazy.compactMap { verb in
            verb.targets == nil ? nil : ([verb.keyword] + (otherNames[verb.title] ?? [])).first { lower == $0 || lower.hasPrefix($0 + " ") }.map { (verb, $0) }
        }.first
        if let (verb, name) = named, let targets = verb.targets {
            // `:hide o` still offers `:hide others`: commands that extend this one's keyword come first.
            let extensions = verbs.filter { $0.keyword.hasPrefix(verb.keyword + " ") }
            return rows(extensions, matching: text) + (await targets(text.dropFirst(name.count).trimmingCharacters(in: .whitespaces)))
        }
        return rows(verbs, matching: text) + (text.isEmpty ? [] : await more(text))
    }

    private func rows(_ verbs: [Verb], matching text: String) -> [LauncherResult] {
        // A group's name lists the group alone: `:left` is the left commands, not every title with l-e-f-t in it.
        let lower = text.lowercased()
        let group = verbs.filter { $0.keyword == lower || $0.keyword.hasPrefix(lower + " ") }
        return (group.isEmpty || lower.isEmpty ? verbs : group).enumerated().compactMap { index, verb in
            let match = [fuzzyScore(text, verb.title), fuzzyScore(text, verb.keyword), otherNameScore(text, verb.title)].compactMap { $0 }.max()
            // As listed when nothing's typed, 0.01 apart, so the ones you use (frecency, up to 0.5) move up.
            guard let score = text.isEmpty ? -0.01 * Double(index) : match else { return nil }
            return LauncherResult(
                id: "verb:\(verb.keyword)", title: verb.showing?() ?? verb.title, subtitle: ":" + verb.keyword, icon: verb.icon,
                score: score, actionTitle: verb.run != nil ? "Run" : "Choose", action: verb.run ?? {},
                completion: verb.targets != nil ? ":\(verb.keyword) " : nil, repeats: verb.repeats, confirm: verb.confirm)
        }
    }
}

extension Verb {
    /// The launcher's commands: the window in front, running apps, files, the Mac, Copperlight.
    @MainActor static func launcher(files: FileSearchProvider) -> [Verb] {
        let place = { (keyword: String, title: String, symbol: String, layout: WindowLayout) in
            Verb(keyword: keyword, title: title, icon: .symbol(symbol), run: { arrangeFrontWindow(layout) })
        }
        let nudge = { (direction: NudgeDirection, title: String, symbol: String) in
            Verb(keyword: "nudge \(direction)", title: "Nudge \(title)", icon: .symbol(symbol), repeats: true, run: { nudgeFrontWindow(direction) })
        }
        return [
            // The window in front
            Verb(keyword: "minimize", title: "Minimize Window", icon: .symbol("minus"), run: { minimizeFrontWindow() }),
            Verb(keyword: "fullscreen", title: "Toggle Fullscreen", icon: .symbol("arrow.up.left.and.arrow.down.right"),
                 run: { toggleFullscreenFrontWindow() }),
            place("maximize", "Maximize Window", "macwindow", .maximize),
            place("center", "Center Window", "rectangle.center.inset.filled", .center),
            place("left", "Left Half", "rectangle.lefthalf.filled", .leftHalf),
            place("right", "Right Half", "rectangle.righthalf.filled", .rightHalf),
            place("top", "Top Half", "rectangle.tophalf.filled", .topHalf),
            place("bottom", "Bottom Half", "rectangle.bottomhalf.filled", .bottomHalf),
            place("top left", "Top Left Quarter", "rectangle.inset.topleft.filled", .topLeft),
            place("top right", "Top Right Quarter", "rectangle.inset.topright.filled", .topRight),
            place("bottom left", "Bottom Left Quarter", "rectangle.inset.bottomleft.filled", .bottomLeft),
            place("bottom right", "Bottom Right Quarter", "rectangle.inset.bottomright.filled", .bottomRight),
            place("left third", "Left Third", "rectangle.leadingthird.inset.filled", .leftThird),
            place("center third", "Center Third", "rectangle.split.3x1", .centerThird),
            place("right third", "Right Third", "rectangle.trailingthird.inset.filled", .rightThird),
            place("left two thirds", "Left Two Thirds", "rectangle.lefthalf.inset.filled", .leftTwoThirds),
            place("right two thirds", "Right Two Thirds", "rectangle.righthalf.inset.filled", .rightTwoThirds),
            nudge(.left, "Left", "arrow.left"),
            nudge(.right, "Right", "arrow.right"),
            nudge(.up, "Up", "arrow.up"),
            nudge(.down, "Down", "arrow.down"),
            Verb(keyword: "next display", title: "Move to Next Display", icon: .symbol("display.2"), run: { moveFrontWindowToNextDisplay() }),
            Verb(keyword: "restore", title: "Restore Window", icon: .symbol("arrow.uturn.backward"), run: { restoreFrontWindow() }),
            Verb(keyword: "close", title: "Close Window", icon: .symbol("xmark.square"), run: { closeFrontWindow() }),
            Verb(keyword: "window", title: "Switch to Window", icon: .symbol("macwindow.on.rectangle"), targets: { windowRows($0) }),
        ] + layouts() + [
            // Running apps
            Verb(keyword: "quit", title: "Quit Application", icon: .symbol("xmark"),
                 targets: { runningAppRows($0, verb: "Quit") { $0.terminate() } }),
            Verb(keyword: "force quit", title: "Force Quit Application", icon: .symbol("xmark.octagon"),
                 targets: { runningAppRows($0, verb: "Force Quit", confirm: true) { $0.forceTerminate() } }),
            Verb(keyword: "hide", title: "Hide Application", icon: .symbol("eye.slash"),
                 targets: { runningAppRows($0, verb: "Hide") { $0.hide() } }),
            Verb(keyword: "hide others", title: "Hide Others", icon: .symbol("eye.slash.circle"), run: { hideOtherApps() }),
            Verb(keyword: "relaunch", title: "Relaunch Application", icon: .symbol("arrow.clockwise.circle"),
                 targets: { runningAppRows($0, verb: "Relaunch") { relaunch($0) } }),
            // Files
            fileVerb("reveal", "Reveal in Finder", icon: .symbol("folder"), files: files) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: $0)])
            },
            fileVerb("copy path", "Copy Path", icon: .symbol("doc.on.doc"), files: files) { copyToClipboard($0) },
            // The Mac
            Verb(keyword: "lock", title: "Lock Screen", icon: .symbol("lock.fill"), run: { lockScreen() }),
            Verb(keyword: "sleep", title: "Sleep", icon: .symbol("moon.zzz.fill"),
                 run: { runDetached("/usr/bin/pmset", ["sleepnow"], label: "Sleep") }),
            Verb(keyword: "sleep displays", title: "Sleep Displays", icon: .symbol("display"),
                 run: { runDetached("/usr/bin/pmset", ["displaysleepnow"], label: "Sleep Displays") }),
            // Apple events to loginwindow (kAERestart, kAEShutDown): apps are asked to quit, as from the Apple menu.
            Verb(keyword: "restart", title: "Restart", icon: .symbol("arrow.clockwise"),
                 confirm: "Restart the Mac? Apps with unsaved changes ask first.",
                 run: { osascript(#"tell application "loginwindow" to «event aevtrest»"#, label: "Restart") }),
            Verb(keyword: "shut down", title: "Shut Down", icon: .symbol("power"),
                 confirm: "Shut down the Mac? Apps with unsaved changes ask first.",
                 run: { osascript(#"tell application "loginwindow" to «event aevtshut»"#, label: "Shut Down") }),
            Verb(keyword: "empty trash", title: "Empty Trash", icon: .symbol("trash"),
                 confirm: "Empty the Trash? This can't be undone.",
                 run: { osascript(#"tell application "Finder" to empty trash"#, label: "Empty Trash") }),
            Verb(keyword: "dark", title: "Toggle Dark Mode", icon: .symbol("circle.lefthalf.filled"),
                 showing: { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? "Turn Dark Mode Off" : "Turn Dark Mode On" },
                 run: {
                     osascript(#"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#,
                               label: "Dark Mode")
                 }),
            Verb(keyword: "wifi", title: "Toggle Wi-Fi", icon: .symbol("wifi"),
                 showing: { wifiIsOn() ? "Turn Wi-Fi Off" : "Turn Wi-Fi On" }, run: { toggleWiFi() }),
            Verb(keyword: "awake", title: "Keep Awake", icon: .symbol("sun.max"),
                 showing: { KeepAwake.isOn ? "Stop Keeping Awake" : "Keep Awake" }, run: { KeepAwake.shared.toggle() }),
            Verb(keyword: "eject", title: "Eject Disk", icon: .symbol("eject"), targets: { ejectRows($0) }),
            // Sound
            Verb(keyword: "play", title: "Play or Pause", icon: .symbol("playpause.fill"), run: { pressMediaKey(NX_KEYTYPE_PLAY) }),
            Verb(keyword: "next track", title: "Next Track", icon: .symbol("forward.fill"), run: { pressMediaKey(NX_KEYTYPE_NEXT) }),
            Verb(keyword: "previous track", title: "Previous Track", icon: .symbol("backward.fill"),
                 run: { pressMediaKey(NX_KEYTYPE_PREVIOUS) }),
            Verb(keyword: "volume", title: "Set Volume", icon: .symbol("speaker.wave.2.fill"), targets: { volumeRows($0) }),
            Verb(keyword: "mute", title: "Toggle Mute", icon: .symbol("speaker.slash.fill"),
                 showing: { outputIsMuted() ? "Unmute" : "Mute" }, run: { toggleMute() }),
            Verb(keyword: "output", title: "Switch Sound Output", icon: .symbol("hifispeaker"), targets: { outputRows($0) }),
            Verb(keyword: "hidden files", title: "Toggle Hidden Files", icon: .symbol("eye"), run: {
                // Finder reads it at launch, so it restarts (its windows come back).
                runDetached("/bin/sh", ["-c", """
                    case "$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)" in 1|YES|true|TRUE) show=false;; *) show=true;; esac
                    defaults write com.apple.finder AppleShowAllFiles -bool $show && killall Finder
                    """], label: "Hidden Files")
            }),
            Verb(keyword: "shortcut", title: "Run Shortcut", icon: .file("/System/Applications/Shortcuts.app"),
                 targets: { shortcutRows($0) }),
            // Listed here to be found (":shell"); Enter types ":! ", and ShellProvider takes every ":!" query.
            Verb(keyword: "!", title: "Run Shell Command", icon: .symbol("terminal"), targets: { _ in [] }),
            // Copperlight
            Verb(keyword: "config", title: "Open Config", icon: .symbol("gearshape"), run: { NSWorkspace.shared.open(Config.file) }),
        ]
    }

    /// `:reveal readme`: a row per matching file (file search, so from 2 letters). A path (`:reveal ~/code/copperlight/`)
    /// lists that folder instead, with the folder itself first.
    private static func fileVerb(_ keyword: String, _ title: String, icon: LauncherResult.Icon, files: FileSearchProvider,
                                 act: @escaping @MainActor @Sendable (String) -> Void) -> Verb {
        Verb(keyword: keyword, title: title, icon: icon, targets: { filter in
            let paths: [(path: String, name: String)]
            if let query = pathQuery(filter) {
                let folder = query.url
                paths = (query.filter.isEmpty ? [(folder.path, folder.lastPathComponent)] : [])
                    + (pathEntries(query) ?? []).map { ($0.path, $0.name) }
            } else {
                paths = await files.hits(for: filter, limit: 20).map { ($0.path, $0.name) }
            }
            return paths.enumerated().map { index, file in
                LauncherResult(id: "\(keyword):\(file.path)", title: "\(title): \(file.name)", subtitle: shortParentPath(file.path),
                               icon: .file(file.path), score: -Double(index), actionTitle: title,
                               action: { act(file.path) })
            }
        })
    }
}

/// One row per running app whose name matches `filter` (all of them, A–Z, when it's empty).
func runningAppRows(_ filter: String, verb: String, confirm: Bool = false,
                    act: @escaping @MainActor @Sendable (NSRunningApplication) -> Void) -> [LauncherResult] {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    return apps.enumerated().compactMap { index, app in
        guard let name = app.localizedName, let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, name) else { return nil }
        let pid = app.processIdentifier
        return LauncherResult(
            // By path, not pid, so frecency remembers "Quit Slack" across launches.
            id: "\(verb):\(app.bundleURL?.path ?? "\(pid)")", title: "\(verb) \(name)",
            icon: app.bundleURL.map { .file($0.path) } ?? .symbol("app"), score: score, actionTitle: verb,
            action: { if let app = NSRunningApplication(processIdentifier: pid) { act(app) } },
            confirm: confirm ? "\(verb) \(name)? Unsaved changes are lost." : nil)
    }
}

// MARK: Apps

/// Hides every app but the one in front (the launcher never takes focus, so that's the one you were in).
@MainActor func hideOtherApps() {
    let front = NSWorkspace.shared.frontmostApplication
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app != front { app.hide() }
}

@MainActor func relaunch(_ app: NSRunningApplication) {
    guard let url = app.bundleURL else { return }
    app.terminate()
    Task {
        for _ in 0..<300 where !app.isTerminated { // up to a minute: it may be asking about unsaved changes
            try? await Task.sleep(for: .milliseconds(200))
        }
        if app.isTerminated {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            notify("\(app.localizedName ?? "The app") didn't quit, so it wasn't relaunched")
        }
    }
}

// MARK: Mac

@MainActor func osascript(_ script: String, label: String) { runDetached("/usr/bin/osascript", ["-e", script], label: label) }

@MainActor func lockScreen() {
    guard hasAccessibility("lock the screen") else { return }
    sendKeystroke(kVK_ANSI_Q, [.maskControl, .maskCommand]) // the system's own Lock Screen shortcut
}

/// `:eject`: a row per disk that can be ejected (external drives, SD cards, disk images).
func ejectRows(_ filter: String) -> [LauncherResult] {
    let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedNameKey]
    let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
    let rows = volumes.enumerated().compactMap { index, url -> LauncherResult? in
        guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsEjectable == true || values.volumeIsRemovable == true,
              let name = values.volumeLocalizedName, let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, name)
        else { return nil }
        let path = url.path
        return LauncherResult(id: "eject:\(path)", title: "Eject \(name)", subtitle: path, icon: .file(path),
                              score: score, actionTitle: "Eject",
                              action: { runDetached("/usr/sbin/diskutil", ["eject", path], label: "Eject \(name)") })
    }
    guard rows.isEmpty, filter.isEmpty else { return rows }
    return [LauncherResult(id: "eject:none", title: "No disks to eject", icon: .symbol("eject"), score: 0, actionTitle: "", action: {})]
}

/// `:volume 30`: one row that sets the output volume (and unmutes). Anything but 0–100 says what to type.
func volumeRows(_ text: String) -> [LauncherResult] {
    guard let level = Int(text), (0...100).contains(level) else {
        return [LauncherResult(id: "volume:help", title: "Type a level from 0 to 100", subtitle: ":volume 30",
                               icon: .symbol("speaker.wave.2.fill"), score: 0, actionTitle: "", action: {})]
    }
    return [LauncherResult(id: "volume:set", title: "Set Volume to \(level)%", icon: .symbol("speaker.wave.2.fill"),
                           score: 0, actionTitle: "Set",
                           action: { osascript("set volume output volume \(level) without output muted", label: "Volume") })]
}

/// `:shortcut name`: a row per Shortcut from Apple's Shortcuts app.
func shortcutRows(_ filter: String) -> [LauncherResult] {
    shortcutNames().enumerated().compactMap { index, name in
        guard let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, name) else { return nil }
        return LauncherResult(id: "shortcut:\(name)", title: "Run Shortcut: \(name)",
                              icon: .file("/System/Applications/Shortcuts.app"), score: score, actionTitle: "Run",
                              action: { runDetached("/usr/bin/shortcuts", ["run", name], label: name) })
    }
}

/// Asks the `shortcuts` tool. ponytail: blocks this (background) thread ~20 ms per keystroke; cache it if that grows.
private func shortcutNames() -> [String] {
    let process = Process(), output = Pipe()
    process.executableURL = URL(filePath: "/usr/bin/shortcuts")
    process.arguments = ["list"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile() // read before waiting, so a full pipe can't stall it
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
}

// MARK: Window in front

enum WindowLayout {
    case maximize, center, leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
}

/// Where a window of `size` goes on a screen whose usable area is `visible` (AppKit coordinates: y grows up).
func layoutFrame(_ layout: WindowLayout, size: CGSize, visible: CGRect) -> CGRect {
    if layout == .center {
        let (width, height) = (min(size.width, visible.width), min(size.height, visible.height))
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }
    // x, y, width, height as fractions of the usable area.
    let (x, y, width, height): (CGFloat, CGFloat, CGFloat, CGFloat) = switch layout {
    case .maximize, .center: (0, 0, 1, 1)
    case .leftHalf: (0, 0, 1 / 2, 1)
    case .rightHalf: (1 / 2, 0, 1 / 2, 1)
    case .topHalf: (0, 1 / 2, 1, 1 / 2)
    case .bottomHalf: (0, 0, 1, 1 / 2)
    case .topLeft: (0, 1 / 2, 1 / 2, 1 / 2)
    case .topRight: (1 / 2, 1 / 2, 1 / 2, 1 / 2)
    case .bottomLeft: (0, 0, 1 / 2, 1 / 2)
    case .bottomRight: (1 / 2, 0, 1 / 2, 1 / 2)
    case .leftThird: (0, 0, 1 / 3, 1)
    case .centerThird: (1 / 3, 0, 1 / 3, 1)
    case .rightThird: (2 / 3, 0, 1 / 3, 1)
    case .leftTwoThirds: (0, 0, 2 / 3, 1)
    case .rightTwoThirds: (1 / 3, 0, 2 / 3, 1)
    }
    return CGRect(x: visible.minX + x * visible.width, y: visible.minY + y * visible.height,
                  width: width * visible.width, height: height * visible.height)
}

enum NudgeDirection { case left, right, up, down }

/// `frame` moved a step, 5% of the screen, toward `direction`, without leaving the screen's usable area.
func nudgedFrame(_ frame: CGRect, _ direction: NudgeDirection, visible: CGRect) -> CGRect {
    let (dx, dy): (CGFloat, CGFloat) = switch direction {
    case .left: (-visible.width / 20, 0)
    case .right: (visible.width / 20, 0)
    case .up: (0, visible.height / 20)
    case .down: (0, -visible.height / 20)
    }
    var moved = frame.offsetBy(dx: dx, dy: dy)
    moved.origin.x = min(max(moved.minX, visible.minX), max(visible.minX, visible.maxX - moved.width))
    moved.origin.y = min(max(moved.minY, visible.minY), max(visible.minY, visible.maxY - moved.height))
    return moved
}

/// The same place on another screen: a left half stays a left half, a small window keeps its share.
func movedFrame(_ frame: CGRect, from old: CGRect, to new: CGRect) -> CGRect {
    let (sx, sy) = (new.width / old.width, new.height / old.height)
    return CGRect(x: new.minX + (frame.minX - old.minX) * sx, y: new.minY + (frame.minY - old.minY) * sy,
                  width: frame.width * sx, height: frame.height * sy)
}

/// Selected text as the launcher's query: on one line, trimmed, and at most 500 characters (longer text translates
/// better from the clipboard: copy it, then `translate`). nil for none.
func launcherText(fromSelection text: String?) -> String? {
    guard let words = text?.split(whereSeparator: \.isWhitespace), !words.isEmpty else { return nil }
    return String(words.joined(separator: " ").prefix(500))
}

/// Chromium browsers and Electron apps build their accessibility tree, the text in it included, only once an app
/// asks (AXManualAccessibility); everything else always has it.
func sharesTextWhenAsked(bundleID: String?, bundleURL: URL?) -> Bool {
    let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                                 "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "company.thebrowser.Browser",
                                 "com.operasoftware.Opera"]
    if let bundleID, chromium.contains(bundleID) { return true }
    guard let bundleURL else { return false }
    return FileManager.default.fileExists(atPath: bundleURL.appending(path: "Contents/Frameworks/Electron Framework.framework").path)
}

/// Apps asked to build their accessibility tree, once each (by pid: a relaunched app starts without it).
@MainActor private var askedForText: Set<pid_t> = []

/// What's selected in the app in front, for the launcher to open with. Asked of that app directly, briefly (a hung
/// app can't hold the hotkey up), and never of a password field. nil without Accessibility, or when the app doesn't
/// say. A Chromium or Electron app is asked to share its text the first time; it answers a moment later.
@MainActor func frontSelection() -> String? {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.1)
    if sharesTextWhenAsked(bundleID: app.bundleIdentifier, bundleURL: app.bundleURL), askedForText.insert(app.processIdentifier).inserted {
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
    guard let focused = axElement(element, kAXFocusedUIElementAttribute),
          axString(focused, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
    else { return nil }
    AXUIElementSetMessagingTimeout(focused, 0.1)
    return launcherText(fromSelection: axString(focused, kAXSelectedTextAttribute))
}

@MainActor func hasAccessibility(_ why: String) -> Bool {
    if AXIsProcessTrusted() { return true }
    notify("Allow Copperlight in Accessibility to \(why)", "Privacy & Security → Accessibility")
    // System Settings opens once per launch: someone who said no doesn't want it back on every Enter.
    if !askedForAccessibility {
        askedForAccessibility = true
        requestAccessibility()
    }
    return false
}

@MainActor private var askedForAccessibility = false

/// The focused window of the app in front. The launcher never takes focus, so that's the app you
/// were in. Moving other apps' windows needs Accessibility, which pasting already asks for.
@MainActor private func frontWindow() -> AXUIElement? {
    guard hasAccessibility("manage windows"), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    return axElement(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
}

@MainActor func minimizeFrontWindow() {
    guard let window = frontWindow() else { return }
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
}

@MainActor func toggleFullscreenFrontWindow() {
    guard let window = frontWindow() else { return }
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
    let on = (value as? Bool) ?? false
    AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, on ? kCFBooleanFalse : kCFBooleanTrue)
}

@MainActor func closeFrontWindow() {
    guard let window = frontWindow() else { return }
    guard let button = axElement(window, kAXCloseButtonAttribute) else { return NSSound.beep() }
    AXUIElementPerformAction(button, kAXPressAction as CFString)
}

@MainActor func arrangeFrontWindow(_ layout: WindowLayout) {
    placeFrontWindow { current, screen in layoutFrame(layout, size: current.size, visible: screen.visibleFrame) }
}

@MainActor func nudgeFrontWindow(_ direction: NudgeDirection) {
    placeFrontWindow { current, screen in nudgedFrame(current, direction, visible: screen.visibleFrame) }
}

@MainActor func moveFrontWindowToNextDisplay() {
    placeFrontWindow { current, screen in
        let screens = NSScreen.screens
        guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return nil }
        return movedFrame(current, from: screen.visibleFrame, to: screens[(index + 1) % screens.count].visibleFrame)
    }
}

/// Where Copperlight moved windows from and to, so `:restore` can put one back.
/// ponytail: never pruned; two rects per window ever moved, gone on quit.
@MainActor private var moves: [AXUIElement: (from: CGRect, to: CGRect)] = [:]

@MainActor func restoreFrontWindow() {
    guard let window = frontWindow() else { return }
    guard let from = moves.removeValue(forKey: window)?.from else { return NSSound.beep() } // Copperlight never moved it
    setFrame(window, from)
}

/// Moves the window in front to the frame `place` picks from its current frame and screen.
@MainActor private func placeFrontWindow(_ place: (CGRect, NSScreen) -> CGRect?) {
    guard let window = frontWindow(), let current = windowFrame(window),
          let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: current.midX, y: current.midY)) }) ?? NSScreen.main,
          let target = place(current, screen)
    else { return }
    // Several moves in a row restore to where it started, unless you moved it yourself since.
    let from = moves[window].flatMap { $0.to == current ? $0.from : nil } ?? current
    setFrame(window, target)
    moves[window] = (from, windowFrame(window) ?? target) // where it really ended up: apps can round sizes
}

/// `:window term`: a row per window of every app, front app first, by window title or app name. Enter brings it
/// forward (unminimizing it). ponytail: Accessibility sees the current Space's windows and minimized ones, not
/// other Spaces' (that needs private APIs).
func windowRows(_ filter: String) -> [LauncherResult] {
    guard AXIsProcessTrusted() else {
        return [LauncherResult(id: "window:access", title: "Allow Copperlight in Accessibility to list windows",
                               subtitle: "Privacy & Security → Accessibility", icon: .symbol("lock.shield"), score: 0,
                               actionTitle: "Open System Settings", action: { requestAccessibility() })]
    }
    // Apps in the order of their windows on screen, front to back; the rest (hidden, minimized only) after.
    let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { $0[kCGWindowLayer as String] as? Int == 0 }.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t }
    let order = Dictionary(onScreen.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
    let apps = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        .sorted { order[$0.processIdentifier, default: .max] < order[$1.processIdentifier, default: .max] }
    var rows: [LauncherResult] = []
    for app in apps {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25) // a hung app can't stall the list
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
        let name = app.localizedName ?? "App"
        for window in windows as? [AXUIElement] ?? [] where axString(window, kAXSubroleAttribute) == kAXStandardWindowSubrole {
            let title = axString(window, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? name
            let minimized = axBool(window, kAXMinimizedAttribute)
            let index = Double(rows.count)
            guard let match = filter.isEmpty ? 0 : [fuzzyScore(filter, title), fuzzyScore(filter, name)].compactMap(\.self).max()
            else { continue }
            nonisolated(unsafe) let window = window
            let pid = app.processIdentifier
            rows.append(LauncherResult(
                id: "window:\(app.bundleURL?.path ?? name):\(title)", title: title,
                subtitle: name + (minimized ? " · minimized" : ""), icon: app.bundleURL.map { .file($0.path) } ?? .symbol("macwindow"),
                score: match - index / 1000, actionTitle: "Switch", action: {
                    if minimized { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
                    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    NSRunningApplication(processIdentifier: pid)?.activate()
                }))
        }
    }
    return rows
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
    return ref as? String
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
    return ref as? Bool ?? false
}

/// A window's frame in AppKit coordinates. Accessibility measures from the top left of the primary
/// screen, AppKit from its bottom left.
@MainActor func windowFrame(_ window: AXUIElement) -> CGRect? {
    guard let position: CGPoint = axValue(window, kAXPositionAttribute, .cgPoint, .zero),
          let size: CGSize = axValue(window, kAXSizeAttribute, .cgSize, .zero),
          let primary = NSScreen.screens.first?.frame
    else { return nil }
    return CGRect(x: position.x, y: primary.maxY - position.y - size.height, width: size.width, height: size.height)
}

@MainActor func setFrame(_ window: AXUIElement, _ frame: CGRect) {
    guard let primary = NSScreen.screens.first?.frame else { return }
    var (position, size) = (CGPoint(x: frame.minX, y: primary.maxY - frame.maxY), frame.size)
    // Size, move, size again: an app may refuse a size that doesn't fit where the window still is.
    for (attribute, value) in [(kAXSizeAttribute, AXValueCreate(.cgSize, &size)), (kAXPositionAttribute, AXValueCreate(.cgPoint, &position)),
                               (kAXSizeAttribute, AXValueCreate(.cgSize, &size))] {
        if let value { AXUIElementSetAttributeValue(window, attribute as CFString, value) }
    }
}

func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref,
          CFGetTypeID(ref) == AXUIElementGetTypeID()
    else { return nil }
    return (ref as! AXUIElement)
}

private func axValue<T: BitwiseCopyable>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ empty: T) -> T? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success, let ref,
          CFGetTypeID(ref) == AXValueGetTypeID()
    else { return nil }
    var value = empty
    return AXValueGetValue(ref as! AXValue, type, &value) ? value : nil
}
