# Using Copperlight

Everything you can type, in detail. [What you can type](../README.md#what-you-can-type) in the README is the short
version; [FEATURES.md](../FEATURES.md) lists every feature on one page, and [configuration.md](configuration.md) covers
config.toml.

> **Switched off for now**, with their code kept: the text inside files and photos. They're described below but
> don't appear in the app yet.

| Key | Action |
|---|---|
| ⌥Space | Show / hide the launcher |
| ↑ ↓ | Move selection |
| Enter | Run: open app or file, copy a calculator, currency or text tool result, run command, open URL, search Google. Clipboard: paste the item |
| `:` (typed first) | Commands: the window in front, running apps, files, the Mac. Clipboard history has its own |
| Esc, or click elsewhere | Hide (or back out of a confirmation) |

The launcher is the only global hotkey, and the panel has no modifier keys: anything besides Enter is a
command you type after `:`. Everything else (note, clipboard history, pomodoro…) is found by typing.

Things to type: `saf`, `vsc`, `2^10 / 3`, `sqrt(2) * pi`, `20% of 150`, `255 in hex`, `25 usd to eur`, `12,50 gbp in brl`, `100jpy usd`,
`25 usd` (converts to `default_target`), `25 eur` (the default itself converts to USD), any command alias,
`note`, `note work`, `clip` (opens clipboard history), `pomo`, `pomo 50`, `pomo break`, `pomo stop`, `bluetooth`,
`dark mode`, `emoji party`, `define serendipity`, `translate bom dia`, `uuid`, `json`, `paste markdown`, `add`,
`add note buy milk`, `screenshot`, any file
name (`invoice`), text inside a file or a picture (`29.99`), an app by what it does (`draw`, `noise`), `f readme` (files only), `github.com/swiftlang` (opens it), anything at all (the last row
searches Google), `~/code/copperlight` or `/Applications` (lists the folder), `:` (every command), `:min`, `:quit saf`, `:window term`, `:!git status`. The selected row says what Enter does.

What you pick rises: every row you press Enter on (an app, a command, a file, a `:` command) ranks higher next
time, fading over a few weeks. So `s` + Enter opens Safari once you use it, and `:` lists your usual commands first.

**Commands (`:`):** `:` lists them all, and what you type after it narrows them down (`:min`, `:fq`).

| Command | Does |
|---|---|
| `:window term` | Switch to a window: every window of every app, front app first, by title or app name. Accessibility sees this Space's windows and minimized ones, not other Spaces' |
| `:minimize`, `:fullscreen`, `:close` | Minimize the window in front, toggle its fullscreen, or close it |
| `:maximize`, `:center`, `:left`, `:right`, `:top`, `:bottom` | Fill the screen, center it, or take a half |
| `:left third`, `:center third`, `:right third`, `:left two thirds`, `:right two thirds` | Thirds |
| `:next display` | Move it to the next screen, same place and share of the screen |
| `:restore` | Put it back where it was before Copperlight moved it (several moves in a row count as one) |
| `:quit saf`, `:force quit saf`, `:hide saf` | Quit, force quit (asks first) or hide a running app. Alone, they list every running app |
| `:hide others`, `:relaunch slack` | Hide every app but the one in front; quit an app and open it again |
| `:reveal readme`, `:copy path readme` | Reveal a file in Finder, or copy its path (file search, so from 2 letters). Given a path (`:copy path ~/code/copperlight/`), they list that folder |
| `:lock`, `:sleep`, `:sleep displays` | Lock the screen (sends ⌃⌘Q, so it needs Accessibility), sleep the Mac or only its displays |
| `:restart`, `:shut down`, `:empty trash` | Ask first, then do it. Apps with unsaved changes still get their say |
| `:dark`, `:hidden files` | Toggle dark mode; show or hide hidden files in Finder (Finder restarts) |
| `:volume 30`, `:eject` | Set the output volume (0–100, unmutes); eject a disk (lists external drives and disk images) |
| `:shortcut name` | Run one of your Shortcuts. That's also the way to Focus modes: make a Shortcut that sets one |
| `:!git status` | Run a shell line (below) |
| `:config` | Open config.toml |
| `:copy …`, `:delete …`, `:clear` (clipboard history) | Copy an item without pasting it, or delete it, or all of them (asks first). Deleting keeps the panel open, for several in a row |

The first time, macOS may ask to let Copperlight control the app that does the work: Finder (`:empty trash`), System
Events (`:dark`), loginwindow (`:restart`, `:shut down`). One Allow each; change it later under Privacy & Security
→ Automation.

Window commands act on the window you were in when you opened the launcher (it never takes focus), and need
Accessibility, like pasting (see Signing). Enter on a command that needs a target (`Quit Application`) fills in
its keyword (`:quit `) so you can type the app.

**Paths:** anything starting with `~` or `/` is a path. A folder that exists (`~/code/copperlight`, `/Applications`)
lists its contents, with the folder itself on top: Enter there opens it in Finder. Otherwise the last part
narrows the folder above it: `~/code/he` lists what in `~/code` matches "he". Enter on a folder goes into it
(types its path), and on a file or an app opens it. Hidden files show once the name starts with `.` (`~/.co`).
The first time you list Desktop, Documents or Downloads, macOS asks to let Copperlight read that folder.

**Shell (`:!`):** `:!git status` runs the line with `zsh -lc` in your home folder when you press Enter, never
while you type. Its output (stdout and stderr together, no colors) replaces the list, and Enter copies it; Esc goes
back to the line to edit or run it again. `:!` alone lists the lines you ran, most used first. A line is stopped
after 30 seconds. `~/.config/copperlight/scripts` is on its PATH. If you hide the launcher before the line finishes, a
notification shows how it ended. It's a login shell, not an interactive one: what `~/.zprofile` sets is there, but
aliases from `~/.zshrc` aren't.

**Text tools:** type a tool's name, then the text to work on (`upper hello`). With nothing after the name, it
works on the clipboard: copy some JSON, type `json`, Enter. Enter copies the result, and long results show in a
preview pane. Text after a name that the tool can't use (`hex f`) shows nothing, so other matches stay on top.
From 3 letters, the start of a name shows the tool too (`pas` → the paste tools).

| Type | Gives |
|---|---|
| `uuid`, `password`, `password 32`, `lorem`, `lorem 3` | A new UUID, a 20-character password (or 4–256), Lorem Ipsum paragraphs |
| `json`, `json min` | The JSON formatted (2 spaces) or minified, keys in their original order |
| `b64`, `b64 decode`, `url encode`, `url decode` | Encoded or decoded text (`b64 decode` takes URL-safe Base64 and missing padding too) |
| `upper`, `lower`, `snake`, `camel` | The text in that case, line by line (`fooBar baz` → `foo_bar_baz`) |
| `sort lines`, `count`, `sha256` | Lines in natural order (a9 before a10); words, characters and lines; the SHA-256 hash |
| `unix`, `unix 1700000000` | The time now as a timestamp; a timestamp (seconds or milliseconds) as a date |
| `hex #ff8800`, `hex 255 136 0` | The color in the other notation |
| `paste plain`, `paste markdown` | Pastes the clipboard into the app you were in: without its formatting, or as Markdown |

`paste markdown` converts anything copied with formatting (HTML or RTF: web pages, Google Docs, Slack, Word, TextEdit):
headings, bold, italic, links, lists, quotes, code and tables. Plain text pastes as it is. Pasting needs
Accessibility, like clipboard history; without it, Enter only copies. The pasted text stays on the clipboard.

**Capture:** `add` lists what you can add, and Enter on one types its name for you.

| Type | Does |
|---|---|
| `add note buy milk` | Adds the line at the end of the floating note, without opening it |
| `add todo call mom tomorrow 5pm` | A reminder in your default Reminders list, due (and alerting) at that time. No time typed: due that day. No date: no due date |
| `add event fri 10am dentist` | An event in your default calendar: an hour long, or the range you type (`10-11:30am`). A day without a time is all day |
| `screenshot`, `record` | The macOS screenshot toolbar (⌘⇧5), ready to capture or to record |

The row shows the title and date Copperlight read before you press Enter, and a notification confirms it. Dates are
read in English ("fri 10am", "tomorrow 5pm", "Oct 20 at 14:00", "next tuesday"). The first reminder asks for
Reminders access (macOS has no add-only option for reminders); the first event asks to add events only, so Copperlight
never reads your calendar. Google or Outlook calendars work when they're added in the Calendar app.

**Your own tools:** a `[[command]]` with the same name as a built-in replaces it, so `screenshot` can open
CleanShot and `add todo` can go to Things. Only the replacement shows. The text after the name reaches it as
typed (Copperlight reads dates only for its own Reminders and Calendar).

```toml
[[command]]
alias = "screenshot"
type = "url"
url = "cleanshot://capture-area"

[[command]]
alias = "add todo"
type = "url"
url = "things:///add?title={query}"
```

**Scripts:** every executable file in `~/.config/copperlight/scripts/` (created on first run) becomes a command,
found by its file name without the extension. Text after the name is passed as arguments, each word one
argument (`deploy staging`). It runs through `zsh -lc`, so it gets the PATH a terminal has, in your home
folder. Optional comment lines near the top, in any comment style (`#`, `//`, `--`):

```sh
#!/bin/sh
# @title Deploy App
# @icon hammer
# @output show
```

`@title` names the row, `@icon` is an SF Symbol, and `@output` says what happens to what it prints: `silent`
(the default: runs in the background, a failure posts a notification), `show` (shown in place of the list,
like `:!`; stopped after 30 seconds) or `copy` (stdout goes to the clipboard). A script named like a built-in
replaces it, like a command. The folder is also on the `:!` shell's PATH. Remember `chmod +x`.

**Snippets:** `[[snippet]]` entries ([configuration.md](configuration.md)) are found by name like commands. Enter pastes the text into the app
you were in, the same way the paste tools do (Accessibility; without it, Enter copies), and then puts your
clipboard back. Placeholders: `{date}` (`2026-10-13`), `{time}` (`16:55`), `{clipboard}`, and `{query}`, the text
typed after the name. A snippet without `{query}` only matches its name, so `sig more` finds nothing.

**Note:** type `n` (any start of "note") and it's the first result. Esc hides it again. It floats on a glass card
like the launcher's: drag it by its title, resize it from its bottom-right corner. `note work` opens a named note
(`notes/work.txt`), created when you first type in it; `note` lists the named ones too, and `note wo` finds them.
Each keeps its own place on screen. `add note` adds to the note.

**System Settings:** a page by name from 3 letters (`bluetooth`, `displays`, `keyboard`, `privacy`), or by
something on it (`dark mode`, `night shift`, `dock`, `default browser`, `login items`). Enter opens that page.

**Emoji:** `emoji party` lists emoji whose names have words starting with each word you typed, using the names of
the macOS emoji picker (flags and combinations too, English). Enter pastes it, like snippets.

**Define:** `define serendipity` shows the entry from the Mac's dictionaries (offline) in the preview pane; Enter
opens it in Dictionary.

**Translate:** `translate bom dia`, `translate good morning to spanish` (`to`, `in` or `into`, then a language's
English name or code). Apple's on-device translation (macOS 26): the source language is detected, and without a
target it goes to your first language in System Settings that isn't the text's. Enter copies it. Language pairs
download once, from System Settings → General → Language & Region → Translation Languages; until then the row
says so and opens that page.

**Clipboard history:** text and images you copy are recorded (polled twice a second). A copy with both, like
spreadsheet cells, is kept as text. Images (screenshots, "Copy Image") are stored as PNG, shown as a
thumbnail in the list and full size in the preview, with their size; type `image` to list only them. Copying something already in the
list moves it to the top. Typing filters: items containing the text, then items whose first line matches
fuzzily ("gco" → "git checkout origin"). Not recorded: copies marked concealed/transient/auto-generated
(password managers mark theirs), copies made while an `ignore_apps` app is in front, and the items you
paste from the list itself. Enter pastes into the app you were in, which needs Accessibility (see Signing).
Without it, Enter copies only and the panel shows a row that takes you to the setting.

**File search:** after 2 letters, files and folders in the `[files]` scopes whose name has a word starting with
what you typed (each word, any order of words: `inv 2026`). Uses the Spotlight index, so anything Spotlight
skips (System Settings → Spotlight → Privacy) is skipped too. Files always rank below apps, commands,
math and currency, and arrive a moment later (150 ms after you stop typing). Order: exact name, then name
starts with it, then a later word does; within that, most recently opened first, then the shallowest path.
Start with `f ` for files only, with up to 60 results instead of 20.

**Inside files and pictures:** from 3 letters, files in the same folders with the words in their text, below the
ones found by name ("Text inside", or "Text in image"). Spotlight reads documents, PDFs, and the text in images and
screenshots, in the background when the Mac is idle, so a picture saved minutes ago may not be found yet. The
preview shows the picture, or the lines with the words.

**Photos:** with Photos access (the welcome window asks), Copperlight reads the text in each photo of your library
once, on this Mac (Vision), newest first, then only new photos; Photos keeps its pictures out of Spotlight. A big
library takes a while the first time, and photos only in iCloud are downloaded at a medium size to be read. From
3 letters, photos with the typed text show with "Text in photo" and the photo in the preview; `29.99` finds 29,99
too. Enter opens a copy in Preview (Photos doesn't let other apps show one of its photos). Kept in `photos.sqlite`.

**Apps by what they do:** `draw` finds Affinity, `noise` Krisp, `docker` OrbStack, with the word that matched beside
the name. Copperlight keeps an index of each app, `apps.json`: its App Store category, publisher and the documents it
opens; online, Homebrew's one-line description and the app homepage's own summary, or the App Store's description for
apps installed from it; then, with Apple Intelligence on, words from the Mac's on-device model (what kind of app it
is, what people do with it, other words for it). New and updated apps are indexed in the background; the Mac limits
how often a background app may use the model, so the first run takes a few minutes. `[apps] online = false` keeps it
all on this Mac.

**Web:** text that looks like a URL (`github.com/x`, `https://…`, `localhost:3000`) gets an "Open" row.
A bare `name.tld` counts only for common TLDs (com, org, net, io, dev, app, co…), so file
names like `readme.md` don't. The last row is always "Search Google for …", so Enter on a query that matches
nothing searches the web.

**Units:** `10 km in mi`, `10km mi`, `100 f to c`, `2,5 kg`, `1 gb in mb`, `90 min in h`. Length, weight,
temperature, volume, speed, data (`kb`… decimal, `kib`… binary), time and area, by symbol or name (`km`, `miles`,
`°c`, `lbs`, `kmh`, `cups`, `floz`). With no target, metric and US units convert to each other (`30c` → °F, `5 lb`
→ kg). `10 in cm` and `10 in in cm` both work. Enter copies the number.

**Time zones:** `now in tokyo` (or `time in tokyo`), `3pm in sf` (3pm here), `15:30 lisbon in new york`, `noon utc
to sf`, also with `to`. A place is any time zone's city (`lisbon`, `new york`, `são paulo`), an alias (`sf`, `la`,
`nyc`, `india`, `china`, `uk`) or an abbreviation (`pst`, `utc`, `cet`). The row shows the time there, the day
and the difference in hours. Enter copies the time.

