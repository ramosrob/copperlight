import AppKit

/// Every emoji macOS names (flags and people combinations too), with the emoji picker's English names, shortest first.
/// ponytail: a private framework's resource; if an update moves it, emoji search finds nothing (a test checks it's there).
let emojiNamesFile = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Resources/en.lproj/AppleName.strings"
let emojiNames: [(emoji: String, name: String)] = {
    let names = NSDictionary(contentsOf: URL(filePath: emojiNamesFile)) as? [String: String] ?? [:]
    return names.map { ($0.key, $0.value) }.sorted { ($0.name.count, $0.name) < ($1.name.count, $1.name) }
}()

/// The emoji whose names have a word starting with each word of `words` ("party pop" → 🎉), up to `limit`.
func emojiMatches(_ words: String, limit: Int = 30) -> [(emoji: String, name: String)] {
    let wanted = words.lowercased().split(whereSeparator: \.isWhitespace)
    guard !wanted.isEmpty else { return [] }
    return Array(emojiNames.lazy.filter { _, name in
        let parts = name.lowercased().split { $0 == " " || $0 == "-" || $0 == ":" || $0 == "," }
        return wanted.allSatisfy { word in parts.contains { $0.hasPrefix(word) } }
    }.prefix(limit))
}

/// `emoji party`: emoji by name. Enter pastes it into the app you were in (copies it without Accessibility).
/// `emo` alone (from 3 letters) offers to start a search.
struct EmojiProvider: ResultProvider {
    var modes: [Mode] { [Mode(prefix: "emoji ", title: "Emoji", icon: .symbol("face.smiling"), hint: "A word for one: party")] }

    func results(for query: String) -> [LauncherResult] {
        if let start = startRow(query, keyword: "emoji", title: "Emoji", hint: "Type a word for one: emoji party", symbol: "face.smiling") {
            return [start]
        }
        guard query.lowercased().hasPrefix("emoji ") else { return [] }
        return emojiMatches(String(query.dropFirst(6))).enumerated().map { index, match in
            let emoji = match.emoji
            return LauncherResult(id: "emoji:\(emoji)", title: match.name.prefix(1).uppercased() + match.name.dropFirst(),
                                  icon: .image("emoji:\(emoji)", { emojiImage(emoji) }), score: 50 - Double(index) / 100,
                                  actionTitle: "Paste", action: {
                copyToClipboard(emoji)
                if hasAccessibility("paste emoji") { sendPaste() }
            })
        }
    }
}

/// The emoji drawn 32 pt square at 2x, for the row's icon.
private func emojiImage(_ emoji: String) -> CGImage? {
    let side = 64
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 50, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: [.font: font]))
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
    context.textPosition = CGPoint(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - ascent - descent) / 2 + descent)
    CTLineDraw(line, context)
    return context.makeImage()
}
