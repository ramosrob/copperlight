import AppKit
import IOKit.ps
import SystemConfiguration

/// A process of yours listening on TCP ports, from `lsof`.
struct Listener: Equatable, Sendable {
    var pid: Int32
    var command: String
    var ports: [Int]
}

/// `lsof -F pcn` output: a `p` line per process, its `c`ommand, then an `n`ame per socket ("*:3000", "[::1]:3000").
func parseListeners(_ output: String) -> [Listener] {
    var listeners: [Listener] = []
    for line in output.split(separator: "\n") where !listeners.isEmpty || line.first == "p" {
        let value = line.dropFirst()
        switch line.first {
        case "p": if let pid = Int32(value) { listeners.append(Listener(pid: pid, command: "", ports: [])) }
        case "c": listeners[listeners.count - 1].command = String(value)
        case "n":
            if let port = value.split(separator: ":").last.flatMap({ Int($0) }), !listeners[listeners.count - 1].ports.contains(port) {
                listeners[listeners.count - 1].ports.append(port)
            }
        default: break
        }
    }
    return listeners.map { var listener = $0; listener.ports.sort(); return listener }
}

/// Asks `lsof`, which sees your own processes (another user's need sudo, and you couldn't end them anyway).
/// ponytail: blocks this (background) thread ~100 ms, per keystroke in the Port chip; cache it if that ever shows.
func listeningProcesses() -> [Listener] {
    let process = Process(), output = Pipe()
    process.executableURL = URL(filePath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile() // read before waiting, so a full pipe can't stall it
    process.waitUntilExit()
    return parseListeners(String(decoding: data, as: UTF8.self))
}

/// Ends a process the way `kill` does, asking it to quit (SIGTERM).
@MainActor func endProcess(_ pid: Int32, _ name: String) {
    guard kill(pid, SIGTERM) != 0 else { return }
    let error = errno
    notify("Couldn't end \(name)", error == EPERM ? "It belongs to another user" : String(cString: strerror(error)))
}

struct BatteryStatus: Equatable, Sendable {
    var percent: Int
    var charging: Bool
    var onPower: Bool
    var minutes: Int? = nil // to full while charging, else left; nil while macOS is still estimating
    var health: String? = nil
    var cycles: Int? = nil
}

/// "87%, charging, 1:05 to full", "87%, 3:12 left", "100%, charged".
func batteryTitle(_ battery: BatteryStatus) -> String {
    let time = battery.minutes.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
    let state: String? = if battery.charging { time.map { "charging, \($0) to full" } ?? "charging" }
        else if battery.onPower { battery.percent >= 100 ? "charged" : "on power, not charging" }
        else { time.map { "\($0) left" } }
    return (["\(battery.percent)%"] + (state.map { [$0] } ?? [])).joined(separator: ", ")
}

/// The internal battery, from IOKit's power sources; nil on a Mac without one.
func readBattery() -> BatteryStatus? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
        guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? Int, let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
        else { continue }
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
        return BatteryStatus(percent: current * 100 / max, charging: charging,
                             onPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                             minutes: minutes.flatMap { $0 > 0 ? $0 : nil }, health: description[kIOPSBatteryHealthKey] as? String,
                             cycles: batteryCycles())
    }
    return nil
}

private func batteryCycles() -> Int? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
}

struct VolumeSpace: Equatable, Sendable {
    var name: String
    var path: String
    var free: Int64
    var total: Int64
}

/// The startup disk and any others mounted, with the free space Finder shows (what macOS can free up counts).
func readVolumes() -> [VolumeSpace] {
    let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                     .volumeAvailableCapacityKey]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
    return urls.compactMap { url in
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return VolumeSpace(name: values.volumeLocalizedName ?? url.lastPathComponent, path: url.path,
                           free: values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0), total: Int64(total))
    }.sorted { ($0.path == "/" ? 0 : 1, $0.name) < ($1.path == "/" ? 0 : 1, $1.name) }
}

/// Not 169.254.x.x: a cable link with nothing to hand out addresses picks one itself, and it says nothing useful.
func isUsefulAddress(_ address: String) -> Bool { !address.hasPrefix("169.254.") }

/// The IPv4 address of each interface that's up, with the name System Settings gives it ("Wi-Fi").
func localAddresses() -> [(address: String, interface: String)] {
    var names: [String: String] = [:]
    for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
        if let bsd = SCNetworkInterfaceGetBSDName(interface), let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) {
            names[bsd as String] = name as String
        }
    }
    var first: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&first) == 0 else { return [] }
    defer { freeifaddrs(first) }
    var addresses: [(String, String)] = []
    for entry in sequence(first: first, next: { $0?.pointee.ifa_next }).compactMap(\.self).map(\.pointee) {
        let flags = Int32(entry.ifa_flags)
        guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
        else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
        let bsd = String(cString: entry.ifa_name)
        addresses.append((host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }, names[bsd] ?? bsd))
    }
    return addresses.filter { isUsefulAddress($0.0) }
}

/// What the internet sees this Mac as. Asks api.ipify.org (made for this, open source), and only when you press Enter.
func publicIP() async -> String? {
    let request = URLRequest(url: URL(string: "https://api.ipify.org")!, timeoutInterval: 8)
    guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return !ip.isEmpty && ip.count <= 45 && ip.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" }) ? ip : nil
}

/// `ip`, `battery`, `disk` and `port 3000`: the Mac's own numbers, typed by name. All read on this Mac, but the
/// public IP. `port` is a chip (Tab): what's listening on a port, or on any, and Enter ends it.
struct LookupProvider: ResultProvider {
    var battery: @Sendable () -> BatteryStatus? = readBattery
    var volumes: @Sendable () -> [VolumeSpace] = readVolumes
    var addresses: @Sendable () -> [(address: String, interface: String)] = localAddresses
    var listeners: @Sendable () -> [Listener] = listeningProcesses

