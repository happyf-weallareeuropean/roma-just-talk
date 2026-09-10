# Changelog

## v1.95.1 - 2026-09-07

- Show a canceled model download as canceled and remove inactive progress indicators, so Retry clearly starts a new attempt.

- Preserve recorded audio across microphone callback boundaries and recording stops, including queued streaming audio and the next recording’s pre-roll.

- Let successful Chinese + English dictation deliver its text while temporary model memory is cleared; the next model operation still waits for cleanup.

- Preserve your transcription language when switching models: using an English-only model no longer replaces Auto-detect or Chinese before returning to Chinese + English. Explicit English choices remain unchanged.

- Fixed Chinese + English model setup failing after the download completed; verify and install the pinned files directly without requiring a separate model cache.

- Fit onboarding within the active Mac desktop, keep navigation visible while welcome, permission, and tutorial content scrolls, and preserve the main window’s frame when repeating setup.

- Keep model setup instructions and navigation visible on shorter Mac windows by letting the model list scroll within the available space.

- Make onboarding’s Skip controls accessible as native buttons while preserving their appearance and setup-later behavior.

- Add local Chinese + English dictation on Apple silicon Macs running macOS 15+, with an English-only setup choice, a country-based suggestion that respects your selection, and download controls. Continuing setup saves your model choice for future onboarding visits. Startup prewarm only loads installed models, so it cannot download the English fallback before you choose. On release, queued bilingual audio is finalized together instead of replaying every live-update chunk. Reuse the GPU stream across bilingual decoding passes to reduce completion delays. Cancel obsolete bilingual live decoding on release, then finalize all captured audio after it drains; cancelling completion also drains the recording.
- Start final local dictation recognition while a cancelled live pass finishes, reducing release delays without dropping audio or publishing stale live text.
- Stop superseded Chinese + English decoding between existing model evaluation batches, so it can skip work that has not started. Finalization still waits for running GPU work to finish; the app latency gate remains pending.
- Keep automatic model-list refreshes from saving the fallback model as your chosen default.
- Added NVIDIA Parakeet zh-TW as an optional cloud model using your own NVIDIA API key on macOS 15+ and iOS 18+; local transcription never switches to it automatically.
- Restrict Homebrew installation to Apple Silicon, matching the architecture of the released Mac app.
- Removed the keyboard-modifier settling delay from Accessibility menu paste commands; simulated Cmd-V retains its settling delay.
- Locate browser and Electron Paste commands while speech recognition runs, then revalidate the focused editor and command before pasting. This removes menu discovery from the final insertion path when the prepared command remains valid.
- Added patch-version support to Roma's informational update feed.
- Added an early-beta label and post-download Mac setup guide with copyable Terminal and agent instructions, plus optional Open Anyway GUI steps.
- Reframed Trust around Felix's commitments to privacy controls, protected access, testing public downloads, and support, backed by a release checklist, with a visible current-release summary and keyboard-accessible expandable details.
- Clarified Trust wording for first-time visitors with direct support links, plain-language release evidence, privacy exceptions beside setup advice, and an accurate microphone disclosure for the browser demo.
- Reworked the landing Trust section to disclose the exact downloadable build, pre-trigger microphone behavior, cloud and context data paths, local history and credential storage, broad permission scope, non-notarized distribution, and Felix's support process, with every direct app-download link pinned to the reviewed v1.95 artifact.
- Added a local-only Hardened Runtime exception for ad-hoc macOS builds that load bundled MediaRemoteAdapter and Sparkle frameworks, while keeping Library Validation enabled for certificate-signed releases.
- Added a fresh-Mac distribution E2E that follows the exact GitHub Actions outer ZIP through Safari quarantine, Archive Utility's real recursive or separate Finder extraction path, Gatekeeper Open Anyway, App Translocation, generic mapped-code verification, and a real transcription smoke.
- Fixed the first cold FluidAudio streaming dictation sometimes pasting nothing when live recognition had text but final ASR returned empty.
- Reduced Parakeet array-clearing work with an exactly pinned FluidAudio patch, preserving scalar reset behavior for other values, types, and layouts; app latency acceptance remains pending.
- Linked whisper.cpp statically into the macOS and iOS apps so ad-hoc builds no longer depend on a separately signed `whisper.framework` at launch.
- Rebuilt `/demo` as a full-screen, zero-download browser dictation experience with a three-second rolling speech pre-roll, Left Shift release insertion, automatic writing-environment changes, microphone recovery, a narrated no-mic preview, and site navigation revealed only at the top edge.
- Added a real-audio `/demo` E2E lane that routes a fixed WAV through BlackHole, starts the player 1.1 seconds before Left Shift, releases after playback, and gates the pre-trigger opening word, transcript accuracy, and key-up completion latency in Chrome's real speech service.
- Restyled the landing-page action frames in white, light gray, and dark gray while keeping their current faces and interactions.
- Changed automatic macOS recording mute to keep AirPods output audible while muting other outputs; explicit On and Off modes remain overrides.
- Renamed the inherited iOS record deep-link scheme from `voiceink://record` to `romajusttalk://record` so external launch identity matches Roma Just Talk.
- Replaced the inherited VoiceInk bundle, logging, iCloud, App Group, keychain, test, and extension identifiers with `com.negentropi.RomaJustTalk`.
- Routed macOS update checks away from the upstream VoiceInk feed to an informational appcast attached to each Roma Just Talk GitHub release.
- Simplified the macOS icon settings to positive Menu Bar and Dock Icon switches whose moving thumb reads Show or Hide, with ON consistently meaning visible while preserving existing choices and backup compatibility.
- Added a landing-site pricing preview for the planned Freemium, Italy, and Roma monthly tiers, clearly marking billing, usage tracking, and entitlement enforcement as not yet live.
- Prevented Special modifier-only shortcuts from arming while macOS Secure Input is already active.
- Added iOS microphone permission setup during onboarding plus a refreshable Settings recovery screen that reuses the recording permission path.
- Resumed incomplete iOS onboarding at its last saved setup step after relaunch, clearing the saved step on completion or app-data reset.
- Exposed iOS app-data reset in shipping Settings with destructive confirmation before deleting recordings, models, preferences, and credentials.
- Added an interactive iOS onboarding tutorial that records and transcribes a test phrase through the normal app pipeline before completing setup.
- Added iOS Help & Support with Common Issues, documentation, support email fallback, sharing, and configurable announcements with dismissal and retry states.
- Added iOS Parakeet V2/V3 model download, selection, batch transcription, live transcription, cancellation, retry, deletion, and prewarming through the shared FluidAudio policy.
- Added iOS local Whisper model import, selection, persistence, and deletion using the existing shared model-file and runtime policies.
- Added iOS Shortcuts actions to start, stop, and cancel recording through the existing recording flow.
- Added iOS 26 Native Apple transcription with mode selection, BCP-47 language handling, Speech asset status/download controls, and recorded-file SpeechAnalyzer routing.
- Added iOS per-language local Whisper prompt editing and trailing-space keyboard delivery using the existing shared preferences and runtime policy.
- Added retained iOS local Whisper contexts with coalesced model loading, launch/foreground prewarm, recording-time cancellation, model-deletion and memory-warning release, and a shared prewarm setting.
- Added an iOS local Whisper VAD control backed by the same shared preference and whisper.cpp runtime configuration as macOS batch transcription.
- Added iOS live transcription for streaming-capable cloud models, including per-model control, ordered PCM streaming, live partial preview, shared cleanup/enhancement of committed text, cancellation, and saved-file batch fallback after connection or finalization failure.
- Added Cartesia credential verification, model selection, and forced streaming transcription on iOS while preserving its explicit no-batch behavior.
- Added iOS custom OpenAI-compatible transcription endpoint CRUD with Keychain-backed secrets, dynamic mode selection, recorded-file routing, reset cleanup, and failure states.
- Added iOS editing for existing word-replacement rules with shared validation, duplicate detection, normalized persistence, and storage-order preservation.
- Added Mistral post-processing to iOS modes through the shared provider catalog, model list, credential readiness, and OpenAI-compatible chat route.
- Added Anthropic post-processing to iOS modes with shared credential verification, native Messages request/response handling, model selection, and output filtering.
- Added OpenRouter post-processing to iOS modes with verified credentials, dynamic model refresh/cache, selection repair, and OpenAI-compatible request routing.
- Added generic custom post-processing to iOS with shared endpoint/model preferences, Keychain credentials, verification, mode selection, and OpenAI-compatible routing.
- Added Ollama post-processing to iOS with local-network permission copy, server/model settings, model refresh, mode selection, and OpenAI-compatible local routing.
- Added an iOS reusable prompt library with native add/edit/delete/reorder controls, trigger words, mode selection, per-recording overrides, and prompt-aware enhancement metadata.
- Added bounded iOS keyboard surrounding-text context for enhancement and cursor-aware capitalization, clearing the shared exchange copy as soon as the app captures the request.
- Added completed-record retranscription and re-enhancement on iOS with mode/prompt selection, cancellation, preserved prior results on failure, and persisted enhancement metadata.
- Added iOS history edit mode with select all, confirmed multi-delete, recording-file cleanup, and shared CSV export through the system share sheet.
- Added a full iOS metrics dashboard with persisted time filters, time-saved and dictation totals, empty-state handling, and transcription/enhancement model comparisons.
- Added iOS transcript/audio retention settings with cleanup previews, confirmed manual cleanup, orphan-file removal, active-note safety, and daily foreground cleanup.
- Added selective iOS settings backup/export/import for general settings, modes, prompts, dictionary entries, and custom model definitions, excluding API keys and preserving current settings when validation or storage fails.
- Added iOS diagnostic support-bundle export with selectable log ranges, compact device/configuration facts, empty-range handling, secret/email/home-path redaction, and system sharing.
- Added an optional iOS keyboard auto-send setting that captures the preference with each completed dictation and inserts one Return after one-time text delivery.
- Added iOS AI-enhancement behavior controls for keyboard context, short-transcript skipping, request timeout, retry, and original-transcript fallback.
- Added iOS haptic, silent, built-in, and imported custom start/stop recording feedback controls using the shared sound catalog and validation policy.
- Added iOS audio/video file import with multi-file queueing, 16 kHz WAV preparation, mode selection, background-safe transcription, cancel/retry controls, persistent history, detail navigation, external file opening, and transcript sharing.
- Added tracked iOS post-record transcription tasks with balanced background execution, retryable expiration/relaunch recovery, user cancellation, keyboard result completion, and whisper.cpp abort support for local inference.
- Added iOS keyboard setup to onboarding and Settings, with installation guidance, a verification field, fresh activation and Full Access status, recovery through system Settings, and a setup-later path.
- Added an iOS keyboard clipboard-history surface opened by horizontal swipe or its toolbar button, with explicit current-pasteboard capture, local App Group retention, text/link/image previews, typed search, filters, pin/delete/clear actions, plus emoji, Tab, and hide-keyboard controls.
- Added context-bound iOS keyboard result handoff so completed dictation inserts exactly once after returning to a matching field, with explicit confirmation for ambiguous empty fields.
- Fixed the iOS keyboard extension crash when a text document identifier is temporarily unavailable during startup.
- Kept dismiss-only iOS recording alerts actionable instead of rendering a disabled OK button.
- Fixed macOS onboarding permission setup so microphone and other grants refresh when the app becomes active or permission state changes, and onboarding resumes at the saved setup step after relaunch.
- Added FluidAudio onboarding download lifecycle logs and changed zero-fraction active downloads to show an indeterminate progress state instead of a dead-looking `0%`.
- Added shared FluidAudio download task control, stale-progress detection, cache-aware retry, cancellation, and persistent failure feedback so onboarding can recover from silent model-download stalls.
- Added Try It Out onboarding diagnostics for permission state, shortcut setup, selected model, recording state, and resulting text length while forcing a shortcut monitor refresh when the step appears.
- Made the macOS onboarding window use regular app/window behavior instead of auxiliary all-spaces panel behavior.
- Suppressed redundant shortcut permission banners while macOS onboarding or setup permission screens are already guiding the user through the same grants.
- Increased the macOS onboarding skip button contrast so "Skip for now" stays legible on the dark setup background.
- Reused the model management panel in macOS onboarding's model step, keeping launch auto-download while limiting onboarding navigation to Next and Skip.
- Added a first-run setup skip action for the keyboard-shortcut step so setup can continue without configuring a shortcut immediately.
- Added a Homebrew cask for installing the fork from the repo tap and aligned CI packaging with the release asset URL.
- Added an opt-in visible-text latency harness for measuring real hotkey-release-to-target-text timing in everyday macOS apps.
- Added an autonomous Namespace macOS runtime E2E harness that feeds fixed WAV fixtures through BlackHole, drives the real Special shortcut, verifies Accessibility-visible insertion across four already-running apps, preserves per-phase evidence without guessing failure ownership, and restores audio, app, clipboard-target, and temporary-resource state.
- Kept macOS recording, cancellation, streaming fallback, and Power Mode runtime closures on the MainActor, with executor enqueue-to-resume queue-delay events in the latency trace for separating scheduler stalls from app work.
- Kept the dictated text on the clipboard when the paste command cannot be posted, so failed target-app pastes do not immediately restore over the transcript.
- Fixed dictation in browser and Electron editors so delivery uses a real paste command instead of Accessibility-only mutation, preserving application state and existing text around the cursor.
- Added up to three seconds of audio pre-roll to iOS after capture has warmed, using the shared PCM pre-roll buffer without carrying over speculative transcription preload.
- Prevented iOS from crashing after onboarding when the active audio route exposes no usable microphone format, returning a recorder-start failure before installing the AVAudioEngine tap.
- Added configurable iOS microphone routing with system-managed routing on by default, optional preferred-input selection with system fallback, deferred preference-driven capture restarts during active recording, and the existing custom-device default preserved on macOS.
- Removed the Preload feature—the speculative rolling-buffer VAD/STT and quick-release path—including its forced-streaming session ownership. Special shortcuts now start ordinary recording immediately on key-down, and the recorder retains its fixed 3-second audio pre-roll without starting ASR beforehand.
- Restored low-latency ordinary recording after Preload removal: local model prewarm now loads the selected runtime directly, and batch-capable key-up falls back to the recorded file instead of waiting for pending streaming startup.
- Restored low-latency FluidAudio processing without restoring Preload: when Power Mode has no configurations, the ordinary key-down session starts alongside recorder startup instead of after it; key-down audio is processed more frequently, key-up closes the already-serialized recorder inline, and a hypothesis is reused only when it covers every captured sample.
- Cached the macOS Launch at Login status for the app lifetime so recording-state view updates no longer block key-up transcription on repeated `SMAppService.status` checks.
- Boosted quiet macOS and iOS local Whisper recordings before transcription while leaving silence, noise-floor, continuous-noise, and sparse click-like audio unchanged, improving low-volume/privacy dictation without changing saved audio.
- Reported malformed macOS local Whisper audio as an audio-processing failure instead of silently sending an empty sample buffer to Whisper.
- Preserved existing shortcut settings when shortcut recording is canceled, rejected, interrupted by another recorder, or dismissed before a replacement is captured.
- Built CI release artifacts with the Release configuration and blocked debug-only binaries from packaged app uploads.
- Moved macOS batch cloud transcription provider wiring onto the shared remote transcription dispatcher used by the imported iOS retry path, preserving provider-specific prompt, vocabulary, timeout, retry, and empty-output behavior.
- Aligned imported iOS retry remote-file transcription with shared provider batch defaults, including Groq JSON/temperature/retry settings, Deepgram paragraph settings, and prompt forwarding where supported.
- Aligned imported iOS note search with macOS history search so accent-insensitive transcript matches now come from shared core.
- Kept imported iOS pending notes in a processing state instead of showing retry controls before transcription fails.
- Prevented the completed iOS audio-import row from opening Share while navigating to transcript detail.
- Stripped Codex follow-up JSON payloads from Local CLI enhancement output so transcript cleanup cannot paste assistant metadata into the target app.
- Removed the unsafe Special Key Down and Special Flex settings that could start recording before the app knew whether the Shift press was just normal typing.
- Fixed imported iOS note playback after recording so AirPods and other Bluetooth outputs keep a playback-owned audio session instead of being cut off by stale recording-session cleanup.
- Moved the macOS first-launch Launch at Login default decision into shared core while leaving the LaunchAtLogin execution in the macOS shell.
- Moved macOS cursor-context reader bounds and text-input role filtering into shared core while leaving Accessibility execution in the macOS shell.
- Moved the audio cleanup daily check interval into shared core while leaving Timer scheduling and file deletion in the macOS shell.
- Moved the model prewarm trigger delay into shared core while leaving wake notifications and prewarm execution in the macOS shell.
- Moved completed-transcription auto-cleanup action selection into shared core while leaving SwiftData and file deletion in the macOS shell.
- Removed the shell-only Ollama enhancement timeout fallback so Ollama requests use the shared enhancement request timeout.
- Moved the default selected AI enhancement provider into shared core while leaving provider execution in the macOS shell.
- Moved Ollama runtime startup and settings reset fallbacks into shared core while leaving Ollama transport execution in the macOS shell.
- Moved diagnostic log level labels into shared core while leaving OSLog fetching and file writing in the macOS shell.
- Moved macOS window identifier, title, and frame autosave names into shared core while leaving AppKit window setup in the macOS shell.
- Moved macOS diagnostic/window logger category identity into shared core while leaving OSLog delivery in the macOS shell.
- Moved macOS shortcut event notification names into shared core while leaving NotificationCenter delivery in the macOS shell.
- Removed unused macOS mini/notch recorder hide notification observers.
- Moved macOS credential/license logger category identity into shared core while leaving Keychain, license, and network execution in the macOS shell.
- Moved Power Mode enhancement prompt fallback gating into shared core while leaving SwiftUI form state and provider/model execution in the macOS shell.
- Moved active AI-enhancement prompt lookup and prompt icon fallback into shared core while leaving macOS selection state and SwiftUI binding execution in the shell.
- Moved the macOS audio-player enhancement prompt fallback icon into shared playback presentation.
- Moved mini-recorder prompt shortcut selection planning into shared core while leaving shortcut capture and state mutation in the macOS shell.
- Moved mini-recorder Power Mode shortcut index selection into shared core while leaving active-session execution in the macOS shell.
- Moved Power Mode global shortcut eligibility into shared core while leaving shortcut storage and event monitoring in the macOS shell.
- Moved the enabled Power Mode configuration predicate into shared core while leaving macOS UI toggles and popovers in the shell.
- Moved Power Mode form save mutation ordering into shared core while leaving macOS persistence and notifications in the shell.
- Moved the recorder Power Mode button icon fallback into shared presentation while leaving SwiftUI rendering in the macOS shell.
- Moved recording shortcut special-mode monitor policy into shared core while leaving event tap execution in the macOS shell.
- Routed every imported iOS recording start entrypoint through the shared mode-count start policy, including keyboard/deep-link starts.

