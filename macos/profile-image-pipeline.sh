#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [BASELINE_REVISION]\n' "$0" >&2
  exit 1
fi
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
if [ "$#" -eq 1 ]; then
  REVISION=$(git -C "$ROOT" rev-parse --verify --end-of-options "$1^{commit}")
  git -C "$ROOT" show "$REVISION:Sources/WaddlyCore/PetImageCore.swift" > "$TEMP/Core.swift"
  LABEL=$(git -C "$ROOT" rev-parse --short "$REVISION")
else
  cp "$ROOT/Sources/WaddlyCore/PetImageCore.swift" "$TEMP/Core.swift"
  LABEL=working-tree
fi
mkdir -p "$ROOT/dist/memory"
OUTPUT="$ROOT/dist/memory/image-pipeline-$LABEL-$(date -u +%Y%m%dT%H%M%SZ).csv"
# The historical preview was NSImage(data:) before the thumbnail API existed.
if rg -q 'public static func preview' "$TEMP/Core.swift"; then
  swiftc -O -swift-version 6 "$TEMP/Core.swift" "$ROOT/Tools/profile_image_pipeline.swift" -o "$TEMP/probe"
else
  swiftc -O -swift-version 6 -D LEGACY "$TEMP/Core.swift" "$ROOT/Tools/profile_image_pipeline.swift" -o "$TEMP/probe"
fi
"$TEMP/probe" > "$OUTPUT"
awk -F, 'NR > 1 { if ($4 > rss) rss = $4; if ($5 > physical) physical = $5; final = $3 } END { printf "Peak RSS %.2f MiB, peak physical footprint %.2f MiB, final physical footprint %.2f MiB\n", rss/1048576, physical/1048576, final/1048576 }' "$OUTPUT"
printf 'Measurements: %s\n' "$OUTPUT"
