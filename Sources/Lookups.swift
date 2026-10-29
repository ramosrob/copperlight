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

/// A process of yours and what it's using, from `ps`.
struct ProcessUsage: Equatable, Sendable {
    var pid: Int32
    var cpu: Double // percent of one core, recent, as Activity Monitor shows it
    var memory: Int64 // resident, in bytes
    var path: String // its executable, or its name alone
    var name: String { (path as NSString).lastPathComponent }
    /// The app it belongs to: the outermost .app in its path (a Chrome Helper is Chrome's).
    var app: String? { path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" } }
    /// The app itself rather than a helper inside it: quitting it lets it ask to save.
    var isApp: Bool { app.map { path == "\($0)/Contents/MacOS/\(name)" } ?? false }
}

/// `ps -o pid=,pcpu=,rss=,comm=` output: the path, last, may have spaces.
func parseProcesses(_ output: String) -> [ProcessUsage] {
    output.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 3)
        guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let kilobytes = Int64(parts[2]) else { return nil }
        return ProcessUsage(pid: pid, cpu: cpu, memory: kilobytes * 1024, path: parts[3].trimmingCharacters(in: .whitespaces))
    }
}

/// Your processes but Copperlight, from `ps` (another user's you couldn't end anyway). Quick enough for every keystroke.
func readProcesses() -> [ProcessUsage] {
    let process = Process(), output = Pipe()
    process.executableURL = URL(filePath: "/bin/ps")
    process.arguments = ["-x", "-U", String(getuid()), "-o", "pid=,pcpu=,rss=,comm="]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile() // read before waiting, so a full pipe can't stall it
    process.waitUntilExit()
    // Not ps itself, nor Copperlight, busy for a moment each time it opens.
    return parseProcesses(String(decoding: data, as: UTF8.self)).filter { $0.pid != process.processIdentifier && $0.pid != getpid() }
}

/// Ends a process the way `kill` does, asking it to quit (SIGTERM).
@MainActor func endProcess(_ pid: Int32, _ name: String) {
    guard kill(pid, SIGTERM) != 0 else { return }
    let error = errno
    notify("Couldn't end \(name)", error == EPERM ? "It belongs to another user" : String(cString: strerror(error)))
}

/// What `networkQuality` measured: download and upload in bits a second, latency idle and under load in milliseconds.
struct SpeedTest: Equatable, Sendable {
    var down: Double, up: Double
    var idle: Double, loaded: Double
    var connection: String // "Wi-Fi", "Ethernet", "Cellular", or the interface's name
}

/// `networkQuality -c` output. Its responsiveness is in round trips a minute (RPM): 60 000 / RPM is the latency, in
/// milliseconds, while the line is busy.
func parseSpeedTest(_ json: String) -> SpeedTest? {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
          let down = object["dl_throughput"] as? Double, let up = object["ul_throughput"] as? Double,
          let idle = object["base_rtt"] as? Double, let rpm = object["responsiveness"] as? Double, rpm > 0
    else { return nil }
    // Per sample, how it was connected: the most common.
    let types = ((object["other"] as? [String: Any])?["interface-type"] as? [String: Int]) ?? [:]
    let connection = switch types.max(by: { $0.value < $1.value })?.key {
    case "wifi": "Wi-Fi"
    case "wiredEthernet": "Ethernet"
    case "cellular": "Cellular"
    default: object["interface_name"] as? String ?? "Network"
    }
    return SpeedTest(down: down, up: up, idle: idle, loaded: 60_000 / rpm, connection: connection)
}

/// "328 Mbps", "1.25 Gbps", "850 Kbps", "4.2 Mbps".
func speedText(_ bitsPerSecond: Double) -> String {
    if bitsPerSecond >= 1e9 { return formatNumber(bitsPerSecond / 1e9, decimals: 0...2) + " Gbps" }
    if bitsPerSecond >= 1e6 { return formatNumber(bitsPerSecond / 1e6, decimals: bitsPerSecond < 1e7 ? 0...1 : 0...0) + " Mbps" }
    return formatNumber(bitsPerSecond / 1e3, decimals: 0...0) + " Kbps"
}

