# Windows Port Direction

Goal: make roma-just-talk work on Windows with the least duplicated code, while keeping the product thesis intact: speak before the hotkey, keep a short pre-roll mic buffer, then commit the captured thought to text.

This is not a SwiftUI-to-Windows port. Swift can run on Windows, but the current app shell is macOS-bound through SwiftUI, AppKit, SwiftData, AVFoundation, CoreAudio, Carbon, ApplicationServices, ScreenCaptureKit, Security, Sparkle, and other Apple frameworks. The low-redundancy path is a shared Swift core plus platform adapters.

## Decision

Build toward this shape:

```text
roma-just-talk
  RomaCore/
    recording state machine
    transcription model/provider interfaces
    cloud transcription providers
    whisper.cpp bridge interface
    text cleanup, insertion polish, dictionary logic
    settings and history protocols
  macOS app/
    existing SwiftUI/AppKit shell
    CoreAudio recorder adapter
    CGEvent/NSPasteboard paste adapter
    NSEvent/CGEventTap shortcut adapter
    SwiftData/Keychain/UserDefaults storage adapters
  Windows app/
    RomaWindowsAgent first, then tray or small desktop shell
    miniaudio/WASAPI recorder adapter
    Win32 hotkey/hook adapter
    Win32 clipboard + SendInput paste adapter
    DPAPI/plain-settings storage adapter
```

The first Windows target should be an agent/proof executable, not a full re-created UI. It only needs to prove:

1. Start a rolling pre-roll mic buffer.
2. Press a global shortcut.
3. Include audio from before the shortcut in the WAV/PCM stream.
4. Transcribe through cloud STT or whisper.cpp.
5. Paste into Notepad or another normal-integrity app.

After that works, add tray/settings/history UI.

## Existing Seams

Reusable now:

- `TranscriptionService` already abstracts file-based STT.
- Cloud provider code is mostly HTTP + model metadata.
- `TranscriptionOutputFilter`, formatter, prompt detection, word replacements, and dictionary behavior are product logic.
- `PCMPreRollBuffer` now lives in `RomaCore` as Foundation-only circular PCM storage.
- `PCM16WAVFile` now lives in `RomaCore` as Foundation-only PCM16 WAV output for proof recordings.
- `MiniaudioCaptureRecorder` now lives in `RomaCore` and feeds miniaudio capture frames into the shared pre-roll/WAV path.
- `OpenAICompatibleTranscriptionService` now lives in `RomaCore` as a Foundation-only multipart HTTP proof path for OpenAI-compatible cloud STT.
- `WhisperCLITranscriptionService` now lives in `RomaCore` as a Foundation-only bridge to the proven `whisper-cli` executable and ggml model files.
- `DictationPipeline` now lives in `RomaCore` as the shared record -> transcribe -> shared cleanup -> optional paste orchestration.
- `RomaTranscriptionOutputFilter` now lives in `RomaCore` as the shared Foundation-only post-STT cleanup and insertion-polish path.
- `RomaWordReplacementProcessor` now lives in `RomaCore` as the shared dictionary replacement matching path.
- `WindowsDictationRuntime` now lives in `RomaCore` as the reusable Windows hotkey/hook -> miniaudio -> STT -> cleanup/replacement -> optional paste composition.
- `RomaWindowsAgent` is the first user-facing Windows executable. It stays thin and calls `WindowsDictationRuntime` instead of duplicating recorder/STT/paste orchestration.
- `RomaWindowsAgentConfiguration` now lives in `RomaCore` as the reusable JSON settings shape for endpoint, model, key source, trigger mode, paste, clipboard restore, language/prompt, and replacement defaults.
- `WindowsHotKey.proofToggle` and the Windows-only `WindowsRegisterHotKeyProof` source define the first `RegisterHotKey` toggle proof path.
- `WindowsLowLevelKeyboardHookProof` now defines the first `WH_KEYBOARD_LL` hold-to-talk keydown/keyup proof path.
- `WindowsClipboardPayload` and the Windows-only `WindowsPasteProof` source define the first `CF_UNICODETEXT` plus `SendInput` paste proof path.
- `WindowsPermissionSurface` now lives in `RomaCore` as the shared permission/native-limit descriptor for laptop proof output.
- `WindowsDPAPISecretStore` now lives in `RomaCore` as the first Windows API-key storage adapter.
- `CoreAudioRecorder` already outputs the right streaming shape: 16 kHz mono Int16 PCM chunks and a WAV file with a 3 second pre-roll buffer, and now reuses `RomaCore.PCMPreRollBuffer`.

