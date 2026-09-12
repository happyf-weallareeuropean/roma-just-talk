# Remote E2E Stage

This workflow prepares the remote computer. Manual interaction remains the
default. The macOS distribution scenario preserves the downloaded artifact's
security state. Deterministic macOS smoke, full runtime, and iOS local-Whisper
scenarios can run before the optional hold.

The intended split:

1. Existing CI workflows produce reusable application artifacts.
2. Namespace downloads those artifacts and prepares a live macOS desktop.
3. A scripted scenario or a person controls the real desktop applications.
4. The stage uploads reports, screenshots, and logs after the scenario/hold.

## Start the stage

Run the `Prepare remote E2E stage` workflow manually.

Inputs:

- `target`: `macos`, `ios`, or `both`.
- `macos_artifact_run_id`: successful `Build roma just talk` workflow run containing the exact macOS artifact to exercise. Blank requires a green build from the stage tooling's exact source SHA.
- `runtime_helper_run_id`: optional build run containing the current Sonoma-compatible runtime helper. Whether selected or discovered, the helper must come from the stage tooling's exact source SHA, so a historical app artifact can use the current trusted test oracle.
- `macos_runner`: GitHub runner label backed by the requested macOS image. Use a separate pinned label for each OS lane.
- `macos_expected_version`: exact `sw_vers -productVersion` required by the test. Blank records but does not enforce the version.
- `macos_expected_build`: exact `sw_vers -buildVersion` required by `distribution-e2e`.
- `macos_distribution_expectation`: `fixed` for a general responsive-first-launch proof, `known-bad-framework-signature` to reproduce a historical framework-signature failure, or `fixed-after-framework-signature` to require a matched historical reproduction before testing the candidate.
- `macos_expected_rejected_framework`: `whisper` or `MediaRemoteAdapter`, required by the known-bad framework-signature mode and ignored by the fixed mode.
- `macos_expected_main_uuid` and `macos_expected_rejected_framework_uuid`: required canonical UUIDs from the historical crash in known-bad framework-signature mode. The runner independently reads the matching arm64 UUIDs from the downloaded app and framework before launch.
- `macos_framework_signature_baseline_run_id`: required by `fixed-after-framework-signature`. It names a successful known-bad remote-stage run produced from the same tooling SHA.
- `developer_dir`: optional Xcode app developer directory for that runner. Blank uses the runner's selected compatible Xcode.
- `macos_scenario`: `none`, `runtime-smoke`, `runtime-e2e`, or `distribution-e2e`.
- `macos_audio_artifact`: private Namespace artifact containing WAV fixtures. Full runtime requires it. Smoke uses a pinned public CC-BY-4.0 [podscripter FLEURS fixture](https://huggingface.co/datasets/podscripter-project/test-fixtures) when blank.
- `macos_repetitions`: `1`, `3`, or `5` repetitions per fixture/app after the smoke run.
- `macos_empty_final_expectation`: `none`, `known-bad`, or `fixed`. The latter two require `runtime-smoke` or `distribution-e2e` and make the selected repetition count apply to the smoke cases.
- `macos_empty_final_baseline_run_id`: successful `known-bad` stage run. Required only for a `fixed` empty-final proof. It must use the same stage tooling SHA and scenario.
- `ios_artifact_run_id`: successful `VoiceInk iOS single-repo migration` workflow run containing the exact Simulator artifact. Blank selects the latest green run.
- `ios_scenario`: `none` or `local-whisper-import`.
- `hold_minutes`: 0 to 60 minutes after setup/scenario. `distribution-e2e` consumes this window while waiting for Safari, Finder, and Gatekeeper interaction and therefore rejects `0`.

The stage downloads the macOS artifact unchanged and does not re-sign it. CI
builds and ad-hoc signs the external runtime helper once, then the selected Mac
runs that prebuilt helper without compiling it. The stage rejects app and helper
run IDs unless they are completed, successful, non-PR runs of
`voiceink-build.yml` from this repository. The helper must match the checked-out
stage tooling SHA. The app build, helper build, and distribution stage must also
report distinct Namespace runner instance names. The stage records its boot
session, then the distribution script independently requires absent Roma
preferences, TCC rows, installed copies, running processes, and model state.
Its evidence ties both
artifacts to their workflow run and source SHA. The
existing iOS migration workflow packages its Xcode-signed Simulator application
as `roma.just.talk.ios-simulator.app`, preserving App Group exchange between the
app and keyboard extension.

For `distribution-e2e`, the workflow also requires the Namespace instance to
have booted within 15 minutes. It uses the Namespace image's existing `runner`
administrator because that account owns the logged-in desktop, has Secure Token,
and is an APFS volume owner. Before the desktop handoff, the workflow verifies
all four properties. A separate credential step then authenticates the image
account through an interactive Open Directory prompt. Any image-contract drift
fails before the artifact is launched.

The image password comes from the masked repository secret
`NAMESPACE_MACOS_RUNNER_PASSWORD`; it is not stored in workflow source. The
credentials are written to
`~/Desktop/Roma Distribution E2E Operator Credentials.txt` with mode `0600`.
Do not upload, copy, or share that Desktop file. After the scenario and hold
finish, an always-running cleanup step removes only the credential file and
proves the Namespace-owned `runner` account and home directory remain present.
The uploaded evidence records those checks but never the password or credential
file.

Those account checks do not prove that Gatekeeper's administrator dialog can
authenticate the account. On macOS 26.3.1 build 25D2128, run
[33958787051](https://github.com/negentropi/roma-just-talk/actions/runs/33958787051)
reached that dialog but Open Directory rejected its generated administrator with
`ODErrorCredentialsMethodNotSupported`: the request supplied ACM data requiring
a SEP credential, while the account lacked a SEP credential and Secure Token.
The built-in `runner` had a Secure Token. The bootstrap-token status query was
unavailable because the Mac was not supervised in MDM or DEP enrolled.
That generated-account setup is not a valid framework-crash negative control.
The distribution lane instead verifies and uses the image-owned `runner`
account; a run is not valid unless the same fresh instance proves its password,
Secure Token, and exact APFS user record before the GUI handoff.
Do not retry the generated-account setup, reset the runner password, substitute
sudo for the GUI approval, or weaken Gatekeeper. Evidence files from the failed
setup are `distribution-operator-auth-method-failure.txt` and
`distribution-operator-secure-token-status.txt`.

Runtime-only runner profiles may attach the persistent model cache. Runtime-only
`nscloud-macos-*` image lanes require a previously absent cache path under that
job's runner-temporary directory and record the pre-state before creating it.
The distribution lane exposes neither cache. The downloaded app is the first
process allowed to create FluidAudio's live model directory, and the lane fails
unless that verified first-launch process creates it.

The public smoke fixture's source, license, and re-encoding notice are recorded
in [the runtime harness guide](RUNTIME_E2E_HARNESS.md#autonomous-namespace-run).

Wait for the `Remote desktop ready` job to print `REMOTE E2E STAGE READY`. In Namespace, open that GitHub job and select **Remote Display**.

The direct CLI path is preferred for future Computer Use:

```bash
scripts/open-remote-e2e-stage.sh <github-run-id>
```

Local requirements: authenticated `nsc` and `jq`. See [Namespace CLI installation](https://namespace.so/docs/reference/cli/installation) and [`nsc vnc`](https://namespace.so/docs/reference/cli/vnc).

The helper uses `nsc github job list` and `nsc github job describe` to find the running job's Namespace instance ID, then executes:

```bash
nsc vnc <instance-id>
```

Omit the run ID only when one remote E2E stage is running. The helper then selects the newest matching stage.

## Prepared desktop

Depending on `target` and scenario, the remote Mac contains:

- ordinary macOS stage without a scripted scenario: `~/Applications/roma just talk.app`, launched with onboarding state reset;
- runtime smoke/full stage: `/Applications/roma just talk.app`, after exercising the landing page's app-only quarantine removal and launch command;
- macOS distribution E2E: the untouched app below a newly mounted APFS volume under `/Volumes`, where Finder extracted it;
- iOS: a booted iPhone Simulator with `roma just talk` installed and launched.
- `~/Desktop/REMOTE E2E STAGE READY.txt`: human-readable handoff.
- `~/Desktop/Roma Distribution E2E Operator Credentials.txt`: present only for a distribution E2E. Use it only if macOS asks for administrator authentication after **Open Anyway**.
- `~/Desktop/Remote E2E Stage`: link to the machine-readable stage directory.
- `~/Desktop/Finish Remote E2E Stage.command`: ends the hold window early.

The stable future-agent contract is:

1. Run `scripts/open-remote-e2e-stage.sh <github-run-id>` to open the VNC client.
2. Wait for `Remote E2E Stage/READY` on the remote desktop.
3. Read `Remote E2E Stage/stage-manifest.json`.
4. Interact with the visible applications.
5. Save additional evidence into the manifest's `evidenceDirectory`.
6. Run `Finish Remote E2E Stage.command`.

Provisioning remains owned by this workflow. Manual interaction prompts and judgment
remain owned by Computer Use; the optional local-STT path is owned by the deterministic script.

## Download-to-launch distribution E2E

Choose `target=macos`, select `macos_scenario=distribution-e2e`, provide the
exact successful build run, set the runner label for the intended OS lane, set
`macos_expected_version` and `macos_expected_build` to the affected release,
and allow 30 to 60 minutes of interaction time. The distribution lane refuses
to start without both exact values.

Use `macos_distribution_expectation=fixed` for a general candidate launch check.
That mode alone does not close a reported framework-signature bug. Use
`fixed-after-framework-signature` for closure. It downloads exactly one
nonexpired `remote-e2e-stage-evidence` artifact from the named successful
baseline run, checks the GitHub artifact digest, then requires the baseline to
prove the same tooling SHA, workflow, repository, exact OS version and build,
runner lane, rejected framework, and reported executable UUIDs. It also requires
the raw crash report, matcher, timing, PID, identity, source-artifact, and fresh
runner evidence. The crash report must also match the short version and bundle
version read from the downloaded app's `Info.plist`. The baseline app run,
artifact ID, digest, and head SHA must all
differ from the candidate. Only a candidate that then completes the normal
Gatekeeper launch and deterministic runtime smoke records
`passed_after_framework_signature_baseline`.

Use
`known-bad-framework-signature` only for a historical failing artifact, with
`macos_expected_rejected_framework=whisper` or
`macos_expected_rejected_framework=MediaRemoteAdapter`. That
mode ends immediately after it proves a parsed AppTranslocated Roma crash-report PID aborted with
all of: `fatalDyldError=1`, `EXC_CRASH`/`SIGABRT`, `Namespace DYLD, Code 1`,
`Library missing`, the selected `@rpath/<framework>.framework`, an actual
framework path, `AppTranslocation`, and `code signature in ... not valid for
use in process` in one new Roma crash report. macOS can truncate the final
MediaRemoteAdapter reason after its exact framework path; the verifier accepts
only that documented truncation shape, not a generic AMFI warning. It rejects
evidence naming the other permitted framework. A UI timeout, authentication
failure, another crash, a second Roma PID, or a wrong OS is a failed test, not
a reproduction.

Gatekeeper can create a suspended Roma process before administrator authentication
finishes. A PID alone does not start the 30-second crash-report completion timer.
That timer starts only when a new report appears; authentication and launch remain
bounded by the configured interaction window. Run
[33936115642](https://github.com/negentropi/roma-just-talk/actions/runs/33936115642)
exposed the old premature timeout: PID 27074 appeared in state `T` at 01:44:35 UTC,
and the test failed at 01:45:06 while the administrator dialog was still open.
This is a test-timing regression, not reproduction of the framework crash.
Run 33958787051 exercised the corrected timer. The saved
`authentication-window-timer-proof.txt` records PID 11117 still suspended at an
elapsed 11:05, beyond the old cutoff. This process observation does not prove
successful authentication, completed launch, or the historical DYLD failure.

This is not the installed-app runtime test with quarantine added afterward. It
starts on a fresh Apple Silicon runner and fails if Roma preferences, Roma TCC
rows, FluidAudio model state, an installed copy, a running process, disabled
Gatekeeper assessments, the wrong architecture, or the wrong exact macOS
product or build version already exist. No model cache is mounted or created for
this lane. In fixed mode, the downloaded app must create the initial FluidAudio
model state during its verified Gatekeeper and App Translocation launch.

The workflow downloads both forms of the selected Actions artifact:

1. the outer ZIP a person receives from the GitHub Actions web download; and
2. the inner `roma.just.talk.app.zip` after GitHub's artifact wrapper is removed.

It requires the outer ZIP hash to match GitHub's recorded artifact digest and
proves that the inner ZIP in the distributed wrapper matches the CLI download
before the user path starts. The scenario then:

1. asks GitHub's authenticated artifact endpoint for a short-lived download redirect for that exact artifact ID, opens the redirect in Safari, and downloads it to a newly mounted APFS volume. The redirect itself is never saved in evidence. APFS preserves the framework symlinks in the signed app bundle;
2. requires Safari quarantine and byte equality with the untouched outer ZIP already fetched from the selected Actions run;
3. asks the operator to double-click the outer ZIP in Finder and waits for Archive Utility to finish. Stock Archive Utility may recursively expand the nested app ZIP and remove that intermediate file. The lane records whether this one-action path produced the app. If the Mac keeps the exact inner ZIP instead, the lane verifies its hash and Safari quarantine before requesting one follow-up Finder extraction;
4. requires human confirmation after each Finder action actually needed, proves the final app inherited Safari quarantine, checks its strict deep signature, and compares every directory mode, every regular file's contents and mode, and every symlink target with an independent reference extracted from the hash-verified inner ZIP. That reference never becomes the launched app. The lane also compares the app's minimum macOS version with the exact runner version;
5. records the complete file, directory, and symlink manifest for the extracted app, performs the first launch while Gatekeeper still rejects it, and requires the operator to confirm the visible "Not Opened" dialog before using Privacy & Security, Open Anyway;
6. starts an approval-window process and log monitor before Open Anyway. In `fixed` mode, it requires the operator to confirm that the approved first-launch UI is visible and responsive, then requires the first observed PID to report finished AppKit launch, run through App Translocation as native ARM64, remain runnable without `SIGCONT`, map every bundle-relative Mach-O dependency discovered recursively from the active ARM64 executable graph, survive a stability interval without dyld or signature errors, and leave the full app bundle byte-identical to its pre-launch manifest. In `known-bad-framework-signature` mode, it instead requires the matching crash-report PID to be dead, any sampled approval PID to equal it, no Roma process to remain, the exact selected-framework three-part dyld signature report, Safari quarantine, and an unchanged bundle. A second Roma PID, wrong crash report, or approval-window dyld error invalidates either mode; and
7. only in fixed mode, records that first-process verdict, requires that exact Roma process to remain the only running Roma instance, records its normal termination, and validates or completes its live model directory against the pinned manifest before deliberately starting separate prewarm and transcription relaunches of the same extracted artifact. Every observed Roma PID must be recorded by the helper, run through App Translocation with the same executable hash, pass the same recursive signature and mapped-code checks through process exit, and have an explicit test-requested termination. A new crash report or unaccounted process invalidates the run. The lane also compares the complete file, directory, and symlink bundle manifest before and after runtime and writes a separate transcription verdict.

CI builds the runtime helper with a macOS 14.0 deployment target. Before changing
TCC or starting Roma runtime work, the target Mac runs that exact packaged helper
executable with `--help`, requires its own clean exit and expected output,
and records the host product version, build, architecture, helper hash, and
minimum OS. The helper uses the ScreenCaptureKit content-filter screenshot API
available on Sonoma, so the functional smoke keeps its rendered-pixel proof on
macOS 14 instead of falling back to Accessibility text alone. The selected Mac
never compiles this Swift 6.2 helper.

Open the running Namespace job's Remote Display as soon as the log prints
`DISTRIBUTION E2E BROWSER ACTION REQUIRED`. Follow
`~/Desktop/GATEKEEPER ACTION REQUIRED.txt`; the file updates at each manual
boundary. No script clicks Open Anyway, clears quarantine, modifies SIP, or
re-signs the app.

If the **Open Anyway** confirmation asks for administrator authentication, open
`~/Desktop/Roma Distribution E2E Operator Credentials.txt` in Remote Display
and enter its image-account credentials. This is the single authorized use of
that file. Never put its contents into GitHub logs, the evidence directory,
chat, or an artifact.

Fixed mode has three Desktop confirmation commands: Finder extraction complete,
Gatekeeper Not Opened, and Roma first-launch ready. Known-bad framework-signature
mode has only the first two, because the app must abort before it can show UI. A
fourth Finder follow-up command appears only when Archive Utility leaves the
nested app ZIP for a separate double-click. Run each Finder command only after
Archive Utility finishes that action. Run the Gatekeeper command only after
seeing and dismissing the actual "Not Opened" dialog. In fixed mode, run the
final command only after the approved Roma process shows responsive first-launch
UI. The fixed verifier still checks the same PID and fails if it stopped, died,
did not finish AppKit launch, or did not run through AppTranslocation.

Run Sonoma and Tahoe as separate jobs. A moving selector such as `14.x` or
`26.x` is useful for coverage but is not proof for 14.2.1 or 26.4.1 unless the
recorded product and build versions equal the requested release. The exact
identity check fails before Safari launches when the runner image is wrong. The
current app target is macOS 14.4, so an exact 14.2.1 lane will stop at the app
compatibility checkpoint until the separate Sonoma deployment work lands. That
failure must not be reported as a signing result.

## Fast macOS hypothesis check

Choose `target=macos`, set `macos_artifact_run_id` to an exact green build,
choose `macos_scenario=runtime-smoke`, leave `macos_audio_artifact` blank, and
use `hold_minutes=0`. The runner fetches the pinned public fixture through
Namespace's immutable-URL cache and verifies its SHA-256 before playback. Pass a
private Namespace WAV artifact only when a hypothesis needs that exact audio.

This lane answers whether a runtime idea survives one named quick-release fixture
of at most eight seconds in TextEdit and Safari, with both empty and existing-text
insertion. It runs the same
preflight, isolated target probe, real app, BlackHole route, Special shortcut,
trace, rendered-text, cleanup, and restoration checks as the full scenario. It
does not provide repeated latency or four-app coverage. Treat it as hypothesis
evidence, then run `runtime-e2e` on the final candidate.

When only `Tools/RuntimeE2EHarness`, its runtime scripts, or these docs changed,
reuse the last exact app build. Do not rebuild macOS or run iOS verification for
an unchanged app. Any app, shared-core, project, entitlement, build-setting, or
dependency change needs a new exact app artifact first.

The remote stage records a failed scenario without ending its cache-owning job,
uploads the evidence, and lets Namespace save the model cache. A separate
verdict job then fails the workflow. Red hypotheses therefore keep the same
failure signal while still warming the next run. Empty cache-volume forks do not
block on FluidAudio's model download. The runner verifies a pinned 22-file model
manifest and fetches only missing files through Namespace's immutable-URL cache
across four workers in parallel with machine setup.

## Matched empty-final regression proof

Use `macos_empty_final_expectation=known-bad` with the historical affected app
artifact first. The lane succeeds only when a case receives a non-empty live
partial, final ASR returns zero characters, and an empty first commit follows
that final result in the same trace. The partial observer is asynchronous, so
its log entry need not precede final ASR. Every red failure must have that same
`emptyTranscript` boundary on a configured target listed by preflight. The
verifier derives every exact affected `target` + `textScenario` pair from the
evidence. A generic launch,
target, permission, or audio failure does not count as reproduction.

Then run the fixed app with `macos_empty_final_expectation=fixed` and set
`macos_empty_final_baseline_run_id` to that successful known-bad stage run. The
stage requires the same runner profile, downloads the immutable evidence
artifact by ID, verifies its GitHub SHA-256 digest, reverifies the known-bad
report, and compares
`empty-final-e2e-contract.json` byte-for-byte before the fixed trial. The
contract binds the tooling SHA, host OS/build/architecture, helper hash, audio
hash and duration, model revision/manifest, translocation mode, targets, timing,
lifecycle, and repetitions. It omits volatile app, build, and audio directory
paths. The audio bytes remain bound by hash; only the affected and candidate app
artifacts may differ.

The app artifact is the experiment's changed input. The fixed stage requires
the affected and candidate app run IDs, artifact IDs, artifact digests, source
SHAs, and executable hashes to differ. The runtime helper and baseline evidence
archives are also downloaded by artifact ID and checked against GitHub's
recorded digest before extraction.

The fixed lane requires every smoke case to pass. It re-derives the baseline
profile from the downloaded report. For every affected baseline `target` +
`textScenario` pair, at least one case on that exact target and text scenario
must show zero-character final ASR followed by the explicit
`fluid_streaming.commit.fallback_to_hypothesis` event, a non-empty first
commit, and non-empty visible text, in that order. Other passing repetitions
may receive a normal non-empty final ASR. A green run missing any matched
fallback case does not prove this fix. Use
`macos_repetitions=5` for both runs. For the release claim, use
`distribution-e2e`; `runtime-smoke` is only a faster diagnostic run.

Both expectations reject a harness fatal error or failed restoration, even when
one case otherwise matches the requested evidence. They also require Roma to be
stopped at preflight, reject external or symlinked model storage, and use the
normal local FluidAudio model directory. Roma relaunches before every smoke case. Each
case gets a fresh Roma process and fresh streaming provider/`AsrManager` after
the normal app-level model prewarm. The verifier requires one unique launch PID
per all 20 smoke cases and the same 20 PIDs in the normal-termination evidence.
Those cases are the five repetitions of each TextEdit/Safari
empty/existing-text condition. Ordinary
runtime lanes keep the existing reused-process behavior.

The exact result is stored in
`runtime-empty-final-regression-verdict.txt`. The distribution chain also records
the requested expectation. A matched `known-bad` run reports
`runtime_transcription_verdict=expected_failure_reproduced`, not a successful
transcription.

## Deterministic macOS runtime E2E scenario

Choose `target=macos`, set `macos_artifact_run_id` to the exact green build,
choose `macos_scenario=runtime-e2e`, provide the private Namespace WAV artifact,
and use `hold_minutes=0` for a fully scripted run.

The scenario:

1. installs BlackHole 2ch, Chrome, and Visual Studio Code on the disposable VM;
2. preserves the downloaded Roma app signature and builds the external harness once;
3. grants exact-CDHash TCC rows only on that ephemeral Mac;
4. verifies the pinned public Parakeet V2 files and waits for Roma's real prewarm;
5. opens TextEdit, Safari, Chrome, and VS Code before the `runningOnly` harness starts;
6. proves isolated target setup/cleanup before involving Roma, audio, or Shift;
7. feeds each WAV into BlackHole, beginning audio `1.1s` before synthetic left-Shift down;
8. runs a four-case TextEdit/Safari smoke using one short fixture, then the requested repeated four-app matrix; and
9. uploads factual phase checkpoints and the first unproven boundary without assigning blame to Roma or the harness.

The TCC database writes are intentionally remote-only. They are not a local setup
mechanism and disappear with the Namespace VM.

## macOS onboarding unit-test host

The macOS build workflow holds temporary, one-hour display and user-active
`caffeinate` assertions from the start of its disposable build job. This does
not unlock an already locked session; fixture readiness still checks the actual
desktop. The workflow then runs
`scripts/run-macos-ci-unit-tests.sh` on that logged-in Actions runner. The script
builds the Debug test host first, then
grants that exact host's designated requirement Accessibility and Microphone
access. `test-without-building` preserves the identity that received permission;
embedding a rebuilt XCTest bundle after granting permission invalidates this setup.

Each onboarding fixture uses the public AX probe compiled from
`Tools/OnboardingAccessibilityProbe.swift` at
`/tmp/roma-onboarding-diagnostic/ExternalAXProbe`. The child verifies its parent
and runtime trust before querying the fixture window. Permission rows alone are
not interaction proof. The workflow retains the XCTest result bundle and checks
the host requirement and host/probe executable hashes before and after testing.
The probe is not packaged in the release app. This provisioning is not a local
installation procedure and does not establish first-launch permission behavior.

## Deterministic iOS local STT scenario

Choose `target=ios`, set `ios_artifact_run_id` to the exact green build, choose
`ios_scenario=local-whisper-import`, and use `hold_minutes=0` for a fully scripted run.

The scenario:

1. installs AXe on the ephemeral Namespace runner when needed;
2. atomically downloads, verifies, and copies the pinned `ggml-base.bin` model into the app container;
3. generates a 16 kHz mono speech fixture with macOS `say`;
4. launches the actual app with onboarding complete and opens the fixture through the app's external-file route;
5. lets fresh-Simulator system banners settle, then uses AXe accessibility labels to start transcription and open transcript detail;
6. requires the normalized expected phrase and `Completed` state in the visible UI;
7. verifies a non-empty canonical WAV header and matching declared data length; and
8. uploads provenance, success or failure state, screenshots, accessibility trees, hashes, and logs.

This proves the built Simulator app's external-open, import, WAV preparation,
local Whisper, persistence, queue completion, and transcript-detail path. It does
not prove live microphone capture, recorder pre-roll, keyboard handoff, or physical-device routing.

## Evidence

The workflow uploads `remote-e2e-stage-evidence` containing:

- Simulator screenshots when iOS is selected;
- macOS and iOS application logs;
- macOS runtime preflight, target-probe, smoke, full report, failure-boundary summary, TCC rows, exact signatures/hashes, audio/model provenance, and restoration logs;
- distribution source and browser hashes, GitHub's artifact digest, exact artifact ID and sanitized redirect host, outer and inner quarantine records, APFS volume inventory, per-extraction human confirmations, Finder and Archive Utility process/log evidence, Gatekeeper assessments, approval-window PID events and crash-report baseline, source and translocated executable identity, native ARM64 process identity, recursively discovered active-slice code, observed mapped bundle code, signatures, process states, and unified logs;
- every runtime Roma PID, its translocated launch identity, lifetime mapped-code evidence, explicit termination intent, and pre/post crash-report inventories;
- app and runtime-helper workflow run IDs, source SHAs, workflow identity, archive and executable hashes, plus the helper's target-host loadability result;
- macOS, Xcode, and Simulator inventory.

Namespace VNC can be active while `screencapture` remains unable to see that display from the runner shell. The workflow records this condition instead of silently claiming a desktop screenshot. The VNC controller or future Computer Use skill owns macOS desktop screenshots.

## Boundaries

- iOS means iOS Simulator on the remote Mac, not a physical iPhone.
- Microphone availability is not assumed; the deterministic STT scenario uses a generated audio file.
- Manual stages do not pre-grant Accessibility, Input Monitoring, Screen Recording, or other TCC permissions.
- `distribution-e2e` requires a person or authorized Computer Use session for Safari's site-download prompt, Finder extraction, and Gatekeeper Open Anyway. A Mac that does not recursively expand the nested ZIP requires one extra Finder action. Missing interaction times out and fails.
- Both macOS runtime scenarios grant only the exact helper/Roma permissions needed on their disposable VM and verify the real global-shortcut/audio-input path.
- The optional local-STT scenario performs narrow AXe UI assertions; XCUITest remains a separate fast gate.
