# Copperlight: everything it does

One page with every feature: what you type, what you get, and what it needs. The details live in
[docs/guide.md](docs/guide.md) (how to use each one), [docs/configuration.md](docs/configuration.md) (config) and the reasons in [SPEC.md](SPEC.md). When a feature ships, it gets a
line here.

**Switched off for now** in [Sources/Features.swift](Sources/Features.swift), with their code kept: the text inside
files and the text in photos. Everything else on this page is on.

## At a glance

| Type | You get | Enter |
|---|---|---|
| `saf` | Apps | Opens it |
| `invoice`, `f invoice` | Files and folders (Spotlight) | Opens it |
| `~/code/copperlight`, `/Applications` | That folder's contents | Goes into a folder, opens a file |
| `gmail.com`, `localhost:3000` | An "Open" row | Opens it in `[browser]` |
| anything | "Search Google for …", always last | Searches (Settings › Browser picks the engine) |
| `2^10 / 3`, `20% of 150`, `255 in hex` | The result | Copies it |
| `25 usd to eur`, `25 usd` | The conversion | Copies it |
| `10 km in mi`, `30c` | Units converted | Copies it |
| `3pm lisbon in sf`, `now in tokyo` | The time there | Copies it |
| `stock AAPL`, `stock MGLU3.SA` | The price, today's change, a 7-day chart (Yahoo Finance) | Opens it on Yahoo Finance |
| `copperlight git` | Bookmarks and recent pages from your browser | Opens it in its profile |
| `meetings` | The rest of today's meetings | Joins the video call |
| `bluetooth`, `dark mode` | System Settings pages | Opens that page |
| `emoji party` | Emoji by name | Pastes it |
| `define serendipity` | The dictionary entry | Opens it in Dictionary |
| `translate bom dia`, `… to spanish` | The translation (on the Mac); `translate` alone, what you copied | Copies it |
| `gh copperlight`, `github` | Your `[[command]]` entries | Opens, launches or runs it |
| `deploy staging` | Your scripts in `~/.config/copperlight/scripts/`, community script commands too | Runs it with the text as arguments |
| `sig`, `reply John` | Your `[[snippet]]` entries | Pastes the text, placeholders filled in |
| `:` | Commands for windows, apps, files, the Mac | Runs it |
| `:export pdf`, `:new tab` | The menus of the app you were in | Chooses that menu item |
| `:play`, `:mute`, `:wifi`, `:awake`, `:output` | What's playing, the sound, Wi-Fi, keeping the Mac awake | Toggles it, or switches to that output |
| `:!git status` | A shell line | Runs it, shows the output; Enter again copies |
| `json`, `uuid`, `upper hi`… | Text tools | Copies (or pastes) the result |
| `paste plain`, `paste markdown` | The clipboard, cleaned or as Markdown | Pastes it |
| `add note …`, `add todo …`, `add event …` | Capture | Adds it |
| `screenshot`, `record` | The screenshot toolbar | Opens it |
| `note`, `note work` | The floating note, or a named one | Shows it |
| `clip` | Clipboard history | Shows it |
| `pomo`, `pomo 50`, `pomo break`, `pomo stop` | The pomodoro timer | Starts or stops it |
| `timer 10 min tea`, `timer 90s`, `timer stop` | A timer | Starts or stops it |
| `ip`, `battery`, `disk` | Your IP addresses (and the public one, asked on Enter), the battery, free space per disk | Copies the IP, opens Battery or Storage settings |
| `port`, `port 3000` | Your processes listening on TCP ports | Ends that process (asks first) |
| `:layout save work`, `:layout work` | Every window on screen, saved by name | Saves them, or puts them back |

## The launcher

- **One hotkey** opens and hides it (`[hotkeys] launcher`, ⌥Space by default). It's the only global hotkey:
  everything else is found by typing.
- **Opens on what you selected:** with text selected in the app you're in, the hotkey opens with it typed and
  selected (on one line, up to 500 characters): `tra` ⇥ translates it, Enter searches it, typing replaces it. Read
  through Accessibility, never from a password field; apps that don't share their selection open empty.
- **Keys:** ↑ ↓ move, Enter runs, Tab fills in, Esc hides (or backs out of a question or an output). No other
  modifiers: anything else is a `:` command.
