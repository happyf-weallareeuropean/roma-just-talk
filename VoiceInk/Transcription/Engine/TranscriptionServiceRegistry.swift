import Foundation
import SwiftUI
import SwiftData
import os
import VoiceInkCore
import VoiceInkQwen

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    let qwenRuntimeResult: Result<QwenRuntime, Error>
    private let ownsQwenRuntime: Bool
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.transcriptionServiceRegistry
    )

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()
    private(set) lazy var qwenTranscriptionService = QwenTranscriptionService(runtimeResult: qwenRuntimeResult)

    init(
        modelProvider: any WhisperModelProvider,
        modelsDirectory: URL,
        modelContext: ModelContext,
        qwenRuntimeResult: Result<QwenRuntime, Error>,
        ownsQwenRuntime: Bool = false
    ) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
        self.qwenRuntimeResult = qwenRuntimeResult
        self.ownsQwenRuntime = ownsQwenRuntime
    }

    func service(for route: VoiceInkTranscriptionServiceRoute) -> TranscriptionService {
        switch route {
        case .localWhisper:
            return localTranscriptionService
        case .localFluidAudio:
            return fluidAudioTranscriptionService
        case .localQwen:
            return qwenTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        case .cloud:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.transcriptionSessionRouteFacts.serviceRoute)
        let message = VoiceInkTranscriptionServiceRouteDiagnostics.transcribingMessage(
            modelDisplayName: model.displayName,
            serviceTypeDescription: String(describing: type(of: service))
        )
        logger.debug("\(message, privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(
        for model: any TranscriptionModel,
        onPartialTranscript: ((String) -> Void)? = nil
    ) -> TranscriptionSession {
        let routePlan = model.transcriptionSessionRouteFacts.plan()

        return routePlan.executionPlan.applyRuntimeState(
            file: { serviceRoute -> TranscriptionSession in
                FileTranscriptionSession(service: service(for: serviceRoute))
            },
            streaming: { request -> TranscriptionSession in
                let streamingService = StreamingTranscriptionService(
                    modelContext: modelContext,
                    streamingAdapterKind: request.adapterKind,
                    fluidAudioService: request.adapterKind == .localFluidAudio ? fluidAudioTranscriptionService : nil,
                    qwenRuntimeResult: request.adapterKind == .localQwen ? qwenRuntimeResult : nil,
                    finalCommitTimeoutNanoseconds: request.finalCommitTimeoutNanoseconds,
                    onPartialTranscript: onPartialTranscript
                )
                let fallback = service(for: request.serviceRoute)
                return StreamingTranscriptionSession(
                    streamingService: streamingService,
                    fallbackService: fallback
                )
            }
        )
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
        // File imports and recording share Qwen; release only when neither is active.
        if ownsQwenRuntime {
            try? await qwenRuntimeResult.get().unloadIfIdle()
        }
    }
}
