"""Real-time Offline Voice Engine (Silero/Energy VAD + ONNX + Few-Shot Calibration + UDP)."""

from __future__ import annotations

import argparse
import json
import math
import socket
import time
from pathlib import Path
from typing import Any

from features import LABELS, TARGET_SAMPLES, TARGET_SR, compute_rms, extract_log_mel

UDP_HOST = "127.0.0.1"
UDP_PORT = 5055


def build_udp_packet(
    *,
    spell: str,
    confidence: float,
    volume: float,
    is_speech: bool,
    silence_sec: float,
    calibrated: bool = True,
) -> bytes:
    """Serialize a uniform JSON packet for Godot PacketPeerUDP."""
    payload: dict[str, Any] = {
        "spell": spell,
        "confidence": round(max(0.0, min(1.0, float(confidence))), 3),
        "volume": round(max(0.0, min(1.0, float(volume))), 3),
        "is_speech": bool(is_speech),
        "silence_sec": round(max(0.0, float(silence_sec)), 2),
        "calibrated": bool(calibrated),
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def softmax(logits: list[float]) -> list[float]:
    m = max(logits)
    exps = [math.exp(x - m) for x in logits]
    s = sum(exps) or 1.0
    return [e / s for e in exps]


def run_simulation(host: str = UDP_HOST, port: int = UDP_PORT) -> None:
    """Stream realistic Chapter I spell events over UDP without needing a microphone."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    script = [
        (1.0, "virdan", 0.96, 0.88, True, 0.0),
        (2.0, "noktar", 0.92, 0.19, True, 0.0),
        (2.0, "targum", 0.98, 0.95, True, 0.0),
        (1.5, "virdan", 0.95, 0.80, True, 0.0),
        (1.5, "noktar", 0.93, 0.72, True, 0.0),
        (1.5, "targum", 0.97, 0.90, True, 0.0),
    ]
    print(f"[SIMULATE] Streaming scripted Chapter I spells to udp://{host}:{port}")
    for delay, spell, conf, vol, speech, sil in script:
        time.sleep(delay)
        pkt = build_udp_packet(
            spell=spell, confidence=conf, volume=vol, is_speech=speech, silence_sec=sil
        )
        sock.sendto(pkt, (host, port))
        print(" ->", pkt.decode("utf-8"))

    # Simulate 5.2 seconds of silence for Ending B test
    for step in range(1, 53):
        time.sleep(0.1)
        pkt = build_udp_packet(
            spell="background", confidence=0.99, volume=0.01, is_speech=False, silence_sec=step * 0.1
        )
        sock.sendto(pkt, (host, port))
    print("[SIMULATE] Completed 5.2s silence sequence.")


def run_live_microphone(
    *,
    model_path: Path,
    host: str = UDP_HOST,
    port: int = UDP_PORT,
    vad_threshold: float = 0.08,
    skip_calibration: bool = False,
) -> None:
    try:
        import numpy as np
        import onnxruntime as ort
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Install dependencies first: pip install -r ai_voice/requirements.txt"
        ) from exc

    if not model_path.is_file():
        raise SystemExit(
            f"Model not found: {model_path}. Train first with train_onnx.py or use --simulate."
        )

    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    calibrated = skip_calibration
    prototypes: dict[str, Any] = {}

    if not skip_calibration:
        print("=== Ритуал привязки голоса (10 сек) ===")
        for word in ("virdan", "noktar", "targum"):
            input(f"Нажми Enter и произнеси '{word.upper()}' один раз...")
            rec = sd.rec(TARGET_SAMPLES, samplerate=TARGET_SR, channels=1, dtype="float32")
            sd.wait()
            mel = extract_log_mel(rec.flatten(), TARGET_SR)
            prototypes[word] = mel.flatten()
        calibrated = True
        print("=== Голос привязан! Слушаю микрофон... ===")

    ring = np.zeros(TARGET_SAMPLES, dtype=np.float32)
    last_speech_ts = time.monotonic()

    def audio_cb(indata, frames, _time_info, _status) -> None:
        nonlocal ring
        mono = indata[:, 0].astype(np.float32)
        if len(mono) >= len(ring):
            ring = mono[-len(ring) :]
        else:
            ring = np.concatenate([ring[len(mono) :], mono])

    with sd.InputStream(samplerate=TARGET_SR, channels=1, dtype="float32", callback=audio_cb):
        last_emit = 0.0
        while True:
            now = time.monotonic()
            if now - last_emit < 0.1:
                time.sleep(0.02)
                continue
            last_emit = now

            recent = ring[-int(0.25 * TARGET_SR) :]
            vol = compute_rms(recent)
            is_speech = vol >= vad_threshold
            if is_speech:
                last_speech_ts = now
            silence_sec = 0.0 if is_speech else (now - last_speech_ts)

            spell = "background"
            conf = 1.0 - vol
            if is_speech:
                mel = extract_log_mel(ring, TARGET_SR)
                logits = session.run(["logits"], {"mel": mel})[0][0].tolist()
                probs = softmax(logits)
                best_idx = max(range(len(probs)), key=lambda i: probs[i])
                spell = LABELS[best_idx]
                conf = probs[best_idx]

                # Few-shot cosine blend if calibrated
                if prototypes and spell != "background":
                    vec = mel.flatten()
                    norm_v = float(np.linalg.norm(vec)) or 1.0
                    sims = {
                        w: float(np.dot(vec, p) / (norm_v * (float(np.linalg.norm(p)) or 1.0)))
                        for w, p in prototypes.items()
                    }
                    best_proto = max(sims, key=sims.get)
                    if sims[best_proto] > 0.45 and conf < 0.72:
                        spell = best_proto
                        conf = max(conf, 0.78)

            pkt = build_udp_packet(
                spell=spell,
                confidence=conf,
                volume=vol,
                is_speech=is_speech,
                silence_sec=silence_sec,
                calibrated=calibrated,
            )
            sock.sendto(pkt, (host, port))


def main() -> int:
    parser = argparse.ArgumentParser(description="Echoes of Arcana Offline Voice Engine")
    parser.add_argument("--simulate", action="store_true", help="Send scripted UDP spells without microphone")
    parser.add_argument("--skip-calibration", action="store_true", help="Skip 10s voice binding ritual")
    parser.add_argument("--host", default=UDP_HOST)
    parser.add_argument("--port", type=int, default=UDP_PORT)
    args = parser.parse_args()

    if args.simulate:
        run_simulation(args.host, args.port)
        return 0

    model_path = Path(__file__).resolve().parent / "spell_model.onnx"
    run_live_microphone(
        model_path=model_path,
        host=args.host,
        port=args.port,
        skip_calibration=args.skip_calibration,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