Not reusable without adapters:

- `VoiceInkEngine` owns SwiftData, AppKit notifications, macOS permission prompts, recorder UI, storage, and paste side effects.
- `TranscriptionPipeline` calls SwiftData directly and pastes through `CursorPaster`.
- `ShortcutMonitor` is macOS-only: `NSEvent`, `CGEventTap`, `AXIsProcessTrusted`, `CGPreflightListenEventAccess`.
- `CursorPaster` is macOS-only: `NSPasteboard`, AppleScript, `CGEvent`, Accessibility.
- `CoreAudioRecorder` is macOS-only: CoreAudio AudioUnit and ExtAudioFile.
- `KeychainService` is macOS-only outside local builds: Security framework.

## Adapter Interfaces To Extract First

Keep these narrow. Each Windows implementation should satisfy the same behavior the macOS app already expects.

```swift
protocol RollingRecorder {
    var onAudioChunk: (@Sendable (Data) -> Void)? { get set }
    func startPreRollBuffering() async throws
    func startRecording(toOutputFile url: URL) async throws
    func finishRecording() async throws
    func stopCapture() async
}

protocol ShortcutListening {
    func start(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) throws
    func stop()
}

protocol TextInsertion {
    func pasteAtCursor(_ text: String) async throws
}

protocol PermissionStatusProviding {
    func microphoneStatus() -> PermissionStatus
    func shortcutStatus() -> PermissionStatus
    func pasteStatus() -> PermissionStatus
}

protocol SecretStoring {
    func save(_ value: String, forKey key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}
```

The first refactor should not move every file. Start by making `TranscriptionPipeline` return a result instead of directly saving and pasting, then wrap platform actions outside core.

## Proven Windows Pieces

These are the lowest-redo candidates because they map directly to the behavior already in the macOS app.

| Need | Windows path | Why |
| --- | --- | --- |
| Rolling mic capture | miniaudio first, raw WASAPI second | miniaudio is single-file C, supports capture, WASAPI, Core Audio, conversion, and ring buffers. `RomaProofAgent miniaudio-record-proof` is the first source path for this. |
| Local Whisper | whisper.cpp CLI first, C API/DLL second | Current app already uses whisper.cpp; upstream supports Windows with MSVC/MinGW and CPU/GPU paths. `WhisperCLITranscriptionService` keeps this as an external executable seam before linking the C++ engine into Swift. |
| Cloud STT | Existing OpenAI-compatible provider logic behind a portable API-key source | Low native surface; fastest proof if local model packaging is not ready. `RomaProofAgent transcribe-proof` is the first source path for this. |
| Global shortcut | `RegisterHotKey` for toggle proof | Simple system-wide hotkey, enough for MVP toggle mode. `RomaProofAgent windows-hotkey-proof` is the first source path for this. |
| Push-to-talk keydown/keyup | `WH_KEYBOARD_LL` after toggle proof | Needed for hold behavior. `RomaProofAgent windows-keyboard-hook-proof` is the first source path for this and still keeps the hook work in a native adapter. |
| Paste | Win32 clipboard plus `SendInput` Ctrl+V | Same MVP behavior as macOS paste: put text on the clipboard, synthesize the paste command, then restore the previous text clipboard after a delay if the clipboard still contains the dictated text. `RomaProofAgent windows-paste-proof` is the first source path for this. |
| Secrets | DPAPI | Windows user-bound secret storage equivalent for API keys. `RomaProofAgent windows-secret-proof` is the first source path for this. |
| UI | tray/small shell first; Tauri optional later | Avoid re-creating all SwiftUI views before the actual Windows native behavior is proven. |

## Permission Model

Windows is not macOS TCC.

