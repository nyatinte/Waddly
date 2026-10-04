#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Waddly.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/macos/Info.plist")

if ! command -v mise >/dev/null 2>&1; then
  printf 'mise is required for the pinned development tools. See CONTRIBUTING.md for setup instructions.\n' >&2
  exit 1
fi

(
  cd "$ROOT"
  mise exec github:nicklockwood/SwiftFormat -- swiftformat Sources Tests Package.swift Tools --lint
  swift Tools/generate_localizations.swift --check
  TOOLCHAIN_DIR="$(xcode-select -p)" mise exec aqua:realm/SwiftLint -- swiftlint lint --strict Sources Tests macos Package.swift Tools
)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/prompts"

swift build --package-path "$ROOT" --configuration release --product Waddly
cp "$ROOT/.build/release/Waddly" "$APP/Contents/MacOS/Waddly"

cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/macos/en.lproj" "$ROOT/macos/ja.lproj" "$APP/Contents/Resources/"
cp "$ROOT"/prompts/*.md "$APP/Contents/Resources/prompts/"
# Remove the SVG tracing canvas and draw white fills before black details.
sed 's/M 0 0 L 1254 0 L 1254 1254 L 0 1254 L 0 0 Z //' "$ROOT/assets/waddly-menubar.svg" \
  | awk '
    /^<svg / { header = $0; next }
    /^<\/svg>/ { footer = $0; next }
    /^<path fill="rgb\(254,253,254\)"/ { white[++whiteCount] = $0; next }
    /^<path fill="rgb\(17,17,17\)"/ { black[++blackCount] = $0; next }
    /^<path / { other[++otherCount] = $0; next }
    END {
      print header
      for (i = 1; i <= whiteCount; i++) print white[i]
      for (i = 1; i <= blackCount; i++) print black[i]
      for (i = 1; i <= otherCount; i++) print other[i]
      print footer
    }' > "$APP/Contents/Resources/waddly-menubar.svg"

ICONSET="$APP/Contents/Resources/Waddly.iconset"
mkdir -p "$ICONSET"
make_icon_size() {
  sips -z "$2" "$2" "$ROOT/assets/waddly-app-icon.png" --out "$ICONSET/$1" >/dev/null
}
make_icon_size icon_16x16.png 16
make_icon_size icon_16x16@2x.png 32
make_icon_size icon_32x32.png 32
make_icon_size icon_32x32@2x.png 64
make_icon_size icon_128x128.png 128
make_icon_size icon_128x128@2x.png 256
make_icon_size icon_256x256.png 256
make_icon_size icon_256x256@2x.png 512
make_icon_size icon_512x512.png 512
make_icon_size icon_512x512@2x.png 1024
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Waddly.icns"
rm -rf "$ICONSET"

if [ -n "${WADDLY_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$WADDLY_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi

printf 'Built %s\n' "$APP"
