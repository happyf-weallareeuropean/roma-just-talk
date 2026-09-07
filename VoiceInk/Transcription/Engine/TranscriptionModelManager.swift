import Foundation
import SwiftUI
import os
import VoiceInkCore

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = TranscriptionModelRegistry.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, fluidAudioModelManager: FluidAudioModelManager) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { availabilityFacts(for: $0).isUsable }
    }

    func isAvailableOnCurrentOS(_ model: any TranscriptionModel) -> Bool {
        availabilityFacts(for: model).isAvailableOnCurrentOS
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        let savedModelName = VoiceInkCurrentTranscriptionModelPreference.modelName()
        let savedModel = savedModelName.flatMap { name in
            allAvailableModels.first(where: { $0.name == name })
        }
        let loadPlan = VoiceInkCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: savedModelName,
            candidateModelExists: savedModel != nil,
            isCandidateAvailableOnCurrentOS: savedModel.map(isAvailableOnCurrentOS) ?? false
        )

        loadPlan.applyRuntimeState(
            clearStoredModelName: {
                VoiceInkCurrentTranscriptionModelPreference.clearModelName()
                currentTranscriptionModel = nil
            },
            restoreSavedModel: {
                guard let savedModel else { return }
                currentTranscriptionModel = savedModel
                ensureSelectedLanguageIsSupported(by: savedModel)
                notifyCurrentModelDidChange()
            }
        )
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        guard isAvailableOnCurrentOS(model) else {
            NotificationManager.shared.showNotification(
                title: model.provider == .nvidia
                    ? "NVIDIA cloud transcription requires macOS 15 or later."
                    : VoiceInkNativeAppleTranscriptionPolicy.requiresMacOS26Title(modelDisplayName: model.displayName),
                type: .error
            )
            return
        }

        self.currentTranscriptionModel = model
        VoiceInkCurrentTranscriptionModelPreference.saveModelName(model.name)
        ensureSelectedLanguageIsSupported(by: model)

        let localWhisperRuntimeUpdate = model
            .transcriptionRuntimeResourcePlan
            .modelSelectionLocalWhisperRuntimeUpdate
        applyLocalWhisperRuntimeUpdate(localWhisperRuntimeUpdate)

        notifyCurrentModelDidChange()
    }

    private func notifyCurrentModelDidChange() {
        NotificationCenter.default.post(name: .didChangeModel, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func ensureSelectedLanguageIsSupported(by model: any TranscriptionModel) {
        let plan = model.transcriptionLanguageSelectionFacts.repairPlan(
            for: VoiceInkTranscriptionLanguagePreference.storedLanguage()
        )

        plan.applyRuntimeState { languageToSave in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(languageToSave)
            VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage()
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    private func availabilityFacts(for model: any TranscriptionModel) -> VoiceInkTranscriptionModelAvailabilityFacts {
        let availabilityRequirement = model.provider.transcriptionModelAvailabilityRequirement
        let isAvailableOnCurrentOS: Bool
        if let remoteProvider = model.provider.remoteTranscriptionProviderKind {
            isAvailableOnCurrentOS = remoteProvider.isSupportedOnCurrentOS
        } else {
            isAvailableOnCurrentOS = availabilityRequirement.requiresCurrentOSSupport
                ? isAvailableOnCurrentOSForNativeAppleTranscription
                : true
        }
        let downloadedLocalWhisperModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
            forModelName: model.name,
            in: whisperModelManager?.availableModels ?? []
        )

        return model.transcriptionModelAvailabilityFacts(
            hasConfiguredAPIKey: hasConfiguredAPIKey(for: model),
            isAvailableOnCurrentOS: isAvailableOnCurrentOS,
            isLocalFluidAudioModelDownloaded: fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false,
            isLocalWhisperModelDownloaded: downloadedLocalWhisperModel != nil
        )
    }

    private func hasConfiguredAPIKey(for model: any TranscriptionModel) -> Bool {
        guard model.provider.transcriptionModelAvailabilityRequirement.requiresConfiguredAPIKey else {
            return false
        }
        return APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
    }

    private var isAvailableOnCurrentOSForNativeAppleTranscription: Bool {
        if #available(macOS 26, *) {
            return true
        } else {
            return false
        }
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelRegistry.models
        let importedLocalModelNames = VoiceInkWhisperModelFiles.importedLocalModelNamesToAdd(
            downloadedLocalModels: whisperModelManager?.availableModels ?? [],
            existingModelNames: models.map(\.name)
        )
        models.append(contentsOf: importedLocalModelNames.map(ImportedWhisperModel.init(fileBaseName:)))

        allAvailableModels = models

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            // Refreshing metadata must not turn the registered fallback into a saved user choice.
            currentTranscriptionModel = updatedModel
            ensureSelectedLanguageIsSupported(by: updatedModel)
            notifyCurrentModelDidChange()
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        VoiceInkCurrentTranscriptionModelPreference.clearModelName()
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        let deletionPlan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: currentTranscriptionModel?.name,
            deletedModelName: modelName
        )
        deletionPlan.applyRuntimeState(
            clearCurrentModel: {
                currentTranscriptionModel = nil
                VoiceInkCurrentTranscriptionModelPreference.clearModelName()
            },
            applyLocalWhisperRuntimeUpdate: applyLocalWhisperRuntimeUpdate
        )
        refreshAllAvailableModels()
    }

    private func applyLocalWhisperRuntimeUpdate(_ update: VoiceInkLocalWhisperRuntimeUpdate) {
        update.applyRuntimeState(
            clearLoadedModel: { whisperModelManager?.loadedWhisperModel = nil },
            setIsModelLoaded: { whisperModelManager?.isModelLoaded = $0 }
        )
    }
}
