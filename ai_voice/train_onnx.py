"""Train a compact 2D-CNN spell classifier and export to spell_model.onnx."""

from __future__ import annotations

import argparse
import random
import wave
from pathlib import Path

from features import LABELS, TARGET_SAMPLES, augment_wave, extract_log_mel


def read_wav_float(path: Path) -> tuple[list[float], int]:
    import struct

    with wave.open(str(path), "rb") as wf:
        sr = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)
        count = len(raw) // 2
        ints = struct.unpack(f"<{count}h", raw)
        return [x / 32768.0 for x in ints], sr


def build_cnn(num_classes: int):
    import torch
    import torch.nn as nn

    class SpellCNN(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.features = nn.Sequential(
                nn.Conv2d(1, 16, kernel_size=3, padding=1),
                nn.BatchNorm2d(16),
                nn.ReLU(),
                nn.MaxPool2d(2),
                nn.Conv2d(16, 32, kernel_size=3, padding=1),
                nn.BatchNorm2d(32),
                nn.ReLU(),
                nn.MaxPool2d(2),
                nn.Conv2d(32, 48, kernel_size=3, padding=1),
                nn.ReLU(),
                nn.AdaptiveAvgPool2d((1, 1)),
            )
            self.classifier = nn.Linear(48, num_classes)

        def forward(self, x):
            feat = self.features(x).flatten(1)
            return self.classifier(feat)

    return SpellCNN()


def main() -> int:
    parser = argparse.ArgumentParser(description="Train SpellCNN and export spell_model.onnx")
    parser.add_argument("--epochs", type=int, default=25)
    parser.add_argument("--aug-per-sample", type=int, default=5)
    parser.add_argument("--synthetic-smoke", action="store_true", help="Verify ONNX export without dataset_raw/")
    args = parser.parse_args()

    try:
        import numpy as np
        import torch
        import torch.nn as nn
    except ImportError as exc:
        raise SystemExit("Install dependencies first: pip install -r ai_voice/requirements.txt") from exc

    base_dir = Path(__file__).resolve().parent
    dataset_dir = base_dir / "dataset_raw"
    out_onnx = base_dir / "spell_model.onnx"

    xs, ys = [], []
    rng = random.Random(42)

    if args.synthetic_smoke:
        for label_idx in range(len(LABELS)):
            for _ in range(16):
                freq = 180.0 + label_idx * 220.0
                wave_data = [
                    0.5 * np.sin(2.0 * np.pi * freq * t / 16000.0)
                    for t in range(TARGET_SAMPLES)
                ]
                xs.append(extract_log_mel(augment_wave(wave_data, rng))[0])
                ys.append(label_idx)
    else:
        for label_idx, label in enumerate(LABELS):
            folder = dataset_dir / label
            if not folder.exists():
                continue
            for wav_file in sorted(folder.glob("*.wav")):
                samples, sr = read_wav_float(wav_file)
                xs.append(extract_log_mel(samples, sr)[0])
                ys.append(label_idx)
                for _ in range(args.aug_per_sample):
                    aug = augment_wave(samples, rng)
                    xs.append(extract_log_mel(aug, sr)[0])
                    ys.append(label_idx)

    if not xs:
        raise SystemExit(
            f"No samples found in {dataset_dir}. Record clips with record_dataset.py or pass --synthetic-smoke."
        )

    X = np.stack(xs).astype(np.float32)
    Y = np.asarray(ys, dtype=np.int64)

    perm = np.random.permutation(len(X))
    X, Y = X[perm], Y[perm]
    split = max(1, int(0.8 * len(X)))
    X_tr, Y_tr = torch.from_numpy(X[:split]), torch.from_numpy(Y[:split])
    X_val, Y_val = torch.from_numpy(X[split:]), torch.from_numpy(Y[split:])

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    model = build_cnn(len(LABELS)).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(1, args.epochs + 1):
        model.train()
        opt.zero_grad()
        logits = model(X_tr.to(device))
        loss = loss_fn(logits, Y_tr.to(device))
        loss.backward()
        opt.step()

        if epoch % 5 == 0 or epoch == args.epochs:
            model.eval()
            with torch.no_grad():
                if len(X_val) > 0:
                    preds = model(X_val.to(device)).argmax(dim=1).cpu()
                    acc = float((preds == Y_val).float().mean()) * 100.0
                else:
                    acc = 100.0
            print(f"Epoch {epoch:02d}/{args.epochs} | loss={loss.item():.4f} | val_acc={acc:.1f}%")

    model.eval().cpu()
    dummy = torch.randn(1, 1, 32, 32)
    torch.onnx.export(
        model,
        dummy,
        str(out_onnx),
        input_names=["mel"],
        output_names=["logits"],
        dynamic_axes={"mel": {0: "batch"}, "logits": {0: "batch"}},
    )
    print(f"Exported ONNX model to {out_onnx}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
