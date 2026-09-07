import Foundation
import Testing
@testable import VoiceInkQwen

@Test(.timeLimit(.minutes(1)), arguments: [true, false])
func cancelledPrewarmAndRecordingCleanupPreserveImportedFileLoader(prewarmOwnsLoader: Bool) async throws {
    let fixture = try RuntimeLifecycleFixture()
    var events = fixture.events.makeAsyncIterator()
    let prewarm: Task<Void, Error>
    let importedFile: Task<String, Error>
    if prewarmOwnsLoader {
        prewarm = Task { try await fixture.runtime.prewarm() }
        await fixture.loader.waitUntilEntered()
        await waitForModelWait(&events)
        importedFile = Task { try await fixture.runtime.transcribe(samples: []) }
    } else {
        importedFile = Task { try await fixture.runtime.transcribe(samples: []) }
        await fixture.loader.waitUntilEntered()
        await waitForModelWait(&events)
        prewarm = Task { try await fixture.runtime.prewarm() }
    }
    // Both callers are suspended on the same actual runtime loading task.
    await waitForModelWait(&events)
    prewarm.cancel()
    await fixture.runtime.unloadIfIdle()
    let cleanup = Task { try await fixture.runtime.endRecordingSelection() }
    while let event = await events.next() {
        if case .selectionEnding = event { break }
    }
    await fixture.loader.release()

    try await cleanup.value
    expectFixtureFailure(await importedFile.result)
    _ = await prewarm.result
    #expect(await fixture.loader.entries == 1)
    #expect(await fixture.loader.wasCancelled == false)
}

@Test(.timeLimit(.minutes(1)))
func importedFileReservesRuntimeBeforeItsModelIsReady() async throws {
    let fixture = try RuntimeLifecycleFixture()
    var events = fixture.events.makeAsyncIterator()
    let importedFile = Task { try await fixture.runtime.transcribe(samples: []) }
    await fixture.loader.waitUntilEntered()
    let recording = Task { try await fixture.runtime.startStreaming() }
    while let event = await events.next() {
        if case .streamingRequested = event { break }
    }
    // The request has entered the runtime before the pending import can resume.
    await fixture.loader.release()

    switch await recording.result {
    case .failure(QwenRuntimeError.busy): break
    default: Issue.record("Recording must be rejected while a file import owns startup")
    }
    expectFixtureFailure(await importedFile.result)
    #expect(await fixture.loader.entries == 1)
}

@Test(.timeLimit(.minutes(1)))
func duplicateSessionCancellationAndSelectionDrainShareTheSameOwner() async throws {
    let fixture = try RuntimeLifecycleFixture()
    var events = fixture.events.makeAsyncIterator()
    let recording = Task { try await fixture.runtime.startStreaming() }
    var reservedID: UUID?
    while let event = await events.next() {
        if case .streamReserved(let id) = event {
            reservedID = id
            break
        }
    }
    let sessionID = try #require(reservedID)
    await fixture.loader.waitUntilEntered()

    let first = Task { try await fixture.runtime.cancelStreaming(sessionID: sessionID) }
    await waitForCancellation(sessionID, &events)
    let duplicate = Task { try await fixture.runtime.cancelStreaming(sessionID: sessionID) }
    await waitForCancellation(sessionID, &events)
    let selection = Task { try await fixture.runtime.endRecordingSelection() }
    await waitForCancellation(sessionID, &events)
    #expect(await fixture.loader.exited == false)
    await fixture.loader.release()

    try await first.value
    try await duplicate.value
    try await selection.value
    expectFixtureFailure(await recording.result)
    #expect(await fixture.loader.exited)
    #expect(await fixture.loader.wasCancelled == false)
    #expect(await fixture.loader.entries == 1)
}

private enum RuntimeFixtureError: Error {
    case loaderFinished
}

private struct RuntimeLifecycleFixture: Sendable {
    let loader: RuntimeLoaderBarrier
    let runtime: QwenRuntime
    let events: AsyncStream<QwenRuntime.LifecycleEvent>

    init() throws {
        let loader = RuntimeLoaderBarrier()
        let pair = AsyncStream<QwenRuntime.LifecycleEvent>.makeStream()
        self.loader = loader
        events = pair.stream
        runtime = try QwenRuntime(
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            modelLoader: { try await loader.load() },
            lifecycle: { pair.continuation.yield($0) }
        )
    }
}

/// A cancelled task remains inside model acquisition until the test explicitly releases it.
private actor RuntimeLoaderBarrier {
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var entries = 0
    private(set) var exited = false
    private(set) var wasCancelled = false

    func load() async throws -> QwenRuntime.LoadedModel {
        entries += 1
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        defer { exited = true }
        wasCancelled = Task.isCancelled
        try Task.checkCancellation()
        // Deliberately never instantiate MLX, load weights, or execute inference.
        throw RuntimeFixtureError.loaderFinished
    }

    func waitUntilEntered() async {
        if entries > 0 { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private func waitForModelWait(
    _ events: inout AsyncStream<QwenRuntime.LifecycleEvent>.Iterator
) async {
    while let event = await events.next() {
        if case .modelWaitStarted = event { return }
    }
    Issue.record("Runtime lifecycle stream ended before model wait")
}

private func waitForCancellation(
    _ sessionID: UUID,
    _ events: inout AsyncStream<QwenRuntime.LifecycleEvent>.Iterator
) async {
    while let event = await events.next() {
        if case .cancellationRequested(let id) = event, id == sessionID { return }
    }
    Issue.record("Runtime lifecycle stream ended before session cancellation")
}

private func expectFixtureFailure<Value>(_ result: Result<Value, Error>) {
    switch result {
    case .failure(RuntimeFixtureError.loaderFinished): break
    default: Issue.record("Expected the independent loader's fixture failure, got \(result)")
    }
}