    var modes: [Mode] { [Mode(prefix: "port ", title: "Port", icon: .symbol("network"), hint: "A port number, like 3000")] }

    func results(for query: String) async -> [LauncherResult] {
        let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "port" || lower.hasPrefix("port ") { return portRows(lower.dropFirst(4).trimmingCharacters(in: .whitespaces)) }
        if let start = startRow(query, keyword: "port", title: "Port", hint: "What’s listening on a port: port 3000", symbol: "network") {
            return [start]
        }
        if let score = named(lower, keyword: "ip", title: "IP Address") { return ipRows(score) }
        if let score = named(lower, keyword: "battery", title: "Battery", from: 4) { return [batteryRow(score)] }
        if let score = named(lower, keyword: "disk", title: "Disk Space") { return diskRows(score) }
        return []
    }

    /// 50, above apps, for the keyword: whole, or from `from` letters ("dis" is Discord's). Else its other names.
    private func named(_ lower: String, keyword: String, title: String, from: Int? = nil) -> Double? {
        if lower == keyword || (lower.count >= (from ?? keyword.count) && keyword.hasPrefix(lower)) { return 50 }
        return otherNameScore(lower, title)
    }

    private func ipRows(_ score: Double) -> [LauncherResult] {
        let local = addresses().enumerated().map { index, entry in
            LauncherResult(id: "ip:\(entry.address)", title: entry.address, subtitle: "Local IP · \(entry.interface)",
                           icon: .symbol("network"), score: score - Double(index) / 100, actionTitle: "Copy",
                           action: { copyToClipboard(entry.address) })
        }
        let lookUp = LauncherResult(
            id: "ip:public", title: "Public IP", subtitle: "Enter asks api.ipify.org", icon: .symbol("globe"),
            score: score - 0.5, actionTitle: "Look Up", action: {}, output: { _ in
                guard let ip = await publicIP() else {
                    return LauncherResult(id: "ip:public", title: "Couldn’t reach api.ipify.org", subtitle: "Offline, or something blocks it",
                                          icon: .symbol("exclamationmark.triangle"), score: .infinity, actionTitle: "", action: {})
                }
                return LauncherResult(id: "ip:public", title: ip, subtitle: "Public IP · from api.ipify.org", icon: .symbol("globe"),
                                      score: .infinity, actionTitle: "Copy", action: { copyToClipboard(ip) })
            })
        return local + [lookUp]
    }

    private func batteryRow(_ score: Double) -> LauncherResult {
        guard let battery = battery() else {
            return LauncherResult(id: "battery", title: "This Mac has no battery", icon: .symbol("powerplug"), score: score,
                                  actionTitle: "", action: {})
        }
        let details = ["Battery"] + [battery.health.map { "health \($0)" }, battery.cycles.map { "\($0) cycles" }].compactMap(\.self)
        let symbol = battery.charging ? "battery.100percent.bolt" : "battery.\([0, 25, 50, 75, 100].min { abs($0 - battery.percent) < abs($1 - battery.percent) }!)percent"
        return LauncherResult(id: "battery", title: batteryTitle(battery), subtitle: details.joined(separator: " · "), icon: .symbol(symbol),
                              score: score, actionTitle: "Open Settings", action: { settingsPage("com.apple.Battery-Settings.extension") })
    }

    private func diskRows(_ score: Double) -> [LauncherResult] {
        volumes().enumerated().map { index, volume in
            let used = Int((Double(volume.total - volume.free) / Double(volume.total) * 100).rounded())
            let size = { (bytes: Int64) in bytes.formatted(.byteCount(style: .file)) }
            let startup = volume.path == "/"
            return LauncherResult(
                id: "disk:\(volume.path)", title: "\(size(volume.free)) free of \(size(volume.total))", subtitle: "\(volume.name) · \(used)% used",
                icon: .file(volume.path), score: score - Double(index) / 100, actionTitle: startup ? "Open Storage" : "Open",
                action: {
                    if startup { settingsPage("com.apple.settings.Storage") } else { NSWorkspace.shared.open(URL(filePath: volume.path)) }
                })
        }
    }

    /// Every process listening, or those on ports starting with `filter` (`port 30`), or named like it (`port node`).
    private func portRows(_ filter: String) -> [LauncherResult] {
        let number = Int(filter) != nil
        let matching = listeners().filter { listener in
            filter.isEmpty || (number ? listener.ports.contains { String($0).hasPrefix(filter) } : fuzzyScore(filter, listener.command) != nil)
        }
        guard !matching.isEmpty else {
            return [LauncherResult(id: "port:none", title: number ? "Nothing is listening on port \(filter)" : "Nothing is listening",
                                   icon: .symbol("network"), score: 50, actionTitle: "", action: {})]
        }
        return matching.enumerated().map { index, listener in
            let port = number ? listener.ports.first { String($0).hasPrefix(filter) }! : listener.ports[0]
            let (pid, name) = (listener.pid, listener.command)
            return LauncherResult(
                id: "port:\(listener.command)", title: name,
                subtitle: "Listening on \(listener.ports.map(String.init).joined(separator: ", ")) · pid \(pid)",
                icon: NSRunningApplication(processIdentifier: pid)?.bundleURL.map { .file($0.path) } ?? .symbol("terminal"),
                score: 50 - Double(index) / 100, actionTitle: "End Process", action: { endProcess(pid, name) },
                confirm: "End \(name) (pid \(pid))? It’s listening on port \(port).")
        }
    }
}

@MainActor private func settingsPage(_ id: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(id)")!)
}
