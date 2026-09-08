import Foundation
import VoiceInkCore

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private var isApplyingPowerModeConfig = false

    private weak var stateProvider: (any PowerModeStateProvider)?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    /// Configure with new VoiceInkEngine-based provider.
    func configure(engine: any PowerModeStateProvider, enhancementService: AIEnhancementService) {
        self.stateProvider = engine
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let stateProvider = stateProvider, let enhancementService = enhancementService else {
            print(VoiceInkPowerModeSessionDiagnostics.notConfiguredMessage)
            return
        }

        let beginPlan = VoiceInkPowerModeSessionBeginPlan.plan(activeSession: loadSession())
        beginPlan.applyRuntimeState(
            id: UUID(),
            startTime: Date(),
            originalState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            ),
            saveSession: saveSession,
            installSettingsObserver: {
                NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
            }
        )

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false

        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        VoiceInkPowerModeSessionPreference.clear()
    }

    @objc func updateSessionSnapshot() {
        let snapshotPlan = VoiceInkPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: isApplyingPowerModeConfig,
            activeSession: loadSession()
        )
        guard let stateProvider = stateProvider,
              let enhancementService = enhancementService else { return }

        snapshotPlan.applyRuntimeState(
            currentState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            ),
            saveSession: saveSession
        )
    }

    private func currentApplicationState(
        stateProvider: any PowerModeStateProvider,
        enhancementService: AIEnhancementService
    ) -> VoiceInkPowerModeApplicationState {
        let aiService = enhancementService.getAIService()

        return VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId,
            selectedAIProvider: aiService.selectedProvider.rawValue,
            selectedAIModel: aiService.currentModel,
            selectedLanguage: VoiceInkTranscriptionLanguagePreference.storedLanguage(),
            transcriptionModelName: stateProvider.currentTranscriptionModel?.name,
            cleanupSettings: VoiceInkTranscriptionCleanupSettings.current()
        )
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            VoiceInkPowerModeSessionApplicationPlan.applying(
                config: config,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func restoreState(_ state: VoiceInkPowerModeApplicationState) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            VoiceInkPowerModeSessionApplicationPlan.restoring(
                state: state,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func applySessionApplicationPlan(
        _ plan: VoiceInkPowerModeSessionApplicationPlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        await plan.applyRuntimeState(
            applyPreferenceApplication: applyPreferenceApplication,
            applyModelResourcePlan: { plan in
                await self.applyModelResourcePlan(plan, stateProvider: stateProvider)
            },
            applyLanguageApplicationPlan: applyLanguageApplicationPlan,
            postConfigurationApplied: {
                NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
            }
        )
    }

    private func applyPreferenceApplication(_ application: VoiceInkPowerModePreferenceApplication) {
        guard let enhancementService else { return }

        let aiService = enhancementService.getAIService()
        application.applyRuntimeState(
            setEnhancementEnabled: { enhancementService.isEnhancementEnabled = $0 },
            setUseScreenCaptureContext: { enhancementService.useScreenCaptureContext = $0 },
            setSelectedPromptId: { enhancementService.selectedPromptId = $0 },
            setSelectedAIProvider: { aiService.selectedProvider = $0 },
            selectAIModel: { aiService.selectModel($0) },
            saveTextFormattingEnabled: { VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled($0) },
            setPunctuationCleanupMode: { PunctuationCleanupMode.setCurrent($0) },
            saveLowercaseTranscription: { VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription($0) }
        )
    }

    private func sessionApplicationFacts(
        stateProvider: any PowerModeStateProvider
    ) -> VoiceInkPowerModeSessionApplicationFacts {
        VoiceInkPowerModeSessionApplicationFacts(
            currentModelName: stateProvider.currentTranscriptionModel?.name,
            availableModelResourceFacts: stateProvider.allAvailableModels.map { $0.powerModeTranscriptionModelResourceFacts },
            availableLocalModelNames: Set(stateProvider.availableModels.map(\.name))
        )
    }

    private func applyLanguageApplicationPlan(_ plan: VoiceInkPowerModeLanguageApplicationPlan) {
        plan.applyRuntimeState(
            saveSelectedLanguage: { language in
                VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(language)
                VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage()
            },
            postLanguageDidChange: {
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        )
    }

    private func applyModelResourcePlan(
        _ plan: VoiceInkPowerModeTranscriptionModelResourcePlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        await plan.applyRuntimeState(
            setDefaultTranscriptionModelNamed: { modelName in
                guard let selectedModel = stateProvider.allAvailableModels.first(where: { $0.name == modelName }) else {
                    return false
                }

                stateProvider.setDefaultTranscriptionModel(selectedModel)
                return true
            },
            cleanupModelResources: {
                await stateProvider.cleanupModelResources()
            },
            loadDownloadedLocalModelNamed: { modelName in
                if let localModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                    forModelName: modelName,
                    in: stateProvider.availableModels
                ) {
                    try await stateProvider.loadModel(localModel)
                }
            },
            handleLocalModelLoadFailure: { modelName, error in
                print(
                    VoiceInkPowerModeSessionDiagnostics.localModelLoadFailedMessage(
                        modelName: modelName,
                        errorDescription: String(describing: error)
                    )
                )
            }
        )
    }

    private func recoverSession() {
        VoiceInkPowerModeSessionRecoveryPlan.plan(activeSession: loadSession()).applyRuntimeState(
            logRecoveringAbandonedSession: {
                print(VoiceInkPowerModeSessionDiagnostics.recoveringAbandonedSessionMessage)
            },
            scheduleEndSession: {
                Task {
                    await self.endSession()
                }
            }
        )
    }

    private func saveSession(_ session: VoiceInkPowerModeSession) {
        do {
            try VoiceInkPowerModeSessionPreference.saveActiveSession(session)
        } catch {
            print(
                VoiceInkPowerModeSessionDiagnostics.saveFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
        }
    }

    private func loadSession() -> VoiceInkPowerModeSession? {
        do {
            return try VoiceInkPowerModeSessionPreference.loadActiveSession()
        } catch {
            print(
                VoiceInkPowerModeSessionDiagnostics.loadFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
            return nil
        }
    }

}
