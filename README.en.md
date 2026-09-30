# Waddly

A lightweight macOS desktop companion that lets your pet live on your desktop. Replace the bundled penguin sprites with your own pet.

[日本語 README](README.md)

## Features

- Reacts to key-down events without storing typed text or key codes.
- Breathes subtly and blinks while idle, falls asleep after a while, and stops animating after five minutes. Input monitoring remains active so it can wake up.
- Drag the pet around the desktop; its position is saved. Choose Small, Medium, or Large.
- The UI follows the preferred macOS language (Japanese or English) and falls back to English for other languages.
- Waddly appears in both the Dock and menu bar; choose where it appears from the “Show in” menu (at least one remains visible). Click the custom W icon or right-click the pet to open the menu. Change size and typing motion, configure pet images, pause reactions, or configure launch at login.
- On first launch, a setup wizard walks through the image-generation prompt, required 3×3 PNG import, and Input Monitoring permission. Drop a PNG anywhere on the image page; a custom image is required to continue. Reopen it from the menu at any time.
- The app icon is generated from the bundled pet's idle frame. Replace `assets/01-idle.png` and rebuild to update it.
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

Choose **Pet images…** from the menu to add any number of transparent PNGs to the Idle, Typing, Sleep, and Enter rows. Drop files onto a row or use **Add** to select multiple images. Use the arrow buttons to reorder images and the remove button to delete them. Idle uses the first image as its normal pose and the rest as blink variants. Typing and Enter images play in order. Sleep images cycle and stop on the last image after five minutes.

Transparent 3×3 PNG sprite sheets are still supported. Drop a sheet onto the pet to preview its cell boundaries and dimensions before importing. Images are stored locally in Application Support and restored at the next launch. Images with a side longer than 1024 px are downsampled in the app before saving; the selected source files are not modified or uploaded.

The image must be square, with dimensions divisible by 3. The limit is 20 MB and 4096 px. Waddly divides the image into equal cells, so follow the cell order and spacing in the prompts.

The image-generation prompts are in [`prompts/ja.md`](prompts/ja.md) and [`prompts/en.md`](prompts/en.md). They leave transparent padding around each pose so the character and keyboard do not crowd the cell boundaries.

Images made with an earlier prompt may use a different cell order. Use the current prompt order for the Enter, drowsy, and sleep reactions to map correctly.

### Edit the bundled pet frames

The repository also includes the legacy `index.html` splitter for editing the bundled 4×4 sprite sheet. Replace the frames in `assets/` and rebuild to change the default pet. Custom images can be configured in the app's image settings window or imported as a 3×3 PNG sheet.

## Privacy

Waddly observes key-down events through a listen-only `CGEventTap`. It uses event timing and a transient check for whether the key is Enter. It does not store typed text or key codes, write input logs, or send input data over the network. The app can run without Input Monitoring permission.

## Measured memory

Measured on Apple Silicon with macOS 27.0, using the Release build. About eight seconds after launch, while idle animation was running, `ps` reported an RSS of 52,416 KB (about 51 MiB). `footprint` reported a physical memory footprint of about 13 MB and a peak of about 13 MB. Results vary with process and OS state. Typing and the frozen state after more than five minutes have not been measured.

RSS includes shared libraries and other resident pages. macOS footprint is a separate measure of the app's impact on physical memory. Both observed values were below this project's 100 MB target.

## License

The code and bundled assets are released under the [MIT License](LICENSE).
