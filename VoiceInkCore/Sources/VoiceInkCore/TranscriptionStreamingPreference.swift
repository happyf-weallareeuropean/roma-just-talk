import Foundation

public enum VoiceInkStreamingTranscriptionEvent {
    case sessionStarted
    case partial(text: String)
    case committed(text: String)
    case error(Error)
}

public enum VoiceInkStreamingTranscriptAssembly {
    public static func committedText(_ committedSegments: [String]) -> String {
        committedSegments.joined(separator: " ")
    }

    public static func previewText(committedSegments: [String], partialText: String) -> String {
        let prefix = committedText(committedSegments)
        guard !prefix.isEmpty else {
            return partialText
        }
        if partialText.hasPrefix(prefix) || partialText.hasPrefix(prefix + " ") {
            return partialText
        }
        return prefix + " " + partialText
    }
}

public struct VoiceInkStreamingTranscriptAccumulator {
    public private(set) var committedSegments: [String] = []

    public init() {}

    public mutating func appendCommitted(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        committedSegments.append(trimmed)
        return true
    }

    public func preview(partialText: String) -> String {
        VoiceInkStreamingTranscriptAssembly.previewText(
            committedSegments: committedSegments,
            partialText: partialText
        )
    }

    public var committedText: String {
        VoiceInkStreamingTranscriptAssembly.committedText(committedSegments)
    }

    public mutating func reset() {
        committedSegments.removeAll()
    }
}

public struct VoiceInkLiveTranscriptionRequest: Equatable, Sendable {
    public let provider: VoiceInkProviderKind
    public let selectedModel: String
    public let connectionModel: String
    public let isStreamingOnly: Bool

    public init(
        provider: VoiceInkProviderKind,
        selectedModel: String,
        connectionModel: String,
        isStreamingOnly: Bool = false
    ) {
        self.provider = provider
        self.selectedModel = selectedModel
        self.connectionModel = connectionModel
        self.isStreamingOnly = isStreamingOnly
    }

    public var finalCommitTimeoutNanoseconds: UInt64 {
        VoiceInkStreamingFinalCommitTimeout.nanoseconds(
            for: provider == .localFluidAudio ? .localFluidAudio : .cloud
        )
    }
}

public enum VoiceInkLiveTranscriptionPolicy {
    public static func capability(
        for configuration: VoiceInkModeRuntimeConfiguration
    ) -> VoiceInkLiveTranscriptionRequest? {
        if configuration.transcriptionProvider == .localFluidAudio,
           let model = VoiceInkTranscriptionModelCatalog.fluidAudioModels.first(where: {
               $0.name == configuration.transcriptionModel
           }),
           model.supportsStreaming {
            return VoiceInkLiveTranscriptionRequest(
                provider: .localFluidAudio,
                selectedModel: model.name,
                connectionModel: model.name
            )
        }

        guard let modelProvider = configuration.transcriptionProvider.transcriptionModelProvider,
              modelProvider != .local,
              let model = VoiceInkTranscriptionModelCatalog.cloudModels(for: modelProvider)
                .first(where: { $0.name == configuration.transcriptionModel })
        else { return nil }

        guard model.supportsStreaming else { return nil }

        return VoiceInkLiveTranscriptionRequest(
            provider: configuration.transcriptionProvider,
            selectedModel: model.name,
            connectionModel: modelProvider.streamingConnectionModelName(
                for: model.name
            ),
            isStreamingOnly: modelProvider.isStreamingOnly
        )
    }

    public static func request(
        for configuration: VoiceInkModeRuntimeConfiguration,
        defaults: UserDefaults = .standard
    ) -> VoiceInkLiveTranscriptionRequest? {
        guard let request = capability(for: configuration) else { return nil }
        let snapshot = VoiceInkTranscriptionStreamingModelSnapshot(
            name: request.selectedModel,
            supportsStreaming: true,
            isStreamingOnly: request.isStreamingOnly
        )
        return VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
            for: snapshot,
            in: defaults
        ) ? request : nil
    }
}

