import Foundation

public enum VoiceInkTranscriptionModelAvailabilityRequirement: Equatable, Sendable {
    case configuredAPIKey
    case configuredAPIKeyAndCurrentOSSupport
    case currentOSSupport
    case downloadedLocalFluidAudioModel
    case downloadedLocalWhisperModel
    case alwaysAvailable
    case unavailable

    public var requiresConfiguredAPIKey: Bool {
        self == .configuredAPIKey || self == .configuredAPIKeyAndCurrentOSSupport
    }

    public var requiresCurrentOSSupport: Bool {
        self == .currentOSSupport || self == .configuredAPIKeyAndCurrentOSSupport
    }
}

public struct VoiceInkTranscriptionModelAvailabilityFacts: Equatable, Sendable {
    public let requirement: VoiceInkTranscriptionModelAvailabilityRequirement
    public let hasConfiguredAPIKey: Bool
    public let isAvailableOnCurrentOS: Bool
    public let isLocalFluidAudioModelDownloaded: Bool
    public let isLocalWhisperModelDownloaded: Bool

    public init(
        requirement: VoiceInkTranscriptionModelAvailabilityRequirement,
        hasConfiguredAPIKey: Bool = false,
        isAvailableOnCurrentOS: Bool = true,
        isLocalFluidAudioModelDownloaded: Bool = false,
        isLocalWhisperModelDownloaded: Bool = false
    ) {
        self.requirement = requirement
        self.hasConfiguredAPIKey = hasConfiguredAPIKey
        self.isAvailableOnCurrentOS = isAvailableOnCurrentOS
        self.isLocalFluidAudioModelDownloaded = isLocalFluidAudioModelDownloaded
        self.isLocalWhisperModelDownloaded = isLocalWhisperModelDownloaded
    }

    public var isUsable: Bool {
        switch requirement {
        case .configuredAPIKeyAndCurrentOSSupport:
            hasConfiguredAPIKey && isAvailableOnCurrentOS
        case .configuredAPIKey:
            hasConfiguredAPIKey
        case .currentOSSupport:
            isAvailableOnCurrentOS
        case .downloadedLocalFluidAudioModel:
            isLocalFluidAudioModelDownloaded
        case .downloadedLocalWhisperModel:
            isLocalWhisperModelDownloaded
        case .alwaysAvailable:
            true
        case .unavailable:
            false
        }
    }
}

public enum VoiceInkNativeAppleTranscriptionFailureKind: Error, LocalizedError, Equatable, Sendable {
    case unsupportedOS
    case unsupportedIOS
    case transcriptionFailed
    case localeNotSupported
    case invalidModel
    case assetDownloadRequired(displayName: String)
    case resultStreamTimedOut

    public var errorDescription: String? {
        VoiceInkNativeAppleTranscriptionPolicy.errorDescription(for: self)
    }
}

public enum VoiceInkNativeAppleTranscriptionPolicy {
    public static let minimumResultStreamTimeout: TimeInterval = 20.0
    public static let resultStreamTimeoutMultiplier = 4.0
    public static let resultStreamTimeoutPadding: TimeInterval = 10.0
    public static let unsupportedOSDiagnosticMessage = "SpeechAnalyzer is not available on this macOS version"
    public static let unsupportedIOSDiagnosticMessage = "SpeechAnalyzer is not available on this iOS version"

    public static func requiresMacOS26Title(modelDisplayName: String) -> String {
        "\(modelDisplayName) requires macOS 26 or later"
    }

    public static func errorDescription(for failure: VoiceInkNativeAppleTranscriptionFailureKind) -> String {
        switch failure {
        case .unsupportedOS:
            return "SpeechAnalyzer requires macOS 26 or later."
        case .unsupportedIOS:
            return "SpeechAnalyzer requires iOS 26 or later."
        case .transcriptionFailed:
            return "Transcription failed using SpeechAnalyzer."
        case .localeNotSupported:
            return "The selected language is not supported by SpeechAnalyzer."
        case .invalidModel:
            return "Invalid model type provided for Native Apple transcription."
        case .assetDownloadRequired(let displayName):
            return "Download required for \(displayName)."
        case .resultStreamTimedOut:
            return "Apple Speech did not finish returning transcription results."
        }
    }

    public static func resultStreamTimeout(forAudioDuration audioDuration: TimeInterval) -> TimeInterval {
        max(minimumResultStreamTimeout, audioDuration * resultStreamTimeoutMultiplier + resultStreamTimeoutPadding)
    }

    public static func unsupportedLocaleDiagnosticMessage(localeIdentifier: String) -> String {
        "Transcription failed: Locale '\(localeIdentifier)' is not supported by SpeechTranscriber."
    }

    public static func missingAssetDiagnosticMessage(localeIdentifier: String) -> String {
        "Transcription failed: Assets for '\(localeIdentifier)' are not downloaded."
    }

    public static func emptyAudioDiagnosticMessage(localeIdentifier: String) -> String {
        "Transcription failed: Apple Speech received no audio samples for '\(localeIdentifier)'."
    }

    public static func assetReservationReturnedFalseDiagnosticMessage(
        localeIdentifier: String,
        statusDescription: String
    ) -> String {
        "Apple Speech asset reservation returned false for '\(localeIdentifier)'. Continuing because the locale is already downloaded. Status: \(statusDescription)."
    }

    public static func assetReservationFailedDiagnosticMessage(
        localeIdentifier: String,
        errorDescription: String,
        statusDescription: String
    ) -> String {
        "Apple Speech asset reservation failed for '\(localeIdentifier)': \(errorDescription). Continuing because the locale is already downloaded. Status: \(statusDescription)."
    }

    public static func resultWaitFailedDiagnosticMessage(errorDescription: String) -> String {
        "Apple Speech result wait failed: \(errorDescription)."
    }
}

fileprivate enum VoiceInkTranscriptionRecordingStartupLoadAction: Equatable, Sendable {
    case none
    case loadLocalWhisperModel
    case loadLocalFluidAudioModel
}

