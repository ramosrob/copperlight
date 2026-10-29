import SwiftUI

/// A result drawn big in place of the preview pane: a picture (a QR code) or a person with their actions beside it, a
/// stock across the whole card, or a color on a band over its rows.
enum Answer: Sendable {
    case picture(CGImage, kicker: String, title: String, subtitle: String)
    case stock(StockCard)
    case color(RGBColor)
    case speed(SpeedTest, tested: Date)
    case entry(DictionaryEntry)
    case person(PersonCard)
}

/// A person's card, its text ready to show.
struct PersonCard: Sendable {
    var initials: String
    var name: String
    var job: String, company: String // either can be empty
    var details: [(String, String)] // each number and email under its label, then their birthday
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

/// Their initials in a circle, their name, job and company, and under a rule how to reach them.
struct PersonTile: View {
    let card: PersonCard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 4) {
            Text(card.initials).font(.system(size: 30, weight: .semibold)).foregroundStyle(scheme == .dark ? Color.copper : Color.copperDeep)
                .frame(width: 84, height: 84).background(Color.copper.opacity(0.2), in: Circle())
                .overlay(Circle().strokeBorder(Color.copper.opacity(0.35))).padding(.bottom, 10)
            Text(card.name).font(.system(size: 20, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
            // "Product Designer · Northwind" on a line, else each on its own: never a "·" starting the second line.
            let line = [card.job, card.company].filter { !$0.isEmpty }
            ViewThatFits(in: .horizontal) {
                Text(line.joined(separator: " · ")).lineLimit(1)
                VStack(spacing: 2) { ForEach(line, id: \.self) { Text($0).lineLimit(1) } }
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
            if !card.details.isEmpty {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.top, 14).padding(.bottom, 8)
                // ponytail: the first 5; the rows beside list every one
                ForEach(Array(card.details.prefix(5).enumerated()), id: \.offset) { _, detail in
                    HStack(spacing: 10) {
                        Text(detail.0).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(detail.1).monospacedDigit().lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 12.5)).padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
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
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, fact in Fact(label: fact.0, value: fact.1) }
                Spacer()
                EnterHint(action: card.action)
            }
        }
    }
}

/// A number under its name, along a card's bottom edge.
private struct Fact: View {
    let label: String, value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15)).monospacedDigit()
        }
    }
}

/// What Enter does, in a card's corner.
private struct EnterHint: View {
    let action: String

    var body: some View {
        HStack(spacing: 7) {
            Text(action).font(.system(size: 12)).foregroundStyle(.secondary)
            Keycap(label: "↵")
        }
    }
}

/// The word set in a serif, its pronunciation, its meanings with an example each, and where it comes from.
struct DictionaryCardView: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(entry.word).font(.system(size: 38, weight: .semibold, design: .serif)).lineLimit(1)
                if !entry.pronunciation.isEmpty { Text("| \(entry.pronunciation) |").font(.system(size: 15)).foregroundStyle(.secondary) }
            }
            ForEach(Array(entry.parts.enumerated()), id: \.offset) { _, part in
                VStack(alignment: .leading, spacing: 8) {
                    Text(part.name).font(.system(size: 12.5, weight: .semibold)).italic().foregroundStyle(Color.copper)
                        .padding(.horizontal, 10).frame(height: 22).background(Color.copper.opacity(0.15), in: Capsule())
                    ForEach(Array(part.senses.enumerated()), id: \.offset) { index, sense in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if part.senses.count > 1 { Text("\(index + 1)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sense.meaning).font(.system(size: 16, design: .serif)).lineLimit(2)
                                if let example = sense.example {
                                    Text(example).font(.system(size: 14, design: .serif)).italic().foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if let origin = entry.origin {
                (Text("ORIGIN  ").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.copper) + Text(origin).font(.system(size: 12.5)))
                    .foregroundStyle(.secondary).lineLimit(2)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack {
                Text("The Mac’s dictionary").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                EnterHint(action: "Open in Dictionary")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Download and upload big, side by side; the latency, idle and under load, along the bottom.
struct SpeedCardView: View {
    let test: SpeedTest
    let tested: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Kicker(text: "Internet speed · \(test.connection)")
                Spacer()
                Text("Apple’s servers · \(tested.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                SpeedTile(label: "Download", symbol: "arrow.down", bitsPerSecond: test.down)
                SpeedTile(label: "Upload", symbol: "arrow.up", bitsPerSecond: test.up)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            HStack(alignment: .bottom, spacing: 32) {
                Fact(label: "Latency", value: "\(Int(test.idle.rounded())) ms")
                Fact(label: "Under load", value: "\(Int(test.loaded.rounded())) ms")
                Spacer()
                EnterHint(action: "Copy")
            }
        }
    }
}

private struct SpeedTile: View {
    let label: String, symbol: String
    let bitsPerSecond: Double

    var body: some View {
        let (value, unit) = speedParts(bitsPerSecond)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.copper)
                Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(.system(size: 54, weight: .semibold)).monospacedDigit()
                Text(unit).font(.system(size: 17)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 16, style: .continuous))
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
