import Foundation
import SwiftData
import Testing
import VoiceInkCore
import VoiceInkQwen
@testable import VoiceInk

@Suite(.serialized)
struct QwenRecordingSelectionTests {
    @Test @MainActor func rapidReselectionStillDrainsOldRecording() async {
        let gate = SelectionDrainGate()
        let manager = QwenModelManager(runtimeResult: .failure(SelectionFixtureError.unusedRuntime)) {
            await gate.drain()
        }
        // All changes occur before their asynchronous cleanup tasks can execute.
        manager.recordingSelectionChanged(isSelected: false)
        manager.recordingSelectionChanged(isSelected: true)
        let awaiting = Task { await manager.awaitRecordingSelection() }
        await gate.waitUntilEntered()
        #expect(gate.calls == 1)
        #expect(!gate.finished)
        gate.release()
        await awaiting.value
        #expect(gate.finished)
    }

    @Test @MainActor func laterDeselectionJoinsInFlightTransition() async {
        let gate = SelectionDrainGate()
        let manager = QwenModelManager(runtimeResult: .failure(SelectionFixtureError.unusedRuntime)) {
            await gate.drain()
        }
        manager.recordingSelectionChanged(isSelected: false)
        await gate.waitUntilEntered()
        let awaiting = Task { await manager.awaitRecordingSelection() }
        manager.recordingSelectionChanged(isSelected: true)
        manager.recordingSelectionChanged(isSelected: false)
        gate.release()
        await awaiting.value
        #expect(gate.calls == 2)
        #expect(gate.finished)
    }

    @Test @MainActor func selectionCancelsDeferredConnectBeforeRuntimeReservation() async throws {
        let schema = Schema([Transcription.self, VocabularyWord.self, WordReplacement.self, SessionMetric.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let whisper = WhisperModelManager(modelsDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let models = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: FluidAudioModelManager())
        models.currentTranscriptionModel = QwenModel()
        let engine = VoiceInkEngine(modelContext: ModelContext(container), whisperModelManager: whisper,
            transcriptionModelManager: models, qwenRuntimeResult: .failure(SelectionFixtureError.unusedRuntime))
        let session = DeferredConnectSession()
        engine.trackQwenRecordingSession(session, model: QwenModel())
        engine.currentSession = session
        _ = try await session.prepare(model: QwenModel(), latencyTraceToken: nil)
        // Runtime has no lease yet. Selection must cancel the session synchronously.
        models.currentTranscriptionModel = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        NotificationCenter.default.post(name: .didChangeModel, object: nil)
        #expect(session.cancelled)
        session.allowConnect()
        await session.waitUntilFinished()
        #expect(!session.connected)
    }
}

private enum SelectionFixtureError: Error { case unusedRuntime }

@MainActor private final class SelectionDrainGate {
    private var entered: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    var calls = 0
    var finished = false

    func drain() async {
        calls += 1
        entered?.resume(); entered = nil
        if !released { await withCheckedContinuation { held = $0 } }
        finished = true
    }
    func waitUntilEntered() async {
        if calls > 0 { return }
        // A known-bad skipped transition must fail, not leave the test hanging.
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.entered?.resume(); self?.entered = nil
        }
        await withCheckedContinuation { entered = $0 }
        timeout.cancel()
    }
    func release() { released = true; held?.resume(); held = nil }
}

@MainActor private final class DeferredConnectSession: TranscriptionSession {
    private var task: Task<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    private var allowed = false
    var cancelled = false
    var connected = false

    func prepare(model: any TranscriptionModel, latencyTraceToken: VoiceInkLatencyTrace.Token?) async throws -> ((Data) -> Void)? {
        task = Task {
            if !allowed { await withCheckedContinuation { gate = $0 } }
            guard !Task.isCancelled else { return }
            connected = true
        }
        return { _ in }
    }
    func transcribe(audioURL: URL) async throws -> String { "" }
    func cancel() { cancelled = true; task?.cancel() }
    func allowConnect() { allowed = true; gate?.resume(); gate = nil }
    func waitUntilFinished() async { await task?.value }
}
