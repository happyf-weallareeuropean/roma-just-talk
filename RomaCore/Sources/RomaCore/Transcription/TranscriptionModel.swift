import Foundation

public enum TranscriptionProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case whisper
    case fluidAudio
    case nativeApple
    case groq
    case elevenLabs
    case deepgram
    case mistral
    case gemini
    case soniox
    case speechmatics
    case assemblyAI
    case xai
    case cartesia
    case custom
}

public struct TranscriptionModelDescriptor: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var displayName: String
    public var provider: TranscriptionProvider
    public var supportedLanguages: [String: String]
    public var supportsStreaming: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        provider: TranscriptionProvider,
        supportedLanguages: [String: String] = [:],
        supportsStreaming: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.provider = provider
        self.supportedLanguages = supportedLanguages
        self.supportsStreaming = supportsStreaming
    }
}

public struct TranscriptionRequest: Equatable, Hashable, Sendable {
    public var audioURL: URL
    public var model: TranscriptionModelDescriptor
    public var language: String?
    public var prompt: String?
    public var customVocabulary: [String]

    public init(
        audioURL: URL,
        model: TranscriptionModelDescriptor,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) {
        self.audioURL = audioURL
        self.model = model
        self.language = language
        self.prompt = prompt
        self.customVocabulary = customVocabulary
    }
}

public struct TranscriptionResult: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var language: String?
    public var durationSeconds: TimeInterval?

    public init(
        text: String,
        language: String? = nil,
        durationSeconds: TimeInterval? = nil
    ) {
        self.text = text
        self.language = language
        self.durationSeconds = durationSeconds
    }
}
