import Foundation
import Testing
@testable import VoiceInkQwen

@Test(.timeLimit(.minutes(1)), arguments: [0, 731, 11_931])
func supersededLivePassReplaysAllPCMFromLastCompletedPrefix(tail: Int) async throws {
    let f = try SupersessionFixture(blocked: [3])
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator()
    var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    let pcm = (0..<(16_800 + tail)).map { Float($0) / 100_000 }
    for pass in 0..<2 {
        try await f.runtime.appendAudio(Array(pcm[(pass * 5_600)..<((pass + 1) * 5_600)]), sessionID: s.id)
        guard case .partial? = try await text.next() else { Issue.record("Missing completed prefix"); return }
    }
    try await f.runtime.appendAudio(Array(pcm[11_200..<16_800]), sessionID: s.id)
    await entered(3, in: &calls)
    try await f.runtime.appendAudio(Array(pcm[16_800...]), sessionID: s.id)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    // onCancel is synchronous, installed before entered; known bad fails here without hanging.
    #expect(f.model.trace.cancelled.contains(3))
    #expect(await f.model.requests.count == 3)
    #expect(!f.model.trace.exited.contains(3))
    await f.model.release(3)
    try await finish.value
    try await onlyFinal(&text, expected: SupersessionModel.finalText)
    let requests = await f.model.requests
    #expect(requests.count == 4)
    #expect(requests.last?.samples == pcm)
    #expect(requests.last?.prefix == String(SupersessionModel.liveText.dropLast(5)))
    #expect(requests.last?.language == "English")
    let exited = try #require(f.model.trace.order.firstIndex(of: "exit:3"))
    let finalEntered = try #require(f.model.trace.order.firstIndex(of: "enter:4"))
    #expect(exited < finalEntered)
    #expect(f.emissions.values.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func duplicateFinishDoesNotCancelTheReplacementFinal() async throws {
    let f = try SupersessionFixture(blocked: [1, 2])
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let first = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    let didCancel = f.model.trace.cancelled.contains(1)
    #expect(didCancel)
    await f.model.release(1)
    // Known bad does not schedule replacement final; stop after the load-bearing failure.
    guard didCancel else { _ = await first.result; return }
    await entered(2, in: &calls)
    let second = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    #expect(!f.model.trace.cancelled.contains(2))
    #expect(await f.model.requests.count == 2)
    #expect(await f.model.requests.last?.samples == Array(repeating: Float(0.1), count: 5_600))
    #expect(await f.model.requests.last?.prefix == "")
    await f.model.release(2)
    try await first.value; try await second.value
    try await onlyFinal(&text, expected: SupersessionModel.finalText)
    #expect(f.emissions.values.count == 1)
}

@Test(.timeLimit(.minutes(1)), arguments: [SupersessionModel.Outcome.error, .limit])
private func realFailureOnSupersededLivePassRemainsTerminal(outcome: SupersessionModel.Outcome) async throws {
    let f = try SupersessionFixture(blocked: [1], firstOutcome: outcome)
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    #expect(f.model.trace.cancelled.contains(1))
    await f.model.release(1)
    await expectFailure(finish, outcome: outcome)
    do { _ = try await text.next(); Issue.record("Failed inference cannot emit success") }
    catch { expectError(error, outcome: outcome) }
    do { try await f.runtime.finishStreaming(sessionID: s.id); Issue.record("Prior failure must survive another finish") }
    catch { expectError(error, outcome: outcome) }
    #expect(await f.model.requests.count == 1)
    #expect(f.emissions.values.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func userCancellationWhileSupersededChildDrainsIsTerminal() async throws {
    let f = try SupersessionFixture(blocked: [1])
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    #expect(f.model.trace.cancelled.contains(1))
    let cancel = Task { try await f.runtime.cancelStreaming(sessionID: s.id) }
    await marker(.cancel, id: s.id, in: &life)
    do { _ = try await f.runtime.startStreaming(); Issue.record("Cancellation must reserve owner through drain") }
    catch QwenRuntimeError.busy {}
    #expect(!f.model.trace.exited.contains(1))
    await f.model.release(1)
    try await cancel.value
    await expectCancellation(finish)
    try await cancelledStream(&text)
    #expect(await f.model.requests.count == 1)
    #expect(f.emissions.values.isEmpty)
    let next = try await f.runtime.startStreaming()
    try await f.runtime.cancelStreaming(sessionID: next.id)
}

