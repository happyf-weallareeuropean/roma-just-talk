import Foundation
import SwiftData
import os
import VoiceInkCore
import VoiceInkQwen

/// Sendable source that bridges audio chunks from any thread into an AsyncStream.
private final class AudioChunkSource: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func send(_ data: Data) {
        continuation.yield(data)
    }

    func finish() {
        continuation.finish()
    }
}

private final class StreamingMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedChunks = 0
    private var receivedBytes = 0
    private var sentChunks = 0
    private var sentBytes = 0

    func reset() {
        lock.lock()
        receivedChunks = 0
        receivedBytes = 0
        sentChunks = 0
        sentBytes = 0
        lock.unlock()
    }

    func recordReceived(_ byteCount: Int) {
        lock.lock()
        receivedChunks += 1
        receivedBytes += byteCount
        lock.unlock()
    }

    func recordSent(_ byteCount: Int) {
        lock.lock()
        sentChunks += 1
        sentBytes += byteCount
        lock.unlock()
    }

    func snapshot() -> (receivedChunks: Int, receivedBytes: Int, sentChunks: Int, sentBytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedChunks, receivedBytes, sentChunks, sentBytes)
    }
}

/// Lifecycle states for a streaming transcription session.
enum StreamingState {
    case idle
    case connecting
    case streaming
    case committing
    case done
    case failed
    case cancelled
}

