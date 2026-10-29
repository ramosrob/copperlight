import AppKit

/// A color in sRGB, 0–255 a channel, in the notations CSS and design apps write.
struct RGBColor: Equatable, Sendable {
    let red: Int, green: Int, blue: Int

    var hex: String { "#" + [red, green, blue].map { String(format: "%02x", $0) }.joined() }
    var rgb: String { "rgb(\(red), \(green), \(blue))" }
    var hsl: String {
        let (r, g, b) = (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
        let high = max(r, g, b), low = min(r, g, b), spread = high - low
        let lightness = (high + low) / 2
        let saturation = spread == 0 ? 0 : spread / (1 - abs(2 * lightness - 1))
        let hue: Double = switch high {
        case _ where spread == 0: 0
        case r: 60 * ((g - b) / spread).truncatingRemainder(dividingBy: 6)
        case g: 60 * ((b - r) / spread + 2)
        default: 60 * ((r - g) / spread + 4)
        }
        let degrees = Int(hue.rounded()) % 360
        return "hsl(\(degrees < 0 ? degrees + 360 : degrees), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    /// hue in degrees, saturation and lightness 0–1.
    init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue.truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b) = switch Int(sector) {
        case 0: (chroma, x, 0.0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        self.init(red: Int(((r + m) * 255).rounded()), green: Int(((g + m) * 255).rounded()), blue: Int(((b + m) * 255).rounded()))
    }

    init(red: Int, green: Int, blue: Int) { (self.red, self.green, self.blue) = (red, green, blue) }

    /// A color from the screen (Display P3, usually) in sRGB, what hex codes mean.
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        self.init(red: channel(srgb.redComponent), green: channel(srgb.greenComponent), blue: channel(srgb.blueComponent))
    }
}

extension RGBColor {
    static let white = RGBColor(red: 255, green: 255, blue: 255), black = RGBColor(red: 0, green: 0, blue: 0)

