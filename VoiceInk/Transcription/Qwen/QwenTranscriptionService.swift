import Foundation
import VoiceInkCore
import VoiceInkQwen

/// App adapter; model selection and the user's language preference remain app-owned.
final class QwenTranscriptionService: TranscriptionService {
    let runtimeResult: Result<QwenRuntime, Error>

    init(runtimeResult: Result<QwenRuntime, Error>) {
        self.runtimeResult = runtimeResult
    }

    func runtime() throws -> QwenRuntime {
        try runtimeResult.get()
    }

    func loadModel() async throws {
        try await runtime().prewarm()
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let samples = try await AudioProcessor().processAudioToSamples(audioURL)
        try Task.checkCancellation()
        let language = VoiceInkTranscriptionLanguagePreference.requestLanguage(for: model.transcriptionLanguageSelectionFacts)
        return try await runtime().transcribe(samples: samples, language: language)
    }

    func cleanup() async throws {
        try await runtime().unload()
    }
}
