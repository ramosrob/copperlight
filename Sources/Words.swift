import AppKit
import CoreServices
import NaturalLanguage
import Synchronization
import Translation

/// A launcher row offering to start `keyword …`, for a query that's the start of it (from 3 letters).
func startRow(_ query: String, keyword: String, title: String, hint: String, symbol: String) -> LauncherResult? {
    let lower = query.lowercased()
    guard lower.count >= 3, let score = keyword.hasPrefix(lower) ? 50 : otherNameScore(query, title) else { return nil }
    return LauncherResult(id: "builtin:\(keyword)", title: title, subtitle: hint, icon: .symbol(symbol), score: score,
                          actionTitle: "Start", action: {}, completion: keyword + " ")
}

// MARK: Define

/// A word's entry in the Mac's dictionaries (Dictionary.app's), as plain text: "serendipity ser·en·dip·i·ty |
/// ˌserənˈdipədē | noun the occurrence…". nil if no dictionary has it.
func definition(of word: String) -> String? {
    DCSCopyTextDefinition(nil, word as NSString, CFRange(location: 0, length: (word as NSString).length))
        .map { $0.takeRetainedValue() as String }
}

/// The entry split for the row and its preview: the pronunciation, and the meanings with a line per bullet and a
/// paragraph per part of speech and section (ORIGIN, PHRASES).
func formatDefinition(_ entry: String) -> (pronunciation: String, body: String) {
    let parts = entry.components(separatedBy: " | ")
    let (pronunciation, body) = parts.count >= 3 ? (parts[1], parts.dropFirst(2).joined(separator: " | ")) : ("", entry)
    let laidOut = body
        .replacing(#/ (?=(?:noun|verb|adjective|adverb|pronoun|preposition|conjunction|exclamation|ORIGIN|PHRASES|PHRASAL VERBS|DERIVATIVES|USAGE)\b)/#,
                   with: "\n\n")
        .replacing(" • ", with: "\n• ")
    return (pronunciation, laidOut.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// `define serendipity`: its dictionary entry in the preview. Enter opens it in Dictionary.
struct DefineProvider: ResultProvider {
    var modes: [Mode] { [Mode(prefix: "define ", title: "Define", icon: .symbol("character.book.closed"), hint: "A word")] }

    func results(for query: String) -> [LauncherResult] {
        if let start = startRow(query, keyword: "define", title: "Define", hint: "Type a word: define serendipity", symbol: "character.book.closed") {
            return [start]
        }
        guard query.lowercased().hasPrefix("define ") else { return [] }
        let word = query.dropFirst(7).trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return [] }
        guard let entry = definition(of: word) else {
            return [LauncherResult(id: "define", title: "No definition for “\(word)”", icon: .symbol("character.book.closed"),
                                   score: 50, actionTitle: "", action: {})]
        }
        let (pronunciation, body) = formatDefinition(entry)
        let url = URL(string: "dict://" + (word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word))!
        return [LauncherResult(id: "define", title: word, subtitle: pronunciation, icon: .symbol("character.book.closed"), score: 50,
                               actionTitle: "Open", action: { NSWorkspace.shared.open(url) }, preview: body, previewStyle: .prose)]
    }
}

// MARK: Translate

/// `translate bom dia`, `translate good morning to spanish`: Apple's on-device translation (macOS 26), from the
/// language it detects to the one named, or else your first language in System Settings that isn't the text's.
/// With no text (`translate`, `translate to spanish`) it's what's on the clipboard, like the text tools. The language
/// can come first too (`translate to german hello`): that's its chip, Translate to German.
/// Enter copies it. A language pair that isn't downloaded yet gets a row that opens where to download it.
struct TranslateProvider: ResultProvider {
    private static let supported = Mutex<[Locale.Language]?>(nil) // asked once
    private static let english = Locale(identifier: "en")
    var clipboard: @Sendable () async -> String? = { await Clip.current(withHTML: false).text }
    var modes: [Mode] {
        let icon = LauncherResult.Icon.symbol("character.bubble")
        let names = Set((Self.supported.withLock { $0 } ?? []).map(Self.shortName)) // English and Chinese come twice
        return [Mode(prefix: "translate ", title: "Translate", icon: icon, hint: "Text, or nothing for what's copied · to spanish")]
            + names.sorted().map { Mode(prefix: "translate to \($0.lowercased()) ", title: "Translate to \($0)", icon: icon,
                                        hint: "Text, or nothing for what's copied") }
    }

    /// The languages the Mac can translate, asked once (at launch, so their chips are ready). None before macOS 26.
    static func languages() async -> [Locale.Language] {
        if let supported = supported.withLock({ $0 }) { return supported }
        guard #available(macOS 26, *) else { return [] }
        let languages = await LanguageAvailability().supportedLanguages
        supported.withLock { $0 = languages }
        return languages
    }

    func results(for query: String) async -> [LauncherResult] {
        let start = startRow(query, keyword: "translate", title: "Translate", hint: "Type text, or copy it; add “to spanish” for another language",
                             symbol: "character.bubble").map { [$0] } ?? []
        let lower = query.lowercased()
        guard lower == "translate" || lower.hasPrefix("translate "), #available(macOS 26, *) else { return start }
        var text = query.dropFirst(9).trimmingCharacters(in: .whitespaces)
        let availability = LanguageAvailability()
        let supported = await Self.languages()
        var target: Locale.Language?
        if let first = text.firstMatch(of: #/(?i)^(?:to|in|into)\s+([\p{L}-]+)\s+(.+)$/#), let language = language(String(first.1), among: supported) {
            (text, target) = (String(first.2), language) // "to german hello": the language chip, then the text
        } else if let named = text.firstMatch(of: #/(?i)^(?:(.+?)\s+)?(?:to|in|into)\s+([\p{L}-]+)$/#),
                  let language = language(String(named.2), among: supported) {
            (text, target) = (named.1.map(String.init) ?? "", language)
        }
        let fromClipboard = text.isEmpty
        if fromClipboard { text = await clipboard()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard !text.isEmpty, let source = detectLanguage(text) else { return start }
        let preferred = Locale.preferredLanguages.map(Locale.Language.init(identifier:))
        guard let target = target ?? (preferred + [Locale.Language(identifier: "en")]).first(where: { $0.languageCode != source.languageCode })
        else { return [] }
        let pair = "\(Self.name(source)) → \(Self.name(target))"
        let row = { (title: String, subtitle: String, actionTitle: String, preview: String?, action: @escaping @MainActor @Sendable () -> Void) in
            LauncherResult(id: "translate", title: title, subtitle: subtitle, icon: .symbol("character.bubble"), score: 50,
                           actionTitle: actionTitle, action: action, preview: preview, previewStyle: .prose)
        }
        switch await availability.status(from: source, to: target) {
        case .installed:
            let session = TranslationSession(installedSource: source, target: target)
            guard let translated = try? await session.translate(text).targetText else { return [] }
            return [row(oneLine(translated), pair + (fromClipboard ? " · from the clipboard" : ""), "Copy", translated.count > 60 || translated.contains("\n") ? translated : nil, {
                copyToClipboard(translated)
            })]
        case .supported:
            return [row("Download \(pair) to translate here", "Language & Region → Translation Languages, once", "Open System Settings", nil, {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
            })]
        case .unsupported:
            return [row("Can't translate \(pair)", "Not a language pair Apple translates", "", nil, {})]
        @unknown default:
            return []
        }
    }

    /// "spanish", "pt", "pt-BR": a language the Mac can translate, by its English name or its code.
    private func language(_ name: String, among supported: [Locale.Language]) -> Locale.Language? {
        let key = name.lowercased()
        return supported.first { language in
            [language.minimalIdentifier, language.languageCode?.identifier].contains { $0?.lowercased() == key }
                || Self.name(language).lowercased() == key || Self.shortName(language).lowercased() == key
        }
    }

    /// One word, as a chip and as typed after "to": Norwegian Bokmål is "norwegian".
    private static func shortName(_ language: Locale.Language) -> String {
        String(name(language).split(separator: " ").first ?? "")
    }

    private static func name(_ language: Locale.Language) -> String {
        language.languageCode.flatMap { Self.english.localizedString(forLanguageCode: $0.identifier) } ?? language.minimalIdentifier
    }

    /// The text's language, leaning to the ones in System Settings (short texts are ambiguous).
    private func detectLanguage(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = Dictionary(Locale.preferredLanguages.map {
            (NLLanguage(rawValue: Locale.Language(identifier: $0).languageCode?.identifier ?? $0), 0.6)
        }, uniquingKeysWith: max)
        recognizer.processString(text)
        return recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
    }
}
