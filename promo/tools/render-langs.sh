#!/usr/bin/env bash
# Render both languages and lay the mastered audio under each.
#
#   ./tools/render-langs.sh          # ja and en
#   ./tools/render-langs.sh en       # one of them
#
# Both languages are the same 30 second film, so they share audio/mix-30s.wav
# (prepare it with ./audio/tools/build-mix.sh). Only the strings differ, which is
# why the two renders are the same length to the frame. npm scripts resolve the
# project's pinned HyperFrames version without a global install.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUDIO=audio/mix-30s.wav
[ -f "$AUDIO" ] || { echo "missing $AUDIO — run ./audio/tools/build-mix.sh" >&2; exit 1; }

LANGS=("$@")
[ "${#LANGS[@]}" -gt 0 ] || LANGS=(ja en)

for LANG_CODE in "${LANGS[@]}"; do
  case "$LANG_CODE" in
    ja | en) ;;
    *) echo "usage: $0 [ja|en ...]" >&2; exit 2 ;;
  esac

  VIDEO="out/_${LANG_CODE}-video.mp4"
  FINAL="out/waddly-promo-${LANG_CODE}-1920x1080-60fps.mp4"

  echo "→ rendering the '$LANG_CODE' cut"
  ./tools/with-lang.sh "$LANG_CODE" -- \
    npm run render -- . -f 60 -q looks --variables "{\"lang\":\"$LANG_CODE\"}" -o "$VIDEO"

  echo "→ muxing $AUDIO"
  ffmpeg -v error -y -i "$VIDEO" -i "$AUDIO" \
    -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -movflags +faststart "$FINAL"
  rm -f "$VIDEO"

  echo "→ $FINAL"
  ffprobe -v error -show_entries format=duration,size \
    -show_entries stream=codec_name,width,height,r_frame_rate,channels,sample_rate \
    -of default=noprint_wrappers=1 "$FINAL"
done
