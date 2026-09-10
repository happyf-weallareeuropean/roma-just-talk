import Foundation
import os
import VoiceInkCore
import VoiceInkQwen

/// Adapts the single local runtime to the existing recording/event pipeline.
actor QwenStreamingProvider: StreamingTranscriptionProvider {
    private let runtimeResult: Result<QwenRuntime, Error>
    private let continuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation
    nonisolated let transcriptionEvents: AsyncStream<VoiceInkStreamingTranscriptionEvent>
    private var connectionID: UUID?
    private var connecting: Task<QwenStreamingSession, Error>?
    private var session: QwenStreamingSession?
    private var eventTask: Task<Void, Never>?
    private nonisolated let traceToken = OSAllocatedUnfairLock<VoiceInkLatencyTrace.Token?>(initialState: nil)

    init(runtimeResult: Result<QwenRuntime, Error>) {
        self.runtimeResult = runtimeResult
        let pair = AsyncStream<VoiceInkStreamingTranscriptionEvent>.makeStream()
        transcriptionEvents = pair.stream
        continuation = pair.continuation
    }

    deinit {
        connecting?.cancel()
        eventTask?.cancel()
        continuation.finish()
        let runtime = try? runtimeResult.get()
        let pending = connecting
        let id = session?.id
        // Session IDs prevent delayed destruction of the old provider canceling a new recording.
        Task {
            if let pending, let prepared = try? await pending.value {
                try? await runtime?.cancelStreaming(sessionID: prepared.id)
            }
            if let id { try? await runtime?.cancelStreaming(sessionID: id) }
        }
    }

    nonisolated func setLatencyTraceToken(_ token: VoiceInkLatencyTrace.Token?) {
        traceToken.withLock { $0 = token }
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard connectionID == nil else { throw QwenRuntimeError.busy }
        let runtime = try runtimeResult.get()
        let id = UUID()
        connectionID = id
        let selectedLanguage = language == VoiceInkLanguageCatalog.autoDetectCode ? nil : language
        let span = VoiceInkLatencyTrace.shared.begin("qwen_streaming.prewarm", token: traceToken.withLock { $0 })
        defer { VoiceInkLatencyTrace.shared.end(span) }
        // Capture this recording's token once; delayed callbacks cannot attach to a new recording.
        let recordToken = traceToken.withLock { $0 }
        let diagnostic: (@Sendable (QwenStreamingDiagnostic) -> Void)?
        if let recordToken {
            diagnostic = { event in
                let phases = event.nativePhases.map { values in values.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",") } ?? "none"
                let details = "session=\(event.sessionID) decode=\(event.decodeID?.uuidString ?? "none") final=\(event.isFinal) samples=\(event.sampleCount.map(String.init) ?? "none") tokens=\(event.generationTokens.map(String.init) ?? "none") reusedEncoderBatches=\(event.reusedEncoderBatches.map(String.init) ?? "none") outcome=\(event.outcome?.rawValue ?? "none") uptime=\(event.uptime) nativePhases=\(phases) reusedDecoderTokens=\(event.reusedDecoderTokens.map(String.init) ?? "none")"
                VoiceInkLatencyTrace.shared.event("qwen_streaming.\(event.phase.rawValue)", details: details, token: recordToken)
            }
        } else {
            diagnostic = nil
        }
        let task = Task { try await runtime.startStreaming(language: selectedLanguage, diagnostic: diagnostic) }
        connecting = task
        var prepared: QwenStreamingSession?
        do {
            let ready = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            prepared = ready
            try Task.checkCancellation()
            guard connectionID == id else { throw CancellationError() }
            connecting = nil
            session = ready
            continuation.yield(.sessionStarted)
            eventTask = Task { [continuation] in
                do {
                    for try await event in ready.events {
                        try Task.checkCancellation()
                        switch event {
                        case .partial(let text): continuation.yield(.partial(text: text))
                        case .final(let text): continuation.yield(.committed(text: text))
                        }
                    }
                } catch is CancellationError {
                } catch {
                    continuation.yield(.error(error))
                }
                continuation.finish()
            }
        } catch {
            if connectionID == id {
                connectionID = nil
                connecting = nil
            }
            if let prepared { try? await runtime.cancelStreaming(sessionID: prepared.id) }
            throw error
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let session else { throw QwenRuntimeError.busy }
        guard data.count.isMultiple(of: MemoryLayout<Int16>.size) else { throw QwenRuntimeError.invalidAudio }
        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)
        try await runtimeResult.get().appendAudio(samples, sessionID: session.id)
    }

    func commit() async throws {
        guard let session else { throw QwenRuntimeError.busy }
        let span = VoiceInkLatencyTrace.shared.begin("qwen_streaming.finalize", token: traceToken.withLock { $0 })
        defer { VoiceInkLatencyTrace.shared.end(span) }
        try await runtimeResult.get().finishStreaming(sessionID: session.id)
    }

    func disconnect() async {
        connectionID = nil
        let pending = connecting
        connecting = nil
        let active = session
        session = nil
        let consumer = eventTask
        eventTask = nil
        pending?.cancel()
        consumer?.cancel()
        let runtime = try? runtimeResult.get()
        if let pending, let prepared = try? await pending.value {
            try? await runtime?.cancelStreaming(sessionID: prepared.id)
        }
        if let active { try? await runtime?.cancelStreaming(sessionID: active.id) }
        await consumer?.value
        continuation.finish()
    }
}
