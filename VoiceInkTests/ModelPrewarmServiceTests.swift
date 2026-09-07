import Foundation
import SwiftData
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct ModelPrewarmServiceTests {
    @Test @MainActor func prewarmRechecksInstalledModelBeforeEveryLoad() async throws {
        let fixture = try PrewarmFixture()
        defer { fixture.restorePreference() }

        // Fresh onboarding has a selected fallback, but no installed files.
        await fixture.service.performPrewarm()
        #expect(fixture.state.loadedNames.isEmpty)

        fixture.state.installed = true
        await fixture.service.performPrewarm()
        #expect(fixture.state.loadedNames == [fixture.model.name])

        fixture.state.installed = false
        await fixture.service.performPrewarm()
        #expect(fixture.state.loadedNames == [fixture.model.name])
    }

    @Test @MainActor func cancelledPrewarmDoesNotLoadInstalledModel() async throws {
        let fixture = try PrewarmFixture()
        defer { fixture.restorePreference() }
        fixture.state.installed = true
        let task = Task { await fixture.service.performPrewarm() }
        task.cancel()
        await task.value
        #expect(fixture.state.loadedNames.isEmpty)
    }
}

private enum PrewarmFixtureError: Error { case unusedRuntime }

@MainActor private final class PrewarmFixture {
    final class State {
        var installed = false
        var loadedNames: [String] = []
    }

    let state: State
    let model = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
    let whisper: WhisperModelManager
    let fluid: FluidAudioModelManager
    let models: TranscriptionModelManager
    let service: ModelPrewarmService
    private let previousPreference: Any?

    init() throws {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        previousPreference = UserDefaults.standard.persistentDomain(forName: domain)?[VoiceInkModelRuntimePreference.userDefaultsKey]
        let state = State()
        self.state = state
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        whisper = WhisperModelManager(modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        fluid = FluidAudioModelManager(client: FluidAudioModelDownloadClient(
            modelsExist: { _ in state.installed }, cacheDirectoryExists: { _ in state.installed },
            validateCache: { _ in state.installed }, downloadAndLoad: { _, _, _ in
                Issue.record("Prewarm must not start a managed download")
            }
        ))
        models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid)
        models.currentTranscriptionModel = model
        service = ModelPrewarmService(transcriptionModelManager: models, whisperModelManager: whisper,
            modelContext: ModelContext(container), qwenRuntimeResult: .failure(PrewarmFixtureError.unusedRuntime),
            loadFluidAudioModel: { state.loadedNames.append($0.name) })
        VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(true)
    }

    func restorePreference() {
        if let previousPreference {
            UserDefaults.standard.set(previousPreference, forKey: VoiceInkModelRuntimePreference.userDefaultsKey)
        } else {
            VoiceInkModelRuntimePreference.clear()
        }
    }
}
