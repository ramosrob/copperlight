import Foundation

/// Other words people use for Copperlight's things and the Mac's apps, by the name they show: typing the start of one
/// (from 3 letters) finds the thing, just below matches on its own name. `:turn off` finds Shut Down, "task manager"
/// Activity Monitor. Hand-picked on purpose: NaturalLanguage's sentence embeddings got 5 in 14 of these right
/// ("reboot" → TextEdit). Apps also get words from Apple Intelligence (AppIndex); System Settings pages keep theirs in
/// their own table (SystemSettings.swift).
let otherNames: [String: [String]] = [
    // : commands
    "Shut Down": ["turn off", "power off", "switch off", "shutdown"],
    "Restart": ["reboot"],
    "Sleep": ["suspend", "standby"],
    "Sleep Displays": ["screen off", "display off", "monitor off"],
    "Lock Screen": ["lock mac", "lock computer"],
    "Empty Trash": ["clear trash", "delete trash", "recycle bin"],
    "Toggle Dark Mode": ["light mode", "night mode", "appearance", "theme"],
    "Quit Application": ["exit", "close app"],
    "Force Quit Application": ["kill", "end task"],
    "Relaunch Application": ["restart app", "reopen"],
    "Set Volume": ["sound", "audio", "louder", "quieter"],
    "Toggle Mute": ["unmute", "silence"],
    "Play or Pause": ["pause", "resume", "media"],
    "Next Track": ["skip", "next song"],
    "Previous Track": ["previous song", "last song"],
    "Switch Sound Output": ["speakers", "headphones", "audio output", "sound output"],
    "Toggle Wi-Fi": ["wi-fi", "wireless", "internet"],
    "Keep Awake": ["caffeinate", "no sleep", "stay awake", "insomnia"],
    "Eject Disk": ["unmount", "usb", "drive"],
    "Toggle Hidden Files": ["show hidden", "dotfiles", "invisible files"],
    "Toggle Fullscreen": ["full screen"],
    // Lookups
    "IP Address": ["my ip", "public ip", "local ip", "ip address", "what is my ip"],
    "Disk Space": ["storage", "free space", "disk usage", "hard drive"],
    "Port": ["listening ports", "open ports", "free a port"],
    "Maximize Window": ["fill screen", "zoom window"],
    "Switch to Window": ["alt tab", "windows"],
    "Move to Next Display": ["next screen", "next monitor", "other screen", "other monitor"],
    "Reveal in Finder": ["show in finder"],
    "Copy Path": ["file path"],
    "Run Shell Command": ["shell", "terminal", "bash", "zsh"],
    "Open Config": ["config.toml"],
    // Copperlight
    "Note": ["notepad", "scratchpad", "jot", "memo"],
    "Clipboard History": ["paste history", "copy history", "copied", "pasteboard"],
    "Copperlight Settings": ["preferences", "options"],
    "Welcome to Copperlight": ["onboarding", "permissions", "get started"],
    "Pomodoro": ["focus timer"],
    "Timer": ["countdown", "kitchen timer", "egg timer"],
    "Emoji": ["emoticon", "smiley"],
    "Define": ["dictionary", "definition", "meaning"],
    "New UUID": ["guid", "unique id"],
    "Format JSON": ["prettify json", "beautify json", "pretty print"],
    "Minify JSON": ["compact json"],
    "New Password": ["generate password", "random password"],
    "Lorem Ipsum": ["placeholder text", "dummy text"],
    "Unix Time ↔ Date": ["epoch", "timestamp"],
    "Hex ↔ RGB": ["color", "colour"],
    "Count": ["word count", "character count"],
    "SHA-256": ["hash", "checksum"],
    "Sort Lines": ["alphabetize"],
    // The Mac's apps, by the names other systems use
    "Activity Monitor": ["task manager", "processes"],
    "System Settings": ["control panel"],
    "Finder": ["explorer", "file explorer", "file manager"],
    "TextEdit": ["notepad", "wordpad", "text editor"],
    "Terminal": ["command prompt", "cmd", "console", "powershell"],
    "Screenshot": ["snipping tool", "print screen", "screen capture"],
    "Preview": ["pdf viewer", "image viewer"],
    "Disk Utility": ["format disk", "partition"],
    "Photo Booth": ["webcam", "camera"],
    "QuickTime Player": ["video player", "screen recording"],
    "Music": ["itunes"],
    "Messages": ["sms", "imessage"],
    "FaceTime": ["video call"],
    "Mail": ["email"],
    "System Information": ["specs", "hardware"],
    "Stickies": ["sticky notes", "post-it"],
    "Image Capture": ["scanner"],
    "Passwords": ["keychain", "password manager"],
]

/// 0.9 when one of `name`'s other names starts with `query`, from 3 letters; nil otherwise.
func otherNameScore(_ query: String, _ name: String) -> Double? {
    let lower = query.lowercased().trimmingCharacters(in: .whitespaces)
    return lower.count >= 3 && (otherNames[name] ?? []).contains { $0.hasPrefix(lower) } ? 0.9 : nil
}
