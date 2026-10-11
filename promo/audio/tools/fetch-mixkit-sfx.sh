#!/usr/bin/env bash
# Re-download the Mixkit sound effects used by the Waddly promo.
#
#   audio/sfx/mixkit-manifest.json  ->  audio/sfx/<slug>.wav
#
# The WAVs are not committed (30 MB). Mixkit's Sound Effects Free License allows
# use in the video, but not redistribution of the sound files themselves, so they
# stay out of the repository and are fetched on demand.
#
# License: https://mixkit.co/license/#sfxFree
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/audio/sfx/mixkit-manifest.json"
DEST="$ROOT/audio/sfx"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0 Safari/537.36"

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }

fail=0
fetch() {
  local slug="$1" id="$2"
  local out="$DEST/$slug.wav"
  if [ -s "$out" ] && [ "$(stat -f%z "$out")" -gt 20000 ]; then
    echo "  ok       $slug"
    return
  fi
  curl -fsSL --max-time 90 -A "$UA" -e "https://mixkit.co/" -o "$out" \
    "https://assets.mixkit.co/active_storage/sfx/$id/$id.wav" || {
      echo "  FAILED   $slug (id $id)" >&2
      rm -f "$out"
      fail=1
      return
    }
  echo "  fetched  $slug ($(du -h "$out" | cut -f1))"
}

echo "Mixkit sound effects -> $DEST"
while IFS=$'\t' read -r slug id; do
  [ -n "$slug" ] && fetch "$slug" "$id"
done < <(python3 -c "
import json,sys
for e in json.load(open('$MANIFEST')):
    print(e['slug'] + '\t' + e['id'])
")
if [ "$fail" -ne 0 ]; then
  echo >&2
  echo "Some sounds could not be downloaded. A few Mixkit assets are premium-only" >&2
  echo "and return 403 for the .wav; the -preview.mp3 for those still works." >&2
  exit 1
fi
echo "done — $(ls "$DEST"/*.wav | wc -l | tr -d ' ') files"
