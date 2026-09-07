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

/// One local model owner shared by file transcription and the streaming adapter.
public actor QwenRuntime {
    // MLX modules are not Sendable. Only this actor grants access, one operation at a time;
    // a task retains the model until its Metal stream has actually drained.
    final class LoadedModel: @unchecked Sendable {
        let value: Qwen3ASRModel
        init(_ value: Qwen3ASRModel) { self.value = value }
    }

    private let store: QwenModelStore
    private let modelLoader: @Sendable () async throws -> LoadedModel
    enum LifecycleEvent: Sendable {
        case modelWaitStarted
        case streamingRequested
        case streamReserved(UUID)
        case cancellationRequested(UUID)
        case selectionEnding
    }
    private let lifecycle: @Sendable (LifecycleEvent) -> Void
    private var model: LoadedModel?
    private var loading: (id: UUID, task: Task<LoadedModel, Error>)?
    private var generation: (id: UUID, task: Task<String, Error>)?
    private var batchStarting: UUID?
    private var streamCancellation: (id: UUID, task: Task<Void, Never>)?
    // Mutable state stays actor-isolated; Sendable permits cancellation-only access in deinit.
    private final class LiveSession: @unchecked Sendable {
        let id = UUID()
        let language: String?
        let continuation: AsyncThrowingStream<QwenStreamingEvent, Error>.Continuation
        var policy = QwenStreamingPolicy(chunkSamples: 5_600)
        var task: Task<Void, Never>?
        var finishing = false
        var failure: Error?

        init(language: String?, continuation: AsyncThrowingStream<QwenStreamingEvent, Error>.Continuation) {
            self.language = language
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
        modelLoader: @escaping @Sendable () async throws -> LoadedModel,
        lifecycle: @escaping @Sendable (LifecycleEvent) -> Void
    ) throws {
        store = QwenModelStore(root: cacheDirectory, snapshot: try .bundled())
        self.modelLoader = modelLoader
        self.lifecycle = lifecycle
    }

    deinit {
        loading?.task.cancel()
        generation?.task.cancel()
        streaming?.task.cancel()
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
        let task = Task.detached {
            try Task.checkCancellation()
            return try Device.withDefaultDevice(.gpu) {
                try Stream.withNewDefaultStream(device: .gpu) {
                    defer { StreamOrDevice.default.stream.synchronize() }
                    let result = try QwenGreedyDecoder.decode(model: model.value, samples: samples, language: language)
                    try Task.checkCancellation()
                    guard case .eos = result.termination else { throw QwenRuntimeError.outputLimitReached }
                    return try QwenTextPresentation.traditional(QwenTranscriptionText.parse(
                        result.generatedText, forcedLanguage: language, expectsHeader: language == nil
                    ).text)
                }
            }
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
    public func startStreaming(language: String? = nil) async throws -> QwenStreamingSession {
        lifecycle(.streamingRequested)
        guard !closing, generation == nil, streaming == nil, batchStarting == nil else { throw QwenRuntimeError.busy }
        let pair = AsyncThrowingStream<QwenStreamingEvent, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let session = LiveSession(language: language, continuation: pair.continuation)
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
        guard !closing, let session = streaming, session.id == sessionID else { throw QwenRuntimeError.busy }
        if let failure = session.failure { throw failure }
        session.finishing = true
        try await prewarm()
        guard streaming?.id == session.id, !closing else { throw CancellationError() }
        scheduleStream(session)
        if let task = session.task {
            await withTaskCancellationHandler {
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
        do {
            while let session = streaming, session.id == id, epoch == startedEpoch, !closing {
                try Task.checkCancellation()
                guard let model, let tokenizer = model.value.tokenizer else {
                    throw QwenDecodeError.tokenizerUnavailable
                }
                let audio: [Float]?
                let finalTail: Bool
                if let chunk = session.policy.takeAudio() {
                    audio = chunk
                    finalTail = false
                } else if session.finishing {
                    audio = session.policy.takeAudio(finalTail: true)
                    finalTail = true
                } else {
                    session.task = nil
                    return
                }
                guard let audio else {
                    let text = try presentation(session, isFinal: true)
                    session.continuation.yield(.final(text))
                    session.continuation.finish()
                    streaming = nil
                    return
                }
                let prefix = session.policy.prefix(
                    finalTail: finalTail,
                    encode: { tokenizer.encode(text: $0) },
                    decode: { tokenizer.decode(tokens: $0) }
                )
                let language = session.language
                let task = Task.detached {
                    try Device.withDefaultDevice(.gpu) {
                        try Stream.withNewDefaultStream(device: .gpu) {
                            defer { StreamOrDevice.default.stream.synchronize() }
                            return try QwenGreedyDecoder.decode(
                                model: model.value, samples: audio, prefix: prefix, language: language
                            )
                        }
                    }
                }
                let result = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
                try Task.checkCancellation()
                guard streaming?.id == id, epoch == startedEpoch, !closing else { return }
                guard case .eos = result.termination else { throw QwenRuntimeError.outputLimitReached }
                session.policy.accept(prefix: prefix, generated: result.generatedText)
                session.continuation.yield(.partial(try presentation(session, isFinal: false)))
            }
        } catch {
            if let session = streaming, session.id == id {
                session.failure = error
                session.finishing = true
                session.task = nil
                session.continuation.finish(throwing: error)
                // Retain the terminal error until this lease disconnects; stop must report it.
            }
        }
    }

    private func presentation(_ session: LiveSession, isFinal: Bool) throws -> String {
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
        unloadIfIdle()
    }

    /// Releases a warm model without disturbing another operation.
    public func unloadIfIdle() {
        // Recording cleanup must not cancel an independent imported-file operation.
        guard !closing, loading == nil, generation == nil, streaming == nil, batchStarting == nil, model != nil else { return }
        model = nil
        Memory.clearCache()
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
        streaming?.continuation.finish(throwing: CancellationError())
        streaming = nil
        loading = nil
        generation = nil
        model = nil
        Memory.clearCache()
    }
}
