# Contributing to Waddly

Thanks for your interest in contributing. This guide covers local development and validation.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift 6
- mise ([install and enable it in your shell](https://mise.jdx.dev/getting-started.html)) for the pinned SwiftFormat and SwiftLint development tools

Trust this repository's mise configuration, then install its pinned tools:

```sh
mise trust
mise install aqua:realm/SwiftLint github:nicklockwood/SwiftFormat
```

Tool versions are pinned in `mise.toml` and their downloads are locked in `mise.lock`. Run `mise lock` after changing a tool version.

SwiftFormat and SwiftLint are development-only tools and are not included in the Waddly app.

## Format and lint

Format Swift source files with the version pinned in `mise.toml`:

```sh
mise exec github:nicklockwood/SwiftFormat -- swiftformat Sources Tests Package.swift Tools
```

Check formatting without changing files:

```sh
mise exec github:nicklockwood/SwiftFormat -- swiftformat Sources Tests Package.swift Tools --lint
```

SwiftFormat handles formatting; SwiftLint continues to handle lint rules.

## Git hooks

The commit hook runs through [hk](https://hk.jdx.dev), which is pinned in `mise.toml`:

```sh
mise install hk
mise exec -- hk install
```

hk 2.4.0 currently publishes a macOS arm64 binary only, so this hook setup is available on Apple Silicon. `hk.pkl` runs the pinned SwiftFormat check, the localization accessor check, and strict SwiftLint before a commit. These are the checks `./macos/build.sh` performs before it compiles, so a change that would fail the build is reported at commit time. Run them without committing with `mise exec -- hk check`, apply fixes with `mise exec -- hk fix`, and remove the hooks with `mise exec -- hk uninstall`.

## Build and run

```sh
./macos/build.sh
open build/Waddly.app
```

The build script checks formatting with SwiftFormat, verifies the generated localization accessors, runs SwiftLint in strict mode, builds the Release app for the host Mac's CPU architecture, and creates `build/Waddly.app`.

## Tests

Run the test suite:

```sh
swift test
```

The tests cover animation phases, image validation and optimization, localization selection, Enter key detection, array reordering, and importing and saving the example 3×3 sprite sheet.

## Continuous integration

`.github/workflows/ci.yml` runs on `macos-26` for pull requests targeting `main`, pushes to `main`, and manual dispatches. It installs the locked tools with mise-action, then runs `hk check --all`, `./macos/build.sh`, and `swift test`. `.github/workflows/pr-hygiene.yml` requires a screenshot or GIF in the pull request description when a visible UI change is declared.

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
- `Tests`: Swift Testing suites for core image and app behavior
- `macos`: localized strings, app metadata, and build/package scripts
- `assets`: the app icon and README examples; pet frames are not bundled

## Contribution notes

- Add or update user-facing strings in both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.
- Update both `README.md` and `README.en.md` when user-facing behavior or setup instructions change.
- Preserve the input privacy boundary: key codes may be checked transiently to identify Enter, but must not be stored, logged, or transmitted. Keep imported images on-device.
- Keep Swift changes compatible with Swift 6 and macOS 14, and avoid new dependencies unless they are needed.
