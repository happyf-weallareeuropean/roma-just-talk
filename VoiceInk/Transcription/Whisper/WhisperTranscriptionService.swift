import Foundation
import AVFoundation
import os
import VoiceInkCore

class WhisperTranscriptionService: TranscriptionService {

    private var whisperContext: WhisperContext?
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.whisperTranscriptionService
    )
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let request = VoiceInkLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, isMultilingual: model.isMultilingualModel)
        guard model.provider == .whisper else {
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: request.failurePlatform)
        }

        logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSInitiatingLocalTranscriptionMessage(modelDisplayName: model.displayName), privacy: .public)")

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: request,
            actions: VoiceInkLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    if let provider = self.modelProvider,
                       await provider.isModelLoaded,
                       let loadedContext = await provider.whisperContext,
                       await provider.loadedWhisperModel?.name == model.name {

                        self.logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSUsingLoadedModelMessage(modelName: model.name), privacy: .public)")
                        self.whisperContext = loadedContext
                        return VoiceInkLocalWhisperContextPlan(
                            context: loadedContext,
                            shouldReleaseContext: false
                        )
                    }

                    let availableModels = await self.modelProvider?.availableModels ?? []
                    guard let modelURL = VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                        forModelName: model.name,
                        in: availableModels
                    ) else {
                        self.logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSModelFileNotFoundMessage(modelName: model.name), privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: request.failurePlatform)
                    }

                    self.logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSLoadingModelMessage(modelName: model.name), privacy: .public)")
                    do {
                        let context = try await WhisperContext.createContext(path: modelURL.path)
                        self.whisperContext = context
                        return VoiceInkLocalWhisperContextPlan(
                            context: context,
                            shouldReleaseContext: true,
                            shouldReleaseContextOnFailure: false
                        )
                    } catch {
                        self.logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSModelLoadFailedMessage(modelName: model.name, localizedDescription: error.localizedDescription), privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: request.failurePlatform)
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL)
                        if samples == nil {
                            self.logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSAudioSamplesProcessingFailedMessage, privacy: .public)")
                        }
                        return samples
                    } catch {
                        self.logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSAudioSamplesProcessingFailedMessage, privacy: .public)")
                        throw error
                    }
                },
                runTranscription: { context, samples, language, prompt in
                    let success = await context.fullTranscribe(
                        samples: samples,
                        language: language,
                        prompt: prompt
                    )
                    if !success {
                        self.logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSCoreTranscriptionFailedMessage, privacy: .public)")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    if self.whisperContext === context {
                        self.whisperContext = nil
                    }
                }
            )
        )

        logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.macOSTranscriptionCompletedMessage, privacy: .public)")

        return text
    }
}
