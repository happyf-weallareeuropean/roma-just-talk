import Foundation
import os

/// Manages API keys using secure Keychain storage.
final class APIKeyManager {
    static let shared = APIKeyManager()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "APIKeyManager")
    private let keychain = KeychainService.shared

    /// Provider to Keychain identifier mapping (iOS compatible for iCloud sync).
    private static let providerToKeychainKey: [String: String] = [
        "groq": "groqAPIKey",
        "deepgram": "deepgramAPIKey",
        "cerebras": "cerebrasAPIKey",
        "gemini": "geminiAPIKey",
        "mistral": "mistralAPIKey",
        "elevenlabs": "elevenLabsAPIKey",
        "soniox": "sonioxAPIKey",
        "speechmatics": "speechmaticsAPIKey",
        "assemblyai": "assemblyAIAPIKey",
        "xai": "xaiAPIKey",
        "cartesia": "cartesiaAPIKey",
        "openai": "openAIAPIKey",
        "anthropic": "anthropicAPIKey",
        "openrouter": "openRouterAPIKey"
    ]

    private static let providerToEnvironmentKey: [String: String] = [
        "elevenlabs": "ELEVENLABS_API_KEY"
    ]

    private init() {}

    // MARK: - Standard Provider API Keys

    /// Saves an API key for a provider.
    @discardableResult
    func saveAPIKey(_ key: String, forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for provider: \(provider, privacy: .public) with key: \(keyIdentifier, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a provider.
    func getAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        if let storedKey = keychain.getString(forKey: keyIdentifier),
           let resolvedKey = Self.resolveAPIKeyReference(storedKey) {
            return resolvedKey
        }

        let lowercased = provider.lowercased()
        if let environmentKey = Self.providerToEnvironmentKey[lowercased],
           let value = ProcessInfo.processInfo.environment[environmentKey],
           !value.isEmpty {
            return value
        }

        return nil
    }

    /// Retrieves the literal stored API key, preserving references like "$ELEVENLABS_API_KEY" for the UI.
    func getStoredAPIKey(forProvider provider: String) -> String? {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        return keychain.getString(forKey: keyIdentifier)
    }

    /// Deletes an API key for a provider.
    @discardableResult
    func deleteAPIKey(forProvider provider: String) -> Bool {
        let keyIdentifier = keychainIdentifier(forProvider: provider)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for provider: \(provider, privacy: .public)")
        }
        return success
    }

    /// Checks if an API key exists for a provider.
    func hasAPIKey(forProvider provider: String) -> Bool {
        return getAPIKey(forProvider: provider) != nil
    }

    static func resolveAPIKeyReference(_ key: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let variableName: String
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            variableName = String(trimmed.dropFirst(2).dropLast())
        } else if trimmed.hasPrefix("$") {
            variableName = String(trimmed.dropFirst())
        } else {
            return trimmed
        }

        guard !variableName.isEmpty,
              variableName.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
              let value = environment[variableName],
              !value.isEmpty else {
            return nil
        }

        return value
    }

    // MARK: - Custom Model API Keys

    /// Saves an API key for a custom model.
    @discardableResult
    func saveCustomModelAPIKey(_ key: String, forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.save(key, forKey: keyIdentifier)
        if success {
            logger.info("Saved API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    /// Retrieves an API key for a custom model.
    func getCustomModelAPIKey(forModelId modelId: UUID) -> String? {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        guard let storedKey = keychain.getString(forKey: keyIdentifier) else { return nil }
        return Self.resolveAPIKeyReference(storedKey)
    }

    /// Deletes an API key for a custom model.
    @discardableResult
    func deleteCustomModelAPIKey(forModelId modelId: UUID) -> Bool {
        let keyIdentifier = customModelKeyIdentifier(for: modelId)
        let success = keychain.delete(forKey: keyIdentifier)
        if success {
            logger.info("Deleted API key for custom model: \(modelId.uuidString, privacy: .public)")
        }
        return success
    }

    // MARK: - Key Identifier Helpers

    /// Returns Keychain identifier for a provider (case-insensitive).
    private func keychainIdentifier(forProvider provider: String) -> String {
        let lowercased = provider.lowercased()
        if let mapped = Self.providerToKeychainKey[lowercased] {
            return mapped
        }
        return "\(lowercased)APIKey"
    }

    /// Generates Keychain identifier for custom model API key.
    private func customModelKeyIdentifier(for modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }
}