- **↑ in the empty field brings back what you ran,** the last 50 queries, newest first; ↑ again (on the top row)
  goes further back. Each comes back as it was run: in its chip, or typed. Kept in `state.json`.
- **It never takes focus** from the app you were in, so window commands and pastes act on that app.
- **The selected row says what Enter does** ("Open ↵", "Paste as Markdown ↵").
- **Some rows ask first** (`:restart`, `:empty trash`, `:clear`): Enter shows the question, Enter again does it.
- **Some rows fill in instead of run,** and their key is Tab: Tab on `Translate` types `translate `, on `Quit
  Application` `:quit `, on a folder its path (Enter does the same). With a name typed whole (`translate`), Tab fills
  it in whatever row is selected.
- **A name that takes text becomes a chip:** `translate `, `define `, `emoji `, `stock `, `pomo `, `timer `, `port `, `add todo `, `:quit `, `:!`,
  `f `. Tab turns the name into a copper chip at the start of the field, keeping what you typed after it
  (`stock aapl` ⇥); the field shows what comes after it with a hint while empty, and only that feature answers (no
  search row). Typing never makes a chip, so `stock apple` still finds `stock_Apple.pdf`. Delete in the empty
  field turns the chip back into the text.
- **What you pick rises (frecency):** every Enter makes that row rank higher next time, fading over a few weeks.
  No aliases or numbers to set up.
- **Other names work too:** Copperlight's own things and the Mac's apps answer to the words people also use for them,
  from 3 letters: `:turn off` finds Shut Down, `:reboot` Restart, `:kill slack` force quits Slack, `:sound 30` sets the
  volume, "task manager" Activity Monitor, "control panel" System Settings, "paste history" Clipboard History,
  "countdown" the timer, "guid" a UUID. They rank just below a match on the real name. The list is hand-picked
  (Sources/OtherNames.swift); NaturalLanguage's phrase similarity was tried and guessed wrong too often.
- **Ranking:** an exact command alias first, then Copperlight's own features typed by name, then apps, commands, math
  and currency by how well they match, then files, and the search row last.
- **The look:** two floating glass pieces, a pill search field and a results card
  under it, in the icon's copper. Long lists fade at the edges instead of being cut. Follows light and dark mode.

## Finding things

- **Apps:** everything in `/Applications`, `/System/Applications`, `~/Applications` and one level of subfolders
  (Utilities). Fuzzy: `vsc` finds Visual Studio Code. Re-scanned each time the launcher opens.
- **Apps by what they do** (from 3 letters): `draw` finds Affinity, `noise` Krisp, `docker` OrbStack, `chat`
  WhatsApp, with the matching word beside the name. From an index of each app (`apps.json`): its category,
  publisher and the documents it opens; online, Homebrew's description and the homepage's summary, or the App
  Store's for App Store apps; with Apple Intelligence on, words from the Mac's on-device model. Built in the
  background, then only new and updated apps. `[apps] online = false` keeps it on the Mac.
- **Files:** after 2 letters, names in the `[files]` scopes with a word starting with each word you type
  (`inv 2026`). Uses the Spotlight index. `exclude` hides paths like `node_modules`. Start with `f ` for files
  only, and more of them.
- **Text inside files and pictures** (from 3 letters): documents, PDFs, screenshots and images whose text has
  the words, below the name matches, marked "Text inside" or "Text in image". The preview shows the picture or the
  matching lines. Spotlight reads images when the Mac is idle, so a brand-new one may take a while.
- **Text in your photos** (with Photos access): `29.99` finds the photo of a price tag. Copperlight reads each
  photo's text once, on the Mac, into `photos.sqlite`; Enter opens a copy in Preview.
- **Paths:** anything starting with `~` or `/`. A folder lists its contents, with itself on top (Enter opens it
  in Finder). Otherwise the last part narrows the folder above it (`~/code/he`). Hidden files once the name
  starts with `.`.
- **Web:** URL-shaped text gets an "Open" row; the last row searches Google, or the engine Settings › Browser
  picks (DuckDuckGo, Bing, Brave Search, Ecosia, Kagi), with its logo. Both open where `[browser]` says: a
  browser and a profile ("Google Chrome: Work"), or the default browser.
