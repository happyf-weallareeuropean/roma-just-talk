import Foundation

public enum TranscriptionAPIKeySourceError: Error, LocalizedError, Equatable {
    case missingEnvironmentValue(String)
    case missingStoredSecret(String)

    public var errorDescription: String? {
        switch self {
        case .missingEnvironmentValue(let name):
            return "Missing environment value \(name)."
        case .missingStoredSecret(let key):
            return "Missing stored secret \(key)."
        }
    }
}

public enum TranscriptionAPIKeySource: Equatable, Hashable, Sendable {
    case environment(name: String)
    case stored(key: String, directoryURL: URL)

    public var kind: String {
        switch self {
        case .environment:
            return "environment"
        case .stored:
            return "dpapi"
        }
    }

    public var reference: String {
        switch self {
        case .environment(let name):
            return name
        case .stored(let key, let directoryURL):
            return "\(key)@\(directoryURL.path)"
        }
    }

    public func resolve() throws -> String {
        switch self {
        case .environment(let name):
            guard let apiKey = ProcessInfo.processInfo.environment[name], !apiKey.isEmpty else {
                throw TranscriptionAPIKeySourceError.missingEnvironmentValue(name)
            }
            return apiKey
        case .stored(let key, let directoryURL):
            let store = WindowsDPAPISecretStore(directoryURL: directoryURL)
            guard let apiKey = try store.get(key), !apiKey.isEmpty else {
                throw TranscriptionAPIKeySourceError.missingStoredSecret(key)
            }
            return apiKey
        }
    }

    public static func make(
        from options: RomaCommandLineOptions,
        defaultSecretDirectoryURL: URL = WindowsDPAPISecretStore.defaultDirectoryURL()
    ) throws -> TranscriptionAPIKeySource {
        let environmentName = options.optionalValue(after: "--api-key-env")
        let storedKeyName = options.optionalValue(after: "--api-key-name")

        if environmentName != nil, storedKeyName != nil {
            throw RomaCommandLineOptionsError.conflictingOptions("--api-key-env and --api-key-name")
        }
        if let environmentName {
            guard RomaCommandLineText.isValidEnvironmentName(environmentName) else {
                throw RomaCommandLineOptionsError.invalidOptionValue("--api-key-env")
            }
            return .environment(name: environmentName)
        }
        if let storedKeyName {
            let directoryPath = options.optionalValue(after: "--secret-dir")
                ?? defaultSecretDirectoryURL.path
            return .stored(
                key: storedKeyName,
                directoryURL: URL(fileURLWithPath: directoryPath, isDirectory: true)
            )
        }

        throw RomaCommandLineOptionsError.missingOption("--api-key-env or --api-key-name")
    }
}