- Microphone: users need global microphone access and desktop-app microphone access enabled. Individual toggles are mainly Store/MSIX/package-identity flows.
- Global hotkey: `RegisterHotKey` generally has no permission prompt, but it can conflict with existing hotkeys.
- Low-level hooks: `WH_KEYBOARD_LL` can work for desktop apps, but requires a message loop and careful cleanup. Use only when hold-to-talk is required.
- Paste/input injection: `SendInput` can be blocked by integrity boundaries. A normal app should not expect to paste into elevated/admin apps.
- Clipboard restore: the Windows MVP restores the previous text clipboard only. It does not yet preserve every non-text clipboard format.
- Screen/window context: skip for MVP. Screen OCR/context has a separate permission and product-risk surface on both platforms.

Minimum Windows MVP permission surface: microphone + shortcut + clipboard/paste. Do not start with screen capture, browser URL detection, media control, or app-aware modes.
Run `swift run RomaProofAgent windows-permission-doctor` or `RomaWindowsAgent doctor` to print the shared permission surface before laptop smoke tests.

## First Implementation Plan

1. Add `RomaCore` as a SwiftPM package or internal package folder. The initial package now exists under `RomaCore/` with portable interfaces for recorder, shortcut, paste, permissions, secrets, settings, and transcription services, plus shared pre-roll PCM buffering, PCM16 WAV output, miniaudio capture, Windows hotkey/paste proof metadata, and a portable `RomaProofAgent` executable.
2. Move only pure types and services first:
   - `TranscriptionService`
   - model/provider types that do not import SwiftData/AppKit
   - cloud provider request builders
   - text cleanup and insertion polish
   - result structs for `TranscriptionPipeline`
3. Replace direct platform calls with injected protocols:
   - storage instead of SwiftData in core
   - settings instead of `UserDefaults`
   - paste instead of `CursorPaster`
   - notifications instead of `NotificationManager`
4. Route command-line proof flows through `DictationPipeline` before building UI. This keeps Windows from growing a second orchestration path.
5. Add macOS adapters that call the current implementations. This proves extraction without behavior change.
6. Add a Windows proof target:
   - miniaudio recorder shim emits 16 kHz mono Int16 PCM and WAV
   - `RegisterHotKey` toggles start/stop
   - cloud STT first, or whisper.cpp CLI/DLL if model packaging is ready
   - Win32 clipboard + `SendInput` pastes text
   - `windows-dictation-proof` composes those pieces into one hotkey -> pre-roll WAV -> STT -> optional paste proof
7. Use `RomaWindowsAgent` as the first laptop-usable Windows entrypoint, then add tray/settings UI around the same runtime.

## Windows Proof Checklist

Run on a Windows laptop or Windows CI runner with audio loopback/mock where possible:

```powershell
cd RomaCore
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1
powershell -ExecutionPolicy Bypass -File .\Scripts\package-windows-agent.ps1 -OutputDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -DoctorOnly
```

For the foreground-dependent proofs:

```powershell
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveHotkey
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractivePaste
```

Useful script options:

- `-SkipMic` skips real microphone capture when Windows microphone access is not ready.
- `-RecordSeconds 5` changes the live mic capture window.
- `-OutputDir C:\tmp\roma-proof` writes proof WAVs somewhere explicit.
- `-TranscribeEndpoint https://api.groq.com/openai/v1/audio/transcriptions -TranscribeModel whisper-large-v3-turbo -TranscribeApiKeyEnv GROQ_API_KEY` runs the OpenAI-compatible transcription proof.
- `-TranscribeApiKeyName groq` stores `-TranscribeApiKeyEnv` into DPAPI and uses the stored key for transcription.
- `-WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin` writes the user-facing Windows agent config for local whisper.cpp transcription.
- `-TranscribeAudio C:\tmp\proof.wav` uses an existing WAV for transcription, useful with `-SkipMic`.
- `-TranscribeLanguage en` and `-TranscribePrompt "roma just talk"` pass optional STT hints.
- `-WordReplacement "just talk=roma-just-talk"` adds a proof-time dictionary replacement before optional paste.
- `-RunInteractiveDictation` waits for `Ctrl+Shift+R`, records with pre-roll, transcribes, and writes `dictation-proof.wav`.
- `-RunInteractiveWindowsAgent` writes `windows-agent.json`, then runs the user-facing `RomaWindowsAgent dictate --config windows-agent.json` command and writes `windows-agent-dictation.wav`.
- `-UseHoldHook` makes interactive dictation use `WH_KEYBOARD_LL`: recording starts on `Ctrl+Shift+R` keydown and stops on keyup.
- `-HoldTimeoutSeconds 15` changes the keydown/keyup wait timeout for hold-hook dictation.
- `-PasteDictation` adds the final paste step to the interactive dictation proof.

