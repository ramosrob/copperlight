# Copperlight — Spec

A minimal macOS launcher, and it stays small: no plugin store, no AI service, no sync, no accounts, no credentials.
Its only requests are public and say nothing about you: currency rates, and for app search Homebrew's app list, app
homepages and App Store descriptions, which `[apps] online = false` turns off. The exceptions say what you asked
for, and only when you ask: `stock AAPL` sends that ticker to Yahoo Finance, in the Stock chip only (Tab) and once
typing pauses, kept a minute; Enter on the Public IP row (`ip`) asks api.ipify.org (decided 2026-10-28); Enter on `speed` runs macOS's
`networkQuality` against Apple's servers (decided 2026-10-29). On-device models are fine: Apple
Intelligence writes app search words, Vision reads the text in photos (decided 2026-10-15) and in the part of the
screen you drag over with `copy text` (decided 2026-10-29). Projects and the developer
tools built on them (git, gh, Claude Code, Jira) were taken out on 2026-10-27: they belong in another app.

## Principles

- **Small core, config over code.** Anything that can be an entry in `config.toml` must not be a new feature.
  Built-ins use macOS's own apps (Reminders, Calendar, the screenshot toolbar); a `[[command]]` with the same name
  replaces one (`screenshot` → CleanShot, `add todo` → Things), so there are no plugins (decided 2026-10-13).
- **Keyboard-only.** Every action is reachable without the mouse.
- **One hotkey.** Only the launcher has a global hotkey; every other feature is found by typing in it.
  More hotkeys may come later as one polished feature, not one at a time (decided 2026-10-12). Nothing watches
  what you type in other apps: snippets are pasted from the launcher, and macOS's Text Replacements expand text
  anywhere (decided 2026-10-28). The hotkey reads what's selected when it's pressed, and only then: the launcher
  opens with that text typed and selected, so typing replaces it (decided 2026-10-28).
  No modifier keys in the panel either: any action besides Enter is a command typed after `:`, vim style. Tab goes a
  step into the selected row: a name that takes text becomes a chip in the field (decided 2026-10-27), a row with
  something to show opens its preview beside the list, and a file, an app or a clipboard item shows what you can do
  with it, in place of the list, its preview beside it, Esc going back (decided 2026-10-29). In the general search the list keeps its full width until
  then; where reading is the point (clipboard history, a chip, a command's output) the preview is open from the start,
  and it only ever shows for a row with something in it (decided 2026-10-28). Typing never makes a chip,
  a space being only a space: `stock apple` may be the start of a file's name (decided 2026-10-28).
- **One symbol.** `:` is the only prefix, and it controls things: the Mac, the window in front, running apps,
  files (`:left`, `:quit saf`, `:lock`; `:!git status` runs a shell line, like vim). Everything else is typed by
  name, and text after a name goes to it (`pomo 50`, `add note buy milk`, `deploy staging`). Capture is one
  word, `add` (`add todo …`, `add event …`), and `add` alone lists what it can add. Math, currency, URLs
  and paths are recognized by their shape. No other prefix symbols: they hide files whose names start with
  them, and nobody can find them by searching (decided 2026-10-13).
- **Commands grouped by what they act on.** Related commands share their first word (`:left`, `:left third`,
  `:left two thirds`), and typing that word lists the group. As commands grow, a person remembers a handful of
  words, not a long flat list (decided 2026-10-13).
- **Use decides the order.** The rows you pick most rise to the top (frecency), and the row you picked for some
  text comes first for that text next time, so there are no aliases or numbers to set up (decided 2026-10-29).
- **Any browser.** Nothing assumes Chrome. Links open in the default browser; `browser` and `profile` on a
  command pick another one (decided 2026-10-13).
- **Its own look, from the icon.** Two floating glass pieces: the search field as a plain pill,
  and the results in a card under it. The icon's copper is the only color (the field's edge,
  the selection, the chip a name that takes text becomes in the field, decided 2026-10-27). Glyphs sit in plain rings, with no colored tiles, no kind labels and no footer; the selected
  row says what Enter does. Its own look, not Spotlight's (decided 2026-10-13).
- **Instant.** No network on the keystroke path. Anything remote is cached and read from the cache. The Stock chip
  alone waits for a pause in typing and then asks Yahoo Finance (decided 2026-10-28).
- **Plain files.** Config, state and the note are human-readable files in `~/.config/copperlight/`. What belongs
  to this Mac (recent queries, saved window layouts, whose frames fit its screens) lives in `state.json`, not
  config.toml, so a config kept in git works on any Mac (decided 2026-10-28). Notes are plain text: their Markdown is
  drawn as you type, and the file never changes for it (decided 2026-10-28).
- **Never crash on user input.** Malformed math, currency or config shows nothing (or an error row); it never crashes.

## Stack

