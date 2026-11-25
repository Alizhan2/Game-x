"""Real-time Offline Voice Engine (Silero/Adaptive Noise Gate + ONNX + Few-Shot Calibration + UDP)."""

from __future__ import annotations

import argparse
import json
import math
import os
import socket
import sys
import time
from collections import deque
from pathlib import Path
from typing import Any

from features import LABELS, TARGET_SAMPLES, TARGET_SR, compute_rms, extract_log_mel, resample_to_16k
from voice_vad import MODEL_PATH as SILERO_PATH, VAD_SAMPLES, SileroVAD

UDP_HOST = "127.0.0.1"
UDP_PORT = 5055
if getattr(sys, "frozen", False):
    app_data = os.environ.get("LOCALAPPDATA")
    PROFILE_DIR = Path(app_data) / "EchoesOfArcana" if app_data else Path(sys.executable).parent
else:
    PROFILE_DIR = Path(__file__).resolve().parent
DEFAULT_PROFILE_PATH = PROFILE_DIR / "calibration_profile.json"


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
            gated_floor = max(0.01, self.noise_floor * 1.15)
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


class UtteranceBuffer:
    """Keep a short lead-in and produce at most one clip per speech segment."""

    def __init__(self) -> None:
        self.lead_in = deque(maxlen=3)
        self.frames: list = []
        self.voiced_levels: list[float] = []
        self.quiet_frames = 0
        self.emitted = False

    def add(self, frame, is_speech: bool, volume: float) -> tuple[list, float] | None:
        if is_speech:
            if not self.voiced_levels:
                self.frames.extend(self.lead_in)
            self.quiet_frames = 0
            if not self.emitted:
                self.voiced_levels.append(volume)
        else:
            self.quiet_frames += 1

        self.lead_in.append(frame)
        if not self.voiced_levels:
            return None
        finished = self.quiet_frames >= 5
        if self.emitted:
            if finished:
                self._clear()
            return None

        self.frames.append(frame)
        if not finished and len(self.frames) * VAD_SAMPLES < TARGET_SAMPLES:
            return None

        self.emitted = True
        result = None
        if len(self.voiced_levels) >= 3:
            result = self.frames, sum(self.voiced_levels) / len(self.voiced_levels)
        if finished:
            self._clear()
        return result

    def _clear(self) -> None:
        self.frames = []
        self.voiced_levels = []
        self.emitted = False


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

    if prototypes and mel_vec and not (spell == "background" and conf >= 0.5):
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


def _try_load_silero_vad(mode: str = "auto") -> tuple[SileroVAD | None, str]:
    if mode == "energy":
        return None, "energy"
    try:
        return SileroVAD(SILERO_PATH), "silero"
    except Exception as exc:
        print(f"[VoiceEngine] Silero недоступен ({exc}). Активен энергетический порог.")
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
    temp_path = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        temp_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        temp_path.replace(path)
    finally:
        temp_path.unlink(missing_ok=True)


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
        noise_floor = float(nf) if nf is not None else None
        if noise_floor is not None and not 0.0 <= noise_floor <= 1.0:
            return None, {}
        protos = {
            word: vec for word, vec in protos.items()
            if word in LABELS[1:] and len(vec) == 32 * 32 and all(map(math.isfinite, vec))
        }
        return noise_floor, protos
    except (AttributeError, OSError, ValueError, TypeError):
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


def _input_sample_rate(sd) -> int:
    device = sd.query_devices(kind="input")
    try:
        sd.check_input_settings(samplerate=TARGET_SR, channels=1, dtype="float32")
        return TARGET_SR
    except sd.PortAudioError:
        return round(device["default_samplerate"])


