# Qwen decoder quantization control

Research only. This control tests whether the saved four-bit decoder representation
can cause the three empty Taiwan transcripts independently of Swift or MLX runtime.
It runs the official PyTorch model in FP32 on CPU, replacing only quantized decoder
matrices and the tied output head. It does not establish Apple runtime correctness,
memory use, or latency.

## Pinned inputs

Download complete snapshots into `ROOT/models/original`, `ROOT/models/4bit` and
`ROOT/models/8bit`, including tokenizer and processor JSON files. Verify each
`model.safetensors` SHA256 before running; the helper validates tensor contents and
architecture, but does not itself enforce repository revisions or file hashes.

| Directory | Hugging Face repository | Revision | Weight bytes |
| --- | --- | --- | --- |
| original | Qwen/Qwen3-ASR-0.6B | `5eb144179a02acc5e5ba31e748d22b0cf3e303b0` | 1,876,091,704 |
| 4bit | mlx-community/Qwen3-ASR-0.6B-4bit | `313d850181767edf09f00a9c289becca70e58cd0` | 708,236,945 |
| 8bit | mlx-community/Qwen3-ASR-0.6B-8bit | `89e96d92ba34aca20b3e29fb10cc284097d1219f` | 1,006,229,426 |

Weight SHA256, in the same order:

```text
79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea
70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf
b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8
```

The recorded environment uses Python3.12, `torch==2.14.0+cpu`, `qwen-asr==0.0.6`,
`transformers==4.57.6`, `numpy==2.5.3`, `safetensors==0.8.0`, and
`opencc-python-reimplemented==0.1.7`. The complete installed freeze is retained in
the evidence archive. Use the PyTorch CPU wheel index for that Torch build.

Place the same 40 public human WAVs in `ROOT/audio/cv-human/` and the independent
manifest in `ROOT/audio/cv-human-references.json`. Each manifest entry must contain
`clip`, `text`, and `wav_sha256`. The source is
`OpenFormosa/common_voice_25_zh-TW` revision
`9e969df60ad63f812b68a755581c961bc967673d`; selection and reference provenance are
documented in [the public benchmark](../../docs/research/roma-asr-public-benchmark.md).
The helper checks all 40 WAV hashes and requires 16kHz mono PCM16. Do not substitute
synthetic speech or references derived from model output.

```sh
python Tools/ASRBenchmark/qwen_quantization_control.py ROOT --self-test-only
python Tools/ASRBenchmark/qwen_quantization_control.py ROOT --output ROOT/results-new
```

Use a fresh output directory. A nonempty directory is rejected before checkpoint
loading; a failed experiment must not leave older scores looking current. All three
variants run in order in one process, batch size1, automatic language, maximum256
new tokens, two Torch threads, one interop thread, no enhancement. Baseline inference
must reproduce21/291 canonical character errors and zero empty outputs before either
quantized variant runs. A baseline mismatch stops the experiment for investigation.

## Representation and mapping checks

The affine format stores low-to-high codes in UInt32 words. Each group has64 values:
eight packed words at4bits, sixteen at8bits. Reconstruction is
`float32(code) * float32(BF16 scale) + float32(BF16 bias)`. This deliberately excludes
BF16 dequantization-output rounding and native quantized matrix-multiply accumulation.
It isolates the saved mathematical representation, rather than emulating MLX kernels.
See the pinned [MLX format documentation](https://github.com/ml-explore/mlx/blob/ce916dbbcaa88e433b6fd1e60a17f766d49c27fe/python/src/ops.cpp#L4739-L4752)
and [Qwen conversion mapping](https://github.com/Blaizzy/mlx-audio/blob/3acb58fbdc10f04c4bfdbec51ffbc8de3e038cca/mlx_audio/stt/models/qwen3_asr/qwen3_asr.py#L808-L834).
These source revisions explain the format; they are not asserted to be the historical
converter versions used to publish the checkpoints.

Known packed-word fixtures, an independent scalar packer and two-row/two-group
arithmetic oracle validate bit order, group boundaries and linear orientation.
Both actual checkpoints pass exact key-inventory and config checks. All301 encoder
tensors equal the original bit-for-bit after explicitly reversing only the three
Conv2D kernels from OHWI to OIHW; every unquantized decoder tensor also matches.
There are197 quantized matrices. The original output head equals the embedding;
the MLX checkpoint omits that tied head. Before each variant, the helper restores
every original parameter, replaces197 matrices plus the tied head, and checks all414
remaining state entries against original FP32 values. No unknown keys are skipped.

## Recorded result, 2026-09-07

| Decoder weights; original encoder throughout | Canonical CER | Empty /40 | Exact /40 | S / I / D |
| --- | --- | --- | --- | --- |
| Original, FP32 inference | 21/291 (7.216%) | 0 | 28 | 20 /0 /1 |
| Four-bit representation, FP32 inference | 44/291 (15.120%) | 3 | 24 | 24 /0 /20 |
| Eight-bit representation, FP32 inference | 21/291 (7.216%) | 0 | 28 | 20 /0 /1 |

The four-bit control reproduces exactly the three native empty cases: `cv-009`,
`cv-025`, `cv-034`. Original and eight-bit output nonempty, correct canonical text
on each. Thus the four-bit representation is sufficient to reproduce these failures
in the official runtime; they cannot be attributed exclusively to Swift frontend
or decoder implementation. This does not prove the absence of separate runtime bugs.

Eight-bit is not transcript-identical to original: two raw answers change, only one
after canonical normalization. `cv-011` changes its two-error answer; `cv-023` changes
script only. All40 per-clip canonical error counts remain equal. Four-bit changes13
raw answers and eight canonical answers; six clips worsen, none improve, and34 retain
the same error count. Raw CER is28/291,58/291 and27/291 respectively. Scoring uses
the reviewed `score_references.py`, retaining raw CER alongside OpenCC `s2twp`
canonical CER; this is a small fixed corpus, not general accuracy certification.

## Evidence and lifecycle

Ignored local evidence: `.local-build/asr-research/qwen-quantization-control/`.
`evidence/` includes120 JSONL results, all scores, per-clip comparison, exhaustive
mapping/replacement reports, model hashes/configs, installed dependencies, run log,
exit0 receipt, and a successful stale-output rejection. The executed helper matches
the source SHA256 `c3c9fdadd91cf411d03e5c49499bf094ca9198f0157bcb9846aa886c6640d49e`.
The final archive `evidence-final.tar.gz` has SHA256
`3d1902ec047b327afe19a316a45268cf76cc555105effb9bd401a349389223bd`.

The separately exported official processor features cover40 CV and20 TaiMECS human
clips. `official-features/manifest.json` preserves exact prompt, versions, WAV/feature
hashes, raw shapes, full attention masks and true encoder lengths. Files are
little-endian Float32 row-major `[128,T]`, without extra cropping or padding.
The60 file hashes, sizes and mask lengths were independently checked after transfer.
`official-features.tar.gz` SHA256:
`e755f0dc6f37d63c54f77d8c43ae7d63b64b0eb922cc0876f19468e05ce2444d`.

Only public audio was used. The owned8CPU/16GB Linux instance `vv0j01qtmvo0a` was
destroyed after evidence collection; destruction exit0 and subsequent unavailable
instance receipt are saved alongside the artifacts. Any recorded elapsed time is
CPU research timing, not Apple performance or microphone release latency.