Packaged artifact smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\prove-windows-agent-artifact.ps1 -PackageDir C:\tmp\roma-windows-agent -DoctorOnly
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -RunDictation -PasteDictation
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\smoke-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -RunDictation -PasteDictation
```

The first command proves the packaged `RomaWindowsAgent.exe doctor` and `write-config` path without SwiftPM. The second command validates the packaged artifact, manifest, required scripts, and Swift runtime DLL before any laptop install. The third command is the laptop proof: hold `Ctrl+Shift+R`, speak, release, transcribe, and optionally paste through the same config path. The fourth command first saves `GROQ_API_KEY` into the packaged agent's DPAPI secret store as `groq`, then writes config using the stored key name.

`package-windows-agent.ps1` copies Swift runtime DLLs from the PATH directory containing `swiftCore.dll` into the artifact. On Windows, packaging fails if no runtime DLLs are copied or if `swiftCore.dll` is missing from the artifact; that keeps CI from passing only because the runner has Swift on `PATH`.

No-admin install proof:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\install-windows-agent.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -RunDictation -PasteDictation
```

By default this installs into `%LOCALAPPDATA%\roma-just-talk\agent` and smokes the installed copy with an install-local smoke config. Passing `-WhisperCLI` and `-WhisperModel` proves the same installed config path for local whisper.cpp without API-key storage. When you pass real endpoint/model/key options or `-RunDictation`, the installer stores config at `%APPDATA%\roma-just-talk\windows-agent.json`. Pass `-InstallDir` and `-ConfigPath` to prove a temp install path in CI.

The installer also copies `run-windows-agent.ps1`. Use it to start the installed agent from the saved config, or pass endpoint/model/key options once to write config and immediately run dictation:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1"
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -PasteDictation
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\roma-just-talk\agent\run-windows-agent.ps1" -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin -PasteDictation
```

Artifact-to-laptop proof wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\prove-windows-agent-artifact.ps1 -PackageDir C:\tmp\roma-windows-agent -Endpoint https://api.groq.com/openai/v1/audio/transcriptions -Model whisper-large-v3-turbo -ApiKeyEnv GROQ_API_KEY -ApiKeyName groq -UseHoldHook -RunDictation -PasteDictation -CreateShortcut -ProofReportPath C:\tmp\roma-windows-agent-proof.json
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\check-windows-proof-report.ps1 -ProofReportPath C:\tmp\roma-windows-agent-proof.json -ExpectedMode cloud -RequireInstall -RequireShortcut -RequireHoldHook -RequireCloudConfig -RequireDictation -RequirePaste
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\prove-windows-agent-artifact.ps1 -PackageDir C:\tmp\roma-windows-agent -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin -UseHoldHook -RunDictation -PasteDictation -CreateShortcut -ProofReportPath C:\tmp\roma-windows-agent-local-whisper-proof.json
powershell -ExecutionPolicy Bypass -File C:\tmp\roma-windows-agent\check-windows-proof-report.ps1 -ProofReportPath C:\tmp\roma-windows-agent-local-whisper-proof.json -ExpectedMode local-whisper -RequireInstall -RequireShortcut -RequireHoldHook -RequireWhisperConfig -RequireDictation -RequirePaste
```

The wrapper validates the packaged artifact and manifest, runs the packaged agent doctor, delegates install/config/shortcut work to `install-windows-agent.ps1`, then verifies the installed launcher with `-DoctorOnly`. It is the preferred laptop handoff command because it reuses the proven scripts instead of adding a second install path.
Pass `-ProofReportPath` to leave a JSON proof record with package/install paths, Windows version, config output path, dictation/paste flags, non-secret transcription config fields, and file existence/byte counts for the agent, installed launcher, optional shortcut, local whisper files, and dictation WAV when `-RunDictation` creates one. Run `check-windows-proof-report.ps1` afterward to fail fast if the expected mode, cloud/local-whisper config, hold-hook config, install, shortcut, dictation WAV, or paste proof fields are missing.

