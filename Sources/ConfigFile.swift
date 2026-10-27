import Foundation

/// A value as config.toml writes it.
enum TOMLValue: Equatable {
    case string(String), int(Int), bool(Bool), strings([String])

    var toml: String {
        switch self {
        case .int(let number): "\(number)"
        case .bool(let flag): "\(flag)"
        case .strings(let items): "[" + items.map(Self.quoted).joined(separator: ", ") + "]"
        case .string(let text) where text.contains("\n"):
            // A multi-line basic string: the newline after the opening quotes isn't part of the text.
            "\"\"\"\n" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"\"\""
        case .string(let text): Self.quoted(text)
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// config.toml, edited the way a person would: one key, or one `[[command]]` or `[[snippet]]` entry, at a time.
/// Every other line, comments included, stays as it was. The settings window parses the result before writing it,
/// so a file this can't edit safely (dotted keys, inline tables) is refused rather than broken.
struct ConfigFile {
    private(set) var lines: [String]

    init(_ text: String) { lines = text.components(separatedBy: "\n") }

    var text: String { lines.joined(separator: "\n") }

    /// Sets `key` in `[table]`, or removes it for nil. A missing key takes the place of its commented-out example
    /// (`# name = "Ghostty"`) if the table has one, else goes after the table's last key; a missing table goes at
    /// the end.
    mutating func set(_ key: String, in table: String, to value: TOMLValue?) {
        let all = statements
        guard let header = all.firstIndex(where: { $0.kind == .table(table) }) else {
            if let value { append(["[\(table)]", "\(key) = \(value.toml)"]) }
            return
        }
        let section = all[(header + 1)...].prefix { $0.kind.isBody }
        if let pair = section.first(where: { $0.kind == .pair(key) }) {
            let comment = Self.comment(after: pair.lines.upperBound - 1, in: lines, from: pair.lines.lowerBound)
            replace(pair.lines, with: value.map { [Self.aligned(Self.indent(lines[pair.lines.lowerBound]) + "\(key) = \($0.toml)", comment)] } ?? [])
        } else if let value {
            if let example = section.first(where: { $0.kind == .other && Self.commentedKey(lines[$0.lines.lowerBound]) == key }) {
                let line = lines[example.lines.lowerBound]
                let uncommented = String(line.drop { $0 == " " || $0 == "\t" }.dropFirst().drop { $0 == " " })
                // Its comment stays in the column it had, behind the "# " that's gone now.
                let comment = Self.comment(after: 0, in: [uncommented], from: 0).map { ($0.text, $0.column + line.count - uncommented.count) }
                replace(example.lines, with: [Self.aligned(Self.indent(line) + "\(key) = \(value.toml)", comment)])
            } else {
                let after = section.last { if case .pair = $0.kind { true } else { false } }?.lines.upperBound ?? all[header].lines.upperBound
                lines.insert("\(key) = \(value.toml)", at: after)
            }
        }
    }

    /// Replaces the `index`th `[[table]]` entry, removes it (nil), or adds one at the end of the list (index nil).
    /// Tables named after the entry (`[table.x]`) belong to it. Comment lines after an entry belong to what follows,
    /// so they stay.
    mutating func setEntry(_ table: String, at index: Int?, to entry: [(key: String, value: TOMLValue)]?) {
        let all = statements
        let headers = all.indices.filter { all[$0].kind == .array(table) }
        func block(_ header: Int) -> Range<Int> {
            var end = all[header].lines.upperBound
            for statement in all[(header + 1)...] {
                switch statement.kind {
                case .pair: end = statement.lines.upperBound
                case .table(let name), .array(let name):
                    guard name.hasPrefix(table + ".") else { return all[header].lines.lowerBound..<end }
                    end = statement.lines.upperBound
                case .other: continue
                }
            }
            return all[header].lines.lowerBound..<end
        }
        let line = { (pair: (key: String, value: TOMLValue)) in "\(pair.key) = \(pair.value.toml)" }
        let rendered = entry.map { ["[[\(table)]]"] + $0.map(line) }
        if let index {
            guard headers.indices.contains(index) else { return }
            let range = block(headers[index])
            if let rendered { return replace(range, with: rendered) }
            replace(range, with: [])
            // The blank line before an entry goes with it, as adding one put it there.
            let at = range.lowerBound
            if at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { lines.remove(at: at - 1) }
        } else if let rendered {
            guard let last = headers.last else { return append(rendered) }
            lines.insert(contentsOf: [""] + rendered, at: block(last).upperBound)
        }
    }

    // MARK: Reading the file

    private enum Kind: Equatable {
        case table(String), array(String), pair(String), other // other: a blank line or a comment

        var isBody: Bool { if case .table = self { false } else if case .array = self { false } else { true } }
    }

    private struct Statement { let kind: Kind; let lines: Range<Int> }

    /// The file as headers, `key = value` pairs (over several lines when an array or a string runs on), and the rest.
    private var statements: [Statement] {
        var out: [Statement] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            var kind = Kind.other, end = index
            if line.hasPrefix("[[") { kind = .array(Self.name(line, brackets: 2)) }
            else if line.hasPrefix("[") { kind = .table(Self.name(line, brackets: 1)) }
            else if !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") {
                kind = .pair(Self.unquoted(line[..<equals]))
                end = Self.valueEnd(lines, line: index, from: lines[index].index(after: lines[index].firstIndex(of: "=")!)).line
            }
            out.append(Statement(kind: kind, lines: index..<end + 1))
            index = end + 1
        }
        return out
    }

    private static func name(_ header: String, brackets: Int) -> String {
        unquoted(header.dropFirst(brackets).prefix { $0 != "]" })
    }

    private static func unquoted(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// `name` for a line like `# name = "Ghostty"  # …`: a setting someone left commented out.
    private static func commentedKey(_ line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let equals = rest.firstIndex(of: "="), !rest.hasPrefix("[") else { return nil }
        let key = unquoted(rest[..<equals])
        return key.isEmpty || key.contains(" ") ? nil : key
    }

    /// Where the value that starts at `from` on `line` ends (it may run on over lines), and where a comment starts
    /// on that last line.
    private static func valueEnd(_ lines: [String], line start: Int, from: String.Index) -> (line: Int, comment: String.Index?) {
        enum Quote { case none, basic, literal, multiBasic, multiLiteral }
        var quote = Quote.none, depth = 0
        for number in start..<lines.count {
            let line = lines[number]
            var at = number == start ? from : line.startIndex
            while at < line.endIndex {
                let rest = line[at...]
                switch quote {
                case .none:
                    if rest.hasPrefix("#") { if depth == 0 { return (number, at) } else { at = line.endIndex; continue } }
                    if rest.hasPrefix("\"\"\"") { quote = .multiBasic; at = line.index(at, offsetBy: 3); continue }
                    if rest.hasPrefix("'''") { quote = .multiLiteral; at = line.index(at, offsetBy: 3); continue }
                    switch line[at] {
                    case "\"": quote = .basic
                    case "'": quote = .literal
                    case "[", "{": depth += 1
                    case "]", "}": depth -= 1
                    default: break
                    }
                case .basic, .multiBasic:
                    if line[at] == "\\" { at = line.index(after: at); if at == line.endIndex { continue } }
                    else if quote == .basic, line[at] == "\"" { quote = .none }
                    else if quote == .multiBasic, rest.hasPrefix("\"\"\"") { quote = .none; at = line.index(at, offsetBy: 3); continue }
                case .literal: if line[at] == "'" { quote = .none }
                case .multiLiteral: if rest.hasPrefix("'''") { quote = .none; at = line.index(at, offsetBy: 3); continue }
                }
                at = line.index(after: at)
            }
            if quote == .basic || quote == .literal { quote = .none } // a single-line string can't run on
            if quote == .none, depth <= 0 { return (number, nil) }
        }
        return (lines.count - 1, nil)
    }

    /// The comment after a value ending on `last`, with the column it started at, so a new value can keep it aligned.
    private static func comment(after last: Int, in lines: [String], from start: Int) -> (text: String, column: Int)? {
        let first = lines[start]
        let equals = first.firstIndex(of: "=").map { first.index(after: $0) } ?? first.startIndex
        guard let at = valueEnd(lines, line: start, from: equals).comment else { return nil }
        let line = lines[last]
        return (String(line[at...]), line.distance(from: line.startIndex, to: at))
    }

    private static func aligned(_ content: String, _ comment: (text: String, column: Int)?) -> String {
        guard let comment else { return content }
        return content.padding(toLength: max(content.count + 2, comment.column), withPad: " ", startingAt: 0) + comment.text
    }

    private static func indent(_ line: String) -> String { String(line.prefix { $0 == " " || $0 == "\t" }) }

    private mutating func replace(_ range: Range<Int>, with new: [String]) { lines.replaceSubrange(range, with: new) }

    /// Adds lines at the end, after a blank line, keeping the file's final newline.
    private mutating func append(_ new: [String]) {
        let end = lines.last == "" ? lines.count - 1 : lines.count
        let blank = end > 0 && !lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty
        lines.insert(contentsOf: (blank ? [""] : []) + new, at: end)
    }
}

extension Config.Command {
    /// The `[[command]]` entry's keys, in the order the example config uses.
    var toml: [(key: String, value: TOMLValue)] {
        let head: [(key: String, value: TOMLValue)] = [("alias", .string(alias))]
        switch action {
        case .url(let url, let browser, let profile):
            return head + [("type", .string("url")), ("url", .string(url))]
                + (browser.map { [("browser", .string($0))] } ?? []) + (profile.map { [("profile", .string($0))] } ?? [])
        case .app(let app): return head + [("type", .string("app")), ("app", .string(app))]
        case .file(let path): return head + [("type", .string("file")), ("path", .string(path))]
        case .shell(let run): return head + [("type", .string("shell")), ("run", .string(run))]
        }
    }
}

extension Config.Snippet {
    var toml: [(key: String, value: TOMLValue)] { [("name", .string(name)), ("text", .string(text))] }
}
