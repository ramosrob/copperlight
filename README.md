<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Copperlight icon">
</p>

<h1 align="center">Copperlight</h1>

<p align="center">
  <b>A warmer light than Spotlight.</b><br>
  The keyboard launcher for your Mac: apps, files, math, clipboard history, notes and windows, all from one field.
</p>

<p align="center">
  <a href="https://github.com/ramosrob/copperlight/releases/latest"><img src="https://img.shields.io/github/v/release/ramosrob/copperlight?label=download&color=E88C4A" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-2A2522" alt="macOS 15 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-2A2522" alt="License: GPL-3.0"></a>
  <a href="https://github.com/ramosrob/copperlight/actions/workflows/test.yml"><img src="https://github.com/ramosrob/copperlight/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
</p>

<p align="center">
  <a href="https://copperlight.app"><b>copperlight.app</b></a> ·
  <a href="#install">Install</a> ·
  <a href="docs/guide.md">Guide</a> ·
  <a href="FEATURES.md">Everything it does</a>
</p>

<p align="center">
  <img src="docs/media/hero.webp" width="740" alt="Typing into Copperlight: a currency conversion, an app, a time zone and a window command">
</p>

Press <kbd>⌥ Space</kbd> anywhere, type, press <kbd>Enter</kbd>. Copperlight opens apps and files, does math and
currency, converts units and time zones, keeps your clipboard history, moves windows, pastes snippets, and runs your
own commands and scripts. One field does it all, and anything that isn't a search is a command typed after a colon
(`:left`, `:quit saf`), so there are no shortcuts to learn.

## Why Copperlight

- **One field for everything.** No modes, no menus. The best match is already selected, and what you pick ranks
  higher next time.
- **Keyboard first.** Every result and every action is a few keystrokes from <kbd>⌥ Space</kbd>. The mouse is optional.
- **Yours.** Your settings live in one plain-text file you can read, edit and keep in git. Add your own commands,
  quicklinks, snippets and scripts.
- **Private.** No account, no telemetry, no AI service. What it keeps stays on your Mac.
- **Free and open source.** GPL-3.0: read it, change it, share it.

## Built in

The little tools you'd otherwise install one by one, a keystroke away. No extra apps, no windows to manage.

| Tool | What it does |
|---|---|
| **Clipboard history**<br>`clip` | Everything you copy, text and images, searchable. Enter pastes it into the app you were in. Passwords are never recorded. |
| **Floating notes**<br>`note`, `note work` | A glass note that floats above your windows and saves as you type. Give one a name and you have another. |
| **Pomodoro**<br>`pomo`, `pomo 50` | A focus timer that counts down in the menu bar and tells you when it's done. |
| **Quick capture**<br>`add todo`, `add event` | Reminders, calendar events and note lines, with the date read from what you type: `add todo call mom tomorrow 5pm`. |
| **Snippets**<br>`sig`, `reply Ana` | The text you type over and over, with placeholders for the date, the clipboard or a name. |
| **Meetings**<br>`meetings` | The rest of today's calendar. Enter joins the video call. |
| **Dictionary and translation**<br>`define`, `translate` | The Mac's dictionary and on-device translation, without opening an app. |
| **Text tools**<br>`json`, `uuid`, `b64`, `hex` | Format JSON, make a UUID or a password, encode text, convert colors and timestamps. |
| **Emoji**<br>`emoji party` | Every emoji by name, pasted where you are. |
| **Screenshots**<br>`screenshot`, `record` | The macOS screenshot toolbar, ready to capture or record. |

## A closer look

**Math and money.** The answer appears as you type: percentages, currencies at today's rate, units and time zones. Enter copies it.

<p align="center"><img src="docs/media/convert.png" width="600" alt="Converting 25 US dollars to euros at the ECB's rate"></p>

**Little things, fast.** Emoji by name, UUIDs, passwords, JSON, colors and timestamps: type the tool's name, press Enter.

<p align="center"><img src="docs/media/emoji.png" width="600" alt="Emoji found by typing emoji party"></p>

**Commands.** Type `:` for windows, apps, files and the Mac itself: `:left`, `:quit saf`, `:dark`, `:lock`.

