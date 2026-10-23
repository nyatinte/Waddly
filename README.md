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

- Transparent PNG with a square canvas
- Both dimensions divisible by 3
- Maximum file size: 20 MB; maximum side length: 4096 px

An AI-generated sheet can drift slightly in pitch, shifting the character's vertical position between cells even when the prompt asks for a fixed anchor. After importing a 3×3 sheet, **Adjust frames…** opens a crop and alignment editor over the staged draft. It exposes exactly nine fixed cells (2 Idle, 4 Typing, 1 Enter, 2 Sleep); resizing the 1:1 crop only narrows the visible frame, while the Align tool moves the character itself. Pan and zoom the canvas with the trackpad or ⌘+/⌘−/⌘0, and check Before/After with the center crosshair.

Sheets larger than 3072 px on a side are reduced during import, and individual images are capped at 1024 px. The shared character screen accepts a chosen PNG, a window-wide PNG drop, or **Paste from Clipboard** (⌘V). Changes stay a draft until you press Continue or Apply.

Right-click the pet to change its size and behavior, language, visibility, and launch-at-login setting. Disabled commands explain what they need in native menu help, and at least one of Dock or menu bar access must remain on.

After setup, use **Set Up Input Monitoring…** for permission, status, and recovery guidance, and **Change Character…** to replace or edit images. Initial or unfinished setup opens **Setup Guide…** instead. The Setup Guide and **Change Character…** share one character screen, and a chosen image stays a draft until you press Continue or Apply. A failed save keeps the draft for another try, and closing with a changed draft asks before discarding it. If macOS requires a restart after you allow Input Monitoring, **Restart Waddly** relaunches the app and returns you to the same setup step.

If you have no image yet, **Try the sample pet first** shows the bundled sample immediately; it is stored locally like any pet and you can replace it with **Change image**.

Images are stored on your Mac as individual PNG frames, plus the optional original 3×3 sheet and its crop/alignment metadata when the frame editor was used. Source files are not modified and images are never uploaded. Older prompts may use a different cell order, so use the current prompt.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac. Share assets are generated locally when the dialog opens and are not uploaded by Waddly. Copying and posting are user actions. The X logo or text only opens a post composer (carrying `#ShareMyWaddly` and no post text); attach the asset and write your own post.

## Measured memory

The app targets a physical memory footprint below 100 MB in typical use. Importing a very large sheet (for example 3072 × 3072 with nine frames) can exceed that target (a known exception in 1.0). See [CONTRIBUTING.md](CONTRIBUTING.md) for the profiling workflow and the allocator regression suite. The frame editor decodes the retained 3 × 3 sheet only while it is open and releases its image buffers when the sheet closes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions.

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle.
