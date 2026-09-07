# Roma local ASR investigation — 2026-09-07

Status: candidate investigation and first private-audio diagnostics. No replacement
selected; Parakeet V2 remains the default. No v1.95.1 release or landing deployment
is implied by this work.

## Recommendation

Investigate **X-ASR-zh-en** as the streaming candidate and **SenseVoiceSmall INT8
Core ML** as the compact Apple-runtime candidate. Use **Breeze ASR 25** as a
Taiwanese/code-switching accuracy control and **Qwen3-ASR 0.6B** as an additional
accuracy candidate. These are evaluation priorities, not measured accuracy ranks.
There is no verified single model satisfying the entire requirement list yet.
X-ASR's missing outputs on several private clips need resolution before it is
an integration recommendation. All five model families now have actual local
diagnostic outputs; none has a human-scored accuracy result on this corpus.

| Candidate | Why it deserves testing | Main gap for Roma |
| --- | --- | --- |
| X-ASR-zh-en, 160/480 ms | Bilingual Zipformer streaming; downloadable ONNX; existing sherpa Swift/C integration | Taiwan, mixed technical vocabulary, and subsecond accuracy unproven; CPU cost/porting to ANE must be measured |
| SenseVoiceSmall INT8 Core ML | Existing FluidAudio manager; compact multilingual CTC pipeline; quantized artifact available | Whole-utterance inference, not native streaming; exact zh-TW/code-switch quality and physical ANE behavior unproven |
| Breeze ASR 25 | Publisher directly targets Taiwanese Mandarin and intra-utterance English; Whisper architecture fits Roma's existing family of runtimes | Larger model; batch architecture; conversion/quantization parity and actual short-word behavior need testing |
| Qwen3-ASR 0.6B | Multilingual accuracy candidate, local Apple ports available | Official wrapper reprocesses accumulated audio; experimental incremental ports need independent validation |
| Nemotron 3.5 multilingual Core ML | Cache-aware native stream, Swift integration, commercial model license | Mandarin is zh-CN broad coverage; current Core ML port has a substantial Chinese latency/quality tradeoff; no demonstrated zh-TW switching advantage |

