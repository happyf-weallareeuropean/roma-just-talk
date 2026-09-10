import Foundation
import Testing
@testable import VoiceInkQwen

@Test(.timeLimit(.minutes(1)))
func finalFinishAndCompletedDisconnectReturnBeforeCacheCleanup() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    defer { Task { await fixture.cleanup.release() } }

    try await fixture.finishBeforeCleanup(session.id)
    try await fixture.completedDisconnectBeforeCleanup(session.id)

    await fixture.cleanup.waitUntilEntered()
    #expect(await fixture.cleanup.exited == false)
    var events = session.events.makeAsyncIterator()
    guard case .final(let text)? = try await events.next() else {
        Issue.record("Completed finish must deliver final text while cache disposal is held")
        return
    }
    #expect(text == "Spoken words.")
    #expect(try await events.next() == nil)
    await fixture.cleanup.release()
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func nextRecordingWaitsForCleanupAndCancellationKeepsOwnership(cancelStartup: Bool) async throws {
    let fixture = try CleanupFixture()
    let previous = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(previous.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let next = Task { try await fixture.runtime.startStreaming(language: "English") }
    await waitForCleanupWait(&events)

    #expect(await fixture.model.decodes == 1)
    if cancelStartup { next.cancel() }
    do {
        _ = try await fixture.runtime.transcribe(samples: [0.1])
        Issue.record("A recording waiting on cleanup still owns startup")
    } catch QwenRuntimeError.busy {}
    await fixture.cleanup.release()

    if cancelStartup {
        switch await next.result {
        case .failure(is CancellationError): break
        default: Issue.record("Canceled startup must not acquire the model after cleanup")
        }
    } else {
        let session = try await next.value
        try await fixture.runtime.cancelStreaming(sessionID: session.id)
    }
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)), arguments: [CleanupTeardown.unload, .delete, .selection])
func teardownWaitsForCompletedRecordingCleanup(operation: CleanupTeardown) async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let teardown = Task {
        switch operation {
        case .unload: try await fixture.runtime.unload()
        case .delete: try await fixture.runtime.delete()
        case .selection: try await fixture.runtime.endRecordingSelection()
        }
    }
    await waitForCleanupWait(&events)
    #expect(await fixture.cleanup.exited == false)
    await fixture.cleanup.release()
    try await teardown.value
    // A second clear disposes cache released when the model reference is dropped.
    #expect(await fixture.cleanup.entries == 2)
}

@Test(.timeLimit(.minutes(1)))
func idleUnloadRechecksReservedRecordingAfterWaitingForCleanup() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let unload = Task { await fixture.runtime.unloadIfIdle() }
    await waitForCleanupWait(&events)
    let next = Task { try await fixture.runtime.startStreaming(language: "English") }
    await waitForCleanupWait(&events)
    await fixture.cleanup.release()
    await unload.value
    let nextSession = try await next.value
    #expect(await fixture.cleanup.entries == 1)
    #expect(await fixture.loads.count == 1)
    try await fixture.runtime.cancelStreaming(sessionID: nextSession.id)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)), arguments: [CleanupOutcome.eos, .cap, .failure])
func batchJoinsCacheCleanupBeforeReturning(outcome: CleanupOutcome) async throws {
    let fixture = try CleanupFixture(outcome: outcome)
    let batch = Task { try await fixture.runtime.transcribe(samples: [0.1], language: "English") }
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    do {
        _ = try await fixture.runtime.startStreaming()
        Issue.record("Batch retains native ownership throughout cleanup")
    } catch QwenRuntimeError.busy {}
    await fixture.cleanup.release()
    expectCleanupResult(await batch.result, outcome: outcome)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)), arguments: [CleanupOutcome.cap, .failure])
func unsuccessfulFinalJoinsCleanupAndNeverPublishes(outcome: CleanupOutcome) async throws {
    let fixture = try CleanupFixture(outcome: outcome)
    let session = try await fixture.finalSession()
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    do {
        _ = try await fixture.runtime.startStreaming()
        Issue.record("Failed final retains ownership until cleanup drains")
    } catch QwenRuntimeError.busy {}
    await fixture.cleanup.release()
    expectCleanupResult(await finish.result.map { "" }, outcome: outcome)
    var events = session.events.makeAsyncIterator()
    do {
        while let event = try await events.next() {
            if case .final = event { Issue.record("Unsuccessful result published final text") }
        }
        Issue.record("Unsuccessful final must terminate the stream with its error")
    } catch {}
    try await fixture.runtime.cancelStreaming(sessionID: session.id)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)))