- **System Settings pages** (from 3 letters): by name (`bluetooth`, `displays`, `privacy`) or by something on
  them (`dark mode` → Appearance, `night shift` → Displays, `dock`, `default browser`). Ranked like apps.
- **Emoji:** `emoji party` lists the emoji whose names have words starting with what you typed (🎉 Party
  popper), with the emoji picker's own names, flags and combinations too. Enter pastes it.

## Math and money

- **Calculator:** `+ - * / ^`, parentheses, `sqrt(2)`, `pi` and the usual math functions. Enter copies the result.
  - Percentages: `20% of 150` (30), `150 + 20%` (180), `150 - 20%` (120). `%` elsewhere is the remainder (`10 % 3`).
  - Hex and binary: `0xff + 1`, `0b1010 * 2`; `255 in hex` (0xFF), `0xff in dec`, `(2^8 - 1) to binary`; `0xff`
    alone shows 255.
  - `ans`: the last result you copied with Enter (`ans * 2`, `ans in hex`). Forgotten on quit.
- **Currency:** `25 usd to eur`, `12,50 gbp in brl`, `100jpy usd`. Without a target, it converts to
  `[currency] default_target`, and that currency itself converts to USD. ECB rates, cached for a day, so it
  works offline.
- **Stocks:** `stock AAPL`, `stock MGLU3.SA`, `stock ^BVSP`, `stock BTC-USD` (Yahoo Finance's tickers; `sto` ⇥ is the
  Stock chip). The row is the price and today's change; the preview pane draws the last 7 days, hourly, in copper,
  with the change over them, the previous close, the exchange and when it was last traded. Enter opens the stock on
  Yahoo Finance. The ticker goes to Yahoo only in the Stock chip, once typing pauses (350 ms); an answer is kept a
  minute. It's Copperlight's one request that says what you looked up. Typed without the chip, `stock aapl` asks
  nothing: a row under the files offers it (Stock Price of AAPL, Tab).

- **Units:** `10 km in mi`, `10km mi`, `100 f to c`, `2,5 kg`, `1 gb in mb`, `90 min in h`, `1 day in hours`.
  Length, weight, temperature, volume, speed, data, time and area, by the names people type (`km`, `miles`,
  `°c`, `lbs`, `kmh`, `cups`). Without a target, metric and US units convert to each other: `30c` gives °F.
- **Time zones:** `now in tokyo`, `time in tokyo`, `3pm in sf` (3pm here), `15:30 lisbon in new york`, `noon utc
  to sf`. Places are cities (any time zone city), common aliases (`sf`, `nyc`, `la`, `india`) or abbreviations
  (`pst`, `utc`, `cet`). The row says the day there and how many hours ahead or behind.

## The Mac's numbers

- **`ip`:** each interface's IPv4 address, by the name System Settings gives it (Wi-Fi, Ethernet); Enter copies it.
  The Public IP row asks api.ipify.org only when you press Enter on it, then shows the address; Enter copies it.
- **`battery`** (from `batt`): the charge, what it's doing and the time left or to full ("87%, 3:12 left"), its health
  and cycle count. Enter opens Battery settings. A Mac without one says so.
- **`disk`:** free space of the startup disk and every other one mounted, as Finder counts it ("245 GB free of 994
  GB", "75% used"). Enter opens Storage settings, or the disk in Finder.
- **`port`** (a chip, with Tab): your processes listening on TCP ports, from `lsof`; `port 3000` or `port 30` those
  on a port starting with it, `port node` by name. Enter ends the process (asks first). Other users' processes
  aren't listed: you couldn't end them anyway.

## Your browser

- **Bookmarks and history** (from 2 letters): each word typed starts a word of a page's title or address
  (`copperlight git` → "Copperlight on GitHub"). Up to 4 bookmarks, then the 4 most recent pages, a title on a site once, just
  above files. From the browser `[browser]` names, else the default one; its
  profile, or all of them (the row says which). Each opens in the profile it came from. Chrome, Brave, Edge,
  Vivaldi, Chromium and Firefox work as they are; Safari needs Full Disk Access for Copperlight. Loaded when the
  launcher opens (at most every 2 minutes), kept in memory only.
- **Meetings** (`meetings`, from `mee`): the rest of today, soonest first, with start time and how soon. Enter
  joins a Meet, Zoom, Teams or Webex call found in the event (a Meet link opens in your `[browser]` profile), or
  opens Calendar. Calendars added to the Calendar app count (Google, Outlook).

## Words

- **Define** (`define serendipity`): the entry from the Mac's dictionaries (Dictionary.app's, offline), in the
  preview pane. Enter opens it in Dictionary.
