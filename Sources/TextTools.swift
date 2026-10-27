import AppKit
import CryptoKit

/// A text tool, found by name (`json`, `upper hello`). It works on the text typed after its name, or on
/// the clipboard when there's none. Enter copies the result; the `paste` ones paste it.
struct TextTool: Sendable {
    let name: String, title: String, icon: String
    var pastes = false
}

/// Longest names first, so "json min" is found before "json".
let textTools = [
    TextTool(name: "paste markdown", title: "Paste as Markdown", icon: "doc.richtext", pastes: true),
    TextTool(name: "paste plain", title: "Paste as Plain Text", icon: "doc.plaintext", pastes: true),
    TextTool(name: "b64 decode", title: "Base64 Decode", icon: "lock.open"),
    TextTool(name: "url encode", title: "URL Encode", icon: "link"),
    TextTool(name: "url decode", title: "URL Decode", icon: "link"),
    TextTool(name: "sort lines", title: "Sort Lines", icon: "arrow.up.arrow.down"),
    TextTool(name: "json min", title: "Minify JSON", icon: "curlybraces"),
    TextTool(name: "password", title: "New Password", icon: "key.fill"),
    TextTool(name: "sha256", title: "SHA-256", icon: "number.square"),
    TextTool(name: "lorem", title: "Lorem Ipsum", icon: "text.alignleft"),
    TextTool(name: "upper", title: "UPPERCASE", icon: "textformat"),
    TextTool(name: "lower", title: "lowercase", icon: "textformat"),
    TextTool(name: "snake", title: "snake_case", icon: "textformat"),
    TextTool(name: "camel", title: "camelCase", icon: "textformat"),
    TextTool(name: "count", title: "Count", icon: "textformat.123"),
    TextTool(name: "json", title: "Format JSON", icon: "curlybraces"),
    TextTool(name: "uuid", title: "New UUID", icon: "number"),
    TextTool(name: "unix", title: "Unix Time ↔ Date", icon: "clock"),
    TextTool(name: "b64", title: "Base64 Encode", icon: "lock"),
    TextTool(name: "hex", title: "Hex ↔ RGB", icon: "paintpalette"),
]

/// What's on the clipboard: its plain text, and its formatting as HTML (RTF is converted) when asked.
struct Clip: Sendable {
    var text: String?
    var html: String? = nil

    @MainActor static func current(withHTML: Bool) -> Clip {
        let pasteboard = NSPasteboard.general
        var clip = Clip(text: pasteboard.string(forType: .string))
        guard withHTML else { return clip }
        clip.html = pasteboard.string(forType: .html) ?? pasteboard.data(forType: .rtf).flatMap { rtf in
            // AppKit writes RTF out as simple HTML (<p>, <b>, <i>, <a>), which markdown(fromHTML:) reads.
            guard let text = NSAttributedString(rtf: rtf, documentAttributes: nil) else { return nil }
            let html = try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
            return html.map { String(decoding: $0, as: UTF8.self) }
        }
        return clip
    }
}

