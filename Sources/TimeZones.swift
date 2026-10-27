import Foundation

/// Places people say that aren't the city in their time zone's name.
private let placeAliases = [
    "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles",
    "nyc": "America/New_York", "ny": "America/New_York", "boston": "America/New_York", "miami": "America/New_York",
    "washington": "America/New_York", "dc": "America/New_York", "austin": "America/Chicago", "dallas": "America/Chicago",
    "rio": "America/Sao_Paulo", "são paulo": "America/Sao_Paulo", "brasilia": "America/Sao_Paulo",
    "uk": "Europe/London", "porto": "Europe/Lisbon",
    "india": "Asia/Kolkata", "delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
    "beijing": "Asia/Shanghai", "china": "Asia/Shanghai", "japan": "Asia/Tokyo",
]

/// "lisbon", "new york", "sf", "pst", "utc": a time zone by its city, an alias, or an abbreviation.
func timeZoneNamed(_ name: String) -> TimeZone? {
    let key = name.lowercased().trimmingCharacters(in: .whitespaces)
    guard !key.isEmpty else { return nil }
    if let id = placeAliases[key] { return TimeZone(identifier: id) }
    let city = { (id: String) in id.split(separator: "/").last.map { $0.replacing("_", with: " ").lowercased() } }
    if let id = TimeZone.knownTimeZoneIdentifiers.first(where: { city($0) == key }) { return TimeZone(identifier: id) }
    return key.count <= 5 && key.allSatisfy(\.isLetter) ? TimeZone(abbreviation: key.uppercased()) : nil
}

struct TimeZoneQuery {
    var date: Date
    var from: TimeZone
    var fromName: String? // nil: here
    var to: TimeZone
    var toName: String
}

/// `now in tokyo`, `time in tokyo`, `3pm in sf` (3pm here), `15:30 lisbon in new york`, `noon utc to sf`.
/// A time is today's, in its own place.
func parseTimeZones(_ query: String, now: Date = .now, here: TimeZone = .current) -> TimeZoneQuery? {
    guard let split = query.firstMatch(of: #/(?i)^(.+?)\s+(?:in|to)\s+(.+)$/#), let to = timeZoneNamed(String(split.2)) else { return nil }
    guard let left = String(split.1).lowercased().wholeMatch(of: #/(now|time|noon|midnight|(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)(?:\s+(.+))?/#)
    else { return nil }
    var from = here, fromName: String? = nil
    if let place = left.5 {
        guard let zone = timeZoneNamed(String(place)) else { return nil }
        (from, fromName) = (zone, String(place))
    }
    var date = now
    if left.1 != "now" && left.1 != "time" {
        var hour = left.2.flatMap { Int($0) } ?? (left.1 == "noon" ? 12 : 0)
        let minute = left.3.flatMap { Int($0) } ?? 0
        if let half = left.4 {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (half == "pm" ? 12 : 0)
        }
        guard hour < 24, minute < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = from
        guard let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        date = at
    }
    return TimeZoneQuery(date: date, from: from, fromName: fromName, to: to, toName: String(split.2))
}

/// "SF", "Tokyo", "New York": how a typed place shows.
private func displayName(_ place: String) -> String { place.count <= 3 ? place.uppercased() : place.capitalized }

/// Times in other places, ranked with math and currency. Enter copies the time.
struct TimeZoneProvider: ResultProvider {
    func results(for query: String) -> [LauncherResult] {
        guard let parsed = parseTimeZones(query) else { return [] }
        let time = { (zone: TimeZone) in
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = zone
            return parsed.date.formatted(style)
        }
        var day = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        day.timeZone = parsed.to
        let hours = Double(parsed.to.secondsFromGMT(for: parsed.date) - parsed.from.secondsFromGMT(for: parsed.date)) / 3600
        let gap = hours == 0 ? "same time" : "\(formatNumber(abs(hours), decimals: 0...2)) h \(hours > 0 ? "ahead" : "behind")"
        let target = time(parsed.to)
        return [LauncherResult(id: "timezone", title: "\(target) in \(displayName(parsed.toName))",
                               subtitle: "\(parsed.date.formatted(day)) · \(time(parsed.from)) \(parsed.fromName.map(displayName) ?? "here") · \(gap)",
                               icon: .symbol("globe.europe.africa"), score: 10, actionTitle: "Copy", action: { copyToClipboard(target) })]
    }
}
