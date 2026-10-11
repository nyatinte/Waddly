#!/usr/bin/env python3
"""Check that a finished MP4 really carries the mix.

Decodes the audio straight out of the delivered file and answers three things:

  1. is the music present the whole way through (per-second level, no gaps)?
  2. is it *this* track (correlation against the BGM window)?
  3. did the effects survive the AAC encode (correlation against the master)?

    python3 tools/verify-mix.py
"""

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 48000
AUDIO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # promo/audio

CUTS = {
    "ja": ("../out/waddly-promo-ja-1920x1080-60fps.mp4", "mix-30s.wav", "bgm/magical-motif-30s.wav"),
    "en": ("../out/waddly-promo-en-1920x1080-60fps.mp4", "mix-30s.wav", "bgm/magical-motif-30s.wav"),
}


def decode(path, stream=None):
    """Decode any media to float64 mono at 48 kHz."""
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        cmd = ["ffmpeg", "-v", "error", "-y", "-i", path]
        if stream is not None:
            cmd += ["-map", stream]
        cmd += ["-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", tmp.name]
        subprocess.run(cmd, check=True)
        with wave.open(tmp.name, "rb") as f:
            raw = f.readframes(f.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0


def rms_db(x):
    return 20 * np.log10(max(float(np.sqrt(np.mean(x ** 2))), 1e-9))


def corr(a, b):
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    if n == 0 or a.std() == 0 or b.std() == 0:
        return float("nan")
    return float(np.corrcoef(a, b)[0, 1])


def main():
    cut = sys.argv[1] if len(sys.argv) > 1 else "ja"
    video, master, bgm = (os.path.join(AUDIO, p) for p in CUTS[cut])

    final = decode(video, "0:a:0")
    ref = decode(master)
    music = decode(bgm)
    seconds = int(len(final) / SR)

    print(f"lang {cut} — {video}")
    print(f"  decoded {len(final) / SR:.2f}s of audio, overall level {rms_db(final):.1f} dBFS")
    print(f"  vs the master   : correlation {corr(final, ref):+.4f}, "
          f"level delta {rms_db(final) - rms_db(ref):+.2f} dB")

    print("\n  per-second: level / music-only level / correlation with the music")
    weak = []
    for s in range(seconds):
        a = final[s * SR:(s + 1) * SR]
        m = music[s * SR:(s + 1) * SR]
        c = corr(a, m)
        flag = ""
        if rms_db(a) < -34:
            flag = "  <-- too quiet"
            weak.append(s)
        print(f"    {s:2d}s  {rms_db(a):7.1f}  {rms_db(m):7.1f}  {c:+.3f}{flag}")

    print(f"\n  seconds below -34 dBFS: {weak if weak else 'none'}")
    quiet = [s for s in range(seconds) if rms_db(final[s * SR:(s + 1) * SR]) < -34]
    print(f"  the music is present in every second: {'YES' if not quiet else 'NO'}")
    print(f"  silent (digital-zero) samples: {int(np.sum(np.abs(final) < 1e-6))} "
          f"of {len(final)}")


if __name__ == "__main__":
    main()
