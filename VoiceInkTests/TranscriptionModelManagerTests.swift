import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

private final class ModelChangeNotificationRecorder: NSObject {
    private(set) var modelChangeCount = 0
    private(set) var modelChangeUserInfos: [[AnyHashable: Any]?] = []
    private(set) var settingsChangeCount = 0

    @objc func modelDidChange(_ notification: Notification) {
        modelChangeCount += 1
        modelChangeUserInfos.append(notification.userInfo)
    }

    @objc func settingsDidChange(_ notification: Notification) {
        settingsChangeCount += 1
    }
}

@Suite(.serialized)
struct TranscriptionModelManagerTests {
    @Test @MainActor func refreshingRegisteredFallbackDoesNotPersistIt() {
        withFreshModelDefaults {
            let whisper = makeWhisperManager()
            let fluid = FluidAudioModelManager()
            let manager = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
            manager.refreshAllAvailableModels()
            manager.loadCurrentTranscriptionModel()
            manager.refreshAllAvailableModels()
            manager.refreshAllAvailableModels()

            #expect(manager.currentTranscriptionModel?.name == VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName)
            #expect(persistedPreference(VoiceInkUserDefaultsKey.currentTranscriptionModel) == nil)
            #expect(persistedPreference(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage) == nil)
        }
    }

    @Test @MainActor func metadataRefreshUpdatesDescriptorAndPreservesExplicitPreferences() {
        let restore = prepareFreshModelDefaults()
        defer { restore() }
        let whisper = makeWhisperManager()
        let fluid = FluidAudioModelManager()
        let manager = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
        let selectedModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        manager.setDefaultTranscriptionModel(selectedModel)
        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("en")

        let recorder = ModelChangeNotificationRecorder()
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(ModelChangeNotificationRecorder.modelDidChange(_:)),
            name: .didChangeModel,
            object: nil
        )
        defer { NotificationCenter.default.removeObserver(recorder) }

        manager.refreshAllAvailableModels()
        #expect(manager.currentTranscriptionModel?.id == manager.allAvailableModels.first(where: { $0.name == selectedModel.name })?.id)
        #expect(manager.currentTranscriptionModel?.id != selectedModel.id)
        #expect(persistedPreference(VoiceInkUserDefaultsKey.currentTranscriptionModel) == selectedModel.name)
        #expect(persistedPreference(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage) == "en")
        #expect(recorder.modelChangeCount == 1)

        let returning = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
        returning.loadCurrentTranscriptionModel()
        #expect(returning.currentTranscriptionModel?.name == selectedModel.name)
    }

    @Test @MainActor func loadingSavedCurrentModelBroadcastsModelAndSettingsChange() {
        let oldModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
        let oldLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage")
        defer {
            restoreDefault(oldModelName, forKey: "CurrentTranscriptionModel")
            restoreDefault(oldLanguage, forKey: "SelectedLanguage")
        }

        let recorder = ModelChangeNotificationRecorder()
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(ModelChangeNotificationRecorder.modelDidChange(_:)),
            name: .didChangeModel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            recorder,
            selector: #selector(ModelChangeNotificationRecorder.settingsDidChange(_:)),
            name: .AppSettingsDidChange,
            object: nil
        )
        defer { NotificationCenter.default.removeObserver(recorder) }

        UserDefaults.standard.set("ggml-tiny", forKey: "CurrentTranscriptionModel")
        UserDefaults.standard.set("auto", forKey: "SelectedLanguage")

        let whisperModelManager = WhisperModelManager(
            modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let modelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: FluidAudioModelManager()
        )

        modelManager.loadCurrentTranscriptionModel()

        #expect(modelManager.currentTranscriptionModel?.name == "ggml-tiny")
        #expect(recorder.modelChangeCount >= 1)
        #expect(recorder.modelChangeUserInfos.allSatisfy { $0?.isEmpty ?? true })
        #expect(recorder.settingsChangeCount >= 1)
    }

    private func restoreDefault(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor private func makeWhisperManager() -> WhisperModelManager {
        WhisperModelManager(modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @MainActor private func withFreshModelDefaults(_ body: () -> Void) {
        let restore = prepareFreshModelDefaults()
        defer { restore() }
        body()
    }

    @MainActor private func prepareFreshModelDefaults() -> () -> Void {
        let defaults = UserDefaults.standard
        let domain = defaultsDomainName
        let previousDomain = defaults.persistentDomain(forName: domain) ?? [:]
        let previousRegistration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        let keys = [VoiceInkUserDefaultsKey.currentTranscriptionModel, VoiceInkUserDefaultsKey.selectedTranscriptionLanguage]
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.register(defaults: [
            VoiceInkUserDefaultsKey.currentTranscriptionModel: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage: "en"
        ])
        return {
            for key in keys {
                if let previous = previousDomain[key] { defaults.set(previous, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            defaults.setVolatileDomain(previousRegistration, forName: UserDefaults.registrationDomain)
        }
    }

    private var defaultsDomainName: String {
        Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }

    private func persistedPreference(_ key: String) -> String? {
        UserDefaults.standard.persistentDomain(forName: defaultsDomainName)?[key] as? String
    }
}
