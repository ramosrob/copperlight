import Foundation

/// What a tool printed: stdout as it was (leading spaces can matter), stderr trimmed, and how
/// it ended.
struct ToolRun: Sendable {
    var output: String
    var errors: String
    var status: Int32
    var timedOut = false

    var succeeded: Bool { status == 0 && !timedOut }
    /// The last lines of stderr (or stdout), for a notification or an error row.
    var message: String {
        let text = errors.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : errors
        return text.split(separator: "\n").suffix(3).joined(separator: "\n")
    }
}

/// Runs `tool` with `arguments` directly (no shell, so no quoting), in `folder`, off the main thread. Stopped after
/// `timeout` seconds, or when the calling task is cancelled (a new keystroke, Esc).
/// `input` goes to its stdin; `mergeErrors` puts stderr in `output`, interleaved as a terminal shows them;
/// `progress` gets the output so far, a few times a second, while it runs. `terminal`: its output goes to a terminal
/// instead (copied into `output`), for a tool that shows its progress only to one (networkQuality's speeds so far);
/// stderr goes there too.
func runTool(_ tool: URL, _ arguments: [String], in folder: URL? = nil, input: String? = nil, mergeErrors: Bool = false,
             environment: [String: String]? = nil, timeout: TimeInterval = 15,
             terminal: Bool = false, progress: (@Sendable (String) async -> Void)? = nil) async -> ToolRun {
    // Files, not pipes: a big diff can't fill a pipe and stall the tool, and a background child can't hold it open.
    let base = FileManager.default.temporaryDirectory.appending(path: "copperlight-\(UUID().uuidString)")
    let (out, err, inFile) = (base.appendingPathExtension("out"), base.appendingPathExtension("err"), base.appendingPathExtension("in"))
    for file in [out, err] { FileManager.default.createFile(atPath: file.path, contents: nil) }
    FileManager.default.createFile(atPath: inFile.path, contents: Data((input ?? "").utf8))
    defer { for file in [out, err, inFile] { try? FileManager.default.removeItem(at: file) } }
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    process.currentDirectoryURL = folder ?? .homeDirectory
    if let environment { process.environment = environment }
    process.standardInput = input == nil ? FileHandle.nullDevice : try? FileHandle(forReadingFrom: inFile)
    let output = try? FileHandle(forWritingTo: out)
    process.standardOutput = output
    process.standardError = mergeErrors ? output : try? FileHandle(forWritingTo: err)
    var master: Int32 = -1, slave: Int32 = -1
    let inTerminal = terminal && openpty(&master, &slave, nil, nil, nil) == 0
    let (masterFD, slaveFD) = (master, slave), copied = DispatchGroup()
    if inTerminal {
        process.standardOutput = FileHandle(fileDescriptor: slaveFD)
        process.standardError = process.standardOutput
    }
    /// What it shows the terminal, into the file: until it closes its end, or has ended and nothing more comes (a
    /// child of its own can hold the end open).
    let copyFromTerminal = { @Sendable in
        copied.enter()
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 4096), ready = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
            while true {
                let polled = poll(&ready, 1, 250)
                if polled > 0 {
                    let count = read(masterFD, &buffer, buffer.count)
                    if count <= 0 { break }
                    try? output?.write(contentsOf: Data(buffer[..<count]))
                } else if polled < 0 || !process.isRunning { break }
            }
            close(masterFD)
            copied.leave()
        }
    }
    let read = { @Sendable (file: URL) in String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self) }
    let watcher = progress.map { progress in
        Task {
            var seen = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                if size != seen, !Task.isCancelled {
                    seen = size
                    await progress(read(out))
                }
            }
        }
    }
    let start = Date.now
    let status: Int32 = await withTaskCancellationHandler {
        await withCheckedContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            guard !Task.isCancelled, (try? process.run()) != nil else {
                process.terminationHandler = nil
                if inTerminal { (close(masterFD), close(slaveFD)) }
                return done.resume(returning: -1)
            }
            if inTerminal {
                close(slaveFD) // its end is the tool's alone now: closed when it ends
                copyFromTerminal()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        }
    } onCancel: {
        if process.isRunning { process.terminate() }
    }
    await withCheckedContinuation { done in copied.notify(queue: .global()) { done.resume() } }
    watcher?.cancel()
    await watcher?.value // its last progress lands before the result, not over it
    return ToolRun(output: read(out), errors: mergeErrors ? "" : read(err).trimmingCharacters(in: .whitespacesAndNewlines),
                   status: status, timedOut: Date.now.timeIntervalSince(start) >= timeout)
}
