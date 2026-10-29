# Developing Copperlight

How to build and test Copperlight, how the code is laid out, and the rules a change has to fit. Read
[SPEC.md](SPEC.md) first: it says what Copperlight is, what it will never be, and why. [FEATURES.md](FEATURES.md)
lists everything it does, [docs/guide.md](docs/guide.md) explains it in detail and
[docs/configuration.md](docs/configuration.md) covers config.toml.

## The rules a change has to fit

- **One hotkey.** The launcher's hotkey is the only global one, and the panel has no modifier keys: Enter runs
  the selected row, and anything else is a command typed after `:`. No ⌘K menus, no ⌘-number shortcuts.
- **One symbol.** `:` is the only prefix, and it controls things (`:quit saf`, `:left`, `:!git status`).
  Related commands share their first word (`:left`, `:left third`), so typing it lists the group. Everything else is found by its name (`note`, `pomo 50`, `emoji party`) or recognized by its shape
  (math, currency, URLs, paths). No new prefix symbols: they hide files whose names start with them.
- **Config over code.** Settings live in one plain `config.toml` that applies on save. If an idea can be a
  `[[command]]`, a snippet or a script in `~/.config/copperlight/scripts/`, it becomes an example there, not a feature.
- **Nothing about the user leaves the Mac.** Its only requests are public and carry nothing about the user:
  daily currency rates, and for app search Homebrew's whole app list, app homepages and App Store descriptions
  (`[apps] online = false` turns those off). No telemetry, no accounts, no sync, no credentials.
- **No AI service and no plugin store.** What runs on the Mac is fine: Apple's on-device model writes app search
  words when Apple Intelligence is on, and Vision reads the text in photos.
- **Use decides the order.** Rows people pick rise on their own (frecency). No aliases or numbers to set up.
- **Its own look.** Two floating glass pieces: the search field as a pill, the results in a card under it. The
  icon's copper is the only color, outside a diff's red and green. No colored tiles, kind labels or footer.

## Building

Requires macOS 15+ and full Xcode 26+ (KeyboardShortcuts needs SwiftUI's macro plugins, which only ship with Xcode).

```sh
# 1. Xcode from the App Store, then point the toolchain at it
sudo xcode-select -s /Applications/Xcode.app
xcodebuild -runFirstLaunch

# 2. Project generator
brew install xcodegen
```

That's enough to build: without a team, builds are signed ad-hoc. To keep macOS's permissions across rebuilds,
sign with your own certificate (see "Signing" below): put your team in `Local.mk` (gitignored:
`TEAM = ABCDE12345`) or pass it once (`make build TEAM=ABCDE12345`).

```sh
make build   # regenerates Copperlight.xcodeproj from project.yml, builds into ./build
make run     # build, kill any running copy, launch it from ./build
make install # Release build, copy to ~/Applications/Copperlight.app, launch that copy
make test    # unit tests (Swift Testing)
make clean   # remove build/ and the generated project
```

`Copperlight.xcodeproj` is generated: XcodeGen lists the source files, so the Makefile regenerates it every time.
Never edit it; change `project.yml` instead.

For everyday use, run `make install` and turn on Launch at Login from that copy's menu. The login item
points at the copy that was running when you turned it on, and `./build` disappears with `make clean`. After
changes, `make install` again (same place, so the login item and Accessibility permission keep working).

### Signing

`make` signs ad-hoc unless it knows your Apple team. An ad-hoc build runs fine, but macOS sees every rebuild as
a new app and asks for its permissions again. Signed with your **Apple Development** certificate, every rebuild
keeps them. A free Apple ID (personal team) is enough.

1. Xcode → Settings → Accounts → add your Apple ID.
2. Select the team → Manage Certificates → **+** → Apple Development.
3. `security find-identity -v -p codesigning` should now list "1 valid identities". If it says 0 valid while
   the certificate is listed, the keychain is missing Apple's current intermediate certificate (common when
   an old, expired one from before 2023 is still around). Install
   [AppleWWDRCAG3.cer](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer):
   `security import AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db`.
4. Your team ID is the `OU=` field of the certificate:
   `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`. Put it in `Local.mk`
   next to the Makefile (gitignored): `echo 'TEAM = ABCDE12345' > Local.mk`. For a one-off build:
   `make build TEAM=ABCDE12345`.

#### Accessibility (clipboard paste, window commands)

Pasting a clipboard item sends ⌘V to the app you were in, and macOS only lets apps send keystrokes with
Accessibility permission. Window commands (`:left`, `:minimize`…) need it too, to move other apps' windows; without
it they ask for it instead. Everything else works without it (the hotkey is a Carbon hotkey, not an event tap).

1. Press Enter on a clipboard item once. It's copied, and the panel shows "allow Copperlight in
   Accessibility". Press Enter on that row: macOS asks, and System Settings opens at Privacy & Security →
   Accessibility.
2. Turn on Copperlight. The permission is checked on every Enter, so the next one should paste without a restart.

