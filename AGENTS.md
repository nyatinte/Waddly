# Agent instructions

## Development environment and code placement

Keep changes within the existing Swift 6, AppKit, and macOS 13+ setup. Prefer system APIs and avoid adding dependencies.

Keep image models, image import, and image processing in `Sources/WaddlyCore`. Keep the app lifecycle, input monitoring, and UI in `Sources/WaddlyApp`.

## Privacy

Use key codes only while handling input events to identify Enter. Never store, log, or transmit key codes. Keep imported images on the device.

## Localization and documentation

When adding or changing user-facing strings, update both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.

When user-visible behavior or setup instructions change, update both `README.md` and `README.en.md`.

## Verification

After changing Swift code, run the test suite with `swift test` and build with `./macos/build.sh`. The build script runs strict SwiftLint checks and creates the Release app.
