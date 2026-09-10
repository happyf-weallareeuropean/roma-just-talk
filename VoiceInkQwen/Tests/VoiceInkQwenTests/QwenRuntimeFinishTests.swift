import Foundation
import Testing
@testable import VoiceInkQwen

@Test(.timeLimit(.minutes(1)), arguments: [151645, 151643])
func releaseCoalescesQueuedPCMAndKeepsCompletedPrefix(eosToken: Int) async throws {
    let fixture = try FinishFixture(blockedPass: 3, eosToken: eosToken, succeedsAfterCancellation: true)
    let session = try await fixture.runtime.startStreaming(language: "English")
    defer { fixture.releaseAndCancel(session.id) }
    var text = session.events.makeAsyncIterator()
    var lifecycle = fixture.lifecycle.makeAsyncIterator()
    var decodeEvents = fixture.model.events.makeAsyncIterator()
    let chunk = 5_600
    let samples = (0..<(chunk * 8 + 731)).map { Float($0) / 100_000 }
    for pass in 0..<2 {
        try await fixture.runtime.appendAudio(Array(samples[(pass * chunk)..<((pass + 1) * chunk)]), sessionID: session.id)
        guard case .partial? = try await text.next() else {
            Issue.record("Expected completed live pass before release")
            return
        }
    }
    try await fixture.runtime.appendAudio(Array(samples[(chunk * 2)..<(chunk * 3)]), sessionID: session.id)
    await waitForDecode(3, in: &decodeEvents)
    // Queue multiple pre-roll/live-sized packets while the native operation is blocked.
    for start in stride(from: chunk * 3, to: samples.count, by: 1_600) {
        try await fixture.runtime.appendAudio(Array(samples[start..<min(start + 1_600, samples.count)]), sessionID: session.id)
    }
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    await waitForFinish(session.id, in: &lifecycle)
    #expect(await fixture.model.requests.count == 3)
    await fixture.model.release()
    try await finish.value
    try await expectOnlyFinal(&text, expected: FinishModel.completedText)
    fixture.emissions.expectOnlyFinal(FinishModel.completedText)

    let requests = await fixture.model.requests
    #expect(requests.count == 4)
    #expect(requests.last?.samples == samples)
    #expect(requests.last?.prefix == String(FinishModel.completedText.dropLast(5)))
    #expect(requests.last?.language == "English")
    #expect(fixture.model.prefixCalls.values.last == true)
}

@Test(.timeLimit(.minutes(1)))
func releaseWithoutPendingPCMFinalizesTheInFlightResultOnce() async throws {
    let fixture = try FinishFixture(blockedPass: 1, succeedsAfterCancellation: true)
    let session = try await fixture.runtime.startStreaming(language: "English")
    defer { fixture.releaseAndCancel(session.id) }
    var text = session.events.makeAsyncIterator()
    var lifecycle = fixture.lifecycle.makeAsyncIterator()
    var decodeEvents = fixture.model.events.makeAsyncIterator()
    try await fixture.runtime.appendAudio(Array(repeating: 0.01, count: 5_600), sessionID: session.id)
    await waitForDecode(1, in: &decodeEvents)
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    await waitForFinish(session.id, in: &lifecycle)
    await fixture.model.release()
    try await finish.value
    try await expectOnlyFinal(&text)
    fixture.emissions.expectOnlyFinal(FinishModel.rawText)
    #expect(await fixture.model.requests.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func cancellationDrainsBlockedFinalDecodeWithoutPublishingIt() async throws {
    let fixture = try FinishFixture(blockedPass: 2)
    let session = try await fixture.runtime.startStreaming(language: "English")
    defer { fixture.releaseAndCancel(session.id) }
    var text = session.events.makeAsyncIterator()
    var lifecycle = fixture.lifecycle.makeAsyncIterator()
    var decodeEvents = fixture.model.events.makeAsyncIterator()
    try await fixture.runtime.appendAudio(Array(repeating: 0.01, count: 5_600), sessionID: session.id)
    _ = try await text.next()
    try await fixture.runtime.appendAudio(Array(repeating: 0.02, count: 731), sessionID: session.id)
    let finish = Task { try await fixture.runtime.finishStreaming(sessionID: session.id) }
    await waitForFinish(session.id, in: &lifecycle)
    await waitForDecode(2, in: &decodeEvents)
    let cancellation = Task { try await fixture.runtime.cancelStreaming(sessionID: session.id) }
    while let event = await decodeEvents.next() {
        if case .cancelled(2) = event { break }
    }
    #expect(await fixture.model.blockedDecodeExited == false)
    do {
        _ = try await fixture.runtime.startStreaming()
        Issue.record("A new recording must wait for the actual canceled decoder to exit")
    } catch QwenRuntimeError.busy {}
    await fixture.model.release()
    try await cancellation.value
    switch await finish.result {
    case .failure(is CancellationError): break
    default: Issue.record("Finishing a canceled decode must fail with cancellation")
    }
    do {
        while let event = try await text.next() {
            if case .final = event { Issue.record("Canceled decoder published a final") }
        }
        Issue.record("Canceled stream must terminate with cancellation")
    } catch is CancellationError {}
    #expect(await fixture.model.blockedDecodeExited)
    #expect(fixture.emissions.values.isEmpty)
    let next = try await fixture.runtime.startStreaming()
    try await fixture.runtime.cancelStreaming(sessionID: next.id)
}

