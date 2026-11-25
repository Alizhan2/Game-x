"""Record 16 kHz mono WAV spell samples for Echoes of Arcana."""

from __future__ import annotations

import argparse
import time
import wave
from pathlib import Path

from features import CLIP_SECONDS, LABELS, TARGET_SR


def save_wav(path: Path, pcm_int16_bytes: bytes, sr: int = TARGET_SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm_int16_bytes)


def main() -> int:
    parser = argparse.ArgumentParser(description="Record 16kHz mono spell clips into dataset_raw/")
    parser.add_argument("--speaker", required=True, help="Teammate name (e.g. ali)")
    parser.add_argument("--word", required=True, choices=LABELS, help="Target spell label")
    parser.add_argument("--count", type=int, default=25, help="Number of clips to record")
    args = parser.parse_args()

    try:
        import numpy as np
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Install dependencies first: pip install -r ai_voice/requirements.txt"
        ) from exc

    out_dir = Path(__file__).resolve().parent / "dataset_raw" / args.word
    out_dir.mkdir(parents=True, exist_ok=True)
    n_samples = int(TARGET_SR * CLIP_SECONDS)

    print(f"Recording {args.count} samples for '{args.word}' (speaker={args.speaker}) at {TARGET_SR} Hz.")
    print("Vary volume: whisper some, shout others!")
    for idx in range(1, args.count + 1):
        input(f"[{idx}/{args.count}] Press Enter and say '{args.word}'...")
        audio = sd.rec(n_samples, samplerate=TARGET_SR, channels=1, dtype="int16")
        sd.wait()
        fname = out_dir / f"{args.speaker}_{int(time.time() * 1000)}_{idx:03d}.wav"
        save_wav(fname, np.asarray(audio).tobytes(), TARGET_SR)
        print(f"  Saved {fname.name}")

    print("Done!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
