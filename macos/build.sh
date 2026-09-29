#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Waddly.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/macos/Info.plist")

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

ICON_SOURCE="$APP/Contents/Resources/waddly-icon-source.png"
ICONSET="$APP/Contents/Resources/Waddly.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/macos/make-icon.swift" "$ROOT/assets/01-idle.png" "$ICON_SOURCE"
make_icon_size() {
  sips -z "$2" "$2" "$ICON_SOURCE" --out "$ICONSET/$1" >/dev/null
}
make_icon_size icon_16x16.png 16
make_icon_size icon_16x16@2x.png 32
make_icon_size icon_32x32.png 32
make_icon_size icon_32x32@2x.png 64
make_icon_size icon_128x128.png 128
make_icon_size icon_128x128@2x.png 256
make_icon_size icon_256x256.png 256
make_icon_size icon_256x256@2x.png 512
make_icon_size icon_512x512.png 512
make_icon_size icon_512x512@2x.png 1024
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Waddly.icns"
rm -rf "$ICONSET"
rm -f "$ICON_SOURCE"

if [ -n "${WADDLY_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$WADDLY_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi

printf 'Built %s\n' "$APP"
