# Autonomous Runtime E2E Harness

This helper drives a real Roma build through the complete macOS path:

```text
WAV fixture -> BlackHole 2ch -> Roma microphone input
timed left Shift down/up ------> Special shortcut
Roma paste --------------------> isolated real-app text field
AX text + rendered pixels -----> user-visible timestamp
LatencyTrace ------------------> app phase timestamps
```

It is external to the production app. The helper does not add test hooks to
VoiceInk or bypass CoreAudio, global shortcuts, transcription, clipboard paste,
target-app focus, Accessibility observation, or rendered-screen verification.
The report keeps Accessibility value arrival separate from first stable screen
pixels so AX state is never presented as proof that a person could already see
the text. Pixel sampling starts at key-up, independently of AX arrival, and a
render is accepted only after two baseline-different frames are also mutually
stable. AX may arrive later without moving the earlier rendered timestamp.

While routing fixture playback through BlackHole, the helper temporarily sets
Roma's recording mute to Off and restores the prior preference afterward,
including recovery from its crash journal. Otherwise automatic speaker mute
also silences the simulated microphone after key-down. Check saved recordings
for the fixture's speech throughout the hold before accepting runtime evidence;
successful playback and nonempty opening text alone do not prove audio delivery.

## Qwen finalization diagnostics

Qwen sessions attach content-free phase events to the recording's existing
`appLatencyTrace` token. The token is captured once at connect; late worker
callbacks cannot attach to a later recording. Direct runtime clients default to
no diagnostic callback. No transcript, PCM, prompt, language, or tensor data is
logged; fields contain session/decode IDs, live/final flag, sample/token counts,
fixed outcomes, and monotonic `uptime` seconds.

The `qwen_streaming.*` markers are `finishRequested`,
`cancellationRequested`, `decodeBegin`, `decodeEnd`, `decodeReceived`,
`presentationBegin`, `presentationEnd`, and `finalEmitted`. Match session and
decode IDs. `decodeBegin` is detached worker entry; `decodeEnd` follows return
or throw from the existing decoder, including its actual Metal drain. A worker
cancelled before model entry still emits a cancelled end. `decodeReceived`
marks actor resumption; cancellation requests do not prove drain completion.
`superseded` on cancellation/receipt identifies replacement intent, while the
end event independently records EOS, token limit, cancellation, or native error.
Presentation end closes the attempted presentation even on error;
`finalEmitted` occurs only after yielding a final event, including a no-audio
final that did not invoke decoding. It does not prove target-app rendering.

Compare finish-to-live-end/receipt with final-begin-to-end and final presentation
on each recording's monotonic clock. These intervals distinguish obsolete live
work from final computation; they do not isolate encoder kernels, allocator
cache clearing, or GPU-only time. No new evaluation, synchronization, cache
operation, cancellation fence, or scheduling policy is introduced. Logging has
finite overhead: retain the original failure and compare a matched build/run
before attributing differences. Actual release-to-persistent-render remains the
250ms acceptance boundary; a faster internal span alone cannot pass it.

## Default Matrix

- Audio: every supported fixture under `~/Downloads/roma jt builds/audio/`
- Audio lead: `1.1s` before left-Shift key-down
- Release: `150ms` after the fixture ends
- Repetitions: `3`
- Text baselines: empty, plus `[existing before]{cursor}[existing after]`
- Candidate apps: TextEdit, Safari, Google Chrome, Arc, Zed, and Visual Studio Code
- Local target policy: `runningOnly`; closed apps are skipped, never launched
- Coverage gate: at least `4` distinct candidate apps must already be running
- Rendered-text timeout: `20s`
- Rendered-text p95 budget: `250ms`
- Transcript answer: optional until supplied in the config

Each selected browser opens an isolated local tab with a uniquely titled,
controlled contenteditable. It accepts only paste-backed DOM `input` events,
records DOM `paste` and accepted-input counts in the report, and passes only
when exactly one of each occurred. This matches web apps that reject
Accessibility-only value mutation. When a cold browser keeps its app-menu Paste
command disabled, Roma refreshes that command by opening and closing its
containing app menu. If Paste remains unavailable, Roma asks the captured editor
(or one of its ancestors) to show its context menu through Accessibility. When
Chromium does not advertise that action, Roma right-clicks the AX-reported caret
using Chromium's selected text-marker bounds when ordinary range bounds cannot
resolve back to the captured editor, converting Chromium's AppKit screen
coordinates before AX hit-testing. It accepts only an activated menu that owns
that same system-hit-tested screen point, then presses enabled Paste and confirms
the exact replacement before reporting delivery. Browser fallbacks stay bound to that
editor's unchanged text and selection; drift aborts without a recaptured,
keyboard-triggered, or Cmd-V CGEvent paste.
Document and
Electron editor apps open a uniquely named temporary text file. Every target
runs once empty and once with text on both sides of the insertion cursor.
Cleanup saves an empty temporary document before closing its tab/window, removes
the resource, terminates only a target process started by the harness, restores
an initially running target if closing its last isolated surface exits it, and
restores the previously frontmost app. Existing documents and pages are not used
as test targets.

