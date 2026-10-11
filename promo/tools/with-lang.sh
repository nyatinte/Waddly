#!/usr/bin/env bash
# Run a command with index.html switched to one language, then put it back.
#
#   ./tools/with-lang.sh en -- hyperframes snapshot . --at 1.2 -o snapshots/en
#
# `hyperframes render` accepts --variables, but `snapshot` does not, so both
# paths go through here. One mechanism, one place that touches index.html, and
# a trap that always restores it.
set -euo pipefail

LANG_CODE="${1:-}"
[ -n "$LANG_CODE" ] || { echo "usage: $0 {ja|en} -- <command...>" >&2; exit 2; }
shift
[ "${1:-}" = "--" ] && shift

case "$LANG_CODE" in
  ja | en) ;;
  *) echo "unknown language: $LANG_CODE" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX="$ROOT/index.html"
BACKUP="$(mktemp)"

cleanup() {
  cp "$BACKUP" "$INDEX"
  rm -f "$BACKUP"
}
trap cleanup EXIT

cp "$INDEX" "$BACKUP"
sed -i '' -e "s/\"default\": \"[a-z]*\"/\"default\": \"$LANG_CODE\"/" "$INDEX"
grep -q "\"default\": \"$LANG_CODE\"" "$INDEX" || { echo "could not select $LANG_CODE" >&2; exit 1; }

cd "$ROOT"
"$@"