/// The result row's title and subtitle.
func speedSummary(_ test: SpeedTest) -> (title: String, subtitle: String) {
    ("\(speedText(test.down)) down · \(speedText(test.up)) up",
     "Latency \(Int(test.idle.rounded())) ms, \(Int(test.loaded.rounded())) ms under load · \(test.connection)")
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

/// `ip`, `battery`, `disk`, `port 3000`, `cpu`, `memory` and `speed`: the Mac's own numbers, typed by name. All read on
/// this Mac, but the public IP and the speed test, on Enter. `port` is a chip (Tab): what's listening on a port, or on any, and Enter ends it. `cpu` and
/// `memory` list your processes, the busiest first, and Enter ends one (an app quits); their chips list them all.
struct LookupProvider: ResultProvider {
    var battery: @Sendable () -> BatteryStatus? = readBattery
    var volumes: @Sendable () -> [VolumeSpace] = readVolumes
    var addresses: @Sendable () -> [(address: String, interface: String)] = localAddresses
    var listeners: @Sendable () -> [Listener] = listeningProcesses
    var processes: @Sendable () -> [ProcessUsage] = readProcesses

    var modes: [Mode] {
        [Mode(prefix: "port ", title: "Port", icon: .symbol("network"), hint: "A port number, like 3000"),
         Mode(prefix: "cpu ", title: "Processes by CPU", icon: .symbol("cpu"), hint: "A name, or nothing for all"),
         Mode(prefix: "memory ", title: "Processes by Memory", icon: .symbol("memorychip"), hint: "A name, or nothing for all")]
    }

    /// In the CPU and Memory chips, every process; typed without them, the 8 busiest.
    func modeResults(for query: String) async -> [LauncherResult] { await results(for: query, limit: 100) }

    func results(for query: String) async -> [LauncherResult] { await results(for: query, limit: 8) }

    private func results(for query: String, limit: Int) async -> [LauncherResult] {
        let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
        for (keyword, byMemory) in [("cpu", false), ("memory", true)] where lower == keyword || lower.hasPrefix(keyword + " ") {
            return processRows(lower.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces), byMemory: byMemory, limit: limit)
        }
        if let start = startRow(query, keyword: "memory", title: "Processes by Memory", hint: "What’s using memory, the most first", symbol: "memorychip")
            ?? startRow(query, keyword: "cpu", title: "Processes by CPU", hint: "What’s using the processor, the busiest first", symbol: "cpu") {
            return [start]
        }
        if lower == "port" || lower.hasPrefix("port ") { return portRows(lower.dropFirst(4).trimmingCharacters(in: .whitespaces)) }
        if let start = startRow(query, keyword: "port", title: "Port", hint: "What’s listening on a port: port 3000", symbol: "network") {
            return [start]
        }
        if let score = named(lower, keyword: "ip", title: "IP Address") { return ipRows(score) }
        if let score = named(lower, keyword: "battery", title: "Battery", from: 4) { return [batteryRow(score)] }
        if let score = named(lower, keyword: "disk", title: "Disk Space") { return diskRows(score) }
        if let score = named(lower, keyword: "speed", title: "Test Internet Speed", from: 5) { return [speedRow(score)] }
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

    /// `speed`: Enter runs macOS's own `networkQuality` (about 20 seconds, against Apple's servers), the time so far
    /// ticking on the row; Esc stops it. Then download, upload and latency, idle and under load; Enter copies them.
    private func speedRow(_ score: Double) -> LauncherResult {
        LauncherResult(id: "speed", title: "Test Internet Speed", subtitle: "Download, upload and latency, with Apple’s servers",
                       icon: .symbol("speedometer"), score: score, actionTitle: "Test", action: {}, output: { progress in
            let started = Date.now
            let ticker = Task {
                while !Task.isCancelled {
                    await progress(LauncherResult(id: "speed", title: "Testing internet speed…", subtitle: "\(Int(Date.now.timeIntervalSince(started))) s · Esc stops it",
                                                  icon: .symbol("speedometer"), score: .infinity, actionTitle: "", action: {}))
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            let run = await runTool(URL(filePath: "/usr/bin/networkQuality"), ["-c"], timeout: 90)
            ticker.cancel()
            await ticker.value // its last "Testing…" lands before the result, not over it
            guard let test = parseSpeedTest(run.output) else {
                return LauncherResult(id: "speed", title: "Couldn’t test the speed", subtitle: "Offline, or Apple’s servers didn’t answer",
                                      icon: .symbol("exclamationmark.triangle"), score: .infinity, actionTitle: "", action: {})
            }
            let (title, subtitle) = speedSummary(test)
            return LauncherResult(id: "speed", title: title, subtitle: subtitle, icon: .symbol("speedometer"), score: .infinity,
                                  actionTitle: "Copy", action: { copyToClipboard("\(title) · \(subtitle)") })
        })
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

    /// Your processes named with `filter`'s words, the busiest first by CPU or by memory. Enter ends one, after asking;
    /// an app (not a helper inside one) quits instead, so it can ask to save.
    private func processRows(_ filter: String, byMemory: Bool, limit: Int) -> [LauncherResult] {
        let words = typedWords(filter)
        let found = processes().filter { process in words.allSatisfy { wordStarts(process.name).contains($0) } }
            .sorted { byMemory ? $0.memory > $1.memory : $0.cpu > $1.cpu }.prefix(limit)
        guard !found.isEmpty else {
            return [LauncherResult(id: "process:none", title: "No process named “\(filter)”", icon: .symbol("cpu"), score: 50,
                                   actionTitle: "", action: {})]
        }
        return found.enumerated().map { index, process in
            let cpu = "\(formatNumber(process.cpu, decimals: 1...1))% CPU", memory = process.memory.formatted(.byteCount(style: .memory))
            let (pid, name, isApp) = (process.pid, process.name, process.isApp)
            return LauncherResult(
                id: "process:\(pid)", title: name, subtitle: (byMemory ? [memory, cpu] : [cpu, memory]).joined(separator: " · ") + " · pid \(pid)",
                icon: process.app.map { .file($0) } ?? .symbol("gearshape"), score: 50 - Double(index) / 1000,
                actionTitle: isApp ? "Quit" : "End Process", action: {
                    if isApp, let app = NSRunningApplication(processIdentifier: pid) { app.terminate() } else { endProcess(pid, name) }
                }, confirm: isApp ? "Quit \(name)?" : "End \(name) (pid \(pid))?")
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