fileprivate enum VoiceInkTranscriptionModelSelectionResourceAction: Equatable, Sendable {
    case preserveLocalWhisperModel
    case clearLocalWhisperModelAndMarkLoaded

    var localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate {
        switch self {
        case .preserveLocalWhisperModel:
            return .preserve
        case .clearLocalWhisperModelAndMarkLoaded:
            return .clearLoadedModel(isModelLoadedAfterUpdate: true)
        }
    }
}

public struct VoiceInkLocalWhisperRuntimeUpdate: Equatable, Sendable {
    private let shouldClearLoadedModel: Bool
    private let isModelLoadedAfterUpdate: Bool?

    fileprivate init(
        shouldClearLoadedModel: Bool,
        isModelLoadedAfterUpdate: Bool?
    ) {
        self.shouldClearLoadedModel = shouldClearLoadedModel
        self.isModelLoadedAfterUpdate = isModelLoadedAfterUpdate
    }

    public static let preserve = Self(
        shouldClearLoadedModel: false,
        isModelLoadedAfterUpdate: nil
    )

    public static func clearLoadedModel(isModelLoadedAfterUpdate: Bool) -> Self {
        Self(
            shouldClearLoadedModel: true,
            isModelLoadedAfterUpdate: isModelLoadedAfterUpdate
        )
    }

    public func applyRuntimeState(
        clearLoadedModel: () -> Void,
        setIsModelLoaded: (Bool) -> Void
    ) {
        if shouldClearLoadedModel {
            clearLoadedModel()
        }

        if let isModelLoadedAfterUpdate {
            setIsModelLoaded(isModelLoadedAfterUpdate)
        }
    }
}

public struct VoiceInkTranscriptionModelDeletionPlan: Equatable, Sendable {
    private let shouldClearCurrentModel: Bool
    private let localWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate

    public init(currentModelName: String?, deletedModelName: String) {
        let shouldClearCurrentModel = currentModelName == deletedModelName
        self.shouldClearCurrentModel = shouldClearCurrentModel
        self.localWhisperRuntimeUpdate = shouldClearCurrentModel
            ? .clearLoadedModel(isModelLoadedAfterUpdate: false)
            : .preserve
    }

    public func applyRuntimeState(
        clearCurrentModel: () -> Void,
        applyLocalWhisperRuntimeUpdate: (VoiceInkLocalWhisperRuntimeUpdate) -> Void
    ) {
        guard shouldClearCurrentModel else { return }

        clearCurrentModel()
        applyLocalWhisperRuntimeUpdate(localWhisperRuntimeUpdate)
    }
}

public struct VoiceInkTranscriptionRuntimeResourcePlan: Equatable, Sendable {
    public let shouldPrewarmModel: Bool
    private let recordingStartupLoadAction: VoiceInkTranscriptionRecordingStartupLoadAction
    private let modelSelectionResourceAction: VoiceInkTranscriptionModelSelectionResourceAction

    public init(serviceRoute: VoiceInkTranscriptionServiceRoute) {
        switch serviceRoute {
        case .localWhisper:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalWhisperModel
            self.modelSelectionResourceAction = .preserveLocalWhisperModel
        case .localFluidAudio:
            self.shouldPrewarmModel = true
            self.recordingStartupLoadAction = .loadLocalFluidAudioModel
            self.modelSelectionResourceAction = .clearLocalWhisperModelAndMarkLoaded
        case .cloud, .nativeApple:
            self.shouldPrewarmModel = false
            self.recordingStartupLoadAction = .none
            self.modelSelectionResourceAction = .clearLocalWhisperModelAndMarkLoaded
        }
    }

    public var modelSelectionLocalWhisperRuntimeUpdate: VoiceInkLocalWhisperRuntimeUpdate {
        modelSelectionResourceAction.localWhisperRuntimeUpdate
    }

    public func applyRecordingStartupRuntimeState(
        loadLocalWhisperModel: () async throws -> Void,
        loadLocalFluidAudioModel: () async throws -> Void
    ) async rethrows {
        switch recordingStartupLoadAction {
        case .none:
            break
        case .loadLocalWhisperModel:
            try await loadLocalWhisperModel()
        case .loadLocalFluidAudioModel:
            try await loadLocalFluidAudioModel()
        }
    }
}

public enum VoiceInkModelPrewarmSamplePolicy {
    public static let generatedSilenceSampleCount = Int(VoiceInkPCM16Audio.mono16kSampleRate)
}

public enum VoiceInkWhisperModelLoadPolicy {
    public static func shouldReuseLoadedContext(
        hasContext: Bool,
        loadedModelName: String?,
        requestedModelName: String
    ) -> Bool {
        hasContext && loadedModelName == requestedModelName
    }
}

public enum VoiceInkModelPrewarmSkipReason: Equatable, Sendable {
    case disabledByUser
    case missingCurrentModel
    case unsupportedRuntime
}

public struct VoiceInkModelPrewarmPlan: Equatable, Sendable {
    public let skipReason: VoiceInkModelPrewarmSkipReason?

    public var shouldRun: Bool {
        skipReason == nil
    }

    public var diagnosticMessage: String? {
        switch skipReason {
        case .disabledByUser:
            return VoiceInkModelPrewarmDiagnostics.disabledByUserMessage
        case .missingCurrentModel:
            return nil
        case .unsupportedRuntime:
            return VoiceInkModelPrewarmDiagnostics.unsupportedRuntimeMessage
        case .none:
            return nil
        }
    }

    public init(skipReason: VoiceInkModelPrewarmSkipReason?) {
        self.skipReason = skipReason
    }

    public static func plan(
        isEnabled: Bool,
        hasCurrentModel: Bool,
        shouldPrewarmModel: Bool
    ) -> Self {
        guard isEnabled else {
            return Self(skipReason: .disabledByUser)
        }

        guard hasCurrentModel else {
            return Self(skipReason: .missingCurrentModel)
        }

        guard shouldPrewarmModel else {
            return Self(skipReason: .unsupportedRuntime)
        }

        return Self(skipReason: nil)
    }
}

