"""Train a compact 2D-CNN spell classifier and export to spell_model.onnx."""

from __future__ import annotations

import argparse
import inspect
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
                nn.BatchNorm2d(48),
                nn.ReLU(),
                nn.AdaptiveAvgPool2d((1, 1)),
            )
            self.dropout = nn.Dropout(0.15)
            self.classifier = nn.Linear(48, num_classes)

        def forward(self, x):
            feat = self.dropout(self.features(x).flatten(1))
            return self.classifier(feat)

    return SpellCNN()


def main() -> int:
    parser = argparse.ArgumentParser(description="Train SpellCNN and export spell_model.onnx")
    parser.add_argument("--epochs", type=int, default=45)
    parser.add_argument("--aug-per-sample", type=int, default=8)
    parser.add_argument("--synthetic-smoke", action="store_true", help="Verify ONNX export without dataset_raw/")
    args = parser.parse_args()

    try:
        import numpy as np
        import torch
        import torch.nn as nn
        from torch.utils.data import DataLoader, TensorDataset
    except ImportError as exc:
        raise SystemExit("Install dependencies first: pip install -r ai_voice/requirements.txt") from exc

    base_dir = Path(__file__).resolve().parent
    dataset_dir = base_dir / "dataset_raw"
    out_onnx = base_dir / "spell_model.onnx"

    tr_xs, tr_ys, val_xs, val_ys = [], [], [], []
    rng = random.Random(42)

    if args.synthetic_smoke:
        for label_idx in range(len(LABELS)):
            for i in range(16):
                freq = 180.0 + label_idx * 220.0
                wave_data = [
                    0.5 * np.sin(2.0 * np.pi * freq * t / 16000.0)
                    for t in range(TARGET_SAMPLES)
                ]
                feat = extract_log_mel(augment_wave(wave_data, rng))[0]
                if i < 12:
                    tr_xs.append(feat)
                    tr_ys.append(label_idx)
                else:
                    val_xs.append(feat)
                    val_ys.append(label_idx)
    else:
        for label_idx, label in enumerate(LABELS):
            folder = dataset_dir / label
            if not folder.exists():
                continue
            wav_files = sorted(folder.glob("*.wav"))
            rng.shuffle(wav_files)
            split_idx = max(1, int(0.75 * len(wav_files))) if len(wav_files) > 1 else len(wav_files)
            for idx_file, wav_file in enumerate(wav_files):
                samples, sr = read_wav_float(wav_file)
                is_train = idx_file < split_idx
                target_x = tr_xs if is_train else val_xs
                target_y = tr_ys if is_train else val_ys
                target_x.append(extract_log_mel(samples, sr)[0])
                target_y.append(label_idx)
                aug_count = args.aug_per_sample if is_train else 2
                for _ in range(aug_count):
                    aug = augment_wave(samples, rng)
                    target_x.append(extract_log_mel(aug, sr)[0])
                    target_y.append(label_idx)

    if not tr_xs:
        raise SystemExit(
            f"No samples found in {dataset_dir}. Record clips with record_dataset.py or pass --synthetic-smoke."
        )

    X_tr = torch.from_numpy(np.stack(tr_xs).astype(np.float32))
    Y_tr = torch.from_numpy(np.asarray(tr_ys, dtype=np.int64))
    X_val = torch.from_numpy(np.stack(val_xs).astype(np.float32)) if val_xs else X_tr
    Y_val = torch.from_numpy(np.asarray(val_ys, dtype=np.int64)) if val_ys else Y_tr

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    model = build_cnn(len(LABELS)).to(device)
    opt = torch.optim.Adam(model.parameters(), lr=2e-3, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    loss_fn = nn.CrossEntropyLoss()
    loader = DataLoader(TensorDataset(X_tr, Y_tr), batch_size=32, shuffle=True)

    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        for bx, by in loader:
            bx, by = bx.to(device), by.to(device)
            opt.zero_grad()
            loss = loss_fn(model(bx), by)
            loss.backward()
            opt.step()
            total_loss += float(loss.item()) * len(bx)
        scheduler.step()

        if epoch % 5 == 0 or epoch == args.epochs:
            model.eval()
            with torch.no_grad():
                preds = model(X_val.to(device)).argmax(dim=1).cpu()
                acc = float((preds == Y_val).float().mean()) * 100.0
            print(f"Epoch {epoch:02d}/{args.epochs} | loss={total_loss / len(X_tr):.4f} | val_acc={acc:.1f}%")

    model.eval().cpu()
    dummy = torch.randn(1, 1, 32, 32)
    export_kwargs = {
        "input_names": ["mel"],
        "output_names": ["logits"],
        "dynamic_axes": {"mel": {0: "batch"}, "logits": {0: "batch"}},
        "opset_version": 17,
    }
    if "dynamo" in inspect.signature(torch.onnx.export).parameters:
        export_kwargs["dynamo"] = False

    torch.onnx.export(model, dummy, str(out_onnx), **export_kwargs)
    print(f"Exported ONNX model to {out_onnx}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
