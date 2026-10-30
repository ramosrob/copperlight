import AppKit
import CoreLocation
import Synchronization

/// A place for the forecast: its name and where it is.
struct Place: Sendable, Equatable {
    var name: String
    var latitude: Double, longitude: Double
}

/// Open-Meteo's forecast in °C and km/h: now, by the hour, by the day. Times are the place's own ("2026-10-29T19:00").
struct Forecast: Sendable {
    struct Now: Sendable { var time: String, temperature: Double, feelsLike: Double, wind: Double, code: Int, isDay: Bool }
    struct Hour: Sendable { var time: String, temperature: Double, code: Int, isDay: Bool }
    struct Day: Sendable { var date: String, code: Int, high: Double, low: Double }
    var now: Now, hours: [Hour], days: [Day]
}

/// Open-Meteo's forecast JSON (`current`, `hourly` and `daily`, as `forecastURL` asks). nil for anything else.
func parseForecast(_ data: Data) -> Forecast? {
    // Named here: the snake-case conversion would make "temperature_2m" "temperature2M".
    struct Body: Decodable {
        struct Current: Decodable {
            let time: String, temperature, feelsLike, wind: Double, code, isDay: Int
            enum CodingKeys: String, CodingKey {
                case time, temperature = "temperature_2m", feelsLike = "apparent_temperature", wind = "wind_speed_10m", code = "weather_code", isDay = "is_day"
            }
        }
        struct Hourly: Decodable {
            let time: [String], temperature: [Double?], code: [Int?], isDay: [Int?]
            enum CodingKeys: String, CodingKey { case time, temperature = "temperature_2m", code = "weather_code", isDay = "is_day" }
        }
        struct Daily: Decodable {
            let time: [String], code: [Int?], high: [Double?], low: [Double?]
            enum CodingKeys: String, CodingKey { case time, code = "weather_code", high = "temperature_2m_max", low = "temperature_2m_min" }
        }
        let current: Current, hourly: Hourly, daily: Daily
    }
    guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
    let (now, hourly, daily) = (body.current, body.hourly, body.daily)
    func at<T>(_ values: [T?], _ index: Int) -> T? { index < values.count ? values[index] : nil }
    return Forecast(
        now: .init(time: now.time, temperature: now.temperature, feelsLike: now.feelsLike, wind: now.wind, code: now.code, isDay: now.isDay == 1),
        hours: hourly.time.indices.compactMap { index in
            guard let temperature = at(hourly.temperature, index), let code = at(hourly.code, index) else { return nil }
            return .init(time: hourly.time[index], temperature: temperature, code: code, isDay: at(hourly.isDay, index) != 0)
        },
        days: daily.time.indices.compactMap { index in
            guard let code = at(daily.code, index), let high = at(daily.high, index), let low = at(daily.low, index) else { return nil }
            return .init(date: daily.time[index], code: code, high: high, low: low)
        })
}

/// Open-Meteo's geocoding answer: the first place it found. nil: none.
func parsePlace(_ data: Data) -> Place? {
    struct Body: Decodable {
        struct Result: Decodable { let name: String, latitude: Double, longitude: Double }
        let results: [Result]?
    }
    guard let first = (try? JSONDecoder().decode(Body.self, from: data))?.results?.first else { return nil }
    return Place(name: first.name, latitude: first.latitude, longitude: first.longitude)
}

/// A WMO weather code (Open-Meteo's) in words, and its symbol, by day or by night.
func weatherConditions(_ code: Int, day: Bool) -> (text: String, symbol: String) {
    switch code {
    case 0: ("Clear", day ? "sun.max.fill" : "moon.stars.fill")
    case 1: ("Mostly clear", day ? "sun.max.fill" : "moon.fill")
    case 2: ("Partly cloudy", day ? "cloud.sun.fill" : "cloud.moon.fill")
    case 3: ("Cloudy", "cloud.fill")
    case 45, 48: ("Fog", "cloud.fog.fill")
    case 51, 53, 55: ("Drizzle", "cloud.drizzle.fill")
    case 56, 57, 66, 67: ("Freezing rain", "cloud.sleet.fill")
    case 61: ("Light rain", "cloud.rain.fill")
    case 63: ("Rain", "cloud.rain.fill")
    case 65: ("Heavy rain", "cloud.heavyrain.fill")
    case 71: ("Light snow", "cloud.snow.fill")
    case 73, 77: ("Snow", "cloud.snow.fill")
    case 75: ("Heavy snow", "cloud.snow.fill")
    case 80, 81: ("Showers", day ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill")
    case 82: ("Heavy showers", "cloud.heavyrain.fill")
    case 85, 86: ("Snow showers", "cloud.snow.fill")
    case 95: ("Thunderstorm", "cloud.bolt.rain.fill")
    case 96, 99: ("Thunderstorm with hail", "cloud.bolt.rain.fill")
    default: ("Weather", "cloud.fill")
    }
}

/// "2026-10-29T19:00" or "2026-10-29", a place's own time, as a date in GMT: formatted in GMT, it reads as it does there.
private func placeTime(_ text: String) -> Date? {
    let parts = text.split { "-T:".contains($0) }.compactMap { Int($0) }
    guard parts.count >= 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                              hour: parts.count > 3 ? parts[3] : 0, minute: parts.count > 4 ? parts[4] : 0))
}

