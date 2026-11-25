"""Generate a multi-voice bootstrap WAV dataset (96 clips, 16 kHz mono) via macOS speech synthesis + ambient noise."""

from __future__ import annotations

import math
import random
import struct
import subprocess
import wave
from pathlib import Path

from features import TARGET_SAMPLES, TARGET_SR, pad_or_trim

BASE_DIR = Path(__file__).resolve().parent
OUT_DIR = BASE_DIR / "bootstrap_raw"

VOICES = [
    ("Milena (Russian (Russia))", "ru"),
    ("Daniel", "en"),
    ("Fred", "en"),
    ("Kathy", "en"),
    ("Eddy (English (US))", "en"),
    ("Flo (English (US))", "en"),
]

SPELL_PROMPTS = {
    "virdan": {
        "ru": ["Вирдан", "Вирдаан", "Вирдан!", "Виирдан"],
        "en": ["Virdan", "Veerdan", "Virdaan", "Vir dan"],
    },
    "noktar": {
        "ru": ["Ноктар", "Ноктаар", "Ноктар!", "Нооктар"],
        "en": ["Noktar", "Noktarr", "Nok tar", "Noctar"],
    },
    "targum": {
        "ru": ["Таргум", "Таргуум", "Таргум!", "Тааргум"],
        "en": ["Targum", "Targuum", "Tar gum", "Targoom"],
    },
}

BACKGROUND_WORDS = [
    ("Milena (Russian (Russia))", "привет"),
    ("Milena (Russian (Russia))", "магия"),
    ("Milena (Russian (Russia))", "щит"),
    ("Milena (Russian (Russia))", "вперёд"),
    ("Milena (Russian (Russia))", "атака"),
    ("Milena (Russian (Russia))", "огонь"),
    ("Daniel", "hello"),
    ("Fred", "start"),
    ("Kathy", "game"),
    ("Eddy (English (US))", "shield"),
    ("Flo (English (US))", "magic"),
    ("Daniel", "world"),
]


def _check_wav_peak(wav_path: Path) -> float:
    with wave.open(str(wav_path), "rb") as wf:
        raw = wf.readframes(wf.getnframes())
    count = len(raw) // 2
    if count == 0:
        return 0.0
    ints = struct.unpack(f"<{count}h", raw)
    return max(abs(x) for x in ints) / 32768.0


def _synth_say_wav(voice: str, text: str, rate: int, out_wav: Path, gain: float = 1.0) -> None:
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    aiff_path = out_wav.with_suffix(".aiff")
    subprocess.run(
        ["say", "-v", voice, "-r", str(rate), "-o", str(aiff_path), text],
        check=True,
    )
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", f"LEI16@{TARGET_SR}", "-c", "1", str(aiff_path), str(out_wav)],
        check=True,
    )
    aiff_path.unlink(missing_ok=True)

    peak = _check_wav_peak(out_wav)
    if peak <= 0.05:
        raise RuntimeError(
            f"Synthesized audio {out_wav.name} is silent (peak={peak:.4f}). "
            "Run outside sandbox (BypassSandbox=true) so macOS speechsynthesisd can render audio."
        )

    # Normalize duration to exact CLIP_SECONDS (1.2s) and apply optional gain (simulates whisper/shout)
    with wave.open(str(out_wav), "rb") as wf:
        raw = wf.readframes(wf.getnframes())
    ints = struct.unpack(f"<{len(raw) // 2}h", raw)
    samples = pad_or_trim([max(-1.0, min(1.0, (x / 32768.0) * gain)) for x in ints], TARGET_SAMPLES)
    pcm = [max(-32768, min(32767, int(round(x * 32767.0)))) for x in samples]
    with wave.open(str(out_wav), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(TARGET_SR)
        wf.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))


def _write_noise_wav(out_wav: Path, rng: random.Random, amp: float, hum_hz: float) -> None:
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    pcm = []
    for i in range(TARGET_SAMPLES):
        val = (
            amp * 0.4 * math.sin(2.0 * math.pi * hum_hz * i / TARGET_SR)
            + rng.uniform(-amp, amp)
        )
        pcm.append(max(-32768, min(32767, int(round(val * 32767.0)))))
    with wave.open(str(out_wav), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(TARGET_SR)
        wf.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))


def main() -> int:
    rng = random.Random(2026)
    rates = [145, 165, 185, 210]
    gains = [0.35, 0.75, 1.0, 1.15]

    for spell, lang_map in SPELL_PROMPTS.items():
        idx = 0
        for v_idx, (voice, lang) in enumerate(VOICES):
            prompts = lang_map[lang]
            for rep in range(4):
                idx += 1
                text = prompts[(v_idx + rep) % len(prompts)]
                rate = rates[(v_idx + rep) % len(rates)]
                gain = gains[(v_idx + rep) % len(gains)]
                out_wav = OUT_DIR / spell / f"{spell}__boot{v_idx+1}_{idx:03d}.wav"
                _synth_say_wav(voice, text, rate, out_wav, gain=gain)
        print(f"Generated {idx} speech clips for '{spell}'")

    bg_idx = 0
    for voice, word in BACKGROUND_WORDS:
        bg_idx += 1
        out_wav = OUT_DIR / "background" / f"background__word_{bg_idx:03d}.wav"
        _synth_say_wav(voice, word, rng.choice(rates), out_wav, gain=rng.uniform(0.5, 1.0))

    for n_i in range(12):
        bg_idx += 1
        out_wav = OUT_DIR / "background" / f"background__noise_{bg_idx:03d}.wav"
        _write_noise_wav(
            out_wav,
            rng,
            amp=rng.uniform(0.004, 0.07),
            hum_hz=rng.choice([50.0, 60.0, 100.0, 120.0]),
        )
    print(f"Generated {bg_idx} clips for 'background' (12 speech + 12 ambient noise)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
