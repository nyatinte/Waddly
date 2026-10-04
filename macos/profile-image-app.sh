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
  git -C "$ROOT" archive "$REVISION" Sources macos | tar -x -C "$TEMP"
  LABEL=$(git -C "$ROOT" rev-parse --short "$REVISION")
else
  cp -R "$ROOT/Sources" "$ROOT/macos" "$TEMP/"
  LABEL=working-tree
fi
mkdir -p "$TEMP/core" "$ROOT/dist/memory"
APP="$TEMP/WaddlyMemoryProbe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TEMP/macos/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.nyatinte.waddly.memoryprobe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable WaddlyMemoryProbe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Waddly Memory Probe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Waddly Memory Probe' "$APP/Contents/Info.plist"
cp -R "$TEMP/macos/en.lproj" "$TEMP/macos/ja.lproj" "$APP/Contents/Resources/"
swiftc -O -swift-version 6 -emit-module -emit-library -static -module-name WaddlyCore \
  "$TEMP"/Sources/WaddlyCore/*.swift -o "$TEMP/core/libWaddlyCore.a" \
  -emit-module-path "$TEMP/core/WaddlyCore.swiftmodule"
rm "$TEMP/Sources/WaddlyApp/AppMain.swift"
swiftc -O -swift-version 6 -I "$TEMP/core" -L "$TEMP/core" -lWaddlyCore \
  "$TEMP"/Sources/WaddlyApp/*.swift "$ROOT/Tools/profile_image_app.swift" \
  -o "$APP/Contents/MacOS/WaddlyMemoryProbe"
swiftc -O -swift-version 6 "$TEMP"/Sources/WaddlyCore/PetImageCore.swift \
  "$ROOT/Tools/profile_image_pipeline.swift" -o "$TEMP/fixture"
"$TEMP/fixture" "$TEMP/source.png"
OUTPUT="$ROOT/dist/memory/image-app-$LABEL-$(date -u +%Y%m%dT%H%M%SZ).csv"
"$APP/Contents/MacOS/WaddlyMemoryProbe" "$TEMP/source.png" "$TEMP/images" > "$OUTPUT"
awk -F, 'NR > 1 { if ($3 > peak) peak = $3; final = $2 } END { printf "Peak physical footprint %.2f MiB, final physical footprint %.2f MiB\n", peak/1048576, final/1048576 }' "$OUTPUT"
printf 'Measurements: %s\n' "$OUTPUT"