@Test(.timeLimit(.minutes(1)), arguments: [false, true])
func teardownCancelsReplacementFinalAndAllowsReloadAfterDrain(deleteModel: Bool) async throws {
    let f = try SupersessionFixture(blocked: [1, 2])
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    await marker(.finish, id: s.id, in: &life)
    let didCancel = f.model.trace.cancelled.contains(1)
    #expect(didCancel)
    await f.model.release(1)
    guard didCancel else { _ = await finish.result; return }
    await entered(2, in: &calls)
    let sentinel = try f.createDeletionSentinel()
    let unload = Task {
        if deleteModel { try await f.runtime.delete() } else { try await f.runtime.unload() }
    }
    // Final was not previously canceled: this event proves unload reached the real child.
    while let event = await calls.next() { if case .cancelled(2) = event { break } }
    #expect(!f.model.trace.exited.contains(2))
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
    do { _ = try await f.runtime.startStreaming(); Issue.record("Teardown must retain owner through drain") }
    catch QwenRuntimeError.busy {}
    await f.model.release(2)
    try await unload.value
    #expect(FileManager.default.fileExists(atPath: sentinel.path) == !deleteModel)
    await expectCancellation(finish)
    try await cancelledStream(&text)
    #expect(f.emissions.values.isEmpty)
    let next = try await f.runtime.startStreaming()
    try await f.runtime.cancelStreaming(sessionID: next.id)
}

@Test(.timeLimit(.minutes(1)))
func cancelledFinishWaiterDrainsSupersededChildWithoutRetry() async throws {
    let f = try SupersessionFixture(blocked: [1])
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: s.id) }
    // Candidate emits the existing marker from inside its installed parent handler.
    await marker(.finish, id: s.id, in: &life)
    #expect(f.model.trace.cancelled.contains(1))
    finish.cancel()
    // Task.cancel synchronously invokes the installed handler that cancels processStream.
    #expect(!f.model.trace.exited.contains(1))
    await f.model.release(1)
    await expectCancellation(finish)
    try await cancelledStream(&text)
    #expect(await f.model.requests.count == 1)
    #expect(f.emissions.values.isEmpty)
    #expect(f.model.trace.exited.contains(1))
}

@Test(.timeLimit(.minutes(1)))
func cancellationAtFinishMarkerMustNotLeaveAnOrphanStreamParent() async throws {
    let f = try SupersessionFixture(blocked: [1], cancelWaiterAtFinish: true)
    let s = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(s.id) }
    var text = s.events.makeAsyncIterator(); var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: s.id)
    await entered(1, in: &calls)
    let start = AsyncStream<Void>.makeStream()
    let finish = Task {
        for await _ in start.stream { break }
        defer { f.model.trace.append("finish-return") }
        try await f.runtime.finishStreaming(sessionID: s.id)
    }
    f.waiter.install(finish)
    start.continuation.yield(()); start.continuation.finish()
    // Callback cancels exact waiter synchronously at the real marker: old code had no handler.
    await marker(.finish, id: s.id, in: &life)
    #expect(f.waiter.didCancel)
    await f.model.release(1)
    await expectCancellation(finish)
    try await cancelledStream(&text)
    #expect(await f.model.requests.count == 1)
    #expect(f.emissions.values.isEmpty)
    let drained = try #require(f.model.trace.order.firstIndex(of: "exit:1"))
    let returned = try #require(f.model.trace.order.firstIndex(of: "finish-return"))
    #expect(drained < returned)
}

