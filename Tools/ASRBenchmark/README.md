# Roma ASR research probe

Isolated model diagnostics, not a Roma application or release test. Audio and
transcripts stay outside Git. There is no ground-truth inference or accuracy
score: a model's transcript cannot serve as another model's reference.

## Reproduce on a disposable Apple Silicon Mac

1. Create an isolated Python environment. The initial run used Python 3.14.3,
   sherpa-onnx 1.13.7, numpy, psutil, and huggingface-hub. Preserve the complete
   installed package list with each run.
2. Download only the selected pinned variants:

   ```sh
   python download_models.py xasr models
   python download_models.py sensevoice models
   python download_models.py parakeet models
   python download_models.py qwen models
   python download_models.py breeze models
   ```

3. For Core ML, clone FluidAudio at
   `5c19d5e12320e22bbfb7a1877b089d2665a69add` into a disposable directory, then
   `python install_probe.py /path/to/FluidAudio`. This changes only that clone's
   package manifest. Build with
   `swift build -c release --product RomaASRBenchmark` from the clone.
4. Provide a directory of mono, 16 kHz, signed PCM16 WAVs. Run models sequentially
   on an otherwise idle host. Each output directory must be new:

   ```sh
   python supervise.py results/xasr160 -- python xasr_probe.py models/xasr audio --tier 160 --tail-ms 500 --paced
   python supervise.py --footprint results/sensevoice -- /path/to/RomaASRBenchmark sensevoice models/sensevoice audio
   python supervise.py --footprint results/parakeet -- /path/to/RomaASRBenchmark parakeet models/parakeet-tdt-0.6b-v2-coreml audio
   ```

   Repeat X-ASR with 480 ms, with `--tail-ms 0`, and without `--paced`.
   Parakeet's canonical directory name is mandatory: FluidAudio resolves that
   sibling even when a different leaf name is passed. Avoid fallback downloads
   by verifying the pinned local files first.

5. For the whole-file accuracy controls, install `qwen-asr`, `transformers`,
   `torch`, and `accelerate` in the isolated environment; preserve `pip freeze`.
   Run after downloads/installations have finished:

   ```sh
   python supervise.py results/qwen -- python quality_probe.py qwen models/qwen audio
   python supervise.py results/breeze -- python quality_probe.py breeze models/breeze audio
   ```

   These use CPU FP32, two Torch threads, automatic language detection, no
   contextual prompt, and a 256-token output cap. Inspect truncation on longer
   inputs. The initial corpus contains only clips shorter than 15 seconds;
   this is not a validated long-audio harness. There is one pass, including
   first-inference overhead. Their latency is not an optimized Apple-port claim.

## Meaning of measurements

- X-ASR receives 80 ms PCM packets. Paced runs deliver each packet only after
  its samples would exist in real time. The model tier is separate from packet
  size. Automatic endpoint detection is disabled: end of file simulates manual
  release. Report any pending decoding backlog separately from final draining.
- The explicitly selected 0/500/1500 ms synthetic tail is submitted during final
  draining, without sleeping for its duration. It measures a manual flush
  strategy, not an automatic silence endpoint. Compare outputs across tails.
- First partial is timed from **clip start**, not speech onset; these recordings
  can contain pre-roll. Unpaced first-partial values are compute diagnostics,
  not interaction latency. Native Core ML probe is whole-file batch inference;
  it has no partial/endpoint latency result.
- `partial_events` and `retracted_characters` cover decoding before final
  draining, including last-packet work that can finish after manual release.
  For live-only partials, retain events at or before the clip's audio duration
  in paced runs. Final draining may extend or change the text; compare final
  `text` separately. A clip can have a final answer but no live partial.
- Core ML emits three repetitions in one loaded process. The first inference
  includes any first-prediction work; later repetitions are warm. Model loading
  excludes downloading. This does not reproduce Roma's agreement buffer, VAD,
  text normalization, shortcut timing, or insertion pipeline.
- CPU seconds are process CPU time. Sampled RSS and OS footprint are different
  memory measures; neither is active wired neural RAM. `ru_maxrss` is lifetime
  peak RSS and is bytes on macOS. The Python probe is intended for macOS only.
- `supervise.py` samples child RSS every 20 ms. This can miss shorter peaks.
  Optional footprint snapshots run at Core ML baseline/loaded/idle pauses;
  their overhead and asynchronous completion must be considered. No active
  neural-memory, reclaimability, GPU/ANE utilization, or power measurement is
  inferred from these snapshots.
- The research VM exposed CPU and Apple Paravirtual GPU, **no ANE**. A successful
  `.cpuAndNeuralEngine` model request is not evidence of ANE execution. Measure
  the user's ~470 MiB neural baseline and candidate on the same physical Mac
  before making that comparison.

## Interpretation limits

Inspect raw outputs and errors, then obtain human references before CER/WER.
Keep raw Traditional output, script-normalized recognition, embedded English
term accuracy, and formatting/grammar edits separate. Run silence/noise controls
and real subsecond speech before judging hallucination or short-word reliability.
Do not publish private WAVs, filenames, or transcripts in research commits.
