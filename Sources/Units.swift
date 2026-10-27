import Foundation

/// A unit by the name people type ("km", "miles", "°c", "lbs"). Foundation does the math, so it's only names.
func unitNamed(_ name: String) -> Dimension? {
    switch name.lowercased() {
    case "mm", "millimeter", "millimeters": UnitLength.millimeters
    case "cm", "centimeter", "centimeters": UnitLength.centimeters
    case "m", "meter", "meters", "metre", "metres": UnitLength.meters
    case "km", "kilometer", "kilometers", "kilometre", "kilometres": UnitLength.kilometers
    case "in", "inch", "inches", "\"": UnitLength.inches
    case "ft", "foot", "feet", "'": UnitLength.feet
    case "yd", "yard", "yards": UnitLength.yards
    case "mi", "mile", "miles": UnitLength.miles
    case "nmi": UnitLength.nauticalMiles
    case "mg": UnitMass.milligrams
    case "g", "gram", "grams": UnitMass.grams
    case "kg", "kilo", "kilos", "kilogram", "kilograms": UnitMass.kilograms
    case "t", "tonne", "tonnes": UnitMass.metricTons
    case "oz", "ounce", "ounces": UnitMass.ounces
    case "lb", "lbs", "pound", "pounds": UnitMass.pounds
    case "st", "stone", "stones": UnitMass.stones
    case "c", "°c", "celsius": UnitTemperature.celsius
    case "f", "°f", "fahrenheit": UnitTemperature.fahrenheit
    case "k", "kelvin": UnitTemperature.kelvin
    case "ml": UnitVolume.milliliters
    case "l", "liter", "liters", "litre", "litres": UnitVolume.liters
    case "tsp": UnitVolume.teaspoons
    case "tbsp": UnitVolume.tablespoons
    case "floz": UnitVolume.fluidOunces
    case "cup", "cups": UnitVolume.cups
    case "pt", "pint", "pints": UnitVolume.pints
    case "qt", "quart", "quarts": UnitVolume.quarts
    case "gal", "gallon", "gallons": UnitVolume.gallons
    case "kmh", "km/h", "kph": UnitSpeed.kilometersPerHour
    case "mph": UnitSpeed.milesPerHour
    case "m/s", "mps": UnitSpeed.metersPerSecond
    case "kn", "knot", "knots": UnitSpeed.knots
    case "b", "byte", "bytes": UnitInformationStorage.bytes
    case "kb": UnitInformationStorage.kilobytes
    case "mb": UnitInformationStorage.megabytes
    case "gb": UnitInformationStorage.gigabytes
    case "tb": UnitInformationStorage.terabytes
    case "kib": UnitInformationStorage.kibibytes
    case "mib": UnitInformationStorage.mebibytes
    case "gib": UnitInformationStorage.gibibytes
    case "tib": UnitInformationStorage.tebibytes
    case "ms": UnitDuration.milliseconds
    case "s", "sec", "secs", "second", "seconds": UnitDuration.seconds
    case "min", "mins", "minute", "minutes": UnitDuration.minutes
    case "h", "hr", "hrs", "hour", "hours": UnitDuration.hours
    case "d", "day", "days": UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    case "wk", "week", "weeks": UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))
    case "m2", "m²", "sqm": UnitArea.squareMeters
    case "km2", "km²": UnitArea.squareKilometers
    case "ft2", "ft²", "sqft": UnitArea.squareFeet
    case "ha", "hectare", "hectares": UnitArea.hectares
    case "acre", "acres": UnitArea.acres
    default: nil
    }
}

/// Where `10 km` goes with no target: across metric and US units, by the source's symbol.
private let defaultTargets = [
    "km": "mi", "mi": "km", "m": "ft", "ft": "m", "cm": "in", "in": "cm", "mm": "in", "yd": "m",
    "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "st": "kg", "t": "lb",
    "°C": "f", "°F": "c", "K": "c",
    "L": "gal", "gal": "l", "mL": "floz", "fl oz": "ml", "cup": "ml", "pt": "l", "qt": "l",
    "km/h": "mph", "mph": "kmh", "m/s": "kmh", "kn": "kmh",
    "m²": "ft2", "ft²": "m2", "ha": "acre", "ac": "ha",
]

struct UnitQuery {
    var value: Double
    var from: Dimension
    var to: Dimension
}

/// `10 km in mi`, `10km mi`, `30c`, `5'` (feet), `10 in in cm`. Without a target, metric and US units convert to
/// each other (`10 km` → miles). nil unless both units exist and measure the same thing.
func parseUnits(_ query: String) -> UnitQuery? {
    guard let match = query.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/(-?\d+(?:[.,]\d+)?)\s*(\S.*)/#),
          let value = Double(match.1.replacing(",", with: "."))
    else { return nil }
    var words = match.2.split(whereSeparator: \.isWhitespace).map(String.init)
    if words.count == 3, ["in", "to", "as", "="].contains(words[1].lowercased()) { words.remove(at: 1) }
    guard (1...2).contains(words.count), let from = unitNamed(words[0]),
          let to = words.count == 2 ? unitNamed(words[1]) : defaultTargets[from.symbol].flatMap(unitNamed),
          // The same dimension: Foundation's own units are private subclasses, so compare base units, not types.
          type(of: from).baseUnit().symbol == type(of: to).baseUnit().symbol, from.symbol != to.symbol
    else { return nil }
    return UnitQuery(value: value, from: from, to: to)
}

/// Unit conversions, ranked with math and currency. Enter copies the number.
struct UnitProvider: ResultProvider {
    func results(for query: String) -> [LauncherResult] {
        guard let parsed = parseUnits(query) else { return [] }
        let value = Measurement(value: parsed.value, unit: parsed.from).converted(to: parsed.to).value
        let number = formatNumber(value, decimals: 0...4)
        return [LauncherResult(id: "units", title: "\(number) \(parsed.to.symbol)",
                               subtitle: "\(formatNumber(parsed.value)) \(parsed.from.symbol)", icon: .symbol("ruler"), score: 10,
                               actionTitle: "Copy", action: { copyToClipboard(number) })]
    }
}
