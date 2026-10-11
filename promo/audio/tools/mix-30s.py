#!/usr/bin/env python3
"""Build the 30 second promo mix (the long cut).

Driven by audio/CUE-SHEET.md: the cue sheet and this table are the same list,
so the two stay in step.

    python3 tools/mix-30s.py keytimes-30s.json bgm/magical-motif-30s.wav mix-30s-raw.wav
"""

import json
import sys

import numpy as np

from mixlib import SR, place, read_wav, resample, rng, trim_lead, write_wav

DURATION = 30.0
SFX_DIR = "sfx-norm"

# t, file, gain dB, pitch, max duration
EVENTS = [
    # --- cold open ---------------------------------------------------------
    (0.700, "sparkle-appear", -12, 1.00, 1.10),
    (0.700, "glitter", -20, 1.00, 1.40),
    # --- keyboard + typing -------------------------------------------------
    (2.950, "ui-open", -17, 1.00, 0.40),
    (7.350, "ui-select", -20, 1.00, 0.40),
    # --- AI chat -----------------------------------------------------------
    (7.650, "ui-open", -18, 1.02, 0.40),
    (10.900, "confirm-positive", -13, 1.00, 1.60),
    # --- the app -----------------------------------------------------------
    (11.350, "ui-open", -17, 0.98, 0.40),
    (12.200, "whoosh-fly", -18, 1.00, 1.15),
    (13.350, "pop-drop", -13, 1.00, 0.60),
    (15.500, "sparkle-touch", -16, 1.00, 0.90),
    (16.100, "confirm-tone", -15, 1.00, 0.90),
    # the pet tries the registered sheets on, then comes back to the penguin
    (16.450, "impact-alt", -13, 1.00, 1.30),
    (16.455, "hit-sub", -15, 1.00, 1.10),
    (16.460, "sparkle-appear", -14, 1.06, 1.20),
    (17.050, "sparkle-appear", -15, 1.09, 1.10),
    (17.650, "sparkle-appear", -14, 1.00, 1.20),
    (17.655, "confirm-tone", -16, 1.02, 0.90),
    # --- the status showcase ------------------------------------------------
    (18.000, "reveal-marimba", -15, 1.00, 0.90),
    (18.110, "reveal-marimba", -15, 1.06, 0.90),
    (18.220, "reveal-marimba", -15, 0.94, 0.90),
    (19.800, "ui-select", -19, 1.00, 0.60),
    (20.400, "reveal-marimba", -15, 0.98, 0.90),
    (20.510, "reveal-marimba", -15, 1.08, 0.90),
    (20.620, "reveal-marimba", -15, 0.92, 0.90),
    # --- freedom ------------------------------------------------------------
    (22.600, "ui-select", -19, 1.00, 0.60),
    (23.270, "ui-select", -16, 1.03, 0.70),
    (24.750, "thud-wood", -12, 1.00, 0.50),
    (24.755, "thud-soft", -22, 1.00, 0.80),
    (26.200, "sparkle-touch", -20, 1.04, 0.70),
    # --- the Return finale --------------------------------------------------
    (26.600, "riser-swell", -20, 1.00, 0.95),
    (27.550, "key-hard", -12, 1.00, 0.30),
    (27.556, "impact-big", -8, 1.00, 1.20),
    (27.552, "hit-sub", -14, 1.00, 1.10),
    (27.650, "chime-achievement", -13, 1.00, 1.40),
    (28.150, "chime-winning", -18, 1.00, 1.40),
]

# the nine cells flying into the app: every other one is enough
for i in range(0, 9, 2):
    EVENTS.append((14.100 + i * 0.135, "whoosh-fast", -19.0 - 1.5 * (i // 2), 1.0 + 0.02 * (i % 3), 0.35))

# the prompt typing itself into the chat (the picture types it, not the keyboard)
for i in range(11):
    EVENTS.append((8.550 + i * 0.155, "key-single", -22.0 + 0.6 * (i % 3), 1.0 + 0.02 * (i % 4), 0.14))

# typing runs: the keyboard section and the run that leads into Return
TYPING_RUNS = [(3.20, 7.25), (26.20, 27.55)]
MIN_GAP = 0.06
KEY_LAYERS = [("key-hard", -3.0), ("key-single", -5.0)]
BED_DB = -23.0


def main():
    keys_path, bgm_path, out_path = sys.argv[1:4]

    with open(keys_path) as f:
        key_times = json.load(f)

    bed = np.zeros((int(DURATION * SR), 2))
    bgm = read_wav(bgm_path)
    bed[: min(bgm.shape[0], bed.shape[0])] += bgm[: bed.shape[0]]

    cache = {}

    def sfx(name):
        if name not in cache:
            cache[name] = trim_lead(read_wav(f"{SFX_DIR}/{name}.wav"))
        return cache[name]

    # one consistent key sound: a thock with a click on top
    jitter = rng(0x9A13)
    last = -99.0
    played = 0
    for t in key_times:
        if not any(a <= t <= b for a, b in TYPING_RUNS):
            continue
        if t - last < MIN_GAP:
            continue
        last = t
        pitch = 1.0 + (next(jitter) - 0.5) * 0.05
        level = -15.0 + (next(jitter) - 0.5) * 2.4
        for name, offset in KEY_LAYERS:
            place(bed, t, resample(sfx(name), pitch), level + offset, 0.012)
        played += 1

    sequence = sfx("key-typing-bed")
    for i, (a, b) in enumerate(TYPING_RUNS):
        span = int((b - a) * SR)
        start = int((0.35 + i * 1.7) * SR)
        place(bed, a, sequence[start:start + span], BED_DB, 0.05)

    for t, name, gain, pitch, max_dur in EVENTS:
        data = resample(sfx(name), pitch)[: int(max_dur * SR)]
        place(bed, t, data, gain)

    peak = write_wav(out_path, bed)
    print(f"typing clicks: {played} of {len(key_times)} scheduled keys")
    print(f"accents: {len(EVENTS)}")
    print(f"peak before trim: {20 * np.log10(max(peak, 1e-9)):.2f} dBFS")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