private struct FinishFixture: Sendable {
    let model: FinishModel
    let runtime: QwenRuntime
    let lifecycle: AsyncStream<QwenRuntime.LifecycleEvent>
    let emissions = FinishEmissions()

    init(blockedPass: Int, eosToken: Int = 151645, succeedsAfterCancellation: Bool = false) throws {
        let model = FinishModel(blockedPass: blockedPass, eosToken: eosToken, succeedsAfterCancellation: succeedsAfterCancellation)
        let events = AsyncStream<QwenRuntime.LifecycleEvent>.makeStream()
        self.model = model
        lifecycle = events.stream
        let emissions = emissions
        runtime = try QwenRuntime(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            modelLoader: { model }, lifecycle: {
                emissions.record($0)
                events.continuation.yield($0)
            })
    }

    func releaseAndCancel(_ id: UUID) {
        Task {
            await model.release()
            try? await runtime.cancelStreaming(sessionID: id)
        }
    }
}

private actor FinishModel: QwenRuntimeModel {
    static let rawText = "repeat repeat repeat."
    static let completedText = "repeat repeat repeat. More spoken words."
    struct Request: Sendable {
        let samples: [Float]
        let prefix: String
        let language: String?
    }
    enum Event: Sendable { case entered(Int), cancelled(Int) }
    nonisolated let events: AsyncStream<Event>
    nonisolated let prefixCalls = PrefixCalls()
    private let continuation: AsyncStream<Event>.Continuation
    private let blockedPass: Int
    private let eosToken: Int
    private let succeedsAfterCancellation: Bool
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var requests: [Request] = []
    private(set) var blockedDecodeExited = false

    init(blockedPass: Int, eosToken: Int, succeedsAfterCancellation: Bool) {
        self.blockedPass = blockedPass
        self.eosToken = eosToken
        self.succeedsAfterCancellation = succeedsAfterCancellation
        let pair = AsyncStream<Event>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    nonisolated func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String {
        prefixCalls.append(finalTail)
        return policy.prefix(finalTail: finalTail,
            encode: { $0.unicodeScalars.map { Int($0.value) } },
            decode: { String(String.UnicodeScalarView($0.compactMap(UnicodeScalar.init))) })
    }

    nonisolated func discardEncoderReuse() {}

    func decode(samples: [Float], prefix: String, language: String?, encoderContext: QwenEncoderContext?) async throws -> QwenDecodeResult {
        requests.append(Request(samples: samples, prefix: prefix, language: language))
        let pass = requests.count
        continuation.yield(.entered(pass))
        if pass == blockedPass {
            await withTaskCancellationHandler {
                if !released { await withCheckedContinuation { held = $0 } }
            } onCancel: { [continuation] in continuation.yield(.cancelled(pass)) }
            blockedDecodeExited = true
        }
        // Model completion can win a cancellation request; keep that race covered.
        if pass != blockedPass || !succeedsAfterCancellation { try Task.checkCancellation() }
        let fullText = pass >= 3 ? Self.completedText : Self.rawText
        #expect(fullText.hasPrefix(prefix))
        return QwenDecodeResult(generatedText: String(fullText.dropFirst(prefix.count)),
            generationTokens: 3, termination: .eos(eosToken))
    }

    func release() { released = true; held?.resume(); held = nil }
}

private final class PrefixCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []
    func append(_ value: Bool) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [Bool] { lock.lock(); defer { lock.unlock() }; return storage }
}

private func waitForDecode(_ pass: Int, in events: inout AsyncStream<FinishModel.Event>.Iterator) async {
    while let event = await events.next() { if case .entered(pass) = event { return } }
    Issue.record("Decoder event stream ended before pass \(pass)")
}

private func waitForFinish(_ id: UUID, in events: inout AsyncStream<QwenRuntime.LifecycleEvent>.Iterator) async {
    while let event = await events.next() { if case .finishRequested(id) = event { return } }
    Issue.record("Lifecycle ended before finish was accepted")
}

private func expectOnlyFinal(_ events: inout AsyncThrowingStream<QwenStreamingEvent, Error>.Iterator,
                             expected: String = FinishModel.rawText) async throws {
    var finals: [String] = []
    while let event = try await events.next() {
        switch event {
        case .partial: Issue.record("Intermediate live text was published after release")
        case .final(let text): finals.append(text)
        }
    }
    #expect(finals == [expected])
}

// Observe the actual yield boundary; bufferingNewest(1) may hide invalid extra emissions.
private final class FinishEmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var finishing = false
    private var storage: [QwenStreamingEvent] = []
    func record(_ event: QwenRuntime.LifecycleEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case .finishRequested: finishing = true
        case .streamEvent(_, let event): if finishing { storage.append(event) }
        default: break
        }
    }
    var values: [QwenStreamingEvent] { lock.lock(); defer { lock.unlock() }; return storage }
    func expectOnlyFinal(_ text: String) {
        let events = values
        #expect(events.count == 1)
        guard case .final(let actual)? = events.first else {
            Issue.record("Only a final event may be emitted after finish")
            return
        }
        #expect(actual == text)
    }
}
