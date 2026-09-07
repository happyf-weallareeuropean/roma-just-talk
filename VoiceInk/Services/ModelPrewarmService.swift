import Foundation
import SwiftData
import os
import VoiceInkCore
import VoiceInkQwen
import AppKit

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    private let whisperModelManager: WhisperModelManager
    private let modelContext: ModelContext
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.modelPrewarm
    )
    private let serviceRegistry: TranscriptionServiceRegistry
    private let loadFluidAudioModel: (FluidAudioModel) async throws -> Void
    private var prewarmTask: Task<Void, Never>?

    init(
        transcriptionModelManager: TranscriptionModelManager,
        whisperModelManager: WhisperModelManager,
        modelContext: ModelContext,
        qwenRuntimeResult: Result<QwenRuntime, Error>,
        serviceRegistry: TranscriptionServiceRegistry? = nil,
        loadFluidAudioModel: ((FluidAudioModel) async throws -> Void)? = nil
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.whisperModelManager = whisperModelManager
        self.modelContext = modelContext
        let registry = serviceRegistry ?? TranscriptionServiceRegistry(
            modelProvider: whisperModelManager,
            modelsDirectory: whisperModelManager.modelsDirectory,
            modelContext: modelContext,
            qwenRuntimeResult: qwenRuntimeResult
        )
        self.serviceRegistry = registry
        self.loadFluidAudioModel = loadFluidAudioModel ?? { model in
            try await registry.fluidAudioTranscriptionService.loadModel(for: model)
        }
        setupNotifications()
        schedulePrewarmOnAppLaunch()
    }

    // MARK: - Notification Setup

    private func setupNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // Trigger on wake from sleep
        center.addObserver(
            self,
            selector: #selector(schedulePrewarm),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(modelSelectionChanged), name: .didChangeModel, object: nil
        )

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.initializedMessage, privacy: .public)")
    }

    // MARK: - Trigger Handlers

    /// Trigger on app launch (cold start)
    private func schedulePrewarmOnAppLaunch() {
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.appLaunchScheduledMessage, privacy: .public)")
        scheduleDelayedPrewarm()
    }

    /// Trigger on wake from sleep or screen unlock
    @objc private func schedulePrewarm() {
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.macActivityScheduledMessage, privacy: .public)")
        scheduleDelayedPrewarm()
    }

    private func scheduleDelayedPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = Task { [weak self] in
            do { try await Task.sleep(for: VoiceInkModelRuntimePreference.prewarmScheduleDelay) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            await performPrewarm()
        }
    }

    @objc private func modelSelectionChanged() {
        scheduleDelayedPrewarm()
    }

    // MARK: - Core Prewarming Logic

    func performPrewarm() async {
        let currentModel = transcriptionModelManager.currentTranscriptionModel
        let prewarmPlan = VoiceInkModelPrewarmPlan.plan(
            isEnabled: VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(),
            hasCurrentModel: currentModel != nil,
            shouldPrewarmModel: currentModel?.transcriptionRuntimeResourcePlan.shouldPrewarmModel ?? false
        )

        guard prewarmPlan.shouldRun else {
            if let diagnosticMessage = prewarmPlan.diagnosticMessage {
                logger.notice("\(diagnosticMessage, privacy: .public)")
            }
            return
        }
        // Runtime loading may download missing files; prewarm only installed models.
        guard !Task.isCancelled, let currentModel,
              transcriptionModelManager.usableModels.contains(where: { $0.name == currentModel.name }) else { return }

        logger.notice("\(VoiceInkModelPrewarmDiagnostics.prewarmingMessage(modelDisplayName: currentModel.displayName), privacy: .public)")
        let startTime = Date()

        do {
            try await currentModel.transcriptionRuntimeResourcePlan.applyRecordingStartupRuntimeState(
                loadLocalWhisperModel: {
                    guard let localModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                        forModelName: currentModel.name,
                        in: self.whisperModelManager.availableModels
                    ) else {
                        throw VoiceInkEngineError.modelLoadFailed
                    }
                    try await self.whisperModelManager.prewarmModel(localModel)
                },
                loadLocalFluidAudioModel: {
                    guard let fluidAudioModel = currentModel as? FluidAudioModel else {
                        throw VoiceInkEngineError.modelLoadFailed
                    }
                    try await self.loadFluidAudioModel(fluidAudioModel)
                },
                loadLocalQwenModel: {
                    await self.transcriptionModelManager.awaitQwenRecordingSelection()
                    try Task.checkCancellation()
                    guard self.transcriptionModelManager.currentTranscriptionModel?.name == currentModel.name,
                          self.transcriptionModelManager.usableModels.contains(where: { $0.name == currentModel.name }) else {
                        throw CancellationError()
                    }
                    try await self.serviceRegistry.qwenTranscriptionService.loadModel()
                }
            )
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("\(VoiceInkModelPrewarmDiagnostics.completedMessage(duration: duration), privacy: .public)")
        } catch is CancellationError {
        } catch {
            logger.error("\(VoiceInkModelPrewarmDiagnostics.failedMessage(errorDescription: error.localizedDescription), privacy: .public)")
        }
    }

    deinit {
        prewarmTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.notice("\(VoiceInkModelPrewarmDiagnostics.deinitializedMessage, privacy: .public)")
    }
}
