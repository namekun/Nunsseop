<p align="center"><img src="docs/images/icon.png" width="120" alt="Nunsseop icon"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>Your MacBook notch, finally useful.</b><br>
  Music, calls, files, a Spotlight-style launcher, AI usage, agent notifications, your calendar and system HUDs, one hover away.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=c86bfa&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-ff5f8f" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="Native Swift">
</p>

<p align="center">
  <b>English</b> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="https://namekun.github.io/Nunsseop/">Website</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="Expanded notch with now playing and calendar">
</p>

*Nunsseop* (눈썹) is Korean for *eyebrow*, the little arch above your screen. It's free, open source, and has no account, subscription or tracking.

## Install in 30 seconds

```sh
brew install --cask namekun/tap/nunsseop
```

Needs [Homebrew](https://brew.sh). Homebrew clears the quarantine flag, so the app opens right away. To update, run `brew update && brew upgrade --cask nunsseop`; when an update is out, Settings › General › Updates copies that command to your clipboard.

Needs macOS 14 Sonoma or later. Works on Apple silicon and Intel, and on screens without a notch.

## Your first minute

1. **Hover over the notch.** It opens. Move the pointer away and it tucks itself back.
2. **Play something** in Music, Spotify, YouTube Music or any browser. The notch picks it up, and the collapsed notch shows a tiny artwork and visualizer.
3. **Right-click the notch → Settings** to choose your tabs, their order, the pop-ups you want and the size.

There's no Dock icon. Nunsseop lives in the notch.

## A look inside

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="Search showing an app, a command and a setting"><br>**Search.** A launcher for apps, files, commands, clipboard, emoji and sums, on any shortcut you like. | <img src="docs/images/tab-ai.png" alt="AI usage for Claude Code and Codex"><br>**AI usage.** Claude Code and Codex limits, no login needed. |
| <img src="docs/images/shelf.png" alt="File shelf with AirDrop tile"><br>**Shelf.** Park files in the notch, or drop them on AirDrop. | <img src="docs/images/tab-timer.png" alt="Timer tab"><br>**Timer.** Countdown, Pomodoro and stopwatch, any length you like. |
| <img src="docs/images/tab-tools.png" alt="Tools tab"><br>**Tools.** Audio output, mic mute, keep awake, screen recording, color picker and text capture. | <img src="docs/images/tab-system.png" alt="System tab with device batteries"><br>**System.** CPU, memory, disk, network and device batteries. |
| <img src="docs/images/tab-emoji.png" alt="Emoji picker"><br>**Emoji.** Every emoji, searchable, one click to copy. | <img src="docs/images/hud-headphones.png" alt="Headphone battery HUD"><br>**HUDs.** Volume, brightness, AirPods battery and more. |
| <img src="docs/images/collapsed-call.png" alt="Collapsed notch during a Zoom call"><br>**Calls.** The call app and how long you've been talking. | <img src="docs/images/collapsed-idle.png" alt="Collapsed notch showing Claude Code usage left and weather"><br>**At a glance.** Pick what each side of the closed notch shows. |

## Everything it does

**🎵 Music**
- **Now playing from any app.** Music, Spotify, YouTube Music, and browsers like Safari, Chrome, Arc, Dia and Aside. Artwork, controls and a progress bar you can drag.
- **Synced lyrics** from [LRCLIB](https://lrclib.net), under the title or under the notch while you work.
- **Sneak peek.** When the track changes, the title slides out for a moment.
- **Podcasts and long videos** get 15-second skips and a speed button (1× to 2×), when the player supports them.

**🗂️ Get things done**
- **Shelf.** Drag files onto the notch and back out later, with previews of images, PDFs and videos. Screenshots and finished downloads can land there automatically. Shake the pointer while dragging files anywhere and a small drop target appears right beside it.
- **Calendar and reminders.** Today in large digits, your week with a dot on busy days, today's events, and reminders you can tick off. Every account added to macOS works (Google, iCloud, Exchange and more), and you choose which calendars show.
- **Upcoming events.** Five minutes before a timed event starts, the notch shows its title and how soon it begins. Events with a Zoom, Google Meet, Teams, Webex, FaceTime, Whereby or Chime link get a green Join button on Home, and clicking the notice joins the meeting.
- **Search that can replace Spotlight or Raycast.** Apps (even ones outside Applications), files, system commands and settings, clipboard history, emoji (start with `:`) and sums like `12*(3+4)`, ranked by what you open most. Initials work: `vsc` finds Visual Studio Code. Arrow keys pick, Return opens.
- **Your shortcut.** <kbd>⇧⌘Space</kbd> by default, or record any combination in Settings. Nunsseop tells you when macOS or another app already uses it.
- **Timer, clipboard history, notes and an emoji picker.** Clipboard history stays in memory and skips anything a password manager marks as secret. Tracking parameters like `utm_` and `fbclid` are stripped from links you copy.

**💻 Your Mac**
- **System HUDs.** Volume, brightness (including DDC external displays), keyboard backlight, charging, Caps Lock and AirPods battery appear in the notch. It can take over the volume and brightness keys so the system HUD stays away.
- **System stats and batteries.** CPU, memory, disk, network, plus your mouse, keyboard and trackpad, with a warning when one runs low.
- **Camera and mic indicator.** A dot on the notch while any app uses them.
- **Tools.** Switch audio output, set each app's volume (experimental, macOS 14.2+), mute the mic, keep the Mac awake, record the screen, eject drives, pick a color from anywhere on screen, and copy the text out of any part of the screen.
- **Weather, downloads, mirror and Dock apps**, one hover away.

**📞 Even when it's closed**
- **Calls.** During a call in Zoom, FaceTime, Teams, Slack, Discord, WhatsApp or Google Meet, the closed notch shows the app and how long you've been talking. It goes by which app uses the microphone, so no extra permissions are needed. For Zoom, FaceTime and Meet you can mute the mic or turn the camera off from the notch, without switching to the call.
- **Your pick on each side.** When nothing is playing, show Claude Code or Codex usage left, agents at work, battery, weather or the date.
- **Music and timers.** Tiny artwork and a visualizer while music plays, and the time left while a timer runs.
- **Downloads.** How far along a Safari or Chrome download is, in percent, from the same progress the Finder shows on the file. Nothing polls for it.

**🤖 For developers**
- **AI usage.** Claude and Codex limits with reset times, and token use over the last 5 hours and 7 days, counted across Claude Code, Codex, gjc, omo and OpenCode. Read from files those tools already keep on your Mac, so there's nothing to sign in to.
- **Live Claude limits (opt-in).** The AI tab asks once whether to fetch your 5-hour and weekly Claude limits from Anthropic, about once an hour, with the sign-in Claude Code keeps in the Keychain. Off until you say yes; change it later in Settings › Services.
- **Notifications from agents and terminals.** Claude Code, Codex, Gemini CLI and OpenCode hooks, agents in Muxy, cmux and herdr, and bells from tmux and WezTerm show in the notch. Click a notice to bring its terminal, pane or tab to the front ([setup below](#agent-and-terminal-notifications)).
- **Notifications tab.** The last 30 notices from agents, terminals and your calendar, with a badge for unseen ones; click one to go back where it came from. Off by default (Settings › Notch), and kept in memory only.
- **Agents at work.** A closed-notch item that shows how many coding agents wait for you (a yellow hand), or, when none wait, how many are working (a green bolt). It follows herdr for now.

**🧩 Make it yours**
- Pick your tabs and their order, what the header and collapsed notch show, and which pop-ups you get. **Anything you turn off stops running.**
- On macOS 26 the expanded notch and its cards use Liquid Glass, so what's behind shows through softly. You can set how dark the glass is, all the way to 100% for a solid black notch, or switch the glass off.
- On displays without a notch, the closed notch is a small pill with the eyebrow logo inside the menu bar, in glass if you like. It fades out after it sits unused (3 to 60 seconds, or never) and comes back when the pointer reaches it; rest there for half a second and it opens.
- Choose the display, size and hover delay, launch at login, and hide the notch while the lid is closed.
- Swipe down to open, up to close, sideways on Home to skip tracks.
- Speaks English, 한국어, 日本語, 简体中文, Español, Deutsch and Français, following your Mac.

## FAQ

<details>
<summary><b>macOS says Nunsseop can't be opened.</b></summary>

The app isn't notarized yet, so install it with Homebrew (`brew install --cask namekun/tap/nunsseop`). Homebrew clears the quarantine flag, and the app opens right away.
</details>

<details>
<summary><b>Nothing shows up when I play music.</b></summary>

Nunsseop shows whatever macOS lists as Now Playing, so the player has to appear in Control Center. Most apps and browsers do. See [how now playing works](#how-now-playing-works) for the fallback.
</details>

<details>
<summary><b>Can Search replace Spotlight?</b></summary>

Yes. Open Settings → Services, click the shortcut and press <kbd>⌘Space</kbd>. Nunsseop will point out that Spotlight uses it and open Keyboard Shortcuts, where you untick *Show Spotlight search*. Search also opens when its tab is hidden.
</details>

<details>
<summary><b>There are too many tabs.</b></summary>

Right-click the notch → Settings → Notch, and switch off what you don't need. Turned-off features stop running entirely.
</details>

<details>
<summary><b>My Mac has no notch.</b></summary>

On a display without a notch, such as an external monitor with the lid closed, the closed notch is a small pill with the eyebrow logo floating inside the menu bar. The eyebrow lifts when the pointer is over it, and opening it attaches the notch to the top edge at the usual size. It fades out when unused; turn that off or change the delay in Settings. Pick which display it uses there too.
</details>

<details>
<summary><b>Why does AI usage show old Claude limits?</b></summary>

By default, Claude's 5-hour and weekly percentages come from caches other tools write: the [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) HUD while you use Claude Code in a terminal, or gjc. The card shows when they were last updated. Claude's limits can also come straight from Claude Code's status line once you connect it in Settings › Services. For limits that stay current without them, turn on live Claude limits in the AI tab or Settings › Services. Token totals are always live.
</details>

<details>
<summary><b>Volume keys stopped showing Nunsseop's HUD after an update.</b></summary>

Versions before 0.8.3 were signed in a way that made macOS forget the Accessibility permission on every update. Since 0.8.3 it's kept. If you came from an older version, remove Nunsseop from System Settings → Privacy & Security → Accessibility once and allow it again; it takes effect without a restart.
</details>

## Agent and terminal notifications

Nunsseop listens on `127.0.0.1:47750` for notifications from tools on your Mac. Requests must carry the secret token stored in `~/Library/Application Support/Nunsseop/notify-token`.

Open Settings → Alerts and press **Connect** next to Claude Code, Codex, Gemini CLI or OpenCode. Only tools you have used on this Mac are listed. Nunsseop changes that tool's settings file (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`) or adds a plugin to `~/.config/opencode/plugins`, and keeps the old file with a `.nunsseop-backup` extension. Codex allows only one `notify` command, so an existing one keeps running after Nunsseop's. **Disconnect** undoes it. Sessions started afterwards send their notifications to the notch.

To set up Claude Code by hand, press **Copy Claude Code hook command** and add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

Terminals and agent apps need no hook:

- **Muxy** and **cmux:** their own notifications are read from the app, and not shown while it's in front.
- **herdr:** agents that finish or wait for input, in every session, read from herdr's socket.
- **tmux:** bells from any window. Nunsseop adds a hook to the running tmux server only; `tmux.conf` isn't changed.
- **WezTerm:** bells, through lines you copy from Settings › Alerts and paste into `~/.wezterm.lua`.

Each has a toggle under Settings › Alerts (WezTerm has a button that copies its config lines instead), shown only when the tool is installed. Tools already connected through their own hook aren't shown twice.

Any script can send one too:

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

## Permissions

Nunsseop asks for a permission only when you first use the feature that needs it.

| Feature | Permission | When it is asked |
| --- | --- | --- |
| Calendar | Calendars | When you press *Allow Access* on the Home tab |
| Reminders | Reminders | When you press *Allow Reminders* on the Home tab |
| Mirror | Camera | When you press *Allow Camera* on the Mirror tab |
| Screen recording, and copying text from other apps' windows | Screen Recording | The first time you start a recording or capture text |
| Recording with sound | Microphone | The first time you record with microphone audio on |
| Taking over volume, brightness and keyboard backlight keys | Accessibility | When you turn the option on in Settings |
| Fallback now playing for Music, Spotify and browsers | Automation | Only if the MediaRemote helper is unavailable |
| Showing Google Meet, Zoom and Teams calls in a browser | Automation (that browser) | When a browser first uses the microphone |
| Launch at login | Login Items | When you turn it on in Settings |

## Privacy

Nunsseop doesn't collect or send personal data. It goes online only to:

- check `api.github.com` for a newer release once a day (can be turned off);
- look up synced lyrics on `lrclib.net` (can be turned off);
- fetch weather from `open-meteo.com` for the city you enter (off until you enter one), asking Apple's geocoder for the city's location when Open-Meteo can't find it;
- download artwork over HTTPS from known music services, only when the MediaRemote helper is unavailable;
- ask `api.anthropic.com` for your Claude limits about once an hour, using Claude Code's sign-in from the Keychain, only if you turn live Claude limits on.

Everything else stays on your Mac. The notification server only accepts connections from this Mac. AI usage is read from local files unless you turn on live Claude limits. Notices in the Notifications tab are kept in memory only. Recordings are saved next to your screenshots. The camera preview runs only while the Mirror tab is open and is never recorded. Clipboard history is cleared when Nunsseop quits.

## How now playing works

Since macOS 15.4, the private MediaRemote framework only answers processes signed by Apple. Nunsseop ships a small helper library (`Sources/NowPlayingHelper`) that runs inside the system's `/usr/bin/perl`, reads the Now Playing state, sends play, pause, skip and seek commands, and streams JSON lines back to the app.

This relies on private API, so a future macOS update may break it. If it does, Nunsseop falls back to AppleScript for Music and Spotify and to reading media tabs in browsers. That fallback needs *Allow JavaScript from Apple Events* turned on in each browser. Dia has no menu item for it, so Nunsseop offers to restart it with `--enable-applescript-javascript`.

## Build from source

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

You need the Xcode command line tools with Swift 5.10 or later. `scripts/bundle.sh` builds the Swift package and wraps it in an ad-hoc signed app bundle.

## License

[MIT](LICENSE). Issues and pull requests are welcome.
