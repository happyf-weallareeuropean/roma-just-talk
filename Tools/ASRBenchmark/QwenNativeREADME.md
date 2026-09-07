# Native Qwen parity probe

Research only; no model catalog, onboarding default, or app dependency changes.
Native bilingual acceptance remains pending. Use a disposable Apple Silicon Mac
with full Xcode and Metal tools. Keep model downloads and inference there.

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
The current parser pin has passed Foundation tests; full native replay remains due.

Stage this directory's `QwenNativePackage.swift` as `/tmp/roma-qwen-native/Package.swift`
and `QwenNativeProbe.swift` as `/tmp/roma-qwen-native/Sources/Probe.swift`. Then:

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

## Historical evidence and remaining gates

Ignored evidence lives in `.local-build/asr-research/qwen-native/` and `qwen-header/`.
Superseded source patches and standalone length probes are archived under
`qwen-native/archived-experiments/`; none are current build instructions.

The original native four-bit 20-clip, one-speaker TaiMECS batch scored 20/662 mixed
errors (3.021%) and 25/1,023 canonical character errors (2.444%). Its larger Taiwan
control produced five empty outputs; the encoder-length fix rescued two, leaving
three. Independent official-runtime decoder-representation controls reproduced
those three with four-bit decoder weights; eight-bit restored zero empty outputs
in that control. Native eight-bit inference remains a separate gate.

The earlier paced run completed 20/20 but leaked language headers in all 20 outputs.
The published parser correction passed 12 actual Foundation test bodies; native
Swift Testing, MLX compilation and paced replay are still required. Actual-module
frontend tests previously passed all four tests, with the known-bad short-packet
case failing as expected and mel error 2.022763 becoming 0 after correction.

Earlier paced timings used packet-start scheduling, feeding up to 80ms unavailable
future audio. Their reported 293ms median/502ms p95 finalization are exploratory;
do not use them as causal microphone-latency evidence. The current packet-end
schedule has actual-loop RED/GREEN proof: original two early packets, candidate
zero, including the last short packet. No corrected native latency is claimed yet.

Repeated suffixes remain around eight-second boundaries. Source analysis and
saved-window Foundation replay identify overlapping acoustic input and unverified
completion-text coverage; no global repeated-text filter was added. Native parser
replay, fresh completed-window decoding control and independent overlap ownership
controls remain required before real app integration or onboarding exposure.
