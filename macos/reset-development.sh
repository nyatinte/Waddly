#!/bin/sh
# Clears the development app's images and preferences so the next launch is a first run.
set -eu

SUFFIX=${WADDLY_DEVELOPMENT_SUFFIX:-development}
SUPPORT="$HOME/Library/Application Support"
# Must match PetImageLocation.directoryName(for:) for a non-shipping bundle identifier.
NAME="Waddly-$SUFFIX"
rm -rf "$SUPPORT/$NAME"
rm -f "$HOME/Library/Preferences/dev.nyatinte.waddly.$SUFFIX.plist"
printf 'Cleared %s and the %s preferences.\n' "$SUPPORT/$NAME" "$SUFFIX"
