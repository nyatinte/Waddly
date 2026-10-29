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
- The pet joins every desktop Space. It does not appear above a fullscreen app.
- Right-click the pet and choose “Share Pet” to generate a five-second MP4 (384 × 384) and a 3×3 PNG sprite sheet (nine frames) locally. You can copy the video or the image, and “Post on X” opens the composer with only `#ShareMyWaddly`, so you write the post and attach the file yourself. Waddly has no share save-to-file action.

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

- **Format:** Square transparent PNG (9 frames in a 3×3 grid)
- **Dimensions:** Width and height divisible by 3 (up to 4096 px per side)
- **File size:** 20 MB or less
- **Auto-scaling:** Sheets larger than 3072 px per side are automatically scaled down on import (up to 1024 px per frame)
- **Frame order:** 2 Idle, 4 Typing, 1 Enter, and 2 Sleep frames (use the current prompt, as older prompts may use a different order)

### Quick setup

1. **Import an image:** Open **Setup Guide…** (on first launch) or **Change Character…** from the menu, then select a PNG file, drag and drop it, or paste it with ⌘V. If you do not have an image yet, click **Try the sample pet first** to use the bundled pet right away.
2. **Adjust frame alignment (optional):** If an AI-generated sheet shifts the character's position between cells, open **Adjust frames…** to fine-tune the crop and character alignment while checking the preview.
3. **Apply:** Click **Apply** (or **Continue** during initial setup) to update your desktop pet.

### Tips and local storage

- **Create another character:** From **Change Character…**, you can copy the generation prompt in the current app language or open ChatGPT at any time.
- **Everyday settings:** Right-click the pet or use the menu bar icon to change pet size, behavior, language, visibility, launch at login, or Input Monitoring settings.
- **Local-only storage:** Imported images and alignment edits are saved only on your Mac without modifying the original files. Waddly never uploads your images or prompts to external servers.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac. Share assets are generated locally when the dialog opens and are not uploaded by Waddly. Copying and posting are user actions. The X logo or text only opens a post composer (carrying `#ShareMyWaddly` and no post text); attach the asset and write your own post.

## Measured memory

The app targets a physical memory footprint below 100 MB in typical use. Importing a very large sheet (for example 3072 × 3072 with nine frames) can exceed that target (a known exception in 1.0). See [CONTRIBUTING.md](CONTRIBUTING.md) for the profiling workflow and the allocator regression suite. The frame editor reuses one Before and one After preview when their image inputs are unchanged, rather than regenerating them for zoom or guide changes. Editor cleanup drops its decoded-sheet and preview references; closing a sheet does not guarantee that process memory immediately returns to its previous level.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle.