@Test(.timeLimit(.minutes(1)))
func sessionDiagnosticsSeparateSupersededDrainFromFinalAndStayWithTheirSession() async throws {
    let f = try SupersessionFixture(blocked: [1])
    let firstLog = StreamingDiagnostics()
    let first = try await f.runtime.startStreaming(language: "English", diagnostic: { firstLog.record($0) })
    defer { f.cleanup(first.id) }
    var text = first.events.makeAsyncIterator()
    var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: first.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: first.id) }
    await marker(.finish, id: first.id, in: &life)
    let held = firstLog.values
    #expect(held.map(\.phase) == [.decodeBegin, .finishRequested, .cancellationRequested])
    #expect(held.first?.sampleCount == 5_600)
    #expect(held.last?.decodeID == held.first?.decodeID)
    #expect(held.last?.outcome == .superseded)
    #expect(!f.model.trace.exited.contains(1))
    await f.model.release(1)
    try await finish.value
    try await onlyFinal(&text, expected: SupersessionModel.finalText)
    let events = firstLog.values
    #expect(events.map(\.phase) == [.decodeBegin, .finishRequested, .cancellationRequested,
        .decodeEnd, .decodeReceived, .decodeBegin, .decodeEnd, .decodeReceived,
        .presentationBegin, .presentationEnd, .finalEmitted])
    #expect(events.allSatisfy { $0.sessionID == first.id })
    #expect(zip(events, events.dropFirst()).allSatisfy { $0.uptime <= $1.uptime })
    let liveEnd = try #require(events.first { $0.phase == .decodeEnd })
    #expect(liveEnd.outcome == .cancelled)
    #expect(liveEnd.decodeID == held.first?.decodeID)
    let finalBegin = try #require(events.first { $0.phase == .decodeBegin && $0.isFinal })
    let finalEnd = try #require(events.first { $0.phase == .decodeEnd && $0.isFinal })
    #expect(finalBegin.decodeID != liveEnd.decodeID)
    #expect(finalBegin.sampleCount == 5_600)
    #expect(finalEnd.decodeID == finalBegin.decodeID)
    #expect(finalEnd.outcome == .eos)
    #expect(finalEnd.generationTokens == 3)
    #expect(f.emissions.values.count == 1)

    let secondLog = StreamingDiagnostics()
    let second = try await f.runtime.startStreaming(diagnostic: { secondLog.record($0) })
    try await f.runtime.finishStreaming(sessionID: second.id)
    #expect(secondLog.values.map(\.phase) == [.finishRequested, .presentationBegin, .presentationEnd, .finalEmitted])
    #expect(secondLog.values.allSatisfy { $0.sessionID == second.id })
    #expect(firstLog.values.count == events.count)
    let third = try await f.runtime.startStreaming()
    try await f.runtime.finishStreaming(sessionID: third.id)
    #expect(firstLog.values.count == events.count)
    #expect(secondLog.values.count == 4)
}

@Test(.timeLimit(.minutes(1)), arguments: [SupersessionModel.Outcome.error, .limit])
private func sessionDiagnosticsRetainTerminalOutcomeWithoutFinalEmission(outcome: SupersessionModel.Outcome) async throws {
    let f = try SupersessionFixture(blocked: [1], firstOutcome: outcome)
    let log = StreamingDiagnostics()
    let session = try await f.runtime.startStreaming(diagnostic: { log.record($0) })
    defer { f.cleanup(session.id) }
    var life = f.lifecycle.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: session.id)
    await entered(1, in: &calls)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: session.id) }
    await marker(.finish, id: session.id, in: &life)
    #expect(!log.values.contains { $0.phase == .decodeEnd })
    await f.model.release(1)
    await expectFailure(finish, outcome: outcome)
    let end = try #require(log.values.first { $0.phase == .decodeEnd })
    switch outcome { case .error: #expect(end.outcome == .error)
    case .limit: #expect(end.outcome == .tokenLimit)
    case .cooperative, .lateEOS: Issue.record("Unexpected test outcome") }
    #expect(!log.values.contains { $0.phase == .presentationBegin || $0.phase == .finalEmitted })
    #expect(f.emissions.values.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func finalDecodeCancellationDiagnosticKeepsItsIdentityUntilDrain() async throws {
    let f = try SupersessionFixture(blocked: [1])
    let log = StreamingDiagnostics()
    let session = try await f.runtime.startStreaming(diagnostic: { log.record($0) })
    defer { f.cleanup(session.id) }
    var calls = f.model.events.makeAsyncIterator()
    // Less than a live chunk: only finish can submit this final request.
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 731), sessionID: session.id)
    let finish = Task { try await f.runtime.finishStreaming(sessionID: session.id) }
    await entered(1, in: &calls)
    let cancel = Task { try await f.runtime.cancelStreaming(sessionID: session.id) }
    while let event = await calls.next() { if case .cancelled(1) = event { break } }
    let begin = try #require(log.values.first { $0.phase == .decodeBegin })
    let requested = try #require(log.values.first { $0.phase == .cancellationRequested })
    #expect(begin.isFinal && requested.isFinal)
    #expect(requested.decodeID == begin.decodeID)
    #expect(requested.outcome == .cancelled)
    #expect(!log.values.contains { $0.phase == .decodeEnd })
    #expect(!f.model.trace.exited.contains(1))
    await f.model.release(1)
    try await cancel.value
    await expectCancellation(finish)
    let end = try #require(log.values.first { $0.phase == .decodeEnd })
    #expect(end.decodeID == begin.decodeID && end.isFinal)
    #expect(end.outcome == .cancelled)
    #expect(!log.values.contains { $0.phase == .finalEmitted })
}

private final class StreamingDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [QwenStreamingDiagnostic] = []
    func record(_ event: QwenStreamingDiagnostic) {
        lock.lock(); defer { lock.unlock() }; storage.append(event)
    }
    var values: [QwenStreamingDiagnostic] { lock.lock(); defer { lock.unlock() }; return storage }
}

