import Foundation
import RomaCore

@main
struct RomaProofAgent {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        switch arguments.first {
        case "doctor":
            printDoctor()
        case "pre-roll-proof":
            try writePreRollProof(arguments: Array(arguments.dropFirst()))
        case "windows-hotkey-doctor":
            printWindowsHotKeyDoctor()
        case "windows-hotkey-proof":
            try runWindowsHotKeyProof()
        case "windows-keyboard-hook-doctor":
            printWindowsKeyboardHookDoctor()
        case "windows-keyboard-hook-proof":
            try runWindowsKeyboardHookProof(arguments: Array(arguments.dropFirst()))
        case "windows-paste-doctor":
            printWindowsPasteDoctor()
        case "windows-paste-proof":
            try runWindowsPasteProof(arguments: Array(arguments.dropFirst()))
        case "windows-secret-doctor":
            printWindowsSecretDoctor()
        case "windows-secret-proof":
            try runWindowsSecretProof(arguments: Array(arguments.dropFirst()))
        case "windows-secret-save-from-env":
            try runWindowsSecretSaveFromEnv(arguments: Array(arguments.dropFirst()))
        case "windows-dictation-proof":
            try await runWindowsDictationProof(arguments: Array(arguments.dropFirst()))
        case "dictation-pipeline-proof":
            try await runDictationPipelineProof(arguments: Array(arguments.dropFirst()))
        case "miniaudio-capture-doctor":
            printMiniaudioCaptureDoctor()
        case "miniaudio-record-proof":
            try await runMiniaudioRecordProof(arguments: Array(arguments.dropFirst()))
        case "transcribe-proof-doctor":
            printTranscribeProofDoctor()
        case "transcribe-proof":
            try await runTranscribeProof(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func printDoctor() {
        print("platform=\(platformName)")
        print("swift_core=true")
        print("pre_roll_seconds=\(PreRollConfiguration().durationSeconds)")
        print("audio_format=pcm16_16000_mono")
        print("wav_writer=true")
        print("native_windows_adapters=false")
        print("windows_register_hotkey_adapter_source=true")
        print("windows_low_level_keyboard_hook_source=true")
        print("windows_paste_adapter_source=true")
        print("windows_dpapi_secret_store_source=true")
        print("miniaudio_capture_adapter_source=true")
        print("openai_compatible_transcription_source=true")
        print("transcription_output_filter_source=true")
        print("word_replacement_processor_source=true")
        print("windows_dictation_runtime_source=true")
        print("windows_dictation_proof_source=true")
    }

    private static func printWindowsHotKeyDoctor() {
        let hotKey = WindowsHotKey.proofToggle
        print("platform=\(platformName)")
        print("hotkey=\(hotKey.displayName)")
        print("hotkey_id=\(hotKey.id)")
        print("modifiers_raw=0x\(String(hotKey.modifiers.rawValue, radix: 16, uppercase: true))")
        print("virtual_key=0x\(String(hotKey.virtualKeyCode, radix: 16, uppercase: true))")
        print("api=RegisterHotKey")
        print("mode=toggle")
        print("permission_prompt=false")
        #if os(Windows)
        print("windows_hotkey_runtime=true")
        #else
        print("windows_hotkey_runtime=false")
        #endif
    }

    private static func runWindowsHotKeyProof() throws {
        let hotKey = WindowsHotKey.proofToggle

        #if os(Windows)
        print("waiting_for=\(hotKey.displayName)")
        try WindowsRegisterHotKeyProof.waitForSingleTrigger(hotKey: hotKey)
        print("hotkey_received=true")
        #else
        throw AgentError.unsupportedPlatform("windows-hotkey-proof requires Windows")
        #endif
    }

    private static func printWindowsKeyboardHookDoctor() {
        let chord = WindowsLowLevelKeyboardHookChord.proofHold
        print("platform=\(platformName)")
        print("hook=WH_KEYBOARD_LL")
        print("api=SetWindowsHookEx")
        print("chain_api=CallNextHookEx")
        print("mode=hold")
        print("key=\(chord.displayName)")
        print("virtual_key=0x\(String(chord.virtualKeyCode, radix: 16, uppercase: true))")
        print("required_modifiers=0x\(String(chord.requiredModifiers, radix: 16, uppercase: true))")
        print("message_loop_required=true")
        print("permission_prompt=false")
        print("runtime=\(WindowsLowLevelKeyboardHookProof.isRuntimeAvailable)")
    }

    private static func runWindowsKeyboardHookProof(arguments: [String]) throws {
        let timeoutMilliseconds = UInt32(try doubleValue(after: "--timeout", in: arguments, default: 15) * 1_000)
        let chord = WindowsLowLevelKeyboardHookChord.proofHold

        print("waiting_for_hold=\(chord.displayName)")
        let result = try WindowsLowLevelKeyboardHookProof.waitForHold(
            chord: chord,
            timeoutMilliseconds: timeoutMilliseconds
        )
        print("key_down=\(result.observedKeyDown)")
        print("key_up=\(result.observedKeyUp)")
        print("observed_events=0x\(String(result.observedEvents, radix: 16, uppercase: true))")
    }

    private static func printWindowsPasteDoctor() {
        let proofText = "roma just talk proof"
        let payload = WindowsClipboardPayload.cfUnicodeTextData(for: proofText)
        print("platform=\(platformName)")
        print("clipboard_format=CF_UNICODETEXT")
        print("clipboard_payload_bytes=\(payload.count)")
        print("input_api=SendInput")
        print("paste_chord=Ctrl+V")
        print("permission_prompt=false")
        print("integrity_limit=equal_or_lower")
        #if os(Windows)
        print("windows_paste_runtime=true")
        #else
        print("windows_paste_runtime=false")
        #endif
    }

    private static func printWindowsSecretDoctor() {
        print("platform=\(platformName)")
        print("secret_store=dpapi")
        print("storage=file")
        print("key_filename_format=utf8_hex_dpapi")
        print("api=CryptProtectData/CryptUnprotectData")
        print("permission_prompt=false")
        print("dpapi_runtime=\(WindowsDPAPIProtectedData.isRuntimeAvailable)")
    }

    private static func runWindowsSecretSaveFromEnv(arguments: [String]) throws {
        let directoryURL = URL(fileURLWithPath: try value(after: "--dir", in: arguments), isDirectory: true)
        let key = try value(after: "--key", in: arguments)
        let valueEnvironmentName = try value(after: "--value-env", in: arguments)

        guard isValidEnvironmentName(valueEnvironmentName) else {
            throw AgentError.invalidOptionValue("--value-env")
        }
        guard let secret = ProcessInfo.processInfo.environment[valueEnvironmentName],
              !secret.isEmpty else {
            throw AgentError.missingEnvironmentValue(valueEnvironmentName)
        }

        let store = WindowsDPAPISecretStore(directoryURL: directoryURL)
        try store.save(secret, forKey: key)

        print("secret_store=dpapi")
        print("directory=\(directoryURL.path)")
        print("key=\(key)")
        print("key_file=\(try WindowsDPAPISecretStore.fileName(forKey: key))")
        print("value_env=\(valueEnvironmentName)")
        print("stored=true")
    }

    private static func runWindowsSecretProof(arguments: [String]) throws {
        let directoryURL = URL(fileURLWithPath: try value(after: "--dir", in: arguments), isDirectory: true)
        let key = "proof-api-key"
        let value = "roma just talk proof secret"
        let store = WindowsDPAPISecretStore(directoryURL: directoryURL)

        try store.save(value, forKey: key)
        guard try store.get(key) == value else {
            throw AgentError.secretProofFailed("saved secret did not round-trip")
        }
        try store.delete(key)
        guard try store.get(key) == nil else {
            throw AgentError.secretProofFailed("deleted secret is still readable")
        }

        print("secret_store=dpapi")
        print("directory=\(directoryURL.path)")
        print("key_file=\(try WindowsDPAPISecretStore.fileName(forKey: key))")
        print("stored=true")
        print("retrieved=true")
        print("deleted=true")
    }

    private static func runWindowsPasteProof(arguments: [String]) throws {
        let text = try value(after: "--text", in: arguments)

        #if os(Windows)
        try WindowsPasteProof.pasteText(text)
        print("paste_sent=true")
        print("text_utf16_bytes=\(WindowsClipboardPayload.cfUnicodeTextData(for: text).count)")
        #else
        throw AgentError.unsupportedPlatform("windows-paste-proof requires Windows")
        #endif
    }

    private static func runWindowsDictationProof(arguments: [String]) async throws {
        let outputURL = URL(fileURLWithPath: try value(after: "--out", in: arguments))
        let seconds = try doubleValue(after: "--seconds", in: arguments, default: 2)
        let timeoutMilliseconds = UInt32(try doubleValue(after: "--timeout", in: arguments, default: 15) * 1_000)
        let endpointText = try value(after: "--endpoint", in: arguments)
        let modelName = try value(after: "--model", in: arguments)
        let apiKeySource = try makeAPIKeySource(arguments: arguments)
        let shouldPaste = arguments.contains("--paste")
        let shouldUseHoldHook = arguments.contains("--hold-hook")
        let wordReplacements = try replacementRules(from: arguments)
        let service = try makeTranscriptionService(
            endpointText: endpointText,
            apiKeySource: apiKeySource
        )
        let model = TranscriptionModelDescriptor(
            name: modelName,
            displayName: modelName,
            provider: .custom
        )
        let trigger: WindowsDictationTrigger = shouldUseHoldHook
            ? .hold(timeoutMilliseconds: timeoutMilliseconds)
            : .toggle(recordSeconds: seconds)
        print("recording_mode=\(shouldUseHoldHook ? "hold" : "toggle")")

        let result = try await WindowsDictationRuntime.run(
            WindowsDictationRuntimeRequest(
                outputURL: outputURL,
                model: model,
                language: optionalValue(after: "--language", in: arguments),
                prompt: optionalValue(after: "--prompt", in: arguments),
                shouldPaste: shouldPaste,
                textProcessing: DictationTextProcessingConfiguration(
                    wordReplacements: wordReplacements
                ),
                trigger: trigger
            ),
            transcriptionService: service
        ) { event in
            switch event {
            case .preRollBuffering:
                print("pre_roll_buffering=true")
            case .waitingForToggle(let displayName):
                print("waiting_for=\(displayName)")
            case .toggleReceived:
                print("hotkey_received=true")
            case .waitingForHoldKeyDown(let displayName):
                print("waiting_for_key_down=\(displayName)")
            case .holdKeyDown:
                print("hold_key_down=true")
            case .holdKeyUp:
                print("hold_key_up=true")
            }
        }
        let audio = result.session.recordedAudio

        print("wrote=\(audio.fileURL.path)")
        print("duration_seconds=\(String(format: "%.3f", audio.durationSeconds ?? 0))")
        print("included_pre_roll_seconds=\(audio.includedPreRollSeconds ?? 0)")
        print("sample_rate=\(audio.format.sampleRate)")
        print("channels=\(audio.format.channelCount)")
        printTranscriptionResult(
            result.transcription,
            endpointText: endpointText,
            modelName: modelName,
            apiKeySource: apiKeySource,
            audioURL: audio.fileURL
        )
        print("processed_transcript_length=\(result.processedText.count)")
        print("processed_transcript_text=\(oneLine(result.processedText))")
        print("word_replacements=\(wordReplacements.count)")

        print("paste_sent=\(shouldPaste)")
        print("paste_text_source=processed_transcript")
    }

    private static func runDictationPipelineProof(arguments: [String]) async throws {
        let outputURL = URL(fileURLWithPath: try value(after: "--out", in: arguments))
        let rawText = optionalValue(after: "--text", in: arguments) ?? "hmm... just talk."
        let wordReplacements = try replacementRules(from: arguments)
        let recorder = ProofRecorder()
        let textInsertion = ProofTextInsertion()
        let service = ProofTranscriptionService(text: rawText)
        let model = TranscriptionModelDescriptor(
            name: "proof-transcriber",
            displayName: "Proof Transcriber",
            provider: .custom
        )
        let pipeline = DictationPipeline(
            recorder: recorder,
            transcriptionService: service,
            textInsertion: textInsertion
        )

        try await recorder.startPreRollBuffering()
        let result = try await pipeline.runRecordingWindow(
            DictationPipelineRequest(
                outputURL: outputURL,
                model: model,
                shouldInsertTranscription: true,
                textProcessing: DictationTextProcessingConfiguration(
                    wordReplacements: wordReplacements
                )
            )
        ) {}

        print("wrote=\(result.session.recordedAudio.fileURL.path)")
        print("raw_transcript_length=\(rawText.count)")
        print("raw_transcript_text=\(oneLine(rawText))")
        print("processed_transcript_length=\(result.processedText.count)")
        print("processed_transcript_text=\(oneLine(result.processedText))")
        print("word_replacements=\(wordReplacements.count)")
        print("fake_paste_text=\(oneLine(await textInsertion.pastedText ?? ""))")
        print("paste_text_source=processed_transcript")
    }

    private static func printMiniaudioCaptureDoctor() {
        let recorder = MiniaudioCaptureRecorder()
        let format = recorder.preRollConfiguration.outputFormat
        print("platform=\(platformName)")
        print("library=miniaudio")
        print("library_version=\(MiniaudioCaptureRecorder.miniaudioVersion)")
        print("capture_format=pcm16")
        print("sample_rate=\(format.sampleRate)")
        print("channels=\(format.channelCount)")
        print("pre_roll_seconds=\(recorder.preRollConfiguration.durationSeconds)")
        print("native_capture_adapter=true")
        print("requires_microphone_access=true")
    }

    private static func printTranscribeProofDoctor() {
        print("platform=\(platformName)")
        print("transcription_client=openai-compatible")
        print("request_format=multipart/form-data")
        print("audio_field=file")
        print("response_field=text")
        print("api_key_source=environment_or_dpapi")
        print("network_required=true")
    }

    private static func runMiniaudioRecordProof(arguments: [String]) async throws {
        let outputURL = URL(fileURLWithPath: try value(after: "--out", in: arguments))
        let seconds = try doubleValue(after: "--seconds", in: arguments, default: 2)
        let recorder = MiniaudioCaptureRecorder()

        try await recorder.startPreRollBuffering()
        try await sleep(seconds: 1)
        try await recorder.startRecording(toOutputFile: outputURL)
        try await sleep(seconds: seconds)
        let audio = try await recorder.finishRecording()
        await recorder.stopCapture()

        print("wrote=\(audio.fileURL.path)")
        print("duration_seconds=\(String(format: "%.3f", audio.durationSeconds ?? 0))")
        print("included_pre_roll_seconds=\(audio.includedPreRollSeconds ?? 0)")
        print("sample_rate=\(audio.format.sampleRate)")
        print("channels=\(audio.format.channelCount)")
    }

    private static func writePreRollProof(arguments: [String]) throws {
        let outputURL = URL(fileURLWithPath: try value(after: "--out", in: arguments))
        let format = AudioChunkFormat.speechPCM16kMono
        let sampleRate = format.sampleRate
        let buffer = PCMPreRollBuffer(configuration: PreRollConfiguration(durationSeconds: 3, outputFormat: format))

        let beforeHotkeySamples = tone(frequency: 440, seconds: 2, sampleRate: sampleRate)
        let afterHotkeySamples = tone(frequency: 880, seconds: 1, sampleRate: sampleRate)

        buffer.append(samples: beforeHotkeySamples)
        let capturedPreRoll = buffer.snapshotSamples()
        let proofSamples = capturedPreRoll + afterHotkeySamples

        try PCM16WAVFile.write(samples: proofSamples, to: outputURL, format: format)

        print("wrote=\(outputURL.path)")
        print("pre_roll_samples=\(capturedPreRoll.count)")
        print("after_hotkey_samples=\(afterHotkeySamples.count)")
        print("sample_rate=\(sampleRate)")
        print("channels=\(format.channelCount)")
    }

    private static func runTranscribeProof(arguments: [String]) async throws {
        let audioURL = URL(fileURLWithPath: try value(after: "--audio", in: arguments))
        let endpointText = try value(after: "--endpoint", in: arguments)
        let modelName = try value(after: "--model", in: arguments)
        let apiKeySource = try makeAPIKeySource(arguments: arguments)

        let result = try await transcribeAudio(
            audioURL: audioURL,
            endpointText: endpointText,
            modelName: modelName,
            apiKeySource: apiKeySource,
            language: optionalValue(after: "--language", in: arguments),
            prompt: optionalValue(after: "--prompt", in: arguments)
        )
        printTranscriptionResult(
            result,
            endpointText: endpointText,
            modelName: modelName,
            apiKeySource: apiKeySource,
            audioURL: audioURL
        )
    }

    private static func transcribeAudio(
        audioURL: URL,
        endpointText: String,
        modelName: String,
        apiKeySource: TranscriptionAPIKeySource,
        language: String?,
        prompt: String?
    ) async throws -> TranscriptionResult {
        let service = try makeTranscriptionService(
            endpointText: endpointText,
            apiKeySource: apiKeySource
        )
        let model = TranscriptionModelDescriptor(
            name: modelName,
            displayName: modelName,
            provider: .custom
        )
        return try await service.transcribe(
            TranscriptionRequest(
                audioURL: audioURL,
                model: model,
                language: language,
                prompt: prompt
            )
        )
    }

    private static func makeTranscriptionService(
        endpointText: String,
        apiKeySource: TranscriptionAPIKeySource
    ) throws -> OpenAICompatibleTranscriptionService {
        guard let endpointURL = URL(string: endpointText), endpointURL.scheme != nil else {
            throw AgentError.invalidOptionValue("--endpoint")
        }
        let apiKey = try apiKeySource.resolve()

        return OpenAICompatibleTranscriptionService(
            configuration: OpenAICompatibleTranscriptionConfiguration(
                endpointURL: endpointURL,
                apiKey: apiKey
            )
        )
    }

    private static func printTranscriptionResult(
        _ result: TranscriptionResult,
        endpointText: String,
        modelName: String,
        apiKeySource: TranscriptionAPIKeySource,
        audioURL: URL
    ) {
        print("provider=openai-compatible")
        print("endpoint=\(endpointText)")
        print("model=\(modelName)")
        print("api_key_source=\(apiKeySource.kind)")
        print("api_key_ref=\(apiKeySource.reference)")
        print("audio=\(audioURL.path)")
        if let language = result.language {
            print("language=\(language)")
        }
        if let duration = result.durationSeconds {
            print("duration_seconds=\(String(format: "%.3f", duration))")
        }
        print("transcript_length=\(result.text.count)")
        print("transcript_text=\(oneLine(result.text))")
    }

    private static func makeAPIKeySource(arguments: [String]) throws -> TranscriptionAPIKeySource {
        try TranscriptionAPIKeySource.make(from: RomaCommandLineOptions(arguments))
    }

    private static func replacementRules(from arguments: [String]) throws -> [RomaWordReplacementRule] {
        try RomaCommandLineText.wordReplacementRules(from: RomaCommandLineOptions(arguments))
    }

    private static func value(after option: String, in arguments: [String]) throws -> String {
        try RomaCommandLineOptions(arguments).value(after: option)
    }

    private static func optionalValue(after option: String, in arguments: [String]) -> String? {
        RomaCommandLineOptions(arguments).optionalValue(after: option)
    }

    private static func values(after option: String, in arguments: [String]) throws -> [String] {
        try RomaCommandLineOptions(arguments).values(after: option)
    }

    private static func doubleValue(after option: String, in arguments: [String], default defaultValue: Double) throws -> Double {
        try RomaCommandLineOptions(arguments).doubleValue(after: option, default: defaultValue)
    }

    private static func sleep(seconds: Double) async throws {
        let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func tone(frequency: Double, seconds: Double, sampleRate: Int) -> [Int16] {
        let sampleCount = Int(Double(sampleRate) * seconds)
        return (0..<sampleCount).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
            let amplitude = sin(phase) * 12_000
            return Int16(amplitude)
        }
    }

    private static func printUsage() {
        print("usage:")
        print("  RomaProofAgent doctor")
        print("  RomaProofAgent pre-roll-proof --out proof.wav")
        print("  RomaProofAgent windows-hotkey-doctor")
        print("  RomaProofAgent windows-hotkey-proof")
        print("  RomaProofAgent windows-keyboard-hook-doctor")
        print("  RomaProofAgent windows-keyboard-hook-proof --timeout 15")
        print("  RomaProofAgent windows-paste-doctor")
        print("  RomaProofAgent windows-paste-proof --text \"roma just talk proof\"")
        print("  RomaProofAgent windows-secret-doctor")
        print("  RomaProofAgent windows-secret-proof --dir C:\\tmp\\roma-secrets")
        print("  RomaProofAgent windows-secret-save-from-env --dir C:\\tmp\\roma-secrets --key groq --value-env GROQ_API_KEY")
        print("  RomaProofAgent windows-dictation-proof --out proof.wav --seconds 2 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY [--replace \"original=replacement\"] [--paste]")
        print("  RomaProofAgent windows-dictation-proof --out proof.wav --hold-hook --timeout 15 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY [--paste]")
        print("  RomaProofAgent windows-dictation-proof --out proof.wav --seconds 2 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --secret-dir C:\\tmp\\roma-secrets [--paste]")
        print("  RomaProofAgent dictation-pipeline-proof --out proof.wav --text \"hmm... just talk.\" --replace \"just talk=roma-just-talk\"")
        print("  RomaProofAgent miniaudio-capture-doctor")
        print("  RomaProofAgent miniaudio-record-proof --out proof.wav --seconds 2")
        print("  RomaProofAgent transcribe-proof-doctor")
        print("  RomaProofAgent transcribe-proof --audio proof.wav --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY")
        print("  RomaProofAgent transcribe-proof --audio proof.wav --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq --secret-dir C:\\tmp\\roma-secrets")
    }

    private static var platformName: String {
        #if os(Windows)
        return "windows"
        #elseif os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #else
        return "unknown"
        #endif
    }

    private static func isValidEnvironmentName(_ value: String) -> Bool {
        RomaCommandLineText.isValidEnvironmentName(value)
    }

    private static func oneLine(_ text: String) -> String {
        RomaCommandLineText.oneLine(text)
    }
}

private enum AgentError: Error, CustomStringConvertible {
    case missingOption(String)
    case invalidOptionValue(String)
    case missingEnvironmentValue(String)
    case conflictingOptions(String)
    case secretProofFailed(String)
    case unsupportedPlatform(String)

