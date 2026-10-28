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

/// A color typed in one notation (`#c87533`, `rgb(…)`, `hsl(…)`) in the others, each row with its swatch; Enter
/// copies. `pick color` picks one off the screen with macOS's magnifier: its hex is copied and the launcher comes back
/// showing it, so the other notations are a row away.
struct ColorProvider: ResultProvider {
    /// Opens the launcher with this typed in.
    var show: @MainActor @Sendable (String) -> Void = { _ in }

    func results(for query: String) async -> [LauncherResult] {
        if let (color, typed) = parseColor(query) {
            let notations = ColorNotation.allCases.filter { $0 != typed } + [typed]
            return notations.enumerated().map { index, notation in row(color, notation, score: 50 - Double(index) / 10) }
        }
        let lower = query.lowercased()
        guard let score = lower.count >= 3 && "pick color".hasPrefix(lower) ? 50 : fuzzyScore(query, "Pick Color") ?? otherNameScore(query, "Pick Color")
        else { return [] }
        return [LauncherResult(id: "builtin:pick color", title: "Pick Color", subtitle: "Click anywhere on the screen to copy its color",
                               icon: .symbol("eyedropper"), score: score, actionTitle: "Pick", action: { [show] in
            NSColorSampler().show { picked in
                guard let color = picked.flatMap(RGBColor.init) else { return } // Esc: nothing picked
                copyToClipboard(color.hex)
                show(color.hex)
            }
        })]
    }

    private func row(_ color: RGBColor, _ notation: ColorNotation, score: Double) -> LauncherResult {
        let text = switch notation { case .hex: color.hex; case .rgb: color.rgb; case .hsl: color.hsl }
        return LauncherResult(id: "color:\(notation)", title: text, accessory: notation == .hex ? "Hex" : "\(notation)".uppercased(),
                              icon: .color(color), score: score, actionTitle: "Copy", action: { copyToClipboard(text) },
                              previewImage: { swatch(color) }, details: [("Hex", color.hex), ("RGB", color.rgb), ("HSL", color.hsl)])
    }
}

/// The color, big, for the preview pane.
@MainActor func swatch(_ color: RGBColor, size: CGSize = CGSize(width: 330, height: 190)) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        return true
    }
}
