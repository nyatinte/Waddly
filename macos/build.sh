#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Waddly.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Frames"

swiftc -swift-version 6 -target "$(uname -m)-apple-macos13.0" -O \
  -framework Cocoa \
  -framework ApplicationServices \
  -framework QuartzCore \
  -framework ServiceManagement \
  "$ROOT/macos/Waddly.swift" \
  -o "$APP/Contents/MacOS/Waddly"

cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT"/assets/[0-9][0-9]-*.png "$APP/Contents/Resources/Frames/"
if [ -n "${WADDLY_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$WADDLY_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi

printf 'Built %s\n' "$APP"
