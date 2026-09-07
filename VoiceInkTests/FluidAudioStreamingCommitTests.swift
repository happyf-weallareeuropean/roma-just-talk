import FluidAudio
import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

@Suite(.serialized)
struct FluidAudioStreamingCommitTests {
    @Test(arguments: [18_000, 240_000])
    func finalPassOverlapsCancelledLivePassWithoutPublishingItsLateResult(finalSamples: Int) async throws {
        let control = StreamingInferenceControl()
        let provider = makeProvider(control)
        let events = collectEvents(provider)
        try await provider.sendAudioChunk(audio(samples: 16_000))
        #expect(await control.waitForCalls(1))
        try await provider.sendAudioChunk(audio(samples: finalSamples - 16_000))
        let completion = StreamingCompletion()
        let commit = Task {
            try await provider.commit()
            await completion.finish()
        }
        let overlapped = await control.waitForCalls(2)
        #expect(overlapped)
        #expect(await completion.finished == false)
        await control.releaseLive()
        try await commit.value
        await provider.disconnect()
        let result = await events.value
        #expect(result == [TextNormalizer.shared.normalizeSentence("final words")])
        let paddedFinalSamples = finalSamples == 240_000 ? finalSamples : finalSamples + 16_000
        #expect(await control.sampleCounts == [32_000, paddedFinalSamples])
    }

    @Test
    func longFinalAudioKeepsSDKProgressSessionsSequential() async throws {
        let control = StreamingInferenceControl()
        let provider = makeProvider(control)
        let events = collectEvents(provider)
        try await provider.sendAudioChunk(audio(samples: 16_000))
        #expect(await control.waitForCalls(1))
        try await provider.sendAudioChunk(audio(samples: 224_001))
        let commit = Task { try await provider.commit() }
        #expect(await control.waitForCalls(2, seconds: 0.1) == false)
        await control.releaseLive()
        try await commit.value
        await provider.disconnect()
        #expect(await control.sampleCounts == [32_000, 240_001])
        #expect(await control.finalStartedBeforeLiveFinished == false)
        #expect(await events.value == [TextNormalizer.shared.normalizeSentence("final words")])
    }

    @Test
    func disconnectDrainsBothPredictionsAndPreventsFinalPublication() async throws {
        let control = StreamingInferenceControl(blockFinal: true)
        let provider = makeProvider(control)
        let events = collectEvents(provider)
        try await provider.sendAudioChunk(audio(samples: 16_000))
        #expect(await control.waitForCalls(1))
        try await provider.sendAudioChunk(audio(samples: 2_000))
        let commit = Task { try await provider.commit() }
        #expect(await control.waitForCalls(2))
        let disconnect = Task {
            await provider.disconnect()
        }
        #expect(await control.waitForCancellations(2))
        #expect(control.state.cleanupActiveCounts.isEmpty)
        await control.releaseLive()
        #expect(await control.waitForActiveCalls(1))
        #expect(control.state.cleanupActiveCounts.isEmpty)
        await control.releaseFinal()
        await disconnect.value
        #expect(control.state.cleanupActiveCounts == [0])
        do {
            try await commit.value
            Issue.record("Disconnected commit unexpectedly succeeded")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await events.value.isEmpty)
    }

    private func makeProvider(_ control: StreamingInferenceControl) -> FluidAudioStreamingProvider {
        FluidAudioStreamingProvider(
            config: AgreementConfig(transcribeIntervalSeconds: 0.001),
            beforeDisconnectCleanupForTesting: { control.state.recordCleanup() }
        ) {
            try await control.transcribe($0)
        }
    }

    private func audio(samples: Int) -> Data {
        Data(repeating: 1, count: samples * 2)
    }

    private func collectEvents(_ provider: FluidAudioStreamingProvider) -> Task<[String], Never> {
        Task {
            var texts: [String] = []
            for await event in provider.transcriptionEvents {
                switch event {
                case .partial(let text), .committed(let text): texts.append(text)
                case .error: texts.append("unexpected error")
                case .sessionStarted: break
                }
            }
            return texts
        }
    }
}

private actor StreamingCompletion {
    private(set) var finished = false
    func finish() { finished = true }
}

private actor StreamingInferenceControl {
    nonisolated let state = StreamingInferenceState()
    private(set) var sampleCounts: [Int] = []
    private let blockFinal: Bool
    private var liveContinuation: CheckedContinuation<Void, Never>?
    private var finalContinuation: CheckedContinuation<Void, Never>?
    private var liveFinished = false
    private(set) var finalStartedBeforeLiveFinished = false

    init(blockFinal: Bool = false) { self.blockFinal = blockFinal }

    func transcribe(_ samples: [Float]) async throws -> ASRResult {
        state.begin()
        defer { state.end() }
        sampleCounts.append(samples.count)
        let isLive = sampleCounts.count == 1
        // Model a prediction that finishes after cancellation; cancellation does not release this latch.
        await withTaskCancellationHandler {
            if isLive {
                await withCheckedContinuation { liveContinuation = $0 }
                liveFinished = true
            } else {
                finalStartedBeforeLiveFinished = !liveFinished
                if blockFinal {
                    await withCheckedContinuation { finalContinuation = $0 }
                }
            }
        } onCancel: {
            state.cancel()
        }
        return ASRResult(text: isLive ? "stale live words" : "final words", confidence: 1,
                         duration: Double(samples.count) / 16_000, processingTime: 0)
    }

    func releaseLive() { liveContinuation?.resume(); liveContinuation = nil }
    func releaseFinal() { finalContinuation?.resume(); finalContinuation = nil }

    func waitForCalls(_ count: Int, seconds: Double = 1) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while sampleCounts.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return sampleCounts.count >= count
    }

    func waitForCancellations(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while state.cancellations < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return state.cancellations >= count
    }

    func waitForActiveCalls(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while state.active != count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return state.active == count
    }
}

private final class StreamingInferenceState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var cancellationCount = 0
    private var cleanupCounts: [Int] = []

    var active: Int { lock.withLock { activeCount } }
    var cancellations: Int { lock.withLock { cancellationCount } }
    var cleanupActiveCounts: [Int] { lock.withLock { cleanupCounts } }
    func begin() { lock.withLock { activeCount += 1 } }
    func end() { lock.withLock { activeCount -= 1 } }
    func cancel() { lock.withLock { cancellationCount += 1 } }
    func recordCleanup() { lock.withLock { cleanupCounts.append(activeCount) } }
}