Electron existing-text fixtures position the caret with actual Command-Left and
Right-arrow events before recording. VS Code can accept an AX selected-range
write and report offset `17` while the editor still inserts at offset `0`.
The helper therefore checks the original focused editor and unchanged fixture
text before each PID-targeted key, then checks range, focus, and text again.
This preparation never inserts a marker, changes the final transcript, or
repairs the cursor after dictation.

For a cursor-preparation regression, use the same isolated one-line fixture and
frozen diagnostic on both helper versions. After preparation, type one unique
ASCII marker with a real keyboard event, read its position in the complete
document, and Undo back to the exact original text. Compare that with explicit
keyboard positioning at `17` and an offset-`0` negative control on the same
restored text. Require trusted, active, uniquely owned window/editor identity,
all marker/Undo observations, and cleanup in every repetition. An AX readback
alone cannot pass this regression. The known-bad `563f3486` helper reproduced an
AX-`17`/actual-`0` disagreement in a valid four-repetition control; the candidate
must put every prepared marker at `17` while preserving the negative control.
Capture-permission interruptions invalidate the attempt and remain separate
from the consent-cleared evidence. This control does not replace the full Roma
runtime matrix or change the rendered `250ms` gate.

Set `targetAvailabilityPolicy` to `launchIfNeeded` only on a dedicated test Mac.
The local default remains `runningOnly` to avoid memory pressure and surprise app
launches. `minimumTargetCount` controls the distinct-app coverage gate.

Runtime execution for this project is Namespace-first. Local commands below are
opt-in tools for a dedicated test Mac; CI/static checks never launch Roma or
change the frontmost application.

## Calibrate the visibility observer

Reports include `visibleText.observationTimings`: each sampling iteration's
start offset, screenshot capture/conversion duration, AX text-read duration,
DOM paste-proof traversal duration, and target-refresh traversal duration.
Skipped operations omit their duration field; aggregate only observed values.
The final browser receipt is a separate timing entry with no AX-read fields.
Paste/input counts accumulate in the controlled page, so receipt inspection runs
after pixel sampling. Valid pre-insertion AX values retain the prepared element;
failed reads trigger rediscovery immediately, with periodic rediscovery while
waiting for insertion to recover detached elements that retain cached values.
These diagnose observer overhead; none is subtracted from the rendered latency
or changes the `250ms` gate.

To isolate the observer from audio and ASR, build the helper and run this on the
disposable test Mac after granting its Accessibility and Screen Recording access:

```sh
open -W -n -o /tmp/visibility-calibration.stdout \
  --stderr /tmp/visibility-calibration.stderr \
  /absolute/path/RuntimeE2EHarness.app --args \
  --visibility-calibration --config /absolute/path/runtime-config.json \
  --json-output /tmp/visibility-calibration.json
```

Interrupted calibration targets use the same target/scenario/repetition naming
contract as runtime cases, so the next harness run can safely recover their
isolated surfaces and temporary files.

This command uses each configured target, empty and existing-text scenarios,
and the same preparation, pixel observer, text reader, and cleanup as runtime
E2E. It posts one controlled Cmd-V after a `200ms` scheduling delay, checks the
exact inserted text and browser DOM paste proof, and restores the clipboard.
`pasteToRenderedMilliseconds` measures from the recorded paste dispatch to the
first persistent rendered change. Nested observation fields retain their runtime
names, but their `keyUp` origin is this calibration's start, not a Roma shortcut.
The command does not launch Roma, load a model, or establish product latency.

Launch through `open`, as above, so capture permission belongs to the helper.
After rebuilding an ad-hoc signed test helper, refresh its exact designated
requirement grants and TCC caches using the disposable runtime setup procedure.
Restart test targets if they retain stale AX authorization, then keep the helper
binary unchanged through preflight and scored controls. `open -W` waits for the
app but does not forward its exit status; inspect the JSON case errors and
cleanup results. A direct CLI or launchd job exposes the helper exit code.
On macOS 26, complete the additional private-window-picker consent before
scoring. Dismiss first-run browser dialogs too. A setup dialog over the editor
invalidates pixel evidence even when TCC reports access granted. Preserve a
clean baseline screenshot when investigating a new capture method; a blank
or blocked capture is not a speed result.

