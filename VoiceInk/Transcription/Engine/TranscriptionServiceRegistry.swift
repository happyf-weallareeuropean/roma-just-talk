import Foundation
import SwiftUI
import SwiftData
import os

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let powerStateProvider: any LiveTranscriptionPowerStateProviding
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()

    init(
        modelProvider: any WhisperModelProvider,
        modelsDirectory: URL,
        modelContext: ModelContext,
        powerStateProvider: any LiveTranscriptionPowerStateProviding = IOKitLiveTranscriptionPowerStateProvider()
    ) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
        self.powerStateProvider = powerStateProvider
    }

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.provider)
        logger.debug("Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(for model: any TranscriptionModel, onPartialTranscript: ((String) -> Void)? = nil) -> TranscriptionSession {
        if supportsStreaming(model: model) {
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    /// Whether the given model supports streaming transcription
    private func supportsStreaming(model: any TranscriptionModel) -> Bool {
        let cloudProvider = CloudProviderRegistry.provider(for: model.provider)
        let isStreamingOnly = cloudProvider?.isStreamingOnly ?? false
        let perModelEnabled = LiveTranscriptionSettings.perModelStreamingEnabled(for: model)
        let powerState = powerStateProvider.currentPowerState()

        return LiveTranscriptionPolicy(defaults: .standard, powerState: powerState).allowsStreaming(
            for: model,
            isStreamingOnly: isStreamingOnly,
            perModelEnabled: perModelEnabled
        )
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
