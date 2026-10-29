import SwiftUI

/// A result drawn big in place of the preview pane: a picture (a QR code) with its actions beside it, a stock across the
/// whole card, or a color on a band over its rows.
enum Answer: Sendable {
    case picture(CGImage, kicker: String, title: String, subtitle: String)
    case stock(StockCard)
    case color(RGBColor)
}

/// A stock's card, its text ready to show.
struct StockCard: Sendable {
    var kicker: String // "AAPL · Apple Inc."
    var price: String
    var change: String // "▲ 0.93% today"; empty without yesterday's close
    var up: Bool
    var corner: String // when, and where it trades
    var closes: [Double]
    var previousClose: Double?
    var facts: [(String, String)]
    var action: String // what Enter does
}

extension Color {
    init(_ color: RGBColor) {
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}

/// The small copper capitals over an answer.
private struct Kicker: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text.uppercased()).font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
            .foregroundStyle(scheme == .dark ? Color.copper : Color.copperDeep)
    }
}

/// A picture on white, rounded, its squares kept sharp.
struct PictureTile: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

/// What a picture is: its kind, what it's of, and a line more.
struct AnswerHeading: View {
    let kicker: String, title: String, subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: kicker)
            Text(title).font(.system(size: 21, weight: .medium)).lineLimit(2)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The price and today's change, the 7 days as a chart with yesterday's close dashed across it, and the numbers under
/// it, with what Enter does in the corner.
struct StockCardView: View {
    let card: StockCard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let trend = card.up ? (dark ? Color(red: 0.36, green: 0.85, blue: 0.6) : Color(red: 0.06, green: 0.48, blue: 0.27))
            : (dark ? Color(red: 1, green: 0.48, blue: 0.44) : Color(red: 0.74, green: 0.17, blue: 0.14))
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker(text: card.kicker)
                    HStack(spacing: 12) {
                        Text(card.price).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                        if !card.change.isEmpty {
                            Text(card.change).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(trend)
                                .padding(.horizontal, 10).frame(height: 26).background(trend.opacity(0.14), in: Capsule())
                        }
                    }
                }
                Spacer()
                Text(card.corner).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 2)
            }
            StockChart(closes: card.closes, previousClose: card.previousClose).frame(height: 150)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack(alignment: .bottom, spacing: 32) {
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.0).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(fact.1).font(.system(size: 15)).monospacedDigit()
                    }
                }
                Spacer()
                HStack(spacing: 7) {
                    Text(card.action).font(.system(size: 12)).foregroundStyle(.secondary)
                    Keycap(label: "↵")
                }
            }
        }
    }
}

/// The closes as a copper line over a fade of it; yesterday's close dashed, inside the scale.
private struct StockChart: View {
    let closes: [Double]
    let previousClose: Double?

    var body: some View {
        GeometryReader { geometry in
            let values = closes + (previousClose.map { [$0] } ?? [])
            let low = values.min() ?? 0, high = values.max() ?? 1, span = high - low == 0 ? 1 : high - low
            let size = geometry.size
            let y = { (value: Double) in 4 + (size.height - 8) * (1 - CGFloat((value - low) / span)) }
            let line = Path { path in
                for (index, close) in closes.enumerated() {
                    let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(max(closes.count - 1, 1)), y: y(close))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            let area = Path { path in
                path.addPath(line)
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
            }
            if closes.count > 1 {
                area.fill(LinearGradient(colors: [.copper.opacity(0.28), .copper.opacity(0)], startPoint: .top, endPoint: .bottom))
                if let previousClose {
                    Path { $0.addLines([CGPoint(x: 0, y: y(previousClose)), CGPoint(x: size.width, y: y(previousClose))]) }
                        .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                line.stroke(Color.copper, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
    }
}

/// The color, with its hex and how it reads on white and black, then two steps lighter and two darker.
struct ColorBand: View {
    let color: RGBColor

    var body: some View {
        let ink = color.contrast(with: .black) >= color.contrast(with: .white) ? Color.black.opacity(0.88) : Color.white
        let ratio = { (other: RGBColor) in String(format: "%.1f : 1", color.contrast(with: other)) }
        ZStack(alignment: .bottomLeading) {
            Color(color)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach([0.5, 0.25, -0.25, -0.5], id: \.self) { step in Color(color.mixed(step)).frame(width: 52) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(color.hex).font(.system(size: 26, weight: .semibold))
                Text("Contrast: \(ratio(.white)) on white, \(ratio(.black)) on black").font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
