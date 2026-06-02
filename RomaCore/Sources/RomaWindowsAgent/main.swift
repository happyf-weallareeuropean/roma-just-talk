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
        print("minimum_permission_surface=microphone,hotkey,clipboard")
        print("screen_capture=false")
    }

    private static func runDictation(arguments: [String]) async throws {
        let outputURL = URL(fileURLWithPath: optionalValue(after: "--out", in: arguments) ?? defaultOutputPath())
        let endpointText = try value(after: "--endpoint", in: arguments)
        let modelName = try value(after: "--model", in: arguments)
        let apiKeySource = try makeAPIKeySource(arguments: arguments)
        let shouldPaste = arguments.contains("--paste")
        let shouldUseHoldHook = arguments.contains("--hold-hook")
        let seconds = try doubleValue(after: "--seconds", in: arguments, default: 2)
        let timeoutMilliseconds = UInt32(try doubleValue(after: "--timeout", in: arguments, default: 15) * 1_000)
        let wordReplacements = try replacementRules(from: arguments)
        let trigger: WindowsDictationTrigger = shouldUseHoldHook
            ? .hold(timeoutMilliseconds: timeoutMilliseconds)
            : .toggle(recordSeconds: seconds)

        guard let endpointURL = URL(string: endpointText), endpointURL.scheme != nil else {
            throw AgentError.invalidOptionValue("--endpoint")
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
        print("processed_transcript_text=\(oneLine(result.processedText))")
        print("word_replacements=\(wordReplacements.count)")
        print("paste_sent=\(result.session.insertedText != nil)")
    }

    private static func saveKeyFromEnvironment(arguments: [String]) throws {
        let key = try value(after: "--key", in: arguments)
        let environmentName = try value(after: "--value-env", in: arguments)
        let directoryPath = optionalValue(after: "--secret-dir", in: arguments)
            ?? WindowsDPAPISecretStore.defaultDirectoryURL().path

        guard isValidEnvironmentName(environmentName) else {
            throw AgentError.invalidOptionValue("--value-env")
        }
        guard let secret = ProcessInfo.processInfo.environment[environmentName], !secret.isEmpty else {
            throw AgentError.missingEnvironmentValue(environmentName)
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

    private static func makeAPIKeySource(arguments: [String]) throws -> TranscriptionAPIKeySource {
        let environmentName = optionalValue(after: "--api-key-env", in: arguments)
        let storedKeyName = optionalValue(after: "--api-key-name", in: arguments)

        if environmentName != nil, storedKeyName != nil {
            throw AgentError.conflictingOptions("--api-key-env and --api-key-name")
        }
        if let environmentName {
            guard isValidEnvironmentName(environmentName) else {
                throw AgentError.invalidOptionValue("--api-key-env")
            }
            return .environment(name: environmentName)
        }
        if let storedKeyName {
            let directoryPath = optionalValue(after: "--secret-dir", in: arguments)
                ?? WindowsDPAPISecretStore.defaultDirectoryURL().path
            return .stored(
                key: storedKeyName,
                directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true)
            )
        }

        throw AgentError.missingOption("--api-key-env or --api-key-name")
    }

    private static func replacementRules(from arguments: [String]) throws -> [RomaWordReplacementRule] {
        try values(after: "--replace", in: arguments).map { value in
            let pieces = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                throw AgentError.invalidOptionValue("--replace")
            }

            let original = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty, !replacement.isEmpty else {
                throw AgentError.invalidOptionValue("--replace")
            }

            return RomaWordReplacementRule(
                originalText: original,
                replacementText: replacement
            )
        }
    }

    private static func value(after option: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            throw AgentError.missingOption(option)
        }
        return arguments[index + 1]
    }

    private static func optionalValue(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        let trimmed = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func values(after option: String, in arguments: [String]) throws -> [String] {
        var values: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            defer { index = arguments.index(after: index) }
            guard arguments[index] == option else { continue }

            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw AgentError.missingOption(option)
            }

            values.append(arguments[valueIndex])
            index = valueIndex
        }
        return values
    }

    private static func doubleValue(after option: String, in arguments: [String], default defaultValue: Double) throws -> Double {
        guard let index = arguments.firstIndex(of: option) else {
            return defaultValue
        }
        guard arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]) else {
            throw AgentError.invalidOptionValue(option)
        }
        return value
    }

    private static func defaultOutputPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-just-talk-\(Int(Date().timeIntervalSince1970)).wav")
            .path
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
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }

        return value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func oneLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
    }

    private static func printUsage() {
        print("usage:")
        print("  RomaWindowsAgent doctor")
        print("  RomaWindowsAgent save-key-from-env --key groq --value-env GROQ_API_KEY [--secret-dir C:\\tmp\\roma-secrets]")
        print("  RomaWindowsAgent dictate --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY [--out proof.wav] [--seconds 2] [--replace \"just talk=roma-just-talk\"] [--paste]")
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

        let line = "error=\(oneLine(description))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

private enum AgentError: Error, CustomStringConvertible {
    case missingOption(String)
    case invalidOptionValue(String)
    case missingEnvironmentValue(String)
    case conflictingOptions(String)

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
        }
    }
}
