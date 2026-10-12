#!/bin/sh
# Puts the development app back to a first run: no images, no preferences, no permission.
set -eu

SUFFIX=${WADDLY_DEVELOPMENT_SUFFIX:-development}
NAME="Waddly-$SUFFIX"
SUPPORT="$HOME/Library/Application Support"
BUNDLE_ID="dev.nyatinte.waddly.$SUFFIX"

# Quit first and wait for it to be gone: a running app writes its state back on the way out,
# which would undo the deletions below.
osascript -e 'quit app "Waddly (development)"' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  ps aux | grep -F "/Applications/Waddly (development).app" | grep -v grep >/dev/null || break
  sleep 0.5
done

rm -rf "$SUPPORT/$NAME"
# `defaults delete` goes through cfprefsd; removing the file alone leaves a cached copy that the
# next launch would read back.
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"

# Input Monitoring stays granted once it is allowed, so testing the permission flow again means
# clearing that entry. Scoped to the development identifier: the installed app is untouched.
if tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1; then
  printf 'Cleared the Input Monitoring entry for %s.\n' "$BUNDLE_ID"
else
  printf 'note: could not clear the Input Monitoring entry; reset it in System Settings.\n' >&2
fi

printf 'Cleared %s and its preferences.\n' "$SUPPORT/$NAME"
