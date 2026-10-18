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
- Right-click the pet and choose “Share Pet” to create a five-second video and a 3×3 sprite sheet. Copy either asset to the clipboard — the video is copied as a file, so the X composer and chat apps attach it when you paste — or click the X logo or “Post on X” to open the composer carrying only the `#ShareMyWaddly` hashtag, with the post text left for you to write. The share window follows macOS light and dark appearance, and closing it cancels any generation still in progress.

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

An AI-generated sheet can drift slightly in pitch, shifting the character's vertical position between cells even when the prompt asks for a fixed anchor. Fix those poses before importing: place the corrected poses on equal transparent canvases with a consistent character anchor, then assemble them into a square equal-thirds (3×3) sheet or add individual frames per animation in the shared character screen. **Edit frames individually…** opens the advanced per-frame editor over the same staged draft. Waddly imports exact thirds and never normalizes frames automatically, because bounding-box normalization would misalign sleeping poses and effects.

Sheets larger than 3072 px on a side are reduced during import, and individual images are capped at 1024 px. The shared character screen accepts a chosen PNG, a window-wide PNG drop, or **Paste from Clipboard** (⌘V); the advanced editor adds several PNGs per animation.

Right-click the pet to change its size and behavior, language, visibility, and launch-at-login setting. Use **Setup Guide…** for Input Monitoring help and **Change Character…** to replace or edit its images; the status menu offers the same controls. In the Setup Guide, **Choose a PNG** or **Change image** opens the shared character screen. A chosen, pasted, or dropped sheet is staged and previewed without writing; Continue applies it once. In the Change Character window, **Apply** saves the reviewed draft and closes only after a successful save. A failed save keeps the draft available for retry. Cancel or closing with a changed draft asks before discarding it. A window-wide drop outside the shared screen still imports directly. An unreadable setup sheet is reported inline at the top of the current step; a ChatGPT opening failure is reported next to its action. Closing the guide, navigating or starting another import discards obsolete pending error feedback. Drop-target borders follow appearance changes without losing an active drag highlight. If you have no image yet, **Try the sample pet first** shows the bundled sample immediately; it is stored locally like any pet and you can replace it with **Change image**. The Keyboard reactions step reports success only after a real key press has reached Waddly while its event tap is running; granting permission alone is shown as needing a restart, and a live tap with no key yet is shown as waiting for a key press, not as ready. Pausing stops the tap, so the guide waits for a new key after you resume. The [first-run journey map and QA tasks](docs/setup-first-run-journey.md) document the flow and the manual checks; the [setup state and QA matrix](docs/setup-wizard-qa.md) lists the automated coverage.

Images are stored on your Mac as individual PNG frames. Source files are not modified and images are never uploaded. Older prompts may use a different cell order, so use the current prompt.

Waddly keeps a small manifest next to the frames that lists the saved images, and removes a frame only once the manifest no longer refers to it. If the app is interrupted — a crash or a forced quit — the next launch restores the last committed images and discards frames that were never committed. The manifest is written atomically but not flushed to disk, so sudden power loss can still lose the most recent change or leave the previous images. A manifest that cannot be read blocks further edits until you import images again; Waddly deletes nothing in that state. Waddly also records the same list in your preferences so a downgraded copy can still find the frames, but running two versions at once, or importing with an older version between saves, is not fully supported: the current version then keeps the extra frames and shows its own last committed set until you import or save again.

## Privacy

Keyboard events are used only to control animation. Waddly does not store, log, or transmit typed text or key codes. Images are stored locally on your Mac. Share assets are generated locally when the dialog opens and are not uploaded by Waddly. Copying and posting are user actions. The X logo or text only opens a post composer (carrying `#ShareMyWaddly` and no post text); attach the asset and write your own post.

## Measured memory

The app targets a physical memory footprint below 100 MB in typical use. One share-dialog sample settled at 53.5 MB while open and 90.5 MB after closing, with a transient 105.0 MB peak during generation; repeat runs are needed before claiming the peak target is met. Importing a very large sheet (for example 3072 × 3072 with nine frames) can also exceed the target (known exception for 1.0). See the [repeatable profiling workflow, baselines, and regression tests](docs/MEMORY.md). `mise run memory:test` runs the isolated regression suite (Swift 6.2 and macOS 26+; the production app still supports macOS 14).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution instructions. `mise run test` rejects Swift Testing runs that exit without reporting completion; `mise run test:guard` checks this guard without launching the app tests. For a source-audited map of the screens, entry points, interaction states, and a manual QA checklist, see the [UX interaction audit](docs/ux-interaction-audit.md).

## License

The software is released under the [MIT License](LICENSE), which is also included in the app bundle.
