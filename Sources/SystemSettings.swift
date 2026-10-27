import AppKit

/// A System Settings page: its name in the sidebar, its extension id (`x-apple.systempreferences:<id>` opens it),
/// a symbol, and other words people search it by.
struct SettingsPage: Sendable {
    let title: String, id: String, symbol: String
    var keywords: [String] = []
}

/// ponytail: ids as of macOS 26 (/System/Library/ExtensionKit/Extensions); a renamed one opens System Settings
/// where it was. Pages with no extension of their own (General) aren't listed.
let settingsPages = [
    SettingsPage(title: "Wi-Fi", id: "com.apple.wifi-settings-extension", symbol: "wifi", keywords: ["wireless"]),
    SettingsPage(title: "Bluetooth", id: "com.apple.BluetoothSettings", symbol: "antenna.radiowaves.left.and.right"),
    SettingsPage(title: "Network", id: "com.apple.Network-Settings.extension", symbol: "network", keywords: ["ethernet", "firewall", "proxy"]),
    SettingsPage(title: "VPN", id: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", symbol: "lock.shield"),
    SettingsPage(title: "Notifications", id: "com.apple.Notifications-Settings.extension", symbol: "bell.badge"),
    SettingsPage(title: "Sound", id: "com.apple.Sound-Settings.extension", symbol: "speaker.wave.2",
                 keywords: ["audio", "output", "input", "microphone", "alert sound"]),
    SettingsPage(title: "Focus", id: "com.apple.Focus-Settings.extension", symbol: "moon", keywords: ["do not disturb"]),
    SettingsPage(title: "Screen Time", id: "com.apple.Screen-Time-Settings.extension", symbol: "hourglass"),
    SettingsPage(title: "About This Mac", id: "com.apple.SystemProfiler.AboutExtension", symbol: "info.circle",
                 keywords: ["serial number", "macos version"]),
    SettingsPage(title: "Software Update", id: "com.apple.Software-Update-Settings.extension", symbol: "arrow.down.circle",
                 keywords: ["upgrade"]),
    SettingsPage(title: "Storage", id: "com.apple.settings.Storage", symbol: "internaldrive", keywords: ["disk space"]),
    SettingsPage(title: "AirDrop & Handoff", id: "com.apple.AirDrop-Handoff-Settings.extension", symbol: "dot.radiowaves.up.forward",
                 keywords: ["airplay receiver"]),
    SettingsPage(title: "Login Items & Extensions", id: "com.apple.LoginItems-Settings.extension", symbol: "power",
                 keywords: ["startup items"]),
    SettingsPage(title: "Language & Region", id: "com.apple.Localization-Settings.extension", symbol: "globe",
                 keywords: ["locale", "date format"]),
    SettingsPage(title: "Date & Time", id: "com.apple.Date-Time-Settings.extension", symbol: "clock", keywords: ["time zone", "clock"]),
    SettingsPage(title: "Sharing", id: "com.apple.Sharing-Settings.extension", symbol: "person.2.wave.2",
                 keywords: ["file sharing", "screen sharing", "remote login", "ssh", "computer name"]),
    SettingsPage(title: "Time Machine", id: "com.apple.Time-Machine-Settings.extension", symbol: "clock.arrow.circlepath", keywords: ["backup"]),
    SettingsPage(title: "Transfer or Reset", id: "com.apple.Transfer-Reset-Settings.extension", symbol: "arrow.counterclockwise",
                 keywords: ["erase"]),
    SettingsPage(title: "Startup Disk", id: "com.apple.Startup-Disk-Settings.extension", symbol: "internaldrive"),
    SettingsPage(title: "Device Management", id: "com.apple.Profiles-Settings.extension", symbol: "checkmark.seal", keywords: ["profiles"]),
    SettingsPage(title: "Appearance", id: "com.apple.Appearance-Settings.extension", symbol: "circle.lefthalf.filled",
                 keywords: ["dark mode", "light mode", "accent color", "theme"]),
    SettingsPage(title: "Accessibility", id: "com.apple.Accessibility-Settings.extension", symbol: "accessibility",
                 keywords: ["voiceover", "zoom", "reduce motion"]),
    SettingsPage(title: "Control Center", id: "com.apple.ControlCenter-Settings.extension", symbol: "switch.2", keywords: ["menu bar"]),
    SettingsPage(title: "Apple Intelligence & Siri", id: "com.apple.Siri-Settings.extension", symbol: "sparkles"),
    SettingsPage(title: "Spotlight", id: "com.apple.Spotlight-Settings.extension", symbol: "magnifyingglass"),
    SettingsPage(title: "Privacy & Security", id: "com.apple.settings.PrivacySecurity.extension", symbol: "hand.raised",
                 keywords: ["permissions", "full disk access", "filevault", "location services"]),
    SettingsPage(title: "Desktop & Dock", id: "com.apple.Desktop-Settings.extension", symbol: "dock.rectangle",
                 keywords: ["dock", "mission control", "stage manager", "hot corners", "default browser", "widgets"]),
    SettingsPage(title: "Displays", id: "com.apple.Displays-Settings.extension", symbol: "display",
                 keywords: ["monitor", "resolution", "night shift", "brightness"]),
    SettingsPage(title: "Wallpaper", id: "com.apple.Wallpaper-Settings.extension", symbol: "photo", keywords: ["background"]),
    SettingsPage(title: "Battery", id: "com.apple.Battery-Settings.extension", symbol: "battery.75percent",
                 keywords: ["energy", "low power mode"]),
    SettingsPage(title: "Lock Screen", id: "com.apple.Lock-Screen-Settings.extension", symbol: "lock", keywords: ["screen saver"]),
    SettingsPage(title: "Touch ID & Password", id: "com.apple.Touch-ID-Settings.extension", symbol: "touchid",
                 keywords: ["fingerprint", "login password"]),
    SettingsPage(title: "Users & Groups", id: "com.apple.Users-Groups-Settings.extension", symbol: "person.2", keywords: ["guest user"]),
    SettingsPage(title: "Internet Accounts", id: "com.apple.Internet-Accounts-Settings.extension", symbol: "at",
                 keywords: ["mail accounts", "google account"]),
    SettingsPage(title: "Apple Account", id: "com.apple.systempreferences.AppleIDSettings", symbol: "person.crop.circle",
                 keywords: ["icloud", "apple id"]),
    SettingsPage(title: "Family", id: "com.apple.Family-Settings.extension", symbol: "person.3"),
    SettingsPage(title: "Game Center", id: "com.apple.Game-Center-Settings.extension", symbol: "gamecontroller"),
    SettingsPage(title: "Game Controllers", id: "com.apple.Game-Controller-Settings.extension", symbol: "gamecontroller"),
    SettingsPage(title: "Wallet & Apple Pay", id: "com.apple.WalletSettingsExtension", symbol: "wallet.pass"),
    SettingsPage(title: "Keyboard", id: "com.apple.Keyboard-Settings.extension", symbol: "keyboard",
                 keywords: ["keyboard shortcuts", "input sources", "dictation", "key repeat"]),
    SettingsPage(title: "Mouse", id: "com.apple.Mouse-Settings.extension", symbol: "computermouse", keywords: ["scroll direction"]),
    SettingsPage(title: "Trackpad", id: "com.apple.Trackpad-Settings.extension", symbol: "rectangle.and.hand.point.up.left",
                 keywords: ["gestures", "tap to click"]),
    SettingsPage(title: "Printers & Scanners", id: "com.apple.Print-Scan-Settings.extension", symbol: "printer"),
]

/// `bluetooth`, `dark mode`, `night shift`: a System Settings page by its name or a word for what's on it (from its
/// start), from 3 letters. Ranked like apps, but only close matches: "note" isn't a scattered n-o-t-e in Control Center.
struct SettingsProvider: ResultProvider {
    func results(for query: String) -> [LauncherResult] {
        guard query.count >= 3 else { return [] }
        let lower = query.lowercased()
        return settingsPages.compactMap { page in
            guard let score = fuzzyScore(query, page.title).flatMap({ $0 >= 0.6 ? $0 : nil })
                ?? (page.keywords.contains { $0.hasPrefix(lower) } ? 0.9 : nil)
            else { return nil }
            let url = URL(string: "x-apple.systempreferences:\(page.id)")!
            return LauncherResult(id: "settings:\(page.id)", title: page.title, subtitle: "System Settings",
                                  icon: .symbol(page.symbol), score: score, action: { NSWorkspace.shared.open(url) })
        }
    }
}
