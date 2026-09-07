# Production Qwen runtime probe

This probe calls `QwenRuntime` directly: snapshot verification/load, streaming session, every audio append, display events, real finish, and unload. It does not invoke or reproduce the decoder. Native build and model replay are pending; previous research-loop timings do not establish this runtime's latency.

Stage `QwenRuntimePackage.swift` as `Package.swift`, `QwenRuntimeProbe.swift` as `Sources/Probe.swift`, and the complete `VoiceInkQwen`, `VoiceInkCore`, `VoiceInkNVIDIA` packages as sibling directories in that package root. Build with Swift 6.2.1 or newer and the repository's pinned dependencies. Save the executable, the built MLX `mlx.metallib` beside it, all generated SwiftPM resource bundles (including `VoiceInkQwen_VoiceInkQwen.bundle`), package lockfile, source hashes, full build log, and compiler version. Preserve the bundles beside the relocated executable; `QwenRuntime.init` reads its snapshot through `Bundle.module` even when model files are cached. Verify the relocated checkpoint with its original build directory unavailable before calling it portable. Run actual `VoiceInkQwen` tests separately; compiling this executable is not a package-test result. Follow the Metal artifact build recipe in `QwenNativeREADME.md`.

Prepare fixtures/cache without downloads (destination must not exist; hard links require the same filesystem):

```sh
python3 Tools/ASRBenchmark/QwenRuntimeFixtures.py \
  .local-build/asr-research/app-fixtures /tmp/roma-qwen-models/8bit \
  VoiceInkQwen/Sources/VoiceInkQwen/Resources /tmp/roma-qwen-runtime-case-run
/path/to/QwenRuntimeProbe /tmp/roma-qwen-runtime-case-run/cache \
  /tmp/roma-qwen-runtime-case-run/cases.json /tmp/roma-qwen-runtime-case-run/results.jsonl
```

The public fixture manifest supplies independent human references and pinned audio checksums. References never enter inference. Model files are verified before hard linking; the real runtime also verifies its complete pinned snapshot on load. Keep the hard-linked cache read-only during the run: deleting/replacing the link is safe, changing linked file bytes also changes the original cache.

Key-down is time zero, before session startup. Three seconds of preceding silence or leading fixture speech are already available then and use the actual production 100ms pre-roll chunks. Subsequent audio becomes available at each packet's **end**, with separate append-start/return timestamps recording delivery delay. Eighty-millisecond and uneven live packet patterns are explicit controlled inputs, not measured microphone callback shapes. Speech-prefix cases include those words in the reference exactly once. The short speech-prefix case pads the earlier pre-roll with silence and releases after 350ms of live silence.

Model-unloaded first use, warm controls, queued initial audio, delayed final audio, and a stitched three-repeat recording are distinct diagnostics. Repetitions retain the repeated reference words. Synthetic backlog cases do not estimate normal-user frequency. Never combine this small heterogeneous matrix into a production acceptance p95.

Each result records all packet boundaries and actual event timestamps. Derive release-to-final-event from `finalEventSeconds - nominalReleaseSeconds`, feed delay from `finishStartedSeconds - nominalReleaseSeconds`, and finish duration from `finishReturnedSeconds - finishStartedSeconds`. The declared release is the end of live audio; it excludes pre-key-down audio. Compare actual final text against independent references, and verify complete packet coverage before interpreting latency. Timed events buffer in memory; JSON output is written after each case. External own-PID memory profiling should be a separate resource pass.

This boundary excludes microphone capture, physical key handling, application selection/relay wiring, insertion, and UI observation. The real app release gate remains separate. Repeat matched cases after any optimization; preserve all PCM, legitimate repetitions, and raw decoder prefix ownership.
