import Foundation
import SwiftData
import os

/// Handles the full post-recording pipeline:
/// transcribe → filter → format → word-replace → prompt-detect → AI enhance → start paste + dismiss → save
@MainActor
class TranscriptionPipeline {
    private let modelContext: ModelContext
    private let serviceRegistry: TranscriptionServiceRegistry
    private let enhancementService: AIEnhancementService?
    private let promptDetectionService = PromptDetectionService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionPipeline")

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

    private struct PrivacySafeTextMetrics {
        let characters: Int
        let words: Int
        let lines: Int

        init(_ text: String) {
            characters = text.count
            words = WordCounter.count(in: text)
            lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        }
    }

    private func logInsertionContext(_ context: TranscriptionOutputFilter.TextInsertionContext?) {
        let selectedCharacters = context?.selectedText?.count ?? 0
        logger.notice(
            "Dictation insertion context available=\(context != nil, privacy: .public) precedingChars=\(context?.precedingText.count ?? 0, privacy: .public) selectedChars=\(selectedCharacters, privacy: .public)"
        )
    }

    private func logCleanupStage(_ stage: String, before: String, after: String) {
        let beforeMetrics = PrivacySafeTextMetrics(before)
        let afterMetrics = PrivacySafeTextMetrics(after)
        logger.notice(
            "Dictation cleanup stage=\(stage, privacy: .public) changed=\(before != after, privacy: .public) beforeChars=\(beforeMetrics.characters, privacy: .public) afterChars=\(afterMetrics.characters, privacy: .public) beforeWords=\(beforeMetrics.words, privacy: .public) afterWords=\(afterMetrics.words, privacy: .public) beforeLines=\(beforeMetrics.lines, privacy: .public) afterLines=\(afterMetrics.lines, privacy: .public)"
        )
    }

    private func logPastePrepared(source: String, text: String) {
        let metrics = PrivacySafeTextMetrics(text)
        logger.notice(
            "Dictation paste prepared source=\(source, privacy: .public) chars=\(metrics.characters, privacy: .public) words=\(metrics.words, privacy: .public) lines=\(metrics.lines, privacy: .public)"
        )
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
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCancel: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?
        var didInsertSessionMetric = false

        func restorePromptDetectionSettingsIfNeeded() async {
            if let result = promptDetectionResult,
               let enhancementService,
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
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
                let duration = await AudioFileMetadata.duration(for: audioURL)
                canceledDuration = duration > 0 ? duration : nil
            }

            transcription.markAsCanceledTranscription(
                duration: canceledDuration,
                modelName: transcription.transcriptionModelName ?? model.displayName
            )

            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save canceled transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        do {
            let insertionContext = TranscriptionOutputFilter.currentInsertionContext()
            logInsertionContext(insertionContext)
            let transcriptionStart = Date()
            var text: String
            if let session {
                text = try await session.transcribe(audioURL: audioURL)
            } else {
                text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
            }
            let rawText = text
            text = TranscriptionOutputFilter.filter(rawText)
            logCleanupStage("filter", before: rawText, after: text)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if shouldCancel() { await finishCanceledTranscription(); return }

            let filteredText = text
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            logCleanupStage("trim", before: filteredText, after: text)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                let textBeforeFormatting = text
                text = WhisperTextFormatter.format(text)
                logCleanupStage("formatter", before: textBeforeFormatting, after: text)
            }

            let textBeforeReplacements = text
            text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
            logCleanupStage("word_replacements", before: textBeforeReplacements, after: text)
            let textBeforeUserCleanup = text
            let cleanedText = TranscriptionOutputFilter.applyUserCleanupPreferences(text)
            logCleanupStage("user_cleanup_preferences", before: textBeforeUserCleanup, after: cleanedText)
            let polishedCleanedText = TranscriptionOutputFilter.applyInsertionPolish(cleanedText, context: insertionContext)
            logCleanupStage("insertion_polish", before: cleanedText, after: polishedCleanedText)

            let actualDuration = await AudioFileMetadata.duration(for: audioURL)

            transcription.text = polishedCleanedText
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            let spacedCleanedText = TranscriptionOutputFilter.applyInsertionSpacing(polishedCleanedText, context: insertionContext)
            logCleanupStage("insertion_spacing", before: polishedCleanedText, after: spacedCleanedText)
            if isPasteableText(spacedCleanedText) {
                finalPastedText = spacedCleanedText
                logPastePrepared(source: "transcription", text: spacedCleanedText)
            } else {
                finalPastedText = nil
            }

            if let enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
            let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
            let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
            let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold && !(promptDetectionResult?.shouldEnableAI == true)

            if let enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured,
               !shouldSkipEnhancement {
                if shouldCancel() { await finishCanceledTranscription(); return }

                onStateChange(.enhancing)
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    let polishedEnhancedText = TranscriptionOutputFilter.applyInsertionPolish(enhancedText, context: insertionContext)
                    logCleanupStage("enhancement_insertion_polish", before: enhancedText, after: polishedEnhancedText)
                    transcription.enhancedText = polishedEnhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    let spacedEnhancedText = TranscriptionOutputFilter.applyInsertionSpacing(polishedEnhancedText, context: insertionContext)
                    logCleanupStage("enhancement_insertion_spacing", before: polishedEnhancedText, after: spacedEnhancedText)
                    if isPasteableText(spacedEnhancedText) {
                        finalPastedText = spacedEnhancedText
                        logPastePrepared(source: "enhancement", text: spacedEnhancedText)
                    }
                } catch {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    transcription.enhancedText = "Enhancement failed: \(errorDescription)"
                    let shortReason = String(errorDescription.prefix(80))
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "Enhancement failed: \(shortReason)",
                            type: .warning
                        )
                    }
                    if shouldCancel() { await finishCanceledTranscription(); return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue
        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

            if let nativeAppleError = error as? NativeAppleTranscriptionService.ServiceError,
               case .assetDownloadRequired = nativeAppleError {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: errorDescription,
                        type: .error,
                        duration: 5.0
                    )
                }
            }

            transcription.text = "Transcription Failed: \(errorDescription)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        func saveTranscriptionAndPostCompletion() {
            if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
                do {
                    didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                        transcription: transcription,
                        model: model,
                        in: modelContext
                    )
                } catch {
                    logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
                }
            }

            do {
                try modelContext.save()
                if didInsertSessionMetric {
                    NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)
                }
                NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
            } catch {
                logger.error("Failed to save transcription: \(error.localizedDescription, privacy: .public)")
            }
        }

        if shouldCancel() {
            await finishCanceledTranscription()
            return
        }

        if var textToPaste = finalPastedText,
           isPasteableText(textToPaste),
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            if case .trialExpired = licenseViewModel.licenseState {
                textToPaste = """
                    Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                    \n\(textToPaste)
                    """
            }

            let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
            let pastedText = textToPaste + (appendSpace ? " " : "")
            _ = await CursorPaster.startPasteAtCursor(pastedText).value
            let autoSendKey = PowerModeManager.shared.currentActiveConfiguration?.autoSendKey
            SoundManager.shared.playStopSound()
            await restorePromptDetectionSettingsAndDismiss {
                if let autoSendKey, autoSendKey.isEnabled {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        CursorPaster.performAutoSend(autoSendKey)
                    }
                }
            }
        } else {
            await restorePromptDetectionSettingsAndDismiss()
        }

        saveTranscriptionAndPostCompletion()
    }

    private func isPasteableText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
