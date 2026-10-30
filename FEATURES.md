# Copperlight: everything it does

One page with every feature: what you type, what you get, and what it needs. The details live in
[docs/guide.md](docs/guide.md) (how to use each one), [docs/configuration.md](docs/configuration.md) (config) and the reasons in [SPEC.md](SPEC.md). When a feature ships, it gets a
line here.

**Not offered yet**, with their code kept: the text inside files and the text in photos. Everything else on this page
is on, and each one can be turned off: Settings › Features, or `[features]` in config.toml
([configuration.md](docs/configuration.md)). Off means off: no rows, no commands, nothing in the background, nothing
sent, no permission asked for. The keywords below (`translate`, `:`…) can have your own words beside them: Settings ›
Keywords, or `[keywords]` (`translate = "t"`, `commands = ";"`).

## At a glance

| Type | You get | Enter |
|---|---|---|
| `saf` | Apps | Opens it |
| `invoice`, `f invoice` | Files and folders (Spotlight) | Opens it |
| `~/code/copperlight`, `/Applications` | That folder's contents | Goes into a folder, opens a file |
| `gmail.com`, `localhost:3000` | An "Open" row | Opens it in `[browser]` |
| anything | "Search Google for …", always last | Searches (Settings › Browser picks the engine) |
| `2^10 / 3`, `20% of 150`, `20% off 80`, `30 is what % of 150`, `10k * 3`, `255 in hex` | The result; Tab puts it in the field to keep going | Copies it |
| `25 usd to eur`, `25 usd`, `39*8 usd` | The conversion | Copies it |
| `10 km in mi`, `30c` | Units converted | Copies it |
| `3pm lisbon in sf`, `now in tokyo` | The time there | Copies it |
| `days until dec 25`, `in 3 weeks`, `dec 25` | How long, which day; a date's weekday and week | Copies it |
| `stock AAPL`, `stock MGLU3.SA` | The price, today's change and a 7-day chart across the card (Yahoo Finance) | Opens it on Yahoo Finance |
| `weather`, `weather lisbon` | Now, the next hours and five days across the card (Open-Meteo) | Opens Weather |
| `copperlight git` | Bookmarks and recent pages from your browser | Opens it in its profile |
| `inbox`, `tabs` ⇥ | The tabs open in your browsers | Switches to it |
| `ana` | People from Contacts; Tab: every way to reach them | Messages them |
| `due` | Reminders due today and overdue (soon ones wait in the empty launcher) | Completes it |
| `meetings`, `agenda`, `events` | The rest of today's events; a copper badge on what's soon; Tab: the details | Joins the video call |
| `bluetooth`, `dark mode` | System Settings pages | Opens that page |
| `emoji party` | Emoji by name | Pastes it |
| `define serendipity` | The dictionary entry, across the card | Opens it in Dictionary |
| `spell definately` | The word spelled right, and the other guesses | Copies it |
| `translate bom dia`, `… to spanish` | The translation (on the Mac); `translate` alone, what you copied | Copies it |
| `gh copperlight`, `github` | Your `[[command]]` entries | Opens, launches or runs it |
| `deploy staging` | Your scripts in `~/.config/copperlight/scripts/`, community script commands too | Runs it with the text as arguments |
| `links docs` | A script filter's rows (`@output rows`), for what you type | Opens or copies the one you pick |
| `sig`, `reply John` | Your `[[snippet]]` entries | Pastes the text, placeholders filled in |
| `:` | Commands for windows, apps, files, the Mac | Runs it |
| `:export pdf`, `:new tab` | The menus of the app you were in | Chooses that menu item |
| `:play`, `:mute`, `:wifi`, `:awake`, `:output` | What's playing, the sound, Wi-Fi, keeping the Mac awake | Toggles it, or switches to that output |
| `:connect` | Paired Bluetooth devices | Connects or disconnects it |
| `:awake 2h`, `:awake until 18:00` | Keeping the Mac awake for a while | Keeps it awake, then lets go by itself |
| `:!git status` | A shell line | Runs it, shows the output; Enter again copies |
| `json`, `uuid`, `upper hi`… | Text tools | Copies (or pastes) the result |
| `#c87533`, `rgb(…)`, `pick color` | The color on a band, in the other notations and a step lighter and darker; a color from the screen | Copies it |
| `qr`, `qr https://…` | A QR code of what you typed or copied, big, its actions beside it | Copies the picture |
| `copy text` | Drag over any part of the screen | Copies its text (a QR code's link opens) |
| `large 555-0100`, `large` | The text across the screen | Shows it |
| `paste plain`, `paste markdown` | The clipboard, cleaned or as Markdown | Pastes it |
| `add note …`, `add todo …`, `add event …` | Capture | Adds it |
| `screenshot`, `record` | The screenshot toolbar | Opens it |
| `note`, then Tab | The Notes chip: your notes alone, last edited first, titled by their first line; typing finds the ones that say it | Opens it; New Note makes one |
| `clip` | Clipboard history | Shows it |
| `pomo`, `pomo 50`, `pomo break`, `pomo stop` | The pomodoro timer | Starts or stops it |
| `timer 10 min tea`, `timer until 15:30`, `timer stop` | A timer | Starts or stops it |
| `stopwatch` | The stopwatch | Starts or stops it |
| `ip`, `battery`, `disk` | Your IP addresses (and the public one, asked on Enter), the battery, free space per disk | Copies the IP, opens Battery or Storage settings |
| `port`, `port 3000` | Your processes listening on TCP ports | Ends that process (asks first) |
| `speed` | An internet speed test (macOS's `networkQuality`) | Runs it, then copies the result |
| `cpu`, `memory`, `cpu chrome` | Your processes, the busiest first by CPU or by memory | Ends it, or quits an app (asks first) |
| `:layout save work`, `:layout work` | Every window on screen, saved by name | Saves them, or puts them back |

## The launcher

- **One hotkey** opens and hides it (`[hotkeys] launcher`, ⌥Space by default). It's the only global hotkey:
  everything else is found by typing.
- **Opens on what you selected:** with text selected in the app you're in, the hotkey opens with it typed and
  selected (on one line, up to 500 characters): `tra` ⇥ translates it, Enter searches it, typing replaces it. Read
  through Accessibility, never from a password field; apps that don't share their selection open empty.
- **Keys:** ↑ ↓ move, Enter runs, Tab fills in (or opens the preview), Esc hides (or backs out of a question or an output). No other
  modifiers: anything else is a `:` command.
- **The next meeting, waiting:** from 10 minutes before a meeting with a call (Meet, Zoom, Teams, Webex) until 10
  minutes after it started, the empty launcher shows it on a band: how soon ("in 4 min", "Now"), its title, times
  and call, who's coming (initials and first names) and the first line of its own notes (never the call's invitation).
  Under it, Join (Enter) and Open in Calendar; `meetings` puts it first the same way. With `[meetings] show_on_open`
  (Settings › Launcher › Calendar: Today's events), the empty launcher lists the day's next five events, that one on its band first. It needs Calendars access already given (`meetings` asks): opening the launcher never asks.
  Typing hides it. Settings › Launcher › Calendar: Nothing (`show_next = false`) keeps it away.
- **Due reminders, waiting:** the reminders that are overdue, due within the hour, or due today with no time, soonest
  deadline first, with a copper badge ("Overdue", "in 20 min", "Today"). Enter completes one and keeps the launcher
  open for the next. Needs full Reminders access already given (`add todo` or `due` asks). `[reminders] show_due = false`
  (Settings › Launcher) keeps them away; `due` still lists them.
- **Suggestions, waiting:** up to 3 apps you open around this time of day (from the launcher, within an hour of now, on
  3 days or more of the last 4 weeks), not the one you're in. Kept in `state.json`; `[apps] suggestions = false`
  (Settings › Launcher) turns them off and stops keeping what you open; Forget deletes what's kept.
- **Tab steps into some rows** while Enter still runs them, and the selected row names both: on a person, Actions ⇥
  (Message ↵); on a calculation, Keep Going ⇥ puts the result in the field (Copy ↵).
- **Tab on a file, an app or a clipboard item: what you can do with it,** in place of the list under its name, with
  its preview beside it; Esc goes back to the list, typing searches again.
  - A file: Open (in its app), Open With… (fills in `:open with`), Reveal in Finder, Copy Path, Copy File (to paste
    in Finder or an email), Open in Terminal, Move to Trash (asks first). Beside them: a text file's start, a picture
    or a PDF's first page, and where it is, its kind, size and when it changed.
  - An app: its recent documents first, the files in your home folder of the kinds the Mac opens in it, the most
    recently opened first (five at most, each with how long ago and its preview); Enter opens one in it. Then Open,
    and while it runs Hide, Quit, Force Quit (asks first) and Relaunch; Reveal in Finder, Copy Path. Beside them: its
    icon, version and where it is.
  - A clipboard item: Paste (or Copy without Accessibility), Copy Without Pasting; for text, Open Link (a web
    address), Large Type and QR Code (the code beside the list, Enter copies it); for a picture, Open in Preview and
    Save to Downloads; Delete from History.
- **↑ in the empty field brings back what you ran,** the last 50 queries, newest first; ↑ again (on the top row)
  goes further back. Each comes back as it was run: in its chip, or typed. Kept in `state.json`. `[learning] recent =
  false` (Settings › Launcher) turns it off, and Forget there deletes them.
- **It never takes focus** from the app you were in, so window commands and pastes act on that app.
- **The selected row says what Enter does** ("Open ↵", "Paste as Markdown ↵").
- **Some rows ask first** (`:restart`, `:empty trash`, `:clear`): Enter shows the question, Enter again does it.
- **Some rows fill in instead of run,** and their key is Tab: Tab on `Translate` types `translate `, on `Quit
  Application` `:quit `, on a folder its path (Enter does the same). With a name typed whole (`translate`), Tab fills
  it in whatever row is selected.
- **A name that takes text becomes a chip:** `translate `, `define `, `spell `, `emoji `, `stock `, `qr `, `large `, `contact `, `tabs `, `pomo `, `timer `, `port `, `cpu `, `memory `, `note `, `add todo `, `:quit `, `:!`,
  `f `, a script filter's name. Tab turns the name into a copper chip at the start of the field, keeping what you typed after it
  (`stock aapl` ⇥); the field shows what comes after it with a hint while empty, and only that feature answers (no
  search row). Typing never makes a chip, so `stock apple` still finds `stock_Apple.pdf`. Delete in the empty
  field turns the chip back into the text.
- **What you pick rises (frecency):** every Enter makes that row rank higher next time, fading over a few weeks.
  No aliases or numbers to set up.
- **What you picked for what you typed comes first:** Enter on Slack with `ss` typed, and next time `ss` puts Slack
  on top, above everything else, an exact alias included. Only for that text (case and spaces aside, up to 15
  characters); picking another row for it takes over, and it fades like frecency. `[learning] picked = false`
  (Settings › Launcher) turns both off: nothing new is kept and what's kept isn't used. Forget deletes it.
- **Other names work too:** Copperlight's own things and the Mac's apps answer to the words people also use for them,
  from 3 letters: `:turn off` finds Shut Down, `:reboot` Restart, `:kill slack` force quits Slack, `:sound 30` sets the
  volume, "task manager" Activity Monitor, "control panel" System Settings, "paste history" Clipboard History,
  "countdown" the timer, "guid" a UUID. They rank just below a match on the real name. The list is hand-picked
  (Sources/OtherNames.swift); NaturalLanguage's phrase similarity was tried and guessed wrong too often.
- **Ranking:** an exact command alias first, then Copperlight's own features typed by name, then apps, commands, math
  and currency by how well they match, then files, and the search row last.
- **The preview beside the list:** in the general search the list keeps its full width; a row with something to show
  (a note, a long snippet) says "Preview ⇥", and Tab opens it beside the list (Tab again closes it; a
  new search starts without it). In clipboard history, in chips and in a command's output it's open from the start.
  It only ever shows for a row with something in it.
- **Answers in their own shape:** an answer that reads better big takes the card in place of the list and the preview,
  laid out for what it is. A stock, a dictionary entry and the speed test's result fill it (Enter opens or copies it); a QR code sits big
  on the left with its actions as rows beside it; a color is a band over its rows. Every row of the answer carries it, so it stays while you move between
  them, and on to the search row under it. `[answers] cards = false` (Settings › Launcher) shows them as plain rows.
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
- **Apps you don't have**, with Homebrew installed (from 3 letters): when what you type isn't the start of an app you
  have, Homebrew's apps whose name starts with it, two at most, below everything else: "Install Figma", with its
  description. Enter runs `brew install --cask figma`, its output beside the row; Enter again hides the launcher and a
  notification says when it's done. Then Enter opens it. An app that needs your password to install can't ask here:
  the row says so, and Enter copies the command for a terminal. From the same Homebrew list, so `[apps] online = false`
  turns it off.
- **Files:** after 2 letters, names in the `[files]` scopes with a word starting with each word you type
  (`inv 2026`). Uses the Spotlight index. `exclude` hides paths like `node_modules`. Start with `f ` for files
  only, and more of them. Tab on one: what you can do with it.
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

- **Calculator:** `+ - * / ^`, parentheses, `sqrt(2)`, `pi` and the usual math functions. On a band over its row:
  what you typed = the answer, big, and what a percentage hid (`150 + 20%`: "20% of 150 is 30"; `20% off 80`: "You
  save 16"). Enter copies the result.
  - Percentages: `20% of 150` (30), `150 + 20%` (180), `150 - 20%` (120), `20% off 80` (64), `30 is what % of 150`
    (20%). `%` elsewhere is the remainder (`10 % 3`).
  - `k` for thousands, in math: `10k * 3` (30000), `2.5k + 1`. Alone, `10k` is left to the search.
  - Tab puts the result in the field (Keep Going), to calculate on with it.
  - Hex and binary: `0xff + 1`, `0b1010 * 2`; `255 in hex` (0xFF), `0xff in dec`, `(2^8 - 1) to binary`; `0xff`
    alone shows 255.
  - `ans`: the last result you copied with Enter (`ans * 2`, `ans in hex`). Forgotten on quit.
- **Currency:** `25 usd to eur`, `12,50 gbp in brl`, `100jpy usd`. On a band: what you had → what it makes, big,
  with the currency names, the rate (`1 USD = 0.8593 EUR`) and how fresh it is ("Live rate, 2 min ago"), and both flags faintly behind, one at each end.
  Enter copies it as money (€21.48); the row below copies the number alone (21.48). Without a target, it converts to
  `[currency] default_target`, and that currency itself converts to USD. Math before it works too: `39*8 usd`. Live
  rates from Coinbase's public rates, every currency in one request (so it never learns which one you convert), crypto
  too (`0.1 btc in eur`): fetched when the launcher opens and they're over 5 minutes old, kept on disk, so it works
  offline (the band then says how old they are).
- **Stocks:** `stock AAPL`, `stock MGLU3.SA`, `stock ^BVSP`, `stock BTC-USD` (Yahoo Finance's tickers; `sto` ⇥ is the
  Stock chip). Across the whole card: the ticker and name, the price and today's change (▲ or ▼), when it was last
  traded and where, the last 7 days drawn hourly in copper with yesterday's close dashed across, and under it the
  previous close and the change over the 7 days. Enter opens the stock on Yahoo Finance. The ticker goes to Yahoo only in the Stock chip, once typing pauses (350 ms); an answer is kept a
  minute. With weather, it's one of the two requests that say what you looked up. Typed without the chip, `stock aapl` asks
  nothing: a row under the files offers it (Stock Price of AAPL, Tab).
- **Weather:** `weather` (`wea` ⇥ is the Weather chip). Nothing typed: where you are, from Location Services (asked
  once, from a row: Weather Where You Are, Allow), else `[weather] city` (Settings › General › Weather); a city typed
  (`weather lisbon`): that city. Across the whole card: the temperature now big with its symbol, the conditions, today's
  high and low, how it feels and the wind; the next five days with their lows and highs on bars of one scale; the next
  seven hours along the bottom. °F and mph where the Mac uses US units. Enter opens the Weather app. Like a stock, the
  place goes to Open-Meteo (free, no key) only in the chip, once typing pauses; where you are goes rounded to about a
  kilometer, and an answer is kept 10 minutes.

- **Units:** `10 km in mi`, `10km mi`, `100 f to c`, `2,5 kg`, `1 gb in mb`, `90 min in h`, `1 day in hours`.
  Length, weight, temperature, volume, speed, data, time and area, by the names people type (`km`, `miles`,
  `°c`, `lbs`, `kmh`, `cups`). Without a target, metric and US units convert to each other: `30c` gives °F.
- **Time zones:** `now in tokyo`, `time in tokyo`, `3pm in sf` (3pm here), `15:30 lisbon in new york`, `noon utc
  to sf`. Places are cities (any time zone city), common aliases (`sf`, `nyc`, `la`, `india`) or abbreviations
  (`pst`, `utc`, `cet`). The row says the day there and how many hours ahead or behind.
- **Dates:** `days until dec 25`, `weeks since jan 1`, `in 3 weeks`, `100 days from today`, `3 days ago`, `30 days
  after dec 25`, `dec 25 + 2 weeks`, `monday in 3 weeks` (that week's Monday), `time in 4 hours`. A date alone (`dec
  25`, `next friday`, `2026-12-25`, `christmas`) shows its weekday, how far it is and its week. Before you finish, `in
  3` answers in 3 days, weeks, months and hours, `3 weeks` from now and ago, and `days` offers until or since a date
  (Tab). Enter copies it.

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
- **`cpu` and `memory`** (also `kill process`, `processes`, `ram`): your processes, from `ps`, the busiest first by
  recent CPU or by memory, each with its CPU, memory and pid, and the icon of the app it belongs to (a Chrome Helper
  shows Chrome's). Typed, the 8 busiest; `cpu` ⇥ or `memory` ⇥, the chip, lists them all, and `cpu chrome` narrows
  them by name. Enter ends a process after asking (SIGTERM), or quits an app, which can ask to save. Copperlight and
  other users' processes aren't listed.
- **`speed`** (also `speedtest`, `internet speed`, `bandwidth`): Enter runs macOS's own `networkQuality` against
  Apple's servers, about 20 seconds: its card shows at once, download and upload climbing as they're measured, a
  spinner and the seconds so far (Esc stops it). Then the result settles on the card: download and upload big ("322 Mbps", "243 Mbps"), the latency idle and under load, how you're connected and
  when it was tested; Enter copies it.
  Nothing is sent until Enter.

## Your browser

- **Bookmarks and history** (from 2 letters): each word typed starts a word of a page's title or address
  (`copperlight git` → "Copperlight on GitHub"). Up to 4 bookmarks, then the 4 most recent pages, a title on a site once, just
  above files. From the browser `[browser]` names, else the default one; its
  profile, or all of them (the row says which). Each opens in the profile it came from. Chrome, Brave, Edge,
  Vivaldi, Chromium and Firefox work as they are; Safari needs Full Disk Access for Copperlight. Loaded when the
  launcher opens (at most every 2 minutes), kept in memory only.
- **Open tabs** (from 2 letters): the tabs open in Chrome, Brave, Edge, Vivaldi, Chromium, Arc and Safari, found the
  same way, up to 4, just above bookmarks. Enter switches to the tab, its window in front. `tabs` ⇥ is the Tabs chip:
  every tab, in window order. Private windows aren't listed. Read through AppleScript when the launcher opens, from
  the browsers that are running and that you allowed (once per browser, from the Tabs chip's row), kept in memory only.
- **Meetings** (`meetings` from `mee`, `agenda` from `age`, `events`): the rest of today, soonest first, with start
  time and how soon, a copper badge on one within the hour or going; Tab shows its details. Enter joins a Meet,
  Zoom, Teams or Webex call found in the event (a Meet link opens in your `[browser]` profile), or opens Calendar.
  Calendars added to the Calendar app count (Google, Outlook).

## People and reminders

- **Contacts** (from 2 letters): people whose name, nickname or company has a word starting with each word typed. The
  row shows their number and email; Enter messages them (mobile number, else a number, else their email), or opens
  their card. Tab: the Contact chip, with Message, Call, FaceTime and WhatsApp (when installed) per number, Email per
  address, Copy for each, and Open in Contacts, beside their card (photo or initials, name, job and company, numbers, emails,
  birthday). `contact` ⇥ lists everyone. Access is
  asked from the `contacts` row; read when the launcher opens (at most every 2 minutes), kept in memory only.
- **Due reminders** (`due`, `overdue`, `todos`): incomplete reminders due today or before, soonest deadline first, with
  their list and a copper badge. Enter completes one, the launcher staying open. The soon ones also wait in the empty
  launcher.

## Words

- **Define** (`define serendipity`): the entry from the Mac's dictionaries (Dictionary.app's, offline), across the
  card: the word set in a serif with its pronunciation; its first two parts of speech, three meanings of the first and
  one of the next, each with its first example; and where it comes from. Its forms, grammar labels, phrases and
  derived words are left out. Enter opens the whole entry in Dictionary.
- **Spell** (`spell definately`): the word spelled right and the other guesses, best first; a sentence comes back with
  each misspelled word corrected; one that's right says so. The Mac's own spelling. Enter copies it.
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
| `# @output rows` | A script filter: its name is a chip, and what it prints for the text after it is the list |

**Script filters** (`@output rows`) run with the text typed after their name as their one argument, once typing
pauses, in their chip (Tab) or typed whole. Each line printed is a row: its title, then after tabs a subtitle and the
value Enter uses. Enter opens a file, a folder or a link an app takes, and copies anything else.

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
| `{cursor}` | Where the cursor ends up once it's pasted: `Dear {cursor},` leaves it after `Dear ` |

## `:` commands

`:` lists them all; typing narrows them (`:min`, `:fq`). Window and app commands act on what you were in.

| Group | Commands |
|---|---|
| Menus | `:export pdf`, `:new tab`: the enabled items of the menus of the app you were in, from 3 letters, after the commands, each with where it is and its shortcut; Enter chooses it |
| Windows | `:window term` lists every window of every app (this Space and minimized ones) by title or app, front first; Enter brings it forward |
| Window in front | `:minimize`, `:fullscreen`, `:close`, `:maximize`, `:center`, `:left`, `:right`, `:top`, `:bottom`, quarters (`:top left`…), thirds (`:left third`…), two thirds, `:next display`, `:nudge left` (right, up, down: a step of 5% of the screen; the panel stays open, so Enter again moves it again), `:restore` (undo Copperlight's last moves) |
| Layouts | `:layout save work` keeps every window on screen (this Space: not hidden, minimized or full screen) by app and title; `:layout work` puts them back, matching each app's windows by title, then in order, on the same screen or the same share of the main one if it's gone; apps that aren't open are named in a notification. `:layout` lists them, `:layout delete work` forgets one. Kept in `state.json`, since the frames belong to this Mac's screens |
| Running apps | `:quit saf`, `:force quit saf` (asks first), `:hide saf`, `:hide others`, `:unhide all`, `:relaunch slack`, `:quit all` and `:quit others` (every app, or all but the one in front; ask first; never Finder) |
| Files | `:reveal readme`, `:copy path readme`, `:trash readme` (asks first), `:terminal readme` (its folder, in `[files] terminal`: Terminal unless you pick another in Settings › Files) (file search, or a path: `:copy path ~/code/copperlight/`). `:open with readme` lists files; Tab on one, then the apps that open it, its default first (`:open with ~/x/readme.md code`) |
| The Mac | `:lock`, `:sleep`, `:sleep displays`, `:restart`, `:shut down`, `:log out`, `:empty trash` (these four ask first), `:screen saver`, `:show desktop` (hides every app; `:unhide all` brings them back), `:open trash`, `:dark`, `:wifi`, `:awake`, `:hidden files`, `:eject`, `:shortcut name` (your Shortcuts, also the way to Focus modes; `:shortcut name some text` gives it the text as input). `:dark`, `:wifi` and `:awake` say what Enter does now (Turn Wi-Fi Off). `:awake 2h`, `:awake 90 min`, `:awake until 18:00` keep it awake for a while; `:awake` alone also offers an hour or two |
| Sound | `:play` (play or pause), `:next track`, `:previous track`: the keyboard's media keys, so they reach whatever is playing (Music, a browser tab, Spotify). `:mute` (Mute or Unmute), `:mute mic` (the microphone: its mute, or for one without, its level to 0 and back), `:volume 30`, `:output airpods` lists the sound outputs, the current one first; Enter switches to it |
| Bluetooth | `:connect airpods` (also `:disconnect`, `:bluetooth`): the devices paired with this Mac, the ones to connect first, the most recently used first. Enter connects one (a few seconds; the row says whether it worked) or disconnects one that's connected. Typing asks for nothing: the first time, Enter on Allow asks for Bluetooth. Pairing a new device and switching Bluetooth on or off stay in System Settings |
| Notes | `:delete note milk` (by its title or what's in it; to the Trash, asks first) |
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

## Colors, QR codes and the screen

- **Colors:** `#c87533`, `#f80`, `rgb(200, 117, 51)` or `hsl(27, 59%, 49%)`: a band of the color with its hex and
  its contrast on white and on black (WCAG; 4.5 : 1 reads as text), two steps lighter and two darker beside it; under
  it the other two notations, the one you typed, then a step lighter and a step darker (a quarter of the way to white
  or black), each row with its swatch. Enter copies it.
- **`pick color`** (or `color picker`, `eyedropper`): macOS's magnifier; click anywhere on the screen and its hex is
  copied, and the launcher comes back with it, the other notations a row away.
- **`colors`** (or `colours`, `my colors`, `recent colors`): the colors you picked, newest first, the last 30, each
  with its swatch, its RGB and when; Enter copies the hex, and the one you're on shows on the band. None yet: Pick
  Color.
  Kept in `state.json`.
- **QR codes:** `qr https://copperlight.app` (`qr` ⇥ is the QR Code chip) shows the code big, with what it's of,
  and `qr` alone makes one of what you copied. Beside it: Copy Picture (Enter), Save to Downloads (a PNG, shown in
  Finder) and Copy Link (Copy Text when it isn't a web address). Made on your Mac.
- **Text from the screen** (`copy text`, or `ocr`, `scan text`): drag over any part of the screen and its text is
  copied, read on the Mac (Vision). A QR code or barcode there is copied instead, and a link in it comes back in the
  launcher, Enter opening it. Needs Screen Recording, asked the first time; only the part you drag over is read.
- **Large Type** (`large 555-0100`, `large` for what you copied): the text across the screen, as big as it fits. Any
  key, a click or switching apps puts it away.

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
- **Notes, as many as you like, with no names:** a note's first line is its title (a heading's `#`s left out), on its
  card and in the list. `note` offers your last note and Notes; Tab on it is the Notes chip, with only your notes,
  the last edited first, each with the line after the title, its age and, beside the list, its text, then New Note:
  Enter opens an empty one, written once you type. Typed in the chip, `milk` keeps the notes that say it (with the
  line), and New Note starts one with it; `note milk` ⇥ goes straight there. `new note` works from the field. `n` opens your last note. Anywhere, from 3
  letters, a note with the words shows below the name matches. `:delete note milk` (to the Trash, asks first).
  Each is a text file (note.txt, and the ones in `notes/`, named by when they were made), with its own place on
  screen. `add note` adds a line to note.txt.
- **Markdown in notes** (`[notes] markdown`, on by default): headings, bold, italic, code, lists, quotes and links are
  styled as you type, the syntax dimmed; `- [ ]` checkboxes tick with a click (⌘Z undoes it). The files stay plain
  text.
- **Clipboard history** (`clip`): text and images you copy, newest first under Today, Yesterday, Earlier,
  with a preview and details. Typing filters (`image` lists images). Enter pastes into the app you were in.
  Tab on an item: what you can do with it (above). Its own `:` commands: `:copy` (copy without pasting), `:delete`,
  `:clear` (asks first). Skips copies marked
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
  `1 hour 30` (a bare number is minutes), from a second to 24 hours; what follows is the label ("for" dropped). One
  at a time: a new one asks before replacing it. `timer` alone offers to stop it; `timer stop` too. Or until a time
  of day: `timer until 15:30 standup`, `timer at 3pm`.
- **Stopwatch** (`stopwatch`, from `stopw`): counts up in the menu bar, kept through restarts; stopping it says the
  time.
- **What's running, on opening:** the pomodoro, the timer, the stopwatch and keeping awake, while they run, are rows
  in the empty launcher, their time ticking in a copper pill (keeping awake's, when it's for a while); Enter stops one
  after asking. The meeting about to start stays
  first.

## Settings

**Settings…** in the menu bar, or `copperlight settings` in the launcher. A pane per group: General (hotkey, Open at
Login, currency, translate to, notes, weather, pomodoro), Launcher (what the empty launcher shows, what it learns and
Forget, answer cards), Features (a switch for each), Keywords (your own words for each keyword), Clipboard (how much to keep, apps not recorded), Files (folders
searched, names hidden, app descriptions online or not),
Browser (where links open, which profile), Commands and Snippets (add, edit, delete), and About (version, license,
and the open source it's built with). Every change goes straight into config.toml, editing only its own lines, comments kept;
one it can't make cleanly is refused, and the file stays as it was. Edits made by hand show up in the window.

## Menu bar

The C, with Settings… (⌘,), Welcome to Copperlight, Launch at Login and Quit. A running pomodoro or timer adds its countdown next to it,
and `:awake` a sun while it keeps the Mac awake (click either to stop it; for a while, its menu says until when). Keeping
awake ends when its time is up, or when Copperlight quits.

## Permissions

The welcome window (`welcome`) asks for Accessibility, Calendars, Reminders, Notifications and Photos in one place.
Otherwise macOS asks when a feature first needs one:

| macOS asks for | When | For |
|---|---|---|
| Accessibility | First paste or window command | Pasting (⌘V into your app), window commands and layouts, `:window`, `:lock`, menu search, `:play` and the track keys, opening on the selected text |
| Automation | First `:empty trash`, `:dark`, `:restart`, `:shut down`, `:log out`; a browser's row in `tabs` ⇥ | Asking Finder, System Events, loginwindow to do it; listing and switching a browser's tabs |
| Reminders | First `add todo`, or `due`'s Allow row | Adding reminders (no add-only option exists), and the ones that are due |
| Contacts | `contacts`, from its Allow row | Finding people as you type |
| Screen Recording | First `copy text` | Reading the part of the screen you drag over |
| Bluetooth | `:connect`, from its Allow row | Listing, connecting and disconnecting paired devices |
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
`note.txt`, `notes/` (the other notes), `state.json` (frecency, what you picked for what you typed, recent queries, saved layouts, the timer, the apps you opened and when, the colors you picked), `clipboard.sqlite` (history, readable only
by you), `rates.json` (currency rates), `apps.json` (what each app does) and `homebrew-apps.json` (Homebrew's list,
trimmed: names, descriptions, homepages), `photos.sqlite` (the text in your photos), `scripts/` (on the shell's PATH).

## Not here on purpose

An AI service or chat (app words come from the Mac's own model), a plugin store, sync, accounts, hotkeys for anything but the launcher, and prefix symbols besides `:`.
See SPEC.md.
