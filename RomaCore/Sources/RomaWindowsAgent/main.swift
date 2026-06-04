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
        case "listen":
            try await runListener(arguments: Array(arguments.dropFirst()))
        case "save-key-from-env":
            try saveKeyFromEnvironment(arguments: Array(arguments.dropFirst()))
        case "write-config":
            try writeConfiguration(arguments: Array(arguments.dropFirst()))
        case "config-doctor":
            try printConfigurationDoctor(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func printDoctor() {
        let permissionSurface = WindowsPermissionSurface.minimumMVP

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
        print("clipboard_restore=text_only_after_delay")
        print("default_record_seconds=\(RomaWindowsAgentConfiguration.defaultRecordSeconds)")
        print("default_hold_timeout_seconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds)")
        print("default_hold_timeout_milliseconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds)")
        print("default_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds)")
        print("maximum_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds)")
        print("secret_store=dpapi")
        print("config_default=\(RomaWindowsAgentConfiguration.defaultURL().path)")
        print("minimum_permission_surface=\(permissionSurface.minimumPermissions.joined(separator: ","))")
        print("os_permission_grants=\(permissionSurface.osPermissionGrants.joined(separator: ","))")
        print("native_capabilities=\(permissionSurface.nativeCapabilities.joined(separator: ","))")
        print("microphone_settings=\(permissionSurface.microphoneSettingsPath)")
        print("desktop_app_microphone_access_required=\(permissionSurface.requiresDesktopAppMicrophoneAccess)")
        print("hotkey_permission_prompt=\(permissionSurface.hotKeyPermissionPrompt)")
        print("paste_permission_prompt=\(permissionSurface.pastePermissionPrompt)")
        print("paste_integrity_limit=\(permissionSurface.pasteIntegrityLimit)")
        print("admin_required=\(permissionSurface.adminRequired)")
        print("startup_mechanism=\(permissionSurface.startupMechanism)")
        print("startup_launcher=\(permissionSurface.startupLauncher)")
        print("startup_launch_mode=\(permissionSurface.startupLaunchMode)")
        print("startup_permission_prompt=\(permissionSurface.startupPermissionPrompt)")
        print("screen_capture_required=\(permissionSurface.screenCaptureRequired)")
    }

    private static func runDictation(arguments: [String]) async throws {
        let options = RomaCommandLineOptions(arguments)
        let configuration = try loadConfiguration(from: options)
            .applyingOverrides(from: options)
        let outputURL = URL(fileURLWithPath: configuration.outputPath ?? defaultOutputPath())
        let transcriptionClient = try makeTranscriptionClient(from: configuration)
        let shouldPaste = configuration.shouldPaste ?? false
        let clipboardRestoreConfiguration = configuration.clipboardRestoreConfiguration()
        let shouldUseHoldHook = configuration.usesHoldHook ?? false
        let seconds = configuration.resolvedRecordSeconds
        let timeoutMilliseconds = try configuration.resolvedHoldTimeoutMilliseconds()
        let wordReplacements = configuration.wordReplacements
        let trigger: WindowsDictationTrigger = shouldUseHoldHook
            ? .hold(timeoutMilliseconds: timeoutMilliseconds)
            : .toggle(recordSeconds: seconds)

        print("agent=roma-windows-agent")
        print("transcription_client=\(transcriptionClient.name)")
        for line in transcriptionClient.details {
            print(line)
        }
        print("recording_mode=\(shouldUseHoldHook ? "hold" : "toggle")")
        print("paste_requested=\(shouldPaste)")
        print("restore_clipboard_after_paste=\(clipboardRestoreConfiguration.restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(clipboardRestoreConfiguration.restoreDelaySeconds)")

        let result = try await WindowsDictationRuntime.run(
            WindowsDictationRuntimeRequest(
                outputURL: outputURL,
                model: transcriptionClient.model,
                language: configuration.language,
                prompt: configuration.prompt,
                shouldPaste: shouldPaste,
                clipboardRestoreConfiguration: clipboardRestoreConfiguration,
                textProcessing: DictationTextProcessingConfiguration(
                    wordReplacements: wordReplacements
                ),
                trigger: trigger
            ),
            transcriptionService: transcriptionClient.service
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

    private static func runListener(arguments: [String]) async throws {
        let options = RomaCommandLineOptions(arguments)
        let maxSessions = try maxListenSessions(from: options)
        let previewConfiguration = try loadConfiguration(from: options)
            .applyingOverrides(from: options)
        try previewConfiguration.validateTranscriptionSettings()

        print("agent=roma-windows-agent")
        print("mode=listen")
        print("max_sessions=\(maxSessions.map(String.init) ?? "unbounded")")

        var completedSessions = 0
        while maxSessions.map({ completedSessions < $0 }) ?? true {
            print("listen_session_start=\(completedSessions + 1)")
            try await runDictation(arguments: arguments)
            completedSessions += 1
            print("listen_session_completed=\(completedSessions)")
        }

        print("listen_completed_sessions=\(completedSessions)")
    }

    private static func maxListenSessions(from options: RomaCommandLineOptions) throws -> Int? {
        guard let value = options.optionalValue(after: "--max-sessions") else {
            return nil
        }
        guard let sessions = Int(value), sessions >= 0 else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--max-sessions")
        }
        return sessions
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

        try configuration.validateTranscriptionSettings()
        try configuration.write(to: url)

        print("config=\(url.path)")
        if configuration.usesWhisperCLI {
            print("transcription_client=whisper.cpp-cli")
            print("whisper_cli=\(try configuration.requireWhisperCLIPath())")
            print("whisper_model=\(try configuration.requireWhisperModelPath())")
            print("whisper_extra_args=\(configuration.whisperExtraArguments.count)")
        } else {
            print("transcription_client=openai-compatible")
            print("endpoint=\(try configuration.requireEndpoint())")
            print("model=\(try configuration.requireModel())")
            print("api_key_source=\(try configuration.apiKeySource().kind)")
        }
        print("paste=\(configuration.shouldPaste ?? false)")
        print("restore_clipboard_after_paste=\(configuration.clipboardRestoreConfiguration().restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(configuration.clipboardRestoreConfiguration().restoreDelaySeconds)")
        print("recording_mode=\((configuration.usesHoldHook ?? false) ? "hold" : "toggle")")
        print("word_replacements=\(configuration.wordReplacements.count)")
        print("written=true")
    }

    private static func printConfigurationDoctor(arguments: [String]) throws {
        let options = RomaCommandLineOptions(arguments)
        let url = RomaWindowsAgentConfiguration.url(from: options)
        let configuration = try loadConfiguration(from: options, allowMissing: true)
            .applyingOverrides(from: options)

        try configuration.validateTranscriptionSettings()
        let setupProofLines = try runnableTranscriptionSetupProof(configuration)
        let transcriptionClient = try makeTranscriptionClient(from: configuration)
        let clipboardRestoreConfiguration = configuration.clipboardRestoreConfiguration()

        print("agent=roma-windows-agent")
        print("config=\(url.path)")
        print("config_exists=\(FileManager.default.fileExists(atPath: url.path))")
        print("config_valid=true")
        print("transcription_client=\(transcriptionClient.name)")
        for line in transcriptionClient.details {
            print(line)
        }
        for line in setupProofLines {
            print(line)
        }
        print("recording_mode=\((configuration.usesHoldHook ?? false) ? "hold" : "toggle")")
        print("paste=\(configuration.shouldPaste ?? false)")
        print("restore_clipboard_after_paste=\(clipboardRestoreConfiguration.restoreClipboard)")
        print("clipboard_restore_delay_seconds=\(clipboardRestoreConfiguration.restoreDelaySeconds)")
        print("word_replacements=\(configuration.wordReplacements.count)")
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

    private static func makeTranscriptionClient(
        from configuration: RomaWindowsAgentConfiguration
    ) throws -> AgentTranscriptionClient {
        if configuration.usesWhisperCLI {
            let whisperConfiguration = try configuration.whisperCLIConfiguration()
            let modelName = whisperConfiguration.modelURL.lastPathComponent
            return AgentTranscriptionClient(
                name: "whisper.cpp-cli",
                service: WhisperCLITranscriptionService(configuration: whisperConfiguration),
                model: TranscriptionModelDescriptor(
                    name: modelName,
                    displayName: modelName,
                    provider: .whisper
                ),
                details: [
                    "whisper_cli=\(whisperConfiguration.executableURL.path)",
                    "whisper_model=\(whisperConfiguration.modelURL.path)",
                    "whisper_output_dir=\(whisperConfiguration.outputDirectoryURL.path)",
                    "whisper_extra_args=\(whisperConfiguration.extraArguments.count)"
                ]
            )
        }

        let endpointText = try configuration.requireEndpoint()
        let modelName = try configuration.requireModel()
        let apiKeySource = try configuration.apiKeySource()

        guard let endpointURL = URL(string: endpointText), endpointURL.scheme != nil else {
            throw RomaCommandLineOptionsError.invalidOptionValue("--endpoint")
        }

        return AgentTranscriptionClient(
            name: "openai-compatible",
            service: OpenAICompatibleTranscriptionService(
                configuration: OpenAICompatibleTranscriptionConfiguration(
                    endpointURL: endpointURL,
                    apiKey: try apiKeySource.resolve()
                )
            ),
            model: TranscriptionModelDescriptor(
                name: modelName,
                displayName: modelName,
                provider: .custom
            ),
            details: [
                "endpoint=\(endpointText)",
                "model=\(modelName)",
                "api_key_source=\(apiKeySource.kind)",
                "api_key_ref=\(apiKeySource.reference)"
            ]
        )
    }

    private static func runnableTranscriptionSetupProof(
        _ configuration: RomaWindowsAgentConfiguration
    ) throws -> [String] {
        guard configuration.usesWhisperCLI else {
            _ = try configuration.apiKeySource().resolve()
            return ["api_key_resolved=true"]
        }

        try requireExistingFile(try configuration.requireWhisperCLIPath(), option: "--whisper-cli")
        try requireExistingFile(try configuration.requireWhisperModelPath(), option: "--whisper-model")
        return [
            "whisper_cli_exists=true",
            "whisper_model_exists=true"
        ]
    }

    private static func requireExistingFile(_ path: String, option: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }
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
        print("  RomaWindowsAgent write-config --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--config C:\\tmp\\roma-agent.json] [--hold-hook] [--paste] [--no-restore-clipboard]")
        print("  RomaWindowsAgent write-config --whisper-cli C:\\path\\whisper-cli.exe --whisper-model C:\\path\\ggml-base.en.bin [--config C:\\tmp\\roma-agent.json] [--hold-hook] [--paste]")
        print("  RomaWindowsAgent config-doctor [--config C:\\tmp\\roma-agent.json]")
        print("  RomaWindowsAgent dictate [--config C:\\tmp\\roma-agent.json] [--endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-env OPENAI_API_KEY] [--out proof.wav] [--seconds 2] [--replace \"just talk=roma-just-talk\"] [--paste] [--clipboard-restore-delay 2]")
        print("  RomaWindowsAgent dictate --whisper-cli C:\\path\\whisper-cli.exe --whisper-model C:\\path\\ggml-base.en.bin [--hold-hook] [--paste]")
        print("  RomaWindowsAgent dictate --hold-hook --timeout 15 --endpoint https://api.example.com/v1/audio/transcriptions --model whisper-large-v3-turbo --api-key-name groq [--paste] [--no-restore-clipboard]")
        print("  RomaWindowsAgent listen --config C:\\tmp\\roma-agent.json [--max-sessions 3]")
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

private struct AgentTranscriptionClient {
    var name: String
    var service: any TranscriptionService
    var model: TranscriptionModelDescriptor
    var details: [String]
}