/// The forecast as the card shows it: now big, the next 7 hours after it, and the next 5 days (today first).
func weatherCard(_ forecast: Forecast, place: String, updated: Date, fahrenheit: Bool) -> WeatherCard {
    let degrees = { (celsius: Double) in fahrenheit ? celsius * 9 / 5 + 32 : celsius }
    let shown = { (celsius: Double) in "\(Int(degrees(celsius).rounded()))°" }
    let now = forecast.now, (conditions, symbol) = weatherConditions(now.code, day: now.isDay)
    let wind = fahrenheit ? "\(Int((now.wind / 1.609344).rounded())) mph" : "\(Int(now.wind.rounded())) km/h"
    let details = [forecast.days.first.map { "H \(shown($0.high)) · L \(shown($0.low))" }, "Feels like \(shown(now.feelsLike))", "Wind \(wind)"]
        .compactMap(\.self).joined(separator: " · ")
    let clock = Date.FormatStyle(timeZone: .gmt).hour().minute(), weekday = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated)
    let start = forecast.hours.firstIndex { $0.time == now.time.prefix(13) + ":00" } ?? forecast.hours.firstIndex { $0.time > now.time } ?? 0
    let hours = [WeatherCard.Hour(label: "Now", symbol: symbol, temperature: shown(now.temperature))]
        + forecast.hours.dropFirst(start + 1).prefix(7).map { hour in
            WeatherCard.Hour(label: placeTime(hour.time)?.formatted(clock) ?? hour.time,
                             symbol: weatherConditions(hour.code, day: hour.isDay).symbol, temperature: shown(hour.temperature))
        }
    let days = forecast.days.prefix(5).enumerated().map { index, day in
        WeatherCard.Day(label: index == 0 ? "Today" : placeTime(day.date)?.formatted(weekday) ?? day.date,
                        symbol: weatherConditions(day.code, day: true).symbol, low: degrees(day.low), high: degrees(day.high))
    }
    return WeatherCard(place: place, temperature: shown(now.temperature), symbol: symbol, conditions: conditions, details: details,
                       hours: hours, days: days, updated: "Open-Meteo · updated \(updated.formatted(date: .omitted, time: .shortened))")
}

/// Whether Location Services lets Copperlight know where this Mac is.
enum LocationStatus: Sendable { case unasked, allowed, refused }

