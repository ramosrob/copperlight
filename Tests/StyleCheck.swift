import AppKit
import Testing
@testable import Copperlight

private struct Fixed: ResultProvider {
    func results(for query: String) async -> [LauncherResult] {
        guard let parsed = parseCurrency(query) else { return [] }
        return currencyRows(parsed, rates: ["EUR": 1, "USD": 1.1638], date: Date.now.formatted(.iso8601.year().month().day()))
    }
}

@MainActor @Test func renderReadme() async throws {
    let cases: [(String, [any ResultProvider])] = [("#c87533", [ColorProvider()]), ("25 usd to eur", [Fixed()])]
    for (name, (query, providers)) in zip(["colors", "currency"], cases) {
        let model = SearchModel(providers: providers)
        let panel = LauncherPanel(model: model, placeholder: "Type anything")
        panel.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(300))
        model.query = query
        try await Task.sleep(for: .milliseconds(700))
        let view = try #require(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!
            .write(to: URL(filePath: "/private/tmp/claude-501/-Users-robson/47641cf4-4a64-45c0-b48e-6d8385ba10ce/scratchpad/cap/panel-\(name).png"))
    }
}
