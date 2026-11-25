"""Record 16 kHz mono WAV spell samples for Echoes of Arcana.

Совет для команды: если Python/sounddevice ещё не установлен, откройте ai_voice/web_recorder.html
в браузере, соберите клипы от всех 3 участников и упакуйте через pack_dataset.py.
"""

from __future__ import annotations

import argparse
import re
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


def _record_word(sd, np, *, speaker: str, word: str, count: int, out_dir: Path) -> None:
    word_dir = out_dir / word
    word_dir.mkdir(parents=True, exist_ok=True)
    n_samples = int(TARGET_SR * CLIP_SECONDS)

    print(f"\n=== Класс '{word.upper()}' ({count} клипов, speaker={speaker}, {TARGET_SR} Hz) ===")
    if word == "background":
        print("Чередуй тишину, шум комнаты и обычную речь без заклинаний.")
    else:
        print("Чередуй громкость: часть шёпотом, часть обычно, часть громко!")
    for idx in range(1, count + 1):
        prompt = "запиши фон" if word == "background" else f"произнеси '{word}'"
        input(f"[{idx}/{count}] Нажми Enter и {prompt}...")
        audio = sd.rec(n_samples, samplerate=TARGET_SR, channels=1, dtype="int16")
        sd.wait()
        fname = word_dir / f"{word}__{speaker}_{int(time.time() * 1000)}_{idx:03d}.wav"
        save_wav(fname, np.asarray(audio).tobytes(), TARGET_SR)
        print(f"  Сохранено: {fname.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Record 16kHz mono spell clips into dataset_raw/")
    parser.add_argument("--speaker", required=True, help="Teammate name (e.g. ali)")
    parser.add_argument("--word", choices=LABELS, help="Target spell label (omit when using --batch)")
    parser.add_argument("--batch", action="store_true", help="Record all 4 classes sequentially")
    parser.add_argument("--count", type=int, default=15, help="Number of clips per class")
    args = parser.parse_args()

    if not args.batch and not args.word:
        parser.error("Укажите --word <label> или --batch для записи всех 4 классов.")
    if not re.fullmatch(r"[A-Za-z0-9-]+", args.speaker):
        parser.error("Имя участника должно содержать только латинские буквы, цифры или дефис.")
    if args.count < 1:
        parser.error("Укажите положительное число записей.")

    try:
        import numpy as np
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Install dependencies first: pip install -r ai_voice/requirements.txt "
            "(или используйте ai_voice/web_recorder.html в браузере)"
        ) from exc

    out_dir = Path(__file__).resolve().parent / "dataset_raw"
    words = ["virdan", "noktar", "targum", "background"] if args.batch else [args.word]
    for word in words:
        _record_word(sd, np, speaker=args.speaker, word=word, count=args.count, out_dir=out_dir)

    print("\nГотово! Дальше: python ai_voice/pack_dataset.py && загрузка dataset_raw.zip в Colab.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