/// Manages a streaming transcription lifecycle: buffers audio chunks, sends them to the provider, and collects the final text.
@MainActor
class StreamingTranscriptionService {

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "StreamingTranscriptionService")
    private var provider: StreamingTranscriptionProvider?
    private var sendTask: Task<VoiceInkLatencyTrace.ExecutorCheckpoint?, Never>?
    private var drainAndCommitTask: Task<VoiceInkLatencyTrace.ExecutorCheckpoint?, Error>?
    private var eventConsumerTask: Task<Void, Never>?
    private let chunkSource = AudioChunkSource()
    private var state: StreamingState = .idle
    private var transcriptAccumulator = VoiceInkStreamingTranscriptAccumulator()
    private let modelContext: ModelContext?
    private let streamingAdapterKind: VoiceInkTranscriptionStreamingAdapterKind
    private let fluidAudioService: FluidAudioTranscriptionService?
    private let qwenRuntimeResult: Result<QwenRuntime, Error>?
    private let providerFactory: ((any TranscriptionModel) -> StreamingTranscriptionProvider)?
    private let onDrainWaitStarted: (@Sendable () -> Void)?
    private let finalCommitTimeoutNanoseconds: UInt64
    private var onPartialTranscript: ((String) -> Void)?
    private let metrics = StreamingMetrics()
    private var stopStartedAt: Date?
    private var firstPartialLogged = false
    private var firstCommitLogged = false

    init(
        modelContext: ModelContext,
        streamingAdapterKind: VoiceInkTranscriptionStreamingAdapterKind,
        fluidAudioService: FluidAudioTranscriptionService? = nil,
        qwenRuntimeResult: Result<QwenRuntime, Error>? = nil,
        finalCommitTimeoutNanoseconds: UInt64 = VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds,
        onPartialTranscript: ((String) -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.streamingAdapterKind = streamingAdapterKind
        self.fluidAudioService = fluidAudioService
        self.qwenRuntimeResult = qwenRuntimeResult
        self.providerFactory = nil
        self.onDrainWaitStarted = nil
        self.finalCommitTimeoutNanoseconds = finalCommitTimeoutNanoseconds
        self.onPartialTranscript = onPartialTranscript
    }

    init(
        streamingAdapterKind: VoiceInkTranscriptionStreamingAdapterKind,
        finalCommitTimeoutNanoseconds: UInt64 = VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds,
        onPartialTranscript: ((String) -> Void)? = nil,
        onDrainWaitStarted: (@Sendable () -> Void)? = nil,
        providerFactory: @escaping (any TranscriptionModel) -> StreamingTranscriptionProvider
    ) {
        self.modelContext = nil
        self.streamingAdapterKind = streamingAdapterKind
        self.fluidAudioService = nil
        self.qwenRuntimeResult = nil
        self.providerFactory = providerFactory
        self.onDrainWaitStarted = onDrainWaitStarted
        self.finalCommitTimeoutNanoseconds = finalCommitTimeoutNanoseconds
        self.onPartialTranscript = onPartialTranscript
    }

    deinit {
        onPartialTranscript = nil
        sendTask?.cancel()
        drainAndCommitTask?.cancel()
        eventConsumerTask?.cancel()
        chunkSource.finish()
        commitSignal?.finish()
    }

    /// Signal used to notify `waitForFinalCommit` when a new committed segment arrives.
    private var commitSignal: AsyncStream<Void>.Continuation?
    private var latencyTraceToken: VoiceInkLatencyTrace.Token?

    /// Whether the streaming connection is fully established and actively sending.
    var isActive: Bool { state == .streaming || state == .committing }

    /// Start a streaming transcription session for the given model.
    func startStreaming(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) async throws {
        let start = Date()
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken ?? latencyTrace.currentToken()
        self.latencyTraceToken = traceToken
        latencyTrace.event(
            "streaming_service.start.enter",
            details: "model=\(model.displayName) adapter=\(String(describing: streamingAdapterKind))",
            token: traceToken
        )
        state = .connecting
        transcriptAccumulator.reset()
        metrics.reset()
        latencyTrace.event("streaming_service.metrics.reset", token: traceToken)
        firstPartialLogged = false
        firstCommitLogged = false

        let provider = createProvider(for: model)
        provider.setLatencyTraceToken(traceToken)
        self.provider = provider

        let selectedLanguage = VoiceInkTranscriptionLanguagePreference.selectedLanguage()
        logger.notice("Streaming start requested model=\(model.displayName, privacy: .public) language=\(selectedLanguage, privacy: .public)")

        let providerConnectSpan = latencyTrace.begin("streaming_provider.connect", token: traceToken)
        do {
            try await provider.connect(model: model, language: selectedLanguage)
            latencyTrace.end(providerConnectSpan, details: "result=success")
        } catch {
            latencyTrace.end(
                providerConnectSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            throw error
        }

        // If cancel() was called while we were awaiting the connection, tear down immediately.
        if state == .cancelled {
            await provider.disconnect()
            self.provider = nil
            return
        }

        state = .streaming
        startSendLoop(latencyTraceToken: traceToken)
        startEventConsumer(latencyTraceToken: traceToken)
        latencyTrace.event("streaming_service.state.streaming", token: traceToken)

        logger.notice("Streaming connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
    }

    /// Buffers an audio chunk for sending. Safe to call from the audio callback thread.
    nonisolated func sendAudioChunk(_ data: Data) {
        metrics.recordReceived(data.count)
        chunkSource.send(data)
    }

    /// Stops streaming, commits remaining audio, and returns the final transcribed text.
    func stopAndGetFinalText(
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) async throws -> String {
        guard let provider = provider, state == .streaming else {
            throw VoiceInkStreamingTranscriptionError.notConnected
        }
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken ?? self.latencyTraceToken

        state = .committing
        stopStartedAt = Date()
        let beforeDrain = metrics.snapshot()
        latencyTrace.event(
            "streaming_service.stop.enter",
            details: "receivedChunks=\(beforeDrain.receivedChunks) sentChunks=\(beforeDrain.sentChunks) receivedBytes=\(beforeDrain.receivedBytes) sentBytes=\(beforeDrain.sentBytes)",
            token: traceToken
        )
        logger.notice("Streaming stop requested receivedChunks=\(beforeDrain.receivedChunks, privacy: .public) sentChunks=\(beforeDrain.sentChunks, privacy: .public) receivedBytes=\(beforeDrain.receivedBytes, privacy: .public) sentBytes=\(beforeDrain.sentBytes, privacy: .public)")

        // Set up the commit signal BEFORE sending commit to avoid a race with the response.
        let (signalStream, signalContinuation) = AsyncStream.makeStream(of: Void.self)
        self.commitSignal = signalContinuation

        // Drain and commit away from MainActor so local final ASR can overlap recorder restoration.
        let drainSpan = latencyTrace.begin("streaming_service.drain", token: traceToken)
        let pendingSendTask = sendTask
        let metrics = metrics
        let onDrainWaitStarted = onDrainWaitStarted
        let drainAndCommitTask = Task.detached {
            onDrainWaitStarted?()
            let drainCheckpoint = await pendingSendTask?.value
            try Task.checkCancellation()
            latencyTrace.executorResumed(
                drainCheckpoint,
                details: "executor=commit_worker"
            )
            let afterDrain = metrics.snapshot()
            latencyTrace.end(
                drainSpan,
                details: "receivedChunks=\(afterDrain.receivedChunks) sentChunks=\(afterDrain.sentChunks) receivedBytes=\(afterDrain.receivedBytes) sentBytes=\(afterDrain.sentBytes)"
            )

            let commitSpan = latencyTrace.begin("streaming_provider.commit", token: traceToken)
            do {
                try await provider.commit()
                latencyTrace.end(commitSpan, details: "result=success")
            } catch {
                latencyTrace.end(
                    commitSpan,
                    details: "result=failure error=\(String(describing: type(of: error)))"
                )
                throw error
            }

            return latencyTrace.executorEnqueued(
                "streaming_service.commit_continuation",
                token: traceToken
            )
        }
        self.drainAndCommitTask = drainAndCommitTask
        chunkSource.finish()

        do {
            let commitCheckpoint = try await drainAndCommitTask.value
            latencyTrace.executorResumed(
                commitCheckpoint,
                details: "executor=main_actor"
            )
            self.drainAndCommitTask = nil
            sendTask = nil
        } catch {
            self.drainAndCommitTask = nil
            sendTask = nil
            commitSignal?.finish()
            commitSignal = nil
            if error is CancellationError || state == .cancelled {
                logger.notice("Streaming commit cancelled")
            } else {
                logger.error("Failed to send commit: \(error.localizedDescription, privacy: .public)")
                state = .failed
            }
            await cleanupStreaming()
            throw error
        }

        // Wait for the server to acknowledge our commit (or timeout)
        let finalWaitSpan = latencyTrace.begin("streaming_service.final_wait", token: traceToken)
        let finalText = await waitForFinalCommit(signalStream: signalStream)
        latencyTrace.end(finalWaitSpan, details: "chars=\(finalText.count)")
        if let stopStartedAt {
            logger.notice("Streaming stop completed elapsed=\(Date().timeIntervalSince(stopStartedAt), format: .fixed(precision: 3), privacy: .public)s finalChars=\(finalText.count, privacy: .public)")
        }

        state = .done
        await cleanupStreaming()

        return finalText
    }

    /// Cancels the streaming session without waiting for results.
    func cancel(latencyTraceToken: VoiceInkLatencyTrace.Token? = nil) {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken ?? self.latencyTraceToken
        latencyTrace.event(
            "streaming_service.cancel",
            details: "state=\(String(describing: state))",
            token: traceToken
        )
        state = .cancelled
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        drainAndCommitTask?.cancel()
        drainAndCommitTask = nil
        chunkSource.finish()

        // Clean up commit signal if waiting
        commitSignal?.finish()
        commitSignal = nil

        let providerToDisconnect = provider
        provider = nil

        Task {
            await providerToDisconnect?.disconnect()
        }

        transcriptAccumulator.reset()
        logger.notice("Streaming cancelled")
    }

    // MARK: - Private

    private func createProvider(for model: any TranscriptionModel) -> StreamingTranscriptionProvider {
        if let providerFactory {
            return providerFactory(model)
        }

        switch streamingAdapterKind {
        case .localQwen:
            return QwenStreamingProvider(
                runtimeResult: qwenRuntimeResult ?? .failure(VoiceInkEngineError.modelLoadFailed)
            )
        case .localFluidAudio:
            guard let fluidAudioService else {
                fatalError("FluidAudioTranscriptionService required for FluidAudio streaming. Ensure it is passed to StreamingTranscriptionService.")
            }
            return FluidAudioStreamingProvider(
                fluidAudioService: fluidAudioService,
                config: .resolveHingeStreaming
            )
        case .cloud:
            guard let modelContext,
                  let cloudProvider = CloudProviderRegistry.provider(for: model.provider),
                  let streamingProvider = cloudProvider.makeStreamingProvider(modelContext: modelContext) else {
                fatalError("Unsupported streaming provider: \(model.provider). Check supportsStreaming() before calling startStreaming().")
            }
            return streamingProvider
        }
    }

    /// Consumes audio chunks from the AsyncStream and sends them to the provider.
    private func startSendLoop(latencyTraceToken: VoiceInkLatencyTrace.Token?) {
        let source = chunkSource
        let provider = provider
        let metrics = metrics

        sendTask = Task.detached { [weak self] in
            VoiceInkLatencyTrace.shared.event(
                "streaming_send_loop.enter",
                token: latencyTraceToken
            )
            for await chunk in source.stream {
                do {
                    try await provider?.sendAudioChunk(chunk)
                    metrics.recordSent(chunk.count)
                } catch {
                    let desc = error.localizedDescription
                    await MainActor.run {
                        self?.logger.error("Failed to send audio chunk: \(desc, privacy: .public)")
                    }
                }
            }
            let snapshot = metrics.snapshot()
            VoiceInkLatencyTrace.shared.event(
                "streaming_send_loop.exit",
                details: "sentChunks=\(snapshot.sentChunks) sentBytes=\(snapshot.sentBytes)",
                token: latencyTraceToken
            )
            return VoiceInkLatencyTrace.shared.executorEnqueued(
                "streaming_service.drain_continuation",
                details: "sentChunks=\(snapshot.sentChunks) sentBytes=\(snapshot.sentBytes)",
                token: latencyTraceToken
            )
        }
    }

    /// Consumes transcription events throughout the session, accumulating committed segments.
    private func startEventConsumer(latencyTraceToken: VoiceInkLatencyTrace.Token?) {
        guard let provider = provider else { return }
        let events = provider.transcriptionEvents

        eventConsumerTask = Task.detached { [weak self] in
            for await event in events {
                guard let self = self else { break }
                switch event {
                case .committed(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        if !self.firstCommitLogged {
                            self.firstCommitLogged = true
                            VoiceInkLatencyTrace.shared.event(
                                "streaming_event.first_commit",
                                details: "chars=\(trimmed.count)",
                                token: latencyTraceToken
                            )
                            let elapsed = self.stopStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                            self.logger.notice("Streaming first committed event chars=\(trimmed.count, privacy: .public) stopElapsed=\(elapsed, format: .fixed(precision: 3), privacy: .public)s")
                        }
                        _ = self.transcriptAccumulator.appendCommitted(trimmed)
                        // Refresh the live preview so it keeps showing the full running transcript
                        // after a commit (instead of resetting to empty until the next partial).
                        if self.state == .streaming {
                            self.onPartialTranscript?(self.transcriptAccumulator.committedText)
                        }
                        if self.state == .committing {
                            self.commitSignal?.yield()
                        }
                    }
                case .partial(let text):
                    await MainActor.run {
                        if !self.firstPartialLogged {
                            self.firstPartialLogged = true
                            VoiceInkLatencyTrace.shared.event(
                                "streaming_event.first_partial",
                                details: "chars=\(text.count)",
                                token: latencyTraceToken
                            )
                            self.logger.notice("Streaming first partial event chars=\(text.count, privacy: .public)")
                        }
                        if self.state == .streaming {
                            let display = self.transcriptAccumulator.preview(partialText: text)
                            self.onPartialTranscript?(display)
                        }
                    }
                case .sessionStarted:
                    break
                case .error(let error):
                    await MainActor.run {
                        self.logger.error("Streaming event error: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }  
        }
    }

    /// Waits for the provider to acknowledge our explicit commit.
    private func waitForFinalCommit(signalStream: AsyncStream<Void>) async -> String {
        // Race: wait for commit acknowledgment vs timeout
        let receivedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                for await _ in signalStream {
                    return true
                }
                return false
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: self.finalCommitTimeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        logger.notice("Streaming final wait finished received=\(receivedInTime, privacy: .public) segments=\(self.transcriptAccumulator.committedSegments.count, privacy: .public)")

        // Clean up the signal
        commitSignal?.finish()
        commitSignal = nil

        if !receivedInTime && transcriptAccumulator.committedSegments.isEmpty {
            logger.warning("No transcript received from streaming")
        }

        return transcriptAccumulator.committedText
    }

    private func cleanupStreaming() async {
        onPartialTranscript = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        sendTask?.cancel()
        sendTask = nil
        drainAndCommitTask?.cancel()
        drainAndCommitTask = nil
        chunkSource.finish()
        commitSignal?.finish()
        commitSignal = nil
        await provider?.disconnect()
        provider = nil
        state = .idle
        transcriptAccumulator.reset()
    }
}