func cancelledFinalAndDuplicateDisconnectJoinCleanupAfterDecodeDrains() async throws {
    let fixture = try CleanupFixture(holdDecode: true)
    let session = try await fixture.finalSession()
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    await fixture.modelBarrier.waitUntilEntered()
    defer { Task { await fixture.modelBarrier.release(); await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let cancellation = Task { try await fixture.runtime.cancelStreaming(sessionID: session.id) }
    while let event = await events.next() {
        if case .cancellationRequested(session.id) = event { break }
    }
    await fixture.modelBarrier.release()
    await fixture.cleanup.waitUntilEntered()
    #expect(await fixture.modelBarrier.exited)
    let duplicate = Task { try await fixture.runtime.cancelStreaming(sessionID: session.id) }
    while let event = await events.next() {
        if case .cancellationRequested(session.id) = event { break }
    }
    do {
        _ = try await fixture.runtime.startStreaming()
        Issue.record("Cancellation retains ownership while disposal is held")
    } catch QwenRuntimeError.busy {}
    await fixture.cleanup.release()
    try await cancellation.value
    try await duplicate.value
    switch await finish.result {
    case .failure(is CancellationError): break
    default: Issue.record("Canceled final must not report success")
    }
    #expect(await fixture.cleanup.entries == 1)
    var text = session.events.makeAsyncIterator()
    do {
        while let event = try await text.next() {
            if case .final = event { Issue.record("Canceled final must not publish text") }
        }
        Issue.record("Canceled session must finish with cancellation")
    } catch is CancellationError {}
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)))
func warmPrewarmWaitsForCleanupAndHonorsCancellation() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let warm = Task { try await fixture.runtime.prewarm() }
    await waitForCleanupWait(&events)
    warm.cancel()
    await fixture.cleanup.release()
    switch await warm.result {
    case .failure(is CancellationError): break
    default: Issue.record("Warm model fast path must still join cleanup and honor cancellation")
    }
    #expect(await fixture.loads.count == 1)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)))
func nextBatchReservesStartupWhilePreviousFinalCleanupRuns() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let batch = Task { try await fixture.runtime.transcribe(samples: [0.1], language: "English") }
    await waitForCleanupWait(&events)
    #expect(await fixture.model.decodes == 1)
    do {
        _ = try await fixture.runtime.startStreaming()
        Issue.record("Imported audio waiting on disposal retains its startup reservation")
    } catch QwenRuntimeError.busy {}
    await fixture.cleanup.release()
    #expect(try await batch.value == "Spoken words.")
    #expect(await fixture.model.decodes == 2)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)))
func releaseDuringLiveCleanupReusesOnlyTheDrainedAcceptedResult() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.runtime.startStreaming(language: "English")
    try await fixture.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var lifecycle = fixture.events.makeAsyncIterator()
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    while let event = await lifecycle.next() {
        if case .finishRequested(session.id) = event { break }
    }
    #expect(await fixture.model.decodes == 1)
    await fixture.cleanup.release()
    try await finish.value
    var text = session.events.makeAsyncIterator()
    guard case .final(let value)? = try await text.next() else {
        Issue.record("Release must finalize the already drained result after its cleanup")
        return
    }
    #expect(value == "Spoken words.")
    #expect(await fixture.model.decodes == 1)
    #expect(await fixture.cleanup.entries == 1)
    try await fixture.runtime.cancelStreaming(sessionID: session.id)
    try await fixture.runtime.unload()
}

@Test(.timeLimit(.minutes(1)))
func explicitUnloadInvalidatesRecordingReservedBehindCleanup() async throws {
    let fixture = try CleanupFixture()
    let session = try await fixture.finalSession()
    try await fixture.finishBeforeCleanup(session.id)
    await fixture.cleanup.waitUntilEntered()
    defer { Task { await fixture.cleanup.release() } }
    var events = fixture.events.makeAsyncIterator()
    let next = Task { try await fixture.runtime.startStreaming(language: "English") }
    await waitForCleanupWait(&events)
    let unload = Task { try await fixture.runtime.unload() }
    await waitForCleanupWait(&events)
    await fixture.cleanup.release()
    try await unload.value
    switch await next.result {
    case .failure(is CancellationError): break
    default: Issue.record("Teardown must invalidate the recording awaiting disposal")
    }
    #expect(await fixture.model.decodes == 1)
}