private struct SupersessionFixture: Sendable {
    let model: SupersessionModel
    let runtime: QwenRuntime
    let lifecycle: AsyncStream<QwenRuntime.LifecycleEvent>
    let emissions = SupersessionEmissions()
    let waiter = FinishWaiterCancellation()
    let cacheDirectory: URL
    init(blocked: Set<Int>, firstOutcome: SupersessionModel.Outcome = .cooperative, cancelWaiterAtFinish: Bool = false) throws {
        let model = SupersessionModel(blocked: blocked, firstOutcome: firstOutcome)
        self.model = model
        let pair = AsyncStream<QwenRuntime.LifecycleEvent>.makeStream()
        lifecycle = pair.stream
        let emissions = emissions; let waiter = waiter
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cacheDirectory = directory
        runtime = try QwenRuntime(cacheDirectory: directory, modelLoader: { model }, lifecycle: {
            if cancelWaiterAtFinish, case .finishRequested = $0 { waiter.cancel() }
            emissions.record($0); pair.continuation.yield($0)
        })
    }
    func createDeletionSentinel() throws -> URL {
        let revision = try QwenSnapshot.bundled().revision
        let directory = cacheDirectory.appendingPathComponent(revision, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("test-owned-sentinel")
        try Data([1]).write(to: sentinel)
        return sentinel
    }
    func cleanup(_ id: UUID) {
        Task {
            await model.releaseAll(); try? await runtime.cancelStreaming(sessionID: id)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
    }
}

private actor SupersessionModel: QwenRuntimeModel {
    static let liveText = "repeat repeat repeat. Earlier words."
    static let finalText = "repeat repeat repeat. Earlier words. Full captured ending."
    enum Outcome: Sendable { case cooperative, error, limit, lateEOS }
    enum Failure: Error { case decoder }
    struct Request: Sendable { let samples: [Float]; let prefix: String; let language: String? }
    enum Event: Sendable { case entered(Int), cancelled(Int) }
    nonisolated let events: AsyncStream<Event>
    nonisolated let trace = SupersessionTrace()
    private let continuation: AsyncStream<Event>.Continuation
    private let blocked: Set<Int>
    private let firstOutcome: Outcome
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private(set) var requests: [Request] = []
    init(blocked: Set<Int>, firstOutcome: Outcome) {
        self.blocked = blocked; self.firstOutcome = firstOutcome
        let pair = AsyncStream<Event>.makeStream(); events = pair.stream; continuation = pair.continuation
    }
    nonisolated func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String {
        policy.prefix(finalTail: finalTail, encode: { $0.unicodeScalars.map { Int($0.value) } },
            decode: { String(String.UnicodeScalarView($0.compactMap(UnicodeScalar.init))) })
    }
    func decode(samples: [Float], prefix: String, language: String?) async throws -> QwenDecodeResult {
        requests.append(Request(samples: samples, prefix: prefix, language: language))
        let pass = requests.count
        defer { trace.append("exit:\(pass)") }
        return try await withTaskCancellationHandler {
            trace.append("enter:\(pass)"); continuation.yield(.entered(pass))
            if blocked.contains(pass), !released.contains(pass) { await withCheckedContinuation { held[pass] = $0 } }
            // Explicit controls model native error or completed non-EOS result winning cancellation.
            if pass == 1 {
                switch firstOutcome {
                case .error: throw Failure.decoder
                case .limit: return QwenDecodeResult(generatedText: "incomplete", generationTokens: 1, termination: .tokenLimit)
                case .lateEOS: return QwenDecodeResult(generatedText: Self.liveText, generationTokens: 3, termination: .eos(151645))
                case .cooperative: break
                }
            }
            try Task.checkCancellation()
            let full = pass > (blocked.min() ?? 0) ? Self.finalText : Self.liveText
            #expect(full.hasPrefix(prefix))
            return QwenDecodeResult(generatedText: String(full.dropFirst(prefix.count)), generationTokens: 3, termination: .eos(151645))
        } onCancel: { [trace, continuation] in
            trace.append("cancel:\(pass)"); continuation.yield(.cancelled(pass))
        }
    }
    func release(_ pass: Int) { released.insert(pass); held.removeValue(forKey: pass)?.resume() }
    func releaseAll() { for pass in blocked { release(pass) } }
}

private final class SupersessionTrace: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [String] = []
    func append(_ item: String) { lock.lock(); defer { lock.unlock() }; storage.append(item) }
    var order: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    var cancelled: Set<Int> { Set(order.compactMap { $0.hasPrefix("cancel:") ? Int($0.dropFirst(7)) : nil }) }
    var exited: Set<Int> { Set(order.compactMap { $0.hasPrefix("exit:") ? Int($0.dropFirst(5)) : nil }) }
}
private final class SupersessionEmissions: @unchecked Sendable {
    private let lock = NSLock(); private var finishing = false; private var storage: [QwenStreamingEvent] = []
    func record(_ event: QwenRuntime.LifecycleEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event { case .finishRequested: finishing = true
        case .streamEvent(_, let value): if finishing { storage.append(value) }
        default: break }
    }
    var values: [QwenStreamingEvent] { lock.lock(); defer { lock.unlock() }; return storage }
}
private final class FinishWaiterCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var task: Task<Void, Error>?; private var cancelled = false
    func install(_ task: Task<Void, Error>) { lock.lock(); defer { lock.unlock() }; self.task = task }
    func cancel() {
        lock.lock(); let value = task; cancelled = true; lock.unlock()
        value?.cancel()
    }
    var didCancel: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
private enum Marker { case finish, cancel }
private func marker(_ kind: Marker, id: UUID, in events: inout AsyncStream<QwenRuntime.LifecycleEvent>.Iterator) async {
    while let event = await events.next() {
        switch (kind, event) { case (.finish, .finishRequested(id)), (.cancel, .cancellationRequested(id)): return
        default: break }
    }
    Issue.record("Expected runtime lifecycle marker")
}
private func entered(_ pass: Int, in events: inout AsyncStream<SupersessionModel.Event>.Iterator) async {
    while let event = await events.next() { if case .entered(pass) = event { return } }
    Issue.record("Expected model entry")
}
private func onlyFinal(_ events: inout AsyncThrowingStream<QwenStreamingEvent, Error>.Iterator, expected: String) async throws {
    var finals: [String] = []
    while let event = try await events.next() {
        switch event { case .partial: Issue.record("Obsolete partial after finish"); case .final(let text): finals.append(text) }
    }
    #expect(finals == [expected])
}
private func expectCancellation(_ task: Task<Void, Error>) async {
    switch await task.result { case .failure(is CancellationError): break; default: Issue.record("Expected cancellation") }
}
private func cancelledStream(_ events: inout AsyncThrowingStream<QwenStreamingEvent, Error>.Iterator) async throws {
    do { while let event = try await events.next() { if case .final = event { Issue.record("Canceled final") } }; Issue.record("Expected stream cancellation") }
    catch is CancellationError {}
}
private func expectFailure(_ task: Task<Void, Error>, outcome: SupersessionModel.Outcome) async {
    switch await task.result { case .failure(let error): expectError(error, outcome: outcome)
    case .success: Issue.record("Inference failure became success") }
}
private func expectError(_ error: Error, outcome: SupersessionModel.Outcome) {
    switch (outcome, error) {
    case (.error, SupersessionModel.Failure.decoder), (.limit, QwenRuntimeError.outputLimitReached): break
    default: Issue.record("Wrong terminal error: \(error)")
    }
}

// Models release after the final EOS cancellation check, before native return/drain.
@Test(.timeLimit(.minutes(1)), arguments: [0, 731])
private func lateEOSAfterSupersessionPreservesCurrentTextAcceptance(tail: Int) async throws {
    let f = try SupersessionFixture(blocked: [1], firstOutcome: .lateEOS)
    let session = try await f.runtime.startStreaming(language: "English")
    defer { f.cleanup(session.id) }
    var text = session.events.makeAsyncIterator()
    var calls = f.model.events.makeAsyncIterator()
    var life = f.lifecycle.makeAsyncIterator()
    try await f.runtime.appendAudio(Array(repeating: 0.1, count: 5_600), sessionID: session.id)
    await entered(1, in: &calls)
    if tail > 0 {
        try await f.runtime.appendAudio(Array(repeating: 0.2, count: tail), sessionID: session.id)
    }
    let finish = Task { try await f.runtime.finishStreaming(sessionID: session.id) }
    await marker(.finish, id: session.id, in: &life)
    #expect(f.model.trace.cancelled.contains(1))
    #expect(!f.model.trace.exited.contains(1))
    await f.model.release(1)
    try await finish.value
    try await onlyFinal(&text, expected: tail == 0 ? SupersessionModel.liveText : SupersessionModel.finalText)
    let requests = await f.model.requests
    #expect(requests.count == (tail == 0 ? 1 : 2))
    if tail > 0 {
        #expect(requests[1].prefix == "")
        let exited = try #require(f.model.trace.order.firstIndex(of: "exit:1"))
        let finalEntered = try #require(f.model.trace.order.firstIndex(of: "enter:2"))
        #expect(exited < finalEntered)
    }
}
