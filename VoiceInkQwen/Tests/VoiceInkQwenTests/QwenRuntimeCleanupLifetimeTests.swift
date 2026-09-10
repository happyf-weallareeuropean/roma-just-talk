import Foundation
import Testing
@testable import VoiceInkQwen

@Test(.timeLimit(.minutes(1)))
func pendingCleanupRetainsRuntimeAndModelAfterExternalOwnerReturns() async throws {
    let disposal = LifetimeDisposalBarrier()
    let lifetime = CleanupModelLifetime()
    let owner = try await finishAndReleaseExternalOwner(disposal: disposal, lifetime: lifetime)
    await disposal.waitUntilEntered()
    defer { Task { await disposal.release() } }

    #expect(owner.isRetained)
    #expect(lifetime.wasReleased == false)
    await disposal.release()

    var released = lifetime.releases.makeAsyncIterator()
    #expect(await released.next() != nil)
    #expect(lifetime.wasReleased)
    #expect(owner.isRetained == false)
}

private func finishAndReleaseExternalOwner(
    disposal: LifetimeDisposalBarrier, lifetime: CleanupModelLifetime
) async throws -> CleanupWeakRuntime {
    let boundary = AsyncStream<Bool>.makeStream()
    let runtime = try QwenRuntime(
        cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
        modelLoader: { LifetimeModel(lifetime: lifetime) },
        lifecycle: { if case .cacheCleanupWaitStarted = $0 { boundary.continuation.yield(false) } },
        cacheCleanup: { await disposal.run() }
    )
    let session = try await runtime.startStreaming(language: "English")
    try await runtime.appendAudio(Array(repeating: 0.1, count: 731), sessionID: session.id)
    let finish = Task {
        defer { boundary.continuation.yield(true) }
        try await runtime.finishStreaming(sessionID: session.id)
    }
    var events = boundary.stream.makeAsyncIterator()
    let returned = await events.next()
    #expect(returned == true)
    if returned != true { await disposal.release() }
    try await finish.value
    return CleanupWeakRuntime(runtime)
}

// A weak reference observes ARC ownership without retaining the object under test.
private final class CleanupWeakRuntime: @unchecked Sendable {
    private weak var value: QwenRuntime?
    init(_ value: QwenRuntime) { self.value = value }
    var isRetained: Bool { value != nil }
}

private final class LifetimeModel: QwenRuntimeModel, Sendable {
    let lifetime: CleanupModelLifetime
    init(lifetime: CleanupModelLifetime) { self.lifetime = lifetime }
    deinit { lifetime.released() }
    func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String { "" }
    nonisolated func discardInferenceReuse() {}

    func decode(samples: [Float], prefix: String, language: String?, inferenceContext: QwenInferenceContext?, draft: QwenDecodeDraft?) async throws -> QwenDecodeResult {
        .init(generatedText: "Spoken words.", generationTokens: 3, termination: .eos(151645))
    }
}

private final class CleanupModelLifetime: @unchecked Sendable {
    let releases: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var didRelease = false
    init() {
        let pair = AsyncStream<Void>.makeStream()
        releases = pair.stream
        continuation = pair.continuation
    }
    var wasReleased: Bool { lock.lock(); defer { lock.unlock() }; return didRelease }
    func released() {
        lock.lock()
        didRelease = true
        lock.unlock()
        continuation.yield(())
        continuation.finish()
    }
}

private actor LifetimeDisposalBarrier {
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var entered = false
    private var released = false
    func run() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }
    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
