#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/build/Waddly.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/macos/Info.plist")

if ! command -v swiftlint >/dev/null 2>&1; then
  printf 'SwiftLint is required. Install it with: brew install swiftlint\n' >&2
  exit 1
fi

(
  cd "$ROOT"
  TOOLCHAIN_DIR="$(xcode-select -p)" swiftlint lint --strict Sources macos Package.swift
)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/prompts"

swift build --package-path "$ROOT" --configuration release --product Waddly
cp "$ROOT/.build/release/Waddly" "$APP/Contents/MacOS/Waddly"

cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/macos/en.lproj" "$ROOT/macos/ja.lproj" "$APP/Contents/Resources/"
cp "$ROOT"/prompts/*.md "$APP/Contents/Resources/prompts/"

if [ -n "${WADDLY_SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$WADDLY_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi

printf 'Built %s\n' "$APP"