- **Translate** (`translate bom dia`, `translate good morning to spanish`): Apple's on-device translation. The
  text's language is detected; it goes to the language you name (`to`, `in`, `into` + a name or a code), or else
  to `[translate] default_target` (Settings › General › Translate to), or else your first language in System Settings
  that isn't the text's. With no text (`translate`, `translate to
  spanish`) it translates what's on the clipboard. The language can be a chip, Translate to German: press Tab with
  it first (`to ger` ⇥) or at the end of the text (`hello world to ger` ⇥), and the field keeps only the text. Enter copies it. A language pair that isn't
  downloaded yet gets a row that opens Language & Region, where Translation Languages downloads it. Needs macOS 26.

## Your commands

`[[command]]` entries in config.toml, found by their alias like apps.

- **`url`:** opens a link with any scheme (`https`, `slack://`, `obsidian://`). `browser` and `profile` pick
  where (Chrome, Brave, Edge, Vivaldi, Firefox profiles); a web link without them follows `[browser]`.
- **Quicklinks:** `{query}` in the URL takes the text after the alias (`gh copperlight` searches GitHub).
- **`app`:** launches or activates an app. **`file`:** opens a file. **`shell`:** runs a line in a login shell,
  detached; a failure posts a notification.
- **Replacing a built-in:** a command or script named like one (`screenshot`, `add todo`) runs instead of Copperlight's
  own, so CleanShot or Things can take over.

## Your scripts

Every executable file in `~/.config/copperlight/scripts/` is a command, found by its file name (without the extension).
Text after the name becomes its arguments: `deploy staging` runs `deploy staging`. Scripts run in a login shell,
so they see the PATH a terminal has. A comment near the top can set:

| Line | Does |
|---|---|
| `# @title Deploy App` | The row's title (otherwise the file name) |
| `# @icon hammer` | An SF Symbol for the row |
| `# @output silent` | The default: runs in the background; a failure posts a notification |
| `# @output show` | Shows the output in place of the list, like `:!`; Enter copies it |
| `# @output copy` | Copies what it prints (stdout) and confirms with a notification |

Community script commands work unchanged: their title, mode, icon (an SF Symbol name), description, confirmation
and declared arguments are read from their headers (docs/guide.md has the details).

## Your snippets

`[[snippet]]` entries in config.toml: a `name` to type and a `text` to paste (multi-line with `"""`). Enter
pastes it into the app you were in, then puts back what was on your clipboard, so `{clipboard}` is always what
you copied (without Accessibility it only copies).
The row shows its first line, and long ones show whole in the preview pane.

| Placeholder | Becomes |
|---|---|
| `{date}`, `{time}` | Today and now: `2026-10-13`, `16:55` |
| `{clipboard}` | The clipboard's text |
| `{query}` | The text typed after the name: `reply John` with `Hi {query},` pastes `Hi John,` |

## `:` commands

`:` lists them all; typing narrows them (`:min`, `:fq`). Window and app commands act on what you were in.

