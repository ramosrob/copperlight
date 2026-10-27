import AppKit

/// `text` with its placeholders filled: `{date}` (2026-10-13), `{time}` (16:55), `{clipboard}` (its text) and
/// `{query}` (what was typed after the snippet's name). Anything else in braces stays as written.
func expandSnippet(_ text: String, query: String, clipboard: String?, now: Date = .now, timeZone: TimeZone = .current) -> String {
    let format = { (pattern: String) in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: now)
    }
    return text.replacingOccurrences(of: "{date}", with: format("yyyy-MM-dd"))
        .replacingOccurrences(of: "{time}", with: format("HH:mm"))
        .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
        .replacingOccurrences(of: "{query}", with: query)
}

/// The `[[snippet]]` entries from config.toml, found by name like commands. Enter pastes the text, filled in,
/// into the app you were in, keeping your clipboard (only copies without Accessibility). A snippet with `{query}` takes the text after
/// its name (`reply John`). Ids are `snippet:<name>`.
actor SnippetProvider: ResultProvider {
    private var snippets: [Config.Snippet] = []

    func setSnippets(_ snippets: [Config.Snippet]) { self.snippets = snippets }

    func results(for query: String) async -> [LauncherResult] {
        let matches = snippets.compactMap { snippet -> (Config.Snippet, typed: String, score: Double)? in
            if snippet.text.contains("{query}"), let name = query.range(of: snippet.name + " ", options: [.caseInsensitive, .anchored]) {
                return (snippet, query[name.upperBound...].trimmingCharacters(in: .whitespaces), 100)
            }
            return aliasScore(query, snippet.name).map { (snippet, "", $0) }
        }
        guard !matches.isEmpty else { return [] }
        let clipboard = matches.contains { $0.0.text.contains("{clipboard}") } ? await MainActor.run { NSPasteboard.general.string(forType: .string) } : nil
        return matches.map { snippet, typed, score in
            let text = expandSnippet(snippet.text, query: typed, clipboard: clipboard)
            let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return LauncherResult(id: "snippet:\(snippet.name)", title: typed.isEmpty ? snippet.name : "\(snippet.name) \(typed)",
                                  subtitle: firstLine, icon: .symbol("text.quote"), score: score, actionTitle: "Paste", action: {
                if hasAccessibility("paste snippets") { Task { await pasteKeepingClipboard(text) } } else { copyToClipboard(text) }
            }, preview: text.contains(where: \.isNewline) || text.count > 80 ? text : nil, previewStyle: .prose)
        }
    }
}
