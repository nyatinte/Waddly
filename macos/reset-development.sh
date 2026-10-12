#!/bin/sh
# Puts the development app back to a first run: no images, no preferences, no permission.
set -eu

SUFFIX=${WADDLY_DEVELOPMENT_SUFFIX:-development}
# The suffix becomes a folder name and a bundle identifier. Dots are allowed, and every suffix gets
# its own name and state, but nothing else may end up in a path we delete below.
case "$SUFFIX" in
  "" | *[!A-Za-z0-9.-]*)
    printf 'error: WADDLY_DEVELOPMENT_SUFFIX may only contain letters, digits, dots and dashes.\n' >&2
    exit 1
    ;;
esac

BUNDLE_ID="dev.nyatinte.waddly.$SUFFIX"
# Mirrors build-development.sh: the app name follows the suffix, so variants are reset one at a time
# instead of whichever bundle happens to carry the default name.
if [ "$SUFFIX" = development ]; then
  NAME="Waddly (development)"
else
  NAME="Waddly ($SUFFIX)"
fi

SUPPORT="$HOME/Library/Application Support"
# Matches PetImageLocation: the whole suffix after the shipping identifier.
STATE_DIR="$SUPPORT/Waddly-$SUFFIX"
WANTED=${WADDLY_DEVELOPMENT_DIR:-/Applications}

# The process is matched by its path rather than by name, so a custom installation directory is
# covered and a differently named variant is not caught by mistake. Both directories the installer
# can use are checked, and each path is quoted: they contain a space and a parenthesis.
running_pids() {
  ps -Ao pid=,command= | while read -r pid command; do
    for app in "$WANTED/$NAME.app" "$HOME/Applications/$NAME.app"; do
      # An app's command line starts with its own executable, so this cannot pick up an unrelated
      # process that merely mentions the path.
      case "$command" in
        "$app/Contents/MacOS/"*) printf '%s\n' "$pid" ;;
      esac
    done
  done
}

# Quit first and wait for it: a running app writes its state back on the way out, which would undo
# the deletions below.
if [ -n "$(running_pids)" ]; then
  osascript -e "quit app \"$NAME\"" >/dev/null 2>&1 || true
  waited=0
  while [ -n "$(running_pids)" ] && [ "$waited" -lt 20 ]; do
    sleep 0.5
    waited=$((waited + 1))
  done
fi

# Deleting the state of a live app would only look like it worked.
live=$(running_pids)
if [ -n "$live" ]; then
  printf 'error: %s is still running (pid %s). Quit it and run this again; nothing was deleted.\n' \
    "$NAME" "$live" >&2
  exit 1
fi

rm -rf "$STATE_DIR"
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

printf 'Cleared %s and its preferences.\n' "$STATE_DIR"