public enum VoiceInkStreamingFallbackPolicy {
    @MainActor
    public static func run<Result>(
        streamingFailed: Bool,
        streaming: @MainActor () async throws -> Result,
        onStreamingFailure: @MainActor (Error) async -> Void = { _ in },
        cancelStreaming: @MainActor () async -> Void,
        prepareFallback: @MainActor () async throws -> Void = {},
        fallback: @MainActor () async throws -> Result
    ) async throws -> Result {
        if !streamingFailed {
            do {
                return try await streaming()
            } catch {
                await onStreamingFailure(error)
                await cancelStreaming()
            }
        } else {
            await cancelStreaming()
        }

        try await prepareFallback()
        return try await fallback()
    }
}

public enum VoiceInkStreamingTranscriptionError: LocalizedError, Equatable, Sendable {
    public static let unknownServerErrorMessage = "Unknown error"

    case missingAPIKey
    case connectionFailed(String)
    case timeout
    case serverError(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured for streaming transcription"
        case .connectionFailed(let message):
            return "Streaming connection failed: \(message)"
        case .timeout:
            return "Streaming transcription timed out waiting for final result"
        case .serverError(let message):
            return "Streaming server error: \(message)"
        case .notConnected:
            return "Not connected to streaming transcription service"
        }
    }
}

public struct VoiceInkTranscriptionStreamingModelSnapshot: Equatable, Sendable {
    public let name: String
    public let supportsStreaming: Bool
    public let isStreamingOnly: Bool

    public init(
        name: String,
        supportsStreaming: Bool,
        isStreamingOnly: Bool = false
    ) {
        self.name = name
        self.supportsStreaming = supportsStreaming
        self.isStreamingOnly = isStreamingOnly
    }
}

public struct VoiceInkTranscriptionStreamingModePresentation: Equatable, Sendable {
    public let streamingToggleTitle: String
    public let isStreamingToggleForcedOn: Bool
    public let isStreamingToggleDisabled: Bool
    public let streamingToggleHelp: String
    public init(
        isStreamingEnabled: Bool,
        isStreamingOnly: Bool
    ) {
        self.streamingToggleTitle = "Streaming"
        self.isStreamingToggleForcedOn = isStreamingOnly
        self.isStreamingToggleDisabled = isStreamingOnly
        if isStreamingOnly {
            self.streamingToggleHelp = "This model only supports active-recording streaming"
        } else if isStreamingEnabled {
            self.streamingToggleHelp = "Streams active-recording audio; click to use saved-file batch mode"
        } else {
            self.streamingToggleHelp = "Saved-file batch mode; click to stream active-recording audio"
        }
    }
}

public enum VoiceInkStreamingFinalCommitSource: Equatable, Sendable {
    case cloud
    case localFluidAudio
    case localQwen
}

public struct TimedWord: Equatable, Sendable {
    public let text: String
    public let normalizedText: String
    public let startTime: Double
    public let endTime: Double
    public let confidence: Float

