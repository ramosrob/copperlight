# Roadmap

What's planned for Copperlight, roughly in order. There are no dates: things ship when they're ready.
[SPEC.md](SPEC.md) decides what fits: a small core, keyboard only, one hotkey, plain-text config, nothing about
you leaves your Mac. Ideas are welcome: [open an issue](https://github.com/ramosrob/copperlight/issues).

## Next

- **Better placeholders:** dates with a format and an offset (`{date +7d}`), and `{clipboard}`, `{selection}` and
  `{date}` inside url and shell commands.
- **Your own fallback rows:** choose what the last rows offer when nothing matches: several search engines, or any of
  your commands.

## 1.0

1.0 means it updates itself, your settings won't break under you, and it works for everyone, in their language and
with VoiceOver.

- **Updates:** tell you when a new version is out, and install it, checking that it's really Copperlight first.
- **Settings for everything:** turn any feature on or off, rename its keyword (even the `:` prefix), and set its
  options, in Settings and in config.toml. Off means off: no rows, no background work, no network, no permission
  asks.
- **Settings that last:** every config.toml key and the saved state settled before 1.0; after it, old keys keep
  working.
- **Other languages:** the whole interface, rows, Settings and docs in other languages; what you type stays as it is.
- **VoiceOver:** every row, chip and answer card read out properly.
- **A privacy page:** every permission Copperlight can ask for, what each one turns on, and every server it ever
  contacts.
- **Sturdier:** with permissions refused, on several screens, in other number and date formats, on Intel, and after
  weeks of clipboard history; Copy Diagnostics in About, for reporting a problem without crash reports.
- **If it's ready:** `brew install` through Copperlight's own tap.

Roughly in that order, then a few weeks of daily use with fixes only.

## Later

- **Calculating:** `2rem in px`.
- **Finding:** `:look` for a full-size preview; kinds, dates and tags in the files chip (`f pdf invoice`, `f last
  week`); folders listed newest first; symbols by name (→, ⌘, ™) and a default emoji skin tone; songs, albums and
  playlists from your Music library; Safari's Reading List and iCloud Tabs; recent files; the text inside files back, as its own
  chip.
- **Clipboard:** pin items; copied files; copied images found by their text, and QR codes read from them; `:plain` and
  `:clear 15 min` in clipboard history; save an item as a snippet; paste in sequence, one older item each time.
- **Text:** more placeholders (`{uuid}`, `{clipboard 1}`, a snippet inside another) with modifiers (`|upper`), and
  several named arguments; Markdown snippets pasted as rich text; title, kebab and sentence case, random numbers, and
  the links pulled out of text.
- **Windows:** sixths, fourths, the full height or width, `:size 1280x800`, gaps between windows; layouts that open
  their apps too.
- **Files and apps:** `:move to`, `:rename`, `:duplicate`, `:compress`, AirDrop and `:info` on a file; the files selected in
  Finder as what the hotkey acts on; `:uninstall` (asks first); `:upgrade`; volume per app.
- **Sports and flights:** scores and the next games of your teams; a flight's status from its number.
- **Your day:** meetings beyond today, free slots to copy, and the next meeting in the menu bar; lists, priorities and
  places in `add todo` and `add event`; what's playing in the empty launcher; screenshots and downloads by date, and
  pasting the latest.
- **The Mac:** `:input` for the microphone; the Wi-Fi password, and a QR code for guests; Stage Manager on and off; dismiss notifications.
- **Extending it:** script rows with live output and a choice of arguments; `copperlight choose`, lines from a
  pipe as rows; a URL scheme and Shortcuts actions; a
  starter library of commands, and importers for snippets and quicklinks from other apps.
- **Look and feel:** themes and custom colors; text size, and which screen it opens on; switching the keyboard layout from the field; a double-tapped modifier as the hotkey (still one hotkey).
- **Usage stats**, kept on your Mac.

## Done

- **v0.11:** answers in their own shape: a stock across the whole card, a QR code big beside what you can do
  with it (copy, save to Downloads, copy the link), a color on a band with its contrast, a step lighter and darker;
  the speed test, download and upload climbing big as they're measured; a dictionary entry across the card; a person's card beside every
  way to reach them; a calculation on a band, what you typed = the answer, with what a percentage hid; a currency
  conversion on a band, the two flags faintly behind it; the meeting to join on a band, who's coming and a line of
  its notes; the weather, now, the next hours and five days, where you are or in any city. Live currency rates, every
  5 minutes, and crypto in conversions (`0.1 btc in eur`).
- **v0.10:** what you picked for what you typed comes first the next time you type it (`ss` → Slack); Tab on a
  file, an app or a clipboard item for what you can do with it (open with, reveal, copy the path or the file, trash;
  an app's recent documents, hide, quit, relaunch; open a link, Large Type, a QR code), its preview beside it; `speed`, an internet speed test; `:awake 2h`, `:awake until 18:00`; `colors`, the colors you picked; installing an app you don't have
  with Homebrew, from its row; `:connect airpods`, your paired Bluetooth devices.
- **v0.9:** colors by their shape (`#c87533`, `rgb(…)`, `hsl(…)`) with a swatch, and `pick color`; `qr`
  codes; date math (`days until dec 25`, `in 3 weeks`, a date's weekday and week), answered before you finish typing;
  `{cursor}` in snippets; currency after math (`39*8 usd`); contacts (Enter messages, Tab for call, FaceTime, WhatsApp,
  email, copy); open browser tabs, Enter switching to one; `copy text` from any part of the screen, and the link in a
  QR code there; `spell`; reminders that are due, and the apps you open around this time, waiting in the empty
  launcher; Large Type; `20% off 80`, `30 is what % of 150`, `10k * 3`, and Tab to keep going with a result; script
  filters (`@output rows`); `cpu` and `memory`, your processes the busiest first, Enter ending one.
- **v0.8:** `timer until 15:30`; a stopwatch; what's running (the pomodoro, the timer, the stopwatch) waiting
  in the empty launcher, its time ticking.
- **v0.7:** the preview opens with Tab in the general search, so the list keeps its width; the next meeting, waiting
  in the empty launcher from 10 minutes before it starts (Enter joins), or all of today's events with a setting;
  `agenda` and `events` too, a copper badge on what's within the hour, and Tab for an event's details; notes you
  browse (`note` ⇥: the Notes chip, every note, last edited first, with a preview; typing finds the one that says it,
  and so does typing `milk` anywhere), titled by their first line, `:delete note`, and Markdown styled as you type,
  with checkboxes you click; `:open with`, `:trash` and `:terminal` (Terminal, or the app you pick) on files and
  folders; text after `:shortcut name` is its input; `:quit all`, `:quit others`, `:unhide all`, `:log out`, `:screen
  saver`, `:show desktop`, `:open trash` and `:mute mic`.
- **v0.6:** opens with the text you selected; ↑ for what you ran before; `ip`, `battery`, `disk` and `port 3000`;
  window quarters, `:nudge`, and saved layouts (`:layout save work`, `:layout work`); a search engine to choose, with
  its logo; System Settings opens once per launch when Accessibility is off.
- **v0.5:** Settings › General › Translate to; text in a language that isn't one of your Mac's is read right.
- **v0.4:** timers (`timer 10 min tea`), counting down in the menu bar beside the pomodoro.
- **v0.3:** music and sound from the field (`:play`, `:next track`, `:mute`, `:output airpods`); `:wifi` and `:awake`,
  whose rows say what Enter does; `translate` alone translates what you copied; a name that takes text turns into a
  chip in the field, with Tab (`tra` ⇥ is the Translate chip). What's playing has no public macOS API for apps, and
  Bluetooth can't be switched on or off without one, so `bluetooth` stays its System Settings page. `stock AAPL`: the
  price, today's change and a 7-day chart, from Yahoo Finance, only when you ask.
- **v0.2:** search the menus of the app you're in (`:export pdf`); System Settings pages as rows (`bluetooth`, `dark
  mode`); community script commands work as they are.

## Maybe, someday

What macOS already does well today, so not soon: the contents of Mail, Messages and Notes (Spotlight searches them),
a grid of every app (Spotlight's Apps view), password manager items (their own quick access), resizing and converting
images (Finder's Quick Actions), dictation, blocking apps and sites (Screen Time and Focus), quitting idle apps (App
Nap), switching Spaces (⌃1–9) and an app's windows (⌘`), answering invitations (Calendar), speaking text (a two-line
`say` script), and hiding the menu bar icon (System Settings › Menu Bar).
