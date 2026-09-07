import Foundation
import SwiftData
import os
import VoiceInkCore

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionPipeline")

    var licenseViewModel: LicenseViewModel

    init(
        modelContext: ModelContext,
        serviceRegistry: TranscriptionServiceRegistry,
        enhancementService: AIEnhancementService?
    ) {
        self.modelContext = modelContext
        self.serviceRegistry = serviceRegistry
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
    }

    /// Run the full pipeline for a given transcription record.
    /// - Parameters:
    ///   - transcription: The pending Transcription SwiftData object to populate and save.
    ///   - audioURL: The recorded audio file.
    ///   - model: The transcription model to use.
    ///   - session: An active streaming session if one was prepared, otherwise nil.
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - shouldCancel: Returns true if the user requested cancellation.
    ///   - onCancel: Called when cancellation is detected to cancel active session state.
    ///   - onDismiss: Called as soon as paste is initiated to dismiss the recorder panel.
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?,
        onStateChange: @escaping (VoiceInkRecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        latencyTrace.event(
            "pipeline.enter",
            details: "model=\(model.displayName) hasStreamingSession=\(session != nil)",
            token: traceToken
        )
        var finalPastedText: String?
        var promptDetectionResult: VoiceInkPromptDetectionResult?

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService {
                enhancementService.restorePromptDetectionSettings(result)
            }
        }

        func restorePromptDetectionSettingsAndDismiss(afterRestore: () -> Void = {}) async {
            await restorePromptDetectionSettingsIfNeeded()
            afterRestore()
            await onDismiss()
        }

        func finishCanceledTranscription() async {
            await onCancel()
            await restorePromptDetectionSettingsIfNeeded()

            let canceledDuration: TimeInterval?
            if transcription.duration > 0 {
                canceledDuration = nil
            } else {
                let durationResult = await AudioFileMetadata.tracedDuration(
                    for: audioURL,
                    executorName: "pipeline.cancel_audio_duration",
                    latencyTraceToken: traceToken
                )
                latencyTrace.executorResumed(durationResult.executorCheckpoint)
                canceledDuration = durationResult.seconds > 0 ? durationResult.seconds : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
            latencyTrace.finish(
                event: "pipeline.cancelled",
                details: "model=\(model.displayName)",
                token: traceToken
            )
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        let cursorContextCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.cursor_context_prefetch",
            token: traceToken
        )
        let preparedCursorTextContext = Task { @MainActor in
            latencyTrace.executorResumed(cursorContextCheckpoint)
            let span = latencyTrace.begin(
                "pipeline.cursor_context_prefetch",
                token: traceToken
            )
            let context = CursorTextContextReader.prepareTextBeforeCursor()
            if VoiceInkPasteMethod.current() == .standard {
                CursorTextContextReader.prepareCommandVMenuItem(
                    for: context,
                    latencyTraceToken: traceToken
                )
            }
            latencyTrace.end(
                span,
                details: "available=\(context != nil)"
            )
            return context
        }
        defer { preparedCursorTextContext.cancel() }
        let pasteAuthorizationCheckpoint = latencyTrace.executorEnqueued(
            "pipeline.paste_authorization_preflight",
            token: traceToken
        )
        let pasteAuthorizationPreflight = Task { @MainActor in
            latencyTrace.executorResumed(pasteAuthorizationCheckpoint)
            let span = latencyTrace.begin(
                "pipeline.paste_authorization_preflight",
                token: traceToken
            )
            let isTrusted = CursorPaster.preflightPasteAuthorization()
            latencyTrace.end(span, details: "trusted=\(isTrusted)")
        }

        do {
            let transcriptionStart = Date()
            let rawText: String
            let transcriptionSpan = latencyTrace.begin("pipeline.transcribe", token: traceToken)
            do {
                if let session {
                    rawText = try await session.transcribe(audioURL: audioURL)
                } else {
                    rawText = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
                }
                latencyTrace.end(
                    transcriptionSpan,
                    details: "result=success rawChars=\(rawText.count)"
                )
            } catch {
                latencyTrace.end(
                    transcriptionSpan,
                    details: "result=failure error=\(String(describing: type(of: error)))"
                )
                throw error
            }
            let cleanupSpan = latencyTrace.begin("pipeline.cleanup", token: traceToken)
            let cleanupConfiguration = VoiceInkTranscriptionCleanupConfiguration.current()
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            let textPlan = VoiceInkTranscriptionRunPreparation.prepareRawTextForEnhancement(
                rawText,
                cleanupConfiguration: cleanupConfiguration
            ) { text in
                DictionaryService.applyWordReplacements(to: text, using: modelContext)
            }
            let text = textPlan.textForEnhancement
            let cleanedText = textPlan.cleanedText
            latencyTrace.end(
                cleanupSpan,
                details: "cleanedChars=\(cleanedText.count) enhancementInputChars=\(text.count)"
            )
            if shouldCancel() { await finishCanceledTranscription(); return }

            transcription.text = cleanedText
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            finalPastedText = cleanedText
            var enhancementResult: VoiceInkAIEnhancementResult?
            var enhancementFailureReason: String?

            if let enhancementService,
               enhancementService.isConfigured,
               enhancementService.hasPromptTriggerWords {
                let detectionResult = enhancementService.analyzePromptTrigger(in: text)
                promptDetectionResult = detectionResult
                enhancementService.applyPromptDetectionResult(detectionResult)
            }

            let enhancementRequest = textPlan.enhancementRequest(
                isEnhancementEnabled: enhancementService?.isEnhancementEnabled == true,
                isEnhancementConfigured: enhancementService?.isConfigured == true,
                promptDetectionResult: promptDetectionResult,
                skipConfiguration: VoiceInkPostProcessingSkipConfiguration.current()
            )

            if let enhancementService,
               let enhancementRequest {
                if shouldCancel() { await finishCanceledTranscription(); return }

                onStateChange(.enhancing)

                let enhancementSpan = latencyTrace.begin("pipeline.enhancement", token: traceToken)
                do {
                    let enhancement = try await enhancementService.enhance(enhancementRequest.text)
                    latencyTrace.end(
                        enhancementSpan,
                        details: "result=success chars=\(enhancement.text.count)"
                    )
                    enhancementResult = enhancement
                    finalPastedText = enhancement.text
                } catch {
                    latencyTrace.end(
                        enhancementSpan,
                        details: "result=failure error=\(String(describing: type(of: error)))"
                    )
                    let errorDescription = VoiceInkErrorDescription.text(for: error)
                    enhancementFailureReason = errorDescription
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: VoiceInkPostProcessingFailurePresentation.enhancementFailureNotificationTitle(
                                reason: errorDescription
                            ),
                            type: .warning
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return }
                }
            }

            let completedDraft = VoiceInkCompletedTranscriptionDraft(
                cleanedText: cleanedText,
                duration: transcription.duration,
                audioFileURL: transcription.audioFileURL,
                transcriptionModelName: model.displayName,
                transcriptionDuration: transcriptionDuration,
                powerModeName: transcription.powerModeName,
                powerModeEmoji: transcription.powerModeEmoji,
                enhancementResult: enhancementResult,
                enhancementFailureReason: enhancementFailureReason,
                enhancementFailurePolicy: .storeFailureText
            )
            transcription.applyCompletedDraft(completedDraft)
        } catch {
            latencyTrace.event(
                "pipeline.transcription_failed",
                details: "error=\(String(describing: type(of: error)))",
                token: traceToken
            )
            let errorDescription = VoiceInkErrorDescription.text(for: error)

            if let nativeAppleError = error as? VoiceInkNativeAppleTranscriptionFailureKind,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.markAsFailedTranscription(reason: errorDescription)
        }

        func saveTranscriptionAndPostCompletion() {
            let shouldRecordSessionMetric = transcription.transcriptionState == .completed
            let didInsertSessionMetric: Bool
            if shouldRecordSessionMetric {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                    didInsertSessionMetric = false
                }
            } else {
                didInsertSessionMetric = false
            }

            var didSaveTranscription = false
            do {
                try modelContext.save()
                didSaveTranscription = true
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
            }

        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        let pasteDecision = VoiceInkTranscriptionPasteOutputPolicy.decision(
            text: finalPastedText,
            transcriptionCompleted: transcription.transcriptionState == .completed
        )
        if SpecialShortcutEmptyTranscriptionFallback.consumeIfNeeded(for: transcription, modelContext: modelContext) {
            latencyTrace.event("pipeline.empty_transcription_fallback", token: traceToken)
            SoundManager.shared.play(.stop)
            await restorePromptDetectionSettingsAndDismiss()
        } else if var textToPaste = pasteDecision.textToPaste {
            let pastePreparationSpan = latencyTrace.begin("pipeline.paste_prepare", token: traceToken)
            textToPaste = await CursorPaster.preparedTextForPaste(
                textToPaste,
                preparedCursorTextContext: preparedCursorTextContext
            )

            let isTrialExpired: Bool
            if case .trialExpired = licenseViewModel.licenseState {
                isTrialExpired = true
            } else {
                isTrialExpired = false
            }
            let pastedText = VoiceInkTranscriptionPasteOutputPolicy.finalPastedText(
                textToPaste,
                appendTrailingSpace: VoiceInkAppendTrailingSpacePreference.isEnabled(),
                isTrialExpired: isTrialExpired
            )
            latencyTrace.end(pastePreparationSpan, details: "chars=\(pastedText.count)")
            let pasteSpan = latencyTrace.begin("pipeline.paste_command", token: traceToken)
            await pasteAuthorizationPreflight.value
            let pasteResult = await CursorPaster.startPasteAtCursor(
                pastedText,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: traceToken
            ).value
            latencyTrace.end(
                pasteSpan,
                details: "textDelivered=\(pasteResult.didDeliverText) result=\(String(describing: pasteResult))"
            )
            let autoSendKey = PowerModeManager.shared.activeConfiguration?.autoSendKey
            let stopSoundSpan = latencyTrace.begin("pipeline.stop_sound", token: traceToken)
            SoundManager.shared.play(.stop)
            latencyTrace.end(stopSoundSpan)
            let dismissSpan = latencyTrace.begin("pipeline.dismiss_recorder", token: traceToken)
            await restorePromptDetectionSettingsAndDismiss {
                if pasteResult.didDeliverText,
                   let autoSendKey,
                   let delayAfterPaste = VoiceInkAutoSendPolicy.delayAfterPasteNanoseconds(for: autoSendKey) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: delayAfterPaste)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
            latencyTrace.end(dismissSpan)
        } else {
            latencyTrace.event(
                "pipeline.no_paste",
                details: "state=\(transcription.transcriptionState) pasteableText=\(pasteDecision.textToPaste != nil)",
                token: traceToken
            )
            if pasteDecision.shouldPlayCompletionSoundWithoutPaste {
                SoundManager.shared.play(.stop)
            }
            await restorePromptDetectionSettingsAndDismiss()
        }

        if transcription.transcriptionState == .completed,
           transcription.duration <= 0 {
            let durationSpan = latencyTrace.begin("pipeline.audio_duration", token: traceToken)
            let durationResult = await AudioFileMetadata.tracedDuration(
                for: audioURL,
                executorName: "pipeline.audio_duration",
                latencyTraceToken: traceToken
            )
            latencyTrace.executorResumed(durationResult.executorCheckpoint)
            transcription.duration = durationResult.seconds
            latencyTrace.end(durationSpan)
        }

        let saveSpan = latencyTrace.begin("pipeline.save", token: traceToken)
        saveTranscriptionAndPostCompletion()
        latencyTrace.end(saveSpan)
        latencyTrace.finish(
            event: "pipeline.complete",
            details: "state=\(transcription.transcriptionState) finalChars=\(finalPastedText?.count ?? 0)",
            token: traceToken
        )
    }
}