public enum VoiceInkWhisperModelWarmupPolicy {
    public static func shouldScheduleWarmup(
        supportsCoreML: Bool,
        isAlreadyWarming: Bool
    ) -> Bool {
        supportsCoreML && !isAlreadyWarming
    }
}

public enum VoiceInkModelPrewarmDiagnostics {
    public static let initializedMessage = "ModelPrewarmService initialized - listening for wake and app launch"
    public static let appLaunchScheduledMessage = "App launched, scheduling prewarm"
    public static let macActivityScheduledMessage = "Mac activity detected (wake/unlock), scheduling prewarm"
    public static let iOSActivityScheduledMessage = "iOS app became active, scheduling prewarm"
    public static let disabledByUserMessage = "Prewarm disabled by user"
    public static let unsupportedRuntimeMessage = "Skipping prewarm - cloud models don't need it"
    public static let deinitializedMessage = "ModelPrewarmService deinitialized"

    public static func prewarmingMessage(modelDisplayName: String) -> String {
        "Prewarming \(modelDisplayName)"
    }

    public static func completedMessage(duration: TimeInterval) -> String {
        "Prewarm completed in \(String(format: "%.2f", duration))s"
    }

    public static func failedMessage(errorDescription: String) -> String {
        "❌ Prewarm failed: \(errorDescription)"
    }
}

public enum VoiceInkWhisperModelWarmupDiagnostics {
    public static func failedMessage(modelName: String, errorDescription: String) -> String {
        "❌ Warmup failed for \(modelName): \(errorDescription)"
    }
}

public enum VoiceInkTranscriptionModelProvider: String, CaseIterable, Sendable {
    case groq
    case openAI
    case assemblyAI
    case cartesia
    case nvidia
    case deepgram
    case elevenLabs
    case mistral
    case gemini
    case soniox
    case speechmatics
    case xai
    case local
    case nativeApple

    public var providerKind: VoiceInkProviderKind? {
        switch self {
        case .nvidia:
            return .nvidia
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .assemblyAI:
            return .assemblyAI
        case .deepgram:
            return .deepgram
        case .elevenLabs:
            return .elevenLabs
        case .mistral:
            return .mistral
        case .gemini:
            return .gemini
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .xai:
            return .xai
        case .local:
            return .localWhisper
        case .nativeApple:
            return .nativeApple
        case .cartesia:
            return nil
        }
    }

    public var languageCodes: [String]? {
        switch self {
        case .nvidia:
            return ["zh", "en"]
        case .assemblyAI:
            return ["en", "es", "de", "fr", "pt", "it"]
        case .cartesia:
            return [
                "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
                "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
                "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
                "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
                "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
                "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
                "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
                "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
                "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
                "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh",
                "zu"
            ]
        case .xai:
            return [
                "ar", "cs", "da", "nl", "en", "fil", "fr", "de", "hi", "id",
                "it", "ja", "ko", "mk", "ms", "fa", "pl", "pt", "ro", "ru",
                "es", "sv", "th", "tr", "vi"
            ]
        case .elevenLabs:
            return [
                "af", "am", "ar", "as", "az", "be", "bg", "bn", "bs", "ca",
                "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa",
                "fi", "fil", "fr", "ga", "gl", "gu", "ha", "he", "hi", "hr",
                "hu", "hy", "id", "ig", "is", "it", "ja", "jw", "ka", "kk",
                "km", "kn", "ko", "ku", "ky", "lb", "ln", "lo", "lt", "lv",
                "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
                "no", "or", "pa", "pl", "ps", "pt", "ro", "ru", "sd", "sk",
                "sl", "sn", "so", "sr", "sv", "sw", "ta", "tg", "te", "th",
                "tr", "uk", "ur", "uz", "vi", "wo", "xh", "yo", "yue", "zh",
                "zu"
            ]
        case .speechmatics:
            return [
                "ar", "ba", "eu", "be", "bn", "bg", "yue", "ca", "hr", "cs",
                "da", "nl", "en", "et", "fi", "fr", "gl", "de", "el", "he",
                "hi", "hu", "id", "it", "ja", "ko", "lv", "lt", "ms", "mt",
                "mr", "mn", "no", "fa", "pl", "pt", "ro", "ru", "sk", "sl",
                "es", "sw", "sv", "tl", "ta", "th", "tr", "uk", "ur", "vi",
                "cy", "zh"
            ]
        case .soniox:
            return [
                "af", "sq", "ar", "az", "eu", "be", "bn", "bs", "bg", "ca",
                "zh", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "gl",
                "de", "el", "gu", "he", "hi", "hu", "id", "it", "ja", "kn",
                "kk", "ko", "lv", "lt", "mk", "ms", "ml", "mr", "no", "fa",
                "pl", "pt", "pa", "ro", "ru", "sr", "sk", "sl", "es", "sw",
                "sv", "tl", "ta", "te", "th", "tr", "uk", "ur", "vi", "cy"
            ]
        case .mistral:
            return ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
        case .deepgram:
            return [
                "ar", "be", "bg", "bn", "bs", "ca", "cs", "da", "de", "el",
                "en", "es", "et", "fa", "fi", "fr", "he", "hi", "hr", "hu",
                "id", "it", "ja", "kn", "ko", "lt", "lv", "mk", "mr", "ms",
                "nl", "no", "pl", "pt", "ro", "ru", "sk", "sl", "sr", "sv",
                "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "zh"
            ]
        case .groq, .openAI, .gemini, .local, .nativeApple:
            return nil
        }
    }

    public var includesAutoDetect: Bool {
        switch self {
        case .assemblyAI, .deepgram, .elevenLabs, .mistral, .soniox, .speechmatics, .xai:
            return true
        case .cartesia, .nvidia, .groq, .openAI, .gemini, .local, .nativeApple:
            return false
        }
    }

    public var supportsRecordedFileTranscription: Bool {
        switch self {
        case .cartesia:
            return false
        case .assemblyAI, .deepgram, .elevenLabs, .mistral, .soniox, .speechmatics, .xai, .groq, .openAI, .gemini, .nvidia, .local, .nativeApple:
            return true
        }
    }

