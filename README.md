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

- Add your own pet images.
- Your pet reacts to keyboard input. Typed text and key codes are not stored.
- While idle, it breathes and blinks, then falls asleep after a while.
- Drag your pet anywhere on the desktop.
- The pet joins every desktop Space. Waddly does not force it above a fullscreen app, and it pulls the pet back into view when a display is disconnected or changed.

## Getting started

Waddly runs on Apple Silicon Macs with macOS 14 or later. There are two ways to install it.

### Install with Homebrew

Use this when you also want Homebrew to handle updates. Homebrew 6.0 or later requires explicit trust for third-party Casks, so the commands below trust only the Cask you install.

```sh
brew tap nyatinte/waddly
brew trust --cask nyatinte/waddly/waddly
brew install --cask waddly
```

Update with `brew upgrade --cask waddly`. To revoke the trust, run `brew untrust --cask nyatinte/waddly/waddly`.

### Install from GitHub Releases

Download `Waddly-<version>-macos-arm64.dmg` from the [latest release](https://github.com/nyatinte/Waddly/releases/latest), open it, and drag Waddly into your Applications folder. Verify the download with the `.sha256` file in the same release.

The app is ad-hoc signed and not notarized, so Gatekeeper may block the first launch. Allow it under System Settings → Privacy & Security → Open Anyway. On macOS 15 or later, Control-click → Open no longer clears the warning.

To try Waddly from source, follow the developer [build instructions](CONTRIBUTING.md).

On first launch, follow Setup Guide… to import your images.

### Turning on keyboard reactions

The second step asks for Input Monitoring. Drag the icon into the list, then switch Waddly on.

![Dragging Waddly into the Input Monitoring list](assets/examples/input-monitoring-guide.en.gif)

macOS applies the permission only after the app restarts.

## Use your own pet

### Prepare a sprite sheet

Send the [sprite sheet prompt](prompts/en.md) to [ChatGPT](https://chatgpt.com/) or another image generator to create a 3×3 sprite sheet.

<details>
<summary>Show the sprite sheet prompt</summary>

```text
Character to draw: <replace this line>

If that line is empty or still reads “<replace this line>”, ask the user what pet or character they want before creating anything.

Using that character, create a 3×3 animated sprite sheet for Waddly. If a reference image is attached, depict the individual in that image.

[Character]
- Keep the individual's features (species, colors, patterns, body shape) in every cell.

[Art style]
- Pixel art in the style of a 16-bit-era game. Few colors, thick outlines, two or three shades of shading.
- Do not use blur, anti-aliasing, gradients, glow, or photorealistic rendering.
- Keep the same size, facing direction, and camera position in all nine cells. Line up the top of the head, the bottom of the body, and the left-right centre at the same position in every cell, and do not change them between poses.

[Sheet and placement]
- Output one transparent PNG. Nine cells in a 3×3 grid. Make all cells equally sized squares, and make the side length divisible by 3.
- Use real transparency, with alpha 0 outside the character's silhouette. Do not draw a checkerboard, white, grey, a colored backdrop, a gradient, a floor, or shadows.
- Fit the whole character inside the central 50% of each cell (a 25% margin on every side). Keep ears, tails, wings, the keyboard, and effects inside that area too.
- A cell that touches its own boundary or a neighboring cell by even one pixel is an invalid output.
- If it does not fit, moderate the pose or the effects instead of shrinking the character.
- Do not draw divider lines, frames, numbers, captions, logos, or watermarks. No text except the optional Enter-key symbol.

[The nine cells: left to right, then top to bottom]
1. Sitting relaxed
2. The same pose as cell 1, but blinking
3. Focused, facing the keyboard
4. Typing slowly
5. Typing in a pose slightly different from cell 4
6. Leaning forward and typing quickly
7. The instant it presses a large Enter key forcefully. If a reference image is attached, take that energy from it
8. Drowsy, with heavy eyelids
9. Curled up and sleeping peacefully

[Keyboard and effects]
- Draw the keyboard only in cells 3–7, the same shape and size in all nine cells. Keep it narrower than 40% of the cell width.
- In cell 7, draw the Enter key larger than the other keys, and within 30% of the cell width. It may carry a “↵” symbol; do not write the word “Enter”.
- In cell 7, place the star-shaped spark and the impact lines right next to the body. Use at most two short strokes, and do not let them reach more than 5% of the cell width beyond the body. Keep their tips at least 30% inside the cell's right and bottom edges.

Output only the sprite sheet image that meets these requirements.
```

</details>

- If you have an image of a pet or character you want to use, attach it along with the prompt.
- If you don't have an image, describe the character in words, such as “a small penguin with a round body.” No image attachment is needed.

You can also create the sprite sheet by hand.

| Reference image | 3×3 sprite sheet |
| --- | --- |
| ![nyatinte-bot reference image](assets/examples/nyatinte-bot.png) | ![nyatinte-bot 3×3 transparent sprite sheet](assets/examples/nyatinte-bot-3x3.png) |

### Image requirements

- Transparent PNG with a square canvas
- Both dimensions divisible by 3
- Maximum file size: 20 MB; maximum side length: 4096 px

Sheets larger than 3072 px on a side are reduced during import, and individual images are capped at 1024 px. Animation Settings… adds several PNGs per animation.

Images are stored on your Mac as individual PNG frames. Source files are not modified and images are never uploaded. Older prompts may use a different cell order, so use the current prompt.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac.

## Measured memory

The app targets a physical memory footprint below 100 MB in typical use.

| Usage | Memory |
| --- | --- |
| Launch, typing, ordinary images | Under 100 MB (target) |
| Importing a very large sheet (for example 3072 × 3072 with nine frames) | Can exceed 100 MB (known exception for 1.0) |

See [memory profiling](docs/MEMORY.md) for the measurement procedure and baselines.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle.