## v1.95 - 2026-06-17

- Fixed Special `startRecording` modifier-only shortcuts so unreliable key-up evidence and short clean presses no longer cancel after recording has already started.
- Canceled unclaimed rolling-buffer preload sessions after sustained silence or a short stale-session cap, preventing local STT from running for minutes after brief ambient speech.

## v1.94 - 2026-06-16

- Shared selected-language option ordering between macOS language pickers and the imported iOS settings path.
- Shared provider credential presence checks between macOS cloud/streaming transcription and the imported iOS transcription path, so whitespace-only API keys are treated as missing consistently.
- Shared selected-language request normalization between macOS local Whisper/cloud transcription and the imported iOS transcription path.
- Aligned imported iOS local Whisper transcription with the shared transcription prompt preference used by macOS.
- Aligned imported iOS retry transcription with the shared paragraph-formatting preference, so iOS can use the same core paragraph break policy as macOS.
- Added iOS filler-word list editing backed by the shared cleanup policy, so imported iOS retry transcription can manage the same vocabulary shape used by macOS.
- Aligned imported iOS retry transcription with shared filler-word cleanup defaults, so the integrated iOS app now uses the same core cleanup configuration as macOS for punctuation, lowercase, and filler words.
- Added iOS transcription language selection backed by the shared language catalog, including local Whisper language hints and remote transcription request normalization.
- Shared transcription model catalog metadata between macOS and the imported iOS app, aligning iOS Groq and Deepgram selectable transcription models with the macOS source of truth.
- Aligned the imported iOS app's empty-mode fallback with its shared local Whisper default instead of falling back to a Groq API-key path.
- Replaced the misaligned silence-filter path with rolling buffer preload controls that use local VAD to pre-run supported STT before capture finalization, independent from final/batch transcription VAD.
- Made the fresh Special shortcut default preload-only so quick releases can commit the rolling-buffer pre-run path without opening a recorder first.
- Added configurable rolling buffer duration with decimal seconds support.
- Renamed model-card transcription mode controls to "Streaming" so they stay separate from rolling buffer preload.
- Renamed the provisional transcript UI toggle to "Show Transcript Preview" so it no longer reads like a separate live-transcription feature.
- Moved recorder audio-duration metadata work after paste so completed text reaches the cursor sooner.
- Deferred the recorder history save until after transcription work starts so quick releases do not wait on SwiftData I/O before STT.
- Removed the fixed pre-paste delay after verified clipboard writes so completed text posts to the cursor sooner.
- Skipped cursor-context Accessibility reads when capitalization logic can prove the output text cannot change.
- Reduced the fixed autosend wait after paste from 500ms to 120ms while keeping a short guard before Return is posted.
- Blocked Auto low-battery local rolling-buffer preload before loading or running the local VAD, so the low-battery opt-out now fully disables buffer pre-run work.
- Claimed ready rolling-preload sessions before Power Mode configuration work so quick releases do not wait on model/session setup when the preloaded model and language still match.
- Tightened cached rolling-preload finalization so quick releases avoid pasting stale partial hypotheses when the local ASR pass is behind the live buffer.
- Let preload-only Special shortcut quick releases commit the rolling buffer instead of being canceled as short no-evidence presses.
- Preserved pre-roll-first streaming order without holding the recorder file lock through the whole pre-roll emission.
- Released the recorder file lock before forwarding queued live chunks after pre-roll streaming emission, reducing audio-thread blocking risk during startup handoff.
- Shortened the post-commit wait for local FluidAudio streaming finalization while preserving the longer cloud streaming wait.
- Moved the rolling-buffer VAD model picker into Rolling Buffer settings and clarified active-recording streaming text so buffer preload is not presented as generic live transcription.
- Overlapped rolling-preload quick-release active-window Power Mode application with STT finalization, so ready preloads no longer wait on window rule resolution before stopping the pre-run session.
- Started active-recording Power Mode rule resolution while audio hardware starts, so pre-roll/live buffered chunks wait less before fallback streaming setup.
- Removed a fixed post-STT wait before trigger-word AI enhancement starts.
- Removed fixed sleeps between simulated paste key events so completed text reaches the target app sooner.
- Kept warmed local STT resources after successful transcription so the next recording and rolling-buffer preload avoid an immediate teardown/reload cycle.
- Warmed the rolling-buffer VAD model before first speech when preload is eligible, so the first VAD trigger can start STT without paying model-load delay.
- Broadcast the restored startup transcription model so rolling-buffer preload can warm immediately after launch instead of waiting for a later settings change.
- Let preload-only quick releases commit an already-ready rolling-buffer STT session directly, without opening and stopping a new recorder session first.
- Let preload-only quick releases fall back to the current rolling-buffer audio snapshot directly, avoiding a recorder open/stop cycle when no pre-run session is claimable and the model supports saved-WAV transcription.
- Let local streaming models transcribe buffered rolling-audio snapshots immediately while the WAV writes in parallel for fallback/history, instead of waiting for the file before STT starts.
- Let very short active recordings that stop during startup replay their captured pre-roll/live PCM into the streaming session before falling back to batch transcription.
- Removed the preload-miss shortcut polling timeout by awaiting recorder startup before the immediate stop handoff.
- Replayed active-recording startup chunks into claimed rolling-preload sessions instead of dropping audio captured during the handoff.
- Preserved rolling-buffer audio for direct snapshot fallback when an existing pre-run session is canceled by a model, language, or finalization-policy mismatch.
- Preserved rolling audio collected while a preload-only quick release finalizes, so the next rolling preload does not restart from an empty lead-in after paste.
- Deferred quick-release rolling-preload history insertion until the post-paste save boundary, removing avoidable SwiftData work before the cursor paste starts.
- Warmed and cached word replacement rules outside the dictation hot path so quick-release paste no longer repeats the SwiftData lookup before every cursor paste.
- Deferred quick-release rolling-preload WAV writing until after cached stream finalization can start, while still waiting for the file before batch fallback or history metadata needs it.
- Added claim-to-paste latency tracing for rolling-preload quick releases so remaining delays can be measured from runtime logs.
- Included rolling-buffer preload mode, duration, VAD model, Auto policy, power state, and per-model preload state in diagnostic log exports.
- Added the last rolling-buffer quick-release claim strategy and claim-to-paste timing to diagnostics so packaged builds can show whether a release used ready preload, buffered audio snapshot, or missed the rolling path.
- Started Power Mode rule resolution on preload-only Special shortcut key-down, so quick releases avoid doing active-window and URL matching work after key-up.
- Cached prompt trigger-word eligibility and skipped prompt detection in the common no-trigger case, reducing transcript-ready-to-paste work.
- Pre-read cursor text context on preload-only Special shortcut key-down so contextual capitalization can avoid an Accessibility read immediately before quick-release paste.
- Pre-read clipboard restore context on preload-only Special shortcut key-down so restore-enabled quick releases avoid copying pasteboard data immediately before paste.
- Started quick-release rolling-buffer WAV writes immediately after claiming buffered audio so file I/O overlaps Power Mode resolution instead of running wholly after key-up validation.
- Used the claimed rolling-buffer PCM byte count for quick-release history duration, avoiding a post-paste AVFoundation metadata read.
- Deferred quick-release session metric recording until after the rolling-preload pipeline returns, so the app can leave the busy path before noncritical metric I/O.
- Deferred quick-release history persistence until after the rolling-preload pipeline returns and added returned/idle timing diagnostics for measuring the remaining post-paste tail.
- Deferred rolling-preload quick-release Power Mode/session restoration until after the engine marks idle, with diagnostics for the remaining session-finish tail.
- Skipped browser URL lookup during automatic Power Mode selection when no enabled URL rules exist, removing an avoidable pre-pipeline quick-release delay.
- Reduced the shortcut duplicate-press guard from 500ms to 80ms so valid back-to-back dictations are not ignored after the app is ready again.
- Skipped fallback streaming setup on immediate startup-stop recordings when the selected model can transcribe the saved WAV directly.
- Included rolling buffer preload mode, per-model opt-outs, Auto policy, duration, finalization, and VAD model settings in settings backup/import.
- Made the pre-run finalization opt-out also skip rolling-buffer STT pre-run work instead of warming an unusable session.
- Preserved the exact latest rolling-buffer preload audio when incoming chunks exceed or cross the configured duration boundary.
- Canceled warm rolling-preload sessions when the selected transcription language changes before the shortcut claims them.
- Woke quick-release claims as soon as rolling-preload startup resolves instead of polling until the next 10ms tick.

