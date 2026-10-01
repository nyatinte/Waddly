# Contributing to Waddly

Thanks for your interest in contributing. This guide covers local development and validation.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 6
- SwiftLint (`brew install swiftlint`)

The Homebrew installation method for Waddly itself is planned; Homebrew is currently used here only to install the SwiftLint development tool.

## Build and run

```sh
./macos/build.sh
open build/Waddly.app
```

The build script runs strict SwiftLint checks, builds the Release app for the host Mac's CPU architecture, and creates `build/Waddly.app`.

## Tests

Run the app's self-tests after building:

```sh
build/Waddly.app/Contents/MacOS/Waddly --self-test
build/Waddly.app/Contents/MacOS/Waddly --self-test-sprite-sheet assets/examples/nyatinte-bot-3x3.png
```

The tests cover animation phases, image validation and optimization, and importing and saving the example 3×3 sprite sheet.

## Localization keys

Add each localization key to both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`, then regenerate the typed accessors from the repository root:

```sh
swift Tools/generate_localizations.swift
```

The generator checks that both languages have matching keys and writes `Sources/WaddlyApp/LocalizationKey.generated.swift`. `./macos/build.sh` checks that the generated file is current.

## Create a DMG

```sh
./macos/package.sh
```

The script writes an architecture-specific DMG to `dist/`. The default build is ad-hoc signed and is not notarized. Internet distribution without Gatekeeper warnings requires Developer ID signing and Apple notarization. Set `WADDLY_SIGN_IDENTITY` to select a signing identity.

## Project structure

- `Sources/WaddlyCore`: image models, import, and processing
- `Sources/WaddlyApp`: app lifecycle, input monitoring, and UI
- `macos`: localized strings, app metadata, and build/package scripts
- `assets`: the app icon and README examples; pet frames are not bundled

## Contribution notes

- Add or update user-facing strings in both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.
- Update both `README.md` and `README.en.md` when user-facing behavior or setup instructions change.
- Preserve the input privacy boundary: key codes may be checked transiently to identify Enter, but must not be stored, logged, or transmitted. Keep imported images on-device.
- Keep Swift changes compatible with Swift 6 and macOS 13, and avoid new dependencies unless they are needed.