Why the signing identity must stay stable: the grant is tied to the app's code signature, not its path or
name. With the same certificate and bundle ID (`app.copperlight`) every rebuild keeps the grant. Debug builds (`make
run`, `make test`) are `app.copperlight.debug`, "Copperlight Dev" in System Settings, with a switch of their own:
sharing the release's bundle ID with another signature, each run took the release's switch away. An
ad-hoc build (no `TEAM`) runs fine, but macOS sees every rebuild as a new app: the
switch in System Settings still looks on, yet pasting stops working. Then turn it off and on again, or
`tccutil reset Accessibility app.copperlight` and grant it again.

Starting a pomodoro, or the first notification (e.g. a shell command that failed), asks to allow
notifications.

No App Sandbox, on purpose (see SPEC.md). There's no entitlements file.


## Releasing

Releases aren't notarized; they're signed with a self-signed certificate named "Copperlight". macOS keys an app's permissions to its certificate, so every release has to be
signed with the same one, or everyone grants Accessibility again after updating. Never lose it.

1. Once, if the keychain has no "Copperlight" certificate (`security find-identity -p codesigning`): Keychain
   Access → Certificate Assistant → Create a Certificate…, named `Copperlight`, Identity Type Self-Signed Root,
   Certificate Type Code Signing. Back it up: in Keychain Access, export it with its private key (My Certificates →
   Copperlight → Export, a .p12 with a password) into your password manager. Never commit it: anyone with the key
   can sign an app that macOS treats as Copperlight, permissions included.
2. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in project.yml.
3. `make release`: `build/Copperlight.zip`, for Apple silicon and Intel, and its SHA-256.
4. Try the zip on a Mac that has never run Copperlight, then publish it:
   `gh release create v<version> build/Copperlight.zip --title "Copperlight <version>" --generate-notes`. Keep the
   name `Copperlight.zip`: copperlight.app's download buttons link to the latest release's file of that name.

## How the code is laid out

Each feature is a type conforming to `ResultProvider` (`Sources/Launcher.swift`): it gets every query and
returns rows. Add it to the list in `Sources/App.swift`. Providers run at the same time on every keystroke, and
their rows show together once all have answered or 50 ms have passed; a slower one's rows merge in later, so
answer well within 50 ms or rank your rows at the bottom. The next keystroke cancels the round. A provider that takes
text after a name (`translate `) lists it in `modes`: typed, the name becomes a chip in the field and the query goes to
that provider alone. A `:` command is a `Verb` (`Sources/Actions.swift`). Every file is listed below.

- Swift 6 with strict concurrency, no warnings. Match the code around you: its naming, its comment density,
  comments that say why rather than what.
- Anything that can take time (a subprocess, a file read) runs off the main thread, with a timeout, and stops when
  its task is cancelled. `runTool` in `Sources/Tools.swift` does all three for command-line tools.
- No new dependency without a good reason. Today there are four, all MIT-licensed (a new one must be GPL v3 compatible,
  and gets a line in `Sources/Acknowledgements.swift`): KeyboardShortcuts, Expression, TOMLKit
  and GRDB.
- A user-visible change updates FEATURES.md and docs/guide.md (and README.md's "What you can type" if it belongs
  there) in the same change, and a new setting goes into the
  example config in `Sources/Config.swift`.

### Every file

