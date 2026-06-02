import Foundation

public enum DictationSessionStatus: String, Codable, Hashable, Sendable {
    case pending
    case transcribing
    case enhancing
    case completed
    case failed
    case canceled
}

public struct DictationSession: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var recordedAudio: RecordedAudio
    public var model: TranscriptionModelDescriptor
    public var status: DictationSessionStatus
    public var rawText: String?
    public var insertedText: String?
    public var errorDescription: String?

    public init(
        id: UUID = UUID(),
        recordedAudio: RecordedAudio,
        model: TranscriptionModelDescriptor,
        status: DictationSessionStatus = .pending,
        rawText: String? = nil,
        insertedText: String? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.recordedAudio = recordedAudio
        self.model = model
        self.status = status
        self.rawText = rawText
        self.insertedText = insertedText
        self.errorDescription = errorDescription
    }
}

public struct TextInsertionContext: Codable, Equatable, Hashable, Sendable {
    public var precedingText: String
    public var selectedText: String?

    public init(precedingText: String = "", selectedText: String? = nil) {
        self.precedingText = precedingText
        self.selectedText = selectedText
    }
}
