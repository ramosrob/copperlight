# Roadmap

What's planned for Copperlight, roughly in order. There are no dates: things ship when they're ready.
[SPEC.md](SPEC.md) decides what fits: a small core, keyboard only, one hotkey, plain-text config, nothing about
you leaves your Mac. Ideas are welcome: [open an issue](https://github.com/ramosrob/copperlight/issues).

## Next

- **Snippets that expand anywhere:** type a snippet's keyword in any app and it becomes the text. Needs the Input
  Monitoring permission, so it will be opt-in.
- **Updates:** tell you when a new version is out, and install it.

## Later

- **Recent queries:** ↑ in an empty field brings back what you typed before.
- **More window actions:** quarters, nudging a window, and saved multi-window layouts defined in config.toml.
- **Contacts:** call, FaceTime, message or email someone by name.
- **Screen tools:** pick a color from the screen; copy the text or a QR code in a region of the screen
  (recognized on your Mac); make a QR code from text.
- **Small lookups:** open browser tabs, recent files, end a process or free a port, your IP, battery and disk.
- **Open the launcher on a selection:** with text selected, the hotkey opens Copperlight with it already typed,
  ready for the text tools or a search.
- **Homebrew:** `brew install` through Copperlight's own tap.
- **A privacy page:** every permission Copperlight can ask for, what each one turns on, and every server it ever
  contacts.

## Done

- **v0.5:** Settings › General › Translate to; text in a language that isn't one of your Mac's is read right.
- **v0.4:** timers (`timer 10 min tea`), counting down in the menu bar beside the pomodoro.
- **v0.3:** music and sound from the field (`:play`, `:next track`, `:mute`, `:output airpods`); `:wifi` and
  `:awake`, whose rows say what Enter does; `translate` alone translates what you copied; a name that takes text
  turns into a chip in the field, with Tab (`tra` ⇥ is the Translate chip). What's playing has no public macOS API for
  apps, and Bluetooth can't be switched on or off without one, so `bluetooth` stays its System Settings page.
  `stock AAPL`: the price, today's change and a 7-day chart, from Yahoo Finance, only when you ask.
- **v0.2:** search the menus of the app you're in (`:export pdf`); System Settings pages as rows (`bluetooth`,
  `dark mode`); community script commands work as they are.

## Not planned

- **An AI assistant or chat.** Copperlight has no AI service, and won't. On-device models (Apple Intelligence,
  Vision) are fine.
- **Accounts, cloud sync or telemetry.** Your config is one plain file: keep it in git or any synced folder.
- **Web answers while you type.** They would send what you type to a search engine.
- **An extension store or runtime.** Commands, snippets and scripts in a folder cover it, with nothing to install
  and nothing running unsandboxed.
- **More global hotkeys, or ⌘K menus.** One hotkey opens Copperlight; everything else is typed. Enter on a result
  lists what you can do with it.