    public var isStreamingOnly: Bool {
        !supportsRecordedFileTranscription
    }

    public var apiErrorDomain: String? {
        switch self {
        case .nvidia:
            return "NVIDIAAPI"
        case .groq:
            return "GroqAPI"
        case .deepgram:
            return "DeepgramAPI"
        case .gemini:
            return "GeminiAPI"
        case .mistral:
            return "MistralAPI"
        case .elevenLabs:
            return "ElevenLabsAPI"
        case .soniox:
            return "SonioxAPI"
        case .speechmatics:
            return "SpeechmaticsAPI"
        case .assemblyAI:
            return "AssemblyAIAPI"
        case .xai:
            return "XAIAPI"
        case .openAI, .cartesia, .local, .nativeApple:
            return nil
        }
    }

    public var requiredAPIErrorDomain: String {
        guard let apiErrorDomain else {
            preconditionFailure("\(rawValue) provider metadata must define an API error domain")
        }
        return apiErrorDomain
    }

    public func streamingConnectionModelName(for selectedModelName: String) -> String {
        switch self {
        case .elevenLabs:
            return "scribe_v2_realtime"
        case .soniox:
            return "stt-rt-v4"
        case .speechmatics:
            return selectedModelName.contains("standard") ? "standard" : "enhanced"
        case .mistral:
            return "voxtral-mini-transcribe-realtime-2602"
        case .assemblyAI, .cartesia, .deepgram, .gemini, .groq, .openAI, .xai, .nvidia, .local, .nativeApple:
            return selectedModelName
        }
    }

    public var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        switch self {
        case .assemblyAI:
            return true
        case .cartesia, .deepgram, .elevenLabs, .gemini, .groq, .mistral, .openAI, .soniox, .speechmatics, .xai, .nvidia, .local, .nativeApple:
            return false
        }
    }
}

public enum VoiceInkModelManagementFilter: String, CaseIterable, Identifiable, Sendable {
    case recommended = "Recommended"
    case local = "Local"
    case cloud = "Cloud"
    case custom = "Custom"

    public var id: String { rawValue }
    public var title: String { rawValue }
    public var settingsSectionTitle: String { "\(title) Models" }
    public var manageSettingsTitle: String { "Manage \(settingsSectionTitle)" }

    private static let recommendedModelNames = [
        "ggml-base.en",
        VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
        "ggml-large-v3-turbo-q5_0",
        "whisper-large-v3-turbo"
    ]

    private func includes(_ facts: VoiceInkModelManagementModelFacts) -> Bool {
        switch self {
        case .recommended:
            return Self.recommendedModelNames.contains(facts.name)
        case .local:
            return facts.category == .local && facts.isAvailableOnCurrentOS
        case .cloud:
            return facts.category == .cloud
        case .custom:
            return facts.category == .custom
        }
    }

    private func sortRank(forModelName name: String) -> Int {
        Self.recommendedModelNames.firstIndex(of: name) ?? Int.max
    }

    public func filteredModels<Model>(
        _ models: [Model],
        facts: (Model) -> VoiceInkModelManagementModelFacts
    ) -> [Model] {
        let includedModels = models.filter { includes(facts($0)) }

        guard self == .recommended else {
            return includedModels
        }

        return includedModels.sorted {
            sortRank(forModelName: facts($0).name) < sortRank(forModelName: facts($1).name)
        }
    }
}

public enum VoiceInkModelManagementModelCategory: Equatable, Sendable {
    case local
    case cloud
    case custom
}

public struct VoiceInkModelManagementModelFacts: Equatable, Sendable {
    public var name: String
    public var category: VoiceInkModelManagementModelCategory
    public var isAvailableOnCurrentOS: Bool

    public init(
        name: String,
        category: VoiceInkModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool
    ) {
        self.name = name
        self.category = category
        self.isAvailableOnCurrentOS = isAvailableOnCurrentOS
    }
}

public enum VoiceInkModelManagementPresentation {
    public static let settingsTitle = "Model Settings"
    public static let defaultModelTitle = "Default Model"
    public static let setAsDefaultButtonTitle = "Set as Default"
    public static let downloadButtonTitle = "Download"
    public static let editModelButtonTitle = "Edit Model"
    public static let deleteModelButtonTitle = "Delete Model"
    public static let deleteButtonTitle = "Delete"
    public static let deleteCustomModelAlertTitle = "Delete Custom Model"
    public static let showInFinderButtonTitle = "Show in Finder"
    public static let speedLabel = "Speed"
    public static let accuracyLabel = "Accuracy"
    public static let multilingualLanguageLabel = "Multilingual"
    public static let englishOnlyLanguageLabel = "English-only"
    public static let importedLocalModelDescription = "Imported local model"
    public static let customProviderLabel = "Custom Provider"
    public static let openAICompatibleLabel = "OpenAI Compatible"
    public static let nativeAppleProviderLabel = "Native Apple"
    public static let onDeviceLabel = "On-Device"
    public static let macOS26RequiredLabel = "macOS 26+"
    public static let noModelSelectedText = "No model selected"
    public static let importLocalModelTitle = "Import Local Model…"
    public static let importLocalModelHelpText = "Add a custom fine-tuned whisper model to use with VoiceInk. Select the downloaded .bin file."
    public static let importLocalModelLearnMoreURLString = "https://tryvoiceink.com/docs/custom-local-whisper-models"
    public static let importLocalModelLearnMoreHelpText = "Read more about custom local models"
    public static let importLocalModelPanelTitle = "Select a Whisper ggml .bin model"
    public static let customModelsLimitationText = "Only OpenAI-compatible transcription APIs are supported."
    public static let intelMacLocalModelsWarningText = "Local models don't work reliably on Intel Macs"
    public static let intelMacUseCloudButtonTitle = "Use Cloud"
    public static let closeButtonHelp = "Close"