The [external-source report](asr-candidates-external.md) contains the X-ASR,
Breeze, Qwen, Paraformer, licensing, and original NVIDIA zh-TW evidence. Relevant
primary artifacts: [X-ASR](https://huggingface.co/GilgameshWind/X-ASR-zh-en),
[SenseVoice Core ML](https://huggingface.co/FluidInference/sensevoice-small-coreml),
[Breeze](https://huggingface.co/MediaTek-Research/Breeze-ASR-25),
[Qwen](https://huggingface.co/Qwen/Qwen3-ASR-0.6B),
[Nemotron Core ML](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML).

## What the runtime/source inspection established

Roma source at `94d5ed65` pins FluidAudio `50aa07193e84b9cf192d8f36041c24a9a4867cd6`.
`FluidAudioStreamingProvider.runTranscriptionPass()` selects an overlapping audio
slice and creates a fresh `TdtDecoderState` on each transcription pass. Its word
agreement engine stabilizes/retires text. It is not a cache-aware encoder stream.
The research harness uses newer FluidAudio
`5c19d5e12320e22bbfb7a1877b089d2665a69add`, so a standalone Parakeet result is an
engine control, not an exact current-app runtime baseline. Source:
[Roma provider](../../VoiceInk/Transcription/Streaming/FluidAudioStreamingProvider.swift),
[existing dependency pin](../../VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved),
[research SDK](https://github.com/FluidInference/FluidAudio/tree/5c19d5e12320e22bbfb7a1877b089d2665a69add).

Current FluidAudio separates batch/sliding-window models from actual streaming
managers. SenseVoice is a separate manager, not an `AsrModelVersion` value; adding
only a catalog row would not implement it. Preserve one stream across Roma's
pre-roll and live frames, flush on release, and route model-specific managers
through Roma's existing transcription event boundary. Do not force CTC or
Zipformer into a TDT-only model loader. [SDK model families](https://github.com/FluidInference/FluidAudio/blob/5c19d5e12320e22bbfb7a1877b089d2665a69add/Documentation/Models.md)

## Artifact and memory evidence

Public manifest inspection found the following exact downloads. These are
**download bytes**, not wired neural allocation or peak process memory:

| Variant | Pinned revision | Selected file bytes |
| --- | --- | ---: |
| X-ASR 160 + 480 ms combined | `689ff18c584d29910da37b6fe904db0c1489c9d1` | 1,229,192,128 |
| SenseVoice preprocessor + INT8 + vocabulary | `cdea3526163035c19915d4a10268992d018ebd46` | 239,913,642 |
| Parakeet V2 Roma manifest components | `ee09c569f73759e6d44c9bd16766f477b2b36d39` | 464,413,250 |
| Qwen3-ASR 0.6B selected snapshot | `5eb144179a02acc5e5ba31e748d22b0cf3e303b0` | 1,880,618,159 |
| Breeze ASR 25 selected snapshot | `cffe7ccb404d025296a00758d0a33468bec3a9d0` | 3,092,421,455 |

[Pinned X-ASR files](https://huggingface.co/GilgameshWind/X-ASR-zh-en/tree/689ff18c584d29910da37b6fe904db0c1489c9d1),
[pinned SenseVoice files](https://huggingface.co/FluidInference/sensevoice-small-coreml/tree/cdea3526163035c19915d4a10268992d018ebd46),
[pinned Parakeet files](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/ee09c569f73759e6d44c9bd16766f477b2b36d39).
[Pinned Qwen files](https://huggingface.co/Qwen/Qwen3-ASR-0.6B/tree/5eb144179a02acc5e5ba31e748d22b0cf3e303b0),
[pinned Breeze files](https://huggingface.co/MediaTek-Research/Breeze-ASR-25/tree/cffe7ccb404d025296a00758d0a33468bec3a9d0).

The user's measured ~469 MiB active neural allocation remains the physical-Mac
reference. Its scope excludes some CPU-side allocations and general app memory.
Do not compare it directly with a publisher's peak RAM, downloaded weight size,
VM RSS, or total unified memory. Accuracy remains the objective; >1 GiB deserves
an explicit tradeoff, not automatic elimination.

SenseVoice's converter reports about 225 MB INT8 encoder size and 0.32 GB peak RAM,
with Mainland Chinese/English conversion checks. Those are publisher measurements,
not Roma results or Taiwanese evidence. The model uses padded shape buckets and
batch decoding; the 70 ms/10-second audio claim must not be presented as streaming
first-token latency. The converter warns about FP16 CPU/GPU numerical problems
and recommends FP32 where ANE is absent. [Conversion card](https://huggingface.co/FluidInference/sensevoice-small-coreml)

Nemotron's available Core ML port is not equivalent to every chunk mode in the
latest NVIDIA base-model card. The port lists 560/1120/2240/4480 ms tiers; its full
vocabulary is necessary for Chinese. It reports 18.57% CER on FLEURS Mainland
Mandarin at 2240 ms, with roughly 2.5-second latency, on M5 Pro. This is not a
Taiwanese benchmark and is not directly comparable with a different candidate's
AISHELL or FLEURS subset. [Port](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML),
[base model](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)

## Private-recording results

Executed on a disposable Namespace Mac: macOS 26.3.1, virtual Apple M4 Pro,
6 vCPUs, 14 GB RAM. Core ML enumerated CPU and Apple Paravirtual GPU, **no ANE**.
The input was 12 unique PCM16 mono/16 kHz WAVs, 70.410625 seconds total, with
no corrected references. Filenames suggest short-word/noise cases but are not
ground truth. There is no labeled zh-TW or code-switching benchmark here.

| Whole-file control | Empty outputs / 12 unique clips | Median inference | Aggregate RTF | Sampled peak process RSS |
| --- | ---: | ---: | ---: | ---: |
| SenseVoice INT8 Core ML | 1 | 48 ms | 0.011 | 589 MiB |
| Parakeet V2 Core ML | 1 | 135 ms | 0.023 | 1,269 MiB |
| Qwen3-ASR 0.6B, CPU FP32 | 0 | 463 ms | 0.146 | 4,333 MiB |
| Breeze ASR 25, CPU FP32 | 0 | 5,262 ms | 0.980 | 8,521 MiB |

Core ML timing uses repetitions 2–3 after one complete corpus pass, in the final
unprofiled runs. Qwen/Breeze use one pass including first-inference overhead,
two Torch threads, automatic language detection, and a 256-token cap. RTF is
total inference time / total audio duration; lower means less computation per
audio second. RSS includes the runtime/process and is sampled across loading,
inference, and idle. Different runtimes, precision, and warmup mean this table
is a deployment diagnostic, **not an architecture efficiency ranking**. The
CPU FP32 controls are not optimized Core ML/MLX ports and cannot be compared
with the ~469 MiB physical neural-memory target.

The first Parakeet load took 96.7 seconds including initial Core ML preparation;
the later load with prepared caches took 0.155 seconds. SenseVoice's corresponding
loads were 0.934 / 0.149 seconds. Do not advertise the cached value as first-install
startup. Initial profiled-run RSS peaks were 1,643 MiB Parakeet / 748 MiB SenseVoice;
reporting only a single memory number would hide this variation.

For X-ASR, explicit end-of-file silence padding changed completion behavior:

| Model tier | No tail: empty / 12 | 500 ms tail: empty / 12 | 1,500 ms tail: empty / 12 |
| --- | ---: | ---: | ---: |
| 160 ms | 6 | 4 | 4 |
| 480 ms | 5 | 3 | 3 |

The 500 ms and 1,500 ms padding is synthetic and submitted without waiting;
it is a manual-release flush strategy. More padding did not recover additional
nonempty results. Empty output is a diagnostic, not automatically a deletion:
speech content needs human confirmation. Nonempty outputs also disagreed,
including short-word language selection; zero empty answers does not mean best
accuracy. No CER, WER, hallucination rate, or model winner is asserted.

Final paced runs fed 80 ms packets when those samples would become available.
With a 500 ms tail, both models produced a live partial on 6 of 12 clips, counting
only events at or before manual release (the clip's audio duration). Median first
live partial was 3,184/3,344 ms for 160/480 ms **from clip start**, only over clips
with a live partial; pre-roll is unlabeled, so these are not speech-onset latency
estimates. A seventh 480 ms clip produced its first partial after release while
decoding the last packet; it is excluded from live coverage.
Manual release-to-final p50 was 78.5/71.8 ms and p95 was 132.3/106.8 ms, including
pending decoding. The p95 uses nearest rank over 12 clips, therefore equals the
maximum. It includes empty final answers and must be read alongside the empty
counts. `partial_events` excludes final draining; final text may extend it.
Automatic endpoint detection was disabled and remains unmeasured.

Runtime receipts: sherpa-onnx 1.13.7; qwen-asr 0.0.6; transformers 4.57.6;
torch 2.14.0; Python 3.14.3; Swift 6.2.1. Final timed runs were sequential after
downloads/installations. Initial paced runs are retained but excluded from the
table because installation overlapped part of that phase. One early Parakeet
attempt used a noncanonical local directory, triggered a fallback download,
and was stopped; it is excluded. The corrected runs used pinned local assets.

Raw WAVs, transcripts, sampled RSS, run receipts, package versions, and a local
listening/reference-export page remain under ignored
`.local-build/asr-research/20260907/`. Audio, original filenames, and transcripts
are excluded from the research commit. Active neural allocation, reclaimability, power, physical ANE
usage, iPhone behavior, speech-onset latency, and Roma insertion remain **N/A**.

## Shipping constraints

Keep code, original weights, conversion, tokenizer, and training-data provenance
distinct. X-ASR and Breeze declare Apache-2.0, but an unspecified collected
training corpus is not a completed provenance audit. SenseVoice's **custom model
license** applies to its converted weights; the SDK/code license does not replace
it. Nemotron's port declares OpenMDW-1.1. Retain required notices and pin the actual
license text with each downloadable variant. These observations identify terms
to check; they are not a blanket legal or training-data clearance.
[SenseVoice model terms](https://github.com/modelscope/FunASR/blob/58830eca4012644aac0c3218c3ccc7d98f003fda/MODEL_LICENSE),
[SenseVoice publisher clarification](https://github.com/QwenAudio/SenseVoice),
[OpenMDW-1.1](https://openmdw.ai/license/1-1/)

The originally requested NVIDIA `parakeet-ctc-0.6b-zh-tw` remains conditional:
its Riva/NIM offering is not proof of a portable, commercially redistributable
Mac checkpoint. Do not silently replace the requirement with a hosted API.

## Acceptance experiment

Use exactly the same input/reference manifest across candidates, including a
license and SHA-256 per recording. Keep model/SDK revision, decoding settings,
language hint, precision, packet size, padding, and VAD policy in each receipt.
Preserve a held-out set; do not choose hotwords or thresholds from its answers.

1. **Recognition:** score raw Traditional Chinese CER, English WER, and a mixed
   error rate using Chinese characters plus English words; publish S/D/I counts.
   Score technical tokens/names and whole-utterance exact match separately.
   Report script-normalized scores additionally; script conversion is not better
   accent recognition. Keep grammar correction/AI Enhancement off.
2. **Strata:** Taiwanese speakers, switching within one sentence, English technical
   terms, isolated words, <1-second speech, 1–3-second speech, longer dictation,
   fast speech, noise, and different microphones. Clip length may include pre-roll;
   label speech duration/onset separately. Include silence and non-speech audio.
3. **Streaming:** paced audio; first token from labeled speech onset; partial
   delay/stability; release-to-final; automatic endpoint separately; p50/p95 and
   failures. Verify encoder cache reuse from implementation and bounded long-stream
   cost. Test empty/short final packets and 0/500 ms explicit flush padding.
4. **Resources:** same physical Apple Mac, sequential runs, fixed power/thermal
   conditions; cold and warm runs; active neural wired allocation, total ASR
   process delta, idle clean/reclaimable/non-reclaimable categories, CPU time,
   GPU/ANE utilization, energy, load latency, and selected download size. Report
   unavailable counters as N/A. Separately test a representative iPhone.
5. **Roma boundary:** only finalists enter the app; test pre-roll, immediate Shift
   release, cancellation, switching/deleting models, and real insertion. A new
   model diagnostic is not a known-bad/candidate regression proof for Roma.

The [reproducible probe](../../Tools/ASRBenchmark/README.md) and private results
record only the subset actually exercised. No model should be advertised as
meeting all 32 requirements until those measurements exist.
