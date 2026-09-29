# Waddly

A lightweight macOS desktop companion that lets your pet live on your desktop. Replace the bundled penguin sprites with your own pet.

[日本語 README](README.md)

## Features

- Reacts to key-down events without storing typed text or key codes.
- Breathes subtly and blinks while idle, falls asleep after a while, and stops animating after five minutes. Input monitoring remains active so it can wake up.
- Drag the pet around the desktop; its position is saved. Choose from 180, 240, and 320 px sizes.
- Waddly appears in both the Dock and menu bar. Click the menu bar label or right-click the pet to open the menu. Change size or position, toggle visibility, pause reactions, configure launch at login, or quit.
- The app icon is generated from the bundled pet's idle frame. Replace `assets/01-idle.png` and rebuild to update it.
- Built with Swift, AppKit, Core Graphics, and Core Animation. No third-party libraries.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 6
- The build script targets the CPU architecture of the Mac running it

## Build and run

```sh
./macos/build.sh
open build/Waddly.app
```

To install it, copy `Waddly.app` to `~/Applications`, or open the DMG in `dist/` and drag the app to its `Applications` shortcut.

On first launch, allow Waddly under **System Settings → Privacy & Security → Input Monitoring**. The app and menu bar item can still launch without this permission; the menu links to the setting.

Create a distributable disk image with:

```sh
./macos/package.sh
```

The script writes `Waddly-0.1.0-macos-<architecture>.dmg` to `dist/`. No Developer ID signing identity is installed on the build machine, so the default build is ad-hoc signed and not notarized. Developer ID signing and Apple notarization are required to avoid Gatekeeper warnings when distributing over the internet. Set `WADDLY_SIGN_IDENTITY` to select a signing identity.

## Add your own pet

The repository includes `index.html`, a preview and splitter for 4×4 sprite sheets.

1. Start a local server:

   ```sh
   python3 -m http.server 8000
   ```

2. Open `http://localhost:8000` and choose your sprite-sheet image.
3. Review the frames and select **Save PNGs to assets/**. Browsers without folder-picker support download the PNGs individually.
4. Back up the existing `assets/01-*.png` through `assets/16-*.png`, then replace them with the new PNGs. Keep the filenames unchanged.
5. Run `./macos/build.sh` and launch the rebuilt `build/Waddly.app`.

### ChatGPT image-generation prompt

Attach a photo or illustration of your pet as the reference image, then use this prompt. The splitter looks for a white background and magenta dividers.

```text
Use the attached image as the only character reference. Create one sprite sheet featuring the same pet in every frame.

Make a square image with 4 equal columns and 4 equal rows (16 cells). Draw exactly one full-body pet in each cell. Keep its scale, orientation, line style, colors, and placement consistent. Do not let the character overlap cell boundaries.

Order the poses from left to right, then top to bottom:
1. Neutral front-facing idle
2. Blinking with eyes closed
3. Surprised, looking left
4. Surprised, looking right
5. Looking at a laptop
6. Typing normally
7. Typing quickly
8. Peeking over the screen
9. Typing excitedly
10. Focused on work
11. Jumping
12. Working one-handed
13. Getting sleepy
14. Sitting asleep
15. Raising both hands to cheer
16. Being gently picked up

Use a pure white background. Add thick, straight, vivid magenta (#ff00ff) dividers between all cells and around the outer edge, making five continuous vertical and five continuous horizontal bands. Do not use magenta on the pet. Do not add shadows, text, speech bubbles, props, or decorative borders. Output one square PNG image.
```

Depending on the generated image, the divider or background detection may need correction before import.

## Privacy

Waddly observes key-down events through a listen-only `CGEventTap`. It uses event timing only. It does not store typed text or key codes, write input logs, or send input data over the network. The app can run without Input Monitoring permission.

## Measured memory

Measured on Apple Silicon with macOS 27.0, using the Release build. About eight seconds after launch, while idle animation was running, `ps` reported an RSS of 52,416 KB (about 51 MiB). `footprint` reported a physical memory footprint of about 13 MB and a peak of about 13 MB. Results vary with process and OS state. Typing and the frozen state after more than five minutes have not been measured.

RSS includes shared libraries and other resident pages. macOS footprint is a separate measure of the app's impact on physical memory. Both observed values were below this project's 100 MB target.

## License

The code and bundled assets are released under the [MIT License](LICENSE).
