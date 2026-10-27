# Character Sprite Sheet Prompt for Waddly

Waddly composes this common contract with one [style block](pixel-art-en.md) and your character description. Pixel Art is the default. A ready-to-copy default prompt is in the [README](../README.md#prepare-a-sprite-sheet).

For manual composition, replace `{{character}}` in the block below with your description, then append the `text` block from exactly one style file: [Pixel Art](pixel-art-en.md), [Hand Drawn](hand-drawn-en.md), [Iconic](iconic-en.md), [Retro Cartoon](retro-cartoon-en.md), [Anime](anime-en.md), or [Paper Cutout](paper-cutout-en.md). Do not include Markdown fences. The app inserts descriptions literally, without interpreting template markers in your text.

An empty or whitespace-only description uses this default:

```character
A round penguin with a blue beanie, a black back, a white belly, and short orange feet.
```

## Common contract

```text
Character to draw: {{character}}

Create one 3×3 sprite sheet for Waddly using this character. If I manually attach a reference image, preserve that individual's identity. A reference image is optional.

[Character and held poses]
- Keep the same species, face, body width and height, palette, accessories, facing direction, camera, and scale in all nine cells.
- Keep the head top, body bottom, and horizontal center anchored at the same cell coordinates. Do not resize or shift the character between poses.
- Design for a few held poses at small desktop-pet sizes, not fluid full-body animation. Idle/blink and typing variations need only small changes; drowsy/sleeping keep the same body silhouette. Reserve the larger expression for the Enter reaction, without moving the body anchor.

[Sheet and placement]
- Output one square transparent PNG: a 3×3 grid of nine equally sized square cells, with the canvas side divisible by 3.
- Use genuine alpha transparency: alpha 0 outside the character and props. No simulated checkerboard, colored backdrop, floor, or cast shadow.
- Keep the entire character, accessories, keyboard, and effects within the central 50% of each cell, leaving a 25% safe margin on every side. Nothing may touch a cell boundary or spill into a neighboring cell.
- If a pose does not fit, reduce the gesture or effects, not the character's size. No gutters, divider lines, frames, numbers, captions, logos, or watermarks. No text except an optional Enter-key symbol.

[Nine cells: left to right, then top to bottom]
1. Idle: sitting relaxed.
2. Blink: identical to cell 1 except for closed eyelids.
3. Focused at keyboard: attentive, hands ready.
4. Typing: a small, slow key press.
5. Typing variation: a slightly different hand position from cell 4.
6. Fast typing: a small forward lean and quicker hands, with the body anchor unchanged.
7. Enter-key reaction: an expressive, forceful press on a larger Enter key, returning to the same anchor.
8. Drowsy: heavy eyelids, seated at the idle anchor.
9. Sleeping: eyes closed, resting in the same seated silhouette as cell 8.

[Keyboard and effects]
- Show the keyboard only in cells 3–7. Keep its position, shape, size, perspective, and colors identical wherever it appears; its width is at most 40% of the cell.
- In cell 7 only, emphasize the Enter key within 30% of the cell width. An optional “↵” symbol is allowed, but not the word “Enter”.
- Keep Enter sparkles and at most two short impact strokes next to the body, within the safe area. No effects in neighboring cells.

Output only the sprite sheet image that meets these requirements and the following style guidance.
```

## Check and recover

Generate externally in ChatGPT or another image generator, then import the PNG into Waddly. Waddly does not generate images or automatically upload a reference: attach one yourself in the external service if desired.

Check all nine crops against light and dark backgrounds for real transparency, safe margins, neighbor fragments, and stable anchors. Use **Adjust frames…** for crop and alignment corrections. Uneven grids, missing poses, baked-in backgrounds, and clipped artwork may need regeneration or an image editor; alignment cannot reconstruct missing pixels. See the [README](../README.md#image-requirements) for the import workflow and maintenance checks.