    public static func deleteCustomModelAlertMessage(displayName: String) -> String {
        "Are you sure you want to delete the custom model '\(displayName)'?"
    }

    public static func deleteModelAlertMessage(modelName: String) -> String {
        "Are you sure you want to delete the model '\(modelName)'?"
    }

    public static func languageLabel(isMultilingual: Bool) -> String {
        isMultilingual ? multilingualLanguageLabel : englishOnlyLanguageLabel
    }

    public static func scoreText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    public static func importedLocalModelAlreadyExistsTitle(modelFilename: String) -> String {
        "A model named \(modelFilename) already exists"
    }

    public static func importedLocalModelSuccessTitle(filename: String) -> String {
        "Imported \(filename)"
    }

    public static func importedLocalModelFailureTitle(errorDescription: String) -> String {
        "Failed to import model: \(errorDescription)"
    }
}

public enum VoiceInkTranscriptionModelProviderRole: Equatable, Sendable {
    case localWhisper
    case localFluidAudio
    case nativeApple
    case customCloud
    case cloud(VoiceInkTranscriptionModelProvider?)

    public var coreTranscriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        switch self {
        case .cloud(let provider):
            return provider
        case .localWhisper, .localFluidAudio, .nativeApple, .customCloud:
            return nil
        }
    }

    public var transcriptionLanguageSource: VoiceInkTranscriptionLanguageSource {
        switch self {
        case .localWhisper:
            return .whisper
        case .localFluidAudio:
            return .fluidAudio
        case .nativeApple:
            return .nativeApple
        case .customCloud:
            return .all
        case .cloud(let provider):
            guard let provider else { return .all }
            return .provider(provider)
        }
    }

    public var modelManagementCategory: VoiceInkModelManagementModelCategory {
        switch self {
        case .localWhisper, .localFluidAudio, .nativeApple:
            return .local
        case .customCloud:
            return .custom
        case .cloud:
            return .cloud
        }
    }

    public var transcriptionServiceRoute: VoiceInkTranscriptionServiceRoute {
        switch self {
        case .localWhisper:
            return .localWhisper
        case .localFluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        case .customCloud, .cloud:
            return .cloud
        }
    }

    public var transcriptionModelAvailabilityRequirement: VoiceInkTranscriptionModelAvailabilityRequirement {
        switch self {
        case .localWhisper:
            return .downloadedLocalWhisperModel
        case .localFluidAudio:
            return .downloadedLocalFluidAudioModel
        case .nativeApple:
            return .currentOSSupport
        case .customCloud:
            return .alwaysAvailable
        case .cloud(.nvidia):
            return .configuredAPIKeyAndCurrentOSSupport
        case .cloud(let provider):
            return provider == nil ? .unavailable : .configuredAPIKey
        }
    }

    public func apiKeyProviderName(defaultName: String) -> String {
        coreTranscriptionModelProvider?.providerKind?.displayName ?? defaultName
    }

    public var supportsRecordedFileTranscription: Bool {
        coreTranscriptionModelProvider?.supportsRecordedFileTranscription ?? true
    }

    public var isStreamingOnly: Bool {
        coreTranscriptionModelProvider?.isStreamingOnly ?? false
    }

    public func streamingConnectionModelName(for selectedModelName: String) -> String {
        coreTranscriptionModelProvider?.streamingConnectionModelName(for: selectedModelName) ?? selectedModelName
    }

    public var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        coreTranscriptionModelProvider?.mapsStreamingTransportTimeoutToFinalTimeout ?? false
    }

    public func transcriptionLanguageOptions(
        defaultLanguages: [String: String],
        isMultilingual: Bool,
        usesRealtimeProviderLanguages: Bool
    ) -> [String: String] {
        switch self {
        case .customCloud:
            return defaultLanguages
        case .localWhisper, .localFluidAudio, .nativeApple, .cloud:
            return VoiceInkTranscriptionLanguageSupport.languages(
                for: transcriptionLanguageSource,
                isMultilingual: isMultilingual,
                assemblyAIUsesRealtime: usesRealtimeProviderLanguages
            )
        }
    }
}

public struct VoiceInkCloudTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let speed: Double
    public let accuracy: Double
    public let isMultilingual: Bool
    public let supportsStreaming: Bool

    public init(
        name: String,
        displayName: String,
        description: String,
        speed: Double,
        accuracy: Double,
        isMultilingual: Bool,
        supportsStreaming: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.speed = speed
        self.accuracy = accuracy
        self.isMultilingual = isMultilingual
        self.supportsStreaming = supportsStreaming
    }
}

public struct VoiceInkNativeAppleTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let isMultilingual: Bool

    public var supportedLanguages: [String: String] {
        Self.supportedLanguages(isMultilingual: isMultilingual)
    }

    public init(
        name: String,
        displayName: String,
        description: String,
        isMultilingual: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.isMultilingual = isMultilingual
    }

    public static func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        isMultilingual ? VoiceInkLanguageCatalog.nativeApple : VoiceInkLanguageCatalog.englishOnly
    }
}

public enum VoiceInkFluidAudioModelVersion: String, Codable, Equatable, Sendable {
    case v2
    case v3
}

public struct VoiceInkFluidAudioTranscriptionModelSpec: Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let size: String
    public let speed: Double
    public let accuracy: Double
    public let ramUsage: Double
    public let modelVersion: VoiceInkFluidAudioModelVersion
    public let isMultilingual: Bool
    public let supportsStreaming: Bool

    public var supportedLanguages: [String: String] {
        Self.supportedLanguages(isMultilingual: isMultilingual)
    }

    public init(
        name: String,
        displayName: String,
        description: String,
        size: String,
        speed: Double,
        accuracy: Double,
        ramUsage: Double,
        modelVersion: VoiceInkFluidAudioModelVersion = .v3,
        isMultilingual: Bool,
        supportsStreaming: Bool
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.modelVersion = modelVersion
        self.isMultilingual = isMultilingual
        self.supportsStreaming = supportsStreaming
    }

    public static func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        VoiceInkLanguageCatalog.fluidAudioLanguages(isMultilingual: isMultilingual)
    }
}