/// What `name` makes of `typed` (the text after its name; nil when there's none, so the clipboard is
/// used). nil when the input doesn't fit: not JSON, not a color, nothing on the clipboard.
func runTextTool(_ name: String, typed: String?, clip: Clip, now: Date = .now, timeZone: TimeZone = .current) -> String? {
    let input = typed ?? clip.text
    func lines(_ text: String) -> [Substring] { text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) }
    switch name {
    case "uuid": return UUID().uuidString.lowercased()
    case "password":
        guard let length = typed.map({ Int($0) }) ?? 20, (4...256).contains(length) else { return nil }
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*-_=+")
        return String((0..<length).map { _ in characters.randomElement()! }) // SystemRandomNumberGenerator: secure
    case "lorem":
        guard let count = typed.map({ Int($0) }) ?? 1, (1...50).contains(count) else { return nil }
        return Array(repeating: loremIpsum, count: count).joined(separator: "\n\n")
    case "unix": return unixTime(input, now: now, timeZone: timeZone)
    case "paste markdown": return clip.html.flatMap(markdown(fromHTML:)) ?? clip.text
    case "paste plain": return clip.text
    default: break
    }
    guard let input, !input.isEmpty else { return nil }
    switch name {
    case "json": return reformatJSON(input, indent: true)
    case "json min": return reformatJSON(input, indent: false)
    case "b64": return Data(input.utf8).base64EncodedString()
    case "b64 decode":
        var base64 = input.filter { !$0.isWhitespace }.replacing("-", with: "+").replacing("_", with: "/") // URL-safe too
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
    case "url encode": return percentEncoded(input)
    case "url decode": return input.removingPercentEncoding
    case "upper": return input.uppercased()
    case "lower": return input.lowercased()
    case "snake": return lines(input).map { words($0).map { $0.lowercased() }.joined(separator: "_") }.joined(separator: "\n")
    case "camel":
        return lines(input).map { line in
            words(line).enumerated().map { $0 == 0 ? $1.lowercased() : $1.prefix(1).uppercased() + $1.dropFirst().lowercased() }.joined()
        }.joined(separator: "\n")
    case "sort lines":
        return lines(input.trimmingCharacters(in: .newlines)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
    case "sha256": return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    case "hex": return convertColor(input)
    case "count":
        func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
        return [count(input.split(whereSeparator: \.isWhitespace).count, "word"), count(input.count, "character"),
                count(lines(input).count, "line")].joined(separator: " · ")
    default: return nil
    }
}

/// "fooBar baz-qux HTTPServer" → foo, Bar, baz, qux, HTTP, Server.
private func words(_ text: Substring) -> [Substring] {
    text.matches(of: #/\p{Lu}+(?!\p{Ll})|\p{Lu}?\p{Ll}+|\d+/#).map(\.output)
}

/// A timestamp (seconds, or milliseconds) as a date in `timeZone`; anything else gives the time now.
func unixTime(_ text: String?, now: Date, timeZone: TimeZone) -> String {
    guard let text, let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
        return String(Int(now.timeIntervalSince1970))
    }
    let seconds = number > 100_000_000_000 ? Double(number) / 1000 : Double(number)
    return Date(timeIntervalSince1970: seconds).formatted(Date.ISO8601FormatStyle(timeZone: timeZone))
}

/// "#ff8800", "ff8800" or "#f80" → "rgb(255, 136, 0)"; "rgb(255, 136, 0)" or "255 136 0" → "#ff8800".
func convertColor(_ text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespaces)
    if let match = text.wholeMatch(of: #/#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/#) {
        let hex = match.1.count == 3 ? match.1.map { "\($0)\($0)" }.joined() : String(match.1)
        let value = Int(hex, radix: 16)!
        return "rgb(\(value >> 16), \(value >> 8 & 0xff), \(value & 0xff))"
    }
    guard let match = text.wholeMatch(of: #/(?i:rgb)?\(?\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*\)?/#) else { return nil }
    let parts = [match.1, match.2, match.3].compactMap { Int($0) }
    guard parts.allSatisfy({ $0 <= 255 }) else { return nil }
    return "#" + parts.map { String(format: "%02x", $0) }.joined()
}

/// `json` re-indented by 2 spaces, or with every space outside strings removed. Works on the text, so
/// key order and number spelling stay as they were (JSONSerialization would shuffle keys). nil if not JSON.
func reformatJSON(_ json: String, indent: Bool) -> String? {
    guard (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) != nil else { return nil }
    let characters = Array(json)
    var out = "", depth = 0, inString = false, escaped = false
    func newline() { out += "\n" + String(repeating: "  ", count: depth) }
    for (index, character) in characters.enumerated() {
        if inString {
            out.append(character)
            if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            continue
        }
        switch character {
        case " ", "\t", "\n", "\r", "\r\n": continue
        case "\"": inString = true; out.append(character)
        case "{", "[":
            out.append(character)
            let next = characters[(index + 1)...].first { !$0.isWhitespace }
            if indent && next != "}" && next != "]" { depth += 1; newline() } // {} and [] stay as they are
        case "}", "]":
            if indent && out.last != "{" && out.last != "[" { depth -= 1; newline() }
            out.append(character)
        case ",": out.append(character); if indent { newline() }
        case ":": out += indent ? ": " : ":"
        default: out.append(character)
        }
    }
    return out
}

