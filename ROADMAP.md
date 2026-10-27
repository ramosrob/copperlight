# Roadmap

What's planned for Copperlight, roughly in order. There are no dates: things ship when they're ready.
[SPEC.md](SPEC.md) decides what fits: a small core, keyboard only, one hotkey, plain-text config, nothing about
you leaves your Mac. Ideas are welcome: [open an issue](https://github.com/ramosrob/copperlight/issues).

## In the next release

- **System Settings pages as rows:** `bluetooth`, `displays`, `dark mode` open that page.
- **Community script headers:** existing community script commands work as they are, dropped in the scripts folder.

## Next

- **Search the menus of the app in front.** Type "export pdf" and run that menu item, without reaching for the
  mouse. Uses the Accessibility permission Copperlight already asks for.

## Later

- **Snippets that expand anywhere:** type a snippet's keyword in any app and it becomes the text. Needs the Input
  Monitoring permission, so it will be opt-in.
- **Media and quick toggles:** play/pause, next, what's playing; Wi-Fi, Bluetooth, mute, keep awake; switch the
  audio output.
- **Timers:** `timer 10 min tea`, counting down in the menu bar like the pomodoro.
- **Recent queries:** ↑ in an empty field brings back what you typed before.
- **More window actions:** quarters, nudging a window, and saved multi-window layouts defined in config.toml.
- **Contacts:** call, FaceTime, message or email someone by name.
- **Screen tools:** pick a color from the screen; copy the text or a QR code in a region of the screen
  (recognized on your Mac); make a QR code from text.
- **Small lookups:** open browser tabs, recent files, end a process or free a port, your IP, battery and disk.
- **Open the launcher on a selection:** with text selected, the hotkey opens Copperlight with it already typed,
  ready for the text tools or a search.
- **Updates:** tell you when a new version is out, and install it.
- **Homebrew:** `brew install` through Copperlight's own tap.
- **A privacy page:** every permission Copperlight can ask for, what each one turns on, and every server it ever
  contacts.

## Not planned

- **An AI assistant or chat.** Copperlight has no AI service, and won't. On-device models (Apple Intelligence,
  Vision) are fine.
- **Accounts, cloud sync or telemetry.** Your config is one plain file: keep it in git or any synced folder.
- **Web answers while you type.** They would send what you type to a search engine.
- **An extension store or runtime.** Commands, snippets and scripts in a folder cover it, with nothing to install
  and nothing running unsandboxed.
- **More global hotkeys, or ⌘K menus.** One hotkey opens Copperlight; everything else is typed. Enter on a result
  lists what you can do with it.
