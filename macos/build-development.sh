#!/bin/sh
# Builds a second, unmistakably separate app for development and testing.
#
# It carries its own bundle identifier, so it gets its own preferences, its own Input Monitoring
# entry, and its own image folder (see PetImageLocation). Running it therefore cannot touch the
# app installed from Homebrew, and the permission flow starts from "not granted" every time.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUFFIX=${WADDLY_DEVELOPMENT_SUFFIX:-development}
BUNDLE_ID="dev.nyatinte.waddly.$SUFFIX"
NAME="Waddly (development)"
WANTED=${WADDLY_DEVELOPMENT_DIR:-/Applications}
DESTINATION=$WANTED

"$ROOT/macos/build.sh"

WORK="$ROOT/build/$NAME.app"
rm -rf "$WORK"
cp -R "$ROOT/build/Waddly.app" "$WORK"

PLIST="$WORK/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $NAME" "$PLIST"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$WORK"

mkdir -p "$DESTINATION" 2>/dev/null || true
if [ ! -w "$DESTINATION" ]; then
  DESTINATION="$HOME/Applications"
  mkdir -p "$DESTINATION"
  printf 'note: %s is not writable; installing to %s instead\n' "$WANTED" "$DESTINATION" >&2
fi

APP="$DESTINATION/$NAME.app"
rm -rf "$APP"
mv "$WORK" "$APP"

printf 'Installed %s\n' "$APP"
printf 'Bundle identifier: %s\n' "$BUNDLE_ID"
printf 'Reset its state with: mise run dev:reset\n'
