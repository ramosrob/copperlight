# Using Copperlight

Everything you can type, in detail. [What you can type](../README.md#what-you-can-type) in the README is the short
version; [FEATURES.md](../FEATURES.md) lists every feature on one page, and [configuration.md](configuration.md) covers
config.toml.

> **Switched off for now**, with their code kept: the text inside files and photos. They're described below but
> don't appear in the app yet.

| Key | Action |
|---|---|
| ⌥Space | Show / hide the launcher. With text selected in the app you're in, it opens with that text typed and selected |
| ↑ ↓ | Move selection. ↑ in the empty field: the last query you ran (↑ again for the one before) |
| Enter | Run: open app or file, copy a calculator, currency or text tool result, run command, open URL, search the web. Clipboard: paste the item |
| Tab | Fill in: on a row that says Tab (Translate, Quit Application, a folder), or with a name typed whole (`translate`), it types the name, which becomes a chip. On a row that names what Tab does beside Enter, it steps into it: a person's Actions, a calculation's Keep Going, and on a file, an app or a clipboard item what you can do with it (Esc goes back). On a row with something to show (a note, a snippet), it opens its preview beside the list, and Tab again closes it. In clipboard history and in chips the preview is open already |
| `:` (typed first) | Commands: the window in front, running apps, files, the Mac. Clipboard history has its own |
| Esc, or click elsewhere | Hide (or back out of a confirmation) |

The launcher is the only global hotkey, and the panel has no modifier keys: anything besides Enter is a
command you type after `:`. Everything else (note, clipboard history, pomodoro…) is found by typing.

Things to type: `saf`, `vsc`, `2^10 / 3`, `sqrt(2) * pi`, `20% of 150`, `255 in hex`, `25 usd to eur`, `12,50 gbp in brl`, `100jpy usd`,
`25 usd` (converts to `default_target`), `25 eur` (the default itself converts to USD), `39*8 usd`, `20% off 80`,
`30 is what % of 150`, `10k * 3`, `days until dec 25`, `in 3 weeks`, `#c87533`, `pick color`, `qr`, `copy text`,
`large 555-0100`, `spell definately`, a person's name, an open tab's title, `due`, any command alias,
`note`, `note milk`, `clip` (opens clipboard history), `pomo`, `pomo 50`, `pomo break`, `pomo stop`, `timer 10 min tea`, `stopwatch`, `bluetooth`,
`dark mode`, `emoji party`, `define serendipity`, `translate bom dia`, `translate` (what you copied), `uuid`, `json`, `paste markdown`, `add`,
`add note buy milk`, `screenshot`, any file
name (`invoice`), text inside a file or a picture (`29.99`), an app by what it does (`draw`, `noise`), `f readme` (files only), `github.com/swiftlang` (opens it), anything at all (the last row
searches the web), `~/code/copperlight` or `/Applications` (lists the folder), `:` (every command), `:min`, `:quit saf`, `:window term`, `:!git status`. The selected row says what Enter does.

**Chips:** a name that takes text (`translate `, `define `, `spell `, `emoji `, `stock `, `qr `, `large `, `contact `, `tabs `, `pomo `, `timer `, `port `, `note `, `add todo `, `add event `, `add note `,
`:quit `, `:window `, `:output `, `:!`, `f `, `cpu `, `memory `, and your script filters' names) turns into a copper chip at the start of the field when you press Tab:
`tra` Tab is the Translate chip, and `stock aapl` Tab is the Stock chip with `aapl` after it. Typing never makes one,
so `stock apple` still finds `stock_Apple.pdf`. The field then holds what follows, with a hint while it's empty, and
only that feature answers, so there's no search row in the way. Delete in the empty field turns the chip back
into text.

What you pick rises: every row you press Enter on (an app, a command, a file, a `:` command) ranks higher next
time, fading over a few weeks. So `s` + Enter opens Safari once you use it, and `:` lists your usual commands first.

What you typed counts too: the row you picked for some text comes first the next time you type exactly that, above
everything else. Pick Slack with `ss` typed, and `ss` is Slack from then on: an abbreviation, with nothing to set up.
Case and spaces around it don't matter; text over 15 characters isn't kept. Picking another row for the same text
takes over, and an abbreviation you stop using fades after a few weeks.

**Commands (`:`):** `:` lists them all, and what you type after it narrows them down (`:min`, `:fq`).

| Command | Does |
|---|---|
| `:export pdf`, `:new tab` | Choose a menu item of the app you were in (below) |
| `:window term` | Switch to a window: every window of every app, front app first, by title or app name. Accessibility sees this Space's windows and minimized ones, not other Spaces' |
| `:minimize`, `:fullscreen`, `:close` | Minimize the window in front, toggle its fullscreen, or close it |
| `:maximize`, `:center`, `:left`, `:right`, `:top`, `:bottom` | Fill the screen, center it, or take a half |
| `:top left`, `:top right`, `:bottom left`, `:bottom right` | Quarters |
| `:left third`, `:center third`, `:right third`, `:left two thirds`, `:right two thirds` | Thirds |
| `:nudge left`, `:nudge right`, `:nudge up`, `:nudge down` | Move it a step (5% of the screen), staying on screen. The panel stays open: Enter again for another step |
| `:layout save work`, `:layout work`, `:layout delete work` | Save every window on screen under a name, put them all back, or forget it. `:layout` lists them (below) |
| `:next display` | Move it to the next screen, same place and share of the screen |
| `:restore` | Put it back where it was before Copperlight moved it (several moves in a row count as one) |
| `:quit saf`, `:force quit saf`, `:hide saf` | Quit, force quit (asks first) or hide a running app. Alone, they list every running app |
| `:hide others`, `:unhide all`, `:relaunch slack` | Hide every app but the one in front, or show them all again; quit an app and open it again |
| `:quit all`, `:quit others` | Quit every app, or every app but the one in front (both ask first; Finder stays) |
| `:reveal readme`, `:copy path readme` | Reveal a file in Finder, or copy its path (file search, so from 2 letters). Given a path (`:copy path ~/code/copperlight/`), they list that folder |
| `:lock`, `:sleep`, `:sleep displays` | Lock the screen (sends ⌃⌘Q, so it needs Accessibility), sleep the Mac or only its displays |
| `:restart`, `:shut down`, `:log out`, `:empty trash` | Ask first, then do it. Apps with unsaved changes still get their say |
| `:screen saver`, `:show desktop`, `:open trash` | Start the screen saver; hide every app to see the desktop (`:unhide all` undoes it); open the Trash |
| `:open with readme` | Open a file with another app: pick the file (Tab), then the app, its default app first (`:open with ~/x/readme.md code`) |
| `:trash readme`, `:terminal readme` | Move a file to the Trash (asks first), or open its folder (a folder itself) in your terminal: Terminal, or the app in Settings › Files › Terminal |
| `:dark`, `:wifi`, `:hidden files` | Dark mode and Wi-Fi on or off (the row says which: Turn Wi-Fi Off); show or hide hidden files in Finder (Finder restarts) |
| `:awake` | Keep the Mac and its displays awake until you run it again (Stop Keeping Awake) or Copperlight quits. A sun in the menu bar shows it's on; click it to stop |
| `:awake 2h`, `:awake 90 min`, `:awake until 18:00` | Keep it awake for a while, then let go by itself. Lengths and times read like `timer`'s (`30` is minutes, `till 6pm`); `:awake` alone also offers an hour or two. Run again, it keeps going until the new time. The time left ticks in the empty launcher, and the sun's menu says until when |
| `:play`, `:next track`, `:previous track` | The keyboard's media keys: play or pause, skip, go back, in whatever is playing (Music, a browser tab, Spotify). Needs Accessibility, like pasting |
| `:mute`, `:volume 30` | Mute or unmute (the row says which), set the output volume (0–100, unmutes). A display's speakers can't be muted from the Mac: a beep says so |
| `:mute mic` | Mute or unmute the microphone (Mute Microphone, Unmute Microphone). One without a mute control gets its input level set to 0, and back |
| `:output airpods` | Switch the sound output: lists speakers, headphones, displays and AirPlay, the current one first |
| `:eject` | Eject a disk (lists external drives and disk images) |
| `:shortcut name` | Run one of your Shortcuts. That's also the way to Focus modes: make a Shortcut that sets one. Text after the name (`:shortcut log water 500 ml`) is its input, as a text file |
| `:!git status` | Run a shell line (below) |
| `:config` | Open config.toml |
| `:copy …`, `:delete …`, `:clear` (clipboard history) | Copy an item without pasting it, or delete it, or all of them (asks first). Deleting keeps the panel open, for several in a row |

The first time, macOS may ask to let Copperlight control the app that does the work: Finder (`:empty trash`), System
Events (`:dark`), loginwindow (`:restart`, `:shut down`). One Allow each; change it later under Privacy & Security
→ Automation.

Window commands act on the window you were in when you opened the launcher (it never takes focus), and need
Accessibility, like pasting (see Signing). Enter on a command that needs a target (`Quit Application`) fills in
its keyword (`:quit `) so you can type the app.

**Layouts:** `:layout save work` keeps the windows on screen now, app by app: those of hidden apps, minimized and
full-screen ones stay out. `:layout work` puts each back, matching an app's windows by title first, then in order,
and unminimizing them. A screen that's gone since gets its windows on the main screen, at the same share. Apps that
aren't open are named in a notification: open them and run it again. Layouts live in `state.json`, not config.toml,
because their frames belong to this Mac's screens.

**Menus:** what you type after `:` also finds the menu items of the app you were in, from 3 letters, below the
commands: `:export pdf` in Pages, `:new tab` in a browser, `:show sidebar` in Finder. Each row says where the item is
(Pages › File › Export To) and shows its shortcut, so you learn it as you go; Enter chooses it, like clicking it. Only
items you could click right now are listed, and not the Apple menu or Services. It reads the menus through
Accessibility; without it, a row at the bottom offers to open the setting.

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

Community script commands work as they are: drop one in the folder and its own headers are read too. Its title
names the row, a `fullOutput` or `inline` mode shows the output (`silent` and `compact` run in the background), an
icon that's an SF Symbol name is its icon (an emoji or image isn't, so it gets the default), its description is the
row's subtitle, and `needsConfirmation true` asks before it runs. A script that declares its arguments
(`argument1`…) gets that many, the last one holding the rest of what you typed, so `ask will it ship` passes "will
it ship" whole. Where a script sets both, `@title`, `@icon` and `@output` win.

**Script filters:** a script with `@output rows` lists what it prints, and Enter acts on the row you pick. Its name
is a chip (`links` ⇥); as you type after it, the script runs with that text as its one argument, once typing pauses,
and its rows replace the list (`links docs` typed whole does the same). Each line it prints is a row: its title, then,
after tabs, a subtitle and the value Enter uses (the title without one). Enter opens a value that's a file or folder
(`/…`, `~/…`) or a link an app takes (`https://…`, `obsidian://…`), and copies anything else. Up to 100 rows, in the
order printed; a failure says so in a row.

```sh
#!/bin/sh
# @title Team Links
# @output rows
printf 'Docs\tThe handbook\thttps://example.com/docs\n'
printf 'Wiki\t\thttps://example.com/wiki\n'
printf 'On-call: %s\n' "$1"
```

**Colors:** a color typed as `#c87533`, `#f80`, `rgb(200, 117, 51)` or `hsl(27, 59%, 49%)` (spaces for commas
too) shows in the other two notations, each row with the color's swatch, the one you typed last. Tab shows it big.
Enter copies it. `pick color` (also `color picker`, `eyedropper`) opens macOS's magnifier: click anywhere on any
screen and its hex is copied, and the launcher comes back with that color typed, so the other notations are a row
away. Esc cancels. Colors are sRGB, what hex codes mean on the web. Every color you pick is kept (the last 30, in
`state.json`): `colors` (or `my colors`) lists them, newest first, each with its swatch and when you picked it. Enter
copies its hex; Tab shows it big, in hex, RGB and HSL.

**QR codes:** `qr https://copperlight.app` offers the code (Tab or Enter), and in the QR Code chip it shows beside the
list as you type. `qr` alone makes one of what you copied. Enter copies the picture (PNG). Made on your Mac; up to
about 2,000 characters.

**Text from the screen:** `copy text` (also `ocr`, `scan text`, `grab text`) turns the pointer into the screenshot
crosshair: drag over any part of any screen (a video, a picture, a locked PDF, an error you can't select) and its
text is copied, line by line, read by the Mac's own text recognition. Esc cancels. If there's a QR code or a barcode,
what it says is copied instead, and a link in it comes back in the launcher, so Enter opens it. Taking the picture
needs the Screen Recording permission (Privacy & Security), asked for the first time; only the part you drag over
is read, and nothing is kept.

**Large Type:** `large 555-0100` (also `big text`) shows the text across the screen, as big as it fits, to show
someone across the desk; `large` alone shows what you copied. Any key, a click or switching apps puts it away.

**Snippets:** `[[snippet]]` entries ([configuration.md](configuration.md)) are found by name like commands. Enter pastes the text into the app
you were in, the same way the paste tools do (Accessibility; without it, Enter copies), and then puts your
clipboard back. Placeholders: `{date}` (`2026-10-13`), `{time}` (`16:55`), `{clipboard}`, and `{query}`, the text
typed after the name. A snippet without `{query}` only matches its name, so `sig more` finds nothing. `{cursor}` is
where the cursor ends up: after the paste, Copperlight presses ← that many times (the first `{cursor}`, if there are
more).

**Note:** type `n` (any start of "note") and it's the first result: your last note. Esc hides it again. It floats on a
glass card like the launcher's: drag it by its title, resize it from its bottom-right corner. Each note keeps its own
place on screen. `add note` adds a line to note.txt.

**Your notes:** they have no names. A note's first line is its title, on its card and in the list (a heading's `#`s
left out). The list has every note, the last edited first, each with the line after its title and how long ago it
changed; the selected one's text shows beside the list. New Note comes last: Enter opens an empty one, saved once you
type. The list is the Notes chip: `note` shows your last note and Notes, and Tab on it (or Enter) turns it into the chip,
with only your notes, no apps or search row. Typed in the chip, `milk` keeps the notes with "milk" in them (with the
line), and New Note then starts one with "milk" on its first line; `note milk` ⇥ goes straight there. `new note` works
from the field too. Anywhere else, from 3 letters, a note with the words you typed shows below what matches by name.
`:delete note milk` moves one to the Trash, after asking. Notes are text files: note.txt, and the ones in `notes/`.

**Markdown in notes:** as you type, `# headings` (to `###`), `**bold**`, `*italic*`, `` `code` ``, lists, `> quotes`
and links (`[text](url)`, or a bare `https://…`) show styled, the syntax dimmed beside them. `- [ ]` is a checkbox:
click it to tick it (`- [x]`, struck through), and ⌘Z to undo. A click on a link opens it. Only the look changes:
the file stays plain text. Settings › General › Notes turns it off (`[notes] markdown`).

**System Settings:** a page by name from 3 letters (`bluetooth`, `displays`, `keyboard`, `privacy`), or by
something on it (`dark mode`, `night shift`, `dock`, `default browser`, `login items`). Enter opens that page.

**Emoji:** `emoji party` lists emoji whose names have words starting with each word you typed, using the names of
the macOS emoji picker (flags and combinations too, English). Enter pastes it, like snippets.

**Define:** `define serendipity` shows the entry from the Mac's dictionaries (offline) in the preview pane; Enter
opens it in Dictionary.

**Spell:** `spell definately` gives the word spelled right and the other guesses, the best first; `spell` with a
sentence gives it back with each misspelled word corrected. A word that's right says so. Enter copies it. It's the
Mac's own spelling, in the languages System Settings › Keyboard › Text Input has for it.

**Translate:** `translate bom dia`, `translate good morning to spanish` (`to`, `in` or `into`, then a language's
English name or code). Apple's on-device translation (macOS 26): the source language is detected, and without a
target it goes to the language in Settings › General › Translate to (`[translate] default_target`), or, set to
Automatic or when the text is already in it, to your first language in System Settings that isn't the text's. With no text, `translate` (or
`translate to spanish`) translates what's on the clipboard: copy, ⌥Space, `translate`, Enter. The language joins the
chip (Translate to German) when you press Tab with it first (`to ger` ⇥) or at the end of the text
(`hello world to ger` ⇥); the field then holds only the text, and Delete takes the language back out. Enter copies it. Language pairs
download once, from System Settings → General → Language & Region → Translation Languages; until then the row
says so and opens that page.

**Clipboard history:** text and images you copy are recorded (polled twice a second). A copy with both, like
spreadsheet cells, is kept as text. Images (screenshots, "Copy Image") are stored as PNG, shown as a
thumbnail in the list and full size in the preview, with their size; type `image` to list only them. Copying something already in the
list moves it to the top. Typing filters: items containing the text, then items whose first line matches
fuzzily ("gco" → "git checkout origin"). Not recorded: copies marked concealed/transient/auto-generated
(password managers mark theirs), copies made while an `ignore_apps` app is in front, and the items you
paste from the list itself. Enter pastes into the app you were in, which needs Accessibility (see Signing).
Without it, Enter copies only and the panel shows a row that takes you to the setting. Tab on an item shows what
else you can do with it: open a link, Large Type, a QR code, save a picture, delete it.

**File search:** after 2 letters, files and folders in the `[files]` scopes whose name has a word starting with
what you typed (each word, any order of words: `inv 2026`). Uses the Spotlight index, so anything Spotlight
skips (System Settings → Spotlight → Privacy) is skipped too. Files always rank below apps, commands,
math and currency, and arrive a moment later (150 ms after you stop typing). Order: exact name, then name
starts with it, then a later word does; within that, most recently opened first, then the shallowest path.
Start with `f ` for files only, with up to 60 results instead of 20.

**What you can do with it (Tab):** on a file, an app or a clipboard item, Tab puts what you can do with it in place
of the list, under its name, with its preview beside it. Esc goes back to the list, the item still selected; typing
searches again. A file (in a search, or a folder's listing): Open (the row says in which app), Open With… (fills in
`:open with`, to pick the app), Reveal in Finder, Copy Path, Copy File (the file itself, to paste in Finder, an email
or a chat), Open in Terminal (its folder, in `[files] terminal`), Move to Trash (asks first); beside them a text
file's start, a picture or a PDF's first page, and where it is, its kind, size and when it changed. An app: its recent
documents first, then Open, and while it runs Hide, Quit, Force Quit (asks first) and Relaunch; Reveal in Finder, Copy
Path; beside them its icon, version and where it is. Its recent documents are the files in your home folder of the
kinds the Mac opens in it (TextEdit: text and Word files; Preview: pictures and PDFs, unless they open elsewhere), the
most recently opened first, five at most, from Spotlight: each says how long ago, its preview beside it, and Enter
opens it in that app. The app's own Open Recent list is kept where macOS lets in only apps with Full Disk Access, which
Copperlight doesn't ask for; an app's own files in `~/Library` are left out, but not your cloud drives there. A clipboard item: Paste (Copy, without Accessibility), Copy Without Pasting; for text, Open
Link if it's a web address, Large Type, and QR Code, the code beside the list (Enter copies the picture); for a
picture, Open in Preview and Save to Downloads; and Delete from History.

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

**Installing an app:** with Homebrew installed, typing an app you don't have (`figma`, from 3 letters, when it isn't
the start of an app you have) offers Install Figma, with Homebrew's description, below everything else; two at most,
the closest name first. Enter runs `brew install --cask figma` with its output beside the row; Enter again hides the
launcher and lets it finish, and a notification says how it ended. Once it's installed, Enter opens it. An app that
needs your password to install (a .pkg) can't ask for it in the launcher: the row says so, and Enter copies the
command to paste in a terminal. The list is Homebrew's, the one app search already downloads, so `[apps] online =
false` turns this off too.

**Web:** text that looks like a URL (`github.com/x`, `https://…`, `localhost:3000`) gets an "Open" row.
A bare `name.tld` counts only for common TLDs (com, org, net, io, dev, app, co…), so file
names like `readme.md` don't. The last row is always "Search Google for …", so Enter on a query that matches
nothing searches the web. Settings › Browser › Search engine picks another: DuckDuckGo, Bing, Brave Search,
Ecosia or Kagi.

