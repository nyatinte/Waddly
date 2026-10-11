<div align="center">
  <img src="assets/waddly-app-icon-rounded.png" alt="Waddly app icon" width="192" height="192">
  <h1>Waddly</h1>
</div>

<p align="center">Put your pet on your Mac desktop and let it react to keyboard input.</p>

<p align="center"><a href="README.ja.md">日本語README</a></p>

<p align="center">
  <img src="assets/waddly-demo.gif" alt="Waddly reacting to keyboard input" width="900">
</p>

## What Waddly does

- Your pet reacts to keyboard input. Typed text and key codes are not stored.
- While idle, it breathes and blinks. After a while it sleeps and wakes when you type.
- Drag your pet anywhere on the desktop; its position is saved between launches.
- Add your own pet images and configure idle, typing, and other animations with “Animation Settings…”.
- Configure size, motion, display location, and language from the menu. “Setup Guide…” walks you through adding your first pet and turning on keyboard reactions. The language item is labeled “Language / 言語”.
- Click the Dock icon to open setup before images are registered; afterwards it only brings your pet back to the front. Animation Settings is opened from the menu. If setup is already open, it is brought to the front instead.

## Use your own pet

### Prepare a sprite sheet

You can attach a photo of your pet to [ChatGPT](https://chatgpt.com/) and use the [English prompt](prompts/en.md) or [Japanese prompt](prompts/ja.md) to create a 3×3 sprite sheet. This optional step sends the photo to ChatGPT under its terms and privacy policy; you can also create the sheet yourself without using an external service.

Setup asks for your pet first and for permission second, and keeps a preview of the pet on the right of every screen. The first step offers two ways in: “Create an image with ChatGPT” copies the prompt and opens ChatGPT, and “Choose a PNG file” imports a sheet you already have. You can also drop the PNG anywhere on the window. Choosing a PNG registers it straight away; nothing changes until you pick a file. The pet then loops through all nine poses in the preview, where you can switch between Animation and 9 cells and play each pose back. Canceling the file picker leaves any previously registered images unchanged. Cells are read from top left to bottom right: two idle poses, four typing poses, one Enter pose, and two sleep poses.

The preview can show the nine cells on a light or a dark background; switch between them and check every cell edge for fragments from neighboring poses and stray floating pixels. Remove accidental specks, but keep intentional detached effects such as motion marks, sleep symbols, and Enter sparkles. To use the corrected example if you imported an older copy, download the updated sheet and import it again; saved frames do not update automatically.

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

Waddly requires an Apple Silicon Mac running macOS 14 or later. It is distributed from Waddly's third-party Homebrew tap. Homebrew 6.0 or later requires explicit trust for third-party Casks. The commands below trust only the Cask you install, not every current and future package or command in the tap.

```sh
brew tap nyatinte/waddly
brew trust --cask nyatinte/waddly/waddly
brew install --cask waddly
```

Cask trust remains in effect for future upgrades. Revoke it with `brew untrust --cask nyatinte/waddly/waddly`.

Update the app with `brew upgrade --cask waddly`. To try Waddly from source, follow the developer [build instructions](CONTRIBUTING.md).

The app is ad-hoc signed and is not notarized. The Homebrew Cask removes the quarantine attribute after each install and upgrade, so Gatekeeper protection is reduced for Homebrew installs. This does not replace Developer ID signing or notarization. Directly downloaded DMGs retain quarantine, so Gatekeeper may block first launch. Confirm that the app came from the official GitHub Release, then allow it under System Settings → Privacy & Security → Open Anyway. On macOS 15 or later, Control-click → Open cannot override this warning; see [Apple’s first-launch instructions](https://support.apple.com/en-us/102445). For a manually downloaded DMG, verify it with the `.sha256` file attached to the same release.

On first launch, follow Setup Guide… to import your images.

### Turning on keyboard reactions

The second step asks for Input Monitoring. Waddly opens System Settings, parks itself beside it, and turns its own preview into a drag guide: drag the icon into the list, then switch Waddly on. If your macOS version does not accept the drop, use “Add it another way” for the manual steps.

![Dragging Waddly into the Input Monitoring list](assets/examples/input-monitoring-guide.gif)

macOS applies the permission only after the app restarts. Waddly keeps the setup step it was on, so it returns to the same screen on the next launch instead of starting over. The app also runs without the permission; it simply does not respond to keys, and the menu bar says so.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac.

## Measured memory

The memory goal is a physical footprint below 100 MB in representative configurations. Importing a very large sheet (for example 3072 × 3072 with nine frames) can exceed that target in the current release; this is a known, accepted exception for 1.0, while the app targets under 100 MB for typical use. See the [repeatable profiling workflow, baselines, and regression tests](docs/MEMORY.md). Compare Release-app RSS and physical footprint across launch, typing, large images, repeated imports, and sleeping/frozen states. `mise run memory:test` runs the isolated regression suite (Swift 6.2 and macOS 26+; the production app still supports macOS 14).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle. Project artwork is not covered by that license: `assets/waddly-app-icon*.png`, `assets/waddly-menubar.svg`, `assets/waddly-demo.gif`, and `assets/examples/`. The icons and demo include penguin artwork. No reuse rights are granted for these assets; obtain permission from their respective copyright holders before reusing them. The adapted `.agent/skill/swift-development` is separately licensed under Apache-2.0; see its accompanying `LICENSE`.
