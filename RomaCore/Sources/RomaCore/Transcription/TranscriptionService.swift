import Foundation

public protocol TranscriptionService: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}

public protocol StreamingTranscriptionSession: AnyObject, Sendable {
    func prepare(
        model: TranscriptionModelDescriptor,
        onPartialTranscript: @escaping @Sendable (String) -> Void
    ) async throws -> (@Sendable (Data) -> Void)?

    func finish(with audioURL: URL) async throws -> TranscriptionResult
    func cancel()
}
