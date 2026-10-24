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
</dict>
</plist>
EOF
# macOS ties the Screen Recording grant to the signature. A fixed local
# certificate keeps the grant across rebuilds; an ad-hoc signature changes every
# build, so the grant would need resetting each time.
identity="TeamsShareGuard Local Signing"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" "$app"
else
    echo "warning: certificate \"$identity\" not found, signing ad-hoc" >&2
    codesign --force --sign - "$app"
fi
echo "built $app"
