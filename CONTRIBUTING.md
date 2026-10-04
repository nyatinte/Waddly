# Contributing to Waddly

Thanks for your interest in contributing. This guide covers local development and validation.

## Requirements

- Apple Silicon Mac with macOS 14 or later
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

Use mise tasks for the common development commands:

```sh
mise run format       # Format Swift source files
mise run format:check # Check formatting without changing files
mise run lint         # Check localization accessors and run strict SwiftLint
```

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
mise run build
open build/Waddly.app
```

The build script checks formatting with SwiftFormat, verifies the generated localization accessors, runs SwiftLint in strict mode, builds the arm64 Release app, and creates `build/Waddly.app`. The `mise run check` task runs formatting, lint, tests, and this Release build—the full local validation path used by CI.

## Tests

Run the test suite:

```sh
mise run test
```

The script adds the Swift Testing macro plugin path when Command Line Tools install it outside the compiler's default search path.

The tests cover animation phases, image validation and optimization, localization selection, Enter key detection, array reordering, importing and saving the example 3×3 sprite sheet, and pixel-hash snapshots for extracted sprite frames.

If a deliberate sprite-sheet visual change breaks `spriteSheetExtractionMatchesPixelSnapshots`, run:

```sh
WADDLY_PRINT_SNAPSHOTS=1 swift test --filter spriteSheetExtractionMatchesPixelSnapshots
```

Copy the printed `expectedSpriteSheetSnapshots` value into `Tests/WaddlyCoreTests/PetImageSnapshotTests.swift`, then rerun `./macos/test.sh`.

## Continuous integration

`.github/workflows/ci.yml` runs on `macos-26` for pull requests targeting `main`, pushes to `main`, and manual dispatches. It installs the locked tools with mise-action, then runs `mise run check`. `.github/workflows/pr-hygiene.yml` requires a screenshot or GIF in the pull request description when a visible UI change is declared.

## Localization keys

Add each localization key to both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`, then regenerate the typed accessors from the repository root:

```sh
swift Tools/generate_localizations.swift
```

The generator checks that both languages have matching keys and writes `Sources/WaddlyApp/LocalizationKey.generated.swift`. `./macos/build.sh` checks that the generated file is current.

## Create a DMG

```sh
mise run package
```

The script writes an arm64 DMG to `dist/`. By design, release builds are ad-hoc signed and not notarized. Gatekeeper may require the user to approve the app on first launch; verify the download and use Finder's Open confirmation or System Settings → Privacy & Security. Do not bypass Gatekeeper by removing quarantine attributes.

## Publish a release for Homebrew

`.github/workflows/release.yml` runs when a `v*` tag is pushed. A stable tag such as `v0.1.0` must match `CFBundleShortVersionString` in `macos/Info.plist`; a beta tag such as `v0.1.0-beta.1` publishes a GitHub prerelease and skips the Tap update. Both channels run `./macos/test.sh`, build and package the Apple Silicon app, verify its ad-hoc signature, and publish a versioned DMG with a SHA-256 file. Stable releases also update `Casks/waddly.rb` in `nyatinte/homebrew-waddly` with the matching URL and checksum. The Cask supports Apple Silicon and macOS 14 or later; it does not remove quarantine or delete user data.

Before the first stable release, create a fine-grained GitHub token restricted to `nyatinte/homebrew-waddly` with Contents read/write permission, then add it to this repository's Actions secrets as `HOMEBREW_TAP_TOKEN`. Beta releases do not need this token. No Apple signing certificate or notarization credentials are used. Push a tag only after updating the app version in `macos/Info.plist` and merging that change to `main`.

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
