import AppKit
import Synchronization

/// A stock's price now and its last 7 days, from Yahoo Finance's chart data.
struct StockQuote: Sendable, Equatable {
    let symbol: String, name: String, currency: String
    let price: Double
    let previousClose: Double? // yesterday's, for today's change
    let closes: [Double] // hourly over the 7 days, gaps left out
    let exchange: String
    let time: Date?
}

/// "aapl", "mglu3.sa", "^bvsp", "brl=x", "btc-usd": a ticker as Yahoo writes it; nil for anything else (words, spaces).
func stockSymbol(_ text: String) -> String? {
    let symbol = text.trimmingCharacters(in: .whitespaces).uppercased()
    return symbol.wholeMatch(of: #/[A-Z0-9^][A-Z0-9.=\-^]{0,14}/#) != nil ? symbol : nil
}

/// Yahoo's chart JSON. nil when it names no stock ("No data found") or isn't chart data.
func parseStockChart(_ data: Data) -> StockQuote? {
    struct Chart: Decodable {
        struct Body: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta; let indicators: Indicators }
        struct Meta: Decodable {
            let symbol: String, currency: String?, regularMarketPrice: Double?, previousClose: Double?
            let longName: String?, shortName: String?, fullExchangeName: String?, regularMarketTime: Double?
        }
        struct Indicators: Decodable { let quote: [Closes] }
        struct Closes: Decodable { let close: [Double?]? }
        let chart: Body
    }
    guard let result = (try? JSONDecoder().decode(Chart.self, from: data))?.chart.result?.first,
          let price = result.meta.regularMarketPrice else { return nil }
    let meta = result.meta
    return StockQuote(symbol: meta.symbol, name: meta.longName ?? meta.shortName ?? meta.symbol, currency: meta.currency ?? "USD",
                      price: price, previousClose: meta.previousClose,
                      closes: result.indicators.quote.first?.close?.compactMap(\.self) ?? [], exchange: meta.fullExchangeName ?? "",
                      time: meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) })
}

/// The last 7 days, hourly, as Yahoo's chart data (or its "No data found" answer). nil when Yahoo can't be reached.
/// ponytail: Yahoo's public chart endpoint has no key and no promise; if it changes, `stock` says it can't reach it.
func fetchStockChart(_ symbol: String) async -> Data? {
    let now = Int(Date.now.timeIntervalSince1970)
    var url = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
    url.path += symbol
    url.queryItems = [.init(name: "period1", value: "\(now - 7 * 86400)"), .init(name: "period2", value: "\(now)"),
                      .init(name: "interval", value: "1h")]
    guard let url = url.url else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 5)
    // Unnamed requests are turned away ("too many requests"); this says who's asking.
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    request.setValue("Copperlight/\(version)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          [200, 404].contains((response as? HTTPURLResponse)?.statusCode) else { return nil }
    return data
}

/// `stock AAPL`, `stock MGLU3.SA`: the price now, today's change and the last 7 days, across the whole card. Enter opens
/// the stock on Yahoo Finance. Only in the Stock chip (Tab), and only once typing pauses, does the ticker go to Yahoo;
/// an answer is kept for a minute. Typed without the chip, "stock apple" may be a file's name: a row offers the chip.
struct StockProvider: ResultProvider {
    private static let cache = Mutex<[String: (fetched: Date, quote: StockQuote)]>([:])
    private static let icon = "chart.line.uptrend.xyaxis"
    var pause = Duration.milliseconds(350)
    var locale = Locale.current
    var fetch: @Sendable (String) async -> Data? = { await fetchStockChart($0) }
    var modes: [Mode] { [Mode(prefix: "stock ", title: "Stock", icon: .symbol(Self.icon), hint: "A ticker: AAPL, MGLU3.SA")] }

    func results(for query: String) async -> [LauncherResult] {
        if let start = startRow(query, keyword: "stock", title: "Stock", hint: "Type a ticker: stock AAPL", symbol: Self.icon) {
            return [start]
        }
        let typed = query.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard query.lowercased().hasPrefix("stock "), let symbol = stockSymbol(typed) else { return [] }
        // Under the files and apps it may also be, over the search row; Tab (or Enter) makes it the chip, which asks.
        return [LauncherResult(id: "stock:offer", title: "Stock Price of \(symbol)", subtitle: "From Yahoo Finance",
                               icon: .symbol(Self.icon), score: -5, actionTitle: "Look Up", action: {}, completion: "stock " + typed)]
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        let typed = query.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        guard let symbol = stockSymbol(typed) else { return [note("Type a ticker, like AAPL", "Yahoo Finance's symbol: MGLU3.SA, ^BVSP")] }
        if let cached = Self.cache.withLock({ $0[symbol] }), Date.now.timeIntervalSince(cached.fetched) < 60 { return [row(cached.quote)] }
        // The card's shape at once, with the ticker; the price fills it in.
        return [LauncherResult(id: "stock", title: "Stock Price of \(symbol)", subtitle: "Asking Yahoo Finance…", icon: .symbol(Self.icon),
                               score: 50, actionTitle: "", action: {}, answer: .stock(.loading(symbol)), later: { await quote(symbol) })]
    }

    private func quote(_ symbol: String) async -> [LauncherResult] {
        try? await Task.sleep(for: pause) // the next keystroke cancels this round, so only a pause asks Yahoo
        guard !Task.isCancelled else { return [] }
        guard let data = await fetch(symbol) else { return [note("Couldn't reach Yahoo Finance", "Check the connection and try again")] }
        guard let quote = parseStockChart(data) else { return [note("No stock called \(symbol)", "Yahoo Finance has no such ticker")] }
        Self.cache.withLock { $0[symbol] = (.now, quote) }
        return [row(quote)]
    }

    private func note(_ title: String, _ subtitle: String) -> LauncherResult {
        LauncherResult(id: "stock", title: title, subtitle: subtitle, icon: .symbol(Self.icon), score: 50, actionTitle: "", action: {})
    }

    private func row(_ quote: StockQuote) -> LauncherResult {
        let money = { (value: Double) in value.formatted(.currency(code: quote.currency).locale(locale)) }
        let change = { (from: Double) in
            (quote.price / from - 1).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(locale))
        }
        let today = quote.previousClose.map(change)
        let url = URL(string: "https://finance.yahoo.com/quote/\(quote.symbol)")
        let up = quote.previousClose.map { quote.price >= $0 } ?? true
        let facts: [(String, String?)] = [("Previous close", quote.previousClose.map(money)), ("7 days", quote.closes.first.map(change))]
        let card = StockCard(
            kicker: "\(quote.symbol) · \(quote.name)", price: money(quote.price),
            change: today.map { "\(up ? "▲" : "▼") \($0.trimmingPrefix(/[+\-−]/)) today" } ?? "", up: up,
            corner: [quote.time?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)), quote.exchange.isEmpty ? nil : quote.exchange]
                .compactMap(\.self).joined(separator: " · "),
            closes: quote.closes, previousClose: quote.previousClose,
            facts: facts.compactMap { label, value in value.map { (label, $0) } }, action: "Open in Yahoo Finance")
        return LauncherResult(
            id: "stock:\(quote.symbol)", title: money(quote.price),
            subtitle: [quote.symbol, quote.name, today.map { "\($0) today" }].compactMap(\.self).joined(separator: " · "),
            icon: .symbol(Self.icon), score: 50, actionTitle: "Open", action: { if let url { NSWorkspace.shared.open(url) } }, answer: .stock(card))
    }
}
