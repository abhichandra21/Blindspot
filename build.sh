#!/bin/bash
# Builds Blindspot.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

app="Blindspot.app"
# Keep the compiler target, the plist minimum and platforms in Package.swift
# in step.
min_macos="13.0"
# Release builds pass VERSION from the git tag; local builds use the default.
version="${VERSION:-0.1}"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
# swiftc links against the installed SDK; swift build would record the
# package's minimum as the SDK, which changes some AppKit defaults.
swiftc -O -target "arm64-apple-macos$min_macos" Sources/Blindspot/*.swift -o "$app/Contents/MacOS/Blindspot"
# Before signing, so the signature covers the icon.
mkdir -p "$app/Contents/Resources"
cp assets/Blindspot.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.abhichandra.blindspot</string>
    <key>CFBundleName</key><string>Blindspot</string>
    <key>CFBundleExecutable</key><string>Blindspot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>$min_macos</string>
    <key>CFBundleIconFile</key><string>Blindspot</string>
</dict>
</plist>
EOF
# macOS ties the Screen Recording grant to the signature. A fixed certificate
# keeps the grant across rebuilds; an ad-hoc signature changes every build, so
# the grant would need resetting each time. Release builds set SIGN_IDENTITY
# and SIGN_KEYCHAIN to the release certificate; local builds use the local one.
identity="${SIGN_IDENTITY:-TeamsShareGuard Local Signing}"
keychain="${SIGN_KEYCHAIN:-}"
if security find-certificate -c "$identity" ${keychain:+"$keychain"} >/dev/null 2>&1; then
    codesign --force ${keychain:+--keychain "$keychain"} --sign "$identity" "$app"
elif [ -n "${SIGN_IDENTITY:-}" ]; then
    # An ad-hoc release would silently drop every user's Screen Recording grant.
    echo "error: certificate \"$identity\" not found" >&2
    exit 1
else
    echo "warning: certificate \"$identity\" not found, signing ad-hoc" >&2
    codesign --force --sign - "$app"
fi
echo "built $app"
