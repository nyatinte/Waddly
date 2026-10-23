# Contributing to Waddly

Thanks for your interest in contributing. This guide covers local development and validation.

## Requirements

- Apple Silicon Mac with macOS 14 or later (minimum supported OS; macOS 14 runtime execution is not verified by CI)
- Xcode Command Line Tools with Swift 6
- mise ([install and enable it in your shell](https://mise.jdx.dev/getting-started.html)) for the pinned development and release tools

Trust this repository's mise configuration, then install its pinned tools:

```sh
mise trust
mise install aqua:orhun/git-cliff aqua:realm/SwiftLint github:nicklockwood/SwiftFormat github:moznion/cccc
```

Tool versions are pinned in `mise.toml` and their downloads are locked in `mise.lock`. Run `mise lock` after changing a tool version.

SwiftFormat, SwiftLint, hk, and git-cliff are tooling only and are not included in the Waddly app. git-cliff generates release notes from commit subjects; use `feat:`, `fix:`, and `perf:` prefixes for grouped entries.

## Format and lint

Use mise tasks for the common development commands:

```sh
mise run format       # Format Swift source files
mise run format:check # Check formatting without changing files
mise run lint         # Check localization accessors and run strict SwiftLint
mise run complexity   # Enforce cognitive complexity <= 15 and cyclomatic complexity <= 10 per function
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

hk 2.4.0 currently publishes a macOS arm64 binary only, so this hook setup is available on Apple Silicon. `hk.pkl` runs the pinned SwiftFormat check, the localization accessor check, strict SwiftLint, and the complexity gate when Swift sources or tests change. The complexity limits match CI: no function may exceed cognitive complexity 15 or cyclomatic complexity 10. Run checks without committing with `mise exec -- hk check`, apply available fixes with `mise exec -- hk fix`, and remove the hooks with `mise exec -- hk uninstall`.

## Build and run

```sh
mise run build
open build/Waddly.app
```

### The development app

Testing the setup flow needs an app whose Input Monitoring permission starts ungranted and whose
pet images are separate from the installed copy. `mise run dev:install` builds and installs exactly
that:

```sh
mise run dev:install   # installs /Applications/Waddly (development).app
mise run dev:reset     # clears its images and preferences, back to a first run
```

It uses the bundle identifier `dev.nyatinte.waddly.development`, which gives it its own
preferences, its own Input Monitoring entry, and its own image folder
(`~/Library/Application Support/Waddly-development`, see `PetImageLocation`). Running it therefore
cannot touch the app installed from Homebrew.

macOS keeps an Input Monitoring grant until it is revoked, so `mise run dev:reset` clears that
entry too (scoped to the development identifier). That is what makes the permission flow
repeatable.

`WADDLY_DEVELOPMENT_SUFFIX` keeps several variants side by side: each suffix gets its own bundle
identifier, app name, and image folder (`Waddly-<suffix>`, dots included), so `setup.development` and
`acceptance.development` do not share anything. `mise run dev:reset` takes the same suffix and
refuses to touch state while that variant is still running. `WADDLY_DEVELOPMENT_DIR` changes where
the app is installed.

The build script checks formatting with SwiftFormat, verifies the generated localization accessors, runs SwiftLint in strict mode, builds the arm64 Release app, and creates `build/Waddly.app`. The `mise run check` task runs formatting, lint, complexity checks, the test-completion guard fixture, tests, and this Release build—the full local validation path used by CI. `cccc` may print Swift parser warnings for syntax it cannot fully analyze; investigate these warnings because results for those files can be incomplete.

## Tests

Run the test suite:

```sh
mise run test
```

The script adds the Swift Testing macro plugin path when Command Line Tools install it outside the compiler's default search path. It also fails closed: if a Swift Testing run starts but never reports completion, `./macos/test.sh` exits nonzero even when the test process itself exits 0, so an interrupted run cannot pass as green. `mise run test:guard` proves that guard against a fake `swift` without building the suites.

The tests cover animation phases, image validation and optimization, localization selection, Enter key detection, array reordering, importing and saving the example 3×3 sprite sheet, and pixel-hash snapshots for extracted sprite frames.

AppKit suites run in a real process, so they build the app with `makeTestApp(...)`, which installs the `.invisible` `WindowPresenter`: windows still open, become visible, host sheets, and close as they do in the app, but nothing is drawn. That keeps `mise run test` from painting the pet or the setup wizard over whatever is on screen. Behavior that leaves the app instead—System Settings, Finder, a relaunch—goes through `NSWorkspace` and is not covered by the presenter.

If a deliberate sprite-sheet visual change breaks `spriteSheetExtractionMatchesPixelSnapshots`, run:

```sh
WADDLY_PRINT_SNAPSHOTS=1 ./macos/test.sh --filter spriteSheetExtractionMatchesPixelSnapshots
```

Copy the printed `expectedSpriteSheetSnapshots` value into `Tests/WaddlyCoreTests/PetImageSnapshotTests.swift`, then rerun `./macos/test.sh`.

## Memory profiling

Keep the physical footprint under **100 MB in typical use**. The app is measured as a Release build, not a debug build, and physical footprint is the budget, not RSS or the allocator's live bytes.

Profile the Release app with the same Mac, OS, images, and settings for any before/after comparison. Quit other Waddly instances, run `mise run build`, launch `build/Waddly.app`, and use one PID for the whole run:

```sh
./macos/profile-memory.sh PID launch-idle 30
```

Samples land in `dist/memory/TIMESTAMP-LABEL/` (`rss.csv`, `footprint.txt`, `summary.txt`, `environment.txt`). Measure the states that change image residency: idle after launch, typing, a large import, repeated imports, a return to idle, and a long idle/sleep run. Repeat three runs and compare both the transient peak and the final plateau. For diagnosis, keep the same PID and use `footprint -p PID -f bytes`, `vmmap -summary PID`, and `leaks PID`, or attach Instruments.

Importing a very large sheet (for example 3072 × 3072 with nine frames) exceeds the 100 MB goal today. That is a known 1.0 exception, so revisit the residency policy before raising the image limits or claiming the goal for large images.

`mise run memory:test` runs the separate serialized Release allocator regression suite in `Performance/` on Swift 6.2 and macOS 26+, with dependencies isolated from the macOS 14 production app. Treat a failing allocator budget or a suspected ownership leak as a prompt to profile the process before changing the image pipeline.

## Continuous integration

`.github/workflows/ci.yml` runs on `macos-26` for pull requests, pushes to `main`, and manual dispatches. It installs the locked tools with mise-action and runs `mise run check`, including the complexity gate. The app targets macOS 14, but CI does not verify runtime execution on macOS 14: the macOS 14 runner image provides Xcode 16.2 / Swift 6.0, whose older SDK does not mark `NSImage` as `Sendable`, so the current Swift 6 sources fail to compile there. CI uses a newer SDK on macOS 26; actual runtime support on macOS 14 remains unverified. `.github/workflows/pr-hygiene.yml` requires a screenshot or GIF in the pull request description when a visible UI change is declared.

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

The script writes an arm64 DMG to `dist/`. Release builds are ad-hoc signed and not notarized. Homebrew Casks remove quarantine after install and upgrade, which reduces Gatekeeper protection but does not replace Developer ID signing or notarization. DMGs retain quarantine, so Gatekeeper may block first launch. Verify the DMG and, if needed, approve it in System Settings → Privacy & Security. Do not remove quarantine from a directly downloaded app to bypass Gatekeeper.

## Publish a release for Homebrew

`.github/workflows/release.yml` runs when a `v*` tag is pushed. The tag must match `v` plus `CFBundleShortVersionString` in `macos/Info.plist`, such as `v0.1.0`; any other tag fails the run before anything is published. The workflow runs `./macos/test.sh`, builds and packages the Apple Silicon app, verifies its ad-hoc signature, and publishes a versioned DMG with a SHA-256 file. Release notes are generated by the mise-pinned `git-cliff` tool from commit subjects: `feat`, `fix`, and `perf` commits are grouped, maintenance commits are omitted, and older non-conventional commits appear under Other Changes. Notes compare against the previous stable tag. The release also updates `Casks/waddly.rb` in `nyatinte/homebrew-waddly` with the matching URL and checksum. The generated Cask removes quarantine after installation and upgrade, supports Apple Silicon and macOS 14 or later, and does not delete user data.

To publish a release, create a fine-grained GitHub token restricted to `nyatinte/homebrew-waddly` with Contents read/write permission, then add it to this repository's Actions secrets as `HOMEBREW_TAP_TOKEN`. No Apple signing certificate or notarization credentials are used. Push a tag only after updating the app version in `macos/Info.plist` and merging that change to `main`.

## Project structure

- `Sources/WaddlyCore`: image models, import, and processing
- `Sources/WaddlyApp`: app lifecycle, input monitoring, and UI
- `Tests`: Swift Testing suites for core image and app behavior
- `macos`: localized strings, app metadata, and build/package scripts
- `assets`: the app icon and README examples; pet frames are not bundled

## Contribution notes

- Add or update user-facing strings in both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.
- Update both the English `README.md` and Japanese `README.ja.md` when user-facing behavior or setup instructions change.
- Preserve the input privacy boundary: key codes may be checked transiently to identify Enter, but must not be stored, logged, or transmitted. Keep imported images on-device.
- Keep Swift changes compatible with Swift 6 and macOS 14, and avoid new dependencies unless they are needed.
- By submitting a contribution, you confirm that you have the right to submit it and agree to license code contributions under the repository's MIT License. Do not submit artwork or other third-party material without permission and clear licensing terms.
