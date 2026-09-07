"""CPU FP32 whole-file controls; unscored outputs, not optimized deployment benchmarks."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import wave

import numpy as np
import torch


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("model", choices=["breeze", "qwen"])
    parser.add_argument("model_root", type=Path)
    parser.add_argument("audio_root", type=Path)
    args = parser.parse_args()
    files = sorted(args.audio_root.glob("*.wav"))
    if not files:
        parser.error("No WAV inputs")
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    started = time.perf_counter()
    if args.model == "qwen":
        from qwen_asr import Qwen3ASRModel
        model = Qwen3ASRModel.from_pretrained(
            str(args.model_root), dtype=torch.float32, device_map="cpu",
            max_inference_batch_size=1, max_new_tokens=256, local_files_only=True)

        def transcribe(samples):
            result = model.transcribe(audio=(samples, 16000), language=None)[0]
            return result.text
    else:
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        processor = WhisperProcessor.from_pretrained(str(args.model_root), local_files_only=True)
        model = WhisperForConditionalGeneration.from_pretrained(
            str(args.model_root), torch_dtype=torch.float32, local_files_only=True).eval()

        def transcribe(samples):
            inputs = processor(samples, sampling_rate=16000, return_tensors="pt", return_attention_mask=True)
            with torch.inference_mode():
                tokens = model.generate(**inputs, task="transcribe", language=None,
                                        max_new_tokens=256, do_sample=False)
            return processor.batch_decode(tokens, skip_special_tokens=True)[0]

    emit({"event": "loaded", "model": args.model, "load_seconds": time.perf_counter() - started,
          "precision": "float32", "device": "cpu", "threads": 2, "language_hint": None,
          "max_new_tokens": 256})
    for path in files:
        with wave.open(str(path)) as wav:
            if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) != (16000, 1, 2):
                raise ValueError("Expected 16 kHz mono PCM16 WAV")
            samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768
        started = time.perf_counter()
        cpu_start = time.process_time()
        text = transcribe(samples)
        emit({"event": "clip", "clip": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "duration_seconds": len(samples) / 16000, "text": text,
              "elapsed_seconds": time.perf_counter() - started,
              "cpu_seconds": time.process_time() - cpu_start, "accuracy_scored": False})
    time.sleep(5)
    emit({"event": "finished"})


if __name__ == "__main__":
    main()
