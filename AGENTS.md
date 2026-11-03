# Agent instructions

## Development environment and code placement

Keep changes within the existing Swift 6, AppKit, Apple Silicon, and macOS 14+ setup. Prefer system APIs and avoid adding dependencies.

Keep image models, image import, and image processing in `Sources/WaddlyCore`. Keep the app lifecycle, input monitoring, and UI in `Sources/WaddlyApp`.

## Design

Follow [`DESIGN.md`](DESIGN.md) for all UI work. It defines the shared tokens, the component contracts, and the surface guarantee matrix. Do not add a raw spacing, type, radius, or color value; use or extend the tokens. The Frame Editor follows the same rules as every other surface.

## Privacy

Use key codes only while handling input events to identify Enter. Never store, log, or transmit key codes. Keep imported images on the device.

## Localization and documentation

When adding or changing user-facing strings, update both `macos/ja.lproj/Localizable.strings` and `macos/en.lproj/Localizable.strings`.

Update both `README.md` and `README.ja.md` when a change affects information users need to discover or use a feature, or makes existing setup instructions inaccurate. Keep both accurate and consistent; avoid documenting UI details already clear in the app or implementation details that do not help users.

## Verification

After changing Swift code, run `mise run test` and `mise run build`. Run `mise run check` when full format, lint, test, and build validation is appropriate.