/// Where this Mac is, from Location Services: asked for once, from a row, never while typing.
@MainActor final class Locator: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = Locator()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer // the forecast gets it rounded to a kilometer anyway
    }

    nonisolated static var status: LocationStatus {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined: .unasked
        case .denied, .restricted: .refused
        default: .allowed
        }
    }

    func ask() { manager.requestWhenInUseAuthorization() }

    /// Where it is: a fix from the last half hour, else a new one (at most 10 seconds). nil: it couldn't tell.
    func coordinate() async -> CLLocationCoordinate2D? {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -1800 { return recent.coordinate }
        return await withCheckedContinuation { done in
            waiting.append(done)
            guard waiting.count == 1 else { return }
            manager.requestLocation()
            Task { try? await Task.sleep(for: .seconds(10)); finish(nil) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finish(locations.last?.coordinate) }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) { finish(nil) }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let done = waiting
        waiting = []
        done.forEach { $0.resume(returning: coordinate) }
    }

    /// Where this Mac is, named by its town (Apple's geocoder). nil: Location Services couldn't tell.
    nonisolated static func here() async -> Place? {
        guard let coordinate = await shared.coordinate() else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let name = try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
        return Place(name: name ?? "Where you are", latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// The forecast for a place, from Open-Meteo: free, no key. Its coordinates go rounded to 2 decimals, about a kilometer.
private func forecastURL(_ place: Place) -> URL? {
    var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    url.queryItems = [
        .init(name: "latitude", value: String(format: "%.2f", place.latitude)), .init(name: "longitude", value: String(format: "%.2f", place.longitude)),
        .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"),
        .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
        .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
        .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "6"),
    ]
    return url.url
}

/// A place by its name, from Open-Meteo's geocoding: the best match.
private func placeURL(_ name: String) -> URL? {
    var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
    url.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1"), .init(name: "language", value: "en")]
    return url.url
}

/// `weather`: the Weather chip. Nothing typed: where you are (Location Services, asked for once from a row, never while
/// typing), else the city set in Settings; a city typed: that city. Only once typing pauses does the place go to
/// Open-Meteo (free, no key; where you are rounded to about a kilometer); the forecast takes the card: now big, the next
/// hours and five days. Kept for 10 minutes. Enter opens the Weather app.
final class WeatherProvider: ResultProvider {
    private static let cache = Mutex<[String: (fetched: Date, place: String, forecast: Forecast)]>([:])
    private static let icon = "cloud.sun"
    private let pause: Duration
    private let city: Mutex<String> // [weather] city
    private let status: @Sendable () -> LocationStatus
    private let locate: @Sendable () async -> Place?
    private let fetch: @Sendable (URL) async -> Data?
    private let fahrenheit: Bool
    var modes: [Mode] { [Mode(prefix: "weather ", title: "Weather", icon: .symbol(Self.icon), hint: "A city, or nothing for where you are")] }

    init(pause: Duration = .milliseconds(350), city: String = "", status: @escaping @Sendable () -> LocationStatus = { Locator.status },
         locate: @escaping @Sendable () async -> Place? = { await Locator.here() },
         fahrenheit: Bool = Locale.current.measurementSystem == .us, // °F and mph where the Mac uses US units
         fetch: @escaping @Sendable (URL) async -> Data? = { url in
             guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 6)),
                   (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
             return data
         }) {
        self.city = Mutex(city) // a Mutex can't go in a tuple
        (self.pause, self.status, self.locate, self.fahrenheit, self.fetch) = (pause, status, locate, fahrenheit, fetch)
    }

    func setCity(_ name: String) { city.withLock { $0 = name.trimmingCharacters(in: .whitespaces) } }

    func results(for query: String) async -> [LauncherResult] {
        startRow(query, keyword: "weather", title: "Weather", hint: "Where you are, or a city: weather lisbon", symbol: Self.icon).map { [$0] } ?? []
    }

    func modeResults(for query: String) async -> [LauncherResult] {
        let typed = query.dropFirst(8).trimmingCharacters(in: .whitespaces), city = self.city.withLock { $0 }
        let here = typed.isEmpty ? status() : .refused
        if typed.isEmpty, city.isEmpty, here == .unasked {
            return [LauncherResult(id: "weather", title: "Weather Where You Are", subtitle: "Asks for your location, once · or type a city",
                                   icon: .symbol(Self.icon), score: 50, actionTitle: "Allow", action: { Locator.shared.ask() })]
        }
        if typed.isEmpty, city.isEmpty, here == .refused {
            return [note("Type a city, or set yours in Settings", "Location Services is off for Copperlight")]
        }
        let key = typed.isEmpty && here == .allowed ? "" : (typed.isEmpty ? city : typed).lowercased()
        if let cached = Self.cache.withLock({ $0[key] }), Date.now.timeIntervalSince(cached.fetched) < 600 {
            return [row(cached.forecast, place: cached.place, updated: cached.fetched)]
        }
        try? await Task.sleep(for: pause) // the next keystroke cancels this round, so only a pause asks Open-Meteo
        guard !Task.isCancelled else { return [] }
        let place: Place
        if key.isEmpty {
            guard let found = await locate() else { return [note("Couldn't tell where you are", "Type a city instead: weather lisbon")] }
            place = found
        } else {
            guard let url = placeURL(key), let data = await fetch(url) else { return [note("Couldn't reach Open-Meteo", "Check the connection and try again")] }
            guard let found = parsePlace(data) else { return [note("No place called \(typed.isEmpty ? city : typed)", "Try another spelling, or a bigger town nearby")] }
            place = found
        }
        guard !Task.isCancelled, let url = forecastURL(place), let data = await fetch(url) else {
            return Task.isCancelled ? [] : [note("Couldn't reach Open-Meteo", "Check the connection and try again")]
        }
        guard let forecast = parseForecast(data) else { return [note("Open-Meteo sent no forecast", "Try again in a moment")] }
        Self.cache.withLock { $0[key] = (.now, place.name, forecast) }
        return [row(forecast, place: place.name, updated: .now)]
    }

    private func note(_ title: String, _ subtitle: String) -> LauncherResult {
        LauncherResult(id: "weather", title: title, subtitle: subtitle, icon: .symbol(Self.icon), score: 50, actionTitle: "", action: {})
    }

    private func row(_ forecast: Forecast, place: String, updated: Date) -> LauncherResult {
        let card = weatherCard(forecast, place: place, updated: updated, fahrenheit: fahrenheit)
        let today = card.days.first.map { " · H \(Int($0.high.rounded()))° L \(Int($0.low.rounded()))°" } ?? ""
        return LauncherResult(id: "weather:\(place)", title: "\(card.temperature) · \(card.conditions)", subtitle: place + today,
                              icon: .symbol(Self.icon), score: 50, actionTitle: "Open", action: {
            NSWorkspace.shared.openApplication(at: URL(filePath: "/System/Applications/Weather.app"), configuration: .init())
        }, answer: .weather(card))
    }
}
