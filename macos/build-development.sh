#!/bin/sh
# Builds a second, unmistakably separate app for development and testing.
#
# It carries its own bundle identifier, so it gets its own preferences, its own Input Monitoring
# entry, and its own image folder (see PetImageLocation). Running it therefore cannot touch the
# app installed from Homebrew, and the permission flow starts from "not granted" every time.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUFFIX=${WADDLY_DEVELOPMENT_SUFFIX:-development}
# The suffix becomes a folder name and a bundle identifier. Dots are allowed and every suffix keeps
# its own state, but nothing else may end up in a path.
case "$SUFFIX" in
  "" | *[!A-Za-z0-9.-]*)
    printf 'error: WADDLY_DEVELOPMENT_SUFFIX may only contain letters, digits, dots and dashes.\n' >&2
    exit 1
    ;;
esac

BUNDLE_ID="dev.nyatinte.waddly.$SUFFIX"
# Variants have to be able to sit next to each other, so the app name follows the suffix; a fixed
# name meant installing a second variant deleted the first one.
if [ "$SUFFIX" = development ]; then
  NAME="Waddly (development)"
else
  NAME="Waddly ($SUFFIX)"
fi
WANTED=${WADDLY_DEVELOPMENT_DIR:-/Applications}

# The installer and `dev:reset` must agree on where the bundle lives, and a running app reports an
# absolute executable path, so a relative or `~` spelling is resolved once, here.
absolute_dir() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    *)
      if [ -d "$1" ]; then
        (CDPATH= cd -- "$1" && pwd -P)
      else
        printf '%s\n' "$1"
      fi
      ;;
  esac
}

mkdir -p "$WANTED" 2>/dev/null || true
WANTED=$(absolute_dir "$WANTED")
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