```
Sources/
  App.swift                 entry point, menu bar item, hotkey, config loading, built-in rows (Note, Clipboard…)
  Launcher.swift            ResultProvider protocol, SearchModel (concurrent query + merge, frecency, what was picked for what was typed, recent queries for ↑),
                            panel + SwiftUI view, opening with the selected text
  Actions.swift             `:` commands: windows (Accessibility), running apps, files, the Mac; the selected text
  Layouts.swift             `:layout save work`, `:layout work`: the windows on screen, kept in state.json and put back
  Lookups.swift             `ip`, `battery`, `disk`, `port 3000`, `cpu`, `memory`, `speed`: getifaddrs, IOKit power sources, volumes, lsof, ps, networkQuality
  Controls.swift            `:play`, `:mute`, `:output`, `:wifi`, `:awake`: media keys, CoreAudio, CoreWLAN, power
  Stocks.swift              `stock AAPL`: Yahoo Finance's chart data, the price row and the 7-day chart
  Menus.swift               `:export pdf`: the menus of the app in front (Accessibility), their shortcuts
  Config.swift              Config (TOML), hotkey parsing, example config, directory watcher
  StateStore.swift          state.json
  AppProvider.swift         fuzzy matcher, app scan
  CalculatorProvider.swift  math via Expression, percentages and their phrases, 10k, hex and binary, ans
  CurrencyProvider.swift    query parser, rate cache
  Shell.swift               `:!` shell lines: run with a timeout, output in place of the list
  Scripts.swift             ~/.config/copperlight/scripts/: executables as commands, their @title/@icon/@output header, script filters
                            and community script commands' headers
  Snippets.swift            [[snippet]] rows, placeholders, paste
  Units.swift               unit names and conversions (Foundation Measurement)
  TimeZones.swift           places, `3pm lisbon in sf`
  Dates.swift               date math: `days until dec 25`, `in 3 weeks`, a date's weekday; what a phrase could become
  BrowserPages.swift        bookmarks and history: Chromium, Firefox, Safari readers, search
  Tabs.swift                open browser tabs (AppleScript, Automation permission), switching to one
  Contacts.swift            people from Contacts, the Contact chip: message, call, FaceTime, WhatsApp, email, copy
  Reminders.swift           reminders that are due (EventKit): the empty launcher, `due`, Enter completes
  Suggestions.swift         the apps you open around this time of day, for the empty launcher (state.json)
  Meetings.swift            today's events (EventKit), video call links
  SystemSettings.swift      System Settings pages by name
  OtherNames.swift          other words for built-ins and apps ("turn off" → Shut Down)
  Emoji.swift               emoji by name (the emoji picker's names)
  Words.swift               define (Dictionary Services), spell (NSSpellChecker), translate (Translation)
  Tools.swift               running command-line tools with a timeout and cancel (:! lines, scripts)
  PathProvider.swift        `~/…` and `/…`: list a folder, go into it, open what's in it
  ItemActions.swift         what Tab shows for a file and an app (clipboard items' are in Clipboard.swift), with their previews;
                            an app's recent documents, from Spotlight
  Capture.swift             add note/todo/event (EventKit, date reading), screenshot and record
  TextTools.swift           text tools (json, b64, case…), paste as plain text or Markdown (HTML → Markdown)
  Colors.swift              `#c87533`, `rgb(…)`, `hsl(…)` in the other notations, `pick color` (NSColorSampler)
  QRCode.swift              `qr`: QR codes (Core Image), copying a picture
  ScreenText.swift          `copy text`: a region of the screen (screencapture), its text and QR codes (Vision)
  LargeType.swift           `large 555-0100`: the text across the screen
  CommandProvider.swift     [[command]] entries, quicklinks, browsers and profiles, URL and web search fallbacks, search engines, detached processes, notifications
  Clipboard.swift           pasteboard polling (text, images), SQLite store, clipboard rows, ⌘V
  FileSearchProvider.swift  Spotlight (NSMetadataQuery) file search, by name and by the text inside
  AppIndex.swift            apps by what they do: bundle facts, Homebrew, homepages, App Store, Apple's on-device model
  PhotoText.swift           the text in Photos (Vision), in photos.sqlite (FTS5)
  Pomodoro.swift            timer, menu bar countdown (shared with the timer), pomo rows
  Timers.swift              `timer 10 min tea`: parsing the length, the countdown, timer rows
  NotePanel.swift           floating notes (titled by their first line), the notes the launcher lists, `:delete note`
  Markdown.swift            Markdown in notes: what to style where, and ticking checkboxes
  Welcome.swift             the welcome window: hotkey, permissions (live status), Open at Login; AppWindow
  Settings.swift            the Settings window: a pane per group, commands and snippets editors, About
  Acknowledgements.swift    the open source Copperlight is built with, shown in Settings › About (a test checks it)
  ConfigFile.swift          edits config.toml in place: one key or [[entry]] at a time, comments kept
Resources/AppIcon.icon      the app icon, made in Icon Composer: open it there to edit it
Resources/Assets.xcassets   Mark: the icon's C in one color, for the menu bar, the note and the welcome screen
Tests/CopperlightTests.swift, Tests/Fixtures/
.github/workflows/test.yml  CI: make test on every push and pull request
```

The icon is `Resources/AppIcon.icon`, made in Icon Composer; Xcode builds every size from it, Liquid Glass on macOS 26 and a flat version for older Macs. `Mark.imageset/mark.svg` is its two arcs (`Assets/1-arc-lit.svg`, `2-arc-unlit.svg`) in black, the unlit one at 40%, cropped to them: redraw it if the arcs change. `docs/icon.png`, the picture at the top of this page, is the built icon: after changing the icon, `make build`, then `iconutil -c iconset build/Build/Products/Debug/Copperlight.app/Contents/Resources/AppIcon.icns` and copy its `icon_128x128@2x.png` over it.

## Tests

Tests use Swift Testing, in `Tests/CopperlightTests.swift`.

- Every piece of logic that can break gets a test: parsing, ranking, what a row says.
- Data from elsewhere is tested with recordings in `Tests/Fixtures/` (a browser's Local State), never live calls.
- A test that needs something only some Macs have (macOS 26, the system dictionaries) skips itself elsewhere
  with `.enabled(if:)`, so the suite passes on any Mac and in CI.
- Keep fixtures free of personal data: recordings from public repos, made-up names and paths.

## License

Free and open source under the GNU GPL v3: see [LICENSE](LICENSE).
