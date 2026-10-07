<div align="center">
  <img src="assets/waddly-app-icon-rounded.png" alt="Waddly app icon" width="192" height="192">
  <h1>Waddly</h1>
</div>

<p align="center">Put your pet on your Mac desktop and let it react to keyboard input.</p>

<p align="center"><a href="README.md">日本語README</a></p>

<p align="center">
  <img src="assets/waddly-demo.gif" alt="Waddly reacting to keyboard input" width="900">
</p>

## What Waddly does

- Your pet reacts to keyboard input. Typed text and key codes are not stored.
- While idle, it breathes and blinks. After a while it sleeps and wakes when you type.
- Drag your pet anywhere on the desktop; its position is saved between launches.
- Add your own pet images and configure idle, typing, and other animations with “Animation Settings…”.
- Configure size, motion, display location, and language from the menu. “Setup Guide…” walks you through the initial image import and Input Monitoring permission. The language item is labeled “Language / 言語”.
- Click the Dock icon to open setup before images are registered, or Animation Settings afterward. If setup is already open, it is brought to the front instead.

## Use your own pet

### Prepare a sprite sheet

Attach a photo of your pet in [ChatGPT](https://chatgpt.com/) and use the [English prompt](prompts/en.md) or [Japanese prompt](prompts/ja.md) to create a 3×3 sprite sheet. You can also create the sheet yourself.

Import a transparent PNG sprite sheet during setup. Drop the PNG onto the image page or use “Choose PNG…” and check the preview. Canceling leaves any previously registered images unchanged. Cells are read from top left to bottom right: two idle poses, four typing poses, one Enter pose, and two sleep poses.

| Reference image | 3×3 sprite sheet |
| --- | --- |
| ![nyatinte-bot reference image](assets/examples/nyatinte-bot.png) | ![nyatinte-bot 3×3 transparent sprite sheet](assets/examples/nyatinte-bot-3x3.png) |

### Image requirements

- Transparent PNG with a square canvas
- Both dimensions divisible by 3
- Maximum file size: 20 MB; maximum side length: 4096 px

Sheets larger than 3072 px on a side are reduced during import. You can also add multiple PNGs for each animation from Animation Settings… in the menu. Scroll horizontally to edit images that do not fit in a row. Individual images are reduced to a maximum side length of 1024 px.

Images are stored on your Mac as individual PNG frames. The source files are not modified, and images are not uploaded. Older prompts may use a different cell order; use the current prompt for the expected order.

## Getting started

Waddly requires an Apple Silicon Mac running macOS 14 or later. The stable Homebrew Cask is available from the official tap.

```sh
brew tap nyatinte/waddly
brew install --cask waddly
```

Beta `0.1.0-beta.1` is available separately as `Waddly Beta.app`:

```sh
brew install --cask nyatinte/waddly/waddly-beta
```

Update the stable app with `brew upgrade --cask waddly` and the beta app with `brew upgrade --cask waddly-beta`. To try Waddly from source, follow the developer [build instructions](CONTRIBUTING.md).

The app is ad-hoc signed and is not notarized. The Homebrew Cask removes the quarantine attribute after each install and upgrade, so Gatekeeper's first-launch confirmation normally does not appear for Homebrew installs. This does not replace notarization or Developer ID signing. A DMG downloaded directly retains quarantine, so Gatekeeper may block the first launch. Confirm that it came from the official GitHub Release, then allow it under System Settings → Privacy & Security → Open Anyway. On macOS 15 or later, Control-click → Open cannot override this warning; see [Apple’s first-launch instructions](https://support.apple.com/en-us/102445). For a manually downloaded DMG, verify it with the `.sha256` file attached to the same release.

On first launch, follow Setup Guide… to import your images. To make the pet react to keyboard input, allow Waddly under System Settings → Privacy & Security → Input Monitoring. The app launches without permission but does not respond to keys.

If the setup wizard appears after upgrading from an earlier beta, import your sprite sheet again.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac.

## Measured memory

The memory goal is a physical footprint below 100 MB in representative configurations. See the [repeatable profiling workflow, baselines, and regression tests](docs/MEMORY.md). Compare Release-app RSS and physical footprint across launch, typing, large images, repeated imports, and sleeping/frozen states. `mise run memory:test` runs the isolated regression suite (Swift 6.2 and macOS 26+; the production app still supports macOS 14).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## License

The code is released under the [MIT License](LICENSE). The app icon, example images, and demo GIF are not covered by that license. The icon and GIF include the author's penguin artwork. Ask the author before reusing them.
