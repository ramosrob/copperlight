import AppKit

struct CurrencyQuery: Equatable {
    var amount: Double
    var from: String
    var to: String
}

/// `25USD to EUR`, `25 usd in eur`, `25usd eur`, `12,50 gbp usd`, and math before it (`39*8 usd`). Case-insensitive.
/// With no target (`25 usd`) it converts to `defaultTarget`, or to USD when that's the source
/// (EUR if the default is USD itself), so `25 eur` still shows something.
func parseCurrency(_ query: String, defaultTarget: String = "EUR") -> CurrencyQuery? {
    let pattern = #/([\d(][\d.,\s+\-*\/^()]*?)\s*([a-z]{3})(?:\s+(?:(?:to|in)\s+)?([a-z]{3}))?/#.ignoresCase()
    guard let match = query.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern) else { return nil }
    let number = String(match.1)
    let amount = number.wholeMatch(of: #/\d+(?:[.,]\d+)?/#) != nil ? Double(number.replacing(",", with: "."))
        : number.contains(where: "+-*/^".contains) ? calculate(number).flatMap { $0 >= 0 && $0.isFinite ? $0 : nil } : nil
    guard let amount else { return nil }
    let from = match.2.uppercased()
    let to = match.3?.uppercased() ?? (from != defaultTarget ? defaultTarget : from == "USD" ? "EUR" : "USD")
    return CurrencyQuery(amount: amount, from: from, to: to)
}

/// `rates` are per 1 EUR (Frankfurter's default base) and must include EUR itself.
func convert(_ query: CurrencyQuery, rates: [String: Double]) -> Double? {
    guard let from = rates[query.from], let to = rates[query.to] else { return nil }
    return query.amount / from * to
}

/// A currency's flag: its code's first two letters as regional indicators (EUR → 🇪🇺, the EU's).
func flag(_ code: String) -> String {
    String(String.UnicodeScalarView(code.uppercased().unicodeScalars.filter { (65...90).contains($0.value) }.prefix(2)
        .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }))
}

/// A flag emoji as a picture cut to the flag itself, so it can be drawn whole at any height. nil: nothing to draw.
func flagPicture(_ flag: String) -> CGImage? {
    let text = NSAttributedString(string: flag, attributes: [.font: NSFont.systemFont(ofSize: 160)]), size = text.size()
    guard !flag.isEmpty, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    text.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    guard let pixels = rep.bitmapData else { return nil }
    var (left, top, right, bottom) = (rep.pixelsWide, rep.pixelsHigh, -1, -1)
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where pixels[y * rep.bytesPerRow + x * 4 + 3] > 8 {
            (left, top, right, bottom) = (min(left, x), min(top, y), max(right, x), max(bottom, y))
        }
    }
    guard right >= left else { return nil }
    return rep.cgImage?.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
}

/// The conversion on a band (what you had → what it makes, the rate, its flags behind), and its two rows: Enter copies
/// it as money (€21.48), the row below the number alone. `date`: the ECB's, of `rates`. Empty for a currency it lacks.
func currencyRows(_ query: CurrencyQuery, rates: [String: Double], date: String, now: Date = .now) -> [LauncherResult] {
    guard let value = convert(query, rates: rates), let rate = convert(CurrencyQuery(amount: 1, from: query.from, to: query.to), rates: rates)
    else { return [] }
    let english = Locale(identifier: "en_US"), calendar = Calendar.current
    let money = { (amount: Double, code: String) in amount.formatted(.currency(code: code).locale(english)) }
    let name = { (code: String) in english.localizedString(forCurrencyCode: code) ?? code }
    let parts = date.split(separator: "-").compactMap { Int($0) }
    let day = parts.count == 3 ? calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) : nil
    let when = day.map { day in
        calendar.isDate(day, inSameDayAs: now) ? "ECB rate, today"
            : calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(day, inSameDayAs: $0) } == true ? "ECB rate, yesterday"
            : "ECB rate of " + day.formatted(.dateTime.month(.abbreviated).day())
    } ?? "ECB rate"
    let shown = money(value, query.to), number = formatNumber(value, decimals: 2...2)
    let card = CurrencyCard(from: money(query.amount, query.from), fromName: name(query.from), fromCode: query.from, to: shown,
                            toName: name(query.to), toCode: query.to,
                            rate: "1 \(query.from) = \(formatNumber(rate, decimals: 2...4)) \(query.to)", when: when)
    return [LauncherResult(id: "currency", title: "Copy " + shown, icon: .symbol("arrow.left.arrow.right"), score: 10, actionTitle: "Copy",
                           action: { copyToClipboard(shown) }, answer: .currency(card)),
            LauncherResult(id: "currency:number", title: "Copy " + number, subtitle: "The number alone, for a spreadsheet",
                           icon: .symbol("number"), score: 9.99, actionTitle: "Copy", action: { copyToClipboard(number) }, answer: .currency(card))]
}

/// Answers from the in-memory copy of rates.json only; the network fetch runs separately.
actor CurrencyProvider: ResultProvider {
    private struct Rates: Decodable { var date: String, rates: [String: Double] }

    private static let file = configDir.appending(path: "rates.json")
    private static let url = URL(string: "https://api.frankfurter.dev/v1/latest")!
    private var rates: [String: Double] = [:]
    private var date = "" // ECB publication date of `rates`
    private var fetched = Date.distantPast
    private var refreshing = false
    private var defaultTarget = "EUR"

    init() {
        guard let data = try? Data(contentsOf: Self.file), let cached = Self.decode(data) else { return }
        (rates, date) = cached
        fetched = (try? Self.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private static func decode(_ data: Data) -> (rates: [String: Double], date: String)? {
        guard let decoded = try? JSONDecoder().decode(Rates.self, from: data) else { return nil }
        return (decoded.rates.merging(["EUR": 1]) { a, _ in a }, decoded.date)
    }

    /// Fetches when the cache is over 24 h old. On failure the stale rates stay in use.
    func refreshIfStale() async {
        guard !refreshing, Date.now.timeIntervalSince(fetched) > 24 * 3600 else { return }
        refreshing = true
        defer { refreshing = false }
        guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
              (response as? HTTPURLResponse)?.statusCode == 200, let fresh = Self.decode(data)
        else { return }
        (rates, date) = fresh
        fetched = .now
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }

    func setDefaultTarget(_ code: String) { defaultTarget = code }

    func results(for query: String) -> [LauncherResult] {
        guard let parsed = parseCurrency(query, defaultTarget: defaultTarget) else { return [] }
        guard !rates.isEmpty else {
            return [LauncherResult(id: "currency", title: "No currency rates yet",
                                   subtitle: "Waiting for the first download from frankfurter.dev",
                                   icon: .symbol("exclamationmark.triangle"), score: 10, actionTitle: "", action: {})]
        }
        return currencyRows(parsed, rates: rates, date: date)
    }
}
