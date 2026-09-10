import Foundation
import MLX
import MLXAudioSTT

public enum QwenStreamingEvent: Sendable {
    case partial(String)
    case final(String)
}

public struct QwenStreamingSession: Sendable {
    public let id: UUID
    public let events: AsyncThrowingStream<QwenStreamingEvent, Error>
}

/// Content-free session diagnostics. Callbacks must be brief and must not block inference.
public struct QwenStreamingDiagnostic: Sendable {
    public enum Phase: String, Sendable {
        case finishRequested, cancellationRequested, decodeBegin, decodeEnd, decodeReceived
        case presentationBegin, presentationEnd, finalEmitted
    }
    public enum Outcome: String, Sendable { case eos, tokenLimit, cancelled, error, superseded }
    public let phase: Phase
    public let sessionID: UUID
    public let decodeID: UUID?
    public let isFinal: Bool
    public let sampleCount: Int?
    public let generationTokens: Int?
    public let outcome: Outcome?
    public let reusedEncoderBatches: Int?
    public let nativePhases: [String: Double]?
    public let uptime: TimeInterval

    init(_ phase: Phase, sessionID: UUID, decodeID: UUID? = nil, isFinal: Bool = false,
         sampleCount: Int? = nil, generationTokens: Int? = nil, outcome: Outcome? = nil, reusedEncoderBatches: Int? = nil, nativePhases: [String: Double]? = nil) {
        self.phase = phase; self.sessionID = sessionID; self.decodeID = decodeID
        self.isFinal = isFinal; self.sampleCount = sampleCount
        self.generationTokens = generationTokens; self.outcome = outcome
        self.reusedEncoderBatches = reusedEncoderBatches
        self.nativePhases = nativePhases
        uptime = ProcessInfo.processInfo.systemUptime
    }
}

// The runtime grants one caller access; native decode returns only after Metal drains.
protocol QwenRuntimeModel: Sendable {
    func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String
    func discardEncoderReuse()
    func decode(samples: [Float], prefix: String, language: String?, encoderContext: QwenEncoderContext?, draft: QwenDecodeDraft?) async throws -> QwenDecodeResult
}

