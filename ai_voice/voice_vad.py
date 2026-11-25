"""Offline 16 kHz Silero inference and explicit setup of the upstream MIT model."""

from __future__ import annotations

import hashlib
from pathlib import Path
from urllib.request import urlopen

from features import TARGET_SR

VAD_SAMPLES = 512
MODEL_PATH = Path(__file__).resolve().with_name("silero_vad.onnx")
UPSTREAM = "https://raw.githubusercontent.com/snakers4/silero-vad/5cd7945676eb32225748052e2e6a0580e4686a08"
MODEL_SHA256 = "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"


class SileroVAD:
    """Send consecutive 32 ms frames to the Silero v6.2.3 ONNX model."""

    def __init__(self, path: Path) -> None:
        import numpy as np
        import onnxruntime as ort

        options = ort.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 1
        self.session = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
        self.np = np
        self.sample_rate = np.array(TARGET_SR, dtype=np.int64)
        self.reset()

    def reset(self) -> None:
        self.state = self.np.zeros((2, 1, 128), dtype=self.np.float32)
        self.context = self.np.zeros((1, 64), dtype=self.np.float32)

    def predict(self, frame) -> float:
        audio = self.np.asarray(frame, dtype=self.np.float32).reshape(1, VAD_SAMPLES)
        audio = self.np.concatenate((self.context, audio), axis=1)
        probability, self.state = self.session.run(
            None, {"input": audio, "state": self.state, "sr": self.sample_rate}
        )
        self.context = audio[:, -self.context.shape[1]:]
        return float(probability.item())


def install_model() -> None:
    with urlopen(f"{UPSTREAM}/src/silero_vad/data/silero_vad.onnx", timeout=30) as response:
        model = response.read()
    if hashlib.sha256(model).hexdigest() != MODEL_SHA256:
        raise SystemExit("Silero VAD: SHA-256 не совпадает. Файл модели не сохранён.")
    with urlopen(f"{UPSTREAM}/LICENSE", timeout=30) as response:
        license_text = response.read()
    MODEL_PATH.with_name("SILERO_LICENSE.txt").write_bytes(license_text)
    MODEL_PATH.write_bytes(model)
    print(f"Silero VAD v6.2.3: {MODEL_PATH}")


if __name__ == "__main__":
    install_model()
