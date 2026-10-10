# Pet Sprite Sheet Prompt for Waddly

Attach an image of the pet or character you want to use, then give the prompt below to an image-generation model. You may also attach the action reference image for the Enter-key pose.

```text
Create a 3×3 animated sprite sheet for Waddly, using the attached pet or character image as the reference.

[Character]
- Depict the same individual as in the reference. Preserve its species, coat or feather colors and patterns, face, body shape, ears, tail, wings, and other identifying features.
- Do not add clothes, hats, or accessories that are not in the reference.
- Do not give the character human limbs or hands. Use natural paws, wings, or other features appropriate to the animal.

[Art style]
- Crisp pixel art reminiscent of a 16-bit-era game character.
- Draw each cell on the same 64×64-pixel logical grid. Keep the palette, outlines, pixel scale, and shading consistent across all cells.
- Do not use anti-aliasing, blur, gradients, glow, or photorealistic textures.
- Keep the same character, facing direction, camera angle, and character scale in every cell. Keep ears, tail, and other features inside each cell; nothing may overlap a neighboring cell.
- Leave about 10% transparent padding on every side of each cell. Fit the character, keyboard, and effects inside the central 80% safe area instead of filling the cell edge to edge. Keep ears, tails, the keyboard, and Enter impact effects well away from cell boundaries.

[Sheet format]
- Output one transparent PNG.
- Use exactly 3 columns and 3 rows for 9 equally sized square cells, with no divider lines or gaps between cells.
- Use real transparency. Do not draw a checkerboard or any background color.
- Do not add numbers, captions, logos, or watermarks. Do not include text except for the optional Enter-key symbol.

[Cell order: left to right, then top to bottom]
1. Relaxed, with a natural expression.
2. Almost the same pose as cell 1, but blinking.
3. Focused and facing a keyboard, just before typing.
4. Typing slowly with natural paws, wings, or other animal features.
5. Typing in a slightly different pose from cell 4.
6. Leaning forward slightly and typing rapidly.
7. The instant the character forcefully presses the Enter key. Use the attached action reference for the comedic, decisive energy of dramatically striking a key. The character leans forward confidently and presses a large, clearly recognizable Enter key with a natural paw, wing, or other animal feature. Show the key being pushed down, with a small pixel-art impact burst or star-shaped spark to convey a satisfying “THUNK!” Do not copy the human, clothing, or exact composition from the reference. Keep the animal’s natural body shape.
8. Drowsy, with heavy eyelids.
9. Sleeping peacefully with eyes closed.

[Keyboard]
- Show the same small keyboard or laptop only in cells 3–7.
- In cell 7, make the Enter key visibly larger than the other keys. It may carry a simple “↵” symbol; do not write the word “Enter.”
- Keep the keyboard and character entirely within their own cells and away from the cell edges.

[Final inspection]
- Inspect all nine cells separately on both light and dark backgrounds before outputting the sheet.
- Check every cell edge for fragments from neighboring poses and stray floating pixels. Remove accidental specks, including single pixels, without removing intentional detached motion marks, sleep symbols, or Enter sparkles.

Output only the sprite sheet image that meets these requirements.
```
