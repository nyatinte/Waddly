"""Shared helpers for the promo audio mixes.

The mixes are deterministic: every cue time comes from the composition, the
jitter uses a fixed seed, and nothing reads the wall clock. Re-running a build
therefore reproduces the same WAV byte for byte.
"""

import wave

import numpy as np

SR = 48000


def read_wav(path):
    """Read any PCM WAV as float64 stereo at 48 kHz."""
    with wave.open(path, "rb") as f:
        ch = f.getnchannels()
        width = f.getsampwidth()
        sr = f.getframerate()
        raw = f.readframes(f.getnframes())
    dtype = {1: np.uint8, 2: np.int16, 4: np.int32}[width]
    data = np.frombuffer(raw, dtype=dtype).astype(np.float64)
    if width == 1:
        data = (data - 128.0) / 128.0
    else:
        data = data / float(2 ** (8 * width - 1))
    data = data.reshape(-1, ch)
    if ch == 1:
        data = np.repeat(data, 2, axis=1)
    if sr != SR:
        data = resample(data, sr / SR)
    return data


def resample(data, ratio):
    """Linear resample; ratio > 1 plays faster and therefore higher."""
    if abs(ratio - 1.0) < 1e-6:
        return data
    n_out = max(1, int(round(data.shape[0] / ratio)))
    src = np.linspace(0, data.shape[0] - 1, n_out)
    idx = np.floor(src).astype(int)
    frac = (src - idx)[:, None]
    nxt = np.minimum(idx + 1, data.shape[0] - 1)
    return data[idx] * (1 - frac) + data[nxt] * frac


def trim_lead(data, floor_db=-48.0, keep=0.003):
    """Drop leading near-silence so the transient lands on the cue frame.

    The normalised effects still carry a little pre-roll — `key-single` peaked
    26 ms in, which reads as a click that arrives late against the picture.
    A few ms are kept so the attack is not clipped.
    """
    threshold = 10 ** (floor_db / 20.0)
    env = np.abs(data).max(axis=1)
    above = np.nonzero(env > threshold)[0]
    if len(above) == 0:
        return data
    cut = max(0, int(above[0]) - int(keep * SR))
    return data[cut:] if cut else data


def rng(seed):
    """Deterministic value source, so the jitter is reproducible."""
    s = seed & 0xFFFFFFFF
    while True:
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        yield s / 0x7FFFFFFF


def place(bed, t, data, gain_db, fade_out=0.02):
    """Mix one effect into the bed at time t (seconds)."""
    start = int(round(t * SR))
    if start >= bed.shape[0]:
        return
    seg = data[: bed.shape[0] - start] * (10 ** (gain_db / 20.0))
    n_fade = min(int(fade_out * SR), seg.shape[0])
    if n_fade > 1:
        seg = seg.copy()
        seg[-n_fade:] *= np.linspace(1.0, 0.0, n_fade)[:, None]
    bed[start : start + seg.shape[0]] += seg


def write_wav(path, bed, ceiling_db=-1.5):
    """Write 16-bit stereo, trimming the peak to the ceiling if needed."""
    peak = float(np.max(np.abs(bed)))
    if peak > 10 ** (ceiling_db / 20.0):
        bed = bed * (10 ** (ceiling_db / 20.0) / peak)
    with wave.open(path, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(bed, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes())
    return peak
