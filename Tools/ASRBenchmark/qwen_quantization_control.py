"""Isolate MLX affine decoder weight quantization in official Qwen FP32 inference.

Research only: never executes MLX/Apple kernels or claims native runtime parity.
Packing: https://github.com/ml-explore/mlx/blob/ce916dbbcaa88e433b6fd1e60a17f766d49c27fe/python/src/ops.cpp
Mapping: https://github.com/Blaizzy/mlx-audio/blob/3acb58fbdc10f04c4bfdbec51ffbc8de3e038cca/mlx_audio/stt/models/qwen3_asr/qwen3_asr.py#L808-L834
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import wave

import numpy as np
from safetensors import safe_open
import torch

from score_references import score


def require(condition, message):
    if not condition:
        raise ValueError(message)


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def dequantize(packed, scales, biases, bits, group_size=64):
    """Return FP32 represented weights, avoiding BF16 dequant-output rounding."""
    require(bits in (4, 8) and group_size == 64, "Expected affine 4/8-bit group64")
    require(packed.dtype == torch.uint32 and packed.ndim == 2, "Expected UInt32 matrix")
    width = packed.shape[1] * (32 // bits)
    require(width % group_size == 0, "Incomplete quantization group")
    require(scales.shape == biases.shape == (packed.shape[0], width // group_size),
            "Scale/bias shapes do not cover packed matrix")
    require(torch.isfinite(scales).all() and torch.isfinite(biases).all(), "Nonfinite metadata")
    output = torch.empty((packed.shape[0], width), dtype=torch.float32)
    shifts = torch.arange(0, 32, bits, dtype=torch.int64)
    # Chunk the vocabulary embedding to bound temporary memory.
    for start in range(0, packed.shape[0], 256):
        stop = min(start + 256, packed.shape[0])
        words = packed[start:stop].to(torch.int64)
        codes = ((words[..., None] >> shifts) & ((1 << bits) - 1)).reshape(stop - start, -1)
        values = codes.reshape(stop - start, -1, group_size).float()
        values = values * scales[start:stop].float()[..., None] + biases[start:stop].float()[..., None]
        output[start:stop] = values.reshape(stop - start, width)
    return output


def self_test():
    fixtures = [(4, 0x87654321, [1, 2, 3, 4, 5, 6, 7, 8]),
                (8, 0x80FF0201, [1, 2, 255, 128])]
    for bits, word, expected in fixtures:
        require([(word >> (bits * i)) & ((1 << bits) - 1) for i in range(32 // bits)] == expected,
                "Independent known-word packing fixture failed")
        codes = [[(i * 7 + row * 3) % (1 << bits) for i in range(128)] for row in range(2)]
        # Independent scalar packer and arithmetic oracle; two groups per row.
        packed = [[sum(row[i + j] << (bits * j) for j in range(32 // bits))
                   for i in range(0, 128, 32 // bits)] for row in codes]
        scales = [[0.5, -2.0], [2.0, -0.5]]
        biases = [[-1.0, 3.0], [8.0, -4.0]]
        expected = [[code * scales[r][i // 64] + biases[r][i // 64]
                     for i, code in enumerate(row)] for r, row in enumerate(codes)]
        actual = dequantize(torch.tensor(packed, dtype=torch.uint32),
                            torch.tensor(scales, dtype=torch.bfloat16),
                            torch.tensor(biases, dtype=torch.bfloat16), bits)
        require(torch.equal(actual, torch.tensor(expected)), "Scalar roundtrip mismatch")
        require(not torch.equal(actual, actual.flip(-1)), "Packing-order fixture is insensitive")
        x = torch.arange(128, dtype=torch.float32)
        require(torch.equal(x @ actual.T,
                            torch.tensor([sum(i * v for i, v in enumerate(row)) for row in expected])),
                "Linear output/input orientation mismatch")
    emit({"event": "self_test", "passed": True, "bits": [4, 8], "group_size": 64,
          "checks": "known packed words; scalar two-row/two-group roundtrips; bit-order sensitivity; linear orientation"})


def canonical_key(key):
    require(key.startswith(("audio_tower.", "model.")), f"Unexpected MLX namespace: {key}")
    return "thinker." + key


def original_layout(key, tensor):
    if key in {f"audio_tower.conv2d{i}.weight" for i in (1, 2, 3)}:
        require(tensor.ndim == 4, f"Expected Conv2D kernel: {key}")
        return tensor.permute(0, 3, 1, 2).contiguous()
    return tensor


def verify_checkpoint(original, converted, original_config, converted_config, bits):
    config = dict(converted_config)
    expected_quantization = {"group_size": 64, "bits": bits, "mode": "affine"}
    for field in ("quantization", "quantization_config"):
        require(config.pop(field, None) == expected_quantization, f"Unexpected {field}")
    require(config == original_config, "Architecture/config differs beyond quantization metadata")
    require(original_config["thinker_config"]["text_config"]["tie_word_embeddings"], "Untied output head")
    require(torch.equal(original.get_tensor("thinker.lm_head.weight"),
                        original.get_tensor("thinker.model.embed_tokens.weight")),
            "Original output head differs from embedding; cannot infer removed MLX head")
    original_keys = set(original.keys())
    keys = set(converted.keys())
    quantized = sorted(key[:-7] for key in keys if key.endswith(".scales"))
    quantized_weights = {name + ".weight" for name in quantized}
    require(len(quantized) == 197, f"Unexpected quantized matrix count: {len(quantized)}")
    expected_keys = {key.removeprefix("thinker.") for key in original_keys - {"thinker.lm_head.weight"}}
    expected_keys |= {name + suffix for name in quantized for suffix in (".scales", ".biases")}
    require(keys == expected_keys, f"Checkpoint key mismatch missing={sorted(expected_keys-keys)} extra={sorted(keys-expected_keys)}")
    rows = []
    for key in sorted(keys):
        if key.endswith((".scales", ".biases")):
            continue  # Exhaustively accounted for in the exact expected-key set above.
        target = canonical_key(key)
        value = converted.get_tensor(key)
        reference = original.get_tensor(target)
        if key in quantized_weights:
            require(key.startswith("model."), f"Encoder unexpectedly quantized: {key}")
            name = key[:-7]
            scales, biases = (converted.get_tensor(name + suffix) for suffix in (".scales", ".biases"))
            require(value.dtype == torch.uint32 and value.ndim == 2, f"Invalid packed weight: {key}")
            require((value.shape[0], value.shape[1] * (32 // bits)) == tuple(reference.shape), f"Quantized shape mismatch: {key}")
            require(scales.dtype == biases.dtype == torch.bfloat16, f"Unexpected affine metadata precision: {key}")
            require(tuple(scales.shape) == tuple(biases.shape) == (reference.shape[0], reference.shape[1] // 64), f"Group shape mismatch: {key}")
            rows.append({"key": key, "target": target, "quantized": True, "shape": list(reference.shape)})
        else:
            value = original_layout(key, value)
            require(value.shape == reference.shape and value.dtype == reference.dtype, f"Float shape/dtype mismatch: {key}")
            require(torch.equal(value, reference), f"Untouched tensor differs from original: {key}")
            rows.append({"key": key, "target": target, "quantized": False, "shape": list(reference.shape),
                         "exact_original_match": True, "layout_transform": "OHWI→OIHW" if "conv2d" in key and key.endswith(".weight") else "none"})
    require(sum(row["key"].startswith("audio_tower.") for row in rows) == 301, "Incomplete encoder validation")
    return {"bits": bits, "quantized_matrices": len(quantized), "exact_encoder_tensors": 301,
            "tied_head_original_equal": True, "rows": rows}


def replace_decoder(model, original, converted, report, bits):
    state = model.state_dict()
    require(set(state) == set(original.keys()), "Loaded PyTorch state differs from original tensor inventory")
    replaced = []
    with torch.no_grad():
        for key, parameter in state.items():
            require(parameter.dtype == torch.float32, f"Non-FP32 inference parameter: {key}")
            parameter.copy_(original.get_tensor(key).float())
        for row in report["rows"]:
            if not row["quantized"]:
                continue
            key = row["key"]
            name = key[:-7]
            value = dequantize(converted.get_tensor(key), converted.get_tensor(name + ".scales"),
                               converted.get_tensor(name + ".biases"), bits)
            state[row["target"]].copy_(value)
            replaced.append(row["target"])
        # MLX uses the quantized embedding as its output head; preserve that tie.
        state["thinker.lm_head.weight"].copy_(state["thinker.model.embed_tokens.weight"])
        replaced.append("thinker.lm_head.weight")
        for key in set(state) - set(replaced):
            require(torch.equal(state[key], original.get_tensor(key).float()),
                    f"Unexpected change outside quantized decoder: {key}")
    require(len(replaced) == 198, "Incomplete decoder/head replacement")
    return {"replaced_parameter_keys": replaced, "untouched_original_verified": len(state) - len(replaced),
            "dequantized_dtype": "float32", "arithmetic": "float32(code) * float32(BF16 scale) + float32(BF16 bias)",
            "native_arithmetic_excluded": "No BF16 output rounding or native quantized-matmul accumulation emulation"}


def run_corpus(asr, references, audio, output, variant):
    events = []
    with (output / f"{variant}-events.jsonl").open("w") as stream:
        for reference in references:
            path = audio / reference["clip"]
            require(hashlib.sha256(path.read_bytes()).hexdigest() == reference["wav_sha256"], f"Audio hash mismatch: {path}")
            with wave.open(str(path)) as wav:
                require((wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) == (16000, 1, 2), "Invalid WAV format")
                samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768
            started, cpu = time.perf_counter(), time.process_time()
            with torch.inference_mode():
                result = asr.transcribe(audio=(samples, 16000), language=None)[0]
            event = {"event": "clip", "clip": path.name, "text": result.text, "variant": variant,
                     "language": result.language, "repetition": 0, "elapsed_seconds": time.perf_counter()-started,
                     "cpu_seconds": time.process_time()-cpu, "sha256": reference["wav_sha256"]}
            events.append(event)
            stream.write(json.dumps(event, ensure_ascii=False) + "\n")
            stream.flush()
            emit(event)
    result = score(references, events)
    (output / f"{variant}-score.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    emit({"event": "score", "variant": variant, **result["summary"]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--output", type=Path, help="Fresh evidence directory; existing nonempty directories are rejected")
    parser.add_argument("--self-test-only", action="store_true")
    args = parser.parse_args()
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    self_test()
    if args.self_test_only:
        return
    root = args.root
    output = args.output or root / "results"
    require(not output.exists() or not any(output.iterdir()), "Output directory contains previous evidence; choose a fresh --output")
    output.mkdir(parents=True, exist_ok=True)
    models = root / "models"
    original_config = json.loads((models / "original/config.json").read_text())
    reports = {}
    with safe_open(models / "original/model.safetensors", framework="pt", device="cpu") as original:
        for bits in (4, 8):
            with safe_open(models / f"{bits}bit/model.safetensors", framework="pt", device="cpu") as converted:
                reports[bits] = verify_checkpoint(original, converted, original_config,
                    json.loads((models / f"{bits}bit/config.json").read_text()), bits)
                (output / f"{bits}bit-mapping.json").write_text(json.dumps(reports[bits], indent=2) + "\n")
                emit({"event": "mapping_verified", "bits": bits, "encoder_tensors_exact": 301, "quantized_matrices": 197})
        from qwen_asr import Qwen3ASRModel
        asr = Qwen3ASRModel.from_pretrained(str(models / "original"), dtype=torch.float32, device_map="cpu",
            max_inference_batch_size=1, max_new_tokens=256, local_files_only=True)
        asr.model.eval()
        references = json.loads((root / "audio/cv-human-references.json").read_text())
        require(len(references) == 40, "Expected all 40 CV clips")
        baseline = run_corpus(asr, references, root / "audio/cv-human", output, "original-fp32")
        require(baseline["summary"]["canonical_character_errors"] == 21 and baseline["summary"]["reference_characters"] == 291
                and baseline["summary"]["empty_output"] == 0, "Baseline does not reproduce known 21/291 CER, zero-empty control; stop before quantized inference")
        for bits in (4, 8):
            with safe_open(models / f"{bits}bit/model.safetensors", framework="pt", device="cpu") as converted:
                replacement = replace_decoder(asr.model, original, converted, reports[bits], bits)
                (output / f"{bits}bit-replacement.json").write_text(json.dumps(replacement, indent=2) + "\n")
            run_corpus(asr, references, root / "audio/cv-human", output, f"dequant-{bits}bit-fp32")
    emit({"event": "finished", "proof_boundary": "FP32 CPU decoder-weight quantization control, not Apple runtime"})


if __name__ == "__main__":
    main()
