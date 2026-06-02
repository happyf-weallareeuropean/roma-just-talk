import Foundation

public struct RomaWindowsAgentConfiguration: Codable, Equatable, Sendable {
    public var endpoint: String?
    public var model: String?
    public var apiKeyEnvironment: String?
    public var apiKeyName: String?
    public var secretDirectoryPath: String?
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

    public init(
        endpoint: String? = nil,
        model: String? = nil,
        apiKeyEnvironment: String? = nil,
        apiKeyName: String? = nil,
        secretDirectoryPath: String? = nil,
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

    public func clipboardRestoreConfiguration() -> WindowsClipboardRestoreConfiguration {
        WindowsClipboardRestoreConfiguration(
            restoreClipboard: restoreClipboardAfterPaste ?? true,
            restoreDelaySeconds: clipboardRestoreDelaySeconds ?? 2
        )
    }

    public func requireEndpoint() throws -> String {
        try required(endpoint, option: "--endpoint")
    }

    public func requireModel() throws -> String {
        try required(model, option: "--model")
    }

    public func validate() throws {
        if let recordSeconds, recordSeconds < 0 {
            throw RomaCommandLineOptionsError.invalidOptionValue("--seconds")
        }
        if let holdTimeoutSeconds, holdTimeoutSeconds < 0 {
            throw RomaCommandLineOptionsError.invalidOptionValue("--timeout")
        }
        if let clipboardRestoreDelaySeconds, clipboardRestoreDelaySeconds < 0 {
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
}
