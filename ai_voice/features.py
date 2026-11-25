"""Audio preprocessing, 16 kHz cross-platform resampling, RMS volume, and Mel-spectrograms."""

from __future__ import annotations

import math
import random
from typing import Iterable

TARGET_SR = 16000
CLIP_SECONDS = 1.2
TARGET_SAMPLES = int(TARGET_SR * CLIP_SECONDS)
LABELS = ["background", "virdan", "noktar", "targum"]


def resample_to_16k(samples: Iterable[float], orig_sr: int) -> list[float]:
    """Resample mono float audio from any sample rate (48kHz Mac / 44.1kHz Win) to 16 kHz."""
    src = [float(x) for x in samples]
    if not src or orig_sr <= 0:
        return []
    if orig_sr == TARGET_SR:
        return src

    out_len = max(1, int(round(len(src) * (TARGET_SR / float(orig_sr)))))
    if len(src) == 1:
        return [src[0]] * out_len

    ratio = (len(src) - 1) / float(max(1, out_len - 1))
    out: list[float] = []
    for i in range(out_len):
        pos = i * ratio
        idx = int(pos)
        frac = pos - idx
        nxt = min(idx + 1, len(src) - 1)
        out.append(src[idx] * (1.0 - frac) + src[nxt] * frac)
    return out


def pad_or_trim(samples: Iterable[float], target_len: int = TARGET_SAMPLES) -> list[float]:
    """Ensure fixed clip length for CNN/ONNX input."""
    arr = [float(x) for x in samples]
    if len(arr) >= target_len:
        return arr[:target_len]
    return arr + [0.0] * (target_len - len(arr))


def compute_rms(samples: Iterable[float]) -> float:
    """Normalized loudness in [0.0, 1.0] for whisper vs shout detection."""
    arr = [float(x) for x in samples]
    if not arr:
        return 0.0
    mean_sq = sum(x * x for x in arr) / float(len(arr))
    rms = math.sqrt(mean_sq)
    return max(0.0, min(1.0, rms * 3.5))


def augment_wave(samples: list[float], rng: random.Random | None = None) -> list[float]:
    """Lightweight augmentation (shift + gain + noise) to generalize to unfamiliar jury voices."""
    r = rng or random.Random()
    if not samples:
        return []
    shift = r.randint(-int(0.08 * len(samples)), int(0.08 * len(samples)))
    gain = r.uniform(0.65, 1.35)
    noise_amp = r.uniform(0.002, 0.02)

    n = len(samples)
    out = [0.0] * n
    for i in range(n):
        src_i = (i - shift) % n
        val = samples[src_i] * gain + r.uniform(-noise_amp, noise_amp)
        out[i] = max(-1.0, min(1.0, val))
    return out


def _hz_to_mel(hz: float) -> float:
    return 2595.0 * math.log10(1.0 + hz / 700.0)


def _mel_to_hz(mel: float) -> float:
    return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)


def extract_log_mel(
    samples: Iterable[float],
    sr: int = TARGET_SR,
    n_mels: int = 32,
    n_frames: int = 32,
):
    """Return a (1, 1, n_mels, n_frames) float32 numpy array of normalized log-Mel features."""
    try:
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("NumPy is required for extract_log_mel. Run: pip install -r ai_voice/requirements.txt") from exc

    wave = np.asarray(pad_or_trim(resample_to_16k(samples, sr), TARGET_SAMPLES), dtype=np.float32)
    n_fft = 512
    hop = max(1, (len(wave) - n_fft) // max(1, n_frames - 1))
    window = np.hanning(n_fft).astype(np.float32)

    frames = []
    for i in range(n_frames):
        start = i * hop
        chunk = wave[start : start + n_fft]
        if len(chunk) < n_fft:
            chunk = np.pad(chunk, (0, n_fft - len(chunk)))
        spec = np.abs(np.fft.rfft(chunk * window)) ** 2
        frames.append(spec)
    power_spec = np.stack(frames, axis=1)  # (n_fft//2 + 1, n_frames)

    mel_min = _hz_to_mel(60.0)
    mel_max = _hz_to_mel(sr / 2.0)
    mel_pts = np.linspace(mel_min, mel_max, n_mels + 2)
    hz_pts = np.array([_mel_to_hz(m) for m in mel_pts])
    bins = np.floor((n_fft + 1) * hz_pts / sr).astype(int)

    fb = np.zeros((n_mels, n_fft // 2 + 1), dtype=np.float32)
    for m in range(1, n_mels + 1):
        left, center, right = bins[m - 1], bins[m], bins[m + 1]
        for k in range(left, center):
            if center > left:
                fb[m - 1, k] = (k - left) / float(center - left)
        for k in range(center, right):
            if right > center:
                fb[m - 1, k] = (right - k) / float(right - center)

    mel_spec = np.maximum(1e-6, fb @ power_spec)
    log_mel = np.log(mel_spec)
    std = float(log_mel.std())
    norm = (log_mel - float(log_mel.mean())) / (std if std > 1e-5 else 1.0)
    return norm.astype(np.float32)[None, None, :, :]
