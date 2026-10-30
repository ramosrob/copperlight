import AppKit
import EventKit
import KeyboardShortcuts
import Photos
import ServiceManagement
import SwiftUI
import UserNotifications

/// The permissions the welcome screen sets up. Each is still asked where it's first used; this is one place to give
/// them all and see which are on.
enum Permission: CaseIterable {
    case accessibility, calendars, reminders, notifications, photos

    /// The ones the features that are on use (Settings › Features).
    static var shown: [Permission] {
        allCases.filter { [.calendars: Feature.calendar, .reminders: .reminders, .photos: .photoText][$0]?.isOn ?? true }
    }

    enum Access { case granted, notAsked, denied }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .notifications: "Notifications"
        case .photos: "Photos"
        }
    }

    var why: String {
        switch self {
        case .accessibility: "Paste into your apps, move and switch windows"
        case .calendars: "Today’s meetings, and the events you add"
        case .reminders: "The todos you add"
        case .notifications: "Timers, and how shell lines ended"
        case .photos: "Find the text in your photos, read on this Mac"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .notifications: "bell"
        case .photos: "photo.on.rectangle"
        }
    }

    func access() async -> Access {
        switch self {
        case .accessibility: AXIsProcessTrusted() ? .granted : .notAsked // asking again just opens System Settings
        case .calendars: Self.access(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.access(EKEventStore.authorizationStatus(for: .reminder))
        case .notifications:
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional: .granted
            case .denied: .denied
            default: .notAsked
            }
        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .authorized, .limited: .granted
            case .denied, .restricted: .denied
            default: .notAsked
            }
        }
    }

    /// `meetings` reads the calendars, so add-only access (from `add event`) still offers Allow.
    private static func access(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    /// macOS asks once; after a no, only System Settings can change it.
    @MainActor func request(_ access: Access) async {
        guard access == .notAsked else {
            let page = self == .notifications ? "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
                : "com.apple.preference.security?Privacy_\(title)"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(page)")!)
            return
        }
        switch self {
        case .accessibility: requestAccessibility()
        case .calendars: _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders: _ = try? await EKEventStore().requestFullAccessToReminders()
        case .notifications: _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .photos: _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }
}

extension KeyboardShortcuts.Shortcut {
    /// One keycap per modifier, then the key: "⌘", "Space".
    @MainActor var keycaps: [String] {
        let symbols = modifiers.ks_symbolicRepresentation
        return symbols.map(String.init) + [String(description.dropFirst(symbols.count))]
    }
}

/// What the welcome screen shows live.
@MainActor @Observable final class Welcome {
    var access: [Permission: Permission.Access] = [:]
    var launchAtLogin = false
    var keycaps: [String] = []
    var triedHotkey = false // pressed while the screen is open

    /// Accessibility has no change callback, and the others change in System Settings too: the screen polls this.
    func refresh() async {
        for permission in Permission.shown {
            let now = await permission.access()
            if access[permission] != now { access[permission] = now }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A window of this menu bar app (the welcome screen, settings). While one is open, Copperlight is in the Dock and ⌘Tab
/// like any app; when the last one closes, it's back to the menu bar only. ⌘W closes it.
class AppWindow: NSWindow {
    init(title: String, style: NSWindow.StyleMask = [], content: some View) {
        super.init(contentRect: .zero, styleMask: NSWindow.StyleMask([.titled, .closable, .fullSizeContentView]).union(style), backing: .buffered, defer: false)
        self.title = title
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: content)
        setContentSize(contentViewController!.view.fittingSize) // now, so center() centers the real size
        center()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless() // macOS may keep another app active (a launch from a script): be seen anyway
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w"
        else { return super.performKeyEquivalent(with: event) }
        close()
        return true
    }

    /// Drops the view, which ends what it runs (polling); the next show builds a new window.
    override func close() {
        super.close()
        contentViewController = nil
        if !NSApp.windows.contains(where: { $0 is AppWindow && $0.isVisible }) { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The welcome screen: on first launch, then from the menu bar or `welcome`. Esc closes it too.
final class WelcomeWindow: AppWindow {
    let model: Welcome

    init(start: @escaping @MainActor () -> Void) {
        let model = Welcome()
        self.model = model
        super.init(title: "Welcome to Copperlight", content: WelcomeView(model: model, start: start))
        titleVisibility = .hidden // the title is for the window list and VoiceOver
        isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] { standardWindowButton(button)?.isHidden = true }
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

private struct WelcomeView: View {
    let model: Welcome
    let start: @MainActor () -> Void
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .shadow(color: .accent.opacity(0.3), radius: 22, y: 10)
                .rise(shown, 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Welcome to")
                Text("Copperlight").foregroundStyle(LinearGradient.brand)
            }
            .font(.system(size: 28, weight: .semibold)).tracking(-0.4)
            .padding(.top, 12).rise(shown, 0.05)
            Text("Type it. Press Enter.").font(.system(size: 16)).foregroundStyle(.secondary)
                .padding(.top, 6).rise(shown, 0.1)

            HotkeyPill(keycaps: model.keycaps, tried: model.triedHotkey).padding(.top, 26).rise(shown, 0.16)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Permissions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Each one is used on this Mac only").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                VStack(spacing: 0) {
                    ForEach(Permission.shown, id: \.self) { permission in
                        if permission != Permission.shown.first { Divider().padding(.leading, 60) }
                        PermissionRow(permission: permission, access: model.access[permission]) {
                            Task {
                                await permission.request(model.access[permission] ?? .notAsked)
                                await model.refresh()
                            }
                        }
                    }
                }
                .modifier(Tray())
            }
            .padding(.top, 24).rise(shown, 0.22)

            Row(symbol: "power", title: "Open at Login", detail: "Ready the moment your Mac starts") {
                Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin },
                                                      set: { model.launchAtLogin = setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).labelsHidden().tint(.accent)
            }
            .modifier(Tray()).padding(.top, 10).rise(shown, 0.28)

            Button(action: start) {
                HStack(spacing: 10) {
                    Text("Start Typing")
                    Image(systemName: "return").font(.system(size: 13, weight: .bold)).opacity(0.8)
                }
            }
            .buttonStyle(PillButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            .padding(.top, 26).rise(shown, 0.34)
            Text("Open this again from the menu bar, or type “welcome”.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .padding(.top, 12).rise(shown, 0.38)
        }
        .padding(.horizontal, 44).padding(.top, 14).padding(.bottom, 26)
        .frame(width: 600)
        .background(alignment: .top) {
            // The accent as a soft light behind it, lighter on the left and deeper on the right.
            let strength = scheme == .dark ? 0.3 : 0.17
            ZStack {
                RadialGradient(colors: [.accent.opacity(strength), .clear], center: UnitPoint(x: 0.3, y: 0),
                               startRadius: 0, endRadius: 330)
                RadialGradient(colors: [.accentDeep.opacity(strength), .clear], center: UnitPoint(x: 0.72, y: 0.04),
                               startRadius: 0, endRadius: 300)
            }
            .frame(height: 440).ignoresSafeArea()
        }
        .background { Color.clear.modifier(GlassBackground(shape: Rectangle(), radius: 0)).ignoresSafeArea() }
        .onAppear { shown = true }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The launcher's field in small, saying which keys open it; once they've been pressed, that it worked.
private struct HotkeyPill: View {
    let keycaps: [String]
    let tried: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        HStack(spacing: 12) {
            BrandMark(height: 22)
            if tried {
                Text("That’s it. It opens over any app, and Esc puts it away.")
                Spacer(minLength: 8)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(LinearGradient.brand)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("Press")
                HStack(spacing: 5) { ForEach(keycaps, id: \.self) { BigKeycap(label: $0) } }
                Text("from any app to open it")
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
        .padding(.leading, 20).padding(.trailing, 18)
        .frame(height: 56)
        .background(Color.primary.opacity(0.035), in: Capsule())
        .overlay(Capsule().strokeBorder(LinearGradient.brand, lineWidth: 1.5))
        .animation(still ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.3), value: tried)
    }
}

/// A key on a keyboard, lit from above.
private struct BigKeycap: View {
    let label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 9).frame(minWidth: 30, minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.12) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 0.5, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let access: Permission.Access?
    let allow: () -> Void
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        Row(symbol: permission.symbol, title: permission.title, detail: permission.why,
            note: permission == .accessibility ? nil : "Optional") {
            switch access {
            case .granted:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(LinearGradient.brand)
                    Text("Allowed").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .denied:
                Button("Open Settings", action: allow).buttonStyle(PillButtonStyle())
            case .notAsked, nil:
                Button("Allow", action: allow).buttonStyle(PillButtonStyle())
                    .accessibilityLabel("Allow \(permission.title)")
            }
        }
        .animation(still ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.35), value: access)
    }
}

/// A glyph in a ring, a title and a line under it, and a control on the right.
private struct Row<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var note: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .overlay { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary) }
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    if let note { Text(note).font(.system(size: 11)).foregroundStyle(.tertiary) }
                }
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }
}

