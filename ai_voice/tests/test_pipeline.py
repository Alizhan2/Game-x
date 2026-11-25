"""Unit tests for the cross-platform Voice AI pipeline (stdlib-safe)."""

from __future__ import annotations

import importlib.util
import json
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from features import LABELS, TARGET_SR, augment_wave, compute_rms, extract_log_mel, resample_to_16k
from voice_engine import build_udp_packet


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

    @unittest.skipUnless(importlib.util.find_spec("numpy") is not None, "numpy not installed in base python3")
    def test_log_mel_shape_when_numpy_available(self) -> None:
        tone = [0.4 * math.sin(2 * math.pi * 300 * i / 16000) for i in range(16000)]
        mel = extract_log_mel(tone, 16000)
        self.assertEqual(mel.shape, (1, 1, 32, 32))


if __name__ == "__main__":
    unittest.main()
