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
    tray or small desktop shell
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
- `WindowsHotKey.proofToggle` and the Windows-only `WindowsRegisterHotKeyProof` source define the first `RegisterHotKey` toggle proof path.
- `WindowsClipboardPayload` and the Windows-only `WindowsPasteProof` source define the first `CF_UNICODETEXT` plus `SendInput` paste proof path.
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
| Local Whisper | whisper.cpp C API or CLI/DLL | Current app already uses whisper.cpp; upstream supports Windows with MSVC/MinGW and CPU/GPU paths. |
| Cloud STT | Existing provider logic behind a portable API-key store and vocabulary source | Low native surface; fastest proof if local model packaging is not ready. |
| Global shortcut | `RegisterHotKey` for toggle proof | Simple system-wide hotkey, enough for MVP toggle mode. `RomaProofAgent windows-hotkey-proof` is the first source path for this. |
| Push-to-talk keydown/keyup | `WH_KEYBOARD_LL` only after toggle proof | Needed for modifier-only or hold behavior, but higher risk and more AV/security sensitivity. |
| Paste | Win32 clipboard plus `SendInput` Ctrl+V | Same behavioral model as macOS: put text on clipboard, synthesize paste command, restore clipboard if enabled. `RomaProofAgent windows-paste-proof` is the first source path for this. |
| Secrets | DPAPI | Windows user-bound secret storage equivalent for API keys. |
| UI | tray/small shell first; Tauri optional later | Avoid re-creating all SwiftUI views before the actual Windows native behavior is proven. |

## Permission Model

Windows is not macOS TCC.

- Microphone: users need global microphone access and desktop-app microphone access enabled. Individual toggles are mainly Store/MSIX/package-identity flows.
- Global hotkey: `RegisterHotKey` generally has no permission prompt, but it can conflict with existing hotkeys.
- Low-level hooks: `WH_KEYBOARD_LL` can work for desktop apps, but requires a message loop and careful cleanup. Use only when hold-to-talk is required.
- Paste/input injection: `SendInput` can be blocked by integrity boundaries. A normal app should not expect to paste into elevated/admin apps.
- Screen/window context: skip for MVP. Screen OCR/context has a separate permission and product-risk surface on both platforms.

Minimum Windows MVP permission surface: microphone + shortcut + clipboard/paste. Do not start with screen capture, browser URL detection, media control, or app-aware modes.

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
4. Add macOS adapters that call the current implementations. This proves extraction without behavior change.
5. Add a Windows proof target:
   - miniaudio recorder shim emits 16 kHz mono Int16 PCM and WAV
   - `RegisterHotKey` toggles start/stop
   - cloud STT first, or whisper.cpp CLI/DLL if model packaging is ready
   - Win32 clipboard + `SendInput` pastes text
6. Only after the proof target works, build tray/settings UI.

## Windows Proof Checklist

Run on a Windows laptop or Windows CI runner with audio loopback/mock where possible:

```powershell
cd RomaCore
powershell -ExecutionPolicy Bypass -File .\Scripts\windows-proof.ps1
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

Raw command sequence:

```powershell
swift --version
swift test
swift run RomaProofAgent doctor
swift run RomaProofAgent pre-roll-proof --out core-proof.wav
swift run RomaProofAgent miniaudio-capture-doctor
swift run RomaProofAgent miniaudio-record-proof --out mic-proof.wav --seconds 2
swift run RomaProofAgent windows-hotkey-doctor
swift run RomaProofAgent windows-hotkey-proof
swift run RomaProofAgent windows-paste-doctor
swift run RomaProofAgent windows-paste-proof --text "roma just talk proof"
roma-agent.exe doctor
roma-agent.exe record-proof --seconds-before-hotkey 2 --seconds-after-hotkey 2 --out proof.wav
roma-agent.exe transcribe-proof --audio proof.wav
roma-agent.exe paste-proof --text "roma just talk proof"
```

Manual proof:

- Start the agent.
- Say "before hotkey".
- Press the configured shortcut.
- Say "after hotkey".
- Stop recording.
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
- SendInput: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- Windows microphone privacy: https://support.microsoft.com/en-us/windows/windows-camera-microphone-and-privacy-a83257bc-e990-d54a-d212-b5e41beba857