For CI or artifact smoke only, pass `-UsePackagedWhisperMock` instead of explicit `-WhisperCLI` and `-WhisperModel`. The wrapper reads the artifact-local `whisper_cli_mock` entry from `manifest.txt` and uses the packaged agent executable as the mock model file; laptop proof should still pass real whisper.cpp paths or a real cloud endpoint/model.

Add `-CreateShortcut` to `install-windows-agent.ps1` after passing real endpoint/model/API-key args, whisper-cli/model args, or `-SkipSmoke` with an existing `-ConfigPath`. The installer refuses to create a user shortcut for the default mock smoke config. The shortcut points at the same config path the installer just smoked. CI package smoke uses the proof-only `-AllowSmokeShortcut` path, creates the shortcut in a temporary folder, verifies its arguments include that config, and verifies the launcher with `-DoctorOnly`.

Windows agent config:

```powershell
swift run RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent write-config --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --hold-hook --paste --clipboard-restore-delay 2 --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent dictate
swift run RomaWindowsAgent write-config --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --hold-hook --paste --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent dictate
```

Use `--config C:\tmp\roma-agent.json` on `write-config` and `dictate` when you want an explicit config path instead of `%APPDATA%\roma-just-talk\windows-agent.json`. Paste restores the previous text clipboard by default; use `--no-restore-clipboard` to leave dictated text on the clipboard, or `--clipboard-restore-delay 0` for smoke tests that should not wait.

CI proof:

- `.github/workflows/romacore.yml` builds `RomaCore` on macOS and Windows.
- The Windows job verifies Visual Studio C++ tools, installs the official Swift toolchain with `winget install --id Swift.Toolchain`, then runs `windows-proof.ps1 -SkipMic`.
- CI is noninteractive, so it proves Windows compilation, PowerShell parse validity, pre-roll/WAV output, shared cleanup/replacement/paste text processing, DPAPI secret round-trip, stored-key transcription against a local mock STT endpoint, local `whisper-cli` argument shaping plus mock process execution, reusable `RomaWindowsAgent` config writing, and hotkey/paste doctor paths. It does not prove real microphone permission, real hotkey delivery, local whisper inference, or paste into Notepad.
- CI also runs `package-windows-agent.ps1`, requires Swift runtime DLLs in the artifact, packages the proof-only `RomaWhisperCLIMock.exe`, verifies the packaged `RomaWindowsAgent.exe` through `smoke-windows-agent.ps1`, asserts generated JSON config for both cloud endpoint/model and local whisper-cli modes, proves no-admin installs for both cloud/default and local whisper-cli config into temp directories, verifies the installed launcher with `-DoctorOnly`, creates a proof-only mock shortcut in a temp folder, creates a real local-whisper shortcut in a separate temp folder, verifies both shortcuts point at their smoked configs, records the install config and shortcut paths in `manifest.txt`, packages and executes `prove-windows-agent-artifact.ps1 -DoctorOnly`, runs the wrapper through the artifact-local manifest-backed local-whisper mock install and shortcut proof, writes and validates a JSON wrapper proof report, and uploads a `roma-windows-agent` artifact for laptop smoke tests.

Raw command sequence:

```powershell
swift --version
swift build
swift run RomaCoreChecks
swift run RomaProofAgent doctor
swift run RomaWindowsAgent doctor
swift run RomaProofAgent pre-roll-proof --out core-proof.wav
swift run RomaProofAgent miniaudio-capture-doctor
swift run RomaProofAgent miniaudio-record-proof --out mic-proof.wav --seconds 2
swift run RomaProofAgent transcribe-proof-doctor
swift run RomaProofAgent whisper-cli-doctor
swift run RomaProofAgent whisper-cli-proof --audio mic-proof.wav --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --language en --prompt "roma just talk"
swift run RomaProofAgent dictation-pipeline-proof --out pipeline-proof.wav --text "hmm... just talk." --replace "just talk=roma-just-talk"
swift run RomaProofAgent dictation-pipeline-proof --out mid-sentence-proof.wav --text "Model." --preceding-text "...so this"
swift run RomaProofAgent transcribe-proof --audio mic-proof.wav --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY
swift run RomaProofAgent windows-hotkey-doctor
swift run RomaProofAgent windows-hotkey-proof
swift run RomaProofAgent windows-keyboard-hook-doctor
swift run RomaProofAgent windows-keyboard-hook-proof --timeout 15
swift run RomaProofAgent windows-paste-doctor
swift run RomaProofAgent windows-paste-proof --text "roma just talk proof"
swift run RomaProofAgent windows-permission-doctor
swift run RomaProofAgent windows-secret-doctor
swift run RomaProofAgent windows-secret-proof --dir C:\tmp\roma-secrets
swift run RomaProofAgent windows-secret-save-from-env --dir C:\tmp\roma-secrets --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY
swift run RomaWindowsAgent write-config --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --hold-hook --paste --clipboard-restore-delay 2 --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent write-config --whisper-cli C:\path\whisper-cli.exe --whisper-model C:\path\ggml-base.en.bin --hold-hook --paste --replace "just talk=roma-just-talk"
swift run RomaWindowsAgent dictate
swift run RomaWindowsAgent dictate --hold-hook --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --paste --no-restore-clipboard
swift run RomaProofAgent transcribe-proof --audio mic-proof.wav --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --secret-dir C:\tmp\roma-secrets
swift run RomaProofAgent windows-dictation-proof --out dictation-proof.wav --seconds 2 --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY --replace "just talk=roma-just-talk" --paste
swift run RomaProofAgent windows-dictation-proof --out hold-dictation-proof.wav --hold-hook --timeout 15 --endpoint https://api.groq.com/openai/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env GROQ_API_KEY --paste
powershell -ExecutionPolicy Bypass -File .\Scripts\package-windows-agent.ps1 -OutputDir C:\tmp\roma-windows-agent
```

User-facing Windows agent proof:

```powershell
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveWindowsAgent -UseHoldHook -PasteDictation -TranscribeEndpoint https://api.groq.com/openai/v1/audio/transcriptions -TranscribeModel whisper-large-v3-turbo -TranscribeApiKeyEnv GROQ_API_KEY -WordReplacement "just talk=roma-just-talk"
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1 -RunInteractiveWindowsAgent -UseHoldHook -PasteDictation -WhisperCLI C:\path\whisper-cli.exe -WhisperModel C:\path\ggml-base.en.bin -WordReplacement "just talk=roma-just-talk"
```

Manual proof:

- Start the agent.
- Say "before hotkey".
- Toggle proof: press the configured shortcut, say "after hotkey", and wait for the configured duration.
- Hold proof: hold the configured shortcut while speaking, then release it.
- Verify `proof.wav` contains both phrases.
- Verify transcription contains both phrases.
- Verify paste lands in Notepad.

Do not claim Windows support until the audio, transcription, and paste proof all pass on a real Windows machine.

## What Not To Do

- Do not rewrite the product from scratch in Electron just to get a Windows window.
- Do not port every SwiftUI settings/history screen before recording and paste work.
- Do not make Windows support depend on screen capture or app-aware context first.
- Do not treat local-vs-cloud STT as the thesis. The thesis is pre-roll capture and speak-before-hotkey.
- Do not make macOS worse while extracting core; macOS stays the proving ground until Windows proof exists.

## References

- Swift Windows install: https://www.swift.org/install/windows/
- Swift Package Manager: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/
- miniaudio manual: https://miniaud.io/docs/manual/index.html
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- WASAPI capture: https://learn.microsoft.com/en-us/windows/win32/coreaudio/capturing-a-stream
- RegisterHotKey: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey
- SetWindowsHookEx: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexa
- LowLevelKeyboardProc: https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc
- KBDLLHOOKSTRUCT: https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct
- CallNextHookEx: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-callnexthookex
- SendInput: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- CryptProtectData: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata
- CryptUnprotectData: https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptunprotectdata
- Windows microphone privacy: https://support.microsoft.com/en-us/windows/windows-camera-microphone-and-privacy-a83257bc-e990-d54a-d212-b5e41beba857