    public init(text: String, startTime: Double, endTime: Double, confidence: Float = 1.0) {
        self.text = text
        self.normalizedText = Self.normalize(text)
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    private static func normalize(_ text: String) -> String {
        String(text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AgreementConfig: Equatable, Sendable {
    public var transcribeIntervalSeconds: Double
    public var tokenConfirmationsNeeded: Int
    public var minWordsToConfirm: Int
    public var minPassConfidence: Float
    public var minWordConfidence: Float

    public init(
        transcribeIntervalSeconds: Double = 1.0,
        tokenConfirmationsNeeded: Int = 3,
        minWordsToConfirm: Int = 5,
        minPassConfidence: Float = 0.15,
        minWordConfidence: Float = 0.6
    ) {
        self.transcribeIntervalSeconds = transcribeIntervalSeconds
        self.tokenConfirmationsNeeded = tokenConfirmationsNeeded
        self.minWordsToConfirm = minWordsToConfirm
        self.minPassConfidence = minPassConfidence
        self.minWordConfidence = minWordConfidence
    }

    /// Active-recording policy: starts only after key-down, then immediately consumes pre-roll.
    public static var resolveHingeStreaming: AgreementConfig {
        AgreementConfig(
            transcribeIntervalSeconds: 0.35,
            tokenConfirmationsNeeded: 3,
            minWordsToConfirm: 5,
            minPassConfidence: 0.15,
            minWordConfidence: 0.6
        )
    }
}

public struct AgreementResult: Equatable, Sendable {
    public let fullText: String
    public let hypothesisText: String
    public let newlyConfirmedText: String
}

public struct VoiceInkFluidAudioCompleteHypothesisCommitPlan: Equatable, Sendable {
    public let reusableText: String?
    public let pendingSamples: Int

    public var requiresFinalASR: Bool {
        reusableText == nil
    }
}

public final class WordAgreementEngine {

    private let config: AgreementConfig

    private var confirmedWords: [TimedWord] = []
    private var previousWords: [TimedWord] = []
    private var consecutiveAgreementCount: Int = 0
    private var isFirstPass: Bool = true

    public private(set) var confirmedEndTime: Double = 0.0
    public private(set) var hypothesisStartTime: Double = 0.0

    public var confirmedText: String {
        confirmedWords.map(\.text).joined(separator: " ")
    }

    public init(config: AgreementConfig = AgreementConfig()) {
        self.config = config
    }

    public func reset() {
        confirmedWords = []
        previousWords = []
        consecutiveAgreementCount = 0
        isFirstPass = true
        confirmedEndTime = 0.0
        hypothesisStartTime = 0.0
    }

    public func processTranscriptionResult(words: [TimedWord], resultConfidence: Float = 1.0) -> AgreementResult {
        guard !words.isEmpty else {
            return makeResult(hypothesisWords: [], newlyConfirmedWords: [])
        }

        if isFirstPass {
            isFirstPass = false
            previousWords = words
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        if resultConfidence < config.minPassConfidence {
            consecutiveAgreementCount = 0
            previousWords = words
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let commonPrefix = findLongestCommonPrefix(current: words, previous: previousWords)
        previousWords = words

        if commonPrefix.count >= config.minWordsToConfirm {
            consecutiveAgreementCount += 1
        } else {
            consecutiveAgreementCount = 0
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        guard consecutiveAgreementCount >= config.tokenConfirmationsNeeded else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let confirmUpTo = applyPunctuationRule(words: Array(words.prefix(commonPrefix.count)))

        guard confirmUpTo > 0 else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let boundaryWords = Array(words.prefix(confirmUpTo).suffix(3))
        let minBoundaryConfidence = boundaryWords.map(\.confidence).min() ?? 1.0
        guard minBoundaryConfidence >= config.minWordConfidence else {
            return makeResult(hypothesisWords: words, newlyConfirmedWords: [])
        }

        let newlyConfirmed = Array(words.prefix(confirmUpTo))
        let hypothesis = Array(words.dropFirst(confirmUpTo))

        confirmedWords.append(contentsOf: newlyConfirmed)
        if let lastConfirmed = newlyConfirmed.last {
            confirmedEndTime = lastConfirmed.endTime
        }

        hypothesisStartTime = hypothesis.first?.startTime ?? confirmedEndTime

        consecutiveAgreementCount = hypothesis.isEmpty ? 0 : 1
        previousWords = hypothesis
        isFirstPass = hypothesis.isEmpty

        return makeResult(hypothesisWords: hypothesis, newlyConfirmedWords: newlyConfirmed)
    }

    private func findLongestCommonPrefix(current: [TimedWord], previous: [TimedWord]) -> [TimedWord] {
        let minCount = min(current.count, previous.count)
        var prefixLength = 0

        for i in 0..<minCount {
            if current[i].normalizedText == previous[i].normalizedText {
                prefixLength = i + 1
            } else {
                break
            }
        }

        return Array(current.prefix(prefixLength))
    }

    private func applyPunctuationRule(words: [TimedWord]) -> Int {
        guard !words.isEmpty else { return 0 }

        let sentenceEnders: Set<Character> = [".", "!", "?", ";"]

        var punctuationIndices: [Int] = []
        for i in 0..<words.count {
            if let lastChar = words[i].text.last, sentenceEnders.contains(lastChar) {
                punctuationIndices.append(i)
            }
        }

        guard punctuationIndices.count >= 3 else { return 0 }

        let cutIndex = punctuationIndices[punctuationIndices.count - 3]
        let confirmCount = cutIndex + 1

        guard confirmCount >= config.minWordsToConfirm else { return 0 }

        return confirmCount
    }

    private func makeResult(hypothesisWords: [TimedWord], newlyConfirmedWords: [TimedWord]) -> AgreementResult {
        let confirmedText = confirmedWords.map(\.text).joined(separator: " ")
        let hypothesisText = hypothesisWords.map(\.text).joined(separator: " ")
        let newlyConfirmedText = newlyConfirmedWords.map(\.text).joined(separator: " ")

        var fullParts: [String] = []
        if !confirmedText.isEmpty { fullParts.append(confirmedText) }
        if !hypothesisText.isEmpty { fullParts.append(hypothesisText) }

        return AgreementResult(
            fullText: fullParts.joined(separator: " "),
            hypothesisText: hypothesisText,
            newlyConfirmedText: newlyConfirmedText
        )
    }
}

public enum VoiceInkFluidAudioTranscriptionPolicy {
    public static let batchVADMinimumDurationSeconds: TimeInterval = 20
    public static let batchVADThreshold: Float = 0.7
    public static let trailingSilenceSeconds: Double = 1
    public static let maxSingleChunkSamples = 240_000

    public static var trailingSilenceSamples: Int {
        VoiceInkPCM16Audio.sampleCount(forMono16kDuration: trailingSilenceSeconds)
    }

    public static func paddedSamplesForTranscription(
        _ samples: [Float],
        trailingSilenceSamples: Int = trailingSilenceSamples,
        maxSingleChunkSamples: Int = maxSingleChunkSamples
    ) -> [Float] {
        guard trailingSilenceSamples > 0 else {
            return samples
        }

        guard samples.count + trailingSilenceSamples <= maxSingleChunkSamples else {
            return samples
        }

        return samples + [Float](repeating: 0, count: trailingSilenceSamples)
    }

    public static func shouldRunTranscriptionPass(
        absoluteSampleCount: Int,
        lastTranscribedSampleCount: Int,
        minimumAudioSamples: Int,
        minimumNewSamples: Int
    ) -> Bool {
        absoluteSampleCount - lastTranscribedSampleCount >= minimumNewSamples &&
        absoluteSampleCount >= minimumAudioSamples
    }

    public static func completeHypothesisCommitPlan(
        latestHypothesisText: String,
        latestHypothesisSampleCount: Int,
        absoluteSampleCount: Int
    ) -> VoiceInkFluidAudioCompleteHypothesisCommitPlan {
        let pendingSamples = max(0, absoluteSampleCount - latestHypothesisSampleCount)
        let text = latestHypothesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return VoiceInkFluidAudioCompleteHypothesisCommitPlan(
                reusableText: nil,
                pendingSamples: pendingSamples
            )
        }

        guard latestHypothesisSampleCount == absoluteSampleCount else {
            return VoiceInkFluidAudioCompleteHypothesisCommitPlan(
                reusableText: nil,
                pendingSamples: pendingSamples
            )
        }

        return VoiceInkFluidAudioCompleteHypothesisCommitPlan(
            reusableText: text,
            pendingSamples: pendingSamples
        )
    }

    public static func resolvedCommitText(
        finalASRText: String?,
        latestHypothesisText: String
    ) -> String {
        let finalText = finalASRText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !finalText.isEmpty {
            return finalText
        }
        return latestHypothesisText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func seekSample(
        hypothesisStartTime: Double,
        confirmedEndTime: Double,
        sampleRate: Double
    ) -> Int {
        let seekTime = hypothesisStartTime > 0 ? hypothesisStartTime : confirmedEndTime
        return max(0, Int(seekTime * sampleRate))
    }

    public static func bufferRelativeSeek(
        seekSample: Int,
        trimmedSampleCount: Int
    ) -> Int {
        max(0, seekSample - trimmedSampleCount)
    }
}

public enum VoiceInkStreamingFinalCommitTimeout {
    public static let cloudNanoseconds: UInt64 = 10_000_000_000
    public static let localFluidAudioNanoseconds: UInt64 = 1_000_000_000
    public static let localQwenNanoseconds: UInt64 = 10_000_000_000

    public static func nanoseconds(for source: VoiceInkStreamingFinalCommitSource) -> UInt64 {
        switch source {
        case .cloud:
            cloudNanoseconds
        case .localFluidAudio:
            localFluidAudioNanoseconds
        case .localQwen:
            localQwenNanoseconds
        }
    }
}

public enum VoiceInkTranscriptionStreamingPreference {
    public static let keyPrefix = "streaming-enabled-"
    public static let defaultIsEnabled = true

    public static func key(forModelName modelName: String) -> String {
        "\(keyPrefix)\(modelName)"
    }

    public static func isEnabled(
        forModelName modelName: String,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: key(forModelName: modelName)) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        forModelName modelName: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: key(forModelName: modelName))
    }

    public static func shouldUseStreaming(
        for model: VoiceInkTranscriptionStreamingModelSnapshot,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard model.supportsStreaming else { return false }
        if model.isStreamingOnly {
            return true
        }
        return isEnabled(forModelName: model.name, in: defaults)
    }
}

public enum VoiceInkStreamingKeysMigration {
    public static let didMigrateKey = "streaming-keys-migrated"
    public static let legacyParakeetStreamingEnabledKey = "parakeet-streaming-enabled"
    public static let defaultPowerModeConfigurationsKey = VoiceInkUserDefaultsKey.powerModeConfigurations
    public static let powerModeSelectedTranscriptionModelNameKey = "selectedTranscriptionModelName"

    public static let removedModelReplacements: [String: String] = [
        "stt-rt-v4": "stt-async-v4",
        "voxtral-mini-transcribe-realtime-2602": "voxtral-mini-latest",
    ]

    @discardableResult
    public static func run(
        in defaults: UserDefaults = .standard,
        powerModeConfigurationsKey: String = defaultPowerModeConfigurationsKey
    ) -> Bool {
        guard !defaults.bool(forKey: didMigrateKey) else { return false }

        migrateLegacyStreamingPreferenceKeys(in: defaults)
        migrateCurrentTranscriptionModel(in: defaults)
        migratePowerModeTranscriptionModels(in: defaults, powerModeConfigurationsKey: powerModeConfigurationsKey)

        defaults.set(true, forKey: didMigrateKey)
        return true
    }

    private static func migrateLegacyStreamingPreferenceKeys(in defaults: UserDefaults) {
        let legacyStreamingMappings: [(old: String, new: [String])] = [
            (legacyParakeetStreamingEnabledKey, [
                VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v2"),
                VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            ]),
        ]

        for mapping in legacyStreamingMappings {
            guard let value = defaults.object(forKey: mapping.old) as? Bool else { continue }
            for newKey in mapping.new {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: mapping.old)
        }
    }

    private static func migrateCurrentTranscriptionModel(in defaults: UserDefaults) {
        guard let savedModel = VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
              let replacement = removedModelReplacements[savedModel] else {
            return
        }

        VoiceInkCurrentTranscriptionModelPreference.saveModelName(replacement, to: defaults)
    }

    private static func migratePowerModeTranscriptionModels(
        in defaults: UserDefaults,
        powerModeConfigurationsKey: String
    ) {
        guard let data = defaults.data(forKey: powerModeConfigurationsKey),
              var configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return
        }

        var changed = false
        for index in configs.indices {
            guard let savedModel = configs[index][powerModeSelectedTranscriptionModelNameKey] as? String,
                  let replacement = removedModelReplacements[savedModel] else {
                continue
            }
            configs[index][powerModeSelectedTranscriptionModelNameKey] = replacement
            changed = true
        }

        if changed, let newData = try? JSONSerialization.data(withJSONObject: configs) {
            defaults.set(newData, forKey: powerModeConfigurationsKey)
        }
    }
}

public enum VoiceInkTranscriptionServiceRoute: Equatable, Sendable {
    case cloud
    case localFluidAudio
    case localQwen
    case localWhisper
    case nativeApple

    public var isCloudTranscriptionProvider: Bool {
        self == .cloud
    }

    public var isLocalTranscriptionProvider: Bool {
        !isCloudTranscriptionProvider
    }
}

public enum VoiceInkTranscriptionServiceRouteDiagnostics {
    public static func transcribingMessage(
        modelDisplayName: String,
        serviceTypeDescription: String
    ) -> String {
        "Transcribing with \(modelDisplayName) using \(serviceTypeDescription)"
    }
}

public enum VoiceInkTranscriptionStreamingAdapterKind: Equatable, Sendable {
    case cloud
    case localFluidAudio
    case localQwen
}

public struct VoiceInkTranscriptionStreamingSessionRequest: Equatable, Sendable {
    public let serviceRoute: VoiceInkTranscriptionServiceRoute
    public let adapterKind: VoiceInkTranscriptionStreamingAdapterKind
    public let finalCommitTimeoutNanoseconds: UInt64
}

fileprivate enum VoiceInkTranscriptionSessionExecutionAction: Equatable, Sendable {
    case file(serviceRoute: VoiceInkTranscriptionServiceRoute)
    case streaming(VoiceInkTranscriptionStreamingSessionRequest)
}

public struct VoiceInkTranscriptionSessionExecutionPlan: Equatable, Sendable {
    private let action: VoiceInkTranscriptionSessionExecutionAction

    fileprivate init(action: VoiceInkTranscriptionSessionExecutionAction) {
        self.action = action
    }

    public func applyRuntimeState<Result>(
        file: (VoiceInkTranscriptionServiceRoute) -> Result,
        streaming: (VoiceInkTranscriptionStreamingSessionRequest) -> Result
    ) -> Result {
        switch action {
        case .file(let serviceRoute):
            return file(serviceRoute)
        case .streaming(let request):
            return streaming(request)
        }
    }
}

public struct VoiceInkTranscriptionSessionRouteFacts: Equatable, Sendable {
    public let serviceRoute: VoiceInkTranscriptionServiceRoute
    public let streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot

    public init(
        serviceRoute: VoiceInkTranscriptionServiceRoute,
        streamingSnapshot: VoiceInkTranscriptionStreamingModelSnapshot
    ) {
        self.serviceRoute = serviceRoute
        self.streamingSnapshot = streamingSnapshot
    }

    public func plan(
        defaults: UserDefaults = .standard
    ) -> VoiceInkTranscriptionSessionRoutePlan {
        let usesStreaming = VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
            for: streamingSnapshot,
            in: defaults
        )

        return VoiceInkTranscriptionSessionRoutePlan(
            serviceRoute: serviceRoute,
            usesStreaming: usesStreaming
        )
    }
}

public struct VoiceInkTranscriptionSessionRoutePlan: Equatable, Sendable {
    public let serviceRoute: VoiceInkTranscriptionServiceRoute
    public let usesStreaming: Bool
    public let streamingAdapterKind: VoiceInkTranscriptionStreamingAdapterKind?
    public let finalCommitSource: VoiceInkStreamingFinalCommitSource?

    public init(
        serviceRoute: VoiceInkTranscriptionServiceRoute,
        usesStreaming: Bool
    ) {
        self.serviceRoute = serviceRoute
        self.usesStreaming = usesStreaming

        guard usesStreaming else {
            self.streamingAdapterKind = nil
            self.finalCommitSource = nil
            return
        }

        switch serviceRoute {
        case .localFluidAudio:
            self.streamingAdapterKind = .localFluidAudio
            self.finalCommitSource = .localFluidAudio
        case .localQwen:
            self.streamingAdapterKind = .localQwen
            self.finalCommitSource = .localQwen
        case .cloud, .localWhisper, .nativeApple:
            self.streamingAdapterKind = .cloud
            self.finalCommitSource = .cloud
        }
    }

    public var finalCommitTimeoutNanoseconds: UInt64? {
        finalCommitSource.map(VoiceInkStreamingFinalCommitTimeout.nanoseconds(for:))
    }

    public var executionPlan: VoiceInkTranscriptionSessionExecutionPlan {
        guard usesStreaming else {
            return VoiceInkTranscriptionSessionExecutionPlan(
                action: .file(serviceRoute: serviceRoute)
            )
        }

        guard let streamingAdapterKind,
              let finalCommitTimeoutNanoseconds else {
            preconditionFailure("Streaming route plan missing streaming adapter details.")
        }

        return VoiceInkTranscriptionSessionExecutionPlan(
            action: .streaming(
                VoiceInkTranscriptionStreamingSessionRequest(
                    serviceRoute: serviceRoute,
                    adapterKind: streamingAdapterKind,
                    finalCommitTimeoutNanoseconds: finalCommitTimeoutNanoseconds
                )
            )
        )
    }
}