| Group | Commands |
|---|---|
| Menus | `:export pdf`, `:new tab`: the enabled items of the menus of the app you were in, from 3 letters, after the commands, each with where it is and its shortcut; Enter chooses it |
| Windows | `:window term` lists every window of every app (this Space and minimized ones) by title or app, front first; Enter brings it forward |
| Window in front | `:minimize`, `:fullscreen`, `:close`, `:maximize`, `:center`, `:left`, `:right`, `:top`, `:bottom`, quarters (`:top left`…), thirds (`:left third`…), two thirds, `:next display`, `:nudge left` (right, up, down: a step of 5% of the screen; the panel stays open, so Enter again moves it again), `:restore` (undo Copperlight's last moves) |
| Layouts | `:layout save work` keeps every window on screen (this Space: not hidden, minimized or full screen) by app and title; `:layout work` puts them back, matching each app's windows by title, then in order, on the same screen or the same share of the main one if it's gone; apps that aren't open are named in a notification. `:layout` lists them, `:layout delete work` forgets one. Kept in `state.json`, since the frames belong to this Mac's screens |
| Running apps | `:quit saf`, `:force quit saf` (asks first), `:hide saf`, `:hide others`, `:relaunch slack` |
| Files | `:reveal readme`, `:copy path readme` (file search, or a path: `:copy path ~/code/copperlight/`) |
| The Mac | `:lock`, `:sleep`, `:sleep displays`, `:restart`, `:shut down`, `:empty trash` (these three ask first), `:dark`, `:wifi`, `:awake`, `:hidden files`, `:eject`, `:shortcut name` (your Shortcuts, also the way to Focus modes). `:dark`, `:wifi` and `:awake` say what Enter does now (Turn Wi-Fi Off) |
| Sound | `:play` (play or pause), `:next track`, `:previous track`: the keyboard's media keys, so they reach whatever is playing (Music, a browser tab, Spotify). `:mute` (Mute or Unmute), `:volume 30`, `:output airpods` lists the sound outputs, the current one first; Enter switches to it |
| Shell | `:!git status` (below) |
| Copperlight | `:config` opens config.toml |

**Shell (`:!`):** runs the line in a login shell (`zsh -lc`, in your home folder) when you press Enter, never
while typing. The output replaces the list and grows as it comes; Esc stops it and goes back to edit or rerun,
and once it's done Enter copies it. `:!` alone lists
the lines you ran, most used first. Stopped after 30 seconds. `~/.config/copperlight/scripts` is on its PATH. Hide the
launcher while it runs and a notification says how it ended.

**Long runs:** a `:!` line and a script with `@output show` show their output as it comes. Esc stops
them (the process is ended); hiding the panel lets them finish, and a notification says how they ended.

## Text tools

Type a name, then the text (`upper hello`), or just the name to use the clipboard. Long results show in a
preview pane. From 3 letters, a name's start finds it too (`pas` → the paste tools).

| Type | Gives |
|---|---|
| `uuid`, `password`, `password 32`, `lorem`, `lorem 3` | A UUID, a password (20, or 4–256 characters), Lorem Ipsum |
| `json`, `json min` | JSON formatted or minified, key order kept |
| `b64`, `b64 decode`, `url encode`, `url decode` | Encoded or decoded text |
| `upper`, `lower`, `snake`, `camel` | The text in that case |
| `sort lines`, `count`, `sha256` | Sorted lines (a9 before a10); words, characters, lines; the hash |
| `unix`, `unix 1700000000` | Now as a timestamp; a timestamp as a date |
| `hex #ff8800`, `hex 255 136 0` | The color in the other notation |
| `paste plain`, `paste markdown` | Pastes the clipboard without formatting, or as Markdown (from web pages, Google Docs, Slack, Word…) |

## Capture

`add` lists what you can add.

| Type | Does |
|---|---|
| `add note buy milk` | Appends the line to the floating note |
| `add todo call mom tomorrow 5pm` | A reminder in your default list, due and alerting then (a day alone: due that day) |
| `add event fri 10am dentist` | An event in your default calendar, an hour or the range typed (a day alone: all day) |
| `screenshot`, `record` | The macOS screenshot toolbar, set to capture or to record |

The row shows the title and date Copperlight read before you press Enter; a notification confirms it. Dates in English.

## Panels

- **Note** (`note`): a floating note on a glass card like the launcher's, always at hand, saved to `note.txt` as
  you type. Drag it by its title, resize it from its bottom-right corner; it remembers both. Esc hides it. Edits
  made in another editor are picked up.
- **Named notes** (`note work`): as many as you like, each in `notes/<name>.txt`, with its own place on screen.
  `note` lists them under the note; `note wo` finds them by name, or offers a new one. `add note` adds to the
  note. To delete one, delete its file.
- **Clipboard history** (`clip`): text and images you copy, newest first under Today, Yesterday, Earlier,
  with a preview and details. Typing filters (`image` lists images). Enter pastes into the app you were in.
  Its own `:` commands: `:copy` (copy without pasting), `:delete`, `:clear` (asks first). Skips copies marked
  as passwords and copies made in `ignore_apps` (password managers by default). Keeps 1000 items or 90 days by
  default.
- **Welcome** (`welcome`): opens by itself on first launch. Shows the hotkey and checks it off once you've
  pressed it; Allow buttons for Accessibility, Calendars, Reminders and Notifications, each turning into a
  check as soon as macOS says yes (Open Settings if it was refused); Open at Login; Start Typing (Enter) opens
  the launcher. Esc closes it. Also in the menu bar menu.
- **Pomodoro** (`pomo`): a timer with a countdown in the menu bar (click it to stop) and a notification with a
  sound at the end. Survives sleep and restarts. `pomo break` starts a break (`[pomodoro] break_minutes`, 5 by
  default; `pomo break 15` for another length), with a cup in the menu bar instead of the timer.
- **Timer** (`timer 10 min tea`): the same for anything else, beside the pomodoro: an hourglass and the countdown in
  the menu bar, and "Timer done" with what it was for, and a sound. A length is `10`, `10 min`, `90s`, `1h30m` or
  `1 hour 30` (a bare number is minutes), from a second to 24 hours; what follows is the label ("for" dropped). One at
  a time: a new one asks before replacing it. `timer` alone offers to stop it; `timer stop` too.

## Settings

**Settings…** in the menu bar, or `copperlight settings` in the launcher. A pane per group: General (hotkey, Open at
Login, currency, translate to, pomodoro), Clipboard (how much to keep, apps not recorded), Files (folders searched, names hidden,
app descriptions online or not),
Browser (where links open, which profile), Commands and Snippets (add, edit, delete), and About (version, license,
and the open source it's built with). Every change goes straight into config.toml, editing only its own lines, comments kept;
one it can't make cleanly is refused, and the file stays as it was. Edits made by hand show up in the window.

## Menu bar

The C, with Settings… (⌘,), Welcome to Copperlight, Launch at Login and Quit. A running pomodoro or timer adds its countdown next to it,
and `:awake` a sun while it keeps the Mac awake (click either to stop it). Keeping awake ends when Copperlight quits.

## Permissions

The welcome window (`welcome`) asks for Accessibility, Calendars, Reminders, Notifications and Photos in one place.
Otherwise macOS asks when a feature first needs one:

| macOS asks for | When | For |
|---|---|---|
| Accessibility | First paste or window command | Pasting (⌘V into your app), window commands and layouts, `:window`, `:lock`, menu search, `:play` and the track keys, opening on the selected text |
| Automation | First `:empty trash`, `:dark`, `:restart`, `:shut down` | Asking Finder, System Events, loginwindow to do it |
| Reminders | First `add todo` | Adding reminders (no add-only option exists) |
| Calendars, add only | First `add event` | Adding events |
| Calendars, full access | `meetings`, from its Allow row | Reading today's events |
| Full Disk Access (by hand) | Only for Safari | Reading Safari's bookmarks and history |
| Notifications | First pomodoro, timer or notification | Pomodoro and timer ends, shell results, errors |
| Photos | From the welcome window | Reading the text in your photos, on the Mac |
| Desktop, Documents, Downloads | First time a path lists one | Reading that folder |

Without Accessibility, a paste copies instead, and the row says Copy. System Settings opens at Accessibility the
first time per launch; after that, a notification says where it is.

## Where things live

All in `~/.config/copperlight/`: `config.toml` (your settings, hot reloaded; a mistake shows as an error row),
`note.txt`, `notes/` (named notes), `state.json` (frecency, recent queries, saved layouts, the timer), `clipboard.sqlite` (history, readable only
by you), `rates.json` (currency rates), `apps.json` (what each app does) and `homebrew-apps.json` (Homebrew's list,
trimmed), `photos.sqlite` (the text in your photos), `scripts/` (on the shell's PATH).

## Not here on purpose

An AI service or chat (app words come from the Mac's own model), a plugin store, sync, accounts, hotkeys for anything but the launcher, and prefix symbols besides `:`.
See SPEC.md.
