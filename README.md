<div align="center">
  <img src="assets/waddly-app-icon-rounded.png" alt="Waddly app icon" width="192" height="192">
  <h1>Waddly</h1>
</div>

<p align="center">Put your pet on your Mac desktop and let it react to keyboard input.</p>

<p align="center"><a href="https://github.com/nyatinte/Waddly/releases/latest">Download DMG</a> · <a href="#install-with-homebrew">Homebrew</a> · <a href="#install-with-nix">Nix</a> · macOS 14+ / Apple Silicon</p>

<p align="center"><a href="README.ja.md">日本語README</a></p>

<p align="center">
  <img src="assets/waddly-demo.gif" alt="Waddly reacting to keyboard input" width="900">
</p>

## What Waddly does

- Add your own pet images.
- Your pet reacts to keyboard input. Typed text and key codes are not stored.
- While idle, it breathes and blinks, then falls asleep after a while.
- Drag your pet anywhere on the desktop.
- The pet joins every desktop Space. It does not appear above a fullscreen app.
- Right-click the pet and choose “Share Pet” to copy a video or image of your pet and paste it into X or chat apps.

## Install

### Install with Homebrew

```sh
brew tap nyatinte/waddly
brew install --cask nyatinte/waddly/waddly
```

Update with `brew upgrade --cask waddly`.

### Install with Nix

The flake installs the Apple Silicon DMG from GitHub Releases. The package is `aarch64-darwin` only.

Run the latest release without installing it:

```sh
nix run github:nyatinte/Waddly
```

Install it into your profile, then open the app:

```sh
nix profile install github:nyatinte/Waddly
open ~/.nix-profile/Applications/Waddly.app
```

Add the flake as an input:

```nix
inputs.waddly.url = "github:nyatinte/Waddly";
```

nix-darwin installs it and copies the bundle to `/Applications/Nix Apps`:

```nix
imports = [ inputs.waddly.darwinModules.default ];

programs.waddly.enable = true;
```

Home Manager installs it through `home.packages`. With `targets.darwin.copyApps` enabled (the default when `stateVersion` is 25.11 or newer), the app is copied to `~/Applications/Home Manager Apps`:

```nix
imports = [ inputs.waddly.homeModules.default ];

programs.waddly.enable = true;
```

Apply the overlay so the rest of the configuration can use `pkgs.waddly`:

```nix
pkgs = import nixpkgs {
  system = "aarch64-darwin";
  overlays = [ inputs.waddly.overlays.default ];
};
```

`programs.waddly.package` selects a different build. The module uses `pkgs.waddly` when that attribute exists, and otherwise the package from this flake.

The app is the same ad-hoc signed build as the DMG. If macOS blocks the first launch, follow the steps under [Install from GitHub Releases](#install-from-github-releases). Then turn on keyboard reactions as described below.

### Install from GitHub Releases

Download `Waddly-<version>-macos-arm64.dmg` from the [latest release](https://github.com/nyatinte/Waddly/releases/latest), open it, and drag Waddly into your Applications folder. Verify the download with the `.sha256` file in the same release.

The app is ad-hoc signed and not notarized, so Gatekeeper may block the first launch. If macOS blocks the first launch, open System Settings → Privacy & Security, scroll to Security, and click Open Anyway. On macOS 15 or later, Control-click → Open no longer clears the warning.

To try Waddly from source, follow the developer [build instructions](CONTRIBUTING.md).

### Turning on keyboard reactions

Choose **Start setup**, then turn Waddly on under System Settings → Privacy & Security → Input Monitoring. If it is not in the list, drag its icon in or add it with **+**. If macOS asks, choose **Quit & Reopen**.

![Dragging Waddly into the Input Monitoring list](assets/examples/input-monitoring-guide.gif)

## Use your own pet

### Prepare a sprite sheet

Prepare a photo of your pet and choose **Open in ChatGPT** in Waddly. Attach the photo in ChatGPT, then return to Waddly and import the generated PNG. To use another image generator, choose **Copy prompt**. The [prompt](prompts/en.md) is also available below.

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

### Tips and local storage

- If the pet does not react, choose **If it does not work** to restart Waddly or check Input Monitoring in System Settings.
- When creating a new character, choose **Change Character…** to open the generation prompt in ChatGPT in the current app language, copy it for another image generator, or import a finished PNG at any time. Opening ChatGPT puts the prompt in the page URL, so it is also recorded in your browser history; **Copy prompt** leaves no trace there.
- Right-click the pet or use the menu bar icon to change pet size, behavior, language, visibility, launch at login, or Input Monitoring settings.
- Imported images and alignment edits are saved on your Mac, leaving your original files untouched. Waddly uploads nothing by itself.

## Privacy

Keystrokes are used only to animate the pet and are never stored, logged, or sent. Images and share videos or images stay on your Mac and are never uploaded automatically. “Post on X” only opens a compose window with `#ShareMyWaddly`, and only “Open in ChatGPT” sends the bundled prompt to ChatGPT.

## Measured memory

The app targets a physical memory footprint below 100 MB in typical use. See [CONTRIBUTING.md](CONTRIBUTING.md) for the profiling workflow and the allocator regression suite.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## Uninstall

If you installed with Homebrew:

```sh
brew uninstall --cask waddly
```

If you installed with Nix:

```sh
nix profile remove waddly
```

For nix-darwin or Home Manager, set `programs.waddly.enable = false` and rebuild.

Also remove Waddly from System Settings → Privacy & Security → Input Monitoring.

If you installed from the DMG, quit Waddly and move /Applications/Waddly.app to the Trash.

## Share and feedback

Share your pet with [#ShareMyWaddly](https://x.com/hashtag/ShareMyWaddly) on X. Report bugs or request features via [GitHub Issues](https://github.com/nyatinte/Waddly/issues). If you enjoy Waddly, a star on the repo helps a lot.

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle.
