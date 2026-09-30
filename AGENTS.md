# Agent instructions

- Keep changes within the existing Swift 6, AppKit, and macOS 13+ setup; prefer system APIs and avoid new dependencies.
- Keep image models, import, and processing in `Sources/WaddlyCore`; keep app lifecycle, input monitoring, and UI in `Sources/WaddlyApp`.
- Preserve the privacy boundary: use key codes only while handling input events to identify Enter; never persist, log, or transmit them. Keep imported images on-device.
- Add or change user-facing strings in both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.
- Run `./macos/build.sh` after Swift changes. It runs strict SwiftLint and creates the Release app. Run `build/Waddly.app/Contents/MacOS/Waddly --self-test` to check core image and animation behavior.
- Update `README.md` and `README.en.md` when user-visible behavior or setup instructions change.
