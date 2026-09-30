# Waddly

<p align="center">
  <img src="assets/waddly-app-icon.png" alt="Waddly app icon" width="160">
</p>

A lightweight macOS desktop companion that lets your pet live on your desktop. Desktop pet images are not bundled; add your own during setup. The app icon uses the author's penguin artwork, and the pet stays hidden until an image is registered.

[日本語 README](README.md)

## Features

- Reacts to key-down events without storing typed text or key codes.
- Breathes subtly and blinks while idle. Toggle breathing from the menu. The pet falls asleep after a while and stops animating after five minutes; Input Monitoring remains active so it can wake up.
- Drag the pet around the desktop; its position is saved. Choose Small, Medium, or Large.
- The UI follows the preferred macOS language (Japanese or English) and falls back to English for other languages. Choose **Language** from the menu to follow System Settings, use Japanese, or use English. Restart Waddly to apply a change.
- Waddly appears in both the Dock and menu bar; choose where it appears from the “Show in” menu (at least one remains visible). Click the custom W icon or right-click the pet to open the menu. Change size and typing motion, configure pet images, pause reactions, or configure launch at login.
- On first launch, a setup wizard walks through the image-generation prompt, required 3×3 PNG import, and Input Monitoring permission. Drop a PNG anywhere on the image page; a custom image is required to continue. Reopen it from the menu at any time.
- Built with Swift, AppKit, Core Graphics, and Core Animation. No third-party libraries.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 6
- SwiftLint for strict linting during development builds (`brew install swiftlint`)
- The build script targets the CPU architecture of the Mac running it

## Build and run

```sh
./macos/build.sh
open build/Waddly.app
```

Swift Package Manager builds two modules: `WaddlyCore` for image data and import processing, and `WaddlyApp` for the application and UI.

To install it, copy `Waddly.app` to `~/Applications`, or open the DMG in `dist/` and drag the app to its `Applications` shortcut.

On first launch, allow Waddly under **System Settings → Privacy & Security → Input Monitoring**. The app still launches without this permission but will not react to key input. The menu bar icon's tooltip indicates when permission is required.

Create a distributable disk image with:

```sh
./macos/package.sh
```

The script writes `Waddly-0.1.0-macos-<architecture>.dmg` to `dist/`. No Developer ID signing identity is installed on the build machine, so the default build is ad-hoc signed with a bundle-ID-based designated requirement and is not notarized. This keeps the local Input Monitoring identity stable across rebuilds. Developer ID signing and Apple notarization are required to avoid Gatekeeper warnings when distributing over the internet. Set `WADDLY_SIGN_IDENTITY` to select a signing identity.

## Use your own pet

### Image processing

Setup imports a transparent 3×3 PNG sprite sheet. The example below shows a reference image and the corresponding nine-cell sheet that Waddly splits during import.

| Reference image | 3×3 sprite sheet |
| --- | --- |
| ![nyatinte-bot reference image](assets/examples/nyatinte-bot.png) | ![nyatinte-bot 3×3 transparent sprite sheet](assets/examples/nyatinte-bot-3x3.png) |

For the README, the reference image is reduced to 384 × 384 px and the sprite sheet to 768 × 768 px.

Waddly validates the PNG format, transparency, square shape, and dimensions divisible by 3. Files must be at most 20 MB and 4096 px per side. The sheet is split into nine equal cells: cells 1–2 are Idle, 3–6 Typing, 7 Enter, and 8–9 Sleep. Sheets longer than 3072 px on a side are downsampled to 3072 px before splitting.

Choose **Pet images…** from the menu to add transparent PNGs to the Idle, Typing, Sleep, and Enter rows. Individual images are downsampled to a maximum side of 1024 px. Idle uses the first image as its normal pose and the rest as blink variants. Typing and Enter images play in order. Sleep images cycle and stop on the last image after five minutes.

The app stores each frame locally as a PNG in Application Support and restores it at the next launch. It does not modify the selected source file or upload images. Pet frames and sample artwork are not included in the app bundle; the separate app icon image is.

The image-generation prompts are in [`prompts/ja.md`](prompts/ja.md) and [`prompts/en.md`](prompts/en.md). They leave transparent padding around each pose so the character and keyboard do not crowd the cell boundaries.

Images made with an earlier prompt may use a different cell order. Use the current prompt order for the Enter, drowsy, and sleep reactions to map correctly.

### Example image license

The reference image is an example generated with inspiration from [Grokbot Icon Studio](https://grokbot-icon-studio.serio-ai.chatgpt.site/ja). Its page states that the prompt text is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) by X user `@multi_serio_ai` (APG) for noncommercial use. Public redistribution of the prompt requires attribution, a source link, license notice, and change notice; commercial prompt use requires separate permission. The prompt text itself is not included in this repository.

The page also says that CC BY-NC 4.0 does not automatically apply to generated images; the operator does not claim copyright or revenue-sharing rights over generated images and does not require attribution for them. Rights in generated images still depend on applicable law, input-image rights, human creative contribution, and the AI service's terms. The repository author makes no claim over the 3×3 grid layout itself.

## Privacy

Waddly observes key-down events through a listen-only `CGEventTap`. It uses event timing and a transient check for whether the key is Enter. It does not store typed text or key codes, write input logs, or send input data over the network. The app can run without Input Monitoring permission.

## Measured memory

Measured on Apple Silicon with macOS 27.0, using the Release build. About eight seconds after launch, while idle animation was running, `ps` reported an RSS of 52,416 KB (about 51 MiB). `footprint` reported a physical memory footprint of about 13 MB and a peak of about 13 MB. Results vary with process and OS state. Typing and the frozen state after more than five minutes have not been measured.

RSS includes shared libraries and other resident pages. macOS footprint is a separate measure of the app's impact on physical memory. Both observed values were below this project's 100 MB target.

## License

The code is released under the [MIT License](LICENSE). The app icon and example images are not covered by that license. The icon is based on the author's penguin artwork; ask the author before reusing it.
