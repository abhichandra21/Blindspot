# Blindspot

A macOS menu bar app that warns you when a Microsoft Teams chat may be visible in your Teams screen share, and can minimize it for you.

If a Teams Chat or Activity window is on the screen you share, everyone in the meeting can read it.
Blindspot notices within a second, then:

- plays a warning sound and turns its menu bar shield red,
- shows a red banner on a screen you are *not* sharing,
- and, if you allow it, minimizes those Teams windows.

<p>
  <img src="docs/images/settings-general.png" width="32%" alt="General settings">
  <img src="docs/images/settings-detection.png" width="32%" alt="Detection settings">
  <img src="docs/images/settings-permissions.png" width="32%" alt="Permission status">
</p>

## Get it

- **Download:** grab `Blindspot.zip` from [Releases](../../releases), then follow [Install](docs/INSTALL.md). macOS blocks the first launch because the app is not signed by Apple; the guide covers the one-time fix.
- **Build it yourself:** see [Building](docs/BUILDING.md). Recommended if you use it daily, since your permissions then survive updates.

Needs macOS 13 or later on Apple silicon, and the new Microsoft Teams for Mac.

## Use it

- **Left-click** the shield to pause or resume. Filled means running, outline means paused.
- **Right-click** for Settings and Quit.

## Known limits

- Teams only. Shares from Zoom, Slack, or a browser are not detected.
- A chat fully hidden behind another window still triggers the warning, so it says the chat *may* be visible.
- Sharing a single window, and automatic minimizing, have not been tested on a real call yet.
- With one screen there is nowhere safe for the banner, so you get the sound and red icon only.
- It relies on how the new Teams names its windows, not a documented API, so a Teams update could break detection.
