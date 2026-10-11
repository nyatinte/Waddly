#!/usr/bin/env python3
"""Pick the best BGM window for a cut.

This is how 42.8028 s was chosen for the 20 s cut — not by ear but by
measurement:

  1. detect the tempo from the onset envelope (autocorrelation)
  2. score every window by how well the picture's accents land on onsets
  3. print the energy arc, so a quiet dip can be matched to a quiet beat
  4. snap the window to the beat phase under the cut's strongest accent

    python3 tools/analyse-bgm.py "Magical Motif.m4a" 30

Needs ffmpeg on PATH and a numpy-enabled python.
"""

import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 48000

# duration, the moments the cut lands a hit (and how much each matters), the
# accent that must sit on a beat, and the region worth searching
#
# The regions are narrow on purpose: the onset score alone likes other stretches,
# but the cut needs an arc — the 30 s section has to *rise* into the Return
# finale (the 24 s candidate dips right before it), and the score then snaps the
# start to the beat under the strongest accent.
PRESETS = {
    20: (20.0,
         [(0.30, 1.5), (0.98, 3.0), (2.34, 1.2), (9.30, 1.0),
          (10.45, 2.0), (12.05, 2.5), (15.20, 1.5), (17.40, 2.0)],
         0.98, (38.0, 50.0)),
    30: (30.0,
         [(0.70, 1.5), (3.25, 1.0), (8.55, 0.8), (11.35, 1.2), (13.35, 2.0),
          (16.45, 2.5), (17.65, 1.5), (18.00, 1.5), (20.40, 1.5),
          (23.27, 1.5), (24.75, 2.0), (27.55, 3.0), (27.65, 2.0)],
         27.55, (85.0, 95.0)),
}


def decode(path):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "2", "-ar", str(SR),
             "-c:a", "pcm_s16le", tmp.name],
            check=True,
        )
        with wave.open(tmp.name, "rb") as f:
            ch = f.getnchannels()
            raw = f.readframes(f.getnframes())
    return np.frombuffer(raw, dtype=np.int16).reshape(-1, ch).mean(axis=1) / 32768.0


def onset_envelope(x):
    hop, win = 256, 1024
    frames = (len(x) - win) // hop
    idx = np.arange(win)[None, :] + hop * np.arange(frames)[:, None]
    spec = np.abs(np.fft.rfft(x[idx] * np.hanning(win), axis=1))
    flux = np.maximum(0, np.diff(spec, axis=0)).sum(axis=1)
    return flux / (flux.max() + 1e-9), SR / hop


def detect_tempo(flux, fps):
    best = []
    for bpm in np.arange(70, 165, 0.25):
        lag = int(round(60.0 / bpm * fps))
        if lag < 2 or lag >= len(flux) // 2:
            continue
        a, b = flux[:-lag], flux[lag:]
        best.append((float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9)), bpm))
    best.sort(reverse=True)
    return best[0][1]


def main():
    path = sys.argv[1]
    cut = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    duration, accents, anchor, region = PRESETS[cut]

    x = decode(path)
    total = len(x) / SR
    flux, fps = onset_envelope(x)
    bpm = detect_tempo(flux, fps)
    beat = 60.0 / bpm
    print(f"track {total:.2f}s   tempo {bpm:.2f} bpm (beat {beat:.4f}s)   cut {duration:.0f}s")

    def window_score(start):
        s = 0.0
        for at, weight in accents:
            i = int((start + at) * fps)
            lo, hi = max(0, i - 3), min(len(flux), i + 4)
            if hi > lo:
                s += weight * float(flux[lo:hi].max())
        i0 = int(start * fps)
        s += 1.2 * float(flux[max(0, i0 - 2):i0 + 3].max())
        return s

    starts = np.arange(0, total - duration, 0.25)
    if region:
        starts = starts[(starts >= region[0]) & (starts <= region[1])]
    cands = sorted(((window_score(s), s) for s in starts), reverse=True)

    sec = int(total)
    rms = np.array([np.sqrt(np.mean(x[i * SR:(i + 1) * SR] ** 2)) for i in range(sec)])
    db = 20 * np.log10(np.maximum(rms, 1e-6))

    span = int(duration)
    third = span // 3
    print("\ntop windows (score, start, arc):")
    for sc, st in cands[:5]:
        w = db[int(st):int(st) + span]
        if len(w) < span:
            continue
        print(f"  score {sc:5.2f}  start {st:7.2f}s  "
              f"head {w[:third].mean():6.1f}  mid {w[third:2 * third].mean():6.1f}  "
              f"tail {w[2 * third:].mean():6.1f} dB")
        print("      " + " ".join(f"{v:5.1f}" for v in w))

    best = cands[0][1]
    lo_t, hi_t = max(0.0, best - 5.0), best + duration + 5.0

    def phase_score(phi):
        times = [t for t in np.arange(phi, total, beat) if lo_t < t < hi_t]
        if not times:
            return 0.0
        return sum(float(flux[max(0, int(t * fps) - 2):int(t * fps) + 3].max())
                   for t in times) / len(times)

    phase_best = max((phase_score(phi), phi) for phi in np.arange(0, beat, 0.002))[1]
    k = round((best + anchor - phase_best) / beat)
    start = phase_best + k * beat - anchor
    print(f"\nbeat phase {phase_best:.4f}s -> window {start:.4f}s .. {start + duration:.4f}s")
    print(f"  (the hit at {anchor}s now sits exactly on a beat)")


if __name__ == "__main__":
    main()
