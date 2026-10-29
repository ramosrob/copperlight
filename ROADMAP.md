# Roadmap

What's planned for Copperlight, roughly in order. There are no dates: things ship when they're ready.
[SPEC.md](SPEC.md) decides what fits: a small core, keyboard only, one hotkey, plain-text config, nothing about
you leaves your Mac. Ideas are welcome: [open an issue](https://github.com/ramosrob/copperlight/issues).

## Next

- **Better placeholders:** dates with a format and an offset (`{date +7d}`), and `{clipboard}`, `{selection}` and
  `{date}` inside url and shell commands.
- **Your own fallback rows:** choose what the last rows offer when nothing matches: several search engines, or any of
  your commands.
- **Updates,** for 1.0: tell you when a new version is out, and install it.

## Later

- **Calculating:** `2rem in px`; crypto in conversions (`0.1 btc in eur`).
- **Finding:** `:look` for a full-size preview; kinds, dates and tags in the files chip (`f pdf invoice`, `f last
  week`); folders listed newest first; symbols by name (→, ⌘, ™) and a default emoji skin tone; songs, albums and
  playlists from your Music library; Safari's Reading List and iCloud Tabs; recent files, and an app's recent documents
  a Tab away from its row; what you picked for an abbreviation first the next time you type it (`ss` → Slack); the
  text inside files back, as its own chip.
- **Clipboard:** pin items; copied files; copied images found by their text, and QR codes read from them; `:plain` and
  `:clear 15 min` in clipboard history; save an item as a snippet; paste in sequence, one older item each time.
- **Text:** more placeholders (`{uuid}`, `{clipboard 1}`, a snippet inside another) with modifiers (`|upper`), and
  several named arguments; Markdown snippets pasted as rich text; title, kebab and sentence case, random numbers, and
  the links pulled out of text; the colors you picked, kept (`colors`).
- **Windows:** sixths, fourths, the full height or width, `:size 1280x800`, gaps between windows; layouts that open
  their apps too.
- **Files and apps:** `:move to`, `:rename`, `:duplicate`, `:compress`, AirDrop and `:info` on a file; Tab on a file,
  an app or a clipboard item for its actions as rows (open with, reveal, copy path, trash); the files selected in
  Finder as what the hotkey acts on; `:uninstall` (asks first); installing an app you don't have with Homebrew, from
  its row, and `:upgrade`; volume per app.
- **Your day:** meetings beyond today, free slots to copy, and the next meeting in the menu bar; lists, priorities and
  places in `add todo` and `add event`; what's playing in the empty launcher; screenshots and downloads by date, and
  pasting the latest.
- **The Mac:** processes by CPU and memory, with Enter to end one; `:awake 2h`, `:awake until 18:00`; connecting paired
  Bluetooth devices (`:connect airpods`); `:input` for the microphone; `speed`, an internet speed test with macOS's own
  tool; the Wi-Fi password, and a QR code for guests; Stage Manager on and off; dismiss notifications.
- **Extending it:** script rows with live output and a choice of arguments; `copperlight choose`, lines from a
  pipe as rows; a URL scheme and Shortcuts actions; a
  starter library of commands, and importers for snippets and quicklinks from other apps.
- **Look and feel:** text size, and which screen it opens on; other languages for the interface (what you type stays
  as it is); switching the keyboard layout from the field; a double-tapped modifier as the hotkey (still one hotkey).
- **Usage stats**, kept on your Mac.
- **Homebrew:** `brew install` through Copperlight's own tap.
- **A privacy page:** every permission Copperlight can ask for, what each one turns on, and every server it ever
  contacts.

## Done

- **v0.9:** colors by their shape (`#c87533`, `rgb(…)`, `hsl(…)`) with a swatch, and `pick color`; `qr`
  codes; date math (`days until dec 25`, `in 3 weeks`, a date's weekday and week), answered before you finish typing;
  `{cursor}` in snippets; currency after math (`39*8 usd`); contacts (Enter messages, Tab for call, FaceTime, WhatsApp,
  email, copy); open browser tabs, Enter switching to one; `copy text` from any part of the screen, and the link in a
  QR code there; `spell`; reminders that are due, and the apps you open around this time, waiting in the empty
  launcher; Large Type; `20% off 80`, `30 is what % of 150`, `10k * 3`, and Tab to keep going with a result; script
  filters (`@output rows`).
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

## Not planned

- **An AI assistant, chat or agents.** Copperlight has no AI service, and won't. On-device models (Apple Intelligence,
  Vision) are fine, and macOS's Writing Tools already rewrite text in every app.
- **Accounts, cloud sync, team sharing or telemetry,** and apps for other devices. Your config is one plain file: keep
  it in git or any synced folder. Universal Clipboard already moves copies between your devices.
- **Web answers while you type,** weather, sports or flight status. They would send what you type to a service.
- **Link previews and favicons for copied links.** Fetching them would tell those sites what you copied.
- **An extension store or runtime,** custom views for extensions, or a visual workflow editor. Commands, snippets and
  scripts in a folder cover it, with nothing to install and nothing running unsandboxed; the Shortcuts app does visual
  automation.
- **More global hotkeys, ⌘K menus, Vim keys or a file buffer.** One hotkey opens Copperlight, and every action has its
  own row or `:` command.
- **Watching what you type elsewhere:** snippets that expand anywhere, or merging copies with a double ⌘C. It would
  mean watching every key. macOS's Text Replacements (System Settings › Keyboard) expand text anywhere; snippets are
  pasted from the launcher, where `{date}`, `{clipboard}` and `{query}` work.
- **Favorites pinned by hand.** Use decides the order.
- **Themes and custom colors.** Copperlight has its own look, from the icon.
- **What macOS already does well:** the contents of Mail, Messages and Notes (Spotlight searches them), a grid of
  every app (Spotlight's Apps view), password manager items (their own quick access), resizing and converting images
  (Finder's Quick Actions), dictation, blocking apps and sites (Screen Time and Focus), quitting idle apps (App Nap),
  switching Spaces (⌃1–9) and an app's windows (⌘`), answering invitations (Calendar), speaking text (a two-line `say`
  script), and hiding the menu bar icon (System Settings › Menu Bar).
