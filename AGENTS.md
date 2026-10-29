# Working on Copperlight

Read [SPEC.md](SPEC.md) (what fits and what never will) and [DEVELOPMENT.md](DEVELOPMENT.md) (building, how the
code is laid out, the rules a change has to fit) first. This file only adds what's easy to miss.

## Commands

- `make test` runs the whole suite. It regenerates the Xcode project first, so new files are picked up.
- One test: `make project`, then
  `xcodebuild -quiet -project Copperlight.xcodeproj -scheme Copperlight -derivedDataPath build -destination "platform=macOS,arch=$(uname -m)" test -only-testing:"CopperlightTests/timerUntil()"`.
- `make run` builds and launches it. Never edit `Copperlight.xcodeproj`: it's generated from `project.yml`.

## Making a change

- Write the failing test first, in `Tests/CopperlightTests.swift` (Swift Testing). No live network calls: data from
  elsewhere is a recording in `Tests/Fixtures/`.
- `state.json` keeps dates as ISO 8601 in whole seconds, so a test date that goes through `StateStore` needs whole
  seconds too.
- In an actor provider, write `modeResults` as `async`, like the protocol: a synchronous one loses to the protocol
  extension's default, which only calls `results`.
- Say so up front when macOS already does something well: ROADMAP.md's "Maybe, someday" lists what it covers today.
- A feature is done when the docs say it: [FEATURES.md](FEATURES.md), [docs/guide.md](docs/guide.md),
  [docs/configuration.md](docs/configuration.md) for a config key, the README when it's worth showing, and
  ROADMAP.md.

## Writing

- Short, plain sentences that say what happens. A row says what Enter does.
- The README and docs describe Copperlight on its own and don't name other apps.
- No personal data in fixtures, screenshots or examples: made-up names, events and paths.