enum CleanupTeardown: Sendable { case unload, delete, selection }
enum CleanupOutcome: Sendable { case eos, cap, failure }
private enum CleanupError: Error { case decode }

private struct CleanupFixture: Sendable {
    let cleanup = CacheCleanupBarrier()
    let modelBarrier = CacheCleanupBarrier()
    let loads = CleanupLoadCounter()
    let model: CleanupModel
    let runtime: QwenRuntime
    let events: AsyncStream<QwenRuntime.LifecycleEvent>
    private let finishBoundary: AsyncStream<Bool>
    private let finishReturned: AsyncStream<Bool>.Continuation

    init(outcome: CleanupOutcome = .eos, holdDecode: Bool = false) throws {
        model = CleanupModel(outcome: outcome, barrier: holdDecode ? modelBarrier : nil)
        let pair = AsyncStream<QwenRuntime.LifecycleEvent>.makeStream()
        events = pair.stream
        let boundary = AsyncStream<Bool>.makeStream()
        finishBoundary = boundary.stream
        finishReturned = boundary.continuation
        let model = model, cleanup = cleanup, loads = loads
        runtime = try QwenRuntime(
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            modelLoader: { await loads.increment(); return model },
            lifecycle: {
                pair.continuation.yield($0)
                if case .cacheCleanupWaitStarted = $0 { boundary.continuation.yield(false) }
            },
            cacheCleanup: { await cleanup.run() }
        )
    }

    func finishBeforeCleanup(_ id: UUID) async throws {
        try await returnsBeforeCleanup { try await runtime.finishStreaming(sessionID: id) }
    }

    func completedDisconnectBeforeCleanup(_ id: UUID) async throws {
        try await returnsBeforeCleanup { try await runtime.cancelStreaming(sessionID: id) }
    }

    private func returnsBeforeCleanup(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let finish = Task {
            defer { finishReturned.yield(true) }
            try await operation()
        }
        var boundary = finishBoundary.makeAsyncIterator()
        // Observe the real return or its forbidden cleanup dependency. Releasing on
        // regression gives a bounded red even though disposal ignores cancellation.
        let returned = await boundary.next()
        #expect(returned == true)
        if returned != true { await cleanup.release() }
        try await finish.value
    }

    func finalSession() async throws -> QwenStreamingSession {
        let session = try await runtime.startStreaming(language: "English")
        // Below the live threshold: the first native operation is the final pass.
        try await runtime.appendAudio(Array(repeating: 0.1, count: 731), sessionID: session.id)
        return session
    }
}

private actor CleanupModel: QwenRuntimeModel {
    let outcome: CleanupOutcome
    let barrier: CacheCleanupBarrier?
    private(set) var decodes = 0
    init(outcome: CleanupOutcome, barrier: CacheCleanupBarrier?) {
        self.outcome = outcome
        self.barrier = barrier
    }
    nonisolated func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String { "" }
    nonisolated func discardInferenceReuse() {}

    func decode(samples: [Float], prefix: String, language: String?, inferenceContext: QwenInferenceContext?, draft: QwenDecodeDraft?) async throws -> QwenDecodeResult {
        decodes += 1
        if let barrier { await barrier.run() }
        try Task.checkCancellation()
        switch outcome {
        case .failure: throw CleanupError.decode
        case .eos, .cap:
            return .init(generatedText: "Spoken words.", generationTokens: 3,
                         termination: outcome == .eos ? .eos(151645) : .tokenLimit)
        }
    }
}

private actor CleanupLoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor CacheCleanupBarrier {
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var entries = 0
    private(set) var exited = false
    func run() async {
        entries += 1
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
        exited = true
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

private func waitForCleanupWait(_ events: inout AsyncStream<QwenRuntime.LifecycleEvent>.Iterator) async {
    while let event = await events.next() { if case .cacheCleanupWaitStarted = event { return } }
    Issue.record("Expected runtime to enter the owned cache cleanup wait")
}

private func expectCleanupResult(_ result: Result<String, Error>, outcome: CleanupOutcome) {
    switch (outcome, result) {
    case (.eos, .success("Spoken words.")), (.cap, .failure(QwenRuntimeError.outputLimitReached)),
         (.failure, .failure(CleanupError.decode)): break
    default: Issue.record("Unexpected result after cache cleanup: \(result)")
    }
}