## Autonomous Namespace Run

For a fast hypothesis check, use the same inputs below with
`macos_scenario=runtime-smoke`. When `macos_audio_artifact` is blank, it pulls a
pinned 5.64-second English FLEURS fixture through Namespace's URL cache and
verifies its SHA-256. The fixture comes from the CC-BY-4.0
[`podscripter-project/test-fixtures`](https://huggingface.co/datasets/podscripter-project/test-fixtures)
dataset and was sourced there from the English FLEURS test set. Smoke then uses
TextEdit, Safari, normally one repetition, and a three-second target-text timeout. An
empty-final regression run instead uses the selected `macos_repetitions`. It
skips Chrome and VS Code installation and the repeated matrix. This is an early
rejection lane, not final runtime proof.

Fixture attribution: `fleurs_en_test_3529855487992513201.wav` comes from
FLEURS by Conneau et al. ([paper](https://arxiv.org/abs/2205.12446)) and is
licensed [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/). The
podscripter fixture project extracted it from the English test archive and
re-encoded it as 16 kHz mono signed-16-bit WAV without trimming. This workflow
downloads that pinned file unchanged.

Run `Prepare remote E2E stage` with:

- `target=macos`
- `macos_scenario=runtime-e2e`
- `macos_artifact_run_id=<exact green app build>`
- `macos_audio_artifact=<private Namespace ZIP containing WAV fixtures>`
- `macos_repetitions=3`
- `hold_minutes=0`

The disposable Namespace Mac installs BlackHole, Chrome, and Visual Studio Code;
opens TextEdit, Safari, Chrome, and VS Code; and keeps the harness policy at
`runningOnly`. It grants Accessibility/Input Monitoring/Microphone only inside
that ephemeral VM. The helper also receives Screen Recording solely for
pixel-level target observation. Grants remain keyed to the exact ad-hoc CDHashes
of the downloaded Roma app and the one-time-built helper. It never re-signs the
production Roma artifact.

Before sampling, the scenario mounts a persistent cache at
`~/Library/Caches/roma-runtime-e2e-models`. It exposes only the pinned model's
child directory to FluidAudio through a symlink when runtime preparation starts.
The distribution lane therefore keeps `~/Library/Application Support/FluidAudio/Models`
absent through the fresh download, Finder, Gatekeeper, and initial App
Translocation launch. The cache is an opportunistic fast path. The runner validates all 22
Parakeet V2 files against a size and SHA-256 manifest pinned to one public model
revision. It fetches missing or corrupt files through Namespace's immutable-URL
artifact cache with four workers, largest files first, while dependency
installation and helper compilation run. App
prewarm then proves FluidAudio can load those exact files. It then runs
deterministic checks, a two-app target probe and four-case smoke using one short
fixture, and the requested repeated four-app matrix with the `250ms` budget. A
smoke failure is retained but does not suppress the repeated matrix in
`runtime-e2e`. All JSON reports, phase stdout/stderr, TCC rows, signatures,
hashes, model/audio provenance, model source and preparation timing, the actual
post-prewarm 22-file hash receipt, app logs, and restoration results are uploaded
as `remote-e2e-stage-evidence` even when a phase fails.
The cache-owning stage treats the scenario command as a recorded outcome so the
Namespace cache post-save still runs after a rejected hypothesis. A dependent
verdict job converts that recorded outcome back into the workflow's final
red/green result.

For a matched fresh-process empty-final regression, run the historical affected artifact
with `macos_scenario=distribution-e2e`,
`macos_empty_final_expectation=known-bad`, and `macos_repetitions=5`. Repeat the
same path with the candidate artifact, `macos_empty_final_expectation=fixed`,
and `macos_empty_final_baseline_run_id` set to the successful known-bad stage
run. The fixed lane downloads that immutable evidence artifact, reverifies its
GitHub digest and known-bad report, and requires the two generated evidence
contracts to match. The stage also requires the same runner profile. It rejects
a baseline whose app run, artifact ID, digest, source SHA, or executable hash
matches the candidate. The contract binds the tooling
SHA, macOS version/build/architecture, helper hash, selected audio hash and
duration, model revision/manifest, translocation mode, targets, timing,
lifecycle, and repetitions. It excludes volatile app, build, and audio
directory paths. The audio bytes remain bound by hash; only the app artifact is
intended to differ.
The first run accepts only a non-empty live partial plus a zero-character final
ASR followed by an empty commit in the same trace. The partial event may be
logged later because its observer crosses an actor boundary. Every red failure
must have that exact symptom on a configured target listed by preflight. The
verifier derives every exact affected `target` + `textScenario` pair from this
report instead of assuming which target or scenario will expose the intermittent
ASR result. The second run reverifies that baseline report and accepts only an
all-green report. For every affected baseline pair, at least one case on that
exact target and text scenario must show zero-character final ASR followed by
`fluid_streaming.commit.fallback_to_hypothesis`, a non-empty first commit, and
non-empty visible text, in that order. A normal non-empty final ASR is allowed
in other passing cases. A run missing any matched fallback case is rejected as
unproven. These expectation modes reject external or symlinked model storage. They
hydrate the normal FluidAudio Application Support directory, stop the prewarm
process before preflight, require the report to begin with no Roma process, and
relaunch Roma before every case. The verifier consumes the launch and normal
termination event files. It requires 20 unique launch PIDs, one for every smoke
case, and the same 20 PIDs in the termination file. The matrix contains five
repetitions of each TextEdit/Safari empty/existing-text condition. Each gets a
fresh streaming provider and `AsrManager` after the normal app-level model
prewarm. This is not an uncached
model-load claim. The matched inputs are recorded in
`empty-final-e2e-contract.json`.

## Isolation Gates

Run target automation without Roma, audio, or shortcut input first:

```bash
make runtime-e2e-target-probe
```

This proves only test-tab/document discovery, focus, empty and middle-cursor AX
baselines, scoped close, and cleanup. A target-probe failure is not reported as a Roma failure.
The separate `--audio-probe` mode validates fixture decoding, transactional
BlackHole control setup, Roma device selection, and playback-process completion.
It does not prove that non-silent PCM reached Roma. Only a full case with Roma
capture/transcription trace evidence and target text proves the complete route.

## What Fails a Case

- Target app missing, not activated, unreadable through AX, or not cleared
- Existing text on either side of the insertion cursor is changed or lost
- WAV cannot play into BlackHole
- Synthetic Special left Shift is not accepted by VoiceInk
- Posted Shift hold and VoiceInk-observed hold differ by more than `150ms`
- No new `LatencyTrace` is emitted
- VoiceInk starts a trace but never completes transcription
- VoiceInk completes transcription with zero characters (`emptyTranscript`)
- VoiceInk posts no text into the target
- Clipboard changes but the target remains empty (`clipboardOnly`)
- Accessibility text arrives but stable changed pixels never render
- Rendered text exceeds the latency budget
- Expected transcript exceeds the configured word-error-rate limit
- Target tab/document or temporary resources cannot be restored

The report preserves each failure instead of dropping it from percentile
calculations. Per-app and overall summaries include total, passed, failed,
no-visible-paste count, p50, p95, and maximum visible-text latency.

An unanswered or denied microphone request is attributed to
`voiceInkMicrophonePermission`, before transcription classification. An empty
transcription is attributed to `voiceInkTranscription`, even if VoiceInk
subsequently writes or posts whitespace. It is never counted as a clipboard,
paste-delivery, or target-visibility failure.

Each case also records factual checkpoints: target prepared, audio started,
shortcut down/up posted, Roma trigger observed, app-observed shortcut hold matched,
transcription completed,
clipboard write succeeded, paste event posted, AX text observed, stable rendered
pixels observed, and target cleanup passed. `failureBoundary` names the first
unproven boundary; it does not guess which component owns the failure.

`shortcutDelivery` means the helper's posted hold and Roma's trace disagree. It
does not assume whether the synthetic injector, macOS delivery, competing input,
or Roma's monitor caused the mismatch.

Latency is split into:

- `voiceInkKeyUpToPasteEventMilliseconds`: Roma trace from shortcut key-up handler
  to paste-event post
- `visibleText.keyUpToAccessibilityTextMilliseconds`: first non-empty AX value;
  useful for paste delivery, but not proof of rendered visibility
- `visibleText.keyUpToVisibleMilliseconds`: first two stable changed pixel frames
  in the exact editable screen rectangle
- `pasteEventToVisibleMilliseconds`: remaining time from Roma's post until the
  rendered-pixel observation
- `voiceInkKeyUpToPipelineCompleteMilliseconds`: Roma post-processing and save
  completion
- `voiceInkKeyUpToInteractionSettledMilliseconds`: final recorder toggle return,
  matching the longer endpoint a human may perceive

The rendered span intentionally remains an end-to-end delivery/visibility
boundary. It includes target rendering and any occlusion inside the sampled
rectangle; the harness does not assign it to Roma, the target app, focus, or
scheduling without further evidence.

For FluidAudio streaming diagnostics, `fluid_streaming.live_transcribe_await`
and `fluid_streaming.final_transcribe_await` bound Roma's respective awaits of
the ASR manager. Their events retain the trace token and record call timing,
sample counts, cancellation state, and final-call scheduling context.
`livePassInFlightAtCommit`,
`liveManagerCallInFlightAtCommit`, and
`liveManagerCallInFlightAtFinalStart` are lock-consistent provider snapshots:
the latter is narrower and brackets the live task's ASR-manager await. They do
not establish Core ML, CPU, GPU, or Neural Engine occupancy.

## Safety and Restoration

Before a run, the helper records:

- VoiceInk microphone mode and selected-device UID
- exact running VoiceInk bundle paths
- system default output-device UID
- BlackHole input/output mute and volume controls when supported

It then selects BlackHole for both sides, unmutes both scopes, normalizes
supported volumes for playback, and launches the exact selected Roma artifact.
On completion or handled failure it restores the original preferences, output
device, BlackHole controls, and running state. It also scans
`/tmp/roma-runtime-e2e-targets` for abandoned test tabs/documents before a run.
Journals under `/tmp/` allow recovery after an interrupted process:

```bash
make runtime-e2e-restore
```

The exact Roma app is selected in this order:

1. `voiceInkAppPath` from config
2. a running app inside the configured build directory
3. the newest matching `.app` directly under `~/Downloads/roma jt builds/`
4. another running matching app
5. the LaunchServices-installed matching app

## Build and Permissions

Build the helper only after code changes are finished:

```bash
make runtime-e2e-app
```

Grant `.local-build/Tools/RuntimeE2EHarness.app` in:

`System Settings -> Privacy & Security -> Accessibility`

`System Settings -> Privacy & Security -> Screen Recording`

Do not rebuild or re-sign afterward. `runtime-e2e-run` intentionally has no
dependency on the build/app targets so the TCC identity remains stable.

Verify readiness:

```bash
make runtime-e2e-preflight
```

Preflight reports selected and skipped target IDs and fails unless macOS 14+,
Accessibility, Screen Recording, fixtures, BlackHole, the exact Roma build, and the
four-running-app gate are all ready. On Sonoma it uses ScreenCaptureKit's macOS 14
content-filter screenshot API for the same rendered-pixel check. The explicit preflight command requests any
missing Accessibility or Screen Recording grant; normal run mode never prompts.

Remote stages use the helper artifact produced by `voiceink-build.yml`. The
target Mac first runs the packaged helper executable with `--help` and records
its process exit. A 14.0 plist value or Mach-O minimum alone does
not count as Sonoma compatibility proof.

## Run

Default full matrix:

```bash
make runtime-e2e-run
```

The default case count is `fixtures x currently-running selected apps x 2 text baselines x 3`; the
four-app minimum is enforced before Roma or audio state changes.

Browser preparation and observation require the fixture editor's unique accessible
label; a matching window title alone can expose only the address bar while the
page loads. Document cleanup handles the standard save sheet after closing the
uniquely identified temporary document, including VS Code's initially empty files.
Check each case's cleanup evidence separately from insertion and latency.

Custom manifest:

```bash
cp Tools/RuntimeE2EHarness/runtime-e2e.example.json /tmp/roma-runtime-e2e.json
make runtime-e2e-run RUNTIME_E2E_CONFIG=/tmp/roma-runtime-e2e.json
```

Add fixture answers by filename:

```json
{
  "expectedTranscripts": {
    "normal noisy clear.wav": "the correct words",
    "normal wispering.wav": "the correct whispered words"
  }
}
```

Use the complete example manifest rather than a partial JSON object; all fields
are explicit so experiment changes remain reviewable.

The default report is written to:

`.local-build/Tools/runtime-e2e-report.json`

## CI Boundary

`make runtime-e2e-check` runs deterministic public-interface checks, compiles the
helper, and verifies that preflight, target-probe, and run targets cannot rebuild,
delete, or re-sign the TCC app. Real GUI/audio sampling runs only in the logged-in
Namespace macOS scenario unless a person explicitly opts into a dedicated local
test Mac.
