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

/// `rates` are per 1 EUR and must include EUR itself.
func convert(_ query: CurrencyQuery, rates: [String: Double]) -> Double? {
    guard let from = rates[query.from], let to = rates[query.to] else { return nil }
    return query.amount / from * to
}

/// Coinbase's rates per 1 EUR, every currency at once (`api.coinbase.com/v2/exchange-rates?currency=EUR`), crypto
/// too. nil: not that, or empty.
func parseRates(_ data: Data) -> [String: Double]? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let table = (object["data"] as? [String: Any])?["rates"] as? [String: String]
    else { return nil }
    let rates = table.compactMapValues { Double($0) }.filter { $0.value > 0 }
    return rates.isEmpty ? nil : rates.merging(["EUR": 1]) { a, _ in a }
}

/// How fresh a rate is: "Live rate, just now" or "Live rate, 4 min ago" within the hour; then "Rate from 14:05",
/// "Rate from yesterday", "Rate from Oct 23".
func rateAge(_ updated: Date, now: Date = .now) -> String {
    let minutes = Int(now.timeIntervalSince(updated) / 60), calendar = Calendar.current
    if minutes < 1 { return "Live rate, just now" }
    if minutes < 60 { return "Live rate, \(minutes) min ago" }
    if calendar.isDate(updated, inSameDayAs: now) { return "Rate from " + updated.formatted(date: .omitted, time: .shortened) }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(updated, inSameDayAs: yesterday) {
        return "Rate from yesterday"
    }
    return "Rate from " + updated.formatted(.dateTime.month(.abbreviated).day())
}

/// A currency's flag: its code's first two letters as regional indicators (EUR → 🇪🇺, the EU's). Empty for a currency
/// of no one country: BTC (not Bhutan's), XAF (six countries').
func flag(_ code: String) -> String {
    let code = code.uppercased()
    guard code == "EUR" || (Locale.commonISOCurrencyCodes.contains(code) && Locale.Region(String(code.prefix(2))).isISORegion) else { return "" }
    return String(String.UnicodeScalarView(code.unicodeScalars.prefix(2).compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }))
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
/// it as money (€21.48), the row below the number alone. `updated`: when `rates` came. Empty for a currency it lacks.
func currencyRows(_ query: CurrencyQuery, rates: [String: Double], updated: Date, now: Date = .now) -> [LauncherResult] {
    guard let value = convert(query, rates: rates), let rate = convert(CurrencyQuery(amount: 1, from: query.from, to: query.to), rates: rates)
    else { return [] }
    let english = Locale(identifier: "en_US")
    // Under 1, up to 6 decimals: a yen in euros is €0.005882, not €0.01.
    let small = { (amount: Double) in amount.magnitude < 1 && amount != 0 }
    let money = { (amount: Double, code: String) in
        let style = FloatingPointFormatStyle<Double>.Currency(code: code).locale(english)
        return amount.formatted(small(amount) ? style.precision(.fractionLength(2...6)) : style)
    }
    let name = { (code: String) in english.localizedString(forCurrencyCode: code) ?? code }
    let shown = money(value, query.to), number = formatNumber(value, decimals: small(value) ? 2...6 : 2...2)
    let card = CurrencyCard(from: money(query.amount, query.from), fromName: name(query.from), fromCode: query.from, to: shown,
                            toName: name(query.to), toCode: query.to,
                            rate: "1 \(query.from) = \(formatNumber(rate, decimals: rate < 0.01 ? 2...8 : 2...4)) \(query.to)",
                            when: rateAge(updated, now: now))
    return [LauncherResult(id: "currency", title: "Copy " + shown, icon: .symbol("arrow.left.arrow.right"), score: 10, actionTitle: "Copy",
                           action: { copyToClipboard(shown) }, answer: .currency(card)),
            LauncherResult(id: "currency:number", title: "Copy " + number, subtitle: "The number alone, for a spreadsheet",
                           icon: .symbol("number"), score: 9.99, actionTitle: "Copy", action: { copyToClipboard(number) }, answer: .currency(card))]
}

/// Answers from the in-memory copy of rates.json only; the fetch runs when the launcher opens.
actor CurrencyProvider: ResultProvider {
    private static let file = configDir.appending(path: "rates.json")
    /// Coinbase's public rates: every currency at once, so it never learns which one you convert. Updated about every
    /// minute; no key.
    private static let url = URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=EUR")!
    private var rates: [String: Double] = [:]
    private var fetched = Date.distantPast // when `rates` came
    private var refreshing = false
    private var defaultTarget = "EUR"

    init() {
        guard let data = try? Data(contentsOf: Self.file), let cached = parseRates(data) else { return }
        rates = cached
        fetched = (try? Self.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Fetches when the rates are over 5 minutes old. On failure the older rates stay in use, saying how old.
    func refreshIfStale() async {
        guard !refreshing, Date.now.timeIntervalSince(fetched) > 5 * 60 else { return }
        refreshing = true
        defer { refreshing = false }
        guard let (data, response) = try? await URLSession.shared.data(from: Self.url),
              (response as? HTTPURLResponse)?.statusCode == 200, let fresh = parseRates(data)
        else { return }
        rates = fresh
        fetched = .now
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }

    func setDefaultTarget(_ code: String) { defaultTarget = code }

    func results(for query: String) -> [LauncherResult] {
        guard let parsed = parseCurrency(query, defaultTarget: defaultTarget) else { return [] }
        guard !rates.isEmpty else {
            return [LauncherResult(id: "currency", title: "No currency rates yet",
                                   subtitle: "Waiting for the first download from Coinbase",
                                   icon: .symbol("exclamationmark.triangle"), score: 10, actionTitle: "", action: {})]
        }
        return currencyRows(parsed, rates: rates, updated: fetched)
    }
}