/// The rounded, faintly filled group the rows sit in.
private struct Tray: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

/// Capsule buttons: the icon's gradient for the main one, a quiet tint for the rest.
private struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View { Pill(configuration: configuration, prominent: prominent) }

    private struct Pill: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var still

        var body: some View {
            configuration.label
                .font(.system(size: prominent ? 15 : 12.5, weight: .semibold))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, prominent ? 30 : 14)
                .frame(height: prominent ? 44 : 28)
                .background {
                    if prominent {
                        Capsule().fill(LinearGradient.brand).brightness(hovering ? 0.06 : 0)
                            .shadow(color: .accent.opacity(0.35), radius: 14, y: 6)
                    } else {
                        Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0.06))
                            .overlay(Capsule().strokeBorder(Color.accent.opacity(0.3), lineWidth: 0.5))
                    }
                }
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed && !still ? 0.97 : 1)
                .animation(.spring(duration: 0.25), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// Fades and lifts into place `delay` seconds after `shown`; only fades with Reduce Motion on.
    fileprivate func rise(_ shown: Bool, _ delay: Double) -> some View { modifier(Rise(shown: shown, delay: delay)) }
}

private struct Rise: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var still

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || still ? 0 : 14)
            .animation(.spring(duration: 0.8, bounce: 0.25).delay(delay), value: shown)
    }
}
