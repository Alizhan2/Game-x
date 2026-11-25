"""Unit tests for the cross-platform Voice AI pipeline (stdlib-safe)."""

from __future__ import annotations

import importlib.util
import json
import math
import struct
import sys
import tempfile
import unittest
import wave
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from features import LABELS, TARGET_SAMPLES, TARGET_SR, augment_wave, compute_rms, extract_log_mel, resample_to_16k
from pack_dataset import organize_and_pack, read_wav_pcm16
from voice_engine import AdaptiveNoiseGate, build_udp_packet, select_prediction


class TestVoicePipeline(unittest.TestCase):
    def test_labels_and_resampling(self) -> None:
        self.assertEqual(LABELS, ["background", "virdan", "noktar", "targum"])
        # 1 second of 48 kHz Mac mic input -> 16 000 samples
        mac_48k = [math.sin(2 * math.pi * 440 * i / 48000) for i in range(48000)]
        res = resample_to_16k(mac_48k, 48000)
        self.assertEqual(len(res), TARGET_SR)

    def test_rms_whisper_vs_shout(self) -> None:
        whisper = [0.02] * 400
        shout = [0.25] * 400
        self.assertLess(compute_rms(whisper), 0.15)
        self.assertGreater(compute_rms(shout), 0.7)

    def test_augment_preserves_bounds(self) -> None:
        src = [0.5 * math.sin(i * 0.1) for i in range(800)]
        aug = augment_wave(src)
        self.assertEqual(len(aug), len(src))
        self.assertTrue(all(-1.0 <= x <= 1.0 for x in aug))

    def test_udp_packet_schema(self) -> None:
        raw = build_udp_packet(
            spell="virdan",
            confidence=0.9412,
            volume=0.8123,
            is_speech=True,
            silence_sec=0.0,
        )
        data = json.loads(raw.decode("utf-8"))
        self.assertEqual(data["spell"], "virdan")
        self.assertAlmostEqual(data["confidence"], 0.941, places=3)
        self.assertTrue(data["is_speech"])
        self.assertTrue(data["calibrated"])

    def test_udp_packet_telemetry_fields(self) -> None:
        raw = build_udp_packet(
            spell="noktar",
            confidence=0.88,
            volume=0.19,
            is_speech=True,
            silence_sec=0.0,
            noise_floor=0.0312,
            vad_mode="silero",
        )
        data = json.loads(raw.decode("utf-8"))
        self.assertEqual(data["spell"], "noktar")
        self.assertAlmostEqual(data["noise_floor"], 0.0312, places=4)
        self.assertEqual(data["vad_mode"], "silero")

    def test_adaptive_noise_gate_calibration_and_silence(self) -> None:
        gate = AdaptiveNoiseGate(min_threshold=0.06, margin=2.2)
        thresh = gate.calibrate_noise([0.04, 0.05, 0.045, 0.055, 0.20])
        self.assertGreaterEqual(thresh, 0.09)

        is_speech, sil = gate.update(volume=0.04, now=10.0)
        self.assertFalse(is_speech)
        self.assertAlmostEqual(sil, 0.0, places=3)

        # Still quiet after 5.3 seconds -> Ending B ready
        is_speech, sil = gate.update(volume=0.04, now=15.3)
        self.assertFalse(is_speech)
        self.assertGreaterEqual(sil, 5.0)

        # Speech resets silence counter
        is_speech, sil = gate.update(volume=0.25, now=16.0, vad_speech_prob=0.85)
        self.assertTrue(is_speech)
        self.assertEqual(sil, 0.0)

    def test_select_prediction_few_shot_boost(self) -> None:
        # High ONNX confidence keeps original class
        spell, conf = select_prediction([0.02, 0.89, 0.05, 0.04], LABELS)
        self.assertEqual(spell, "virdan")
        self.assertAlmostEqual(conf, 0.89, places=3)

        # Uncertain ONNX confidence (<0.72) boosted by matching calibration prototype
        protos = {
            "virdan": [1.0, 0.0, 0.0],
            "noktar": [0.0, 1.0, 0.0],
            "targum": [0.0, 0.0, 1.0],
        }
        spell_b, conf_b = select_prediction(
            [0.35, 0.25, 0.25, 0.15],
            LABELS,
            mel_vec=[0.05, 0.98, 0.02],
            prototypes=protos,
        )
        self.assertEqual(spell_b, "noktar")
        self.assertGreaterEqual(conf_b, 0.78)

    def test_pack_dataset_imports_and_zips(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            import_dir = root / "downloads"
            dataset_dir = root / "dataset_raw"
            out_zip = root / "dataset_raw.zip"
            import_dir.mkdir(parents=True, exist_ok=True)

            # Create a 48kHz 1.0s synthetic WAV matching web_recorder output naming
            wav_path = import_dir / "virdan__ali_normal_001.wav"
            samples_48k = [
                int(12000 * math.sin(2.0 * math.pi * 320.0 * i / 48000.0))
                for i in range(48000)
            ]
            with wave.open(str(wav_path), "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(48000)
                wf.writeframes(struct.pack(f"<{len(samples_48k)}h", *samples_48k))

            counts = organize_and_pack(
                dataset_dir=dataset_dir,
                import_dir=import_dir,
                out_zip=out_zip,
            )
            self.assertEqual(counts["virdan"], 1)
            normalized_wav = dataset_dir / "virdan" / "virdan__ali_normal_001.wav"
            self.assertTrue(normalized_wav.is_file())

            norm_samples, norm_sr = read_wav_pcm16(normalized_wav)
            self.assertEqual(norm_sr, TARGET_SR)
            self.assertEqual(len(norm_samples), TARGET_SAMPLES)

            self.assertTrue(out_zip.is_file())
            with zipfile.ZipFile(out_zip, "r") as zf:
                self.assertIn("dataset_raw/virdan/virdan__ali_normal_001.wav", zf.namelist())

    @unittest.skipUnless(importlib.util.find_spec("numpy") is not None, "numpy not installed in base python3")
    def test_log_mel_shape_when_numpy_available(self) -> None:
        tone = [0.4 * math.sin(2 * math.pi * 300 * i / 16000) for i in range(16000)]
        mel = extract_log_mel(tone, 16000)
        self.assertEqual(mel.shape, (1, 1, 32, 32))


if __name__ == "__main__":
    unittest.main()
