import AppKit
import Vision

/// What a picture of the screen holds: its lines of text, top to bottom and left to right, and what any QR code or
/// barcode in it says. Read on the Mac.
func readScreenshot(_ image: CGImage) -> (text: String, codes: [String]) {
    let text = VNRecognizeTextRequest()
    text.recognitionLevel = .accurate
    text.automaticallyDetectsLanguage = true
    let codes = VNDetectBarcodesRequest()
    try? VNImageRequestHandler(cgImage: image).perform([text, codes])
    // Vision's boxes start at the bottom: a higher line first, and on one line (half a line's height), the left one.
    let lines = (text.results ?? []).sorted { a, b in
        let (a, b) = (a.boundingBox, b.boundingBox)
        return abs(a.midY - b.midY) > min(a.height, b.height) / 2 ? a.midY > b.midY : a.minX < b.minX
    }
    return (lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"), (codes.results ?? []).compactMap(\.payloadStringValue))
}

/// `copy text`: drag over any part of the screen (a video, a picture, an error you can't select) and its text is
/// copied, read on the Mac. A QR code there is copied instead, and a link in one comes back in the launcher, Enter
/// opening it. Taking the picture needs the Screen Recording permission, asked for on the first use.
struct ScreenTextProvider: ResultProvider {
    /// Opens the launcher with this typed in.
    var show: @MainActor @Sendable (String) -> Void = { _ in }

    func results(for query: String) async -> [LauncherResult] {
        let lower = query.lowercased()
        let prefix = (lower.count >= 6 && "copy text from screen".hasPrefix(lower)) || (lower.count >= 4 && "text from screen".hasPrefix(lower))
        guard let score = prefix ? 50 : fuzzyScore(query, "Copy Text from Screen") ?? otherNameScore(query, "Copy Text from Screen")
        else { return [] }
        return [LauncherResult(id: "builtin:copy text", title: "Copy Text from Screen", subtitle: "Drag over anything to copy its text",
                               icon: .symbol("text.viewfinder"), score: score, actionTitle: "Select", action: { [show] in copyTextFromScreen(show: show) })]
    }
}

@MainActor private func copyTextFromScreen(show: @escaping @MainActor @Sendable (String) -> Void) {
    guard CGPreflightScreenCaptureAccess() else {
        CGRequestScreenCaptureAccess()
        return notify("Allow Copperlight to record the screen, then try again",
                      "Privacy & Security → Screen & System Audio Recording. Copperlight only reads the part you drag over.")
    }
    let file = FileManager.default.temporaryDirectory.appending(path: "copperlight-\(UUID().uuidString).png")
    Task {
        defer { try? FileManager.default.removeItem(at: file) }
        _ = await runTool(URL(filePath: "/usr/sbin/screencapture"), ["-i", "-x", file.path], timeout: 600) // -i: you drag, Esc cancels
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return } // cancelled
        let (text, codes) = await Task.detached { readScreenshot(image) }.value
        if let code = codes.first {
            copyToClipboard(code)
            return code.hasPrefix("http://") || code.hasPrefix("https://") ? show(code) : notify("QR code copied", oneLine(code))
        }
        guard !text.isEmpty else { return notify("No text there") }
        copyToClipboard(text)
        notify("Text copied", oneLine(text))
    }
}
