#!/usr/bin/env python3
"""Author and validate the character-style samples. See assets/character-styles/README.md.

Development dependency: Pillow==12.1.0. No fonts, downloaded art, or random state.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

import PIL
from PIL import Image, ImageChops, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "character-styles"
CELL = 256
STYLES = (
    "pixel-art", "hand-drawn", "iconic", "retro-cartoon", "anime", "paper-cutout",
)
POSES = (
    "idle", "blink", "focused", "typing", "typing-variation", "fast-typing",
    "enter", "drowsy", "sleeping",
)
# Ink, feathers, belly, beanie, hat light, hat shade, feet, key deck, key caps.
PALETTES = {
    "pixel-art": ("#172b45", "#30445d", "#fff3d5", "#387bd2", "#79bded", "#23519a", "#efaf55", "#607b94", "#c9e2e7"),
    "hand-drawn": ("#383f4b", "#4a5966", "#fff6df", "#669bcb", "#a2c6db", "#4979a2", "#e9ac68", "#87999c", "#e2e7d9"),
    "iconic": ("#18334b", "#18334b", "#fff9e9", "#357ddb", "#357ddb", "#2561af", "#f3b449", "#527d95", "#dcecf1"),
    "retro-cartoon": ("#302f3b", "#424453", "#ffedc9", "#4b8ab5", "#83b6d0", "#306383", "#e5a05a", "#5a7886", "#e2d9bc"),
    "anime": ("#273456", "#3e506c", "#fff8eb", "#448ce6", "#a0d6ff", "#2857a8", "#f7b866", "#577591", "#dcecf4"),
    "paper-cutout": ("#263f50", "#395363", "#f4ecd8", "#5894c2", "#8eb9d4", "#386789", "#dca35f", "#72909d", "#d9e1d7"),
}


class Canvas:
    """Small path rasterizer; every coordinate is in the same 256 px cell space."""

    def __init__(self, style):
        self.style = style
        self.scale = 0.25 if style == "pixel-art" else 4
        side = round(CELL * self.scale)
        self.image = Image.new("RGBA", (side, side))
        self.ink, self.body, self.cream, self.blue, self.light, self.shade, self.gold, self.deck, self.key = PALETTES[style]
        self.stroke = {"iconic": 0, "paper-cutout": 0, "retro-cartoon": 2.8, "hand-drawn": 1.8}.get(style, 1.8)

    def shape(self, points, fill, outline=True, width=None):
        if self.style == "hand-drawn":
            points = [(x + 0.28 * math.sin(y * 0.8 + x), y + 0.24 * math.sin(x * 0.7)) for x, y in points]
        points = [(round(x * self.scale), round(y * self.scale)) for x, y in points]
        draw = ImageDraw.Draw(self.image)
        draw.polygon(points, fill=fill)
        if self.style == "paper-cutout":
            # The offset edge is clipped INSIDE each paper piece, never a floor shadow.
            mask = Image.new("L", self.image.size)
            ImageDraw.Draw(mask).polygon(points, fill=255)
            edge = ImageChops.subtract(mask, ImageChops.offset(mask, -5, -6))
            layer = Image.new("RGBA", self.image.size, "#24384b")
            layer.putalpha(edge.point(lambda value: value // 5))
            self.image = Image.alpha_composite(self.image, layer)
        weight = self.stroke if width is None else width
        if outline and weight:
            ImageDraw.Draw(self.image).line(points + points[:1], fill=self.ink, width=max(1, round(weight * self.scale)), joint="curve")

    def path(self, start, curves, fill, outline=True, width=None):
        points = [start]
        for x1, y1, x2, y2, x3, y3 in curves:
            x0, y0 = points[-1]
            for step in range(1, 21):
                t = step / 20
                u = 1 - t
                points.append((u**3 * x0 + 3 * u**2 * t * x1 + 3 * u * t**2 * x2 + t**3 * x3,
                               u**3 * y0 + 3 * u**2 * t * y1 + 3 * u * t**2 * y2 + t**3 * y3))
        self.shape(points, fill, outline, width)

    def ellipse(self, box, fill, outline=True, width=None):
        left, top, right, bottom = box
        self.shape([( (left + right) / 2 + (right - left) / 2 * math.cos(i * math.tau / 80),
                      (top + bottom) / 2 + (bottom - top) / 2 * math.sin(i * math.tau / 80)) for i in range(80)],
                   fill, outline, width)

    def line(self, points, fill=None, width=1.5):
        draw = ImageDraw.Draw(self.image)
        scaled = [(round(x * self.scale), round(y * self.scale)) for x, y in points]
        weight = max(1, round(width * self.scale))
        draw.line(scaled, fill=fill or self.ink, width=weight, joint="curve")
        if self.style != "pixel-art":
            r = weight / 2
            for x, y in (scaled[0], scaled[-1]):
                draw.ellipse((x - r, y - r, x + r, y + r), fill=fill or self.ink)

    def finish(self):
        if self.style == "paper-cutout":
            # Coordinate-hashed fiber, identical in every pose and on every run.
            pixels = self.image.load()
            for y in range(self.image.height):
                for x in range(self.image.width):
                    r, g, b, a = pixels[x, y]
                    if a:
                        grain = ((x * 73 + y * 151 + (x * y) % 97) % 13) - 6
                        pixels[x, y] = tuple(max(0, min(255, v + grain)) for v in (r, g, b)) + (a,)
        method = Image.Resampling.NEAREST if self.style == "pixel-art" else Image.Resampling.LANCZOS
        result = self.image.resize((CELL, CELL), method)
        # Canonical transparent RGB also makes pixel comparisons unambiguous.
        result.paste((0, 0, 0, 0), mask=result.getchannel("A").point(lambda a: 255 if a == 0 else 0))
        return result


def draw_body(c):
    # These landmarks never translate, scale, or rotate between semantic poses.
    c.ellipse((94, 177, 119, 188), c.gold)
    c.ellipse((137, 177, 162, 188), c.gold)
    if c.style == "pixel-art":
        c.shape([(108, 88), (148, 88), (148, 92), (160, 92), (160, 100), (168, 100),
                 (168, 116), (176, 116), (176, 164), (168, 164), (168, 176),
                 (152, 176), (152, 180), (104, 180), (104, 176), (88, 176),
                 (88, 164), (80, 164), (80, 116), (88, 116), (88, 100),
                 (96, 100), (96, 92), (108, 92)], c.body)
    else:
        c.path((128, 88), [(155, 88, 170, 105, 172, 126), (182, 153, 176, 175, 157, 179),
                          (145, 184, 111, 184, 99, 179), (80, 175, 74, 153, 84, 126),
                          (86, 105, 101, 88, 128, 88)], c.body)
    if c.style in ("anime", "pixel-art"):
        c.path((155, 100), [(179, 121, 183, 165, 158, 177), (145, 181, 141, 178, 144, 170),
                            (168, 150, 169, 121, 155, 100)], c.ink, False)
    c.path((128, 116), [(112, 96, 94, 109, 96, 127), (87, 149, 96, 173, 111, 175),
                       (122, 178, 137, 178, 145, 175), (160, 173, 169, 149, 160, 127),
                       (162, 109, 144, 96, 128, 116)], c.cream, c.style == "hand-drawn", 1)
    if c.style == "anime":
        c.path((98, 146), [(101, 172, 122, 177, 145, 170), (130, 183, 95, 180, 98, 146)], "#d0dce4", False)
        c.line([(88, 124), (87, 143)], "#7d92ae", 2)
    if c.style == "paper-cutout":
        c.path((94, 137), [(92, 157, 99, 171, 109, 175), (98, 166, 99, 148, 94, 137)], "#ddd7c4", False)


def draw_hat(c):
    if c.style == "pixel-art":
        c.shape([(96, 100), (92, 100), (92, 88), (100, 88), (100, 80), (112, 80),
                 (112, 76), (144, 76), (144, 80), (156, 80), (156, 88), (164, 88),
                 (164, 100)], c.blue)
        c.shape([(104, 88), (104, 84), (116, 84), (116, 80), (132, 80), (132, 84), (116, 84), (116, 88)], c.light, False)
    elif c.style == "paper-cutout":
        c.shape([(92, 99), (95, 86), (108, 77), (126, 74), (147, 78), (160, 87), (164, 100)], c.blue)
        c.shape([(98, 96), (103, 86), (117, 80), (129, 79), (118, 88), (115, 98)], c.light, False)
        c.shape([(145, 80), (160, 88), (163, 98), (149, 98)], c.shade, False)
    else:
        c.path((92, 100), [(91, 69, 157, 64, 164, 100), (146, 105, 111, 105, 92, 100)], c.blue)
        if c.style == "anime":
            c.path((98, 91), [(102, 79, 118, 75, 135, 78), (122, 79, 110, 84, 107, 94)], c.light, False)
            c.path((143, 78), [(157, 81, 162, 91, 164, 100), (155, 102, 147, 101, 145, 98),
                             (149, 89, 148, 84, 143, 78)], c.shade, False)
    c.ellipse((121, 68, 135, 81), c.light)
    if c.style == "paper-cutout":
        c.shape([(90, 98), (164, 97), (166, 109), (92, 111)], c.shade)
        c.shape([(92, 99), (162, 99), (162, 107), (92, 108)], c.blue, False)
    else:
        c.path((92, 98), [(112, 95, 144, 95, 164, 98), (166, 99, 166, 107, 163, 109),
                          (142, 111, 112, 111, 93, 109), (90, 107, 90, 100, 92, 98)], c.blue)
    if c.style != "iconic":
        for x in range(99, 160, 8 if c.style == "pixel-art" else 6):
            c.line([(x, 100), (x, 106)], c.shade, 1)
    if c.style in ("hand-drawn", "retro-cartoon"):
        for x in (107, 119, 139, 151):
            c.line([(x, 93), (x + 1, 86)], c.shade, 1)
    # A tiny stitched diamond is a common identity detail, not text.
    c.shape([(128, 100), (131, 104), (128, 108), (125, 104)], c.cream, False)


def draw_face(c, pose):
    sleepy = pose in (7, 8)
    closed = pose in (1, 8)
    focused = pose in (2, 3, 4, 5)
    for x in (111, 145):
        if closed:
            c.line([(x - 5, 124), (x - 2, 126), (x + 2, 126), (x + 5, 123)], width=2)
        elif sleepy:
            c.line([(x - 4, 122), (x + 4, 122)], width=2)
            c.ellipse((x - 2, 122, x + 2, 126), c.ink, False)
        elif c.style == "retro-cartoon":
            c.ellipse((x - 5, 115, x + 5, 129), c.ink, False)
            c.shape([(x - 5, 116), (x, 121), (x - 5, 122)], c.cream, False)
        elif c.style == "anime":
            c.ellipse((x - 5, 115, x + 5, 129), c.ink, False)
            c.ellipse((x - 3, 120, x + 3, 127), c.blue, False)
            c.ellipse((x - 1.5, 118, x + 1.5, 126), c.ink, False)
            c.ellipse((x - 3, 116, x, 120), "#ffffff", False)
            c.ellipse((x + 1, 124, x + 3, 126), "#ffffff", False)
            c.line([(x - 6, 116), (x - 2, 114), (x + 4, 115)], width=1.4)
        elif c.style == "iconic":
            c.ellipse((x - 2.8, 118, x + 2.8, 126), c.ink, False)
        else:
            c.ellipse((x - 3, 117, x + 3, 126), c.ink, False)
            if c.style != "paper-cutout":
                c.ellipse((x - 1, 118, x + 1, 120), c.cream, False)
        if focused:
            c.line([(x - 5, 114 if x < 128 else 116), (x + 5, 116 if x < 128 else 114)], width=1.5)
    if c.style in ("anime", "hand-drawn", "retro-cartoon"):
        for x in (102, 154):
            c.ellipse((x - 4, 129, x + 4, 132), "#e9b1a1", False)
    if c.style == "retro-cartoon":
        c.ellipse((120, 130, 136, 138), c.gold)
        c.line([(123, 136), (128, 140), (134, 137)], width=1.2)
    else:
        c.shape([(121, 131), (128, 129), (135, 131), (128, 138)], c.gold, c.style not in ("iconic", "paper-cutout"), 1)
    if pose == 6:
        c.ellipse((125, 141, 131, 147), c.ink, False)
    if pose == 8:
        # A small breath curl rather than a text glyph outside the safe area.
        c.line([(139, 141), (143, 138), (146, 140), (145, 143)], c.deck, 1.3)
    if c.style == "hand-drawn":
        for x in (104, 108, 148, 152):
            c.line([(x, 150), (x - 2, 154)], c.deck, 0.7)


def draw_keyboard(c, pose):
    c.shape([(85, 162), (171, 162), (175, 179), (172, 183), (84, 183), (81, 179)], c.deck)
    c.shape([(87, 164), (169, 164), (172, 178), (84, 178)], c.key, False)
    if c.style == "iconic":
        for y in (168, 174):
            c.line([(90, y), (140 if pose == 6 else 166, y)], c.deck, 2)
    else:
        for row in range(2):
            for col in range(7 if pose == 6 else 10):
                x, y = 89 + col * 8, 166 + row * 6
                c.shape([(x, y), (x + 5, y), (x + 5.5, y + 3), (x - 0.5, y + 3)], c.deck, False)
    # Keep the deck anchored; emphasize an enlarged Enter cap only in the Enter reaction.
    if pose == 6:
        c.shape([(149, 165), (166, 165), (168, 176), (150, 176)], c.blue, c.style not in ("iconic", "paper-cutout"), 1)
        c.line([(161, 168), (161, 172), (155, 172), (157, 170)], c.cream, 1.2)


def draw_wings(c, pose):
    # Short movements around fixed shoulders, not a linear animation strip.
    tips = {
        0: ((85, 159), (171, 159)), 1: ((85, 159), (171, 159)),
        2: ((105, 160), (151, 160)), 3: ((110, 168), (153, 158)),
        4: ((103, 158), (149, 168)), 5: ((111, 166), (149, 166)),
        6: ((101, 156), (159, 171)), 7: ((105, 165), (151, 165)),
        8: ((118, 160), (138, 160)),
    }
    for side, (tx, ty) in zip((-1, 1), tips[pose]):
        shoulder = 128 + side * 39
        if c.style == "iconic":
            c.path((shoulder, 137), [(shoulder + side * 9, 148, tx + side * 8, ty + 5, tx, ty + 6),
                                    (tx - side * 5, ty + 5, shoulder - side * 3, 146, shoulder, 137)], c.body, False)
        elif c.style == "paper-cutout":
            c.shape([(shoulder, 136), (shoulder + side * 6, 145), (tx + side * 5, ty),
                     (tx, ty + 6), (tx - side * 5, ty + 1), (shoulder - side * 4, 143)], c.body)
        else:
            c.path((shoulder, 137), [(shoulder + side * 14, 145, tx + side * 9, ty + 7, tx, ty + 6),
                                    (tx - side * 8, ty + 5, shoulder - side * 5, 143, shoulder, 137)], c.body)
            if c.style == "anime":
                c.line([(shoulder + side, 143), (tx + side * 2, ty + 1)], "#7186a4", 1.5)
            if c.style == "retro-cartoon" and pose in (3, 4, 5, 6):
                c.ellipse((tx - 6, ty - 1, tx + 6, ty + 7), c.cream)
                c.line([(tx - 2, ty + 1), (tx - 2, ty + 4)], width=0.9)
                c.line([(tx + 2, ty + 1), (tx + 2, ty + 4)], width=0.9)
    if pose == 5:
        c.line([(99, 150), (96, 154)], c.blue, 1.5)
        c.line([(157, 150), (160, 154)], c.blue, 1.5)
    if pose == 6:
        c.shape([(172, 145), (174, 150), (179, 152), (174, 154),
                 (172, 159), (170, 154), (165, 152), (170, 150)], c.gold, False)
        c.line([(160, 158), (161, 154)], c.gold, 1.5)


def render_cell(style, pose):
    c = Canvas(style)
    draw_body(c)
    draw_hat(c)
    draw_face(c, pose)
    if 2 <= pose <= 6:
        draw_keyboard(c, pose)
    draw_wings(c, pose)
    return c.finish()


def render_sheet(style):
    cells = [render_cell(style, pose) for pose in range(9)]
    sheet = Image.new("RGBA", (CELL * 3, CELL * 3))
    for i, cell in enumerate(cells):
        sheet.paste(cell, ((i % 3) * CELL, (i // 3) * CELL))
    return sheet, cells


def digest(image):
    return hashlib.sha256(image.tobytes()).hexdigest()


def validate(sheet, cells, style):
    if sheet.mode != "RGBA" or sheet.size != (768, 768):
        raise ValueError(f"{style}: expected a 768x768 RGBA PNG")
    bounds = []
    for i, expected in enumerate(cells):
        x, y = (i % 3) * CELL, (i // 3) * CELL
        crop = sheet.crop((x, y, x + CELL, y + CELL))
        if crop.tobytes() != expected.tobytes():
            raise ValueError(f"{style}/{POSES[i]}: stale artwork or incorrect crop")
        alpha = crop.getchannel("A")
        box = alpha.getbbox()
        if not box or min(box[:2]) < 64 or max(box[2:]) > 192:
            raise ValueError(f"{style}/{POSES[i]}: art must fit central 50%, got {box}")
        if alpha.getextrema() != (0, 255):
            raise ValueError(f"{style}/{POSES[i]}: missing transparent or opaque pixels")
        # An unchanged hat proves position and scale, not just a similar bounding box.
        if crop.crop((64, 64, 192, 110)).tobytes() != cells[0].crop((64, 64, 192, 110)).tobytes():
            raise ValueError(f"{style}/{POSES[i]}: hat/head anchor moved")
        if crop.crop((64, 188, 192, 192)).tobytes() != cells[0].crop((64, 188, 192, 192)).tobytes():
            raise ValueError(f"{style}/{POSES[i]}: foot baseline moved")
        bounds.append(box)
    if len({b[1] for b in bounds}) != 1 or len({b[3] for b in bounds}) != 1:
        raise ValueError(f"{style}: unstable vertical bounds")
    if len({digest(cell) for cell in cells}) != 9:
        raise ValueError(f"{style}: semantic poses must be distinct")
    if style == "pixel-art" and set(sheet.getchannel("A").get_flattened_data()) != {0, 255}:
        raise ValueError("pixel-art: antialiasing is not allowed")
    return bounds


def contact_sheet(rendered):
    """Two background swatches at actual 120 and 180 px CELL sizes, all nine poses."""
    preview = Image.new("RGB", (1720, 6 * 230 + 64), "#f5f1e8")
    draw = ImageDraw.Draw(preview)
    font = ImageFont.load_default(size=18)
    small = ImageFont.load_default(size=13)
    draw.text((24, 16), "AUTHORED STYLE STUDIES / 120 px light + 180 px dark / all nine semantic poses", fill="#263f50", font=font)
    for row, (style, (_, cells)) in enumerate(rendered.items()):
        y = 64 + row * 230
        draw.text((24, y + 10), style.upper(), fill="#263f50", font=font)
        draw.text((24, y + 40), "120 px", fill="#607080", font=small)
        draw.text((24, y + 116), "180 px", fill="#607080", font=small)
        for index, cell in enumerate(cells):
            x = 180 + index * 170
            method = Image.Resampling.NEAREST if style == "pixel-art" else Image.Resampling.LANCZOS
            # Crop only the known transparent margin for a compact review layout.
            light = cell.resize((120, 120), method).crop((27, 27, 93, 93))
            dark = cell.resize((180, 180), method).crop((40, 40, 140, 140))
            draw.rounded_rectangle((x, y, x + 150, y + 204), radius=10, fill="#e6e0d4")
            draw.rectangle((x, y + 79, x + 150, y + 204), fill="#202e40")
            preview.paste(light, (x + 42, y + 6), light)
            preview.paste(dark, (x + 25, y + 83), dark)
            draw.text((x + 5, y + 209), f"{index + 1} {POSES[index]}", fill="#263f50", font=small)
    return preview


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate shipped PNGs and regenerate in memory; never write")
    args = parser.parse_args()
    if PIL.__version__ != "12.1.0":
        parser.error(f"use Pillow==12.1.0 for reproducible rasterization (found {PIL.__version__})")
    rendered = {style: render_sheet(style) for style in STYLES}
    manifest = {"cellSize": CELL, "poseOrder": POSES, "pixelHashes": {}, "cellBounds": {}}
    for style, (expected, cells) in rendered.items():
        path = OUTPUT / f"{style}.png"
        if args.check:
            with Image.open(path) as shipped:
                shipped.load()
                bounds = validate(shipped, cells, style)
        else:
            bounds = validate(expected, cells, style)
            OUTPUT.mkdir(parents=True, exist_ok=True)
            expected.save(path, compress_level=9)
        manifest["pixelHashes"][style] = [digest(cell) for cell in cells]
        manifest["cellBounds"][style] = bounds
        print(f"PASS {style}: RGBA 768x768, 9 exact 256px crops, >=64px clear margins, fixed hat/feet, sha256 {digest(expected)[:16]}")
    preview = contact_sheet(rendered)
    manifest_text = json.dumps(manifest, indent=2) + "\n"
    if args.check:
        if (OUTPUT / "manifest.json").read_text() != manifest_text:
            raise ValueError("manifest.json is stale; regenerate samples")
        with Image.open(OUTPUT / "contact-sheet.png") as shipped:
            if shipped.mode != preview.mode or shipped.size != preview.size or shipped.tobytes() != preview.tobytes():
                raise ValueError("contact-sheet.png is stale; regenerate samples")
    else:
        (OUTPUT / "manifest.json").write_text(manifest_text)
        preview.save(OUTPUT / "contact-sheet.png", compress_level=9)
    print("PASS manifest and 120/180px light/dark contact sheet match deterministic source")


if __name__ == "__main__":
    main()
