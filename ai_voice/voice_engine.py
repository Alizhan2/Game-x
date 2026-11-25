"""Real-time Offline Voice Engine (Silero/Adaptive Noise Gate + ONNX + Few-Shot Calibration + UDP)."""

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
DEFAULT_PROFILE_PATH = Path(__file__).resolve().parent / "calibration_profile.json"


class AdaptiveNoiseGate:
    """Tracks room noise floor and speech/silence durations without external dependencies."""

    def __init__(
        self,
        *,
        noise_floor: float = 0.03,
        margin: float = 2.2,
        min_threshold: float = 0.06,
        whisper_threshold: float = 0.28,
    ) -> None:
        self.noise_floor = max(0.0, float(noise_floor))
        self.margin = max(1.0, float(margin))
        self.min_threshold = max(0.005, float(min_threshold))
        self.whisper_threshold = float(whisper_threshold)
        self.threshold = max(self.min_threshold, self.noise_floor * self.margin)
        self.last_speech_ts: float | None = None

    def calibrate_noise(self, rms_samples: list[float]) -> float:
        """Estimate ambient room noise floor from 1-2s of silence and update speech threshold."""
        clean = sorted(max(0.0, float(x)) for x in rms_samples if float(x) >= 0.0)
        if clean:
            trim_end = max(1, int(len(clean) * 0.85))
            trimmed = clean[:trim_end]
            self.noise_floor = sum(trimmed) / float(len(trimmed))
        self.threshold = max(self.min_threshold, self.noise_floor * self.margin)
        return self.threshold

    def update(
        self,
        volume: float,
        now: float,
        vad_speech_prob: float | None = None,
    ) -> tuple[bool, float]:
        """Return (is_speech, silence_sec) using adaptive RMS gate + optional Silero VAD prob."""
        vol = max(0.0, float(volume))
        if self.last_speech_ts is None:
            self.last_speech_ts = now

        if vad_speech_prob is not None:
            gated_floor = max(self.min_threshold * 0.75, self.noise_floor * 1.2)
            is_speech = (vad_speech_prob >= 0.5 and vol >= gated_floor) or (
                vol >= self.threshold * 1.35
            )
        else:
            is_speech = vol >= self.threshold

        if is_speech:
            self.last_speech_ts = now
            return True, 0.0

        silence_sec = max(0.0, now - self.last_speech_ts)
        return False, silence_sec


def select_prediction(
    probs: list[float],
    labels: list[str],
    mel_vec: list[float] | None = None,
    prototypes: dict[str, list[float]] | None = None,
) -> tuple[str, float]:
    """Select best spell from ONNX softmax probabilities with stdlib cosine few-shot boost."""
    if not probs or not labels or len(probs) != len(labels):
        return "background", 0.0

    best_idx = max(range(len(probs)), key=lambda i: probs[i])
    spell = str(labels[best_idx])
    conf = float(probs[best_idx])

    if prototypes and mel_vec:
        norm_v = math.sqrt(sum(x * x for x in mel_vec)) or 1.0
        best_proto = ""
        best_sim = -1.0
        for word, proto_vec in prototypes.items():
            if not proto_vec or len(proto_vec) != len(mel_vec):
                continue
            norm_p = math.sqrt(sum(y * y for y in proto_vec)) or 1.0
            dot = sum(x * y for x, y in zip(mel_vec, proto_vec))
            sim = dot / (norm_v * norm_p)
            if sim > best_sim:
                best_sim = sim
                best_proto = str(word)

        if best_proto and best_sim > 0.45 and conf < 0.72:
            return best_proto, max(conf, 0.78)

    return spell, conf