## v1.93 - 2026-06-15

- Improved cursor-context capitalization in editors that expose focused text but not an exact Accessibility cursor range.
- Made Special shortcuts fail closed when key evidence is unreliable, including secure text entry, held companion keys at Shift release, and very short no-evidence Shift presses, so hidden typing does not start dictation.
- Removed the Keyboard Shortcut setup card from App Permissions so the page only lists macOS permission grants.
- Renamed the main sidebar items to home, manual stt, past, models, and style.

## v1.92 - 2026-06-13

- Fixed Special shortcut typing detection for Karabiner mappings that emit bare function keys, including `Left Shift` + `X` and `Left Shift` + `S/D/F`.
- Fixed Special shortcut empty taps so they only paste the previous transcription after the current tap transcribes empty, instead of treating every short tap as paste-only.

## v1.91 - 2026-06-12

- Polished the app shell and dashboard with cleaner native glass surfaces, quieter accent use, and a less marketing-heavy metrics layout.
- Added cursor-context capitalization for dictation paste so mid-sentence inserts lower an auto-capitalized first word while sentence starts stay capitalized.
- Fixed Special shortcut typing detection so fast held Shift chords such as `Shift` down, `S` down, `Shift` up reliably cancel instead of pasting last text or committing an empty recording.
- Made Special shortcut empty taps paste the last transcription immediately instead of waiting for an empty recording to transcribe.
- Reused the PermissionFlow grant path for shortcut warning banners and metrics permission actions instead of direct System Settings deep links.

