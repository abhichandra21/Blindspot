# Blindspot

A small macOS menu bar app that warns you when a Microsoft Teams chat may be visible in your Teams screen share, and can minimize it for you.

Screen sharing the wrong screen is easy to do.
If a Teams chat or the Activity feed is open on the screen you share, everyone in the meeting can read it.
Blindspot watches for that and steps in.

## What it does

When you share your screen from Teams and a Teams **Chat** or **Activity** window is on the shared screen, Blindspot:

- plays a short warning sound,
- turns its menu bar shield red,
- shows a red banner on a screen you are *not* sharing (it never puts the banner on the shared screen),
- and, if you allow it, minimizes those Teams windows right away.

When the share stops, or the chat moves off the shared screen, the warning clears on its own.

## How it works

Blindspot checks the window list once a second. No Teams plugin or account access is involved.

- While you share, Teams shows a hidden window named "Sharing Indicator" that covers exactly the shared area. That tells Blindspot a share is on and which screen it is.
- The main Teams window's title starts with the current tab, such as "Chat | ..." or "Activity | ...". That tells it whether chat content is showing.
- If a matching Teams window overlaps the shared screen, that counts as exposed.

These are observations of how the new Teams for Mac behaves, not a documented API, so a future Teams update could change them.

## Requirements

- macOS 13 or later, Apple silicon
- The new Microsoft Teams for Mac
- Xcode Command Line Tools (for `swiftc` and `codesign`)

## Build

```
./build.sh
open Blindspot.app
```

`build.sh` compiles `main.swift` into `Blindspot.app` next to it.

### Optional: a stable signing certificate

macOS ties permissions to the app's signature.
Without a certificate the app is signed ad-hoc, and the signature changes on every build, so you have to grant permissions again after each rebuild.
To avoid that, create a local code signing certificate once.
`build.sh` uses it automatically if it finds it:

```
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = TeamsShareGuard Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -name "TeamsShareGuard Local Signing"
security import id.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
rm key.pem cert.pem id.p12 cert.cnf
```

The certificate shows as "not trusted" in Keychain Access. That is expected and does not stop it from signing.
The name is a leftover from the app's earlier name; it is only a label.

## Permissions

| Permission | Why |
|---|---|
| Screen Recording | Required. Window titles are only readable with it, and that is how Blindspot recognizes the sharing indicator and the Chat and Activity windows. Blindspot never records or saves your screen. |
| Accessibility | Optional. Only needed to minimize Teams windows. |

The Settings window shows the status of both, with buttons to the matching System Settings pages.

## Using it

- **Left-click** the shield to pause or resume. Filled shield means running, outline means paused. Every launch starts unpaused, so a pause is never forgotten.
- **Right-click** (or Control-click) for Settings and Quit.

Settings has four tabs:

- **General**: start at login, warning sound.
- **Detection**: which Teams tabs to watch (Chat, Activity), and automatic minimizing.
- **Permissions**: status of Screen Recording and Accessibility.
- **About**: version and where the app is running from.

Start at Login uses a launch agent at `~/Library/LaunchAgents/com.abhichandra.blindspot.plist`.
It also restarts the app if it crashes, but not after you quit it.

## Known limits

- Teams only. Shares from Zoom, Slack, or a browser are not detected.
- A chat window that is completely covered by another window still counts as exposed, so the warning says the chat *may* be visible.
- Checks run once a second, so a chat can be visible for up to about a second before it is minimized.
- Sharing a single window (instead of a whole screen) has not been verified yet. Neither has automatic minimizing.
- With only one screen there is nowhere safe for the banner, so you get the sound and the red menu bar icon only.
- Teams chats that are popped out into their own window may have titles Blindspot does not recognize.
