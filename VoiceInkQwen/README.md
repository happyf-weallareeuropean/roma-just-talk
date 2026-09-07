# Local bilingual Qwen runtime

Roma's macOS adapter uses one serialized Qwen owner for recording and file
transcription. The application gates use to Apple silicon and macOS 15 or later.
The package is linked only into the macOS application; FluidAudio stays unchanged.

Pinned sources and model:

- MLX Audio Swift fork `ad2f08874165b054b3d3647003159858e1047bed`, based on
  upstream `bf14ae0c26e4e85553dd989571cae29d70fa6735`.
  Maintained frontend length/frame corrections and public transcription parser.
- MLX Swift 0.31.4, MLX LM 3.31.4, Hugging Face Swift 0.10.0.
- `mlx-community/Qwen3-ASR-0.6B-8bit`, revision
  `89e96d92ba34aca20b3e29fb10cc284097d1219f`.
- Official prefix policy adapted from QwenLM/Qwen3-ASR
  `7c6daf77a2421100f5fb066495372c00129d39ff` (Apache-2.0).

`Resources/snapshot.json` pins every installed file, byte size and SHA256.
Only `install` performs network access: immutable revision, explicit whitelist,
no ambient credentials or global model cache. A sibling staging directory receives
bounded-memory checksum checks and the exact bundled tokenizer before atomic
installation. Cancellation and deletion await the actual download task. Partial
installs do not count as ready. Cached `prewarm` validates all hashes and loads
only the local directory; it does not generate tokens or send synthetic text.
Loaded-model prewarming does not establish warm first-inference latency.

Both batch and streaming call the same raw greedy decoder. Streaming consumes
350 ms packets against cumulative utterance audio, resetting the prefix for two
passes and then rolling back five tokens, matching the qualified control.
The model recomputes the cumulative encoder input; this is not encoder KV caching.
Manual release takes precedence over the live-update cadence: after any in-flight
decode drains and updates the raw prefix, all queued PCM joins one cumulative
final pass. No queued audio is discarded or split into additional live passes.
The runtime emits one final result, without intermediate post-release updates.
This scheduling rule belongs to Roma; the pinned tokenizer, greedy decoder and
official prefix rollback policy remain unchanged.
EOS, token exhaustion and cancellation remain distinct. The 256-token generation
cap produces an explicit error; no repetition filter silently truncates speech.
Raw tokens remain unchanged. Complete display/final text converts Simplified
Chinese to Traditional Chinese through Foundation. Explicit language choice is
preserved; nil requests detection.

Unload/delete await inference and synchronize its actual Metal stream before
releasing the model or files. Recording startup retains audio in the app until
the verified model session is connected. Session IDs prevent stale disconnects
from cancelling a newer recording.

The exact bundled tokenizer was used for native eight-bit controls. First cached
load cannot regenerate it. Tests compare all vocabulary IDs, ordered merges and
special-token semantics with pinned inputs; compact fixture hashes use UTF-8
lengths and token IDs encoded as eight-byte big-endian integers. Resources include
MIT notices for the MLX components and Apache-2.0 model/policy derivation notices.
No model weights are bundled. See `Resources/NOTICE.txt`.

Xcode builds the MLX 0.31.4 package shaders. Its C++ loader searches the application
and resource bundles for `mlx-swift_Cmlx.bundle/default.metallib` (including the
macOS `Contents/Resources` layout). The macOS project checks that this shader
exists in the built app. A CLI-adjacent `mlx.metallib` alone is not app proof.

Current human controls: eight-bit batch had zero empty outputs on CV40 and
TaiMECS20. The qualified 350 ms streaming control scored 27/662 mixed units
(4.08%), zero empty/capped outputs, and model-only final median 172.6 ms / p95
267.7 ms. These are not app end-to-end latency claims. Measured peak MLX allocation
was 1593.68 MiB and process lifetime peak RSS 2120.97 MiB: a substantial memory
tradeoff. First cold partial reached 2.196 s; warmed median was 672 ms.

Integration acceptance still requires the actual shared-helper executable replay,
package tests, full app dependency/build gates, offline installed-store use,
model switch/delete during inference and cold/warm app recording tests. Earlier
standalone controls do not substitute for these gates.

Package test command (Xcode 26.3 / Swift 6.2.1 or newer):

```sh
swift test --package-path VoiceInkQwen -c release --enable-testable-imports
```

Tests do not load model weights or run Metal inference; compilation still builds
MLX dependencies. The application gate separately verifies shipped shaders.
