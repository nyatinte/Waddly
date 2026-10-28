# Pet Sprite Sheet Prompt for Waddly

Copy the prompt below and send it to an image-generation model.

- If you have an image of a pet or character you want to use, attach it along with the prompt.
- If you don't have an image, replace “Character to draw” on the first line with your own description (for example `A small penguin with a round body. Short legs, black back and white belly.`). If you send it unchanged, the image model asks what you want to create.
- You may also attach an action reference image showing a comedic, forceful key press for the Enter-key pose.

The prompt below is the shared contract and does not depend on art style. Waddly joins it with the `[Art style]` block of the selected style (pixel art while no style is selected; the available blocks are pixel-art, hand-drawn, iconic, retro-cartoon, anime, and paper-cutout). To use it outside the app, copy the shared prompt and the chosen style block and concatenate them.

```text
Character to draw: {{character}}

If that line is empty or still reads “<replace this line>”, ask the user what pet or character they want before creating anything.

Using that character, create a 3×3 animated sprite sheet for Waddly. If a reference image is attached, depict the individual in that image.

[Character]
- Keep the individual's features (species, colors, patterns, body shape) in every cell.
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

The app fills `{{character}}` from what the person typed. When they leave it empty, the placeholder below keeps the prompt usable as-is; change it only to change that default.

```character
<replace this line>
```

## Checking the generated image

An image-generation model cannot verify its own output, so the person who generated the image does the checking. Asking the model to check its work has little effect, and the longer the instructions get, the less it follows the other requirements. Check these three things.

- To confirm real transparency, put the image on a dark background or in a dark-mode window. If white or a checkerboard is baked in, it is not transparent.
- Waddly's preview can switch between a light and a dark background. Look at the four edges of each of the nine cells for fragments of a neighboring pose or anything touching a boundary.
- If you find a single-pixel speck or a fragment from another cell, generate another option that fits better, or fix just that cell in an image editor. Keep the intentional motion marks, sleep symbols, and Enter sparkles.
