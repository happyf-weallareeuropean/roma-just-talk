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
no ambient credentials or global model cache. The staging directory receives
at most two concurrent file downloads from the pinned manifest. Hugging Face Swift
0.10.0's snapshot API requires a cache after completing destination-only downloads;
the installer uses its single-file API so a complete transfer can be verified and
published without a second cache. The staging directory receives
bounded-memory checksum checks and the exact bundled tokenizer before atomic
installation. Cancellation and deletion await the actual download task. Partial
installs do not count as ready. Cached `prewarm` validates all hashes and loads
only the local directory; it does not generate tokens or send synthetic text.
Loaded-model prewarming does not establish warm first-inference latency.

Both batch and streaming call the same raw greedy decoder. Streaming consumes
350 ms packets against cumulative utterance audio, resetting the prefix for two
passes and then rolling back five tokens, matching the qualified control.
The model recomputes the cumulative encoder input; this is not encoder KV caching.
Manual release supersedes an unfinished live pass. Its child task cooperatively
cancels and drains before one final pass uses all captured PCM and the last
completed raw prefix. A canceled pass contributes no hypothesis; a completed EOS
can still update the prefix. Even when that live pass consumed the last full
packet, its accumulated PCM receives final inference. No audio is discarded.
The final pass cannot be superseded by another finish call. The runtime emits one
final result, without intermediate post-release updates. This scheduling rule
belongs to Roma; tokenizer, model math and official prefix rollback stay unchanged.
EOS, token exhaustion and cancellation remain distinct. A reached 256-token cap
remains an explicit error even if release concurrently cancels the child task.
User cancellation and teardown remain terminal and await the actual drain; finish
installs its cancellation handler before suspending and never initiates model load.
No repetition filter silently truncates speech.
Raw tokens remain unchanged. Complete display/final text converts Simplified
Chinese to Traditional Chinese through Foundation. Explicit language choice is
preserved; nil requests detection.

Unload/delete await inference and synchronize its actual Metal stream before
releasing the model or files. Recording startup retains audio in the app until
the verified model session is connected. Session IDs prevent stale disconnects
from cancelling a newer recording.

Decoding reuses MLX's default GPU stream instead of creating a stream for every
live pass. In the pinned MLX implementation, creating a stream adds a command
queue retained beyond the stream scope. Each runtime retains separate model and
cache state and grants one operation at a time; evaluation and final stream
synchronization use MLX's evaluation lock. Other MLX consumers can share the
default stream, so this does not promise exclusive GPU scheduling. The separate
model-load stream still drains before its model is published. Cancellation,
errors and successful decoding all synchronize before releasing model ownership.
Matched native stream controls retained all 11 final transcripts and full audio
coverage; alternating focused runs confirmed lower completion latency. These are
runtime controls, not the app's 250 ms release gate or encoder caching.

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

Package test command after the Release app build (Xcode 26 / Swift 6.2.1 or newer):

```sh
bash scripts/test-qwen-package.sh "$HOME/Applications/roma just talk.app"
```

Tests do not load model weights or run inference. Unload/delete tests initialize
MLX's Metal device when clearing its cache. The script checks resolved revisions
against the preceding app build, builds the test executable, and supplies that
app's shader through MLX's supported executable-adjacent lookup before running
the complete suite. It never changes the app. The application gate separately
verifies shipped shaders and inference.
