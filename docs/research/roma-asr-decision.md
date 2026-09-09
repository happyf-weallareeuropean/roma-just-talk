# Roma local ASR investigation — 2026-09-09

Status: native eight-bit Qwen is the local bilingual integration lead, with app
acceptance still pending. Parakeet V2 remains the current English choice.
No v1.95.1 release or landing deployment is implied by this work.

## Current app result

The fixed 48-case cancellation comparison on September 8 completed against
baseline `09ed6015` and candidate `9dc47caf`, on one disposable Apple Silicon
Mac running macOS 26.3.1. It repeated three public fixtures across TextEdit and
Code, empty/existing text, and ABBA blocks. This is a narrow diagnostic matrix,
not 48 independent recordings or a public-download acceptance test.

The unchanged render audit qualified 42 observations and 19 matched pairs.
Qualified visible arm medians were **434.30 ms → 329.11 ms** (21 observations
per arm); the median paired improvement was **117.90 ms** (19 pairs). All 42
qualified observations exceeded 250 ms; six observations remain unqualified.
Both arms scored 8 substitutions over 608 mixed reference units, with no empty
outputs. The candidate's final worker alone exceeded 250 ms in 13/24 cases
(median 252.24 ms), before text delivery. Cancellation helps, but does not meet
the insertion requirement. Different captured sample counts and playback timing
prevent treating this as an identical-input compute comparison.

A subsequent on/off instrumentation experiment recorded 18/24 cases before a
process-identity observer failure interrupted A2 startup. The whole experiment
is invalid: missing cases, a paired score difference, different recording and
cancellation trajectories, and an unqualified render prevent an accepted
instrumentation comparison. Its 12 instrumented timelines locate expensive
encoder, prefill, and sequential generation work; they do not prove any of it
can safely be skipped. Even subtracting the entire observed cache-clear/drain
cost would leave 9/12 workers above 250 ms before delivery. That arithmetic is
an upper-bound exercise, not a predicted optimization.

Finish the independently scoped process-observer repair before reusing that
runner. Do not repeat the unchanged matrix looking for a favorable result.
Any next optimization needs a specific compute or scheduling contract, preserved
recognition quality and ownership, then actual app insertion proof. The 250 ms
gate remains unchanged. Parakeet V2 remains the English option; NVIDIA zh-TW is
an explicit cloud backup, not the primary local solution.

Retained local evidence under `.local-build/asr-research/qwen-integration/`:

- `cancellation-shipping-v1/app-comparison-v2/analysis-416mddbkt9hsg/REPORT.md`:
  completed comparison, all cases and qualification reasons.
- `final-worker-partition-v1/actual-kb32jrvtbidek/native-path-analysis/REPORT.md`:
  incomplete experiment and limits of the observed component costs.
- `exact-transformer-batch-timing-v1/physical-timing-v1/REPORT.md`:
  exact reuse saved about 20–24 ms on eligible ordinary native requests, but
  slowed no-hit requests and did not solve startup generation. Research-shader
  timings are separate from the app artifact.

## Recommendation

Advance **Qwen3-ASR 0.6B native MLX eight-bit** through Roma integration. On the
physical Apple M5, automatic-language batch decoding returned no empty outputs
across all 90 public clips. TaiMECS scored 24/662 mixed errors (3.63%) and
39/1023 normalized CER (3.81%); the 40-speaker Common Voice subset scored 21/291
CER (7.22%), matching the original FP32 aggregate. The three remaining four-bit
early-EOS failures did not recur. Isolated English commands remain weak:
12 errors over 30 words, affecting 11 clips; this is not general dictation WER.

With cumulative-audio decoding every 350 ms, all 20 human mixed-language clips
completed without empty output or token-cap hits: 27/662 mixed errors (4.08%)
and 34/1023 normalized CER (3.32%). First nonempty text from recording start was
median 672 ms / p95 876 ms, with a cold-process maximum of 2.196 seconds.
Release-to-final was median 172.6 ms / p95 267.7 ms. Nonempty text is not a
validated usable partial, and this headless result does not pass Roma's 250 ms
insertion gate. On the same model and recordings at 350 ms cadence, cumulative
decoding scored 27/662 versus the older window policy's 76/662. The two-second
cumulative control scored 25/662. Context and prefix handling also change, so
these comparisons do not isolate a single cause. Shared production-module compilation is
complete; the later app comparison above exercises actual helper delivery and
cancellation. Broader lifecycle coverage and full app acceptance remain pending.

