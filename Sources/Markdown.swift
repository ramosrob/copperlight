import AppKit

/// How a stretch of a note shows. The text itself never changes: this is drawing only, and the file stays plain text.
enum MarkdownStyle: Equatable, Sendable {
    case heading(Int) // the whole line, `#` to `###`
    case bold, italic, code
    case marker // the syntax around a style (`**`, `# `, `](url)`), dimmed
    case bullet // `- `, `* `, `1. `
    case checkbox(done: Bool) // `[ ]`, `[x]`: click to tick
    case done // what follows a ticked box
    case quote // the whole line, `> `
    case link(String)
}

struct MarkdownSpan: Equatable, Sendable {
    let range: NSRange
    let style: MarkdownStyle
}

private func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) }

private let headingLine = regex(#"^(#{1,3} +).*$"#)
private let quoteLine = regex(#"^(> ?).*$"#)
private let checkboxLine = regex(#"^(\s*[-*+] )(\[( |x|X)\])(.*)$"#)
private let bulletLine = regex(#"^\s*([-*+]|\d+\.) (?!\[[ xX]\])"#)
private let codeSpan = regex(#"`([^`\n]+)`"#)
private let boldSpan = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
private let italicSpan = regex(#"(?<![*\w])\*(?=[^\s*])([^*\n]*?[^\s*])\*(?![*\w])|(?<![_\w])_(?=[^\s_])([^_\n]*?[^\s_])_(?![_\w])"#)
private let linkSpan = regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
private let bareURL = regex(#"https?://[^\s)\]>]+"#)

/// The styles of a note's Markdown: headings, bold, italic, code, lists and checkboxes, quotes and links. Ranges are
/// UTF-16, as NSTextStorage counts. ponytail: a line-by-line reading, not CommonMark (no nesting, no code blocks).
func markdownSpans(_ text: String) -> [MarkdownSpan] {
    let string = text as NSString, all = NSRange(location: 0, length: string.length)
    var spans: [MarkdownSpan] = []
    func each(_ pattern: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
        pattern.enumerateMatches(in: text, range: all) { match, _, _ in match.map(body) }
    }
    each(headingLine) { match in
        let level = string.substring(with: match.range(at: 1)).filter { $0 == "#" }.count
        spans += [MarkdownSpan(range: match.range, style: .heading(level)), MarkdownSpan(range: match.range(at: 1), style: .marker)]
    }
    each(quoteLine) { spans += [MarkdownSpan(range: $0.range, style: .quote), MarkdownSpan(range: $0.range(at: 1), style: .marker)] }
    each(checkboxLine) { match in
        let done = string.substring(with: match.range(at: 3)) != " "
        spans += [MarkdownSpan(range: match.range(at: 1), style: .bullet), MarkdownSpan(range: match.range(at: 2), style: .checkbox(done: done))]
        let rest = match.range(at: 4), text = string.substring(with: rest)
        let lead = text.prefix { $0 == " " }.utf16.count
        if done, rest.length > lead { spans.append(MarkdownSpan(range: NSRange(location: rest.location + lead, length: rest.length - lead), style: .done)) }
    }
    each(bulletLine) { spans.append(MarkdownSpan(range: NSRange(location: $0.range(at: 1).location, length: $0.range(at: 1).length + 1), style: .bullet)) }
    each(codeSpan) { match in
        spans.append(MarkdownSpan(range: match.range(at: 1), style: .code))
        spans += markers(around: match.range, inner: match.range(at: 1))
    }
    each(boldSpan) { match in
        spans.append(MarkdownSpan(range: match.range(at: 2), style: .bold))
        spans += markers(around: match.range, inner: match.range(at: 2))
    }
    each(italicSpan) { match in
        let inner = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        spans.append(MarkdownSpan(range: inner, style: .italic))
        spans += markers(around: match.range, inner: inner)
    }
    var linked: [NSRange] = []
    each(linkSpan) { match in
        let url = string.substring(with: match.range(at: 2))
        spans.append(MarkdownSpan(range: match.range(at: 1), style: .link(url)))
        spans += markers(around: match.range, inner: match.range(at: 1))
        linked.append(match.range)
    }
    each(bareURL) { match in
        guard !linked.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
        spans.append(MarkdownSpan(range: match.range, style: .link(string.substring(with: match.range))))
    }
    return spans
}

/// The syntax on either side of `inner` within `whole`: `**` and `**`, `[` and `](url)`.
private func markers(around whole: NSRange, inner: NSRange) -> [MarkdownSpan] {
    [NSRange(location: whole.location, length: inner.location - whole.location),
     NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner))]
        .filter { $0.length > 0 }.map { MarkdownSpan(range: $0, style: .marker) }
}

/// The checkbox at `location` and what clicking it makes it: `[ ]` becomes `[x]`, and back. nil if there's none there.
func checkboxToggle(_ text: NSString, at location: Int) -> (range: NSRange, replacement: String)? {
    let line = text.lineRange(for: NSRange(location: min(location, max(text.length - 1, 0)), length: 0))
    guard let match = checkboxLine.firstMatch(in: text as String, range: line) else { return nil }
    let box = match.range(at: 2)
    guard NSLocationInRange(location, box) || location == NSMaxRange(box) else { return nil }
    return (box, text.substring(with: match.range(at: 3)) == " " ? "[x]" : "[ ]")
}

/// The link a checkbox carries, so a click on it reaches the note (NSTextView hands clicks on links to its delegate).
let checkboxScheme = "copperlight-checkbox"
