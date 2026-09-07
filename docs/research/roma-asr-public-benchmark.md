# Roma public human-reference benchmark — 2026-09-08

This report concerns local bilingual model selection for v1.95.1. NVIDIA zh-TW
is a separate, manually selected cloud backup. No model in this report has passed
all 32 Roma requirements or the complete app release gate.

## Current decision

**Native MLX eight-bit Qwen3-ASR 0.6B is the integration lead.** It returned
nonempty text on all 90 public batch clips, matched the original FP32 Common
Voice aggregate, and completed a 350 ms cumulative streaming control on all 20
human mixed-language recordings. The four-bit variant remains unsuitable because
three early-EOS failures persist after the encoder-length correction.

This is a model/runtime recommendation, not shipping approval. Isolated English
language choice, Traditional output, usable partials, memory, lifecycle, and the
actual app's 250 ms insertion gate remain open. The shared production module has
compiled; its actual helper replay and app lifecycle gates are pending. Breeze
Q8 retains stronger measured bilingual scores but lacks Apple streaming/resource
acceptance. Corrected CoreML Qwen is a measured alternative with 360 MiB active neural
allocation, different attention context and weaker accuracy in this subset.

## Shared corpora

| Corpus | Selection and reference boundary | Size | Limitations |
| --- | --- | ---: | --- |
| [TaiMECS, pinned revision](https://huggingface.co/datasets/JacobLinCool/TaiMECS/tree/83f397e41840ba187cc6833e1320bd2e5fa858f1) | All `source=human` rows; original transcripts; 80 synthetic rows excluded; CC BY 4.0 | 20 clips, 163.536 s, 662 mixed units | One Taiwanese speaker. Embedded English technical words; not a diverse independent test of accents. TEA trained on TaiMECS, so it would not be held out for TEA. |
| [Common Voice 25 zh-TW, pinned mirror](https://huggingface.co/datasets/OpenFormosa/common_voice_25_zh-TW/tree/9e969df60ad63f812b68a755581c961bc967673d) | Official test split, at least two upvotes and no downvotes; deterministic filename selection; one clip per speaker; 20 recordings ≤3 s and 20 between 3–10 s; CC0 | 40 speakers/clips, 130.992 s, 291 normalized characters | Stratified exploratory subset, not the full benchmark. Recording duration does not label speech onset/duration. |
| [Speech Commands V2](https://www.tensorflow.org/datasets/catalog/speech_commands) | Test archive; `yes/no/up/down/left/right/on/off/stop/go`; first three distinct speaker IDs per label by sorted filename | 30 one-second recordings, 30 reference words | Keyword-spotting corpus. Homophones and isolated-word context matter. This is not general English dictation WER or a labeled subsecond-speech set. |

Inputs were PCM16 mono at 16 kHz. TaiMECS and Common Voice conversion used ffmpeg;
Speech Commands WAVs were used directly. Manifests preserve dataset revision,
original filename, source/WAV SHA-256, and independent reference text. The user's
English-only private recordings remain separate and cannot prove bilingual
accuracy. No model output was used as a reference.

## Scoring

[The reviewed scorer](../../Tools/ASRBenchmark/score_references.py) uses the first
result for every reference clip and rejects missing, extra, or duplicate first
results. Empty outputs count as deletions. Six regression tests include a
length-changing normalization case that previously gave the wrong raw-CER
denominator.

Raw CER uses NFKC and lowercase, ignoring punctuation/spacing/control characters.
Normalized CER additionally uses OpenCC `s2twp`, which changes both Chinese script
and some Taiwan vocabulary. This is text normalization, **not an acoustic accuracy
improvement**. Mixed units are Han characters, Latin words, and numeric tokens;
spaces are preserved until English tokenization. Mixed-unit error is not a general
English WER. OpenCC implementation is pinned to `opencc-python-reimplemented==0.1.7`.

## Accuracy results

All entries below use the same references within each column. `—` means not run,
not zero errors. Settings are automatic language detection unless explicitly
marked otherwise. No AI enhancement, vocabulary hints, or reference-derived
prompts were applied.

| Implementation | TaiMECS mixed error | TaiMECS normalized CER | Common Voice normalized CER | English commands mixed error | Empty outputs |
| --- | ---: | ---: | ---: | ---: | --- |
| Qwen0.6 native MLX eight-bit, physical M5 | 24/662 = 3.63% | 39/1023 = 3.81% | 21/291 = 7.22% | 12/30 = 40.00% | **0/90** |
| Qwen0.6 native MLX 4-bit | 20/662 = 3.02% | 25/1023 = 2.44% | 57/291 = 19.59% | 10/30 = 33.33% | 0/20 mixed; **5/40 CV**; 0/30 commands |
| Qwen0.6 native MLX 4-bit, integer-length correction | — | — | 44/291 = 15.12% | — | **3/40 CV** |
| Qwen0.6 original PyTorch FP32 CPU | 23/662 = 3.47% | 31/1023 = 3.03% | 21/291 = 7.22% | 11/30 = 36.67% | 0 on all three sets |
| Qwen0.6 FP32, English hint | — | — | — | 7/30 = 23.33% | 0/30; diagnostic control only |
| Qwen0.6 official FP32 runtime, dequantized 4-bit decoder only | — | — | 44/291 = 15.12% | — | **3/40 CV**, same three native failures |
| Qwen0.6 official FP32 runtime, dequantized 8-bit decoder only | — | — | 21/291 = 7.22% | — | 0/40 CV; decoder isolation control |
| Qwen0.6 CoreML int8 variant, shipping SDK frontend | 115/662 = 17.37% | 157/1023 = 15.35% | 60/291 = 20.62% | — | 0/60 |
| Qwen0.6 CoreML int8 variant, official precomputed frontend | 26/662 = 3.93% | 40/1023 = 3.91% | 32/291 = 11.00% | — | 0/60 |
| Qwen0.6 CoreML int8 variant, corrected native frontend | 28/662 = 4.23% | 40/1023 = 3.91% | 32/291 = 11.00% | — | 0/60 |
| Breeze ASR25 PyTorch FP32 CPU | 16/662 = 2.42% | 10/1023 = 0.98% | — | — | 0/20 mixed |
| Breeze ASR25 GGML Q8, CPU beam5 | 14/662 = 2.11% | 10/1023 = 0.98% | 19/291 = 6.53% | 8/30 = 26.67% | 0/20 mixed; 0/40 CV; **7/30 commands** |
| Current Parakeet V2, shipping SDK/model, physical Mac | — | — | — | 19/30 = 63.33% | **16/30 commands** |
| X-ASR160 greedy, 500 ms flush | 66/662 = 9.97% | 85/1023 = 8.31% | 50/291 = 17.18% | 18/30 = 60.00% | 0/20 mixed; 0/40 CV; **16/30 commands** |
| X-ASR160 beam, 500 ms flush | — | — | — | 17/30 = 56.67% | **13/30 commands** |
| X-ASR160 greedy, no flush | — | — | — | 29/30 = 96.67% | **29/30 commands** |
| SenseVoice INT8 Core ML | 104/662 = 15.71% | 149/1023 = 14.57% | — | — | **2/20 mixed**, repeated on all three passes |
| SenseVoice FP32, fixed export shape | 55/662 = 8.31% | 56/1023 = 5.47% | — | — | 0/20 mixed |

On TaiMECS, native eight-bit Qwen's raw CER was 115/1022 = 11.25%, versus
normalized 3.81%; four-bit raw CER was 168/1022 = 16.44%, versus normalized 2.44%.
Breeze FP32's raw CER was 10/1022 = 0.98%; Q8's was 12/1022 = 1.17%. Traditional conversion therefore needs a
separate product policy; normalized scores must not conceal the actual output
script. Qwen's isolated English errors include wrong-language interpretation;
a forced-English control helps but does not validate automatic code-switching.
Eight-bit commands had 11 incorrect clips (19 exact), with 11 substitutions and
one insertion: 12 errors is not 12 failed clips. All 30 produced text.

The native Qwen 4-bit Common Voice failures are recordings of 2.256, 2.280,
4.296, 4.704, and 4.032 seconds, so they are not simply zero-length inputs.
No silence retry or transcript replacement is used to hide these failures.
The remaining three empty answers persist with whole-prompt prefill and FP32
encoder arithmetic; they generate immediate end-of-sequence, rather than text
that a parser accidentally removes.

A decoder-only control explains those failures. In the original PyTorch FP32
runtime, replacing the decoder with mathematically dequantized MLX 4-bit weights
reproduced the same three empty clips (`cv-009`, `cv-025`, `cv-034`) and 44/291 CER.
All 301 encoder tensors were verified bitwise identical to the original model
after the explicit Conv2D layout transform. All other untouched state keys were
also verified; 197 quantized matrices and the tied output head were replaced.
Repeating with the [8-bit checkpoint](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/tree/89e96d92ba34aca20b3e29fb10cc284097d1219f)
returned 21/291 CER and zero empty outputs, matching the original's aggregate
score. The 4-bit representation alone can therefore cause these failures; they
are not exclusively a Swift runtime defect. The later physical native eight-bit
run independently recovered all three clips and matched 21/291 aggregate CER;
the FP32 dequantization control itself does not prove MLX arithmetic equivalence.

This isolation uses affine group-64 UInt32 unpacking into FP32
`code * scale + bias`; it deliberately excludes MLX BF16/kernel arithmetic.
Independent packed-value fixtures and exhaustive weight mapping passed. Runtime:
`qwen-asr==0.0.6`, `transformers==4.57.6`, `torch==2.14.0`, CPU FP32, two threads,
batch size one, automatic language, and 256 maximum generated tokens. The
original 21/291, zero-empty baseline was reproduced before the substitutions.

The Parakeet control uses the exact shipping FluidAudio `50aa0719` SDK, all 22
matching model-file hashes, the same 30 WAV hashes, a fresh TDT state per clip,
the production one-second final padding, and the catalog's nil language hint.
It is a headless physical Mac batch control, not an app test. Its weak isolated
word result prevents mislabeling every candidate keyword error as a regression
from the current app; it does not make those errors acceptable.

Breeze Q8 uses whisper.cpp `ba573929cd31ddea3c77c5dc9caae78da8117123`, eight Linux
CPU threads, automatic language, beam5/best5, no VAD, and no previous-text context.
Roma currently uses greedy decoding, so this is not identical app decoding.
The [pinned conversion](https://huggingface.co/alan314159/Breeze-ASR-25-whispercpp/tree/c7f120183c8e8ad932f315e04e3d0359d839702d)
is 1,656,129,708 bytes with SHA-256
`669eb226a0e23b42465a6d2f60ce1902fbd534e19faab59511730420eb25e90d`.
Its improved score relative to the FP32 run cannot be attributed to quantization
because the decoding settings differ. All eight command errors selected Chinese
for English audio; seven were empty.

## Physical native eight-bit deployment evidence

The Apple M5 / 32 GiB / macOS 26.6.1 batch run used source fork
`aee9bd1dffcf786f544d6562d971b3e25221e261`, MLX Swift 0.31.4, Swift LM 3.31.4,
Swift 6.2.1 and eight-bit snapshot `89e96d92ba34aca20b3e29fb10cc284097d1219f`.
Decoding was automatic language, GPU, greedy, maximum 256 tokens, without an
FP32-encoder override. The weights file is 1,006,229,426 bytes, SHA-256
`b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8`;
config/tokenizer downloads are additional. The generated tokenizer SHA-256 is
`a1b84857f2052751736e1ca96e208da455db7de53bea3b6e52c34600d59ec192`.

Some batch timing intervals overlapped helper compilation at 16:04–16:12 UTC.
The complete accuracy outputs remain recorded; those intervals are excluded from
latency and resource comparisons. The paced controls and separate resource pass
below have their own receipts and must not inherit those batch timing claims.

The resource pass sampled its own PID 13 times while one loaded model processed
61 sequential clips (longest-clip warmup, then the 60 bilingual recordings).
Sampled physical footprint reached 1,516,308,376 bytes (1,446 MiB), while the
kernel-reported lifetime peak was 2,223,998,872 bytes (2,121 MiB). All neural-ledger
tags were zero; MLX used the GPU, so this is an accounting category, **not zero
model memory**. These are profiling results, not latency results or an app-process
delta. They establish a >1 GiB tradeoff; they do not establish sustained idle,
pressure, energy, or superiority over CoreML under a matched workload.

## Historical four-bit VM deployment evidence

The clean Qwen mixed-language run used [mlx-audio-swift at bf14ae0](https://github.com/Blaizzy/mlx-audio-swift/tree/bf14ae0c26e4e85553dd989571cae29d70fa6735),
MLX Swift 0.31.4, Swift LM 3.31.4, Swift 6.2.1, and [4-bit model revision
313d850](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit/tree/313d850181767edf09f00a9c289becca70e58cd0).
The package declares macOS 14 / iOS 17. Its code is MIT; model weights are
Apache-2.0. Actual app and iOS integration are separate gates.
Native batch decoding used automatic language, greedy selection, and a maximum
of 256 generated tokens. The streaming control used `.realtime`, a 0.35-second
decode interval, `maxCachedWindows=2`, and 1,280-sample (80 ms) input packets.
No explicit silence tail was appended; stop drained the pending frontend/audio.

| Measurement | Clean native Qwen4bit result | Scope |
| --- | ---: | --- |
| Whole-file inference median | 353.7 ms | 20 mixed-language recordings; includes first inference |
| Aggregate RTF | 0.04799 | Total inference / total recording duration |
| Model load | 505.5 ms | Warm OS/model cache; **not** first-install cold start |
| Process peak RSS | 868,532,224 bytes | Lifetime process high-water mark |
| MLX peak allocation | 1,367,963,820 bytes | MLX counter; distinct from process RSS |
| MLX active allocation after inference | Approximately 714 MB | Not physical wired neural allocation |
| Weights file | 708,236,945 bytes | Download size only; ancillary tokenizer/config files additional |

The disposable Mac had six virtual CPUs, 14 GB RAM, macOS 26.3.1 and an Apple
Paravirtual Metal GPU, with **no ANE**. Timed native runs were isolated from other
inference/builds. An earlier partial run overlapped a build and is preserved but
excluded. Linux FP32 controls establish accuracy, not optimized Apple performance;
Breeze's 973.7-second CPU pass is not an MLX/Core ML latency estimate.

The user's approximately 469 MiB physical active neural baseline is a different
counter and environment. It cannot be compared directly with RSS, MLX active
allocations, weight size, or total unified memory. Physical wired/reclaimable
allocation, power, and idle behavior were unmeasured in this VM pass. The later
physical eight-bit process measurements above are a separate environment.

## Physical CoreML Qwen control

The unchanged shipping FluidAudio `50aa0719` SDK also contains a real Qwen
manager, gated to macOS 15 / iOS 18 and arm64. The [CoreML snapshot at c081689](https://huggingface.co/FluidInference/qwen3-asr-0.6b-coreml/tree/c081689ec58bcf29c2ef7c474ef78a164bda672b)
was downloaded by exact revision and verified file hashes: 12 required files,
1,285,887,304 bytes for the `int8` variant. This name does not mean every tensor
is int8: its encoder is FP16; the decoder mixes FP16 and int8 weights.

On a physical Apple M5 with 32 GiB RAM and macOS 26.6.1, the SDK's HTK mel scale
and uncentered frames caused substantial recognition loss. Replacing only input
features with the pinned official Qwen processor improved both public sets above.
A small native Accelerate frontend using Slaney filters and centered reflect
padding then matched all 60 official feature shapes, valid lengths and tails:
maximum absolute difference `5.50e-5`, mean clip RMSE `5.46e-7`, versus stock SDK
mean RMSE `0.278`. This establishes a native path without a Python runtime.
The SDK and model inference implementation remained unchanged.

Native and official-feature transcripts matched on 59/60 clips. The remaining
clip split `workload` into `work load`, adding two mixed-unit errors while leaving
CER unchanged. Corrected native raw CER was 62/291 = 21.31% on CV and
216/1022 = 21.14% on TaiMECS; the normalized scores must not hide the substantial
Simplified Chinese output difference. Corrected native batch medians were 0.384 s on CV and 1.181 s on
TaiMECS, including frontend work; aggregate RTF was 0.143 / 0.147. Official-feature
timings excluded preprocessing and are not directly equivalent. These are batch
measurements, not streaming release latency. The convenience streaming wrapper
retranscribes a growing buffer every two seconds, caps it at 30 seconds, and has
a one-second minimum by default; it is not an accepted Roma streaming adapter.

The conversion also differs structurally from official Qwen: its fixed one-second
encoder attention includes padded tail positions that the SDK only trims after
attention, whereas the official model removes padding before attention and can
group longer windows. These source differences could contribute to the remaining
accuracy gap; this has not been isolated experimentally. The [pinned SDK documents the context limitation](https://github.com/FluidInference/FluidAudio/blob/50aa07193e84b9cf192d8f36041c24a9a4867cd6/Documentation/ASR/Qwen3-ASR.md#coreml-limitations);
the [official encoder removes padding before attention](https://github.com/QwenLM/Qwen3-ASR/blob/7c6daf77a2421100f5fb066495372c00129d39ff/qwen_asr/core/transformers_backend/modeling_qwen3_asr.py#L625-L672).
Do not attribute the
whole residual gap to weight quantization or present the conversion as equivalent.
Its decoder also uses per-output-row signed int8 scaling with FP16 scales and
unquantized external token embeddings. The MLX 8-bit control instead uses affine
group-64 BF16 scale/bias and quantized embeddings. Equal bit width does not make
them a matched quantization comparison.

A follow-up resource pass used the **corrected native frontend and all 60
bilingual recordings**, after the longest-clip warmup. It collected 76 successful
own-PID samples with no query failures, including 40 active-corpus samples and
11 samples during 10.48 seconds of post-corpus idle. The largest collection took
58.6 ms; this profiling pass is not a latency comparison.

| Counter / phase | Corrected native CoreML Qwen result |
| --- | ---: |
| Active neural ledger / wired | 360.141 MiB / 360.344 MiB |
| Active neural reclaimable | 0.203 MiB |
| Active sampled process footprint maximum | 1,915,373,632 bytes = 1,826.643 MiB |
| Kernel-reported lifetime process peak | 1,929,611,328 bytes = 1,840.221 MiB |
| After 9.17 s idle: neural clean / wired | 3.109 MiB / 0 MiB |
| After 9.17 s idle: neural reclaimable | 357.234 MiB |
| Process footprint at that idle sample | 1,745,307,712 bytes = 1,664.455 MiB |

These are overlapping accounting views, not quantities to add. The earlier
stock-frontend repeated-clip pass observed only six seconds of idle and missed
this transition. Its apparent lack of reclaimability is superseded; different
workloads and observation windows prevent a frontend-causality claim. The active
neural ledger is below the historical ~469 MiB Parakeet reference, but substantial
non-neural process memory remains. Neither pass proves all-day behavior, memory
pressure response, energy use, or actual GPU/ANE placement.

## Current physical eight-bit streaming controls

The same 20 TaiMECS human recordings were replayed with causal packet-end pacing,
automatic language and no reference prompts. The cumulative control follows the
official policy: fresh decoding over all audio so far, first two passes without
an output prefix, then a five-token rollback of prior raw output. It is not
bounded-cost cached decoding. The older window policy and cumulative policy also
differ in cadence, context and prefix handling; their comparison is not a one-variable
experiment. At the same 350 ms cadence, cumulative decoding scored 27/662
versus the window policy's 76/662 on the same model and recordings.

| Native eight-bit policy | Mixed error | Normalized CER | Empty / token-cap hits |
| --- | ---: | ---: | --- |
| Older eight-second window policy, 350 ms cadence | 76/662 = 11.48% | 106/1023 = 10.36% | 0/20 / not summarized here |
| Cumulative policy, 350 ms cadence | 27/662 = 4.08% | 34/1023 = 3.32% | 0/20 / 0 |
| Cumulative policy, two-second cadence | 25/662 = 3.78% | 29/1023 = 2.83% | 0/20 / 0 |

| Cumulative timing, 20 clips | Two-second cadence median / p95 | 350 ms cadence median / p95 |
| --- | ---: | ---: |
| First nonempty partial from recording start | 2,199.7 / 2,686.3 ms | 672.4 / 875.9 ms |
| Nominal release-to-final, including feed backlog | 175.6 / 293.6 ms | 172.6 / 267.7 ms |
| Stop invocation-to-final | 160.3 / 217.0 ms | 139.0 / 167.3 ms |

For 350 ms cadence, first-partial maximum was 2.196 s (cold-process first clip),
release-to-final maximum 292.5 ms and feed-overrun maximum 158.3 ms. Cold-process
work is included; this is not a fresh-install cold-start measurement. Nonempty
text does not prove a useful partial: a post-hoc check found the first three
canonical reference units in a live prefix on 18/20 clips, median 1.238 s /
p95 2.488 s among those 18. Suffixes could still be wrong; references were used
only after decoding. There are no labeled speech onsets or human usability/stability
judgments. Release-to-final p95 remains above 250 ms before app insertion overhead.
Actual shared-module helper replay, model lifecycle, and end-to-end app insertion
are still required; probe acceptance does not establish those boundaries.

## Historical four-bit window-stream findings

The earlier native Qwen window session accepts new samples and caches completed
eight-second encoder windows. It re-encodes the incomplete window and creates a
new decoder cache per decoding pass. This is bounded-window incremental
processing, not fully cached decoding. The API defaults to English; a bilingual
adapter must explicitly request automatic language detection.

Source inspection found a real frontend mismatch: batch preprocessing used
Slaney mel scale and periodic Hann; incremental preprocessing still used HTK
scale and symmetric Hann. The isolated fixture compared identical interior
frames: pristine max absolute error **2.022763**, corrected **0**, threshold
`0.0001`. Only those two constructor arguments changed. This proves the frontend
regression fix; it does not prove streaming transcript quality or finalization.
An additional incomplete-frame guard fixes Swift integer truncation attempting a
400-point FFT from 241–399 buffered samples. The actual module reproduced that
failure, then passed all four regression tests including 800 encoder lengths,
batch/stream mel parity, uneven packets, and short-buffer flushing.

The fixes are maintained in a minimal [reviewed source fork at 9adf5b3](https://github.com/negentropi/mlx-audio-swift/commit/9adf5b35d1e15119785e7bc1b531877ee680f7dc),
with original MIT terms and provenance retained. No build-time source patch or
app dependency change was used in that experiment. A drop-last-STFT-frame experiment did not recover
the remaining CV failures and was excluded from the fork.

A subsequent [protocol-parser correction at aee9bd1](https://github.com/negentropi/mlx-audio-swift/commit/aee9bd1dffcf786f544d6562d971b3e25221e261)
passed 12 actual-source Foundation test bodies and two fresh independent reviews.
The physical eight-bit results above include this correction; the historical
four-bit scores below precede it.

With these three fixes, a paced native run finished all 20 human clips without
empty output, but **all 20 exposed generated language/protocol headers**. Raw
mixed error was 186/662 = 28.10%. Removing only the known headers in a separate
diagnostic left 62/662 = 9.37% mixed error, including 43 insertions. That diagnostic
is not a repaired-runtime score: repeated words across windows remain a separate
defect. The production repair must parse each generated window's protocol while
preserving decoder token/cache state and ordinary literal text.

The probe supplied each packet at its start-sample timestamp, making up to 80 ms
of future microphone audio available early; it waited until the full recording
duration before stopping. This is an exploratory schedule, not causal microphone
pacing. The current physical eight-bit controls above use the corrected packet-end schedule.

Finalization from nominal audio end was median 293.3 ms, p95 502.5 ms,
maximum 503.8 ms. It includes ingestion backlog (maximum 136.4 ms) and is not the
Roma insertion gate. First-partial and display-event counts are invalid transcript
latency/stability measures while headers and identical repeated events count as
text. Peak RSS was 877,854,720 bytes; MLX peak was 1,371,771,332 bytes.

## Remaining requirement coverage

| Requirement | Evidence / remaining work |
| --- | --- |
| 1. zh-TW CER | Two public human sets; native eight-bit CV matches original aggregate with no empties; broader coverage pending |
| 2. English WER | General labeled dictation set not measured; keyword test is narrower |
| 3–5. Code-switching, embedded technical words, Taiwanese accent | TaiMECS one speaker; independent broad-speaker switching set still needed |
| 6. Single words | Thirty labeled commands, including exact current Parakeet comparison; narrower than general dictation and no excellent-recognition claim |
| 7. Sub-1-second speech | Not annotated; one-second recording is not a speech-duration label |
| 8. 1–3-second utterances | Twenty short CV recordings, not isolated speech-duration measurements |
| 9. Normal dictation | Mixed-language recordings; broader long dictation still needed |
| 10–12. Fast speech, noise, microphone variation | Not controlled or annotated |
| 13. Insertions/deletions/substitutions | Recorded in scorer JSON per clip and aggregate |
| 14. Hallucination rate | Not a labeled silence/non-speech benchmark yet |
| 15–18. First token, partial delay, finalization, stability | 350 ms control measured nonempty partials and release tail; speech-onset, usable partial/stability and app insertion proof pending |
| 19. RTF | Native batch and CPU controls measured separately |
| 20–23. Neural/process/idle memory | Physical MLX and corrected CoreML own-process samples above; sustained/pressure behavior and app process delta pending |
| 24–26. CPU, GPU/ANE, energy | MLX GPU route and CoreML sampled process CPU; zero MLX neural tags are accounting, not energy proof; controlled silent-hold/power and CoreML placement pending |
| 27. Cold start/load | Warm-cache load measured; fresh-install cold start pending |
| 28. Download size | Pinned file bytes above; not RAM |
| 29–30. Apple runtime and macOS integration | Native batch/stream probes and shared production-module compile complete; actual helper replay, lifecycle and app gate pending |
| 31. iOS viability | Package deployment declaration only; native device/runtime validation pending |
| 32. Commercial shipping | Code/model licenses identified; retain notices, conversion provenance and pinned artifacts; no broad training-data clearance claim |

## Evidence receipts

Local ignored evidence lives in `.local-build/asr-research/`:
`qwen-native/`, `linux-controls-20260907/`, `public-20260907/`, `breeze-ggml/`,
`qwen-quantization-control/`, and `qwen-coreml/`.
Current physical eight-bit receipts are under `qwen-native/physical-8bit/`:
`human20-score.json`, `cv40-score.json`, `commands30-score.json`,
`window-human20-score.json`, `official-human20-score.json`, `fast-human20-score.json`,
the matching `*-human20-summary.json` files, `fast-human20-coverage.json`, and
`resource/{summary,samples,receipt}.json`. Corrected CoreML resource receipts are
under `qwen-coreml/resource-native-corpus/`, with summary, samples, source and
public-audio hashes. These distinguish current results from the older controls.

They contain public reference manifests, raw outputs, reviewed scores, environment
receipts, source revisions, and failed/contended diagnostics. Neither disposable
initial Linux instance remains running. The decoder-isolation instance was also
checkpointed and destroyed after delivering the official features. The original
shared Mac was checkpointed and destroyed to release capacity for full app CI;
the parent coordinates the current runtime Mac and owns app acceptance.
