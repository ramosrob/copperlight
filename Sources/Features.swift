/// What this build switches on. A feature that's off keeps its code, compiled and tested, but nothing wires it in:
/// no rows, no `:` commands, no background work, no permission asks, no Settings pane. Add it to `on` to bring it back.
enum Feature: CaseIterable {
    case clipboard      // clipboard history and its panel
    case notes          // the floating note, named notes, capture into the note
    case quickTools     // currency, units, time zones, emoji, define, translate, stocks, the text tools, pomodoro
    case snippets
    case scripts        // the scripts folder
    case commands       // your own commands from config.toml: links, apps, files, shell
    case fileContent    // the text inside files
    case photoText      // the text in your photos (its own permission and index)
    case systemSettings // System Settings panes as rows

    static let on: Set<Feature> = [.clipboard, .notes, .quickTools, .snippets, .scripts, .commands, .systemSettings]
    var isOn: Bool { Self.on.contains(self) }
}
