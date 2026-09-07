"""Unscored streaming diagnostics. Never derives gold transcripts from ASR."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import time
import wave

import numpy as np
import psutil
import sherpa_onnx


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("model_root", type=Path)
    parser.add_argument("audio_root", type=Path)
    parser.add_argument("--tier", type=int, choices=[160, 480], required=True)
    parser.add_argument("--paced", action="store_true")
    parser.add_argument("--tail-ms", type=int, default=0)
    args = parser.parse_args()
    if args.tail_ms < 0:
        parser.error("--tail-ms must be nonnegative")
    files = sorted(args.audio_root.glob("*.wav"))
    if not files:
        parser.error("No WAV inputs")
    process = psutil.Process()
    start_rss = process.memory_info().rss
    base = args.model_root / "deployment/models" / f"chunk-{args.tier}ms-model"
    started = time.perf_counter()
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(base / "tokens.txt"), encoder=str(base / f"encoder-{args.tier}ms.onnx"),
        decoder=str(base / f"decoder-{args.tier}ms.onnx"), joiner=str(base / f"joiner-{args.tier}ms.onnx"),
        num_threads=1, sample_rate=16000, feature_dim=80, decoding_method="greedy_search",
        provider="cpu", model_type="zipformer2", enable_endpoint_detection=False)
    emit({"event": "loaded", "model": "xasr", "tier_ms": args.tier,
          "load_seconds": time.perf_counter() - started, "rss_before_bytes": start_rss,
          "rss_loaded_bytes": process.memory_info().rss, "pid": process.pid,
          "sherpa_version": sherpa_onnx.__version__, "tail_ms": args.tail_ms, "paced": args.paced})
    for path in files:
        with wave.open(str(path)) as wav:
            if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) != (16000, 1, 2):
                raise ValueError("Expected 16 kHz mono PCM16 WAV")
            samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768
        stream = recognizer.create_stream()
        events = []
        previous = ""
        retracted = 0
        started = time.perf_counter()
        cpu_start = time.process_time()
        for offset in range(0, len(samples), 1280):
            chunk = samples[offset:offset + 1280]
            if args.paced:
                time.sleep(max(0, started + (offset + len(chunk)) / 16000 - time.perf_counter()))
            stream.accept_waveform(16000, chunk)
            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
                text = recognizer.get_result(stream)
                if text != previous:
                    common = 0
                    for left, right in zip(previous, text):
                        if left != right:
                            break
                        common += 1
                    retracted += len(previous) - common
                    events.append({"at_ms": 1000 * (time.perf_counter() - started), "text": text})
                    previous = text
        # Measure final draining after real audio, with explicitly reported synthetic tail.
        released = time.perf_counter()
        if args.tail_ms:
            stream.accept_waveform(16000, np.zeros(args.tail_ms * 16, dtype=np.float32))
        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        text = recognizer.get_result(stream)
        ended = time.perf_counter()
        emit({"event": "clip", "clip": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "duration_seconds": len(samples) / 16000, "text": text,
              "elapsed_seconds": ended - started, "cpu_seconds": time.process_time() - cpu_start,
              "final_drain_ms": 1000 * (ended - released),
              "backlog_at_release_ms": max(0, 1000 * (released - started - len(samples) / 16000)) if args.paced else None,
              "release_to_final_ms": 1000 * (ended - started - len(samples) / 16000) if args.paced else None,
              "first_partial_from_clip_start_ms": next((e["at_ms"] for e in events if e["text"]), None),
              "partial_events": events, "retracted_characters": retracted,
              "rss_bytes": process.memory_info().rss,
              "lifetime_peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
              "accuracy_scored": False})
    time.sleep(5)
    emit({"event": "idle", "rss_bytes": process.memory_info().rss})


if __name__ == "__main__":
    main()
