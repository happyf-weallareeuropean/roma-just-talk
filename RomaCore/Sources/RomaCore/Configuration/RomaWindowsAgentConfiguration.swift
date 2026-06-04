import Foundation

public struct RomaWindowsAgentConfiguration: Codable, Equatable, Sendable {
    public static let defaultRecordSeconds = 2.0
    public static let defaultHoldTimeoutSeconds = 15.0
    public static let minimumRecordSeconds = 1.0 / 1_000_000_000
    public static let maximumRecordSeconds = Double(UInt64.max / 1_000_000_000)
    public static let minimumHoldTimeoutSeconds = 1.0 / 1_000
    public static let maximumHoldTimeoutSeconds = Double(UInt32.max) / 1_000

    public var endpoint: String?
    public var model: String?
    public var apiKeyEnvironment: String?
    public var apiKeyName: String?
    public var secretDirectoryPath: String?
    public var whisperCLIPath: String?
    public var whisperModelPath: String?
    public var whisperOutputDirectoryPath: String?
    public var whisperExtraArguments: [String]
    public var language: String?
    public var prompt: String?
    public var outputPath: String?
    public var shouldPaste: Bool?
    public var restoreClipboardAfterPaste: Bool?
    public var clipboardRestoreDelaySeconds: Double?
    public var usesHoldHook: Bool?
    public var recordSeconds: Double?
    public var holdTimeoutSeconds: Double?
    public var wordReplacements: [RomaWordReplacementRule]

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case model
        case apiKeyEnvironment
        case apiKeyName
        case secretDirectoryPath
        case whisperCLIPath
        case whisperModelPath
        case whisperOutputDirectoryPath
        case whisperExtraArguments
        case language
        case prompt
        case outputPath
        case shouldPaste
        case restoreClipboardAfterPaste
        case clipboardRestoreDelaySeconds
        case usesHoldHook
        case recordSeconds
        case holdTimeoutSeconds
        case wordReplacements
    }

    public init(
        endpoint: String? = nil,
        model: String? = nil,
        apiKeyEnvironment: String? = nil,
        apiKeyName: String? = nil,
        secretDirectoryPath: String? = nil,
        whisperCLIPath: String? = nil,
        whisperModelPath: String? = nil,
        whisperOutputDirectoryPath: String? = nil,
        whisperExtraArguments: [String] = [],
        language: String? = nil,
        prompt: String? = nil,
        outputPath: String? = nil,
        shouldPaste: Bool? = nil,
        restoreClipboardAfterPaste: Bool? = nil,
        clipboardRestoreDelaySeconds: Double? = nil,
        usesHoldHook: Bool? = nil,
        recordSeconds: Double? = nil,
        holdTimeoutSeconds: Double? = nil,
        wordReplacements: [RomaWordReplacementRule] = []
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKeyEnvironment = apiKeyEnvironment
        self.apiKeyName = apiKeyName
        self.secretDirectoryPath = secretDirectoryPath
        self.whisperCLIPath = whisperCLIPath
        self.whisperModelPath = whisperModelPath
        self.whisperOutputDirectoryPath = whisperOutputDirectoryPath
        self.whisperExtraArguments = whisperExtraArguments
        self.language = language
        self.prompt = prompt
        self.outputPath = outputPath
        self.shouldPaste = shouldPaste
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.clipboardRestoreDelaySeconds = clipboardRestoreDelaySeconds
        self.usesHoldHook = usesHoldHook
        self.recordSeconds = recordSeconds
        self.holdTimeoutSeconds = holdTimeoutSeconds
        self.wordReplacements = wordReplacements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        apiKeyEnvironment = try container.decodeIfPresent(String.self, forKey: .apiKeyEnvironment)
        apiKeyName = try container.decodeIfPresent(String.self, forKey: .apiKeyName)
        secretDirectoryPath = try container.decodeIfPresent(String.self, forKey: .secretDirectoryPath)
        whisperCLIPath = try container.decodeIfPresent(String.self, forKey: .whisperCLIPath)
        whisperModelPath = try container.decodeIfPresent(String.self, forKey: .whisperModelPath)
        whisperOutputDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .whisperOutputDirectoryPath
        )
        whisperExtraArguments = try container.decodeIfPresent(
            [String].self,
            forKey: .whisperExtraArguments
        ) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        shouldPaste = try container.decodeIfPresent(Bool.self, forKey: .shouldPaste)
        restoreClipboardAfterPaste = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreClipboardAfterPaste
        )
        clipboardRestoreDelaySeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .clipboardRestoreDelaySeconds
        )
        usesHoldHook = try container.decodeIfPresent(Bool.self, forKey: .usesHoldHook)
        recordSeconds = try container.decodeIfPresent(Double.self, forKey: .recordSeconds)
        holdTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .holdTimeoutSeconds)
        wordReplacements = try container.decodeIfPresent(
            [RomaWordReplacementRule].self,
            forKey: .wordReplacements
        ) ?? []
    }

    public static func defaultURL() -> URL {
        #if os(Windows)
        if let appData = ProcessInfo.processInfo.environment["APPDATA"], !appData.isEmpty {
            return URL(fileURLWithPath: appData)
                .appendingPathComponent("roma-just-talk", isDirectory: true)
                .appendingPathComponent("windows-agent.json", isDirectory: false)
        }
        #endif

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".roma-just-talk", isDirectory: true)
            .appendingPathComponent("windows-agent.json", isDirectory: false)
    }

    public static func url(from options: RomaCommandLineOptions) -> URL {
        if let path = options.optionalValue(after: "--config") {
            return URL(fileURLWithPath: path)
        }
        return defaultURL()
    }

    public static func load(from url: URL) throws -> RomaWindowsAgentConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RomaWindowsAgentConfiguration.self, from: data)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    public func applyingOverrides(from options: RomaCommandLineOptions) throws -> RomaWindowsAgentConfiguration {
        var configuration = self
        let selectsOpenAICompatible = options.contains("--endpoint") ||
            options.contains("--api-key-env") ||
            options.contains("--api-key-name")
        let selectsWhisperCLI = options.contains("--whisper-cli") ||
            options.contains("--whisper-model")

        if selectsOpenAICompatible {
            configuration.whisperCLIPath = nil
            configuration.whisperModelPath = nil
            configuration.whisperOutputDirectoryPath = nil
            configuration.whisperExtraArguments = []
        }
        if selectsWhisperCLI {
            configuration.endpoint = nil
            configuration.model = nil
            configuration.apiKeyEnvironment = nil
            configuration.apiKeyName = nil
            configuration.secretDirectoryPath = nil
        }

        if let value = options.optionalValue(after: "--endpoint") {
            configuration.endpoint = value
        }
        if let value = options.optionalValue(after: "--model") {
            configuration.model = value
        }
        if let value = options.optionalValue(after: "--api-key-env") {
            configuration.apiKeyEnvironment = value
            configuration.apiKeyName = nil
        }
        if let value = options.optionalValue(after: "--api-key-name") {
            configuration.apiKeyName = value
            configuration.apiKeyEnvironment = nil
        }
        if let value = options.optionalValue(after: "--secret-dir") {
            configuration.secretDirectoryPath = value
        }
        if let value = options.optionalValue(after: "--whisper-cli") {
            configuration.whisperCLIPath = value
        }
        if let value = options.optionalValue(after: "--whisper-model") {
            configuration.whisperModelPath = value
        }
        if let value = options.optionalValue(after: "--whisper-output-dir") {
            configuration.whisperOutputDirectoryPath = value
        }
        if options.contains("--whisper-arg") {
            configuration.whisperExtraArguments = try options.values(after: "--whisper-arg")
        }
        if let value = options.optionalValue(after: "--language") {
            configuration.language = value
        }
        if let value = options.optionalValue(after: "--prompt") {
            configuration.prompt = value
        }
        if let value = options.optionalValue(after: "--out") {
            configuration.outputPath = value
        }
        if options.contains("--paste") {
            configuration.shouldPaste = true
        }
        if options.contains("--no-paste") {
            configuration.shouldPaste = false
        }
        if options.contains("--restore-clipboard") {
            configuration.restoreClipboardAfterPaste = true
        }
        if options.contains("--no-restore-clipboard") {
            configuration.restoreClipboardAfterPaste = false
            configuration.clipboardRestoreDelaySeconds = nil
        }
        if options.contains("--clipboard-restore-delay") {
            configuration.clipboardRestoreDelaySeconds = try options.doubleValue(
                after: "--clipboard-restore-delay",
                default: 2
            )
        }
        if options.contains("--hold-hook") {
            configuration.usesHoldHook = true
        }
        if options.contains("--toggle") {
            configuration.usesHoldHook = false
        }
        if options.contains("--seconds") {
            configuration.recordSeconds = try options.doubleValue(after: "--seconds", default: 2)
        }
        if options.contains("--timeout") {
            configuration.holdTimeoutSeconds = try options.doubleValue(after: "--timeout", default: 15)
        }
        if options.contains("--replace") {
            configuration.wordReplacements = try RomaCommandLineText.wordReplacementRules(from: options)
        }

        try configuration.validate()
        return configuration
    }

    public func apiKeySource() throws -> TranscriptionAPIKeySource {
        try TranscriptionAPIKeySource.make(
            environmentName: apiKeyEnvironment,
            storedKeyName: apiKeyName,
            secretDirectoryPath: secretDirectoryPath
        )
    }

    public var usesWhisperCLI: Bool {
        whisperCLIPath != nil || whisperModelPath != nil
    }

    public func whisperCLIConfiguration() throws -> WhisperCLITranscriptionConfiguration {
        WhisperCLITranscriptionConfiguration(
            executableURL: URL(fileURLWithPath: try requireWhisperCLIPath()),
            modelURL: URL(fileURLWithPath: try requireWhisperModelPath()),
            outputDirectoryURL: URL(
                fileURLWithPath: whisperOutputDirectoryPath ?? FileManager.default.temporaryDirectory.path,
                isDirectory: true
            ),
            extraArguments: whisperExtraArguments
        )
    }

    public func clipboardRestoreConfiguration() -> WindowsClipboardRestoreConfiguration {
        WindowsClipboardRestoreConfiguration(
            restoreClipboard: restoreClipboardAfterPaste ?? true,
            restoreDelaySeconds: clipboardRestoreDelaySeconds ?? 2
        )
    }

    public var resolvedRecordSeconds: Double {
        recordSeconds ?? Self.defaultRecordSeconds
    }

    public func resolvedHoldTimeoutMilliseconds() throws -> UInt32 {
        try Self.holdTimeoutMilliseconds(fromSeconds: holdTimeoutSeconds ?? Self.defaultHoldTimeoutSeconds)
    }

    public static func holdTimeoutMilliseconds(fromSeconds seconds: Double) throws -> UInt32 {
        try validatePositiveFiniteDuration(
            seconds,
            option: "--timeout",
            minimum: minimumHoldTimeoutSeconds,
            maximum: maximumHoldTimeoutSeconds
        )
        return UInt32(seconds * 1_000)
    }

    public func requireEndpoint() throws -> String {
        try required(endpoint, option: "--endpoint")
    }

    public func requireModel() throws -> String {
        try required(model, option: "--model")
    }

    public func requireWhisperCLIPath() throws -> String {
        try required(whisperCLIPath, option: "--whisper-cli")
    }

    public func requireWhisperModelPath() throws -> String {
        try required(whisperModelPath, option: "--whisper-model")
    }

    public func validateTranscriptionSettings() throws {
        try validate()

        if usesWhisperCLI {
            _ = try requireWhisperCLIPath()
            _ = try requireWhisperModelPath()
            if endpoint != nil ||
                model != nil ||
                apiKeyEnvironment != nil ||
                apiKeyName != nil ||
                secretDirectoryPath != nil {
                throw RomaCommandLineOptionsError.conflictingOptions(
                    "OpenAI-compatible endpoint/key options and --whisper-cli"
                )
            }
            return
        }

        _ = try requireEndpoint()
        _ = try requireModel()
        _ = try apiKeySource()
    }

    public func validate() throws {
        try validatePositiveFiniteDuration(
            recordSeconds,
            option: "--seconds",
            minimum: Self.minimumRecordSeconds,
            maximum: Self.maximumRecordSeconds
        )
        try validatePositiveFiniteDuration(
            holdTimeoutSeconds,
            option: "--timeout",
            minimum: Self.minimumHoldTimeoutSeconds,
            maximum: Self.maximumHoldTimeoutSeconds
        )
        if let clipboardRestoreDelaySeconds,
           !clipboardRestoreDelaySeconds.isFinite ||
            clipboardRestoreDelaySeconds < 0 ||
            clipboardRestoreDelaySeconds > WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds {
            throw RomaCommandLineOptionsError.invalidOptionValue("--clipboard-restore-delay")
        }
        if restoreClipboardAfterPaste == false, clipboardRestoreDelaySeconds != nil {
            throw RomaCommandLineOptionsError.conflictingOptions(
                "--no-restore-clipboard and --clipboard-restore-delay"
            )
        }
        if let apiKeyEnvironment,
           !RomaCommandLineText.isValidEnvironmentName(apiKeyEnvironment) {
            throw RomaCommandLineOptionsError.invalidOptionValue("--api-key-env")
        }
        if apiKeyEnvironment != nil, apiKeyName != nil {
            throw RomaCommandLineOptionsError.conflictingOptions("--api-key-env and --api-key-name")
        }
    }

    private func required(_ value: String?, option: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw RomaCommandLineOptionsError.missingOption(option)
        }
        return value
    }

    private func validatePositiveFiniteDuration(
        _ value: Double?,
        option: String,
        minimum: Double,
        maximum: Double
    ) throws {
        guard let value else {
            return
        }
        try Self.validatePositiveFiniteDuration(
            value,
            option: option,
            minimum: minimum,
            maximum: maximum
        )
    }

    private static func validatePositiveFiniteDuration(
        _ value: Double,
        option: String,
        minimum: Double,
        maximum: Double
    ) throws {
        guard value.isFinite, value >= minimum, value <= maximum else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }
    }
}