public enum VoiceInkFluidAudioDownloadPhase: Equatable, Sendable {
    case preparingDownload
    case listingFiles
    case checkingCachedModels
    case downloadingFiles(completedFiles: Int, totalFiles: Int)
    case finalizingModels
    case compiling(modelComponentName: String)
}

public struct VoiceInkFluidAudioDownloadStatus: Equatable, Sendable {
    public static let compactDownloadingStatusText = "Downloading..."

    public let fractionCompleted: Double
    public let phase: VoiceInkFluidAudioDownloadPhase
    public let message: String
    public let percent: Int
    public let percentText: String

    public init(
        fractionCompleted: Double,
        phase: VoiceInkFluidAudioDownloadPhase
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.phase = phase
        self.message = Self.message(for: phase)
        self.percent = Int(self.fractionCompleted * 100)
        self.percentText = "\(percent)%"
    }

    private static func message(for phase: VoiceInkFluidAudioDownloadPhase) -> String {
        switch phase {
        case .preparingDownload:
            return "Preparing FluidAudio download..."
        case .listingFiles:
            return "Listing files from repository..."
        case .checkingCachedModels:
            return "Checking cached models..."
        case .downloadingFiles(let completedFiles, let totalFiles):
            return "Downloading models: \(completedFiles)/\(totalFiles) files"
        case .finalizingModels:
            return "Finalizing models..."
        case .compiling(let modelComponentName):
            return "Compiling \(displayName(forModelComponent: modelComponentName))"
        }
    }

    private static func displayName(forModelComponent modelComponentName: String) -> String {
        modelComponentName.replacingOccurrences(of: ".mlmodelc", with: "")
    }
}

public enum VoiceInkMacOSTranscriptionModelProvider: String, Codable, Hashable, CaseIterable, Sendable {
    case whisper = "Whisper"
    case fluidAudio = "Parakeet"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case mistral = "Mistral"
    case gemini = "Gemini"
    case soniox = "Soniox"
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case xai = "xAI"
    case cartesia = "Cartesia"
    case nvidia = "NVIDIA"
    case custom = "Custom"
    case nativeApple = "Native Apple"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "Local" {
            self = .whisper
            return
        }

        guard let provider = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ModelProvider: \(rawValue)"
            )
        }

        self = provider
    }

    public var coreTranscriptionModelProviderRole: VoiceInkTranscriptionModelProviderRole {
        switch self {
        case .groq:
            return .cloud(.groq)
        case .deepgram:
            return .cloud(.deepgram)
        case .elevenLabs:
            return .cloud(.elevenLabs)
        case .mistral:
            return .cloud(.mistral)
        case .gemini:
            return .cloud(.gemini)
        case .soniox:
            return .cloud(.soniox)
        case .speechmatics:
            return .cloud(.speechmatics)
        case .assemblyAI:
            return .cloud(.assemblyAI)
        case .xai:
            return .cloud(.xai)
        case .cartesia:
            return .cloud(.cartesia)
        case .nvidia:
            return .cloud(.nvidia)
        case .whisper:
            return .localWhisper
        case .fluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        case .custom:
            return .customCloud
        }
    }

    public var coreTranscriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        coreTranscriptionModelProviderRole.coreTranscriptionModelProvider
    }

    public var remoteTranscriptionProviderKind: VoiceInkProviderKind? {
        coreTranscriptionModelProvider?.providerKind
    }

    public var apiErrorDomain: String? {
        coreTranscriptionModelProvider?.apiErrorDomain
    }

    public var apiKeyProviderName: String {
        coreTranscriptionModelProviderRole.apiKeyProviderName(defaultName: rawValue)
    }

    public var languageCodes: [String]? {
        coreTranscriptionModelProvider?.languageCodes
    }

    public var includesAutoDetect: Bool {
        coreTranscriptionModelProvider?.includesAutoDetect ?? false
    }

    public var cloudModelSpecs: [VoiceInkCloudTranscriptionModelSpec] {
        guard let provider = coreTranscriptionModelProvider else {
            return []
        }

        return VoiceInkTranscriptionModelCatalog.cloudModels(for: provider)
    }

    public func remoteTranscriptionOptions(
        prompt: String?,
        customVocabulary: [String]
    ) -> VoiceInkRemoteTranscriptionOptions {
        guard let provider = remoteTranscriptionProviderKind else {
            return VoiceInkRemoteTranscriptionOptions()
        }

        return VoiceInkRemoteTranscriptionOptions.batchDefaults(
            forProviderKind: provider,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    public func acceptsRemoteTranscriptionText(_ text: String) -> Bool {
        remoteTranscriptionProviderKind?.transcriptionEmptyTextPolicy.accepts(text) ?? true
    }

    public var transcriptionLanguageSource: VoiceInkTranscriptionLanguageSource {
        coreTranscriptionModelProviderRole.transcriptionLanguageSource
    }

    public func supportedLanguages(isMultilingual: Bool) -> [String: String] {
        VoiceInkTranscriptionLanguageSupport.languages(
            for: transcriptionLanguageSource,
            isMultilingual: isMultilingual
        )
    }

    public func transcriptionLanguageOptions(
        defaultLanguages: [String: String],
        isMultilingual: Bool,
        usesRealtimeProviderLanguages: Bool
    ) -> [String: String] {
        coreTranscriptionModelProviderRole.transcriptionLanguageOptions(
            defaultLanguages: defaultLanguages,
            isMultilingual: isMultilingual,
            usesRealtimeProviderLanguages: usesRealtimeProviderLanguages
        )
    }

    public var modelManagementCategory: VoiceInkModelManagementModelCategory {
        coreTranscriptionModelProviderRole.modelManagementCategory
    }

    public var transcriptionServiceRoute: VoiceInkTranscriptionServiceRoute {
        coreTranscriptionModelProviderRole.transcriptionServiceRoute
    }

    public var transcriptionModelAvailabilityRequirement: VoiceInkTranscriptionModelAvailabilityRequirement {
        coreTranscriptionModelProviderRole.transcriptionModelAvailabilityRequirement
    }

    public var supportsRecordedFileTranscription: Bool {
        coreTranscriptionModelProviderRole.supportsRecordedFileTranscription
    }

    public var isStreamingOnly: Bool {
        coreTranscriptionModelProviderRole.isStreamingOnly
    }

    public func streamingConnectionModelName(for selectedModelName: String) -> String {
        coreTranscriptionModelProviderRole.streamingConnectionModelName(for: selectedModelName)
    }

    public var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        coreTranscriptionModelProviderRole.mapsStreamingTransportTimeoutToFinalTimeout
    }
}

