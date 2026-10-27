import Expression
import Foundation
import Synchronization

/// The calculator result last taken with Enter: `ans` in the next calculation. ponytail: in memory, gone on quit.
let lastAnswer = Mutex<Double?>(nil)

/// The value of `query` if it's a calculation. nil for anything malformed, non-finite,
/// or that isn't really math (a bare number like `42`, a lone constant like `pi`).
/// Besides Expression's math: `20% of 150`, `150 + 20%` (20% of 150 added), `0b1010`, and `ans`.
func calculate(_ query: String, ans: Double? = nil) -> Double? {
    var text = query.trimmingCharacters(in: .whitespaces)
    // Empty parens: Expression 0.13.9 crashes (out-of-range index) describing the error for
    // inputs like "x 2()". No math needs them. Fuzzed ~6M random inputs with this guard: no crash.
    guard Double(text) == nil, !text.contains(#/\(\s*\)/#) else { return nil }
    text = text.replacing(#/\b0b([01]+)\b/#) { binary in Int(binary.1, radix: 2).map(String.init) ?? String(binary.0) }
    // Expression's % is the remainder (10 % 3), so only these two shapes mean percent.
    if let percent = text.wholeMatch(of: #/(\d+(?:\.\d+)?)\s*%\s+of\s+(.+)/#) {
        text = "(\(percent.1) / 100) * (\(percent.2))"
    } else if let percent = text.wholeMatch(of: #/(.+?)\s*([+-])\s*(\d+(?:\.\d+)?)\s*%/#) {
        text = "(\(percent.1)) * (1 \(percent.2) \(percent.3) / 100)"
    }
    // No cache: it would keep every keystroke's string forever.
    let parsed = Expression.parse(text, usingCache: false)
    guard parsed.error == nil,
          parsed.symbols.contains(where: { if case .variable = $0 { false } else { true } })
    else { return nil }
    let expression = Expression(parsed, constants: ans.map { ["ans": $0] } ?? [:], symbols: [.infix("^"): { pow($0[0], $0[1]) }])
    guard let value = try? expression.evaluate(), value.isFinite else { return nil }
    return value
}

/// `0xff`, `0b1010`, `255`: a whole number as typed in any of the three bases.
func wholeNumber(_ text: String) -> Int? {
    let text = text.trimmingCharacters(in: .whitespaces).lowercased()
    if text.hasPrefix("0x") { return Int(text.dropFirst(2), radix: 16) }
    if text.hasPrefix("0b") { return Int(text.dropFirst(2), radix: 2) }
    return Int(text)
}

/// `255 in hex` → 0xFF, `0xff in dec` → 255, `(2^8 - 1) to binary`, and `0xff` or `0b1010` alone → its decimal.
/// nil unless the number is whole.
func convertBase(_ query: String, ans: Double? = nil) -> String? {
    let query = query.trimmingCharacters(in: .whitespaces)
    if query.lowercased().hasPrefix("0x") || query.lowercased().hasPrefix("0b"), let value = wholeNumber(query) { return String(value) }
    guard let match = query.wholeMatch(of: #/(?i)(.+?)\s+(?:in|to|as)\s+(hex|bin|binary|dec|decimal)/#),
          let value = wholeNumber(String(match.1))
            ?? (match.1.lowercased() == "ans" ? ans : calculate(String(match.1), ans: ans)).flatMap({ Int(exactly: $0) })
    else { return nil }
    let sign = value < 0 ? "-" : ""
    return switch match.2.lowercased() {
    case "hex": sign + "0x" + String(value.magnitude, radix: 16, uppercase: true)
    case "bin", "binary": sign + "0b" + String(value.magnitude, radix: 2)
    default: String(value)
    }
}

struct CalculatorProvider: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        let ans = lastAnswer.withLock { $0 }
        if let converted = convertBase(query, ans: ans) {
            return [LauncherResult(id: "calculator", title: converted, subtitle: query, icon: .symbol("number"), score: 10,
                                   actionTitle: "Copy", action: { copyToClipboard(converted) })]
        }
        guard let value = calculate(query, ans: ans) else { return [] }
        let text = formatNumber(value)
        return [LauncherResult(id: "calculator", title: text, subtitle: query, icon: .symbol("equal"), score: 10, actionTitle: "Copy",
                               action: {
                                   lastAnswer.withLock { $0 = value }
                                   copyToClipboard(text)
                               })]
    }
}
