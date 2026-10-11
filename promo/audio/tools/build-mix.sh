#!/usr/bin/env bash
# Build the promo audio mix: BGM window + every SFX cue, mastered to -14 LUFS.
#
#   ./tools/build-mix.sh
#
# The key schedule is read straight out of the composition, so re-running after
# a timing change keeps the clicks on the picture. Requires ffmpeg, node and a
# numpy-enabled python (override with PYTHON=/path/to/python3).
set -euo pipefail

CUT="${1:-30}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIO="$ROOT/audio"
BGMSRC="${BGMSRC:-$HOME/Downloads/Magical Motif.m4a}"
NODE="${NODE:-node}"
PYTHON="${PYTHON:-python3}"

case "$CUT" in
  30)
    # tools/analyse-bgm.py 30: the section that rises towards the Return finale
    START=92.4587; DUR=30; FADE_OUT=29.4; STORY=scripts/story.js; MIXER=tools/mix-30s.py
    BGM=bgm/magical-motif-30s.wav; KEYS=keytimes-30s.json; RAW=mix-30s-raw.wav; OUT=mix-30s.wav
    ;;
  *)
    echo "usage: $0 [30]" >&2; exit 2 ;;
esac

cd "$AUDIO"

if [ ! -f "$BGM" ]; then
  [ -f bgm/magical-motif.m4a ] || cp "$BGMSRC" bgm/magical-motif.m4a
  echo "→ extracting the ${DUR}s BGM window from ${START}s"
  ffmpeg -v error -y -ss "$START" -t "$DUR" -i bgm/magical-motif.m4a \
    -af "afade=t=in:st=0:d=0.25,afade=t=out:st=$FADE_OUT:d=0.6,loudnorm=I=-20:TP=-2:LRA=11" \
    -ar 48000 -ac 2 -c:a pcm_s16le "$BGM"
fi

echo "→ reading the key schedule from $STORY"
"$NODE" tools/extract-keys.cjs "$STORY" > "$KEYS"
echo "   $(grep -o ',' "$KEYS" | wc -l | tr -d ' ') keys"

echo "→ mixing"
"$PYTHON" "$MIXER" "$KEYS" "$BGM" "$RAW"

echo "→ mastering to -14 LUFS"
MEASURED="$(ffmpeg -hide_banner -nostats -i "$RAW" \
  -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | tail -n 30)"

field() { echo "$MEASURED" | sed -n "s/.*\"$1\" *: *\"\{0,1\}\([-0-9.]*\)\"\{0,1\}.*/\1/p" | head -1; }
I="$(field input_i)"; TP="$(field input_tp)"; LRA="$(field input_lra)"
TH="$(field input_thresh)"; OFF="$(field target_offset)"

ffmpeg -v error -y -i "$RAW" \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true" \
  -ar 48000 -ac 2 -c:a pcm_s16le "$OUT"

ffmpeg -hide_banner -nostats -i "$OUT" -af ebur128 -f null - 2>&1 | grep -A3 "Integrated loudness" | head -4
echo "wrote audio/$OUT"
