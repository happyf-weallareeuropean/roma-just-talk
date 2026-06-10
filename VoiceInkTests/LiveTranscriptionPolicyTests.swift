import Foundation
import Testing
@testable import VoiceInk

private struct TestTranscriptionModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let isMultilingualModel = false
    let supportedLanguages = ["en": "English"]
    let supportsStreaming: Bool
}

private final class ScriptedSpeechDetector: SpeechActivityDetecting, @unchecked Sendable {
    private var results: [Bool]
    private(set) var checkedChunks: [Data] = []

    init(_ results: [Bool]) {
        self.results = results
    }

    func containsSpeech(inPCM16LEData data: Data) -> Bool {
        checkedChunks.append(data)
        return results.isEmpty ? false : results.removeFirst()
    }
}

struct LiveTranscriptionPolicyTests {
    @Test func defaultsUseAutoWithCloudRuleOffAndLowBatteryRuleOnAtFortyPercent() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }

        let configuration = LiveTranscriptionSettings.configuration(in: defaults)

        #expect(configuration.mode == .auto)
        #expect(configuration.autoDisablesCloudModels == false)
        #expect(configuration.autoDisablesLowBatteryLocalModels == true)
        #expect(configuration.lowBatteryThresholdPercent == 40)
    }

    @Test func autoDisablesLocalStreamingBelowBatteryThresholdOnly() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let model = streamingModel(provider: .fluidAudio)

        defaults.set(LiveTranscriptionMode.auto.rawValue, forKey: LiveTranscriptionSettings.modeKey)
        defaults.set(true, forKey: LiveTranscriptionSettings.autoDisableLowBatteryLocalModelsKey)
        defaults.set(40, forKey: LiveTranscriptionSettings.lowBatteryThresholdPercentKey)

        #expect(!LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 39))
            .allowsStreaming(for: model, isStreamingOnly: false, perModelEnabled: true))
        #expect(LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 40))
            .allowsStreaming(for: model, isStreamingOnly: false, perModelEnabled: true))
        #expect(LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: 10))
            .allowsStreaming(for: model, isStreamingOnly: false, perModelEnabled: true))
    }

    @Test func autoCloudRuleIsOptIn() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let model = streamingModel(provider: .deepgram)

        defaults.set(LiveTranscriptionMode.auto.rawValue, forKey: LiveTranscriptionSettings.modeKey)
        defaults.set(false, forKey: LiveTranscriptionSettings.autoDisableCloudModelsKey)

        #expect(LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 20))
            .allowsStreaming(for: model, isStreamingOnly: false, perModelEnabled: true))

        defaults.set(true, forKey: LiveTranscriptionSettings.autoDisableCloudModelsKey)

        #expect(!LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: nil))
            .allowsStreaming(for: model, isStreamingOnly: false, perModelEnabled: true))
    }

    @Test func manualModeStillHonorsPerModelOptOutAndStreamingCapability() {
        let defaults = temporaryDefaults()
        defer { removeTemporaryDefaults(defaults) }
        let streaming = streamingModel(provider: .fluidAudio)
        let batchOnly = TestTranscriptionModel(
            name: "batch-only",
            displayName: "Batch Only",
            description: "No streaming",
            provider: .whisper,
            supportsStreaming: false
        )

        defaults.set(LiveTranscriptionMode.on.rawValue, forKey: LiveTranscriptionSettings.modeKey)

        let policy = LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: true, batteryLevelPercent: 1))
        #expect(policy.allowsStreaming(for: streaming, isStreamingOnly: false, perModelEnabled: true))
        #expect(!policy.allowsStreaming(for: streaming, isStreamingOnly: false, perModelEnabled: false))
        #expect(!policy.allowsStreaming(for: batchOnly, isStreamingOnly: false, perModelEnabled: true))

        defaults.set(LiveTranscriptionMode.off.rawValue, forKey: LiveTranscriptionSettings.modeKey)
        #expect(!LiveTranscriptionPolicy(defaults: defaults, powerState: .init(isOnBattery: false, batteryLevelPercent: nil))
            .allowsStreaming(for: streaming, isStreamingOnly: false, perModelEnabled: true))
    }

    @Test func speechGateDropsSilenceUntilSpeechThenFlushesLeadIn() {
        let chunk1 = data("silent-1")
        let chunk2 = data("silent-2")
        let chunk3 = data("silent-3")
        let speech = data("speech")
        let detector = ScriptedSpeechDetector([false, false, false, true])
        let gate = AudioChunkSpeechGate(
            detector: detector,
            leadInChunkCount: 2,
            trailingSilenceChunkCount: 1
        )

        #expect(gate.accept(chunk1).isEmpty)
        #expect(gate.accept(chunk2).isEmpty)
        #expect(gate.accept(chunk3).isEmpty)
        #expect(gate.accept(speech) == [chunk2, chunk3, speech])
        #expect(detector.checkedChunks == [chunk1, chunk2, chunk3, speech])
    }

    @Test func speechGateKeepsShortTailAfterSpeech() {
        let speech = data("speech")
        let tail = data("tail")
        let silence = data("silence")
        let detector = ScriptedSpeechDetector([true, false, false])
        let gate = AudioChunkSpeechGate(
            detector: detector,
            leadInChunkCount: 1,
            trailingSilenceChunkCount: 1
        )

        #expect(gate.accept(speech) == [speech])
        #expect(gate.accept(tail) == [tail])
        #expect(gate.accept(silence).isEmpty)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "VoiceInkTests.LiveTranscriptionPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "_temporaryDefaultsSuiteName")
        return defaults
    }

    private func removeTemporaryDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "_temporaryDefaultsSuiteName") else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func streamingModel(provider: ModelProvider) -> TestTranscriptionModel {
        TestTranscriptionModel(
            name: "\(provider.rawValue)-streaming",
            displayName: "\(provider.rawValue) Streaming",
            description: "Streaming test model",
            provider: provider,
            supportsStreaming: true
        )
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
