"""Validate, resample to 16 kHz mono WAV, organize dataset_raw/, and build dataset_raw.zip for Colab."""

from __future__ import annotations

import argparse
import io
import re
import shutil
import struct
import zipfile
import wave
from collections import Counter
from pathlib import Path

from features import LABELS, TARGET_SAMPLES, TARGET_SR, pad_or_trim, resample_to_16k

DEFAULT_AI_DIR = Path(__file__).resolve().parent
RECORDING_NAME = re.compile(
    r"^(?P<speaker>[a-zA-Z0-9_-]+)_(?:normal|whisper|loud|shout|noise)_\d+(?:_\d{10,})?$"
)
LEGACY_RECORDING_NAME = re.compile(r"^(?P<speaker>[a-zA-Z0-9_-]+?)(?:_\d{10,})?_\d+$")


def speaker_from_filename(path: Path) -> str | None:
    _, separator, recording = path.stem.partition("__")
    if not separator:
        return None
    match = RECORDING_NAME.fullmatch(recording) or LEGACY_RECORDING_NAME.fullmatch(recording)
    return match.group("speaker").lower() if match else None


def read_wav_pcm16(path: Path) -> tuple[list[float], int]:
    """Read PCM16 WAV (mono or stereo) into normalized float samples in [-1.0, 1.0]."""
    with wave.open(str(path), "rb") as wf:
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        sr = wf.getframerate()
        n_frames = wf.getnframes()
        if sampwidth != 2 or n_frames <= 0 or sr <= 0:
            raise ValueError(f"Unsupported or empty WAV: {path.name} (width={sampwidth}, frames={n_frames})")
        raw = wf.readframes(n_frames)
        if len(raw) != n_frames * channels * sampwidth:
            raise ValueError(f"Truncated WAV: {path.name}")
    total_ints = len(raw) // 2
    ints = struct.unpack(f"<{total_ints}h", raw[: total_ints * 2])
    if channels == 1:
        return [x / 32768.0 for x in ints], sr
    if channels >= 2:
        mono: list[float] = []
        for i in range(0, len(ints) - channels + 1, channels):
            mono.append(sum(ints[i : i + channels]) / (channels * 32768.0))
        return mono, sr
    raise ValueError(f"Invalid channel count in {path.name}: {channels}")


def write_wav_pcm16_16k(path: Path, samples: list[float], orig_sr: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode_normalized_wav(samples, orig_sr))


def encode_normalized_wav(samples: list[float], orig_sr: int) -> bytes:
    res = pad_or_trim(resample_to_16k(samples, orig_sr), TARGET_SAMPLES)
    pcm = [max(-32768, min(32767, int(round(x * 32768.0)))) for x in res]
    output = io.BytesIO()
    with wave.open(output, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(TARGET_SR)
        wf.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    return output.getvalue()


def detect_label_from_filename(filename: str) -> str | None:
    lower = filename.lower()
    for label in LABELS:
        if lower.startswith(f"{label}__") or lower.startswith(f"{label}_"):
            return label
    return None


def organize_and_pack(
    *,
    dataset_dir: Path,
    import_dir: Path | None = None,
    out_zip: Path,
) -> dict[str, int]:
    """Import prefixed WAVs, normalize everything in dataset_raw/ to 16kHz mono, and zip for Colab."""
    for label in LABELS:
        (dataset_dir / label).mkdir(parents=True, exist_ok=True)

    if import_dir is not None and import_dir.exists():
        for wav_file in sorted(import_dir.glob("*.wav")):
            label = detect_label_from_filename(wav_file.name)
            if label is None:
                continue
            target = dataset_dir / label / wav_file.name
            if wav_file.resolve() != target.resolve():
                if target.exists():
                    if wav_file.read_bytes() != target.read_bytes() and (
                        encode_normalized_wav(*read_wav_pcm16(wav_file))
                        != encode_normalized_wav(*read_wav_pcm16(target))
                    ):
                        raise ValueError(f"Conflicting recording: {target.name}. Rename it before importing.")
                    continue
                shutil.copy2(wav_file, target)

    counts: dict[str, int] = {label: 0 for label in LABELS}
    speakers: Counter[str] = Counter()
    skipped: list[str] = []
    accepted: list[tuple[str, Path, bytes]] = []

    for label in LABELS:
        folder = dataset_dir / label
        for wav_file in sorted(folder.glob("*.wav")):
            try:
                samples, sr = read_wav_pcm16(wav_file)
                resampled = pad_or_trim(resample_to_16k(samples, sr), TARGET_SAMPLES)
                peak = max(abs(x) for x in resampled)
                if label != "background" and peak < 0.002:
                    skipped.append(f"{wav_file.name} (тишина)")
                    continue
                prefix, separator, _ = wav_file.name.partition("__")
                if separator and prefix.lower() != label:
                    skipped.append(f"{wav_file.name} (класс в имени расходится с папкой)")
                    continue
                accepted.append((label, wav_file, encode_normalized_wav(resampled, TARGET_SR)))
                counts[label] += 1
                speaker = speaker_from_filename(wav_file)
                if speaker:
                    speakers[speaker] += 1
            except (OSError, ValueError, EOFError, wave.Error) as exc:
                skipped.append(f"{wav_file.name} ({exc})")

    out_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for label, wav_file, audio in accepted:
            if wav_file.read_bytes() != audio:
                wav_file.write_bytes(audio)
            zf.writestr(f"dataset_raw/{label}/{wav_file.name}", audio)

    print("=== Сводка датасета ===")
    for label in LABELS:
        print(f"  {label:<12}: {counts[label]} клипов")
    if speakers:
        print("  По спикерам :", ", ".join(f"{k}={v}" for k, v in sorted(speakers.items())))
    if skipped:
        print("  Пропущено   :", ", ".join(skipped))
    print(f"Готовый архив для Google Colab: {out_zip}")
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate WAV clips and pack dataset_raw.zip for Colab")
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_AI_DIR / "dataset_raw")
    parser.add_argument(
        "--import-dir",
        type=Path,
        default=None,
        help="Optional folder (e.g. ~/Downloads) with <word>__<speaker>.wav from web_recorder.html",
    )
    parser.add_argument("--out-zip", type=Path, default=DEFAULT_AI_DIR / "dataset_raw.zip")
    args = parser.parse_args()

    organize_and_pack(dataset_dir=args.dataset_dir, import_dir=args.import_dir, out_zip=args.out_zip)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