/// Markdown for clipboard HTML (web pages, Google Docs, Slack, Word, RTF via AppKit): headings, paragraphs,
/// bold, italic, code, links, images, lists, quotes, tables. nil if it doesn't parse.
/// ponytail: Markdown characters in the text (`*`, `_`) aren't escaped; escape them if a paste ever breaks.
func markdown(fromHTML html: String) -> String? {
    guard let root = (try? XMLDocument(xmlString: html, options: .documentTidyHTML))?.rootElement() else { return nil }
    return markdown(root).replacing(#/[ \t]+\n/#, with: "\n").replacing(#/\n{3,}/#, with: "\n\n").trimmed
}

private func markdown(_ node: XMLNode, inPre: Bool = false) -> String {
    guard let element = node as? XMLElement else {
        guard node.kind == .text, let text = node.stringValue else { return "" }
        return inPre ? text : text.replacing(#/[\s\u{a0}]+/#, with: " ")
    }
    let children = { (element.children ?? []).map { markdown($0, inPre: inPre) }.joined() }
    let block = { (text: String) in "\n\n" + text + "\n\n" }
    // Google Docs marks bold and italic with inline styles, and wraps everything in <b style="font-weight:normal">.
    let style = element.attribute(forName: "style")?.stringValue?.replacing(" ", with: "").lowercased() ?? ""
    switch element.localName?.lowercased() ?? "" {
    case "head", "script", "style", "title": return ""
    case let tag where tag.count == 2 && tag.hasPrefix("h") && ("1"..."6").contains(tag.suffix(1)):
        return block(String(repeating: "#", count: Int(tag.suffix(1))!) + " " + children().trimmed)
    case "p", "div", "section", "article", "header", "footer", "figure": return block(children().trimmed)
    case "br": return "\n"
    case "hr": return block("---")
    case "b", "strong": return style.contains("font-weight:normal") || style.contains("font-weight:400") ? children() : wrap(children(), "**")
    case "i", "em": return wrap(children(), "*")
    case "s", "del", "strike": return wrap(children(), "~~")
    case "code": return inPre ? children() : wrap(children(), "`")
    case "pre":
        return block("```\n" + (element.children ?? []).map { markdown($0, inPre: true) }.joined().trimmingCharacters(in: .newlines) + "\n```")
    case "a":
        let label = children().trimmed
        guard let href = element.attribute(forName: "href")?.stringValue, !href.isEmpty, !href.hasPrefix("#") else { return children() }
        return label.isEmpty ? "" : "[\(label)](\(href))"
    case "img":
        guard let source = element.attribute(forName: "src")?.stringValue, !source.hasPrefix("data:") else { return "" }
        return "![\(element.attribute(forName: "alt")?.stringValue ?? "")](\(source))"
    case "blockquote":
        let inner = children().trimmed.replacing(#/\n{3,}/#, with: "\n\n")
        return block(inner.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
    case let list where list == "ul" || list == "ol":
        let items = (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName?.lowercased() == "li" }
        return block(items.enumerated().map { index, item in
            let marker = list == "ol" ? "\(index + 1). " : "- "
            let body = markdown(item).trimmed.replacing(#/\n{2,}/#, with: "\n") // a tight list, nested ones included
            return marker + body.replacing("\n", with: "\n" + String(repeating: " ", count: marker.count))
        }.joined(separator: "\n"))
    case "table":
        let rows = ((try? element.nodes(forXPath: ".//*[local-name()='tr']")) ?? []).map { row in
            ((row as? XMLElement)?.children ?? []).compactMap { $0 as? XMLElement }
                .map { markdown($0).trimmed.replacing("\n", with: " ").replacing("|", with: "\\|") }
        }
        guard let header = rows.first, !header.isEmpty else { return children() }
        let line = { (cells: [String]) in "| " + cells.joined(separator: " | ") + " |" }
        return block(([line(header), line(header.map { _ in "---" })] + rows.dropFirst().map(line)).joined(separator: "\n"))
    default:
        if style.contains("font-weight:700") || style.contains("font-weight:bold") { return wrap(children(), "**") }
        return style.contains("font-style:italic") ? wrap(children(), "*") : children()
    }
}

/// `**bold**`, with the spaces around the text kept outside the markers ("a<b> b</b>" → "a **b**").
private func wrap(_ text: String, _ marker: String) -> String {
    let inner = text.trimmed
    guard !inner.isEmpty else { return text }
    return String(text.prefix { $0.isWhitespace }) + marker + inner + marker + String(text.reversed().prefix { $0.isWhitespace })
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private let loremIpsum = """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore \
    magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo \
    consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \
    Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    """

struct TextToolProvider: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        // A whole name, with or without text after it, ranks first. From 3 letters, a name's beginning
        // shows the tool too, but only when it has something to show ("pas" → the paste tools).
        let named = textTools.lazy.compactMap { tool -> (TextTool, String?)? in
            guard let range = query.range(of: tool.name, options: [.caseInsensitive, .anchored]) else { return nil }
            let rest = query[range.upperBound...]
            guard rest.isEmpty || rest.first == " " else { return nil }
            let typed = rest.trimmingCharacters(in: .whitespaces)
            return (tool, typed.isEmpty ? nil : typed)
        }.first
        let starts = named == nil && query.count >= 3 ? textTools.filter { $0.name.hasPrefix(query.lowercased()) || otherNameScore(query, $0.title) != nil } : []
        guard named != nil || !starts.isEmpty else { return [] }
        let clip = await Clip.current(withHTML: (named.map { [$0.0] } ?? starts).contains { $0.name == "paste markdown" })
        if let (tool, typed) = named { return row(tool, typed: typed, clip: clip, score: 50, hint: typed == nil).map { [$0] } ?? [] }
        return starts.compactMap { row($0, typed: nil, clip: clip, score: 0.5, hint: false) }
    }

    /// nil when the tool can't use its input; with `hint`, a row saying how to give it some instead.
    private func row(_ tool: TextTool, typed: String?, clip: Clip, score: Double, hint: Bool) -> LauncherResult? {
        let id = "builtin:\(tool.name)", icon = LauncherResult.Icon.symbol(tool.icon)
        guard let output = runTextTool(tool.name, typed: typed, clip: clip) else {
            guard hint else { return nil }
            let how = tool.pastes ? "Copy some text first" : "Type text after “\(tool.name)”, or copy it first"
            return LauncherResult(id: id, title: tool.title, subtitle: how, icon: icon, score: score,
                                  actionTitle: "", action: {})
        }
        let fromClipboard = typed == nil && !tool.pastes && !["uuid", "password", "lorem", "unix"].contains(tool.name)
        let long = output.contains(where: \.isNewline) || output.count > 80
        // A long result shows in the preview pane, so the row names the tool ("paste plain" and "paste markdown"
        // looked alike, cut short beside the pane). A short one is the row, with the tool's name at the right edge;
        // selected, the paste tools say which paste Enter does there.
        return LauncherResult(id: id, title: long ? tool.title : oneLine(output), subtitle: fromClipboard ? "from the clipboard" : "",
                              accessory: long ? "" : tool.title, icon: icon, score: score,
                              actionTitle: tool.pastes ? (long ? "Paste" : tool.title) : "Copy", action: {
            copyToClipboard(output)
            if tool.pastes, hasAccessibility("paste") { sendPaste() }
        }, preview: long ? output : nil)
    }
}