def build_udp_packet(
    *,
    spell: str,
    confidence: float,
    volume: float,
    is_speech: bool,
    silence_sec: float,
    calibrated: bool = True,
    noise_floor: float | None = None,
    vad_mode: str | None = None,
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
    if noise_floor is not None:
        payload["noise_floor"] = round(max(0.0, float(noise_floor)), 4)
    if vad_mode is not None:
        payload["vad_mode"] = str(vad_mode)
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def softmax(logits: list[float]) -> list[float]:
    m = max(logits)
    exps = [math.exp(x - m) for x in logits]
    s = sum(exps) or 1.0
    return [e / s for e in exps]


def _try_load_silero_vad(mode: str = "auto") -> tuple[Any | None, str]:
    if mode == "energy":
        return None, "energy"
    try:
        import torch  # noqa: F401
        from silero_vad import load_silero_vad

        vad_model = load_silero_vad()
        return vad_model, "silero"
    except Exception:
        if mode == "silero":
            print("[VoiceEngine] Silero VAD не найден; откат на AdaptiveNoiseGate (energy).")
        return None, "energy"


def save_calibration_profile(
    path: Path,
    noise_floor: float,
    prototypes: dict[str, list[float]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "noise_floor": round(float(noise_floor), 5),
        "prototypes": {k: [round(float(v), 5) for v in vec] for k, vec in prototypes.items()},
    }
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def load_calibration_profile(path: Path) -> tuple[float | None, dict[str, list[float]]]:
    if not path.is_file():
        return None, {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        nf = data.get("noise_floor")
        raw_protos = data.get("prototypes", {})
        protos = {
            str(k): [float(x) for x in v]
            for k, v in raw_protos.items()
            if isinstance(v, list)
        }
        return (float(nf) if nf is not None else None), protos
    except Exception:
        return None, {}


def _stream_script(
    script: list[tuple[float, str, float, float, bool, float]],
    host: str,
    port: int,
    label: str,
) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"[{label}] Streaming scripted spells to udp://{host}:{port}")
    for delay, spell, conf, vol, speech, sil in script:
        time.sleep(delay)
        pkt = build_udp_packet(
            spell=spell,
            confidence=conf,
            volume=vol,
            is_speech=speech,
            silence_sec=sil,
            noise_floor=0.025,
            vad_mode="simulate",
        )
        sock.sendto(pkt, (host, port))
        print(" ->", pkt.decode("utf-8"))

    # Simulate 5.2 seconds of silence for Ending B test
    for step in range(1, 53):
        time.sleep(0.1)
        pkt = build_udp_packet(
            spell="background",
            confidence=0.99,
            volume=0.01,
            is_speech=False,
            silence_sec=step * 0.1,
            noise_floor=0.025,
            vad_mode="simulate",
        )
        sock.sendto(pkt, (host, port))
    print(f"[{label}] Completed 5.2s silence sequence.")


def run_simulation(host: str = UDP_HOST, port: int = UDP_PORT) -> None:
    """Stream realistic Chapter I spell events over UDP without needing a microphone."""
    script = [
        (1.0, "virdan", 0.96, 0.88, True, 0.0),
        (2.0, "noktar", 0.92, 0.19, True, 0.0),
        (2.0, "targum", 0.98, 0.95, True, 0.0),
        (1.5, "virdan", 0.95, 0.80, True, 0.0),
        (1.5, "noktar", 0.93, 0.72, True, 0.0),
        (1.5, "targum", 0.97, 0.90, True, 0.0),
    ]
    _stream_script(script, host, port, "SIMULATE")


def run_adaptive_simulation(host: str = UDP_HOST, port: int = UDP_PORT) -> None:
    """Stream an AdaptiveAI test: 3x virdan spam -> counter-shield -> noktar -> targum -> combo -> silence."""
    script = [
        (0.8, "virdan", 0.94, 0.84, True, 0.0),
        (1.1, "virdan", 0.93, 0.82, True, 0.0),
        (1.1, "virdan", 0.95, 0.86, True, 0.0),
        (1.6, "noktar", 0.91, 0.22, True, 0.0),  # switch school to clear shield (whisper)
        (1.3, "targum", 0.96, 0.92, True, 0.0),
        (1.1, "virdan", 0.94, 0.85, True, 0.0),
        (1.1, "noktar", 0.92, 0.75, True, 0.0),
        (1.1, "targum", 0.97, 0.93, True, 0.0),
    ]
    _stream_script(script, host, port, "SIMULATE-ADAPTIVE")


def run_live_microphone(
    *,
    model_path: Path,
    host: str = UDP_HOST,
    port: int = UDP_PORT,
    vad_mode: str = "auto",
    vad_threshold: float = 0.06,
    skip_calibration: bool = False,
    calibrate_only: bool = False,
    profile_path: Path = DEFAULT_PROFILE_PATH,
    allow_no_mic: bool = False,
) -> int:
    try:
        import numpy as np
        import onnxruntime as ort
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Install dependencies first: pip install -r ai_voice/requirements.txt"
        ) from exc

    if not model_path.is_file() and not calibrate_only:
        raise SystemExit(
            f"Model not found: {model_path}. Train first in Colab/train_onnx.py or use --simulate."
        )

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    gate = AdaptiveNoiseGate(min_threshold=vad_threshold)

    try:
        default_in = sd.query_devices(kind="input")
        if not default_in or int(default_in.get("max_input_channels", 0)) <= 0:
            raise RuntimeError("No input channels available")
    except Exception as exc:
        print(f"[VoiceEngine] Микрофон не обнаружен ({exc}). Работает клавиатурный фолбэк [1/2/3] в Godot.")
        if allow_no_mic:
            while True:
                time.sleep(1.0)
        return 0

    loaded_nf, prototypes = load_calibration_profile(profile_path)
    if loaded_nf is not None:
        gate.noise_floor = loaded_nf
        gate.threshold = max(gate.min_threshold, loaded_nf * gate.margin)
    calibrated = skip_calibration or bool(prototypes)

    if not skip_calibration or calibrate_only:
        print("=== Ритуал привязки голоса (10 сек) ===")
        print("1/4: Замер шума зала (помолчите 1.5 сек)...")
        silence_rec = sd.rec(int(1.5 * TARGET_SR), samplerate=TARGET_SR, channels=1, dtype="float32")
        sd.wait()
        flat_sil = silence_rec.flatten().tolist()
        chunk_sz = max(1, TARGET_SR // 10)
        rms_chunks = [compute_rms(flat_sil[i : i + chunk_sz]) for i in range(0, len(flat_sil), chunk_sz)]
        thresh = gate.calibrate_noise(rms_chunks)
        print(f"   Уровень шума={gate.noise_floor:.4f}, порог речи={thresh:.4f}")

        prototypes = {}
        for idx, word in enumerate(("virdan", "noktar", "targum"), start=2):
            input(f"{idx}/4: Нажми Enter и произнеси '{word.upper()}' один раз...")
            rec = sd.rec(TARGET_SAMPLES, samplerate=TARGET_SR, channels=1, dtype="float32")
            sd.wait()
            mel = extract_log_mel(rec.flatten(), TARGET_SR)
            prototypes[word] = [float(x) for x in mel.flatten().tolist()]

        save_calibration_profile(profile_path, gate.noise_floor, prototypes)
        calibrated = True
        print(f"=== Профиль сохранён в {profile_path.name}! ===")
        if calibrate_only:
            return 0

    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    silero_model, active_vad_mode = _try_load_silero_vad(vad_mode)
    print(f"[VoiceEngine] Активен режим VAD={active_vad_mode}, порог={gate.threshold:.4f}, UDP={host}:{port}")

    ring = np.zeros(TARGET_SAMPLES, dtype=np.float32)

    def audio_cb(indata, _frames, _time_info, _status) -> None:
        nonlocal ring
        mono = indata[:, 0].astype(np.float32)
        if len(mono) >= len(ring):
            ring = mono[-len(ring) :]
        else:
            ring = np.concatenate([ring[len(mono) :], mono])

    try:
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

                vad_prob: float | None = None
                if silero_model is not None:
                    try:
                        import torch

                        chunk_512 = torch.from_numpy(ring[-512:].copy())
                        vad_prob = float(silero_model(chunk_512, TARGET_SR).item())
                    except Exception:
                        vad_prob = None

                is_speech, silence_sec = gate.update(vol, now, vad_prob)

                spell = "background"
                conf = max(0.0, 1.0 - vol)
                if is_speech:
                    mel = extract_log_mel(ring, TARGET_SR)
                    logits = session.run(["logits"], {"mel": mel})[0][0].tolist()
                    probs = softmax(logits)
                    mel_vec = [float(x) for x in mel.flatten().tolist()]
                    spell, conf = select_prediction(probs, LABELS, mel_vec, prototypes)

                pkt = build_udp_packet(
                    spell=spell,
                    confidence=conf,
                    volume=vol,
                    is_speech=is_speech,
                    silence_sec=silence_sec,
                    calibrated=calibrated,
                    noise_floor=gate.noise_floor,
                    vad_mode=active_vad_mode,
                )
                sock.sendto(pkt, (host, port))
    except Exception as exc:
        print(f"[VoiceEngine] Аудиопоток остановлен ({exc}). В Godot используйте клавиши [1/2/3].")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Echoes of Arcana Offline Voice Engine")
    parser.add_argument("--simulate", action="store_true", help="Send scripted UDP spells without microphone")
    parser.add_argument("--simulate-adaptive", action="store_true", help="Send AdaptiveAI counter-shield test script")
    parser.add_argument("--skip-calibration", action="store_true", help="Skip 10s voice binding ritual")
    parser.add_argument("--calibrate-only", action="store_true", help="Run 10s calibration and save profile")
    parser.add_argument("--allow-no-mic", action="store_true", help="Keep process alive silently if no mic exists")
    parser.add_argument("--vad", choices=("auto", "silero", "energy"), default="auto")
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE_PATH)
    parser.add_argument("--host", default=UDP_HOST)
    parser.add_argument("--port", type=int, default=UDP_PORT)
    args = parser.parse_args()

    if args.simulate:
        run_simulation(args.host, args.port)
        return 0
    if args.simulate_adaptive:
        run_adaptive_simulation(args.host, args.port)
        return 0

    model_path = Path(__file__).resolve().parent / "spell_model.onnx"
    return run_live_microphone(
        model_path=model_path,
        host=args.host,
        port=args.port,
        vad_mode=args.vad,
        skip_calibration=args.skip_calibration,
        calibrate_only=args.calibrate_only,
        profile_path=args.profile,
        allow_no_mic=args.allow_no_mic,
    )


if __name__ == "__main__":
    raise SystemExit(main())