**Bookmarks and history:** from 2 letters, pages from your browser where each word you typed starts a word of
the title or the address (`copperlight git`; `30c` doesn't match inside "HP30138C"): up to 4 bookmarks, then the 4 most
recently visited, the same title on a site only once, ranked just above files. The browser is
`[browser] name`, else the default one; the profile is `[browser] profile`, else all of them (each row names its
profile and opens there). Chrome, Brave, Edge, Vivaldi and Chromium (bookmarks JSON, `History`) and Firefox
(`places.sqlite`) are read as they are; the history files are copied first, since the browser keeps them locked.
Safari's `Bookmarks.plist` and `History.db` need Full Disk Access for Copperlight (Privacy & Security). Arc isn't read.
Loaded in the background when the launcher opens, at most every 2 minutes; never written anywhere.

**Meetings:** `meetings` (from `mee`) lists the rest of today's events from Calendar, all-day ones aside, with
their times and how soon they start. Enter joins the video call it finds in the event's URL, location or notes
(Google Meet, Zoom, Teams, Webex), opening web links where `[browser]` says, or opens Calendar. The first time,
the row asks to read your calendars (full access; `add event` only asked to add).

**Pomodoro:** `pomo` starts `default_minutes`, `pomo 50` starts 50 minutes (1–240), `pomo break` starts
`break_minutes` of break (`pomo break 15` for another length; a cup in the menu bar), `pomo stop` stops. While
it runs, the menu bar shows the countdown; click it to stop. Nothing is shown when no timer runs. The end time
is saved, so the timer keeps going through sleep and app restarts (if it ended while the app was closed, you
get the notification on the next launch). When it ends: a notification with a sound. Starting a timer the first
time asks to allow notifications. Starting one while another runs asks before replacing it.