public struct VoiceInkMacOSTranscriptionModelFacts: Equatable, Sendable {
    public let name: String
    public let provider: VoiceInkMacOSTranscriptionModelProvider
    public let isMultilingual: Bool
    public let supportedLanguages: [String: String]
    public let supportsStreaming: Bool

    public init(
        name: String,
        provider: VoiceInkMacOSTranscriptionModelProvider,
        isMultilingual: Bool,
        supportedLanguages: [String: String],
        supportsStreaming: Bool
    ) {
        self.name = name
        self.provider = provider
        self.isMultilingual = isMultilingual
        self.supportedLanguages = supportedLanguages
        self.supportsStreaming = supportsStreaming
    }

    public var supportsRecordedFileTranscription: Bool {
        provider.supportsRecordedFileTranscription
    }

    public var streamingPreferenceSnapshot: VoiceInkTranscriptionStreamingModelSnapshot {
        VoiceInkTranscriptionStreamingModelSnapshot(
            name: name,
            supportsStreaming: supportsStreaming,
            isStreamingOnly: provider.isStreamingOnly
        )
    }

    public var transcriptionSessionRouteFacts: VoiceInkTranscriptionSessionRouteFacts {
        VoiceInkTranscriptionSessionRouteFacts(
            serviceRoute: provider.transcriptionServiceRoute,
            streamingSnapshot: streamingPreferenceSnapshot
        )
    }

    public var streamingConnectionModelName: String {
        provider.streamingConnectionModelName(for: name)
    }

    public var mapsStreamingTransportTimeoutToFinalTimeout: Bool {
        provider.mapsStreamingTransportTimeoutToFinalTimeout
    }

    public var transcriptionRuntimeResourcePlan: VoiceInkTranscriptionRuntimeResourcePlan {
        VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: provider.transcriptionServiceRoute)
    }

    public func transcriptionModelAvailabilityFacts(
        hasConfiguredAPIKey: Bool = false,
        isAvailableOnCurrentOS: Bool = true,
        isLocalFluidAudioModelDownloaded: Bool = false,
        isLocalWhisperModelDownloaded: Bool = false
    ) -> VoiceInkTranscriptionModelAvailabilityFacts {
        VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: provider.transcriptionModelAvailabilityRequirement,
            hasConfiguredAPIKey: hasConfiguredAPIKey,
            isAvailableOnCurrentOS: isAvailableOnCurrentOS,
            isLocalFluidAudioModelDownloaded: isLocalFluidAudioModelDownloaded,
            isLocalWhisperModelDownloaded: isLocalWhisperModelDownloaded
        )
    }

    public var transcriptionLanguageOptions: [String: String] {
        provider.transcriptionLanguageOptions(
            defaultLanguages: supportedLanguages,
            isMultilingual: isMultilingual,
            usesRealtimeProviderLanguages: VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(
                for: streamingPreferenceSnapshot
            )
        )
    }

    public var transcriptionLanguageSelectionFacts: VoiceInkTranscriptionLanguageSelectionFacts {
        VoiceInkTranscriptionLanguageSelectionFacts(
            source: provider.transcriptionLanguageSource,
            isMultilingual: isMultilingual,
            languageOptions: transcriptionLanguageOptions
        )
    }

    public func validTranscriptionLanguageOrFallback(_ language: String?) -> String {
        transcriptionLanguageSelectionFacts.compatibleLanguage(language)
    }

    public var powerModeTranscriptionModelFacts: VoiceInkPowerModeTranscriptionModelFacts {
        VoiceInkPowerModeTranscriptionModelFacts(
            name: name,
            languageSource: provider.transcriptionLanguageSource,
            isMultilingual: isMultilingual,
            languageOptions: transcriptionLanguageOptions
        )
    }

    public var powerModeTranscriptionModelResourceFacts: VoiceInkPowerModeTranscriptionModelResourceFacts {
        VoiceInkPowerModeTranscriptionModelResourceFacts(
            name: name,
            languageSource: provider.transcriptionLanguageSource
        )
    }

    public func modelManagementFacts(isAvailableOnCurrentOS: Bool) -> VoiceInkModelManagementModelFacts {
        VoiceInkModelManagementModelFacts(
            name: name,
            category: provider.modelManagementCategory,
            isAvailableOnCurrentOS: isAvailableOnCurrentOS
        )
    }
}

public enum VoiceInkTranscriptionModelCatalog {
    public static let localBaseModel = "base"
    public static let defaultMacOSFluidAudioModelName = "parakeet-tdt-0.6b-v2"

    public static let nativeAppleModel = VoiceInkNativeAppleTranscriptionModelSpec(
        name: "apple-speech",
        displayName: "Apple Speech",
        description: "Uses the native Apple Speech framework for transcription. Requires macOS 26",
        isMultilingual: true
    )

    public static let fluidAudioModels = [
        VoiceInkFluidAudioTranscriptionModelSpec(
            name: "parakeet-tdt-0.6b-v2",
            displayName: "Parakeet V2",
            description: "NVIDIA's Parakeet V2 model optimized for lightning-fast English-only transcription",
            size: "474 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            modelVersion: .v2,
            isMultilingual: false,
            supportsStreaming: true
        ),
        VoiceInkFluidAudioTranscriptionModelSpec(
            name: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet V3",
            description: "Parakeet V3 with English and 25 European language support",
            size: "494 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            modelVersion: .v3,
            isMultilingual: true,
            supportsStreaming: true
        )
    ]

