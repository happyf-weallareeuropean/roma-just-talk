import Foundation
import RomaCore

@main
struct RomaWindowsAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        do {
            try await run(arguments: arguments)
        } catch {
            printError(error)
            exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        switch arguments.first {
        case "doctor":
            printDoctor()
        case "dictate":
            try await runDictation(arguments: Array(arguments.dropFirst()))
        case "save-key-from-env":
            try saveKeyFromEnvironment(arguments: Array(arguments.dropFirst()))
        case "write-config":
            try writeConfiguration(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func printDoctor() {
        print("agent=roma-windows-agent")
        print("platform=\(platformName)")
        print("runtime_available=\(WindowsDictationRuntime.isRuntimeAvailable)")
        print("dictation_runtime=WindowsDictationRuntime")
        print("recorder=miniaudio")
        print("audio_format=pcm16_16000_mono")
        print("pre_roll_seconds=\(PreRollConfiguration().durationSeconds)")
        print("toggle_hotkey=RegisterHotKey Ctrl+Shift+R")
        print("hold_hook=WH_KEYBOARD_LL Ctrl+Shift+R")
        print("paste=win32_clipboard_sendinput")
        print("secret_store=dpapi")
        print("config_default=\(RomaWindowsAgentConfiguration.defaultURL().path)")
        print("minimum_permission_surface=microphone,hotkey,clipboard")
        print("screen_capture=false")
    }

    private static func runDictation(arguments: [String]) async throws {
        let options = RomaCommandLineOptions(arguments)
        let configuration = try loadConfiguration(from: options)
            .applyingOverrides(from: options)
        let outputURL = URL(fileURLWithPath: configuration.outputPath ?? defaultOutputPath())
        let endpointText = try configuration.requireEndpoint()
        let modelName = try configuration.requireModel()
        let apiKeySource = try configuration.apiKeySource()
        let shouldPaste = configuration.shouldPaste ?? false
        let shouldUseHoldHook = configuration.usesHoldHook ?? false
        let seconds = configuration.recordSeconds ?? 2
        let timeoutMilliseconds = UInt32((configuration.holdTimeoutSeconds ?? 15) * 1_000)
        let wordReplacements = configuration.wordReplacements
        let trigger: WindowsDictationTrigger = shouldUseHoldHook
            ? .hold(timeoutMilliseconds: timeoutMilliseconds)
            : .toggle(recordSeconds: seconds)

        guard let endpointURL = URL(string: endpointText), endpointURL.scheme != nil else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--endpoint")
        }

        let service = OpenAICompatibleTranscriptionService(
            configuration: OpenAICompatibleTranscriptionConfiguration(
                endpointURL: endpointURL,
                apiKey: try apiKeySource.resolve()
            )
        )
        let model = TranscriptionModelDescriptor(
            name: modelName,
            displayName: modelName,
            provider: .custom
        )

        print("agent=roma-windows-agent")
        print("recording_mode=\(shouldUseHoldHook ? "hold" : "toggle")")
        print("paste_requested=\(shouldPaste)")
        print("api_key_source=\(apiKeySource.kind)")
        print("api_key_ref=\(apiKeySource.reference)")

        let result = try await WindowsDictationRuntime.run(
            WindowsDictationRuntimeRequest(
                outputURL: outputURL,
                model: model,
                language: configuration.language,
                prompt: configuration.prompt,
                shouldPaste: shouldPaste,
                textProcessing: DictationTextProcessingConfiguration(
                    wordReplacements: wordReplacements
                ),
                trigger: trigger
            ),
            transcriptionService: service
        ) { event in
            printEvent(event)
        }

        let audio = result.session.recordedAudio
        print("wrote=\(audio.fileURL.path)")
        print("duration_seconds=\(String(format: "%.3f", audio.durationSeconds ?? 0))")
        print("included_pre_roll_seconds=\(audio.includedPreRollSeconds ?? 0)")
        print("sample_rate=\(audio.format.sampleRate)")
        print("channels=\(audio.format.channelCount)")
        if let language = result.transcription.language {
            print("language=\(language)")
        }
        if let duration = result.transcription.durationSeconds {
            print("transcription_duration_seconds=\(String(format: "%.3f", duration))")
        }
        print("raw_transcript_length=\(result.transcription.text.count)")
        print("processed_transcript_length=\(result.processedText.count)")
        print("processed_transcript_text=\(RomaCommandLineText.oneLine(result.processedText))")
        print("word_replacements=\(wordReplacements.count)")
        print("paste_sent=\(result.session.insertedText != nil)")
    }

    private static func saveKeyFromEnvironment(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let key = try options.value(after: "--key")
        let environmentName = try options.value(after: "--value-env")
        let directoryPath = options.optionalValue(after: "--secret-dir")
            ?? WindowsDPAPISecretStore.defaultDirectoryURL().path

        guard RomaCommandLineText.isValidEnvironmentName(environmentName) else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--value-env")
        }
        guard let secret = ProcessInfo.processInfo.environment[environmentName], !secret.isEmpty else {
            throw TranscriptionAPIKeySourceError.missingEnvironmentValue(environmentName)
        }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try WindowsDPAPISecretStore(directoryURL: directoryURL).save(secret, forKey: key)
        print("secret_store=dpapi")
        print("directory=\(directoryURL.path)")
        print("key=\(key)")
        print("key_file=\(try WindowsDPAPISecretStore.fileName(forKey: key))")
        print("value_env=\(environmentName)")
        print("stored=true")
    }

    private static func writeConfiguration(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let url = RomaWindowsAgentConfiguration.url(from: options)
        let configuration = try loadConfiguration(from: options, allowMissing: true)
            .applyingOverrides(from: options)

        _ = try configuration.requireEndpoint()
        _ = try configuration.requireModel()
        _ = try configuration.apiKeySource()
        try configuration.write(to: url)

        print("config=\(url.path)")
        print("endpoint=\(try configuration.requireEndpoint())")
        print("model=\(try configuration.requireModel())")
        print("api_key_source=\(try configuration.apiKeySource().kind)")
        print("paste=\(configuration.shouldPaste ?? false)")
        print("recording_mode=\((configuration.usesHoldHook ?? false) ? "hold" : "toggle")")
        print("word_replacements=\(configuration.wordReplacements.count)")
        print("written=true")
    }

    private static func printEvent(_ event: WindowsDictationRuntimeEvent) {
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

    private static func defaultOutputPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-just-talk-\(Int(Date().timeIntervalSince1970)).wav")
            .path
    }

    private static func loadConfiguration(
        from options: RomaCommandLineOptions,
        allowMissing: Bool = true
    ) throws -> RomaWindowsAgentConfiguration {
        let url = RomaWindowsAgentConfiguration.url(from: options)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if allowMissing {
                return RomaWindowsAgentConfiguration()
            }
            throw RomaCommandLineOptionsError.missingOption("--config")
        }
        return try RomaWindowsAgentConfiguration.load(from: url)
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

    private static func printUsage() {
        print("usage:")
        print("  RomaWindowsAgent doctor")
        print("  RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY [--secret-dir C:\\tmp\\roma-secrets]")
        print("  RomaWindowsAgent write-config --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--config C:\\tmp\\roma-agent.json] [--hold-hook] [--paste]")
        print("  RomaWindowsAgent dictate [--config C:\\tmp\\roma-agent.json] [--endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY] [--out proof.wav] [--seconds 2] [--replace \"just talk=roma-just-talk\"] [--paste]")
        print("  RomaWindowsAgent dictate --hold-hook --timeout 15 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--paste]")
    }

    private static func printError(_ error: Error) {
        let description: String
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            description = errorDescription
        } else {
            description = String(describing: error)
        }

        let line = "error=\(RomaCommandLineText.oneLine(description))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
