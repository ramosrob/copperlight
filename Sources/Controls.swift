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
private func audioProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ empty: T) -> T? {
    var address = address(selector, scope), value = empty, size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
}

private func setAudioProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
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

func currentInput() -> AudioObjectID { audioProperty(system, kAudioHardwarePropertyDefaultInputDevice, AudioObjectID(0)) ?? 0 }

/// The microphone's level before `:mute mic` set it to 0, for one with no mute control (many built-in ones).
private let micLevelBeforeMute = Mutex<Float32?>(nil)

func micIsMuted() -> Bool {
    audioProperty(currentInput(), kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput, UInt32(0)) == 1
        || micLevelBeforeMute.withLock { $0 != nil }
}

/// `:mute mic`: the input device's mute; for a mic without one, its input level to 0 and back. A beep if neither works.
@MainActor func toggleMicMute() {
    let mic = currentInput(), input = kAudioObjectPropertyScopeInput
    if let before = micLevelBeforeMute.withLock({ $0 }) {
        if setAudioProperty(mic, kAudioDevicePropertyVolumeScalar, scope: input, before) { micLevelBeforeMute.withLock { $0 = nil } } else { NSSound.beep() }
        return
    }
    let muted = audioProperty(mic, kAudioDevicePropertyMute, scope: input, UInt32(0))
    if let muted, setAudioProperty(mic, kAudioDevicePropertyMute, scope: input, UInt32(muted == 1 ? 0 : 1)) { return }
    if let level = audioProperty(mic, kAudioDevicePropertyVolumeScalar, scope: input, Float32(0)),
       setAudioProperty(mic, kAudioDevicePropertyVolumeScalar, scope: input, Float32(0)) {
        return micLevelBeforeMute.withLock { $0 = level }
    }
    NSSound.beep()
}

// MARK: Wi-Fi

func wifiIsOn() -> Bool { CWWiFiClient.shared().interface()?.powerOn() ?? false }

@MainActor func toggleWiFi() {
    guard let wifi = CWWiFiClient.shared().interface() else { return NSSound.beep() }
    do { try wifi.setPower(!wifi.powerOn()) } catch { notify("Couldn't turn Wi-Fi \(wifi.powerOn() ? "off" : "on")", error.localizedDescription) }
}

// MARK: Keep awake

/// `:awake`: keeps the Mac and its displays awake until it's run again, or Copperlight quits (macOS lets go with it);
/// `:awake 2h`, `:awake until 18:00` for a while, after which it lets go by itself. While it's on, a menu bar item says
/// so (click it to stop, like the pomodoro's), and the empty launcher lists it with what's running.
@MainActor final class KeepAwake: NSObject {
    static let shared = KeepAwake()
    private nonisolated static let assertion = Mutex<IOPMAssertionID?>(nil)
    nonisolated static var isOn: Bool { assertion.withLock { $0 != nil } }
    /// When it lets go by itself; nil: when you stop it.
    private(set) var until: Date?
    private var item: NSStatusItem?
    private var ending: Task<Void, Never>?

    func toggle() { Self.isOn ? stop() : start() }

    /// On, until `deadline` (nil: until stopped). Already on, it keeps going until the new deadline instead.
    func start(until deadline: Date? = nil) {
        if !Self.isOn {
            var id = IOPMAssertionID(0)
            guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              "Keep Awake, from Copperlight" as CFString, &id) == kIOReturnSuccess
            else { return NSSound.beep() }
            Self.assertion.withLock { $0 = id }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Keeping Awake")
            self.item = item
        }
        until = deadline
        ending?.cancel()
        ending = deadline.map { deadline in
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) // a continuous clock: sleep counts
                if !Task.isCancelled { self?.stop() }
            }
        }
        let menu = NSMenu()
        if let deadline { menu.addItem(withTitle: "Awake until \(deadline.formatted(date: .omitted, time: .shortened))", action: nil, keyEquivalent: "") }
        menu.addItem(withTitle: "Stop Keeping Awake", action: #selector(stopFromMenu), keyEquivalent: "").target = self
        item?.menu = menu
    }

    func stop() {
        if let id = Self.assertion.withLock({ id in defer { id = nil }; return id }) { IOPMAssertionRelease(id) }
        if let item { NSStatusBar.system.removeStatusItem(item) }
        (item, until) = (nil, nil)
        ending?.cancel()
    }

    @objc private func stopFromMenu() { stop() }
}

/// What follows `:awake`: a length (`2h`, `90 min`, `30`, a bare number being minutes) or a time of day (`until 18:00`,
/// `till 6pm`), as `timer` reads them; "for" before a length is fine. nil for anything else.
func awakeDeadline(_ text: String, now: Date = .now) -> Date? {
    var text = text.trimmingCharacters(in: .whitespaces)
    if text.lowercased().hasPrefix("for ") { text.removeFirst(4) }
    return switch parseTimer(text) {
    case .start(let seconds, let label) where label.isEmpty: now + TimeInterval(seconds)
    case .until(let hour, let minute, let label) where label.isEmpty: nextTime(hour: hour, minute: minute, after: now)
    default: nil
    }
}

/// `:awake` rows: on (or off) first, so Enter still toggles it, then an hour or two; with a time typed, for that long.
@MainActor func awakeRows(_ text: String, now: Date = .now) -> [LauncherResult] {
    let at = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
    let row = { (title: String, subtitle: String, deadline: Date?, score: Double) in
        LauncherResult(id: "awake:\(title)", title: title, subtitle: subtitle, icon: .symbol("sun.max"), score: score, actionTitle: "Run",
                       action: { KeepAwake.shared.start(until: deadline) })
    }
    guard text.isEmpty else {
        guard let deadline = awakeDeadline(text, now: now) else {
            return [LauncherResult(id: "awake:hint", title: "Keep Awake for a while", subtitle: "Type how long: 2h, 90 min, until 18:00",
                                   icon: .symbol("sun.max"), score: 1, actionTitle: "", action: {})]
        }
        let seconds = Int(deadline.timeIntervalSince(now).rounded())
        let atTime = text.lowercased().firstMatch(of: #/^(until|till|til|at)\b/#) != nil // a time of day, not a length
        return [atTime ? row("Keep Awake until \(at(deadline))", "For \(timerLength(seconds / 60 * 60))", deadline, 1)
                          : row("Keep Awake for \(timerLength(seconds))", "Until \(at(deadline))", deadline, 1)]
    }
    let toggle = KeepAwake.isOn
        ? LauncherResult(id: "awake:toggle", title: "Stop Keeping Awake", subtitle: KeepAwake.shared.until.map { "Awake until \(at($0))" } ?? "Awake until you stop it",
                         icon: .symbol("sun.max"), score: 2, actionTitle: "Run", action: { KeepAwake.shared.stop() },
                         ticking: KeepAwake.shared.until.map { .down(to: $0) })
        : row("Keep Awake", "Until you stop it", nil, 2)
    return [toggle] + [3600, 7200].enumerated().map { index, seconds in
        row("Keep Awake for \(timerLength(seconds))", "Until \(at(now + TimeInterval(seconds)))", now + TimeInterval(seconds), 1 - Double(index) / 100)
    }
}
