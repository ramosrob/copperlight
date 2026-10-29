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

/// A word's entry, tidied for its card.
struct DictionaryEntry: Equatable, Sendable {
    struct Sense: Equatable, Sendable {
        var meaning: String
        var example: String?
    }
    struct Part: Equatable, Sendable {
        var name: String // "noun"
        var senses: [Sense]
    }
    var word: String
    var pronunciation: String
    var parts: [Part]
    var origin: String?
}

private let partsOfSpeech = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "exclamation"]

/// The entry for its card: the first two parts of speech, three meanings of the first and one of the next, each with
/// its first example, and where the word comes from. Its forms ("(runs)"), grammar labels ("[no object]") and the
/// notes after a meaning are left out: Dictionary has the whole entry.
func parseDefinition(_ entry: String, word: String) -> DictionaryEntry {
    let (pronunciation, body) = formatDefinition(entry)
    var parts: [DictionaryEntry.Part] = [], origin: String?, meanings = true
    for paragraph in body.components(separatedBy: "\n\n") {
        if paragraph.hasPrefix("ORIGIN ") { origin = String(paragraph.dropFirst(7)); continue }
        // After the meanings: phrases with the word and words made from it, each with a part of speech of its own.
        if ["PHRASES", "PHRASAL VERBS", "DERIVATIVES", "USAGE"].contains(where: paragraph.hasPrefix) { meanings = false }
        guard meanings, parts.count < 2, let name = partsOfSpeech.first(where: { paragraph.hasPrefix($0 + " ") }) else { continue }
        var text = String(paragraph.dropFirst(name.count + 1))
        if let first = text.firstMatch(of: #/(?:^| )1 /#) { text = String(text[first.range.upperBound...]) } // its forms come before
        // ponytail: "2 " after a word or a period starts the next meaning; a number in the text like that would too.
        let pieces = text.replacing(#/([\w.)\]’']) [2-9] (?=\S)/#) { "\($0.1)\n• " }.components(separatedBy: "\n• ")
        let senses = pieces.compactMap(sense).prefix(parts.isEmpty ? 3 : 1)
        if !senses.isEmpty { parts.append(.init(name: name, senses: Array(senses))) }
    }
    return DictionaryEntry(word: word, pronunciation: pronunciation, parts: parts, origin: origin)
}

/// "[no object] move fast: she ran | he ran." → "move fast", "she ran".
private func sense(_ text: String) -> DictionaryEntry.Sense? {
    let clean = text.replacing(#/\[[^\]]*\]\s*:?\s*/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    let halves = clean.split(separator: ": ", maxSplits: 1).map(String.init)
    let trim = { (text: String) in text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    let sentences = halves.first?.split(separator: ". ", maxSplits: 1) ?? []
    let meaning = trim(String(sentences.first ?? "")) // the notes after it left out
    guard !meaning.isEmpty else { return nil }
    // After a note, what follows the colon is the note's: "Genus Pyrus, family Rosaceae: many kinds".
    let example = halves.count > 1 && sentences.count == 1 ? halves[1].components(separatedBy: " | ").first.map(trim) : nil
    return .init(meaning: meaning, example: example?.isEmpty == false ? example : nil)
}

/// `define serendipity`: its dictionary entry across the card. Enter opens it in Dictionary.
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
        return [row(word: word, entry: entry)]
    }

    func row(word: String, entry: String) -> LauncherResult {
        let parsed = parseDefinition(entry, word: word)
        let url = URL(string: "dict://" + (word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word))!
        return LauncherResult(id: "define", title: word, subtitle: parsed.pronunciation, icon: .symbol("character.book.closed"), score: 50,
                              actionTitle: "Open", action: { NSWorkspace.shared.open(url) }, answer: .entry(parsed))
    }
}

// MARK: Spelling

/// `text` spelled right: a word's guesses, the best first (up to 5), or the text with each misspelled word replaced by
/// its best guess. Empty when it's spelled right, or nothing fits. `language` nil: the Mac's spelling setting.
@MainActor func spellings(of text: String, language: String? = nil) -> [String] {
    let checker = NSSpellChecker.shared
    let misspelled = { (from: Int) in checker.checkSpelling(of: text, startingAt: from, language: language, wrap: false,
                                                            inSpellDocumentWithTag: 0, wordCount: nil) }
    guard misspelled(0).location != NSNotFound else { return [] }
    if !text.contains(" ") {
        return Array((checker.guesses(forWordRange: NSRange(location: 0, length: (text as NSString).length), in: text, language: language,
                                      inSpellDocumentWithTag: 0) ?? []).prefix(5))
    }
    var fixed = text as NSString, from = 0
    while case let range = checker.checkSpelling(of: fixed as String, startingAt: from, language: language, wrap: false,
                                                 inSpellDocumentWithTag: 0, wordCount: nil), range.location != NSNotFound {
        // Its best guess: autocorrect's pick is a word that's close, "leter" → "Peter".
        let word = checker.guesses(forWordRange: range, in: fixed as String, language: language, inSpellDocumentWithTag: 0)?.first
            ?? checker.correction(forWordRange: range, in: fixed as String, language: language ?? checker.language(), inSpellDocumentWithTag: 0)
        guard let word else { from = range.location + range.length; continue }
        fixed = fixed.replacingCharacters(in: range, with: word) as NSString
        from = range.location + (word as NSString).length
    }
    return fixed as String == text ? [] : [fixed as String]
}

/// `spell definately`: the word spelled right, and the other guesses; `spell` with words, the text corrected. Enter
/// copies it. The Mac's own spelling, its languages as System Settings has them.
struct SpellProvider: ResultProvider {
    var language: String? = nil
    var modes: [Mode] { [Mode(prefix: "spell ", title: "Spell", icon: .symbol("textformat.abc"), hint: "A word or a sentence")] }

    func results(for query: String) async -> [LauncherResult] {
        if let start = startRow(query, keyword: "spell", title: "Spell", hint: "Type a word: spell definately", symbol: "textformat.abc") {
            return [start]
        }
        guard query.lowercased().hasPrefix("spell ") else { return [] }
        let text = query.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let row = { (index: Int, title: String, subtitle: String) in
            LauncherResult(id: "spell:\(index)", title: title, subtitle: subtitle, icon: .symbol("textformat.abc"), score: 50 - Double(index) / 100,
                           actionTitle: "Copy", action: { copyToClipboard(title) })
        }
        let found = await MainActor.run { [language] in
            (fixes: spellings(of: text, language: language), right: NSSpellChecker.shared.checkSpelling(of: text, startingAt: 0, language: language,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound)
        }
        if found.right { return [row(0, text, "Spelled right")] }
        guard !found.fixes.isEmpty else {
            return [LauncherResult(id: "spell", title: "No spelling for “\(text)”", icon: .symbol("textformat.abc"), score: 50, actionTitle: "", action: {})]
        }
        return found.fixes.enumerated().map { row($0, $1, "Spelling of “\(text)”") }
    }
}

// MARK: Translate

/// `translate bom dia`, `translate good morning to spanish`: Apple's on-device translation (macOS 26), from the
/// language it detects to the one named, or else `[translate] default_target`, or else your first language in System
/// Settings that isn't the text's (the default target too, when the text is already in it).
/// With no text (`translate`, `translate to spanish`) it's what's on the clipboard, like the text tools. The language
/// can come first too (`translate to german hello`): that's its chip, Translate to German.
/// Enter copies it. A language pair that isn't downloaded yet gets a row that opens where to download it.
final class TranslateProvider: ResultProvider {
    private static let supported = Mutex<[Locale.Language]?>(nil) // asked once
    private static let english = Locale(identifier: "en")
    private let clipboard: @Sendable () async -> String?
    private let defaultTarget = Mutex<String?>(nil) // [translate] default_target: a language's name or code
    var modes: [Mode] {
        let icon = LauncherResult.Icon.symbol("character.bubble")
        return [Mode(prefix: "translate ", title: "Translate", icon: icon, hint: "Text, or nothing for what you copied")]
            + Self.languageChoices.map { Mode(prefix: "translate to \($0.key) ", title: "Translate to \($0.name)", icon: icon,
                                              hint: "Text, or nothing for what you copied") }
    }

    init(clipboard: @escaping @Sendable () async -> String? = { @MainActor in Clip.current(withHTML: false).text }) {
        self.clipboard = clipboard
    }

    func setDefaultTarget(_ language: String?) { defaultTarget.withLock { $0 = language } }

    /// The languages to choose from, A–Z, once `languages()` has run: what's typed after "to" ("german", one word) and
    /// its name. English and Chinese come twice from the Mac, once here.
    static var languageChoices: [(key: String, name: String)] {
        Set((supported.withLock { $0 } ?? []).map(shortName)).sorted().map { ($0.lowercased(), $0) }
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
        guard !text.isEmpty, let source = detectLanguage(text, among: supported) else { return start }
        let preferred = Locale.preferredLanguages.map(Locale.Language.init(identifier:))
        let chosen = defaultTarget.withLock { $0 }.flatMap { language($0, among: supported) }
        guard let target = target ?? ([chosen].compactMap(\.self) + preferred + [Locale.Language(identifier: "en")])
            .first(where: { $0.languageCode != source.languageCode })
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
    /// Every language it can translate gets a little weight and yours more: hints with only yours read German as
    /// Portuguese, since the recognizer picks among the hinted languages alone.
    private func detectLanguage(_ text: String, among supported: [Locale.Language]) -> Locale.Language? {
        let code = { (language: Locale.Language) in NLLanguage(rawValue: language.languageCode?.identifier ?? language.minimalIdentifier) }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = Dictionary(supported.map { (code($0), 0.1) }, uniquingKeysWith: max)
            .merging(Locale.preferredLanguages.map { (code(Locale.Language(identifier: $0)), 0.6) }, uniquingKeysWith: max)
        recognizer.processString(text)
        return recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
    }
}