## v1.90 - 2026-06-10

- Released a branch that excludes the nine post-v1.82 ad-hoc packaging, entitlement-proof, notarized DMG, and PermissionFlow routing commits while preserving the later shortcut fixes.

## v1.89 - 2026-06-10

- Fixed Special shortcut flex-off handling so modifier-only shortcuts fail closed when the key-evidence event tap is unavailable.
- Updated the app bundle version metadata to 1.89 / 189 for the release artifact.

## v1.88 - 2026-06-10

- Added Special shortcut sub-settings for keydown preload behavior, key-down-only flex, and empty-tap paste-last fallback.

## v1.87 - 2026-06-09

- Fixed a post-keyup latency regression by finalizing the recording file without restarting the pre-roll AudioUnit on every stop.

## v1.86 - 2026-06-09

- Reissued the release as v1.86 after the v1.84 and v1.85 tags failed before publishing an app asset.
- Hid the menu bar icon by default for fresh installs while keeping Dock-icon hiding as a separate setting.
- Added Special shortcut mode as the fresh default with Left Shift: start recording on keydown, decide on keyup, and cancel typing cases where another key was released during the hold.

## v1.83 - 2026-06-08

- Switched release packaging to a simple Airpods-style ad-hoc signed `.app.zip` build.
- Removed dashes from the generated app wrapper and bundle name so macOS shows roma just talk.

## v1.82 - 2026-06-08

- Renamed the generated app wrapper and bundle name to roma-just-talk so macOS system dialogs use the fork name.

## v1.81 - 2026-06-08

- Replaced the README, source app icon, and menu bar logo with the roma-just-talk split-keyboard mark.
- Changed fresh defaults to Parakeet V2, menu-bar-only mode, muted sound feedback, and launch-at-login, with Parakeet auto-downloaded for the selected default.
- Renamed the visible app shell to roma-just-talk while leaving bundle identifiers and update infrastructure unchanged.

## v1.80 - 2026-06-01

- Added guided macOS permission grants with PermissionFlow.
- Fixed permission refresh so Microphone and Accessibility grants update while VoiceInk is running.
- Added an inline "Relaunch to Apply" path for macOS permissions that TCC grants but only activates for a fresh process.
- Made Screen Context optional and removed it from the required setup gate.
- Avoided disruptive direct Screen Recording prompts and removed the noisy floating screen-recording hint.
- Added GitHub Actions build artifact packaging for the macOS app.
- Updated the project pitch toward pre-roll voice capture and rolling voice buffer language.