- Swift 6, SwiftUI + AppKit, macOS 15+.
- XcodeGen (`project.yml`); build/test via `xcodebuild` through a `Makefile` (`make build`, `make run`, `make test`).
- `LSUIElement = true` (menu bar only, no Dock icon).
- **No App Sandbox** (breaks Spotlight queries, synthetic keystrokes, launching a browser with args).
- Signed with my Apple Development identity so TCC (Accessibility) grants survive rebuilds.
- Allowed SPM dependencies (anything else needs my approval):
  - `sindresorhus/KeyboardShortcuts` — global hotkeys
  - `nicklockwood/Expression` — safe math evaluation
  - `LebJe/TOMLKit` — config parsing (Milestone 2)
  - `groue/GRDB.swift` — SQLite for clipboard history (Milestone 3)

## Files

```
~/.config/copperlight/
  config.toml        # edited by hand or from Settings, hot-reloaded on save
  state.json         # frecency, window positions, misc app state
  note.txt           # the floating note's content
  rates.json         # currency rate cache
  clipboard.sqlite   # clipboard history
```

## Architecture

- **Launcher panel:** borderless, non-activating `NSPanel`, centered on the active screen.
  Search field + results list. Esc or focus loss hides it. ↑↓ to move, Enter to run,
  `:` for commands (the Mac, the window in front, running apps, files).
- **Providers:** every feature is a provider.

  ```swift
  protocol ResultProvider {
      func results(for query: String) async -> [LauncherResult]
  }
  ```

  All providers are queried on every keystroke; results are merged and sorted by score.
  Slow providers (file search) must not block fast ones (apps, calculator).
- **Config:** `config.toml` is loaded at startup and reloaded when the file changes on disk. The Settings window
  edits that file in place, one key or entry at a time, keeping its comments; it's never a second store.
  A bad config keeps the previous valid config and shows an error row/notification.

## Features

### Must-haves

| # | Feature | Behavior |
|---|---|---|
| 1 | App switching | Running apps (`NSWorkspace.runningApplications`) + installed apps from `/Applications`, `/System/Applications`, `~/Applications`. Fuzzy match on name. Running apps ranked higher, plus frecency. Enter activates or launches. |
| 2 | Calculator | If the query parses as math (via `Expression`), show the result inline. Enter copies it. |
| 3 | Currency | `25USD to EUR`, `25 usd in eur`, `25usd eur` (case-insensitive, `.` or `,` decimals). Rates from the Frankfurter API (ECB, free, no key), cached 24 h, stale cache used offline. Enter copies. |
| 4 | Clipboard history | Poll `NSPasteboard.changeCount` every 0.5 s, store in SQLite. Dedupe. Skip `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType`. Enter restores the item and pastes (⌘V via CGEvent; needs Accessibility). Text first, images later. Opened from the launcher (`clip`). |
| 5 | Notes widget | Separate small floating `NSPanel` (`.floating`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`). One plain-text `NSTextView`, autosaved to `note.txt`. Opened from the launcher (`note`). Remembers size and position. |
| 6 | File search | `NSMetadataQuery` (Spotlight index) scoped to folders in config, debounced ~150 ms. Enter opens; `:reveal` reveals in Finder. |

### Wishlist

- **Custom commands / websites:** one list of `alias → action` in config. Types: `url` (optional `browser` and
  `profile`; `{query}` takes the text after the alias), `app`, `file`, `shell`.
- **Browser profiles:** Chromium browsers (Chrome, Brave, Edge, Vivaldi) resolve the display name (e.g. `"Work"`)
  to the profile directory via their `Local State` (`profile.info_cache`), then
  `open -na <browser> --args --profile-directory="<dir>" <url>`. Firefox takes the name: `-P <name>`.
- **Pomodoro:** `pomo` (default length), `pomo 50`, `pomo stop`. Countdown in the menu bar, notification when done.

## Config example

```toml
[hotkeys]
launcher = "option+space"

[currency]
default_target = "EUR"

[files]
scopes = ["~/code", "~/Documents", "~/Downloads"]

[pomodoro]
default_minutes = 25

[[command]]
alias = "github"
type = "url"
url = "https://github.com"
browser = "Google Chrome"
profile = "Work"

[[command]]
alias = "pr"
type = "url"
url = "https://github.com/pulls"
profile = "Work"

[[command]]
alias = "dev"
type = "shell"
run = "cd ~/code/api && docker compose up -d"

[[command]]
alias = "budget"
type = "file"
path = "~/Documents/finance/cashflow.xlsx"
```

## Milestones

1. **M1:** project scaffold, hotkey, panel, provider architecture, apps, calculator, currency.
2. **M2:** `config.toml` + hot reload, notes widget, custom commands incl. browser profiles.
3. **M3:** clipboard history (Accessibility permission).
4. **M4:** file search, pomodoro.

## Rules for agents

- Do **not** run `git commit` or `git push`. I review and commit.
- Stay inside the milestone's scope. Note ideas under "Open questions" instead of building them.
- No new dependencies beyond the list above without asking.
- Every milestone ends with: what was built, what's untested, open questions.
