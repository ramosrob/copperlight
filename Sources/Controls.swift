import AppKit
import CoreAudio
import CoreWLAN
import IOKit.hidsystem
import IOKit.pwr_mgt
import Synchronization

// MARK: Media

/// `:play`, `:next track`, `:previous track`: the keyboard's media keys, so they go to whatever is playing (Music,
/// a browser tab, Spotify), as the keys do. Posting them needs Accessibility, which pasting already asks for.
@MainActor func pressMediaKey(_ key: Int32) {
    guard hasAccessibility("control what's playing") else { return }
    for down in [true, false] {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                           subtype: 8, data1: Int(key) << 16 | (down ? 0xA : 0xB) << 8, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}

// MARK: Sound

struct SoundOutput: Sendable { let id: AudioObjectID, name: String }

private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

/// A fixed-size property of an audio object (the system, a device). nil if it hasn't one.
private func audioProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ empty: T) -> T? {
    var address = address(selector, scope), value = empty, size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
}

private func setAudioProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) -> Bool {
    var address = address(selector, scope), value = value
    return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
}

private let system = AudioObjectID(kAudioObjectSystemObject)

func currentOutput() -> AudioObjectID { audioProperty(system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0)) ?? 0 }

/// The outputs the Sound menu lists: speakers, headphones, displays, AirPlay.
func soundOutputs() -> [SoundOutput] {
    var address = address(kAudioHardwarePropertyDevices), size = UInt32(0)
    AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids)
    return ids.compactMap { id in
        guard audioProperty(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeOutput, UInt32(0)) == 1,
              let name = audioProperty(id, kAudioObjectPropertyName, Unmanaged<CFString>?.none)??
                .takeRetainedValue()
        else { return nil }
        return SoundOutput(id: id, name: name as String)
    }
}

/// `:output air`: a row per sound output, the one playing now first. Enter switches to it.
func outputRows(_ filter: String, outputs: [SoundOutput] = soundOutputs(), current: AudioObjectID = currentOutput()) -> [LauncherResult] {
    let ordered = outputs.filter { $0.id == current } + outputs.filter { $0.id != current }
    return ordered.enumerated().compactMap { index, output -> LauncherResult? in
        guard let score = filter.isEmpty ? -0.01 * Double(index) : fuzzyScore(filter, output.name) else { return nil }
        let id = output.id
        return LauncherResult(id: "output:\(output.name)", title: output.name, subtitle: id == current ? "Current output" : "",
                              icon: .symbol("hifispeaker"), score: score, actionTitle: "Switch", action: {
            if !setAudioProperty(system, kAudioHardwarePropertyDefaultOutputDevice, id) { NSSound.beep() }
        })
    }
}

func outputIsMuted() -> Bool {
    audioProperty(currentOutput(), kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, UInt32(0)) == 1
}

/// Displays and some interfaces can't be muted (their volume isn't the Mac's): a beep says so.
@MainActor func toggleMute() {
    if !setAudioProperty(currentOutput(), kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, UInt32(outputIsMuted() ? 0 : 1)) {
        NSSound.beep()
    }
}

// MARK: Wi-Fi

func wifiIsOn() -> Bool { CWWiFiClient.shared().interface()?.powerOn() ?? false }

@MainActor func toggleWiFi() {
    guard let wifi = CWWiFiClient.shared().interface() else { return NSSound.beep() }
    do { try wifi.setPower(!wifi.powerOn()) } catch { notify("Couldn't turn Wi-Fi \(wifi.powerOn() ? "off" : "on")", error.localizedDescription) }
}

// MARK: Keep awake

/// `:awake`: keeps the Mac and its displays awake until it's run again, or Copperlight quits (macOS lets go with it).
/// While it's on, a menu bar item says so; click it to stop, like the pomodoro's.
/// ponytail: no time limit (`:awake 2h`); add one if people forget it on.
@MainActor final class KeepAwake: NSObject {
    static let shared = KeepAwake()
    private nonisolated static let assertion = Mutex<IOPMAssertionID?>(nil)
    nonisolated static var isOn: Bool { assertion.withLock { $0 != nil } }
    private var item: NSStatusItem?

    func toggle() { Self.isOn ? stop() : start() }

    private func start() {
        var id = IOPMAssertionID(0)
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Keep Awake, from Copperlight" as CFString, &id) == kIOReturnSuccess
        else { return NSSound.beep() }
        Self.assertion.withLock { $0 = id }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Keeping Awake")
        let menu = NSMenu()
        menu.addItem(withTitle: "Stop Keeping Awake", action: #selector(stopFromMenu), keyEquivalent: "").target = self
        item.menu = menu
        self.item = item
    }

    private func stop() {
        if let id = Self.assertion.withLock({ id in defer { id = nil }; return id }) { IOPMAssertionRelease(id) }
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func stopFromMenu() { stop() }
}
