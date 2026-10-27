import Foundation

struct CurrencyQuery: Equatable {
    var amount: Double
    var from: String
    var to: String
}

/// `25USD to EUR`, `25 usd in eur`, `25usd eur`, `12,50 gbp usd`. Case-insensitive.
/// With no target (`25 usd`) it converts to `defaultTarget`, or to USD when that's the source
/// (EUR if the default is USD itself), so `25 eur` still shows something.
func parseCurrency(_ query: String, defaultTarget: String = "EUR") -> CurrencyQuery? {
    let pattern = #/(\d+(?:[.,]\d+)?)\s*([a-z]{3})(?:\s+(?:(?:to|in)\s+)?([a-z]{3}))?/#.ignoresCase()
    guard let match = query.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern),
          let amount = Double(match.1.replacing(",", with: "."))
    else { return nil }
    let from = match.2.uppercased()
    let to = match.3?.uppercased() ?? (from != defaultTarget ? defaultTarget : from == "USD" ? "EUR" : "USD")
    return CurrencyQuery(amount: amount, from: from, to: to)
}

/// `rates` are per 1 EUR (Frankfurter's default base) and must include EUR itself.
func convert(_ query: CurrencyQuery, rates: [String: Double]) -> Double? {
    guard let from = rates[query.from], let to = rates[query.to] else { return nil }
    return query.amount / from * to
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
        guard let value = convert(parsed, rates: rates) else { return [] }
        let number = formatNumber(value, decimals: 2...2)
        return [LauncherResult(id: "currency", title: "\(number) \(parsed.to)",
                               subtitle: "\(formatNumber(parsed.amount)) \(parsed.from) · ECB rate of \(date)",
                               icon: .symbol("arrow.left.arrow.right"), score: 10, actionTitle: "Copy",
                               action: { copyToClipboard(number) })]
    }
}
