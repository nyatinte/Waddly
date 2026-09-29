#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Waddly.app"
DIST="$ROOT/dist"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/waddly.XXXXXX")
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/macos/Info.plist")
ARCH=$(uname -m)
DMG="$DIST/Waddly-$VERSION-macos-$ARCH.dmg"

trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
"$ROOT/macos/build.sh"
mkdir -p "$DIST" "$STAGING/Waddly"
cp -R "$APP" "$STAGING/Waddly/"
ln -s /Applications "$STAGING/Waddly/Applications"
rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "Waddly $VERSION" "$STAGING/Waddly" "$DMG"

printf 'Packaged %s\n' "$DMG"