A separate physical resource pass sampled MLX process footprint up to 1,446 MiB,
with a kernel-reported lifetime peak of 2,121 MiB. Its zero neural-ledger tags
reflect GPU accounting, not zero model memory. This is a substantial memory
tradeoff requiring app-level validation. Batch timings that overlapped helper
compilation at 16:04–16:12 UTC are excluded from performance comparisons.

Correcting the separate FluidAudio CoreML frontend produced 11.00% CV CER and
4.23% mixed error, without empty clips. The corrected whole-corpus resource
follow-up measured 360 MiB active neural allocation and 1,827 MiB sampled
process footprint. About 357 MiB became neural-reclaimable after 9.17 seconds
idle, superseding the earlier six-second observation. Different workloads and
observation windows prevent attributing this change to the frontend correction.
CoreML's attention context/padding differences and whole-buffer streaming
wrapper remain tradeoffs; it is not the integration lead.

**Breeze ASR 25 Q8** produced 2.11% mixed error and 0.98% normalized CER on that
set, plus 6.53% CER on the 40-speaker subset without empty answers. Its complete
1.656 GB artifact loads through whisper.cpp; the CPU beam-search control is not
the app's greedy decoder or an Apple performance result. Its quality makes it a
credible alternative if native memory and streaming costs are acceptable.
**X-ASR** is excluded from the current recommendation: its measured bilingual
accuracy trails both candidates and 16 of 30 labeled English commands were empty
even with a 500 ms flush (13 with beam search). Current Parakeet also returned
16 empty commands, so the keyword failure alone is not evidence of a regression
from the current app. **SenseVoice INT8**
also returned two repeatable empty bilingual outputs on the VM without an ANE;
FP32 avoided those failures but required a research frontend-shape correction.

The [public benchmark report](roma-asr-public-benchmark.md) records corpora,
settings, scores, limitations, and the remaining 32-requirement coverage. No
candidate has yet demonstrated the entire requirement list. Earlier unlabeled
private-recording diagnostics below remain historical evidence, not accuracy
rankings.

| Candidate | Why it deserves testing | Main gap for Roma |
| --- | --- | --- |
| Qwen3-ASR 0.6B native MLX eight-bit | All 90 batch clips nonempty; original-level CV aggregate; 350 ms cumulative streaming measured | Isolated English/language choice, Traditional output, usable partials, >1 GiB process memory, lifecycle and actual app 250 ms gate |
| Breeze ASR 25 | Best measured bilingual scores; complete Q8 artifact verified through whisper.cpp | Apple memory/performance and app greedy decoding/streaming unverified; wrong-language isolated English errors |
| X-ASR-zh-en, 160/480 ms | Bilingual Zipformer with cached streaming | Tested accuracy and command deletions trail the leading alternatives; no onboarding integration |
| SenseVoiceSmall INT8 Core ML | Compact multilingual CTC pipeline | Repeatable empty outputs on VM without ANE; batch architecture; physical ANE remains unmeasured |
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
Some early research harnesses use newer FluidAudio
`5c19d5e12320e22bbfb7a1877b089d2665a69add`, so a standalone Parakeet result is an
engine control, not an exact current-app runtime baseline. A later headless
Parakeet command control uses the exact shipping SDK and all matching model/audio
hashes; its 19/30 errors and 16 empty outputs are recorded in the public report.
It still does not prove the live app's recording/insertion behavior. Source:
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
| Qwen3-ASR 0.6B MLX eight-bit weights only | `89e96d92ba34aca20b3e29fb10cc284097d1219f` | 1,006,229,426 |
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
are excluded from the research commit. For this historical private-recording pass,
active neural allocation, reclaimability, power, physical ANE usage, iPhone
behavior, speech-onset latency, and Roma insertion were **N/A**. Subsequent public
physical memory measurements are recorded in the public benchmark report.

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

The user clarified that NVIDIA `parakeet-ctc-0.6b-zh-tw` belongs in the optional
**cloud backup** list. The committed client uses the documented hosted Riva gRPC
contract and the user's NVIDIA API key, gated to macOS 15 / iOS 18. It never
replaces a local selection automatically. Native client tests, Core policy tests,
and an iOS 17 package cross-build passed; live hosted inference still requires a
key and remains unverified. Local bilingual selection is a separate requirement.

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
