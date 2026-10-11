#!/usr/bin/env python3
"""Remove detached specks from sliced Waddly frames.

The 3x3 sheets are generated, and a cell can pick up a few pixels that bled
across the grid line from its neighbour (see README: check each cell for
"隣のコマの混入"). Left alone, that speck floats next to the pet on the desktop.

Usage: despeckle.py <frame.png> [<frame.png> ...]

Keeps every connected opaque region of at least MIN_AREA_RATIO of the cell area
and zeroes the alpha of the rest. Deterministic, in place.
"""

from __future__ import annotations

import sys
from collections import deque

from PIL import Image

ALPHA_FLOOR = 24
# Fraction of the cell area that separates a real detached element from bleed.
# At 768 px cells the smallest legitimate motion mark is ~880 px (0.15%) and the
# worst speck is 93 px (0.016%), so 0.05% sits between them. Scaling by area
# keeps the rule correct at any sheet resolution (a 1:1 256 px sheet uses ~33 px).
MIN_AREA_RATIO = 0.0005
MIN_AREA_FLOOR = 12


def components(alpha: Image.Image):
    w, h = alpha.size
    px = alpha.load()
    seen = bytearray(w * h)
    out = []
    for y0 in range(h):
        for x0 in range(w):
            i0 = y0 * w + x0
            if seen[i0] or px[x0, y0] <= ALPHA_FLOOR:
                continue
            queue = deque([(x0, y0)])
            seen[i0] = 1
            pixels = []
            while queue:
                x, y = queue.popleft()
                pixels.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        ni = ny * w + nx
                        if not seen[ni] and px[nx, ny] > ALPHA_FLOOR:
                            seen[ni] = 1
                            queue.append((nx, ny))
            out.append(pixels)
    return out


def clean(path: str) -> int:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    w, h = image.size
    min_area = max(MIN_AREA_FLOOR, int(w * h * MIN_AREA_RATIO))
    blobs = components(alpha)
    if not blobs:
        return 0
    removed = 0
    data = image.load()
    for blob in blobs:
        if len(blob) >= min_area:
            continue
        for x, y in blob:
            r, g, b, _ = data[x, y]
            data[x, y] = (r, g, b, 0)
        removed += len(blob)

    if removed:
        image.save(path)
    return removed


def main(argv: list[str]) -> int:
    total = 0
    for path in argv[1:]:
        removed = clean(path)
        if removed:
            print(f"  despeckled {path}: removed {removed} px")
        total += removed
    return 0 if total >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