def _calibrate(stream, frames_per_block: int, read_frame, gate, profile_path: Path) -> dict:
    blocks_per_second = TARGET_SR / VAD_SAMPLES

    def record(seconds: float):
        return [read_frame(stream, frames_per_block) for _ in range(round(seconds * blocks_per_second))]

    input("Подготовься к калибровке. Нажми Enter и дождись подсказок (около 10 секунд).")
    print("Помолчи 1.5 сек, измеряю фон…", flush=True)
    discarded = stream.read_available
    if discarded:
        stream.read(discarded)
    gate.calibrate_noise([compute_rms(frame) for frame in record(1.5)])

    prototypes = {}
    for word in LABELS[1:]:
        print(f"Приготовься: {word.upper()}", flush=True)
        record(1.5)
        print(f"Сейчас: {word.upper()}!", flush=True)
        frames = record(1.2)
        if max(map(compute_rms, frames)) < max(0.01, gate.noise_floor * 1.2):
            raise ValueError(f"Слово {word.upper()} не было слышно. Повтори калибровку ближе к микрофону.")
        samples = [sample for frame in frames for sample in frame]
        prototypes[word] = extract_log_mel(samples).ravel().tolist()

    save_calibration_profile(profile_path, gate.noise_floor, prototypes)
    print(f"[VoiceEngine] Профиль сохранён: {profile_path}")
    return prototypes


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

        sample_rate = _input_sample_rate(sd)
        frames_per_block = max(1, round(sample_rate * VAD_SAMPLES / TARGET_SR))
        if not calibrate_only and not model_path.is_file():
            raise FileNotFoundError(f"Модель не найдена: {model_path}")
    except Exception as exc:
        print(f"[VoiceEngine] Голос недоступен ({exc}). В Godot работают клавиши [1/2/3].")
        if allow_no_mic:
            while True:
                time.sleep(1.0)
        return 1 if calibrate_only else 0

    def read_frame(stream, frame_count):
        data, overflowed = stream.read(frame_count)
        if overflowed:
            raise BufferError("Пропуск аудиоблока")
        mono = data[:, 0]
        if sample_rate != TARGET_SR:
            mono = np.asarray(resample_to_16k(mono, sample_rate), dtype=np.float32)
        return mono

    gate = AdaptiveNoiseGate(min_threshold=vad_threshold)
    loaded_nf, prototypes = load_calibration_profile(profile_path)
    if loaded_nf is not None:
        gate.noise_floor = loaded_nf
        gate.threshold = max(gate.min_threshold, loaded_nf * gate.margin)
    calibrated = bool(prototypes)

    try:
        with sd.InputStream(
            samplerate=sample_rate, channels=1, dtype="float32", blocksize=frames_per_block, latency="high"
        ) as stream, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            if not skip_calibration or calibrate_only:
                prototypes = _calibrate(stream, frames_per_block, read_frame, gate, profile_path)
                calibrated = True
                if calibrate_only:
                    return 0

            session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
            silero_model, active_vad_mode = _try_load_silero_vad(vad_mode)
            print(f"[VoiceEngine] VAD={active_vad_mode}, порог={gate.threshold:.4f}, UDP={host}:{port}")
            utterance = UtteranceBuffer()
            next_heartbeat = 0.0
            discarded = stream.read_available
            if discarded:
                stream.read(discarded)

            while True:
                try:
                    frame = read_frame(stream, frames_per_block)
                except BufferError:
                    utterance = UtteranceBuffer()
                    gate.last_speech_ts = time.monotonic()
                    if silero_model is not None:
                        silero_model.reset()
                    continue

                now = time.monotonic()
                volume = compute_rms(frame)
                vad_probability = None
                if silero_model is not None:
                    try:
                        vad_probability = silero_model.predict(frame)
                    except Exception as exc:
                        print(f"[VoiceEngine] Silero остановлен ({exc}). Активен энергетический порог.")
                        silero_model, active_vad_mode = None, "energy"

                is_speech, silence_sec = gate.update(volume, now, vad_probability)
                clip = utterance.add(frame, is_speech, volume)
                spell, confidence = "background", max(0.0, 1.0 - volume)
                if clip is not None:
                    frames, volume = clip
                    mel = extract_log_mel(np.concatenate(frames), TARGET_SR)
                    logits = session.run(["logits"], {"mel": mel})[0][0].tolist()
                    spell, confidence = select_prediction(softmax(logits), LABELS, mel.ravel().tolist(), prototypes)

                if clip is None and now < next_heartbeat:
                    continue
                next_heartbeat = now + 0.1
                cast = spell != "background"
                sock.sendto(
                    build_udp_packet(
                        spell=spell,
                        confidence=confidence,
                        volume=volume,
                        is_speech=is_speech or cast,
                        silence_sec=0.0 if cast else silence_sec,
                        calibrated=calibrated,
                        noise_floor=gate.noise_floor,
                        vad_mode=active_vad_mode,
                    ),
                    (host, port),
                )
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        print(f"[VoiceEngine] Аудиопоток остановлен ({exc}). В Godot работают клавиши [1/2/3].")
        return 1 if calibrate_only else 0


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