**Units:** `10 km in mi`, `10km mi`, `100 f to c`, `2,5 kg`, `1 gb in mb`, `90 min in h`. Length, weight,
temperature, volume, speed, data (`kb`… decimal, `kib`… binary), time and area, by symbol or name (`km`, `miles`,
`°c`, `lbs`, `kmh`, `cups`, `floz`). With no target, metric and US units convert to each other (`30c` → °F, `5 lb`
→ kg). `10 in cm` and `10 in in cm` both work. Enter copies the number.

**Time zones:** `now in tokyo` (or `time in tokyo`), `3pm in sf` (3pm here), `15:30 lisbon in new york`, `noon utc
to sf`, also with `to`. A place is any time zone's city (`lisbon`, `new york`, `são paulo`), an alias (`sf`, `la`,
`nyc`, `india`, `china`, `uk`) or an abbreviation (`pst`, `utc`, `cet`). The row shows the time there, the day
and the difference in hours. Enter copies the time.

**Dates:** `days until dec 25` (or `how many days until christmas?`), `weeks until dec 25` (8 weeks, 2 days), `days
since jan 1`; `in 3 weeks`, `3 weeks from now`, `100 days from today`, `3 days ago`, `in 2 months`, `30 days after dec
25`, `2 weeks before dec 25`, `dec 25 + 2 weeks`, `monday in 3 weeks` (the Monday of that week); `time in 4 hours`, `in
90 minutes`. A date alone shows its weekday, how far it is and its week number (as your Mac's calendar counts them):
`dec 25`, `25 december 2027`, `2026-12-25`, `tomorrow`, `next friday` (the one after this week's, as macOS reads it),
`last friday`, `christmas`, `new year`. Without a year it's the next one, or the last one after `since`. A weekday's
name alone ranks low, under an app with that name. While you type, `in 3` answers in 3 days, weeks, months and hours,
`3 weeks` from now and ago, each with its phrase at the right edge, and `days` or `weeks` offers until or since a
date: Tab, then the date. Enter copies the answer.

**Stocks:** `stock AAPL`, `stock MGLU3.SA`, `stock ^BVSP`, `stock BTC-USD` (`sto` ⇥ for the Stock chip; tickers as
Yahoo Finance writes them). The row shows the price and today's change; beside it, the last 7 days drawn hourly, the
change over them, the previous close, the exchange and when it last traded. Enter opens the stock on Yahoo Finance.
It says what you asked for, so it waits for you: only in the Stock chip, and only once you
pause typing, does the ticker go to Yahoo; the answer is kept for a minute. Typed without the chip, `stock aapl` asks
nothing: below the files, a row offers it (Stock Price of AAPL), and Tab or Enter on it makes the chip.

**Lookups:** `ip` lists each interface's IPv4 address (Wi-Fi, Ethernet; Enter copies it) and a Public IP row that
asks api.ipify.org only when you press Enter on it. `battery` (from `batt`) shows the charge and what it's doing
("87%, charging, 1:05 to full"), its health and cycle count; Enter opens Battery settings. `disk` shows free space on
each disk mounted, as Finder counts it; Enter opens Storage settings. `port` (`por` ⇥ for the Port chip) lists your
processes listening on TCP ports, `port 3000` (or `port 30`, `port node`) narrows them, and Enter ends one, after
asking. Another user's processes aren't listed.

**Processes:** `cpu` lists your 8 busiest processes by recent CPU use, `memory` (from `mem`, or `ram`) by memory, each
with its CPU, memory and pid, and the icon of the app it belongs to: a Chrome Helper shows Chrome's. `cpu chrome`
narrows them by name; `cpu` ⇥ or `memory` ⇥, the chip, lists every one. Enter ends a process after asking, the way
`kill` does (SIGTERM); on an app itself (not a helper inside it) it quits the app instead, so it can ask to save.
`kill process` and `processes` find it too. Copperlight and another user's processes aren't listed.

**Speed test:** `speed` (also `speedtest`, `internet speed`) offers Test Internet Speed. Enter runs macOS's own
`networkQuality`, which measures your connection against Apple's servers for about 20 seconds, the time so far ticking
on the row; Esc stops it. Then the row says the download and upload speed ("322 Mbps down · 243 Mbps up"), the
latency when the line is idle and when it's busy (what calls and games feel), and whether it's Wi-Fi, Ethernet or
cellular. Enter copies it. Typing `speed` sends nothing.

**Bookmarks and history:** from 2 letters, pages from your browser where each word you typed starts a word of
the title or the address (`copperlight git`; `30c` doesn't match inside "HP30138C"): up to 4 bookmarks, then the 4 most
recently visited, the same title on a site only once, ranked just above files. The browser is
`[browser] name`, else the default one; the profile is `[browser] profile`, else all of them (each row names its
profile and opens there). Chrome, Brave, Edge, Vivaldi and Chromium (bookmarks JSON, `History`) and Firefox
(`places.sqlite`) are read as they are; the history files are copied first, since the browser keeps them locked.
Safari's `Bookmarks.plist` and `History.db` need Full Disk Access for Copperlight (Privacy & Security). Arc isn't read.
Loaded in the background when the launcher opens, at most every 2 minutes; never written anywhere.

**Browser tabs:** typing finds the tabs open in your browsers, like bookmarks: every word you typed starts a word of
the title or the address, from 2 letters, up to 4 tabs, ranked just above bookmarks. Enter switches to the tab, its
window coming forward, instead of opening the page again. `tabs` ⇥ is the Tabs chip: every open tab, in window order,
and typing narrows them. Chrome, Brave, Edge, Vivaldi, Chromium, Arc and Safari, whichever are running; private
windows aren't listed, and Firefox can't say what tabs it has. Copperlight asks each browser through AppleScript,
which needs your OK once per browser: the Tabs chip has a row that asks (System Settings › Privacy & Security ›
Automation, if you said no). Read when the launcher opens, kept in memory only.

**Contacts:** from 2 letters, the people in your contacts where each word you typed starts a word of their name,
nickname or company. The row shows their number and email; Enter messages them in Messages (their mobile number,
else their first number, else their email), or opens their card if they have neither. Tab goes into the person, the
Contact chip: Message, Call (through your iPhone), FaceTime and WhatsApp (when it's installed) for each number, Email
for each address, Copy for each, and Open in Contacts, with their card beside the list (numbers, emails, birthday).
`contact` ⇥ alone lists everyone. The first time, `contacts` (below the Contacts app) has a row that asks to read
them. Read on your Mac when the launcher opens, at most every 2 minutes, kept in memory only.

**Meetings:** `meetings` (from `mee`), `agenda` (from `age`) or `events` list the rest of today's events from
Calendar, all-day ones aside, with their times and how soon they start; `calendar` typed whole too, below the
Calendar app. One that starts within the hour, or is going, has a copper badge ("in 17 min", "Now"). Tab shows its
details beside the list: its day, times and notes, its calendar, place, call and link, who's coming and who asked.
Enter joins the video call it finds in the event's URL, location or notes (Google Meet, Zoom, Teams, Webex), opening
web links where `[browser]` says, or opens Calendar. The first time, the row asks to read your calendars (full
access; `add event` only asked to add).

**The next meeting:** a few minutes before a meeting with a call, there's no need to type: from 10 minutes before it
starts until 10 minutes after, the empty launcher shows that meeting with its badge, and Enter joins. Settings ›
General › Calendar › Show today's events when the launcher opens (`[meetings] show_on_open`) lists the day's next
five events there instead, with or without a call. Either only once Calendars access is given; opening the launcher
never asks. Typing hides it.

**Due reminders:** the empty launcher lists the reminders that are overdue, due within the hour, or due today with no
time, the soonest deadline first, each with a copper badge ("Overdue", "in 20 min", "Today") and its list. Enter
completes one and keeps the launcher open, so you can tick off the next. `due` (or `overdue`, `todos`) lists all of
today's and the overdue ones. Reading them needs full Reminders access, which `add todo` asks for, or the row `due`
shows the first time; opening the launcher never asks.

**Pomodoro:** `pomo` starts `default_minutes`, `pomo 50` starts 50 minutes (1–240), `pomo break` starts
`break_minutes` of break (`pomo break 15` for another length; a cup in the menu bar), `pomo stop` stops. While it
runs, the menu bar shows the countdown; click it to stop. Nothing is shown when no timer runs. The end time is
saved, so the timer keeps going through sleep and app restarts (if it ended while the app was closed, you get the
notification on the next launch). When it ends: a notification with a sound. Starting a timer the first time asks to
allow notifications. While one runs, `pomo` offers to stop it, its time left ticking, and a break (or, during a
break, a pomodoro), not another of the same; `pomo 50` replaces it, after asking.

**Timer:** `timer 10 min tea` counts down 10 minutes for tea, beside the pomodoro and like it: an hourglass and the
time left in the menu bar (click it to stop), kept through sleep and restarts, and a notification with a sound when
it's done ("Timer done", tea · 10 minutes). The length comes first: `10` (minutes), `10 min`, `90s`, `1h30m`,
`1 hour 30`, from one second to 24 hours; whatever follows is what it's for (`for` dropped:
`timer 20m for the laundry`). One runs at a time; starting another asks before replacing it. `timer` alone offers to
stop the one running, and so does `timer stop`. `tim` Tab is the Timer chip. A time of day works too:
`timer until 15:30 standup`, `timer at 3pm` (tomorrow's, if it's gone today).

**Stopwatch:** `stopwatch` (from `stopw`) starts one, counting up in the menu bar and kept through restarts;
`stopwatch` again, or a click on it in the menu bar, stops it and says the time in a notification.

**What's running, when you open it:** while a pomodoro, a break, a timer or the stopwatch runs, or the Mac is kept
awake, the empty launcher lists it with its time ticking in a copper pill: left for the pomodoro, the timer and keeping
awake for a while, so far for the stopwatch.
Enter stops it, after asking. A meeting about to start stays above them, so Enter still joins.

**Suggestions:** below all that, the empty launcher shows up to 3 apps you open around this time of day: opened from
the launcher within an hour of now on 3 days or more of the last 4 weeks, the most often first (a recent day counts
more). The app you're in isn't one of them. Learned from what you open with Copperlight, kept in `state.json`;
Settings › Files › Apps › Suggest apps when the launcher opens (`[apps] suggestions`) turns it off.
