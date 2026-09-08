import FluidAudio
import Foundation
import os
import VoiceInkCore

/// Agreement-based on-device streaming transcription using FluidAudio ASR.
final class FluidAudioStreamingProvider {

    typealias ModelLoader = (String) async throws -> AsrModels

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "FluidAudioStreaming")
    private let loadModels: ModelLoader
    private var latencyTraceToken: VoiceInkLatencyTrace.Token?
    private var eventsContinuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation?

    private(set) var transcriptionEvents: AsyncStream<VoiceInkStreamingTranscriptionEvent>

    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let sampleRate = VoiceInkPCM16Audio.mono16kSampleRate
    // Samples trimmed from buffer front; subtract from absolute indices for buffer-relative access.
    private var trimmedSampleCount: Int = 0

    private var asrManager: AsrManager?
    private var decoderLayerCount: Int = 0
    private var languageHint: Language?
    private let agreementEngine: WordAgreementEngine
    private let config: AgreementConfig

    private var transcriptionTask: Task<Void, Never>?
    private var finalTranscriptionTask: Task<String?, Never>?
    private var isDisconnected = false
    private var isTranscribing = false
    private var isFinalizing = false
    // This is narrower than isTranscribing: it brackets the manager await.
    private var isLiveManagerCallInFlight = false
    private var inFlightSampleCount = 0
    private var lastTranscribedSampleCount = 0
    private var latestHypothesisText = ""
    private var latestHypothesisSampleCount = 0
    private let minimumAudioSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
    private let minNewSamples = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)

    #if DEBUG
    private var transcribeForTesting: (([Float]) async throws -> ASRResult)?
    private var beforeDisconnectCleanupForTesting: (() -> Void)?

    convenience init(
        config: AgreementConfig,
        beforeDisconnectCleanupForTesting: (() -> Void)? = nil,
        transcribeForTesting: @escaping ([Float]) async throws -> ASRResult
    ) {
        self.init(loadModels: { _ in throw CancellationError() }, config: config)
        self.asrManager = AsrManager(config: .default)
        self.decoderLayerCount = 2
        self.transcribeForTesting = transcribeForTesting
        self.beforeDisconnectCleanupForTesting = beforeDisconnectCleanupForTesting
        startTranscriptionLoop()
    }
    #endif

    init(loadModels: @escaping ModelLoader, config: AgreementConfig = AgreementConfig()) {
        self.loadModels = loadModels
        self.config = config
        self.agreementEngine = WordAgreementEngine(config: config)

        var continuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    #if os(macOS)
    convenience init(
        fluidAudioService: FluidAudioTranscriptionService,
        config: AgreementConfig = AgreementConfig()
    ) {
        self.init(
            loadModels: { modelName in
                try await fluidAudioService.getOrLoadModels(
                    for: FluidAudioModelManager.asrVersion(for: modelName)
                )
            },
            config: config
        )
    }
    #endif

    deinit {
        transcriptionTask?.cancel()
        finalTranscriptionTask?.cancel()
        eventsContinuation?.finish()
    }

    func setLatencyTraceToken(_ token: VoiceInkLatencyTrace.Token?) {
        latencyTraceToken = token
    }

    func connect(modelName: String, language: String?) async throws {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let modelDataSpan = latencyTrace.begin("fluid_streaming.load_model_data", token: traceToken)
        let models: AsrModels
        do {
            models = try await loadModels(modelName)
            latencyTrace.end(modelDataSpan, details: "result=success")
        } catch {
            latencyTrace.end(
                modelDataSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            throw error
        }
        try Task.checkCancellation()

        let manager = AsrManager(config: .default)
        let managerLoadSpan = latencyTrace.begin("fluid_streaming.manager_load", token: traceToken)
        do {
            try await manager.loadModels(models)
            latencyTrace.end(managerLoadSpan, details: "result=success")
            try Task.checkCancellation()
        } catch {
            latencyTrace.end(
                managerLoadSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            await manager.cleanup()
            throw error
        }
        self.asrManager = manager
        self.decoderLayerCount = await manager.decoderLayerCount
        self.languageHint = FluidAudioModelManager.languageHint(
            from: language,
            for: modelName
        )

        agreementEngine.reset()
        audioBuffer = []
        trimmedSampleCount = 0
        lastTranscribedSampleCount = 0
        latestHypothesisText = ""
        latestHypothesisSampleCount = 0
        isFinalizing = false
        isDisconnected = false
        isLiveManagerCallInFlight = false
        inFlightSampleCount = 0

        startTranscriptionLoop()

        eventsContinuation?.yield(.sessionStarted)
        logger.notice("FluidAudio agreement streaming started for \(modelName, privacy: .public)")
    }

    func sendAudioChunk(_ data: Data) async throws {
        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)
        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()
    }

    func commit() async throws {
        let commitStartedAt = Date()
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let loopStopSpan = latencyTrace.begin("fluid_streaming.stop_background_loop", token: traceToken)
        let liveTask = currentLiveTask()
        liveTask?.cancel()
        let liveStateAtCommit = freezeLiveTranscription()
        if !liveStateAtCommit.canOverlapFinal {
            await liveTask?.value
        }
        latencyTrace.end(
            loopStopSpan,
            details: "overlapFinal=\(liveStateAtCommit.canOverlapFinal) livePassInFlightAtCommit=\(liveStateAtCommit.livePassInFlight) liveManagerCallInFlightAtCommit=\(liveStateAtCommit.liveManagerCallInFlight)"
        )

        let commitPlan = completeHypothesisCommitPlan()
        if let reusableText = commitPlan.reusableText {
            await liveTask?.value
            clearLiveTask()
            try ensureCommitActive()
            latencyTrace.event(
                "fluid_streaming.commit.reuse_complete_hypothesis",
                details: "pendingSamples=\(commitPlan.pendingSamples) chars=\(reusableText.count)",
                token: traceToken
            )
            logger.notice("FluidAudio commit reused complete key-down hypothesis elapsed=\(Date().timeIntervalSince(commitStartedAt), format: .fixed(precision: 3), privacy: .public)s chars=\(reusableText.count, privacy: .public)")
            try yieldFinalText(reusableText)
            return
        }

        latencyTrace.event(
            "fluid_streaming.commit.final_asr_required",
            details: "pendingSamples=\(commitPlan.pendingSamples)",
            token: traceToken
        )

        let finalASRSpan = latencyTrace.begin("fluid_streaming.final_asr", token: traceToken)
        guard !Task.isCancelled, let finalTask = beginFinalTranscription() else {
            await liveTask?.value
            clearLiveTask()
            throw CancellationError()
        }
        let finalASRText = await withTaskCancellationHandler {
            await finalTask.value ?? ""
        } onCancel: {
            finalTask.cancel()
        }
        latencyTrace.end(finalASRSpan, details: "chars=\(finalASRText.count)")
        // Core ML cancellation is cooperative. Drain the cancelled pass after overlapping final ASR.
        let joinSpan = latencyTrace.begin("fluid_streaming.join_background_loop", token: traceToken)
        await liveTask?.value
        clearLiveTask()
        latencyTrace.end(joinSpan)
        try ensureCommitActive()
        // A cold final pass can be empty after live ASR already recognized the remaining speech.
        let committedText = VoiceInkFluidAudioTranscriptionPolicy.resolvedCommitText(
            finalASRText: finalASRText,
            latestHypothesisText: currentHypothesisText()
        )
        if finalASRText.isEmpty && !committedText.isEmpty {
            latencyTrace.event(
                "fluid_streaming.commit.fallback_to_hypothesis",
                details: "pendingSamples=\(commitPlan.pendingSamples) chars=\(committedText.count)",
                token: traceToken
            )
            logger.notice("FluidAudio final ASR was empty; committed the latest live hypothesis chars=\(committedText.count, privacy: .public)")
        }
        logger.notice("FluidAudio commit ran final ASR elapsed=\(Date().timeIntervalSince(commitStartedAt), format: .fixed(precision: 3), privacy: .public)s chars=\(finalASRText.count, privacy: .public)")
        try yieldFinalText(committedText)
    }

    func disconnect() async {
        let tasks = disconnectTasks()
        tasks.live?.cancel()
        tasks.final?.cancel()
        await tasks.live?.value
        _ = await tasks.final?.value
        clearLiveTask()

        #if DEBUG
        beforeDisconnectCleanupForTesting?()
        #endif
        await asrManager?.cleanup()
        asrManager = nil
        decoderLayerCount = 0
        languageHint = nil

        bufferLock.lock()
        audioBuffer = []
        trimmedSampleCount = 0
        latestHypothesisText = ""
        latestHypothesisSampleCount = 0
        agreementEngine.reset()
        bufferLock.unlock()

        eventsContinuation?.finish()
        logger.notice("FluidAudio agreement streaming disconnected")
    }

    // MARK: - Private

    private func beginFinalTranscription() -> Task<String?, Never>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard !isDisconnected else { return nil }
        let task = Task { [weak self] in await self?.transcribeRemainingAudio() }
        finalTranscriptionTask = task
        return task
    }

    private func ensureCommitActive() throws {
        try Task.checkCancellation()
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard !isDisconnected else { throw CancellationError() }
    }

    private func yieldFinalText(_ text: String) throws {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard !isDisconnected, !Task.isCancelled else { throw CancellationError() }
        eventsContinuation?.yield(.committed(text: text))
    }

    private func clearLiveTask() {
        bufferLock.lock()
        transcriptionTask = nil
        bufferLock.unlock()
    }

    private func currentLiveTask() -> Task<Void, Never>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return transcriptionTask
    }

    private func currentHypothesisText() -> String {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return latestHypothesisText
    }

    private func disconnectTasks() -> (live: Task<Void, Never>?, final: Task<String?, Never>?) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        isDisconnected = true
        isFinalizing = true
        return (transcriptionTask, finalTranscriptionTask)
    }

    private func startTranscriptionLoop() {
        transcriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(
                        (self?.config.transcribeIntervalSeconds ?? 1.0) * 1_000_000_000
                    ))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.runTranscriptionPass()
            }
        }
    }

    private func freezeLiveTranscription() -> (
        canOverlapFinal: Bool,
        livePassInFlight: Bool,
        liveManagerCallInFlight: Bool
    ) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        isFinalizing = true
        let seek = VoiceInkFluidAudioTranscriptionPolicy.seekSample(
            hypothesisStartTime: agreementEngine.hypothesisStartTime,
            confirmedEndTime: agreementEngine.confirmedEndTime,
            sampleRate: sampleRate
        )
        let relativeSeek = VoiceInkFluidAudioTranscriptionPolicy.bufferRelativeSeek(
            seekSample: seek, trimmedSampleCount: trimmedSampleCount
        )
        // Long chunks share SDK progress sessions; keep those calls sequential.
        return (
            canOverlapFinal: inFlightSampleCount <= ASRConstants.maxModelSamples &&
                audioBuffer.count - relativeSeek <= ASRConstants.maxModelSamples,
            livePassInFlight: isTranscribing,
            liveManagerCallInFlight: isLiveManagerCallInFlight
        )
    }

    private func beginLivePass() -> (samples: [Float], absoluteCount: Int, seek: Int)? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard !isFinalizing, !isTranscribing, !Task.isCancelled else { return nil }
        let absoluteCount = trimmedSampleCount + audioBuffer.count
        guard VoiceInkFluidAudioTranscriptionPolicy.shouldRunTranscriptionPass(
            absoluteSampleCount: absoluteCount,
            lastTranscribedSampleCount: lastTranscribedSampleCount,
            minimumAudioSamples: minimumAudioSamples,
            minimumNewSamples: minNewSamples
        ) else { return nil }
        let seek = VoiceInkFluidAudioTranscriptionPolicy.seekSample(
            hypothesisStartTime: agreementEngine.hypothesisStartTime,
            confirmedEndTime: agreementEngine.confirmedEndTime,
            sampleRate: sampleRate
        )
        let relativeSeek = VoiceInkFluidAudioTranscriptionPolicy.bufferRelativeSeek(
            seekSample: seek, trimmedSampleCount: trimmedSampleCount
        )
        guard relativeSeek < audioBuffer.count else { return nil }
        let samples = VoiceInkFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(
            Array(audioBuffer[relativeSeek...])
        )
        guard samples.count >= minimumAudioSamples else { return nil }
        isTranscribing = true
        inFlightSampleCount = samples.count
        return (samples, absoluteCount, seek)
    }

    private func endLivePass() {
        bufferLock.lock()
        isTranscribing = false
        inFlightSampleCount = 0
        bufferLock.unlock()
    }

    private func setLiveManagerCallInFlight(_ inFlight: Bool) {
        bufferLock.lock()
        isLiveManagerCallInFlight = inFlight
        bufferLock.unlock()
    }

    private func liveManagerCallInFlight() -> Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return isLiveManagerCallInFlight
    }

    private func transcribe(
        _ samples: [Float], manager: AsrManager, state: inout TdtDecoderState
    ) async throws -> ASRResult {
        #if DEBUG
        if let transcribeForTesting {
            return try await transcribeForTesting(samples)
        }
        #endif
        return try await manager.transcribe(samples, decoderState: &state, language: languageHint)
    }

    private func runTranscriptionPass() async {
        guard let asrManager, let pass = beginLivePass() else { return }
        defer { endLivePass() }
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let inferenceSpan = latencyTrace.begin(
            "fluid_streaming.live_transcribe_await",
            details: "samples=\(pass.samples.count) absoluteSamples=\(pass.absoluteCount) cancellationRequested=\(Task.isCancelled)",
            token: traceToken
        )
        do {
            setLiveManagerCallInFlight(true)
            let result = try await transcribe(pass.samples, manager: asrManager, state: &state)
            setLiveManagerCallInFlight(false)
            latencyTrace.end(
                inferenceSpan,
                details: "result=success cancellationRequested=\(Task.isCancelled)"
            )
            applyLiveResult(result, absoluteSampleCount: pass.absoluteCount, seekSample: pass.seek)
        } catch {
            setLiveManagerCallInFlight(false)
            latencyTrace.end(
                inferenceSpan,
                details: "result=failure cancellationRequested=\(Task.isCancelled)"
            )
            guard !Task.isCancelled else { return }
            logger.error("Transcription pass failed: \(error.localizedDescription, privacy: .public)")
            eventsContinuation?.yield(.error(error))
        }
    }

    private func applyLiveResult(_ result: ASRResult, absoluteSampleCount: Int, seekSample: Int) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        // Freezing and applying share this lock: a late cancelled result cannot trim final audio.
        guard !isFinalizing, !Task.isCancelled else { return }
        lastTranscribedSampleCount = absoluteSampleCount
        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            let text = TextNormalizer.shared.normalizeSentence(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if !text.isEmpty {
                latestHypothesisText = text
                latestHypothesisSampleCount = absoluteSampleCount
                eventsContinuation?.yield(.partial(text: text))
            }
            return
        }
        let timeOffset = Double(seekSample) / sampleRate
        let words = WordAgreementEngine.mergeTokensToWords(tokenTimings, timeOffset: timeOffset)
        guard !words.isEmpty else { return }
        let agreementResult = agreementEngine.processTranscriptionResult(words: words, resultConfidence: result.confidence)
        latestHypothesisText = TextNormalizer.shared.normalizeSentence(agreementResult.hypothesisText)
        latestHypothesisSampleCount = absoluteSampleCount
        if !agreementResult.newlyConfirmedText.isEmpty {
            let text = TextNormalizer.shared.normalizeSentence(agreementResult.newlyConfirmedText)
            eventsContinuation?.yield(.committed(text: text))
        }
        if !agreementResult.fullText.isEmpty {
            eventsContinuation?.yield(.partial(text: agreementResult.fullText))
        }
        let newHypothesisStartTime = agreementEngine.hypothesisStartTime
        if newHypothesisStartTime > 0 {
            let safeTrimPoint = max(0, Int(newHypothesisStartTime * sampleRate))
            let samplesToTrim = safeTrimPoint - trimmedSampleCount
            if samplesToTrim > 0 {
                let actualTrim = min(samplesToTrim, audioBuffer.count)
                audioBuffer.removeFirst(actualTrim)
                trimmedSampleCount += actualTrim
            }
        }
    }

    private func finalAudioSnapshot() -> (samples: [Float], seek: Int, trimmed: Int)? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let seekSample = VoiceInkFluidAudioTranscriptionPolicy.seekSample(
            hypothesisStartTime: agreementEngine.hypothesisStartTime,
            confirmedEndTime: agreementEngine.confirmedEndTime,
            sampleRate: sampleRate
        )

        let bufferRelativeSeek = VoiceInkFluidAudioTranscriptionPolicy.bufferRelativeSeek(
            seekSample: seekSample,
            trimmedSampleCount: trimmedSampleCount
        )
        guard bufferRelativeSeek < audioBuffer.count else {
            return nil
        }
        return (Array(audioBuffer[bufferRelativeSeek...]), bufferRelativeSeek, trimmedSampleCount)
    }

    // Final transcription of audio after the last confirmed word.
    private func transcribeRemainingAudio() async -> String? {
        guard let asrManager, let snapshot = finalAudioSnapshot() else { return nil }
        var samples = snapshot.samples

        VoiceInkLatencyTrace.shared.event(
            "fluid_streaming.final_audio",
            details: "samples=\(samples.count) seek=\(snapshot.seek) trimmed=\(snapshot.trimmed)",
            token: latencyTraceToken
        )

        guard samples.count >= minimumAudioSamples else { return nil }

        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        let rawSampleCount = samples.count
        let paddingSpan = latencyTrace.begin("fluid_streaming.final_padding", token: traceToken)
        samples = VoiceInkFluidAudioTranscriptionPolicy.paddedSamplesForTranscription(samples)
        latencyTrace.end(
            paddingSpan,
            details: "rawSamples=\(rawSampleCount) paddedSamples=\(samples.count)"
        )

        let stateSpan = latencyTrace.begin("fluid_streaming.final_decoder_state", token: traceToken)
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        latencyTrace.end(stateSpan, details: "layers=\(decoderLayerCount)")

        let inferenceSpan = latencyTrace.begin(
            "fluid_streaming.final_transcribe_await",
            details: "samples=\(samples.count) singleChunk=\(samples.count <= ASRConstants.maxModelSamples) priority=\(Task.currentPriority.rawValue) liveManagerCallInFlightAtFinalStart=\(liveManagerCallInFlight())",
            token: traceToken
        )
        do {
            let result = try await transcribe(samples, manager: asrManager, state: &state)
            // Single-chunk SDK timing ends before result formatting; this await also includes scheduling.
            latencyTrace.end(
                inferenceSpan,
                details: "result=success cancellationRequested=\(Task.isCancelled) sdkProcessingMs=\(result.processingTime * 1_000) sdkAudioSeconds=\(result.duration) tokens=\(result.tokenTimings?.count ?? 0)"
            )

            let normalizationSpan = latencyTrace.begin("fluid_streaming.final_normalization", token: traceToken)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                latencyTrace.end(normalizationSpan, details: "result=empty")
                return nil
            }
            let normalizer = TextNormalizer.shared
            let normalized = normalizer.normalizeSentence(text)
            latencyTrace.end(
                normalizationSpan,
                details: "result=success nativeITN=\(normalizer.isNativeAvailable) chars=\(normalized.count)"
            )
            return normalized
        } catch {
            latencyTrace.end(
                inferenceSpan,
                details: "result=failure cancellationRequested=\(Task.isCancelled)"
            )
            logger.error("Final transcription failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func completeHypothesisCommitPlan() -> VoiceInkFluidAudioCompleteHypothesisCommitPlan {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let absoluteSampleCount = trimmedSampleCount + audioBuffer.count

        return VoiceInkFluidAudioTranscriptionPolicy.completeHypothesisCommitPlan(
            latestHypothesisText: latestHypothesisText,
            latestHypothesisSampleCount: latestHypothesisSampleCount,
            absoluteSampleCount: absoluteSampleCount
        )
    }

}

#if os(macOS)
extension FluidAudioStreamingProvider: StreamingTranscriptionProvider {
    func connect(model: any TranscriptionModel, language: String?) async throws {
        try await connect(modelName: model.name, language: language)
    }
}
#endif