/// One local model owner shared by file transcription and the streaming adapter.
public actor QwenRuntime {
    // MLX modules are not Sendable. Only this actor grants access, one operation at a time;
    // a task retains the model until its Metal stream has actually drained.
    final class LoadedModel: QwenRuntimeModel, @unchecked Sendable {
        private let value: Qwen3ASRModel
        private let encoderReuse = QwenEncoderReuse()
        init(_ value: Qwen3ASRModel) { self.value = value }

        func prefix(for policy: QwenStreamingPolicy, finalTail: Bool) throws -> String {
            guard let tokenizer = value.tokenizer else { throw QwenDecodeError.tokenizerUnavailable }
            return policy.prefix(finalTail: finalTail,
                encode: { tokenizer.encode(text: $0) }, decode: { tokenizer.decode(tokens: $0) })
        }

        func discardEncoderReuse() { encoderReuse.discard() }

        func decode(samples: [Float], prefix: String, language: String?, encoderContext: QwenEncoderContext?, draft: QwenDecodeDraft?) async throws -> QwenDecodeResult {
            try Device.withDefaultDevice(.gpu) {
                // Reuse MLX's GPU stream; new streams retain a queue beyond this call.
                // The runtime still owns the model until this stream actually drains.
                encoderReuse.begin(encoderContext)
                var result: QwenDecodeResult?
                defer {
                    StreamOrDevice.default.stream.synchronize()
                    encoderReuse.complete(result)
                }
                let decoded = try QwenGreedyDecoder.decodeRetainingCache(model: value, samples: samples, prefix: prefix, language: language, encoderReuse: encoderReuse, draft: draft)
                result = decoded
                return decoded
            }
        }
    }

    private let store: QwenModelStore
    private let modelLoader: @Sendable () async throws -> any QwenRuntimeModel
    enum LifecycleEvent: Sendable {
        case modelWaitStarted
        case streamingRequested
        case streamReserved(UUID)
        case cancellationRequested(UUID)
        case selectionEnding
        case finishRequested(UUID)
        case streamEvent(UUID, QwenStreamingEvent)
        case cacheCleanupWaitStarted
    }
    private let lifecycle: @Sendable (LifecycleEvent) -> Void
    private let cacheCleanup: @Sendable () async -> Void
    private var pendingCacheCleanup: (id: UUID, task: Task<Void, Never>)?
    private var model: (any QwenRuntimeModel)?
    private var loading: (id: UUID, task: Task<any QwenRuntimeModel, Error>)?
    private var generation: (id: UUID, task: Task<String, Error>)?
    private var batchStarting: UUID?
    private var streamCancellation: (id: UUID, task: Task<Void, Never>)?
    // Mutable state stays actor-isolated; Sendable permits cancellation-only access in deinit.
    private final class LiveSession: @unchecked Sendable {
        let id = UUID()
        let language: String?
        let diagnostic: (@Sendable (QwenStreamingDiagnostic) -> Void)?
        let continuation: AsyncThrowingStream<QwenStreamingEvent, Error>.Continuation
        var policy = QwenStreamingPolicy(chunkSamples: 5_600)
        var task: Task<Void, Never>?
        var finishing = false
        var liveDecode: (id: UUID, task: Task<QwenDecodeResult, Error>)?
        var supersededDecodeID: UUID?
        var diagnosticDecode: (id: UUID, isFinal: Bool)?
        var needsFinalDecode = false
        var lastCompletedDraft: QwenDecodeDraft?
        var acceptedDecodeID: UUID?
        var failure: Error?

        init(language: String?, continuation: AsyncThrowingStream<QwenStreamingEvent, Error>.Continuation,
             diagnostic: (@Sendable (QwenStreamingDiagnostic) -> Void)?) {
            self.language = language
            self.diagnostic = diagnostic
            self.continuation = continuation
        }
    }
    private var streaming: LiveSession?
    private var closing = false
    private var epoch: UInt64 = 0

    public init(cacheDirectory: URL) throws {
        let store = QwenModelStore(root: cacheDirectory, snapshot: try .bundled())
        self.store = store
        lifecycle = { _ in }
        cacheCleanup = { Memory.clearCache() }
        modelLoader = {
            let directory = try await store.cachedDirectory()
            try Task.checkCancellation()
            return try await Device.withDefaultDevice(.gpu) {
                try await Stream.withNewDefaultStream(device: .gpu) {
                    defer { StreamOrDevice.default.stream.synchronize() }
                    let value = try await Qwen3ASRModel.fromModelDirectory(directory)
                    try Task.checkCancellation()
                    return LoadedModel(value)
                }
            }
        }
    }

    // Tests replace only model acquisition; actor ownership and drain paths remain real.
    init(
        cacheDirectory: URL,
        modelLoader: @escaping @Sendable () async throws -> any QwenRuntimeModel,
        lifecycle: @escaping @Sendable (LifecycleEvent) -> Void,
        cacheCleanup: @escaping @Sendable () async -> Void = { Memory.clearCache() }
    ) throws {
        store = QwenModelStore(root: cacheDirectory, snapshot: try .bundled())
        self.modelLoader = modelLoader
        self.lifecycle = lifecycle
        self.cacheCleanup = cacheCleanup
    }

    deinit {
        loading?.task.cancel()
        generation?.task.cancel()
        streaming?.task?.cancel()
        streaming?.continuation.finish(throwing: CancellationError())
    }

    /// Lightweight picker status. Prewarm always performs complete checksum verification.
    public func isInstalled() async -> Bool {
        guard !closing else { return false }
        return await store.isInstalled()
    }

    public func cancelDownload() async {
        await store.cancelAndDrain()
    }

    public func install(
        progress: @escaping @Sendable (QwenDownloadProgress) -> Void
    ) async throws {
        guard !closing else { throw QwenRuntimeError.busy }
        let startedEpoch = epoch
        _ = try await store.install(progress: progress)
        try Task.checkCancellation()
        guard !closing, epoch == startedEpoch else { throw CancellationError() }
    }

    /// Uses only the verified installed snapshot. Never downloads while recording starts.
    public func prewarm() async throws {
        try Task.checkCancellation()
        guard !closing else { throw QwenRuntimeError.busy }
        let startedEpoch = epoch
        await waitForCacheCleanup()
        try Task.checkCancellation()
        guard !closing, epoch == startedEpoch else { throw CancellationError() }
        if model != nil { return }
        if let loading {
            lifecycle(.modelWaitStarted)
            let loaded = try await loading.task.value
            try Task.checkCancellation()
            guard !closing, epoch == startedEpoch else { throw CancellationError() }
            model = loaded
            return
        }
        let id = UUID()
        let task = Task.detached { [modelLoader] in try await modelLoader() }
        loading = (id, task)
        defer { if loading?.id == id { loading = nil } }
        // A canceled prewarm waiter may share this load with a file import.
        // Only explicit runtime teardown cancels the common loader.
        lifecycle(.modelWaitStarted)
        let loaded = try await task.value
        try Task.checkCancellation()
        guard !closing, epoch == startedEpoch else { throw CancellationError() }
        model = loaded
    }

    /// Complete mono, 16 kHz audio. Nil means model language detection; explicit English stays English.
    public func transcribe(samples: [Float], language: String? = nil) async throws -> String {
        guard samples.allSatisfy(\.isFinite) else { throw QwenRuntimeError.invalidAudio }
        guard !closing, generation == nil, streaming == nil, batchStarting == nil else { throw QwenRuntimeError.busy }
        let startupID = UUID()
        batchStarting = startupID
        defer { if batchStarting == startupID { batchStarting = nil } }
        try await prewarm()
        guard !closing, generation == nil, streaming == nil, let model else { throw QwenRuntimeError.busy }
        if samples.isEmpty { return "" }
        let startedEpoch = epoch
        let id = UUID()
        let task = Task.detached { [cacheCleanup] in
            try Task.checkCancellation()
            let result: QwenDecodeResult
            do {
                result = try await model.decode(samples: samples, prefix: "", language: language, encoderContext: nil, draft: nil)
            } catch {
                await cacheCleanup()
                throw error
            }
            await cacheCleanup()
            try Task.checkCancellation()
            guard case .eos = result.termination else { throw QwenRuntimeError.outputLimitReached }
            return try QwenTextPresentation.traditional(QwenTranscriptionText.parse(
                result.generatedText, forcedLanguage: language, expectsHeader: language == nil
            ).text)
        }
        generation = (id, task)
        defer { if generation?.id == id { generation = nil } }
        return try await withTaskCancellationHandler {
            let text = try await task.value
            try Task.checkCancellation()
            guard !closing, epoch == startedEpoch else { throw CancellationError() }
            return text
        } onCancel: {
            task.cancel()
        }
    }

    /// The app retains startup audio until this verified, warm session is ready.
    public func startStreaming(
        language: String? = nil,
        diagnostic: (@Sendable (QwenStreamingDiagnostic) -> Void)? = nil
    ) async throws -> QwenStreamingSession {
        lifecycle(.streamingRequested)
        guard !closing, generation == nil, streaming == nil, batchStarting == nil else { throw QwenRuntimeError.busy }
        let pair = AsyncThrowingStream<QwenStreamingEvent, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let session = LiveSession(language: language, continuation: pair.continuation, diagnostic: diagnostic)
        streaming = session
        lifecycle(.streamReserved(session.id))
        do {
            try await prewarm()
            guard streaming?.id == session.id, !closing else { throw CancellationError() }
            scheduleStream(session)
            return QwenStreamingSession(id: session.id, events: pair.stream)
        } catch {
            if streaming?.id == session.id { streaming = nil }
            session.continuation.finish(throwing: error)
            throw error
        }
    }

    public func appendAudio(_ samples: [Float], sessionID: UUID) throws {
        guard !closing, let session = streaming, session.id == sessionID else {
            throw QwenRuntimeError.busy
        }
        if let failure = session.failure { throw failure }
        guard !session.finishing else { throw QwenRuntimeError.busy }
        guard samples.allSatisfy(\.isFinite) else { throw QwenRuntimeError.invalidAudio }
        session.policy.append(samples)
        scheduleStream(session)
    }

    public func finishStreaming(sessionID: UUID) async throws {
        try Task.checkCancellation()
        guard !closing, model != nil, let session = streaming, session.id == sessionID else { throw QwenRuntimeError.busy }
        if let failure = session.failure { throw failure }
        session.diagnostic?(.init(.finishRequested, sessionID: session.id, isFinal: true))
        session.finishing = true
        if let live = session.liveDecode {
            session.diagnostic?(.init(.cancellationRequested, sessionID: session.id, decodeID: live.id, outcome: .superseded))
            session.supersededDecodeID = live.id
            live.task.cancel()
        }
        // startStreaming already owns a warm model. Install cancellation before
        // suspending so a canceled finish cannot leave its stream running.
        scheduleStream(session)
        if let task = session.task {
            await withTaskCancellationHandler {
                lifecycle(.finishRequested(sessionID))
                await task.value
            } onCancel: {
                task.cancel()
            }
        }
        try Task.checkCancellation()
        if let failure = session.failure { throw failure }
    }

    /// Disconnects one recording while retaining the warm model for the next recording.
    public func cancelStreaming(sessionID: UUID) async throws {
        lifecycle(.cancellationRequested(sessionID))
        if let cancellation = streamCancellation, cancellation.id == sessionID {
            await cancellation.task.value
            return
        }
        guard let session = streaming, session.id == sessionID else { return }
        guard !closing else { throw QwenRuntimeError.busy }
        session.diagnostic?(.init(.cancellationRequested, sessionID: session.id,
                                  decodeID: session.diagnosticDecode?.id,
                                  isFinal: session.diagnosticDecode?.isFinal ?? session.finishing, outcome: .cancelled))
        closing = true
        let task = Task { await self.completeStreamCancellation(session) }
        streamCancellation = (sessionID, task)
        await task.value
    }

    private func completeStreamCancellation(_ session: LiveSession) async {
        defer {
            closing = false
            streamCancellation = nil
        }
        session.task?.cancel()
        if let task = session.task { await task.value }
        model?.discardEncoderReuse()
        if let loading { _ = await loading.task.result }
        self.loading = nil
        session.failure = CancellationError()
        session.continuation.finish(throwing: CancellationError())
        streaming = nil
    }

    private func scheduleStream(_ session: LiveSession) {
        guard model != nil, session.task == nil, session.failure == nil else { return }
        let startedEpoch = epoch
        let id = session.id
        session.task = Task { [weak self] in
            guard let self else { return }
            await self.processStream(id: id, startedEpoch: startedEpoch)
        }
    }

    private func processStream(id: UUID, startedEpoch: UInt64) async {
        var needsCacheCleanup = false
        do {
            await waitForCacheCleanup()
            while let session = streaming, session.id == id, epoch == startedEpoch, !closing {
                try Task.checkCancellation()
                guard let model else {
                    throw QwenDecodeError.tokenizerUnavailable
                }
                // Superseded inference drains before one final pass over all PCM.
                let finalTail = session.finishing
                let audio = session.policy.takeAudio(finalTail: finalTail)
                    ?? (finalTail && session.needsFinalDecode ? session.policy.accumulatedAudio : nil)
                if audio == nil, !finalTail {
                    session.task = nil
                    return
                }
                guard let audio else {
                    model.discardEncoderReuse()
                    let text = try presentation(session, isFinal: true)
                    emit(.final(text), for: session)
                    session.continuation.finish()
                    streaming = nil
                    return
                }
                let prefix = try model.prefix(for: session.policy, finalTail: finalTail)
                let language = session.language
                let draft = finalTail ? session.lastCompletedDraft : nil
                let decodeID = UUID()
                let encoderContext = QwenEncoderContext(sessionID: id, decodeID: decodeID,
                    acceptedPredecessorID: session.acceptedDecodeID, isFinal: finalTail)
                let diagnostic = session.diagnostic
                if diagnostic != nil { session.diagnosticDecode = (decodeID, finalTail) }
                needsCacheCleanup = true
                let task = Task.detached {
                    diagnostic?(.init(.decodeBegin, sessionID: id, decodeID: decodeID,
                                      isFinal: finalTail, sampleCount: audio.count))
                    do {
                        try Task.checkCancellation()
                        let result = try await model.decode(samples: audio, prefix: prefix, language: language, encoderContext: encoderContext, draft: draft)
                        // decode returns only after its existing Metal drain, including on error.
                        let outcome: QwenStreamingDiagnostic.Outcome
                        switch result.termination { case .eos: outcome = .eos; case .tokenLimit: outcome = .tokenLimit }
                        diagnostic?(.init(.decodeEnd, sessionID: id, decodeID: decodeID,
                                          isFinal: finalTail, generationTokens: result.generationTokens, outcome: outcome, reusedEncoderBatches: result.reusedEncoderBatches, nativePhases: finalTail ? result.nativePhases : nil))
                        return result
                    } catch {
                        diagnostic?(.init(.decodeEnd, sessionID: id, decodeID: decodeID,
                                          isFinal: finalTail, outcome: error is CancellationError ? .cancelled : .error))
                        throw error
                    }
                }
                if !finalTail { session.liveDecode = (decodeID, task) }
                let result: QwenDecodeResult
                do {
                    result = try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: {
                        task.cancel()
                    }
                } catch {
                    beginCacheCleanup()
                    await waitForCacheCleanup()
                    needsCacheCleanup = false
                    session.diagnosticDecode = nil
                    diagnostic?(.init(.decodeReceived, sessionID: id, decodeID: decodeID,
                                      isFinal: finalTail, outcome: session.supersededDecodeID == decodeID ? .superseded : (error is CancellationError ? .cancelled : .error)))
                    if session.liveDecode?.id == decodeID { session.liveDecode = nil }
                    let wasSuperseded = session.supersededDecodeID == decodeID
                    if wasSuperseded { session.supersededDecodeID = nil }
                    if error is CancellationError, wasSuperseded, !finalTail,
                       !Task.isCancelled, streaming?.id == id, epoch == startedEpoch,
                       session.finishing, !closing {
                        // takeAudio already moved these samples into accumulatedAudio.
                        // Even an empty pending tail still needs a complete final decode.
                        session.needsFinalDecode = true
                        continue
                    }
                    throw error
                }
                session.diagnosticDecode = nil
                diagnostic?(.init(.decodeReceived, sessionID: id, decodeID: decodeID, isFinal: finalTail))
                if session.liveDecode?.id == decodeID { session.liveDecode = nil }
                if session.supersededDecodeID == decodeID { session.supersededDecodeID = nil }
                if !finalTail {
                    beginCacheCleanup()
                    await waitForCacheCleanup()
                    needsCacheCleanup = false
                }
                try Task.checkCancellation()
                guard streaming?.id == id, epoch == startedEpoch, !closing else { throw CancellationError() }
                guard case .eos(let eosToken) = result.termination else { throw QwenRuntimeError.outputLimitReached }
                session.policy.accept(prefix: prefix, generated: result.generatedText)
                if !finalTail {
                    session.lastCompletedDraft = QwenDecodeDraft(rawText: session.policy.rawDecoded, eosToken: eosToken)
                }
                session.acceptedDecodeID = decodeID
                session.needsFinalDecode = false
                if finalTail {
                    let text = try presentation(session, isFinal: true)
                    beginCacheCleanup()
                    needsCacheCleanup = false
                    emit(.final(text), for: session)
                    session.continuation.finish()
                    streaming = nil
                    return
                }
                if !session.finishing {
                    emit(.partial(try presentation(session, isFinal: false)), for: session)
                }
            }
        } catch {
            if needsCacheCleanup {
                beginCacheCleanup()
                await waitForCacheCleanup()
            }
            if let session = streaming, session.id == id {
                session.failure = error
                session.finishing = true
                session.task = nil
                session.continuation.finish(throwing: error)
                // Retain the terminal error until this lease disconnects; stop must report it.
            }
        }
    }

    private func beginCacheCleanup() {
        precondition(pendingCacheCleanup == nil)
        let id = UUID()
        // Retain this owner until disposal finishes; teardown and the next native
        // operation join the handle, while completed recording disconnect stays cheap.
        let task = Task.detached { [self, cacheCleanup] in
            await cacheCleanup()
            await cacheCleanupFinished(id: id)
        }
        pendingCacheCleanup = (id, task)
    }

    private func cacheCleanupFinished(id: UUID) {
        if pendingCacheCleanup?.id == id { pendingCacheCleanup = nil }
    }

    private func waitForCacheCleanup() async {
        while let cleanup = pendingCacheCleanup {
            lifecycle(.cacheCleanupWaitStarted)
            await cleanup.task.value
        }
    }

    private func emit(_ event: QwenStreamingEvent, for session: LiveSession) {
        lifecycle(.streamEvent(session.id, event))
        session.continuation.yield(event)
        if case .final = event { session.diagnostic?(.init(.finalEmitted, sessionID: session.id, isFinal: true)) }
    }

    private func presentation(_ session: LiveSession, isFinal: Bool) throws -> String {
        if isFinal { session.diagnostic?(.init(.presentationBegin, sessionID: session.id, isFinal: true)) }
        defer { if isFinal { session.diagnostic?(.init(.presentationEnd, sessionID: session.id, isFinal: true)) } }
        let text = QwenTranscriptionText.parse(
            session.policy.rawDecoded, forcedLanguage: session.language,
            isFinal: isFinal, expectsHeader: session.language == nil
        ).text
        return try QwenTextPresentation.traditional(text)
    }

    /// Drains actual tasks before releasing model memory. Cancellation is only a request.
    public func endRecordingSelection() async throws {
        lifecycle(.selectionEnding)
        if let id = streaming?.id { try await cancelStreaming(sessionID: id) }
        await unloadIfIdle()
    }

    /// Releases a warm model without disturbing another operation.
    public func unloadIfIdle() async {
        // Recording cleanup must not cancel an independent imported-file operation.
        guard !closing, loading == nil, generation == nil, streaming == nil, batchStarting == nil else { return }
        await waitForCacheCleanup()
        guard !closing, loading == nil, generation == nil, streaming == nil, batchStarting == nil, model != nil else { return }
        model = nil
        beginCacheCleanup()
        await waitForCacheCleanup()
    }

    /// Explicit model deletion/shutdown may cancel every operation owned by this runtime.
    public func unload() async throws {
        guard !closing else { throw QwenRuntimeError.busy }
        closing = true
        epoch &+= 1
        defer { closing = false }
        await drain()
    }

    public func delete() async throws {
        guard !closing else { throw QwenRuntimeError.busy }
        closing = true
        epoch &+= 1
        defer { closing = false }
        await drain()
        try await store.delete()
    }

    private func drain() async {
        loading?.task.cancel()
        generation?.task.cancel()
        streaming?.task?.cancel()
        await store.cancelAndDrain()
        if let loading { _ = await loading.task.result }
        if let generation { _ = await generation.task.result }
        if let task = streaming?.task { await task.value }
        await waitForCacheCleanup()
        streaming?.continuation.finish(throwing: CancellationError())
        streaming = nil
        loading = nil
        generation = nil
        model = nil
        beginCacheCleanup()
        await waitForCacheCleanup()
    }
}