<p align="center"><img src="docs/media/commands.png" width="600" alt="The list of colon commands for windows"></p>

**Words.** The Mac's dictionary in a preview beside the results, on-device translation, and every emoji by name.

<p align="center"><img src="docs/media/define.png" width="600" alt="The dictionary entry for serendipity, beside the results"></p>

## What you can type

A taste of what the field understands. Enter does the obvious thing: opens, copies, pastes or runs.

### Open and find

| Type | You get |
|---|---|
| `saf` | Safari; Enter opens it |
| `invoice` | Files and folders, from Spotlight's index (`f invoice`: files only) |
| `~/Downloads`, `/Applications` | That folder's contents, to go into or open |
| `copperlight git` | Bookmarks and recent pages from your browser, opened in their profile |
| `gmail.com`, `localhost:3000` | Opens it in your browser |
| anything | "Search Google for …", always last |

### Calculate and convert

The answer appears as you type; Enter copies it.

| Type | You get |
|---|---|
| `20% of 150`, `150 + 20%` | `30`, `180` |
| `255 in hex` | `0xFF` |
| `25 usd to eur` | The amount in euros, at today's rate |
| `10 km in mi`, `30c` | `6.21 mi`, `86 °F` |
| `3pm lisbon in sf`, `now in tokyo` | The time there |

### Words

| Type | You get |
|---|---|
| `define laconic` | The entry from the Mac's dictionary |
| `translate bom dia`, `translate thank you to japanese` | The translation, made on your Mac (macOS 26) |
| `emoji party` | Emoji by name; Enter pastes it |

### Clipboard and text

| Type | You get |
|---|---|
| `clip` | Everything you copied, text and images, searchable; Enter pastes it into the app you were in |
| `paste plain`, `paste markdown` | The clipboard without its formatting, or as Markdown (from web pages, Google Docs, Slack) |
| `json`, `upper`, `snake`, `b64`, `sha256` | The clipboard formatted, converted or hashed; or type the text after it: `upper hello` |
| `uuid`, `password 32`, `lorem 3` | A UUID, a password, placeholder text |
| `unix 1700000000`, `hex #ff8800` | `2023-11-14T22:13:20Z`, `rgb(255, 136, 0)` |

### Windows, apps and the Mac

