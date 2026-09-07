# Native Qwen parity probe

Research only; no model catalog, onboarding default, or app dependency changes.
Native bilingual acceptance remains pending. Use a disposable Apple Silicon Mac
with full Xcode and Metal tools. Physical-device inference requires a separately
authorized headless slot; preserve the executable and adjacent Metal library.

## Current reproducible candidate

| Input | Exact revision / version | License |
| --- | --- | --- |
| [Reviewed MLX Audio fork](https://github.com/negentropi/mlx-audio-swift/tree/aee9bd1dffcf786f544d6562d971b3e25221e261) | `aee9bd1dffcf786f544d6562d971b3e25221e261` | MIT |
| MLX Swift | `0.31.4` | MIT |
| MLX Swift LM | `3.31.4` | MIT |
| [Next native eight-bit model](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/tree/89e96d92ba34aca20b3e29fb10cc284097d1219f) | `89e96d92ba34aca20b3e29fb10cc284097d1219f` | Apache-2.0 |
| [Historical four-bit control](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit/tree/313d850181767edf09f00a9c289becca70e58cd0) | `313d850181767edf09f00a9c289becca70e58cd0` | Apache-2.0 |

The fork preserves the original package's Swift 6.2, macOS 14 and iOS 17 baseline.
It contains the reviewed encoder-length, incremental frontend, short-packet and
language-header corrections. No dependency-source patch is applied during builds.
The parser pin has passed Foundation tests and the complete native probe compiles.

Stage this directory's `QwenNativePackage.swift` as `/tmp/roma-qwen-native/Package.swift`
and `QwenNativeProbe.swift` as `/tmp/roma-qwen-native/Sources/Probe.swift`. Copy
`QwenOfficialStreamingPolicy.swift` and `QwenOfficialStreamingControl.swift` into
the same `Sources` directory. Keep the standalone `*Proof.swift` outside that
executable target. Then:

```sh
cd /tmp/roma-qwen-native
swift build -c release --product QwenNativeProbe
mkdir -p scripts
curl --fail --location 'https://raw.githubusercontent.com/soniqo/speech-swift/ca4daaf9be7cccf230f691e443cd80b7a0bd8d97/scripts/build_mlx_metallib.sh' -o scripts/build_mlx_metallib.sh
printf '%s\n' '18e502916ecf10bfdb595bdec2b5d0cd97209a47e1779add896631c397965e55  scripts/build_mlx_metallib.sh' | shasum -a 256 -c -
bash scripts/build_mlx_metallib.sh release
shasum -a 256 Package.resolved .build/release/QwenNativeProbe .build/release/mlx.metallib
```

The pinned Apache-2.0 shader helper compiles the pinned MLX Metal sources; it does
not change dependency source. If Xcode reports missing Metal tools, install its
MetalToolchain component in the disposable environment and rerun. For command-line
Swift tests, copy the resulting `mlx.metallib` into the generated test bundle's
`Contents/MacOS` and `Contents/Resources` directories before scoring test results.
The helper's built-in test-bundle names differ from this probe's bundle name.

Predownload the complete chosen model revision and record every file's SHA256.
The eight-bit weights file is 1,006,229,426 bytes; four-bit is 708,236,945 bytes.
Download size is not active memory. The loader may generate a missing tokenizer
JSON inside the disposable model directory; preserve that receipt too.

```sh
.build/release/QwenNativeProbe MODEL_DIRECTORY WAV_DIRECTORY batch.jsonl MODEL_REVISION
.build/release/QwenNativeProbe --streaming MODEL_DIRECTORY WAV_DIRECTORY paced.jsonl MODEL_REVISION
.build/release/QwenNativeProbe --official-streaming MODEL_DIRECTORY WAV_DIRECTORY official.jsonl MODEL_REVISION
.build/release/QwenNativeProbe --official-streaming --official-chunk-ms=350 MODEL_DIRECTORY WAV_DIRECTORY fast.jsonl MODEL_REVISION
```

Preserve `Package.resolved`, executable/shader hashes, model file receipt, source
hashes and full JSONL outputs. The probe does not download models. Use mono WAV inputs. The pinned loader resamples to 16kHz but selects the
first channel of multichannel files; it does not downmix stereo. Decoding uses automatic language, greedy sampling and a
maximum 256 tokens. Locale/IP never overrides recognition language.

## Timing boundaries and controls

Batch mode includes complete audio decoding; its first clip can include cold work.
Cached model load and process lifetime peak RSS are separately recorded. Virtual
Metal results are not physical-device ANE performance.

`--streaming` exercises `StreamingInferenceSession.feedAudio` and `stop`, with
1,280-sample packets, `.realtime`, 0.35-second decode cadence, two cached windows
and one-second encoder overlap. Each packet arrives at its **last sample's** audio
time, including the final partial packet. `release_to_final_seconds` starts at the
nominal final-sample deadline; `feed_overrun_seconds` exposes late ingestion, and
`stop_to_final_seconds` starts at the actual `stop()` call. Top-level streaming
elapsed time includes audio playback pacing and is not compute-only RTF.
`first_partial_seconds` / `partial_count` describe raw nonempty display events,
which can include unchanged text; they are not unique revision counts.

Optional `--cpu` selects MLX CPU. `--token-stream` exercises token emission from
already-complete audio; this is not live audio streaming. `--encoder-fp32` tests
upcast encoder arithmetic and cannot restore precision lost in saved weights.
`--frontend-proof` checks incremental versus batch interior mel frames without a
model. The fork's regression suite separately covers framing boundaries and lengths.

## Official streaming policy control

`--official-streaming` is a separate research control based on
[QwenLM/Qwen3-ASR's pinned implementation](https://github.com/QwenLM/Qwen3-ASR/blob/7c6daf77a2421100f5fb066495372c00129d39ff/qwen_asr/inference/qwen3_asr.py#L584).
It consumes two-second chunks, re-encodes all audio from the utterance start, and
retains no caller-owned decoder cache between passes. The first two passes use no
text prefix. Later passes retokenize the prior raw output, roll back five tokens,
and expand that rollback until the prefix contains no Unicode replacement
character. The generated suffix replaces the previous suffix. A final short tail
includes every remaining sample without padding; matching the official source,
its rollback retains at least one token and does not repair incomplete Unicode.
Raw protocol state remains separate from display parsing.

`--official-chunk-ms=350` is an explicit cadence experiment; the default remains
2,000 ms. Accepted intervals are 80 through 30,000 ms, bounded below by the input
packet duration to avoid unsupported tiny frontend inputs. The first-two-pass
prefix rule stays unchanged, so reducing the chunk interval also reduces the
initial audio context before prefix retention. This tradeoff requires accuracy
measurement. With 80 ms packet delivery, a 350 ms chunk first becomes available
at 400 ms; the setting does not promise a 350 ms visible update.

The control uses native public model/tokenizer APIs, full-prompt retokenization
and a fresh KV cache each pass. It checks that the native prompt round-trips
through the tokenizer before extending it. This is a policy comparison, not a
claim of identical vLLM runtime: it uses greedy generation capped at 256 tokens
rather than the official vLLM default of 4,096. The official global repetition
cleaner is deliberately omitted so legitimate repeated dictation is preserved.
The official no-marker display fallback is retained for this control; it differs
from the fork's stricter unfinished-header suppression.

Packets use the same causal final-sample schedule. Decoding is synchronous, so
slow inference can delay ingestion. Compare `release_to_final_seconds` for user
latency and inspect `feed_overrun_seconds`. `stop_to_final_seconds` excludes prior
ingestion delays and can approach zero for exact chunk multiples whose last pass
finished before stop. `official_passes` records cumulative audio length, raw
prefix, generated suffix, complete raw text, token count, measured decode time,
completion time from utterance start, display text and EOS versus token-limit
termination. A nonempty display event is not automatically a correct usable prefix.
These timings describe this control implementation, not vLLM or an app provider.

The small policy proof compiles without MLX:

```sh
swiftc -parse-as-library QwenOfficialStreamingPolicy.swift QwenOfficialStreamingPolicyProof.swift -o /tmp/qwen-policy-proof
/tmp/qwen-policy-proof
```

Its 20 assertions cover cumulative sample ownership, suffix replacement, Unicode
rollback, final-tail differences and preserving repeated words. Synthetic
tokenizers establish state transitions; actual BPE and audio quality require the
native replay. The proof is not itself a known-bad model regression test.

## Physical reference evidence

The native eight-bit two-second cumulative control completed all 20 mixed-language
clips with 25/662 mixed errors (3.78%), 29/1,023 canonical character errors (2.83%),
zero empty outputs and zero token-limit hits. Median release-to-final was 176 ms,
p95 294 ms; first nonempty text arrived at median 2.20 seconds. These are model
control timings on a physical M5, not the app's end-to-end 250 ms gate. The first
clip includes cold work.

The explicit 350 ms control completed the same 20 clips with 27/662 mixed errors
(4.08%), zero empty outputs and zero token-limit hits. Median release-to-final was
173 ms, p95 268 ms; median first nonempty output was 672 ms. A stricter post-hoc
proxy found a live output matching at least three initial reference units in
18/20 clips, median 1.24 seconds. That proxy is not human usability judgment; the
remaining suffix may still be wrong. References never entered inference prompts.
These model-only timings do not pass the app's 250 ms p95 requirement.

Memory is a substantial tradeoff: the native batch allocator peak reached
1,593.68 MiB. A separate one-model resource pass over the longest warm-up clip plus
all 60 clips recorded 13 own-PID samples with zero query errors: sampled physical
footprint peaked at 1,446.06 MiB and the kernel's lifetime physical-footprint peak
at 2,120.97 MiB. GPU model allocations appear under graphics categories; zero
neural ledger tags do not mean zero model memory. Preserve these distinct counters;
resource polling results are not uncontended inference timing evidence.

## Historical evidence and remaining gates

Ignored evidence lives in `.local-build/asr-research/qwen-native/` and `qwen-header/`.
Superseded source patches and standalone length probes are archived under
`qwen-native/archived-experiments/`; none are current build instructions.

The original native four-bit 20-clip, one-speaker TaiMECS batch scored 20/662 mixed
errors (3.021%) and 25/1,023 canonical character errors (2.444%). Its larger Taiwan
control produced five empty outputs; the encoder-length fix rescued two, leaving
three. Independent official-runtime decoder-representation controls reproduced
those three with four-bit decoder weights; eight-bit restored zero empty outputs
in that control. Physical M5 native eight-bit batch now scored 21/291 canonical
character errors (7.22%), zero empty and 28 exact on the 40 Taiwan sentences;
the 20 mixed-language clips scored 24/662 mixed errors (3.63%), zero empty.
The 30 isolated English commands remained ambiguous: 19 exact, zero empty,
12/30 mixed errors (40%). Do not generalize that command set to sentence accuracy.

The earlier paced run completed 20/20 but leaked language headers in all 20 outputs.
The published parser correction passed 12 actual Foundation test bodies; native
Swift Testing and paced replay are still required. The pinned parser and probe
compiled with the complete native MLX graph on Xcode 26.3. Actual-module
frontend tests previously passed all four tests, with the known-bad short-packet
case failing as expected and mel error 2.022763 becoming 0 after correction.

Earlier paced timings used packet-start scheduling, feeding up to 80ms unavailable
future audio. Their reported 293ms median/502ms p95 finalization are exploratory;
do not use them as causal microphone-latency evidence. The current packet-end
schedule has actual-loop RED/GREEN proof: original two early packets, candidate
zero, including the last short packet. Current model-control results use the
corrected schedule; historical timings remain excluded.

Repeated suffixes remain around eight-second boundaries. Source analysis and
saved-window Foundation replay identify overlapping acoustic input and unverified
completion-text coverage; no global repeated-text filter was added. The matched
eight-bit physical replay scored 76/662 mixed errors (11.48%) with 44 insertions
for the existing windowed policy, versus 25/662 with five insertions for cumulative
two-second decoding. Both used the same corpus, model and causal packet schedule;
multiple policy details differ. Use the cumulative policy for further integration
work. Longer dictation, language constraints, shared production decoder parity and
the complete app path remain separate acceptance gates.