    /// How light it looks, 0–1 (WCAG's relative luminance).
    var luminance: Double {
        let linear = { (channel: Int) in
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG's contrast ratio, 1–21: 4.5 or more reads well as text.
    func contrast(with other: RGBColor) -> Double {
        let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    /// Part of the way to white (0.25: a quarter), or to black for a negative amount.
    func mixed(_ amount: Double) -> RGBColor {
        let toward = { (channel: Int) in
            Int((amount >= 0 ? Double(channel) + (255 - Double(channel)) * amount : Double(channel) * (1 + amount)).rounded())
        }
        return RGBColor(red: toward(red), green: toward(green), blue: toward(blue))
    }
}

enum ColorNotation: CaseIterable { case hex, rgb, hsl }

/// "#ff8800", "#f80", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)" (spaces for commas too): the color, and how it was
/// written. nil for anything else: a bare "ff8800" may be a file's name or a hash.
func parseColor(_ text: String) -> (color: RGBColor, notation: ColorNotation)? {
    let text = text.trimmingCharacters(in: .whitespaces)
    if let match = text.wholeMatch(of: #/#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})/#) {
        let hex = match.1.count == 3 ? match.1.map { "\($0)\($0)" }.joined() : String(match.1)
        let value = Int(hex, radix: 16)!
        return (RGBColor(red: value >> 16, green: value >> 8 & 0xff, blue: value & 0xff), .hex)
    }
    if let match = text.wholeMatch(of: #/(?i)rgb\(\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*[,\s]\s*(\d{1,3})\s*\)/#) {
        let parts = [match.1, match.2, match.3].compactMap { Int($0) }
        guard parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (RGBColor(red: parts[0], green: parts[1], blue: parts[2]), .rgb)
    }
    if let match = text.wholeMatch(of: #/(?i)hsl\(\s*(\d{1,3})(?:deg)?\s*[,\s]\s*(\d{1,3})%\s*[,\s]\s*(\d{1,3})%\s*\)/#),
       let hue = Double(match.1), let saturation = Double(match.2), let lightness = Double(match.3),
       hue <= 360, saturation <= 100, lightness <= 100 {
        return (RGBColor(hue: hue, saturation: saturation / 100, lightness: lightness / 100), .hsl)
    }
    return nil
}

/// A color picked off the screen, kept for `colors` in state.json: the last 30, newest first.
struct PickedColor: Codable, Equatable, Sendable {
    static let stateSection = "colors"
    static let limit = 30
    var hex: String
    var at: Date
}

/// Keeps a picked color, on top, once.
@MainActor func rememberColor(_ color: RGBColor, in store: StateStore, at date: Date = .now) {
    let kept = store.get(PickedColor.stateSection, as: [PickedColor].self) ?? []
    store.set(PickedColor.stateSection, Array(([PickedColor(hex: color.hex, at: date)] + kept.filter { $0.hex != color.hex }).prefix(PickedColor.limit)))
}

/// A color typed in one notation (`#c87533`, `rgb(…)`, `hsl(…)`) in the others and a step lighter and darker, under a
/// band of the color with its contrast on white and black; Enter copies. `pick color` picks one off the screen with macOS's magnifier: its hex is copied and the launcher comes back
/// showing it, so the other notations are a row away. Picked colors are kept: `colors` lists them, newest first.
struct ColorProvider: ResultProvider {
    /// Opens the launcher with this typed in.
    var show: @MainActor @Sendable (String) -> Void = { _ in }
    /// Where picked colors are kept; nil: not kept.
    var store: StateStore? = nil

    func results(for query: String) async -> [LauncherResult] {
        if let (color, typed) = parseColor(query) {
            let notations = ColorNotation.allCases.filter { $0 != typed } + [typed]
            return notations.enumerated().map { index, notation in row(color, notation, score: 50 - Double(index) / 10) }
                + [(0.25, "A step lighter"), (-0.25, "A step darker")].enumerated().map { index, step in
                    let shade = color.mixed(step.0)
                    return LauncherResult(id: "color:\(step.1)", title: shade.hex, subtitle: step.1, icon: .color(shade), score: 49.6 - Double(index) / 10,
                                          actionTitle: "Copy", action: { copyToClipboard(shade.hex) }, answer: .color(color))
                }
        }
        let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "colors" || lower == "colours" || otherNameScore(lower, "Your Colors") != nil { return await keptRows() }
        guard let score = lower.count >= 3 && "pick color".hasPrefix(lower) ? 50 : fuzzyScore(query, "Pick Color") ?? otherNameScore(query, "Pick Color")
        else { return [] }
        return [pickRow(subtitle: "Click anywhere on the screen to copy its color", score: score)]
    }

    private func pickRow(subtitle: String, score: Double) -> LauncherResult {
        LauncherResult(id: "builtin:pick color", title: "Pick Color", subtitle: subtitle, icon: .symbol("eyedropper"), score: score,
                       actionTitle: "Pick", action: { [show, store] in
            NSColorSampler().show { picked in
                guard let color = picked.flatMap(RGBColor.init) else { return } // Esc: nothing picked
                Task { @MainActor in
                    copyToClipboard(color.hex)
                    if let store { rememberColor(color, in: store) }
                    show(color.hex)
                }
            }
        })
    }

    /// `colors`: the colors you picked, newest first, each with its swatch and when; Enter copies its hex, and the one
    /// you're on shows on a band over the list. None yet: Pick Color.
    private func keptRows() async -> [LauncherResult] {
        let kept = await MainActor.run { [store] in store?.get(PickedColor.stateSection, as: [PickedColor].self) ?? [] }
        let now = Date.now
        let rows = kept.enumerated().compactMap { index, picked -> LauncherResult? in
            guard let color = parseColor(picked.hex)?.color else { return nil }
            return LauncherResult(id: "color:kept:\(picked.hex)", title: picked.hex, subtitle: color.rgb, accessory: shortAge(picked.at, now: now),
                                  icon: .color(color), score: 50 - Double(index) / 1000, actionTitle: "Copy", action: { copyToClipboard(picked.hex) },
                                  answer: .color(color))
        }
        return rows.isEmpty ? [pickRow(subtitle: "Your colors show here once you’ve picked some", score: 50)] : rows
    }

    private func row(_ color: RGBColor, _ notation: ColorNotation, score: Double) -> LauncherResult {
        let text = switch notation { case .hex: color.hex; case .rgb: color.rgb; case .hsl: color.hsl }
        return LauncherResult(id: "color:\(notation)", title: text, accessory: notation == .hex ? "Hex" : "\(notation)".uppercased(),
                              icon: .color(color), score: score, actionTitle: "Copy", action: { copyToClipboard(text) }, answer: .color(color))
    }
}