    public static var defaultMacOSFluidAudioModel: VoiceInkFluidAudioTranscriptionModelSpec {
        fluidAudioModels.first { $0.name == defaultMacOSFluidAudioModelName } ?? fluidAudioModels[0]
    }

    public static func fluidAudioModelVersion(forModelName modelName: String) -> VoiceInkFluidAudioModelVersion {
        fluidAudioModels.first { $0.name == modelName }?.modelVersion ?? .v3
    }

    public static func fluidAudioLanguageHintCode(
        from selectedLanguage: String?,
        forModelName modelName: String
    ) -> String? {
        guard fluidAudioModelVersion(forModelName: modelName) == .v3,
              let selectedLanguage,
              selectedLanguage != VoiceInkLanguageCatalog.autoDetectCode
        else { return nil }

        return selectedLanguage
    }

    public static func modelNames(for provider: VoiceInkTranscriptionModelProvider) -> [String] {
        switch provider {
        case .assemblyAI, .cartesia, .groq, .deepgram, .elevenLabs, .mistral, .gemini, .soniox, .speechmatics, .xai, .nvidia:
            return cloudModels(for: provider).map(\.name)
        case .openAI:
            return [
                "whisper-1",
                "gpt-4o-transcribe",
                "gpt-4o-mini-transcribe"
            ]
        case .local:
            return [localBaseModel]
        case .nativeApple:
            return [nativeAppleModel.name]
        }
    }

    public static func cloudModels(for provider: VoiceInkTranscriptionModelProvider) -> [VoiceInkCloudTranscriptionModelSpec] {
        switch provider {
        case .nvidia:
            return [VoiceInkCloudTranscriptionModelSpec(
                name: "parakeet-ctc-0.6b-zh-tw",
                displayName: "Parakeet zh-TW (NVIDIA Cloud)",
                description: "Optional cloud backup for Taiwanese Mandarin and English. Sends audio to NVIDIA; requires your API key and macOS 15 or later.",
                speed: 0,
                accuracy: 0,
                isMultilingual: true,
                supportsStreaming: false
            )]
        case .assemblyAI:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "universal-3-pro",
                    displayName: "Universal-3 Pro (AssemblyAI)",
                    description: "Highest-accuracy multilingual transcription with realtime support.",
                    speed: 0.94,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "universal-streaming",
                    displayName: "Universal-2 (AssemblyAI)",
                    description: "Balanced multilingual transcription with auto-detect.",
                    speed: 0.96,
                    accuracy: 0.92,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .cartesia:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "ink-whisper",
                    displayName: "Ink Whisper (Cartesia)",
                    description: "Cartesia's fastest streaming STT model — engineered for real-time voice agents with 90+ language support",
                    speed: 0.99,
                    accuracy: 0.94,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .groq:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "whisper-large-v3-turbo",
                    displayName: "Whisper Large v3 Turbo (Groq)",
                    description: "Whisper Large v3 Turbo model with Groq's lightning-speed inference",
                    speed: 0.65,
                    accuracy: 0.95,
                    isMultilingual: true
                )
            ]
        case .deepgram:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "nova-3",
                    displayName: "Nova 3 (Deepgram)",
                    description: "Deepgram's latest Nova 3 model for fast, accurate transcription",
                    speed: 0.99,
                    accuracy: 0.96,
                    isMultilingual: true,
                    supportsStreaming: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "nova-3-medical",
                    displayName: "Nova 3 Medical (Deepgram)",
                    description: "Specialized medical transcription model optimized for clinical environments",
                    speed: 0.99,
                    accuracy: 0.96,
                    isMultilingual: false,
                    supportsStreaming: true
                )
            ]
        case .mistral:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "voxtral-mini-latest",
                    displayName: "Voxtral (Mistral)",
                    description: "Mistral's Voxtral model for fast and accurate transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .gemini:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-2.5-pro",
                    displayName: "Gemini 2.5 Pro",
                    description: "Google's advanced model with high-quality transcription capabilities",
                    speed: 0.7,
                    accuracy: 0.97,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-2.5-flash",
                    displayName: "Gemini 2.5 Flash",
                    description: "Google's optimized model for low-latency transcription",
                    speed: 0.9,
                    accuracy: 0.95,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-3.1-pro-preview",
                    displayName: "Gemini 3.1 Pro",
                    description: "Google's latest model with enhanced transcription capabilities",
                    speed: 0.75,
                    accuracy: 0.97,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "gemini-3-flash-preview",
                    displayName: "Gemini 3 Flash",
                    description: "Google's newest fast model combining intelligence with superior speed",
                    speed: 0.92,
                    accuracy: 0.95,
                    isMultilingual: true
                )
            ]
        case .soniox:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "stt-async-v4",
                    displayName: "Soniox V4",
                    description: "Soniox transcription model v4 with human-parity accuracy",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .elevenLabs:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "scribe_v1",
                    displayName: "Scribe v1 (ElevenLabs)",
                    description: "ElevenLabs' Scribe model for fast & accurate transcription",
                    speed: 0.7,
                    accuracy: 0.98,
                    isMultilingual: true
                ),
                VoiceInkCloudTranscriptionModelSpec(
                    name: "scribe_v2",
                    displayName: "Scribe V2 (ElevenLabs)",
                    description: "ElevenLabs' Scribe V2 model for the most accurate transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .xai:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "grok-stt",
                    displayName: "Grok (xAI)",
                    description: "xAI's Grok speech-to-text with streaming and batch transcription",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .speechmatics:
            return [
                VoiceInkCloudTranscriptionModelSpec(
                    name: "speechmatics-enhanced",
                    displayName: "Speechmatics",
                    description: "Speechmatics enhanced accuracy transcription with streaming and 50+ language support",
                    speed: 0.99,
                    accuracy: 0.98,
                    isMultilingual: true,
                    supportsStreaming: true
                )
            ]
        case .openAI, .local, .nativeApple:
            return []
        }
    }
}
