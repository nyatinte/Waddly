#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  printf 'Usage: %s PID LABEL [SECONDS=30]\n' "$0" >&2
  exit 1
fi
PID="$1"
LABEL="$2"
SECONDS_TO_SAMPLE="${3:-30}"
case "$PID:$SECONDS_TO_SAMPLE" in
  *[!0-9:]* | :* | *:) printf 'PID and duration must be positive integers.\n' >&2; exit 1 ;;
esac
if [ "$PID" -eq 0 ] || [ "$SECONDS_TO_SAMPLE" -eq 0 ]; then
  printf 'PID and duration must be positive integers.\n' >&2
  exit 1
fi
case "$LABEL" in
  '' | *[!a-zA-Z0-9_-]*) printf 'Label must contain only letters, numbers, underscores, and hyphens.\n' >&2; exit 1 ;;
esac
if ! ps -p "$PID" -o pid= >/dev/null; then
  printf 'Process %s does not exist.\n' "$PID" >&2
  exit 1
fi
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT="$ROOT/dist/memory/$(date -u +%Y%m%dT%H%M%SZ)-$LABEL"
mkdir -p "$OUTPUT"
{
  sw_vers
  uname -m
  git -C "$ROOT" rev-parse HEAD
  ps -p "$PID" -o pid=,etime=,command=
  printf 'duration_seconds=%s\n' "$SECONDS_TO_SAMPLE"
} > "$OUTPUT/environment.txt"
printf 'utc,rss_kib\n' > "$OUTPUT/rss.csv"
# A permission failure is retained in the log; RSS still remains available.
footprint -p "$PID" -f bytes --sample 1 --sample-duration "$SECONDS_TO_SAMPLE" \
  > "$OUTPUT/footprint.txt" 2>&1 &
FOOTPRINT_PID=$!
trap 'kill "$FOOTPRINT_PID" 2>/dev/null || true' EXIT HUP INT TERM
ELAPSED=0
while [ "$ELAPSED" -lt "$SECONDS_TO_SAMPLE" ]; do
  RSS=$(ps -p "$PID" -o rss= | tr -d ' ')
  if [ -z "$RSS" ]; then
    printf 'Process %s exited during sampling.\n' "$PID" >&2
    break
  fi
  printf '%s,%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RSS" >> "$OUTPUT/rss.csv"
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done
wait "$FOOTPRINT_PID" || printf 'footprint failed; see %s/footprint.txt\n' "$OUTPUT" >&2
awk -F, 'NR > 1 { sum += $2; count++; if ($2 > peak) peak = $2 } END { if (count) printf "RSS mean %.2f MiB, peak %.2f MiB (%d samples)\n", sum/count/1024, peak/1024, count }' \
  "$OUTPUT/rss.csv" | tee "$OUTPUT/summary.txt"
printf 'Measurements: %s\n' "$OUTPUT"
