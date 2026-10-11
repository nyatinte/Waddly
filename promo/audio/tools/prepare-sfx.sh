#!/usr/bin/env bash
# Turn the raw downloads into a sync-ready sound library.
#
#   audio/sfx/       raw, exactly as downloaded (kept for provenance)
#   audio/sfx-norm/  leading silence trimmed, peak-normalised, faded out
#
# Why this matters:
#   * `key-single.wav` peaks at -18.9 dBFS and `whoosh-fly.wav` at -9.9 dBFS,
#     while most others sit near -1 dBFS. Without normalising, the levels in
#     CUE-SHEET.md would be meaningless — the key clicks would vanish.
#   * Several files carry leading silence. Triggering them on the frame of a key
#     press would land audibly late, so the head is trimmed to the transient.
#
# Target peak: -3 dBFS (standard for a short-transient SFX library).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/audio/sfx"
DEST="$ROOT/audio/sfx-norm"
TARGET_PEAK=-3.0

mkdir -p "$DEST"

# Trim silence, then measure the peak of the trimmed result.
trim() {
  ffmpeg -y -v error -i "$1" -af \
    "silenceremove=start_periods=1:start_silence=0.004:start_threshold=-55dB:detection=peak,\
areverse,\
silenceremove=start_periods=1:start_silence=0.03:start_threshold=-55dB:detection=peak,\
areverse" \
    -c:a pcm_s16le "$2"
}

peak_db() {
  ffmpeg -hide_banner -nostats -i "$1" -af astats=metadata=1:reset=0 -f null - 2>&1 \
    | grep "Peak level dB" | tail -1 | sed 's/.*: //'
}

printf "%-20s %9s %9s %9s %8s\n" file peak_in peak_out gain dur
for f in "$SRC"/*.wav; do
  base="$(basename "$f")"
  tmp="$(mktemp -t sfx).wav"
  out="$DEST/$base"

  trim "$f" "$tmp"
  pin="$(peak_db "$tmp")"
  gain="$(python3 -c "print(round($TARGET_PEAK - ($pin), 2))")"

  # last 30 ms fade-out so a hard cut never clicks
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmp")"
  fade="$(python3 -c "d=$dur; print(f'{max(0.0, d-0.03):.3f}')")"

  ffmpeg -y -v error -i "$tmp" \
    -af "volume=${gain}dB,afade=t=out:st=${fade}:d=0.03" \
    -c:a pcm_s16le -ar 48000 "$out"

  pout="$(peak_db "$out")"
  printf "%-20s %9.2f %9.2f %9.2f %8.3f\n" "${base%.wav}" "$pin" "$pout" "$gain" "$dur"
  rm -f "$tmp"
done

echo
echo "normalised $(ls "$DEST"/*.wav | wc -l | tr -d ' ') files -> $DEST"
