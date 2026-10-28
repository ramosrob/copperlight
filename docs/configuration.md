# Configuring Copperlight

Everything is optional: Copperlight works with no config at all. **Settings…** in the menu bar edits the same file.

`~/.config/copperlight/config.toml` is created with commented examples on first run. **Settings…** in the menu bar
edits it for you: the hotkey, currency, pomodoro, clipboard, file search, browser, and your commands and
snippets. It changes only the lines it needs and keeps your comments, and a change it can't make
cleanly (dotted keys, inline tables) isn't saved. Or edit the file in any editor: saved changes apply
immediately. If the file doesn't parse, the launcher pins an error row at the top saying where the problem is
(Enter opens the file), and the last valid config stays in use until you fix it. Every setting is optional.
Deleting the file means all defaults.

```toml
[hotkeys]
launcher = "option+space"      # default; the only hotkey

[currency]
default_target = "EUR"         # default. Used by "25 usd" (no target). When the source is the default
                               # itself ("25 eur"), it converts to USD (to EUR if the default is USD).

[clipboard]
ignore_apps = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
               "com.apple.keychainaccess", "com.apple.Passwords"]   # default (bundle ids)
max_items = 1000               # default
max_days = 90                  # default
max_images = 100               # default; images also count toward max_items. 0 = text only

[files]
scopes = ["~/code", "~/Documents", "~/Downloads", "~/Desktop"]                 # default
exclude = ["node_modules", ".git", ".venv", "__pycache__", "DerivedData", "build", ".build"]   # default

[pomodoro]
default_minutes = 25           # default, 1–240
break_minutes = 5              # default, 1–240

[translate]
default_target = "german"      # optional: "translate bom dia" without "to …" goes here (an English name or a code,
                               # "de"). Unset: the first of your Mac's languages the text isn't in, which is also
                               # used when the text is already in this one. Settings › General › Translate to.

[browser]                      # where web links open: typed URLs, the search row, url commands without their own
name = "Google Chrome"         # optional: name or bundle id; the default browser if missing
profile = "Personal"           # optional; unset, the browser picks the profile
search = "duckduckgo"          # optional: the search row's engine: google (default), duckduckgo, bing, brave,
                               # ecosia, kagi. Settings › Browser › Search engine.

[[command]]
alias = "github"
type = "url"
url = "https://github.com"
browser = "Google Chrome"      # optional: name or bundle id; the default browser if missing
profile = "Work"               # optional

[[command]]
alias = "gh"
type = "url"
url = "https://github.com/search?q={query}"   # "gh copperlight" searches GitHub for "copperlight"

[[command]]
alias = "slack"
type = "app"
app = "Slack"                  # app name or bundle id ("com.tinyspeck.slackmacgap")

[[command]]
alias = "budget"
type = "file"
path = "~/Documents/finance/cashflow.xlsx"

[[command]]
alias = "dev"
type = "shell"
run = "cd ~/code/api && docker compose up -d"

[[snippet]]
name = "sig"
text = """
Best,
Alex"""

[[snippet]]
name = "reply"                 # "reply John"
text = "Hi {query}, thanks for the note. I'll get back to you by {date}."
```

**The hotkey** is `modifier+…+key`. Modifiers: `command`/`cmd`, `option`/`opt`/`alt`, `control`/`ctrl`,
`shift`. Keys: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`, `delete`, `left`/`right`/`up`/`down`,
`f1`–`f12`, and `` - = [ ] ; ' , . / \ ` ``. Keys are matched by position on a US keyboard.
macOS lets two apps register the same hotkey without any error, and only one of them gets it. If it
does nothing, another app probably has it: check other launchers and keyboard tools, chat and speech-to-text apps
(several default to ⌥Space), or pick a different one.

**Clipboard:** a screenshot is 1–5 MB, so `max_images` keeps the database small; images over 25 MB aren't
recorded. `ignore_apps` replaces the default list, so keep the password managers in it. To find an
app's bundle id: `osascript -e 'id of app "Slack"'`. Older items are deleted at launch, after each copy, and
when you change these settings.

**Files:** `exclude` hides results with one of these names anywhere in their path (whole folder or file
names, not patterns). Like `ignore_apps`, it replaces the default list, so keep the defaults you want.

**Commands** show up when the query fuzzy-matches the alias. An exact alias match ranks first.

| `type` | Field | Enter does |
|---|---|---|
| `url` | `url`, optional `browser`, `profile` | Opens with the default app for the link (any scheme: `https`, `slack://`, `obsidian://`). With `browser` or `profile`, opens in that browser and profile. A web link without them follows `[browser]`. |
| `app` | `app` | Launches or activates the app, by bundle id or name. |
| `file` | `path` (`~` ok) | Opens with the default app. |
| `shell` | `run` | Runs `/bin/zsh -lc "<run>"` in `~`, detached. A non-zero exit posts a notification with the end of stderr. |

- `{query}` in `url` makes it a search: the text typed after the alias fills it, URL-encoded (`gh copperlight` →
  `…/search?q=copperlight`). Any site with a search URL works: Jira, docs, maps, translate.
- `browser` is an app name ("Firefox", "Safari", "Arc") or bundle id. Without it, `profile` uses the default
  browser.
- `profile` works in Chrome, Brave, Edge, Vivaldi and Chromium: the name the browser shows ("Work") or its
  folder ("Profile 1"), looked up in the browser's `Local State`. An unknown one shows an error row instead of
  quietly opening the default profile. Firefox takes its profile name (`about:profiles`) and shows its profile
  manager for one it doesn't know. Safari and Arc can't be opened in a profile from outside, so that's an
  error row too.
- `[browser]` sets where web links go when nothing more specific does: what you type (`gmail.com`), the
  search row, and `http(s)` commands without their own `browser` or `profile`. Its rows say where
  ("Google Chrome: Personal"). If its profile can't be used, the default browser opens the link and the row
  says why.
- `-l` makes zsh a login shell: it reads `~/.zprofile` (where Homebrew's PATH usually goes), but not
  `~/.zshrc`. Anything a command needs (PATH, env vars) belongs in `~/.zprofile`.

## Where things live

Everything lives in `~/.config/copperlight/`:

- `config.toml`: yours to edit (above).
- `note.txt`: the note's text. Saved 500 ms after you stop typing, and when the note hides or the app
  quits. Edits made elsewhere are picked up while the note doesn't have focus.
- `notes/`: named notes (`note work` → `notes/work.txt`), saved the same way. Edits made elsewhere show the next
  time the note opens. Delete a file to delete that note.
- `state.json`: app state, one top-level section per feature (`frecency`, `windows`, `pomodoro`). Written by the app
  (debounced, atomic). Sections it doesn't know are kept. If the file is unreadable it's moved to
  `state.json.bad` and the app starts fresh.
- `rates.json`: Frankfurter/ECB rates, raw API response. Refreshed in the background when over 24 h old,
  on launch and on panel open. When you're offline the old rates are used.
- `clipboard.sqlite`: clipboard history, text and PNG images (SQLite, readable only by you). Deleted items are overwritten on
  disk (`secure_delete`), not just unlinked. `sqlite3 ~/.config/copperlight/clipboard.sqlite` to poke at it.