    var description: String {
        switch self {
        case .missingOption(let option):
            return "missing required option \(option)"
        case .invalidOptionValue(let option):
            return "invalid value for option \(option)"
        case .missingEnvironmentValue(let name):
            return "missing environment value \(name)"
        case .conflictingOptions(let message):
            return "conflicting options: \(message)"
        case .secretProofFailed(let message):
            return message
        case .unsupportedPlatform(let message):
            return message
        }
    }
}

private final class ProofRecorder: RollingRecorder, @unchecked Sendable {
    var onAudioChunk: (@Sendable (Data) -> Void)?
    let preRollConfiguration = PreRollConfiguration()
    private var outputURL: URL?

    func startPreRollBuffering() async throws {}

    func startRecording(toOutputFile url: URL) async throws {
        outputURL = url
    }

    func finishRecording() async throws -> RecordedAudio {
        guard let outputURL else {
            throw AgentError.invalidOptionValue("--out")
        }

        let samples = Array(repeating: Int16(0), count: preRollConfiguration.outputFormat.sampleRate / 10)
        try PCM16WAVFile.write(
            samples: samples,
            to: outputURL,
            format: preRollConfiguration.outputFormat
        )
        return RecordedAudio(
            fileURL: outputURL,
            format: preRollConfiguration.outputFormat,
            durationSeconds: 0.1,
            includedPreRollSeconds: preRollConfiguration.durationSeconds
        )
    }

    func stopCapture() async {
        outputURL = nil
    }
}

private struct ProofTranscriptionService: TranscriptionService {
    var text: String

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(text: text)
    }
}

private actor ProofTextInsertion: TextInsertion {
    private(set) var pastedText: String?

    func pasteAtCursor(_ text: String) async throws {
        pastedText = text
    }
}
