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
/// `progress` gets the output so far, a few times a second, while it runs.
func runTool(_ tool: URL, _ arguments: [String], in folder: URL? = nil, input: String? = nil, mergeErrors: Bool = false,
             environment: [String: String]? = nil, timeout: TimeInterval = 15,
             progress: (@Sendable (String) async -> Void)? = nil) async -> ToolRun {
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
                return done.resume(returning: -1)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        }
    } onCancel: {
        if process.isRunning { process.terminate() }
    }
    watcher?.cancel()
    return ToolRun(output: read(out), errors: mergeErrors ? "" : read(err).trimmingCharacters(in: .whitespacesAndNewlines),
                   status: status, timedOut: Date.now.timeIntervalSince(start) >= timeout)
}