| Type | You get |
|---|---|
| `:left`, `:left third`, `:maximize`, `:next display` | The window in front, moved there; `:restore` puts it back |
| `:window term` | Any window of any app, found by its title |
| `:quit saf`, `:hide others`, `:relaunch slack` | The apps that are running |
| `:dark`, `:volume 30`, `:lock`, `:empty trash` | The Mac itself (the ones you can't undo ask first) |
| `:shortcut name` | Your Shortcuts, Focus modes included |

### Your day

| Type | You get |
|---|---|
| `meetings` | The rest of today's meetings; Enter joins the video call |
| `add todo call mom tomorrow 5pm` | A reminder, due and alerting then |
| `add event fri 10am dentist` | An event in your calendar |
| `note`, `note work`, `add note buy milk` | Floating notes, saved as you type |
| `pomo`, `pomo 50`, `pomo break` | A pomodoro, counting down in the menu bar |
| `screenshot`, `record` | The macOS screenshot toolbar |

### Yours

| Type | You get |
|---|---|
| `gh copperlight` | Your quicklinks: a URL with what you typed filled in |
| `deploy staging` | Your scripts in `~/.config/copperlight/scripts/`, run with the text as arguments |
| `sig`, `reply Ana` | Your snippets, placeholders filled in, pasted where you are |
| `:!git status` | A shell line, its output right in the launcher |

[All of it, in detail →](docs/guide.md)

## Install

Requires macOS 15 or later, on Apple silicon or Intel.

### Download

1. Download the zip from [Releases](https://github.com/ramosrob/copperlight/releases), unzip it and move
   Copperlight.app to Applications.
2. Open it. The first time, macOS asks you to confirm it: click **Done**, then open System Settings → Privacy &
   Security, scroll down to "Copperlight was blocked" and click **Open Anyway**. Only once.

   Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Copperlight.app`

Every release is signed with the same certificate, so updates keep the permissions you gave it.

### Build from source

Needs Xcode 26 or later (the full app: the Command Line Tools alone can't build it).

```sh
brew install xcodegen
git clone https://github.com/ramosrob/copperlight.git
cd copperlight
make install
```

`make install` builds a release copy into `~/Applications/Copperlight.app` and opens it. If `make` can't find
Xcode, select it once: `sudo xcode-select -s /Applications/Xcode.app && xcodebuild -runFirstLaunch`.

Builds are signed ad-hoc unless `make` knows your Apple team, and macOS forgets an ad-hoc app's permissions each
time it's rebuilt. If you'll rebuild it, see [Signing](DEVELOPMENT.md#signing).

### First launch

The first launch opens a welcome window: the hotkey, a button for each permission, and Open at Login. After
that Copperlight lives in the menu bar (the C), with no Dock icon. Press ⌥Space and type. Its menu has
**Settings…** (or type `copperlight settings`).

## Permissions

None are needed to start: search, math, files and most of the rest work without any. Each permission turns on a
few features. The welcome window asks for them in one place; otherwise macOS asks the first time a feature needs one.

| Permission | Turns on |
|---|---|
| Accessibility | Pasting into the app you were in (clipboard history, snippets, emoji, paste as Markdown); moving and switching windows |
| Calendars | `meetings` (reads today's events) and `add event` (add-only access is enough for that) |
| Reminders | `add todo` |
| Notifications | The end of a pomodoro, shell lines that finish in the background, errors |
| Automation | `:empty trash`, `:dark`, `:restart`, `:shut down` (asking Finder, System Events or loginwindow) |
| Full Disk Access, by hand | Safari's bookmarks and history only |

## Privacy

- **No account, no analytics, no crash reports.** Nothing about you is sent anywhere.
- **Few network requests, none about you:** currency rates (ECB, through frankfurter.dev) at most once a day, and for
  finding apps by what they do, Homebrew's public app list (downloaded whole, weekly, so it doesn't reveal which apps
  you have), each listed app's homepage once, and the App Store's description of apps you got there.
  `[apps] online = false` turns those off. Links and searches open in your browser.
- **What it keeps stays on your Mac**, in `~/.config/copperlight/`: your config, notes, state and clipboard history
  (SQLite, readable only by you; deleted items are overwritten). Copies marked as passwords, and copies made in
  password managers, are never recorded.
- **No AI service.** With Apple Intelligence on, the Mac's own on-device model writes search words for your apps.
  Nothing leaves the Mac.

## Make it yours

Everything lives in `~/.config/copperlight/config.toml`, created with commented examples on first run. Edit it in
**Settings…** or by hand: changes apply when you save.

```toml
[[command]]
alias = "gh"
type = "url"
url = "https://github.com/search?q={query}"   # "gh copperlight" searches GitHub

[[command]]
alias = "dev"
type = "shell"
run = "cd ~/code/api && docker compose up -d"

[[snippet]]
name = "reply"                                # "reply Ana"
text = "Hi {query}, thanks for the note. I'll get back to you by {date}."
```

Drop an executable into `~/.config/copperlight/scripts/` and it becomes a command too. Every setting is in
[docs/configuration.md](docs/configuration.md).

## Documentation

| | |
|---|---|
| [Guide](docs/guide.md) | Everything you can type, in detail |
| [Configuration](docs/configuration.md) | config.toml and every setting in it |
| [Everything it does](FEATURES.md) | Every feature on one page |
| [Why it works this way](SPEC.md) | The principles behind it |
| [Developing](DEVELOPMENT.md) | Building, testing, releasing, and the rules a change has to fit |

## Support Copperlight

Copperlight is free, and it stays free. If it saves you time, you can
[sponsor it on GitHub](https://github.com/sponsors/ramosrob) or [buy me a coffee](https://buymeacoffee.com/ramosrob).
Found a bug or have an idea? [Open an issue](https://github.com/ramosrob/copperlight/issues).

## License

Copperlight is free and open source under the [GNU GPL v3](LICENSE). © 2026 Robson Ramos.
