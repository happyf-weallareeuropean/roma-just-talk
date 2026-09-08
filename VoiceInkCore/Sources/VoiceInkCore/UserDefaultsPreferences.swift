import Foundation

public enum VoiceInkUserDefaultsKey {
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let lowercaseTranscription = "LowercaseTranscription"
    public static let removeFillerWords = "RemoveFillerWords"
    public static let fillerWords = "FillerWords"
    public static let wordReplacements = "voiceInkIOSWordReplacements"
    public static let customVocabularyTerms = "voiceInkIOSCustomVocabularyTerms"
    public static let modes = "modes"
    public static let selectedModeId = "selectedModeId"
    public static let selectedTranscriptionLanguage = "SelectedLanguage"
    public static let currentTranscriptionModel = "CurrentTranscriptionModel"
    public static let transcriptionPrompt = "TranscriptionPrompt"
    public static let isTextFormattingEnabled = "IsTextFormattingEnabled"
    public static let isVADEnabled = "IsVADEnabled"
    public static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    public static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    public static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
    public static let audioRetentionPeriodDays = "AudioRetentionPeriod"
    public static let audioPlaybackRate = "audioPlaybackRate"
    public static let appendTrailingSpace = "AppendTrailingSpace"
    public static let skipShortEnhancement = "SkipShortEnhancement"
    public static let shortEnhancementWordThreshold = "ShortEnhancementWordThreshold"
    public static let enhancementTimeoutSeconds = "EnhancementTimeoutSeconds"
    public static let enhancementRetryOnTimeout = "EnhancementRetryOnTimeout"
    public static let audioSessionTimeoutSeconds = "audioSessionTimeoutSeconds"
    public static let isAIEnhancementEnabled = "isAIEnhancementEnabled"
    public static let useClipboardContext = "useClipboardContext"
    public static let useScreenCaptureContext = "useScreenCaptureContext"
    public static let customPrompts = "customPrompts"
    public static let selectedPromptId = "selectedPromptId"
    public static let powerModeUIFlag = "powerModeUIFlag"
    public static let powerModePersistConfig = "powerModePersistConfig"
    public static let powerModeConfigurations = "powerModeConfigurationsV2"
    public static let activePowerModeConfigurationId = "activeConfigurationId"
    public static let activePowerModeSession = "powerModeActiveSession.v1"
    public static let prewarmModelOnWake = "PrewarmModelOnWake"
    public static let showLiveTextPreview = "showLiveTextPreview"
    public static let primaryRecordingShortcut = "primaryRecordingShortcut"
    public static let secondaryRecordingShortcut = "secondaryRecordingShortcut"
    public static let primaryRecordingShortcutMode = "primaryRecordingShortcutMode"
    public static let secondaryRecordingShortcutMode = "secondaryRecordingShortcutMode"
    public static let isMiddleClickToggleEnabled = "isMiddleClickToggleEnabled"
    public static let middleClickActivationDelay = "middleClickActivationDelay"
    public static let specialShortcutPasteLastTranscriptOnEmptyTap = "specialShortcutPasteLastTranscriptOnEmptyTap"
    public static let selectedAIProvider = "selectedAIProvider"
    public static let openRouterModels = "openRouterModels"
    public static let ollamaBaseURL = "ollamaBaseURL"
    public static let ollamaSelectedModel = "ollamaSelectedModel"
    public static let customProviderBaseURL = "customProviderBaseURL"
    public static let customProviderModel = "customProviderModel"
    public static let showMenuBarIcon = "ShowMenuBarIcon"
    public static let legacyIsMenuBarOnly = "IsMenuBarOnly"
    public static let enableAnnouncements = "enableAnnouncements"
    public static let didApplyLaunchAtLoginDefault = "DidApplyLaunchAtLoginDefault"

    public static func selectedAIProviderModel(_ providerRawValue: String) -> String {
        "\(providerRawValue)SelectedModel"
    }
}

public enum VoiceInkPreferenceDefault {
    public static let audioSessionTimeoutSeconds = 90
    public static let isTextFormattingEnabled = true
    public static let isVADEnabled = true
    public static let lowercaseTranscription = false
    public static let removeFillerWords = true
    public static let transcriptionRetentionMinutes = 24 * 60
    public static let audioRetentionDays = 7
    public static let appendTrailingSpace = true
    public static let skipShortEnhancement = true
    public static let shortEnhancementWordThreshold = 3
    public static let enhancementTimeoutSeconds = 7
    public static let enhancementRetryOnTimeout = true
    public static let powerModeUIEnabled = false
    public static let powerModePersistConfiguredPreferences = false
    public static let prewarmModelOnWake = true
    public static let showLiveTextPreview = false
    public static let isMiddleClickToggleEnabled = false
    public static let middleClickActivationDelay = 200
    public static let specialShortcutPasteLastTranscriptOnEmptyTap = true
    public static let ollamaBaseURL = "http://localhost:11434"
    public static let macOSSelectedTranscriptionLanguage = "en"
    public static let showMenuBarIcon = false
    public static let showDockIcon = false
    public static let enableAnnouncements = true
    public static let didApplyLaunchAtLoginDefault = false
}

public enum VoiceInkSystemMuteMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case always = "always"
    case never = "never"

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .always:
            return "On"
        case .never:
            return "Off"
        }
    }
}

public struct VoiceInkRecordingFeedbackDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct VoiceInkMacOSRecordingFeedbackSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let soundFeedbackLabel: String
    public let systemMuteModeLabel: String
    public let audioResumptionDelayLabel: String
    public let audioResumptionDelayOptions: [VoiceInkRecordingFeedbackDelayOption]
    public let experimentalSectionTitle: String
    public let pauseMediaLabel: String
    public let pauseMediaInfoMessage: String
    public let pauseMediaResumeDelayLabel: String

    public init(
        sectionTitle: String,
        soundFeedbackLabel: String,
        systemMuteModeLabel: String,
        audioResumptionDelayLabel: String,
        audioResumptionDelayOptions: [VoiceInkRecordingFeedbackDelayOption],
        experimentalSectionTitle: String,
        pauseMediaLabel: String,
        pauseMediaInfoMessage: String,
        pauseMediaResumeDelayLabel: String
    ) {
        self.sectionTitle = sectionTitle
        self.soundFeedbackLabel = soundFeedbackLabel
        self.systemMuteModeLabel = systemMuteModeLabel
        self.audioResumptionDelayLabel = audioResumptionDelayLabel
        self.audioResumptionDelayOptions = audioResumptionDelayOptions
        self.experimentalSectionTitle = experimentalSectionTitle
        self.pauseMediaLabel = pauseMediaLabel
        self.pauseMediaInfoMessage = pauseMediaInfoMessage
        self.pauseMediaResumeDelayLabel = pauseMediaResumeDelayLabel
    }
}

public struct VoiceInkRecordingFeedbackBackupPreferences: Codable, Equatable, Sendable {
    public let isSoundFeedbackEnabled: Bool?
    public let isSystemMuteEnabled: Bool?
    public let isPauseMediaEnabled: Bool?
    public let audioResumptionDelay: Double?
    public let isExperimentalFeaturesEnabled: Bool?

    public init(
        isSoundFeedbackEnabled: Bool?,
        isSystemMuteEnabled: Bool?,
        isPauseMediaEnabled: Bool?,
        audioResumptionDelay: Double?,
        isExperimentalFeaturesEnabled: Bool? = nil
    ) {
        self.isSoundFeedbackEnabled = isSoundFeedbackEnabled
        self.isSystemMuteEnabled = isSystemMuteEnabled
        self.isPauseMediaEnabled = isPauseMediaEnabled
        self.audioResumptionDelay = audioResumptionDelay
        self.isExperimentalFeaturesEnabled = isExperimentalFeaturesEnabled
    }
}

public struct VoiceInkRecordingFeedbackBackupImportPlan: Equatable, Sendable {
    private let isSoundFeedbackEnabled: Bool?
    private let systemMuteMode: VoiceInkSystemMuteMode?
    private let isPauseMediaEnabled: Bool?
    private let audioResumptionDelay: Double?
    private let isExperimentalFeaturesEnabled: Bool?

    public var shouldDisablePauseMediaForExperimentalImport: Bool {
        isExperimentalFeaturesEnabled == false
    }

    public init(
        isSoundFeedbackEnabled: Bool?,
        systemMuteMode: VoiceInkSystemMuteMode?,
        isPauseMediaEnabled: Bool?,
        audioResumptionDelay: Double?,
        isExperimentalFeaturesEnabled: Bool? = nil
    ) {
        self.isSoundFeedbackEnabled = isSoundFeedbackEnabled
        self.systemMuteMode = systemMuteMode
        self.isPauseMediaEnabled = isPauseMediaEnabled
        self.audioResumptionDelay = audioResumptionDelay
        self.isExperimentalFeaturesEnabled = isExperimentalFeaturesEnabled
    }

    public func applyRuntimeState(
        setSoundFeedbackEnabled: (Bool) -> Void,
        setSystemMuteMode: (VoiceInkSystemMuteMode) -> Void,
        setPauseMediaEnabled: (Bool) -> Void,
        setAudioResumptionDelay: (Double) -> Void,
        disablePauseMediaForExperimentalImport: () -> Void
    ) {
        if let isSoundFeedbackEnabled {
            setSoundFeedbackEnabled(isSoundFeedbackEnabled)
        }
        if let systemMuteMode {
            setSystemMuteMode(systemMuteMode)
        }
        if let isPauseMediaEnabled {
            setPauseMediaEnabled(isPauseMediaEnabled)
        }
        if let audioResumptionDelay {
            setAudioResumptionDelay(audioResumptionDelay)
        }
        if shouldDisablePauseMediaForExperimentalImport {
            disablePauseMediaForExperimentalImport()
        }
    }

    public func applyCorePreferenceState(
        setExperimentalFeaturesEnabled: (Bool) -> Void
    ) {
        if let isExperimentalFeaturesEnabled {
            setExperimentalFeaturesEnabled(isExperimentalFeaturesEnabled)
        }
    }
}

public enum VoiceInkBuiltInRecordingSound: String, CaseIterable, Identifiable, Sendable {
    case sound1
    case sound2
    case sound3
    case sound4
    case sound5
    case sound6
    case sound7

    public var id: String { rawValue }

    public var displayName: String {
        "Sound \(number)"
    }

    public var fileExtension: String {
        switch self {
        case .sound1, .sound2, .sound3, .sound4, .sound7:
            return "wav"
        case .sound5, .sound6:
            return "mp3"
        }
    }

    private var number: Int {
        Int(rawValue.replacingOccurrences(of: "sound", with: "")) ?? 0
    }
}

public enum VoiceInkCustomSoundType: String, CaseIterable, Sendable {
    case start
    case stop

    public var displayName: String {
        switch self {
        case .start:
            return "Start"
        case .stop:
            return "Stop"
        }
    }

    public var isUsingKey: String {
        "isUsingCustom\(capitalizedRawValue)Sound"
    }

    public var filenameKey: String {
        "custom\(capitalizedRawValue)SoundFilename"
    }

    public var builtInSoundKey: String {
        "selected\(capitalizedRawValue)BuiltInSound"
    }

    public var standardName: String {
        "Custom\(capitalizedRawValue)Sound"
    }

    public var defaultBuiltInSound: VoiceInkBuiltInRecordingSound {
        switch self {
        case .start:
            return .sound1
        case .stop:
            return .sound2
        }
    }

    public var recordingSoundCue: VoiceInkRecordingSoundCue {
        switch self {
        case .start:
            return .start
        case .stop:
            return .stop
        }
    }

    private var capitalizedRawValue: String {
        rawValue.capitalized
    }
}

public enum VoiceInkCustomSoundMenuSelection: Hashable, Sendable {
    case builtIn(VoiceInkBuiltInRecordingSound)
    case custom
}

public struct VoiceInkCustomSoundSelectionState: Equatable, Sendable {
    public let type: VoiceInkCustomSoundType
    public let isUsingCustomSound: Bool
    public let selectedBuiltInSound: VoiceInkBuiltInRecordingSound
    public let customFilename: String?

    public init(
        type: VoiceInkCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: VoiceInkBuiltInRecordingSound,
        customFilename: String?
    ) {
        self.type = type
        self.isUsingCustomSound = isUsingCustomSound
        self.selectedBuiltInSound = selectedBuiltInSound
        self.customFilename = customFilename
    }

    public var menuSelection: VoiceInkCustomSoundMenuSelection {
        isUsingCustomSound ? .custom : .builtIn(selectedBuiltInSound)
    }

    public var isDefaultSelection: Bool {
        VoiceInkCustomSoundPreference.isDefaultSelection(
            for: type,
            isUsingCustomSound: isUsingCustomSound,
            selectedBuiltInSound: selectedBuiltInSound
        )
    }

    public func customSoundURL(in customSoundsDirectory: URL?) -> URL? {
        VoiceInkCustomSoundPreference.customSoundURL(
            isUsingCustomSound: isUsingCustomSound,
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func storedCustomSoundURL(in customSoundsDirectory: URL?) -> URL? {
        VoiceInkCustomSoundPreference.storedCustomSoundURL(
            filename: customFilename,
            in: customSoundsDirectory
        )
    }

    public func selectingBuiltInSound(
        _ sound: VoiceInkBuiltInRecordingSound
    ) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: sound,
            customFilename: customFilename
        )
    }

    public func usingExistingCustomSound() -> VoiceInkCustomSoundSelectionState? {
        guard customFilename != nil else { return nil }
        return VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: customFilename
        )
    }

    public func settingCustomFilename(_ filename: String) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: true,
            selectedBuiltInSound: selectedBuiltInSound,
            customFilename: filename
        )
    }

    public func resettingToDefault() -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: false,
            selectedBuiltInSound: type.defaultBuiltInSound,
            customFilename: nil
        )
    }
}

public enum VoiceInkCustomSoundSettingsPresentation {
    public static let pickerTitle = "Sound"
    public static let customFallbackTitle = "Custom"
    public static let selectSoundHelpText = "Select sound"
    public static let testButtonHelpText = "Test"
    public static let chooseButtonHelpText = "Choose"
    public static let resetButtonHelpText = "Reset"
    public static let testButtonSystemImageName = "play.fill"
    public static let chooseButtonSystemImageName = "folder"
    public static let resetButtonSystemImageName = "arrow.uturn.backward"
    public static let openPanelMessage = "Select an audio file"
    public static let invalidAudioAlertTitle = "Invalid Audio File"
    public static let alertDismissButtonTitle = "OK"

    public static func label(for type: VoiceInkCustomSoundType) -> String {
        "\(type.displayName) Sound"
    }

    public static func customMenuTitle(filename: String?) -> String {
        "Custom: \(filename ?? customFallbackTitle)"
    }

    public static func openPanelTitle(for type: VoiceInkCustomSoundType) -> String {
        "Choose \(type.displayName) Sound"
    }
}

public enum VoiceInkRecordingSoundCue: CaseIterable, Sendable {
    case start
    case stop
    case esc
}

public enum VoiceInkRecordingSoundPlayerSlot: CaseIterable, Hashable, Sendable {
    case defaultStart
    case defaultStop
    case defaultEsc
    case customStart
    case customStop

    public var volume: Float {
        switch self {
        case .defaultStart, .defaultStop, .customStart, .customStop:
            return 0.4
        case .defaultEsc:
            return 0.3
        }
    }
}

public enum VoiceInkRecordingSoundPlaybackPolicy {
    public static let setupSlots: [VoiceInkRecordingSoundPlayerSlot] = [
        .defaultStart,
        .defaultStop,
        .defaultEsc,
        .customStart,
        .customStop
    ]

    public static func playbackSlots(
        for cue: VoiceInkRecordingSoundCue
    ) -> [VoiceInkRecordingSoundPlayerSlot] {
        switch cue {
        case .start:
            return [.customStart, .defaultStart]
        case .stop:
            return [.customStop, .defaultStop]
        case .esc:
            return [.defaultEsc]
        }
    }
}

public enum VoiceInkRecordingSoundPlaybackDiagnostics {
    public static func loadFailedMessage(localizedDescription: String) -> String {
        "Failed to load sound: \(localizedDescription)"
    }
}

public enum VoiceInkCustomSoundError: LocalizedError, Equatable, Sendable {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .durationTooLong(let duration, let maxDuration):
            return String(
                format: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter for start and stop sounds.",
                duration,
                maxDuration
            )
        case .directoryCreationFailed:
            return "Failed to create custom sounds directory"
        case .fileCopyFailed:
            return "Failed to copy audio file"
        }
    }
}

fileprivate enum VoiceInkCustomSoundCopyAction: Equatable, Sendable {
    case useExistingDestination
    case copy
    case replaceExistingDestinationAndCopy
}

public struct VoiceInkCustomSoundCopyPlan: Equatable, Sendable {
    public let filename: String
    public let destinationURL: URL
    private let action: VoiceInkCustomSoundCopyAction

    fileprivate init(
        filename: String,
        destinationURL: URL,
        action: VoiceInkCustomSoundCopyAction
    ) {
        self.filename = filename
        self.destinationURL = destinationURL
        self.action = action
    }

    public func applyRuntimeState(
        removeExistingDestination: (URL) throws -> Void,
        copyToDestination: (URL) throws -> Void
    ) -> Result<String, VoiceInkCustomSoundError> {
        switch action {
        case .useExistingDestination:
            return .success(filename)
        case .replaceExistingDestinationAndCopy:
            try? removeExistingDestination(destinationURL)
        case .copy:
            break
        }

        do {
            try copyToDestination(destinationURL)
            return .success(filename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }
}

public enum VoiceInkCustomSoundPreference {
    public static let customSoundsRelativeDirectory = "VoiceInk/CustomSounds"
    public static let changedNotificationName = "CustomSoundsChanged"
    public static let maxDuration: TimeInterval = 3.0

    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkCustomSoundType.start.builtInSoundKey: VoiceInkCustomSoundType.start.defaultBuiltInSound.rawValue,
            VoiceInkCustomSoundType.stop.builtInSoundKey: VoiceInkCustomSoundType.stop.defaultBuiltInSound.rawValue
        ]
    }

    public static func selectionState(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkCustomSoundSelectionState {
        VoiceInkCustomSoundSelectionState(
            type: type,
            isUsingCustomSound: isUsingCustomSound(for: type, from: defaults),
            selectedBuiltInSound: selectedBuiltInSound(for: type, from: defaults),
            customFilename: customFilename(for: type, from: defaults)
        )
    }

    public static func isUsingCustomSound(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: type.isUsingKey)
    }

    public static func saveIsUsingCustomSound(
        _ isUsingCustomSound: Bool,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isUsingCustomSound, forKey: type.isUsingKey)
    }

    public static func customFilename(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: type.filenameKey)
    }

    public static func saveCustomFilename(
        _ filename: String?,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        if let filename {
            defaults.set(filename, forKey: type.filenameKey)
        } else {
            defaults.removeObject(forKey: type.filenameKey)
        }
    }

    public static func selectedBuiltInSound(
        for type: VoiceInkCustomSoundType,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkBuiltInRecordingSound {
        if let rawValue = defaults.string(forKey: type.builtInSoundKey),
           let sound = VoiceInkBuiltInRecordingSound(rawValue: rawValue) {
            return sound
        }

        return type.defaultBuiltInSound
    }

    public static func saveSelectedBuiltInSound(
        _ sound: VoiceInkBuiltInRecordingSound,
        for type: VoiceInkCustomSoundType,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(sound.rawValue, forKey: type.builtInSoundKey)
    }

    public static func isDefaultSelection(
        for type: VoiceInkCustomSoundType,
        isUsingCustomSound: Bool,
        selectedBuiltInSound: VoiceInkBuiltInRecordingSound
    ) -> Bool {
        !isUsingCustomSound && selectedBuiltInSound == type.defaultBuiltInSound
    }

    public static func copiedFilename(
        sourceExtension: String,
        for type: VoiceInkCustomSoundType
    ) -> String {
        "\(type.standardName).\(sourceExtension)"
    }

    public static func customSoundURL(
        isUsingCustomSound: Bool,
        filename: String?,
        in customSoundsDirectory: URL?
    ) -> URL? {
        guard isUsingCustomSound else { return nil }
        return storedCustomSoundURL(filename: filename, in: customSoundsDirectory)
    }

    public static func storedCustomSoundURL(
        filename: String?,
        in customSoundsDirectory: URL?
    ) -> URL? {
        guard let filename, let customSoundsDirectory else { return nil }
        return customSoundsDirectory.appendingPathComponent(filename)
    }

    public static func copyPlan(
        sourceURL: URL,
        customSoundsDirectory: URL,
        for type: VoiceInkCustomSoundType,
        fileManager: FileManager = .default
    ) -> VoiceInkCustomSoundCopyPlan {
        let filename = copiedFilename(sourceExtension: sourceURL.pathExtension, for: type)
        let destinationURL = customSoundsDirectory.appendingPathComponent(filename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return VoiceInkCustomSoundCopyPlan(
                filename: filename,
                destinationURL: destinationURL,
                action: .useExistingDestination
            )
        }

        return VoiceInkCustomSoundCopyPlan(
            filename: filename,
            destinationURL: destinationURL,
            action: fileManager.fileExists(atPath: destinationURL.path) ? .replaceExistingDestinationAndCopy : .copy
        )
    }

    public static func preflightValidationError(
        fileExists: Bool,
        duration: TimeInterval
    ) -> VoiceInkCustomSoundError? {
        guard fileExists else { return .fileNotFound }
        guard duration.isFinite && duration > 0 else { return .invalidAudioFile }

        if duration > maxDuration {
            return .durationTooLong(duration: duration, maxDuration: maxDuration)
        }

        return nil
    }
}

public enum VoiceInkRecordingFeedbackPreference {
    public static let systemMuteModeKey = "systemMuteMode"
    public static let legacyIsSystemMuteEnabledKey = "isSystemMuteEnabled"
    public static let audioResumptionDelayKey = "audioResumptionDelay"
    public static let isPauseMediaEnabledKey = "isPauseMediaEnabled"
    public static let isSoundFeedbackEnabledKey = "isSoundFeedbackEnabled"
    public static let experimentalFeaturesEnabledKey = "isExperimentalFeaturesEnabled"

    public static let defaultSystemMuteMode = VoiceInkSystemMuteMode.automatic
    public static let defaultAudioResumptionDelay: TimeInterval = 0.0
    public static let defaultSystemMuteScheduleDelayNanoseconds: UInt64 = 250_000_000
    public static let defaultPauseMediaCommandDelayNanoseconds: UInt64 = 50_000_000
    public static let defaultIsPauseMediaEnabled = false
    public static let defaultIsSoundFeedbackEnabled = false

    public static var registeredDefaults: [String: Any] {
        [
            systemMuteModeKey: defaultSystemMuteMode.rawValue,
            legacyIsSystemMuteEnabledKey: true,
            audioResumptionDelayKey: defaultAudioResumptionDelay,
            isPauseMediaEnabledKey: defaultIsPauseMediaEnabled,
            isSoundFeedbackEnabledKey: defaultIsSoundFeedbackEnabled
        ]
    }

    public static let macOSSettingsPresentation = VoiceInkMacOSRecordingFeedbackSettingsPresentation(
        sectionTitle: "Recording Feedback",
        soundFeedbackLabel: "Sound Feedback",
        systemMuteModeLabel: "Mute Audio While Recording",
        audioResumptionDelayLabel: "Audio Resume Delay",
        audioResumptionDelayOptions: [
            VoiceInkRecordingFeedbackDelayOption(label: "0s", value: 0.0),
            VoiceInkRecordingFeedbackDelayOption(label: "1s", value: 1.0),
            VoiceInkRecordingFeedbackDelayOption(label: "2s", value: 2.0),
            VoiceInkRecordingFeedbackDelayOption(label: "3s", value: 3.0),
            VoiceInkRecordingFeedbackDelayOption(label: "4s", value: 4.0),
            VoiceInkRecordingFeedbackDelayOption(label: "5s", value: 5.0)
        ],
        experimentalSectionTitle: "Experimental",
        pauseMediaLabel: "Pause Media While Recording",
        pauseMediaInfoMessage: "Pauses playing media when recording starts and resumes when done.",
        pauseMediaResumeDelayLabel: "Resume Delay"
    )

    public static func systemMuteMode(from defaults: UserDefaults = .standard) -> VoiceInkSystemMuteMode {
        if let rawValue = defaults.string(forKey: systemMuteModeKey),
           let mode = VoiceInkSystemMuteMode(rawValue: rawValue) {
            return mode
        }

        if let legacyEnabled = defaults.object(forKey: legacyIsSystemMuteEnabledKey) as? Bool,
           legacyEnabled == false {
            return .never
        }

        return defaultSystemMuteMode
    }

    public static func saveSystemMuteMode(
        _ mode: VoiceInkSystemMuteMode,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: systemMuteModeKey)
        defaults.set(mode != .never, forKey: legacyIsSystemMuteEnabledKey)
    }

    public static func isSystemMuteEnabled(from defaults: UserDefaults = .standard) -> Bool {
        systemMuteMode(from: defaults) != .never
    }

    public static func saveSystemMuteEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        saveSystemMuteMode(isEnabled ? .always : .never, to: defaults)
    }

    public static func audioResumptionDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: audioResumptionDelayKey) != nil else {
            return defaultAudioResumptionDelay
        }

        return defaults.double(forKey: audioResumptionDelayKey)
    }

    public static func saveAudioResumptionDelay(
        _ delay: TimeInterval,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(delay, forKey: audioResumptionDelayKey)
    }

    public static func isPauseMediaEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isPauseMediaEnabledKey) != nil else {
            return defaultIsPauseMediaEnabled
        }

        return defaults.bool(forKey: isPauseMediaEnabledKey)
    }

    public static func savePauseMediaEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: isPauseMediaEnabledKey)
    }

    public static func isSoundFeedbackEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isSoundFeedbackEnabledKey) != nil else {
            return defaultIsSoundFeedbackEnabled
        }

        return defaults.bool(forKey: isSoundFeedbackEnabledKey)
    }

    public static func saveSoundFeedbackEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: isSoundFeedbackEnabledKey)
    }

    public static func isExperimentalFeaturesEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: experimentalFeaturesEnabledKey)
    }

    public static func saveExperimentalFeaturesEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: experimentalFeaturesEnabledKey)
    }

    public static func backupPreferences(
        isSoundFeedbackEnabled: Bool,
        isSystemMuteEnabled: Bool,
        isPauseMediaEnabled: Bool,
        audioResumptionDelay: Double,
        isExperimentalFeaturesEnabled: Bool
    ) -> VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkRecordingFeedbackBackupPreferences
    ) -> VoiceInkRecordingFeedbackBackupImportPlan {
        VoiceInkRecordingFeedbackBackupImportPlan(
            isSoundFeedbackEnabled: preferences.isSoundFeedbackEnabled,
            systemMuteMode: preferences.isSystemMuteEnabled.map { $0 ? .always : .never },
            isPauseMediaEnabled: preferences.isPauseMediaEnabled,
            audioResumptionDelay: preferences.audioResumptionDelay,
            isExperimentalFeaturesEnabled: preferences.isExperimentalFeaturesEnabled
        )
    }
}

public enum VoiceInkPasteMethod: String, CaseIterable, Identifiable, Sendable {
    case standard = "default"
    case appleScript = "appleScript"

    public static let userDefaultsKey = "pasteMethod"
    public static let legacyAppleScriptPasteKey = "useAppleScriptPaste"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard:
            return "Default"
        case .appleScript:
            return "AppleScript"
        }
    }

    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkPasteMethod {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let method = VoiceInkPasteMethod(rawValue: rawValue) {
            return method
        }

        return defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard
    }

    public static func selection(
        fromStoredRawValue storedRawValue: String?,
        in defaults: UserDefaults = .standard
    ) -> VoiceInkPasteMethod {
        if let storedRawValue, let method = VoiceInkPasteMethod(rawValue: storedRawValue) {
            return method
        }

        return current(in: defaults)
    }

    public static func setCurrent(_ method: VoiceInkPasteMethod, in defaults: UserDefaults = .standard) {
        defaults.set(method.rawValue, forKey: userDefaultsKey)
        defaults.set(method == .appleScript, forKey: legacyAppleScriptPasteKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           VoiceInkPasteMethod(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyAppleScriptPasteKey) ? .appleScript : .standard, in: defaults)
    }
}

public struct VoiceInkPasteDelayOption: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: TimeInterval

    public var id: TimeInterval { value }

    public init(label: String, value: TimeInterval) {
        self.label = label
        self.value = value
    }
}

public struct VoiceInkMacOSPasteSettingsPresentation: Equatable, Sendable {
    public let keepClipboardContentLabel: String
    public let keepClipboardContentInfoMessage: String
    public let restoreDelayLabel: String
    public let restoreDelayOptions: [VoiceInkPasteDelayOption]
    public let pasteMethodLabel: String
    public let pasteMethodHelpMessage: String

    public init(
        keepClipboardContentLabel: String,
        keepClipboardContentInfoMessage: String,
        restoreDelayLabel: String,
        restoreDelayOptions: [VoiceInkPasteDelayOption],
        pasteMethodLabel: String,
        pasteMethodHelpMessage: String
    ) {
        self.keepClipboardContentLabel = keepClipboardContentLabel
        self.keepClipboardContentInfoMessage = keepClipboardContentInfoMessage
        self.restoreDelayLabel = restoreDelayLabel
        self.restoreDelayOptions = restoreDelayOptions
        self.pasteMethodLabel = pasteMethodLabel
        self.pasteMethodHelpMessage = pasteMethodHelpMessage
    }
}

public struct VoiceInkPasteBackupPreferences: Codable, Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
}

public struct VoiceInkPasteBackupImportPlan: Equatable, Sendable {
    public let shouldRestoreClipboardAfterPaste: Bool?
    public let clipboardRestoreDelay: Double?

    public init(
        shouldRestoreClipboardAfterPaste: Bool?,
        clipboardRestoreDelay: Double?
    ) {
        self.shouldRestoreClipboardAfterPaste = shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = clipboardRestoreDelay
    }
}

public enum VoiceInkPastePreference {
    public static let restoreClipboardAfterPasteKey = "restoreClipboardAfterPaste"
    public static let clipboardRestoreDelayKey = "clipboardRestoreDelay"
    public static let defaultRestoreClipboardAfterPaste = true
    public static let defaultClipboardRestoreDelay: TimeInterval = 2.0
    public static let minimumClipboardRestoreDelay: TimeInterval = 0.25

    public static var registeredDefaults: [String: Any] {
        [
            restoreClipboardAfterPasteKey: defaultRestoreClipboardAfterPaste,
            clipboardRestoreDelayKey: defaultClipboardRestoreDelay,
            VoiceInkPasteMethod.legacyAppleScriptPasteKey: false
        ]
    }

    public static let macOSSettingsPresentation = VoiceInkMacOSPasteSettingsPresentation(
        keepClipboardContentLabel: "Keep Clipboard Content",
        keepClipboardContentInfoMessage: "VoiceInk temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard.",
        restoreDelayLabel: "Restore Delay",
        restoreDelayOptions: [
            VoiceInkPasteDelayOption(label: "250ms", value: 0.25),
            VoiceInkPasteDelayOption(label: "500ms", value: 0.5),
            VoiceInkPasteDelayOption(label: "1s", value: 1.0),
            VoiceInkPasteDelayOption(label: "2s", value: 2.0),
            VoiceInkPasteDelayOption(label: "3s", value: 3.0),
            VoiceInkPasteDelayOption(label: "4s", value: 4.0),
            VoiceInkPasteDelayOption(label: "5s", value: 5.0)
        ],
        pasteMethodLabel: "Paste Method",
        pasteMethodHelpMessage: "Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly."
    )

    public static func shouldRestoreClipboardAfterPaste(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: restoreClipboardAfterPasteKey)
    }

    public static func clipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        defaults.double(forKey: clipboardRestoreDelayKey)
    }

    public static func boundedClipboardRestoreDelay(from defaults: UserDefaults = .standard) -> TimeInterval {
        max(clipboardRestoreDelay(from: defaults), minimumClipboardRestoreDelay)
    }

    public static func saveShouldRestoreClipboardAfterPaste(
        _ value: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: restoreClipboardAfterPasteKey)
    }

    public static func saveClipboardRestoreDelay(
        _ value: TimeInterval,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: clipboardRestoreDelayKey)
    }

    public static func backupPreferences(
        shouldRestoreClipboardAfterPaste: Bool,
        clipboardRestoreDelay: Double
    ) -> VoiceInkPasteBackupPreferences {
        VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkPasteBackupPreferences
    ) -> VoiceInkPasteBackupImportPlan {
        VoiceInkPasteBackupImportPlan(
            shouldRestoreClipboardAfterPaste: preferences.shouldRestoreClipboardAfterPaste,
            clipboardRestoreDelay: preferences.clipboardRestoreDelay
        )
    }
}

public enum VoiceInkPasteDiagnostics {
    public static let failedToPrepareClipboardMessage = "Failed to prepare clipboard for paste"
    public static let skippedClipboardRestoreCommandNotPostedMessage = "Skipping clipboard restore because paste command was not posted"
    public static let appleScriptPasteScriptUnavailableMessage = "AppleScript paste script is unavailable"
    public static let accessibilityPermissionRequiredForSimulatedPasteMessage = "Accessibility permission is required to paste with simulated key events"
    public static let failedToCreateCommandVPasteEventsMessage = "Failed to create Cmd+V keyboard events"

    public static func appleScriptPasteFailedMessage(errorDescription: String) -> String {
        "AppleScript paste failed: \(errorDescription)"
    }
}

public struct VoiceInkMacOSAppendTrailingSpaceSettingsPresentation: Equatable, Sendable {
    public let toggleTitle: String
    public let helpText: String

    public static let macOS = VoiceInkMacOSAppendTrailingSpaceSettingsPresentation(
        toggleTitle: "Add Space After Paste",
        helpText: "Add a trailing space after pasted transcription output."
    )
}

public enum VoiceInkAppendTrailingSpacePreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.appendTrailingSpace
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.appendTrailingSpace
    public static let settingsPresentation = VoiceInkMacOSAppendTrailingSpaceSettingsPresentation.macOS
    public static let macOSSettingsPresentation = settingsPresentation

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultIsEnabled
        ]
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkContextualCapitalizationFormatter {
    public static func needsCursorContext(_ text: String) -> Bool {
        guard let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return false
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return false }

        return shouldUppercaseFirstCasedCharacter(in: firstWord) ||
            shouldLowercaseFirstCasedCharacter(in: firstWord)
    }

    public static func format(_ text: String, beforeCursor: String?) -> String {
        guard let beforeCursor,
              let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return text
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return text }

        switch boundary(beforeCursor) {
        case .sentenceStart:
            guard shouldUppercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).uppercased())
        case .midSentence:
            guard shouldLowercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).lowercased())
        }
    }

    private enum Boundary {
        case sentenceStart
        case midSentence
    }

    private static let sentenceTerminators = Set<Character>([".", "!", "?", "。", "！", "？"])
    private static let wordInternalCharacters = Set<Character>(["'", "’", "‘", "ʼ", "＇", "-"])

    private static func boundary(_ beforeCursor: String) -> Boundary {
        var index = beforeCursor.endIndex
        var sawTrailingNewline = false

        while index > beforeCursor.startIndex {
            let previousIndex = beforeCursor.index(before: index)
            let character = beforeCursor[previousIndex]

            if isWhitespace(character) {
                if containsNewline(character) {
                    sawTrailingNewline = true
                }
                index = previousIndex
                continue
            }

            if sawTrailingNewline || sentenceTerminators.contains(character) {
                return .sentenceStart
            }

            return .midSentence
        }

        return .sentenceStart
    }

    private static func firstCasedCharacterRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if isCasedLetter(text[index]) {
                return index..<nextIndex
            }
            index = nextIndex
        }
        return nil
    }

    private static func word(in text: String, startingAt startIndex: String.Index) -> String {
        var index = startIndex
        var result = ""

        while index < text.endIndex {
            let character = text[index]
            guard isWordCharacter(character) else { break }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func shouldUppercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard let first = letters.first,
              isLowercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func shouldLowercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard letters.count > 1,
              let first = letters.first,
              isUppercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func casedLetters(in word: String) -> [Character] {
        word.filter { isCasedLetter($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        isCasedLetter(character) ||
            wordInternalCharacters.contains(character) ||
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isCasedLetter(_ character: Character) -> Bool {
        let value = String(character)
        return value.lowercased() != value.uppercased()
    }

    private static func isLowercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.lowercased() && value != value.uppercased()
    }

    private static func isUppercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.uppercased() && value != value.lowercased()
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func containsNewline(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    private static func replacing(_ text: String, range: Range<String.Index>, with replacement: String) -> String {
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
    }
}

public enum VoiceInkTranscriptionPasteOutputPolicy {
    public static let trialExpiredPrefix = "Your trial has expired. Upgrade to VoiceInk Pro at \(VoiceInkLicenseLinks.purchaseDisplayURLString)"

    public struct PasteDecision: Equatable, Sendable {
        public let textToPaste: String?
        public let shouldPlayCompletionSoundWithoutPaste: Bool
    }

    public static func shouldPaste(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func decision(
        text: String?,
        transcriptionCompleted: Bool
    ) -> PasteDecision {
        guard transcriptionCompleted, let text else {
            return PasteDecision(
                textToPaste: nil,
                shouldPlayCompletionSoundWithoutPaste: false
            )
        }
        guard shouldPaste(text) else {
            return PasteDecision(
                textToPaste: nil,
                shouldPlayCompletionSoundWithoutPaste: true
            )
        }
        return PasteDecision(
            textToPaste: text,
            shouldPlayCompletionSoundWithoutPaste: false
        )
    }

    public struct CursorPasteTextPlan: Equatable, Sendable {
        public let text: String
        public let shouldReadCursorContext: Bool

        public init(text: String, shouldReadCursorContext: Bool) {
            self.text = text
            self.shouldReadCursorContext = shouldReadCursorContext
        }

        public func text(beforeCursor: String?) -> String {
            guard shouldReadCursorContext else { return text }
            return VoiceInkContextualCapitalizationFormatter.format(
                text,
                beforeCursor: beforeCursor
            )
        }
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        shouldLowercase: Bool
    ) -> CursorPasteTextPlan {
        CursorPasteTextPlan(
            text: text,
            shouldReadCursorContext: !shouldLowercase
                && VoiceInkContextualCapitalizationFormatter.needsCursorContext(text)
        )
    }

    public static func cursorPasteTextPlan(
        _ text: String,
        from defaults: UserDefaults = .standard
    ) -> CursorPasteTextPlan {
        cursorPasteTextPlan(
            text,
            shouldLowercase: VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults)
        )
    }

    public static func finalPastedText(
        _ text: String,
        appendTrailingSpace: Bool,
        isTrialExpired: Bool
    ) -> String {
        let textWithLicensePrefix = isTrialExpired
            ? "\(trialExpiredPrefix)\n\n\(text)"
            : text

        return textWithLicensePrefix + (appendTrailingSpace ? " " : "")
    }
}

public enum VoiceInkCursorTextContextPolicy {
    public static let defaultMaximumLength = 240
    public static let parentTraversalLimit = 4
    public static let textInputRoleNames: Set<String> = [
        "AXComboBox",
        "AXTextArea",
        "AXTextField"
    ]

    public static func shouldAttemptRead(maximumLength: Int = defaultMaximumLength) -> Bool {
        maximumLength > 0
    }

    public static func prefixLength(
        cursorLocation: Int,
        maximumLength: Int = defaultMaximumLength
    ) -> Int? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              cursorLocation >= 0 else {
            return nil
        }

        return min(maximumLength, cursorLocation)
    }

    public static func isTextInputRole(_ role: String?) -> Bool {
        guard let role else { return false }
        return textInputRoleNames.contains(role)
    }

    public static func valueSuffix(
        from text: String,
        role: String?,
        maximumLength: Int = defaultMaximumLength
    ) -> String? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              isTextInputRole(role) else {
            return nil
        }

        guard text.count > maximumLength else {
            return text
        }

        return String(text.suffix(maximumLength))
    }

    public static func boundedSuffix(
        _ text: String?,
        maximumLength: Int = defaultMaximumLength
    ) -> String? {
        guard shouldAttemptRead(maximumLength: maximumLength),
              let text,
              !text.isEmpty else {
            return nil
        }

        return String(text.suffix(maximumLength))
    }
}

public enum VoiceInkPreferenceList {
    public static func changedElements<Element: Equatable>(
        from currentElements: [Element],
        to proposedElements: [Element]
    ) -> [Element]? {
        currentElements == proposedElements ? nil : proposedElements
    }

    public static func removing<Element>(at offsets: IndexSet, from elements: [Element]) -> [Element] {
        var updatedElements = elements

        for index in offsets.sorted(by: >) where updatedElements.indices.contains(index) {
            updatedElements.remove(at: index)
        }

        return updatedElements
    }
}

public struct VoiceInkSettingsPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let modesSectionTitle: String
    public let addModeButtonTitle: String
    public let addActionSystemImageName: String

    public static let iOS = VoiceInkSettingsPresentation(
        navigationTitle: "Settings",
        modesSectionTitle: "Modes",
        addModeButtonTitle: "Add New Mode",
        addActionSystemImageName: "plus.circle.fill"
    )
}

public struct VoiceInkMacOSSettingsPresentation: Equatable, Sendable {
    public let generalSectionTitle: String
    public let menuBarTitle: String
    public let dockIconTitle: String
    public let showVisibilityValueTitle: String
    public let hideVisibilityValueTitle: String
    public let launchAtLoginTitle: String
    public let autoCheckUpdatesTitle: String
    public let showAnnouncementsTitle: String
    public let checkForUpdatesButtonTitle: String
    public let privacySectionTitle: String
    public let privacyFooterText: String
    public let backupSectionTitle: String
    public let backupFooterText: String
    public let exportSettingsLabel: String
    public let exportButtonTitle: String
    public let importSettingsLabel: String
    public let importButtonTitle: String
    public let diagnosticsSectionTitle: String

    public static let macOS = VoiceInkMacOSSettingsPresentation(
        generalSectionTitle: "General",
        menuBarTitle: "Menu Bar",
        dockIconTitle: "Dock Icon",
        showVisibilityValueTitle: "Show",
        hideVisibilityValueTitle: "Hide",
        launchAtLoginTitle: "Launch at Login",
        autoCheckUpdatesTitle: "Auto-check Updates",
        showAnnouncementsTitle: "Show Announcements",
        checkForUpdatesButtonTitle: "Check for Updates",
        privacySectionTitle: "Privacy",
        privacyFooterText: "Control how VoiceInk handles your transcription data and audio recordings.",
        backupSectionTitle: "Backup",
        backupFooterText: "Export all settings, or choose specific categories when importing a backup.",
        exportSettingsLabel: "Export Settings",
        exportButtonTitle: "Export",
        importSettingsLabel: "Import Settings",
        importButtonTitle: "Import",
        diagnosticsSectionTitle: "Diagnostics"
    )

    public func visibilityValueTitle(isVisible: Bool) -> String {
        isVisible ? showVisibilityValueTitle : hideVisibilityValueTitle
    }
}

public enum VoiceInkSettingsBackupCategory: String, CaseIterable, Hashable, Sendable {
    case general
    case prompts
    case powerMode
    case dictionary
    case customModels

    public var title: String {
        switch self {
        case .general:
            return "General Settings"
        case .prompts:
            return "Custom Prompts"
        case .powerMode:
            return "Power Mode"
        case .dictionary:
            return "Dictionary"
        case .customModels:
            return "Custom Model Definitions"
        }
    }
}

public enum VoiceInkSettingsBackupImportPolicy {
    public static let fallbackVersion = "0.0.0"

    public static func currentVersion(bundleShortVersion: String?) -> String {
        bundleShortVersion ?? fallbackVersion
    }

    public static func categorySummary(for categories: Set<VoiceInkSettingsBackupCategory>) -> String {
        if categories == Set(VoiceInkSettingsBackupCategory.allCases) {
            return "All settings"
        }

        return VoiceInkSettingsBackupCategory.allCases
            .filter { categories.contains($0) }
            .map(\.title)
            .joined(separator: ", ")
    }

    public static func needsAPIKeyReminder(for categories: Set<VoiceInkSettingsBackupCategory>) -> Bool {
        !categories.isDisjoint(with: [.prompts, .powerMode, .customModels])
    }

    public static func versionReview(
        importedVersion: String,
        currentVersion: String
    ) -> VoiceInkSettingsBackupVersionReview {
        VoiceInkSettingsBackupVersionReview(
            importedVersion: importedVersion,
            currentVersion: currentVersion
        )
    }

    public static func importSelectionReview(
        selectedCategories: Set<VoiceInkSettingsBackupCategory>?
    ) -> VoiceInkSettingsBackupImportSelectionReview {
        VoiceInkSettingsBackupImportSelectionReview(
            selectedCategories: selectedCategories
        )
    }

    public static func importSuccessPlan(
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> VoiceInkSettingsBackupImportSuccessPlan {
        VoiceInkSettingsBackupImportSuccessPlan(categories: categories)
    }
}

public struct VoiceInkSettingsBackupVersionReview: Equatable, Sendable {
    public let importedVersion: String
    public let currentVersion: String

    public var hasMismatch: Bool {
        importedVersion != currentVersion
    }

    public init(importedVersion: String, currentVersion: String) {
        self.importedVersion = importedVersion
        self.currentVersion = currentVersion
    }

    public func applyRuntimeState(
        reportVersionMismatch: (_ importedVersion: String, _ currentVersion: String) -> Void
    ) {
        guard hasMismatch else { return }
        reportVersionMismatch(importedVersion, currentVersion)
    }
}

public enum VoiceInkSettingsBackupImportSelectionReview: Equatable, Sendable {
    case canceled
    case emptySelection
    case selected(Set<VoiceInkSettingsBackupCategory>)

    public init(selectedCategories: Set<VoiceInkSettingsBackupCategory>?) {
        guard let selectedCategories else {
            self = .canceled
            return
        }

        if selectedCategories.isEmpty {
            self = .emptySelection
        } else {
            self = .selected(selectedCategories)
        }
    }

    public func applyRuntimeState(
        reportNoSettingsImported: () -> Void,
        reportEmptyCategorySelection: () -> Void,
        importSelectedCategories: (Set<VoiceInkSettingsBackupCategory>) throws -> Void
    ) rethrows {
        switch self {
        case .canceled:
            reportNoSettingsImported()
        case .emptySelection:
            reportEmptyCategorySelection()
        case .selected(let categories):
            try importSelectedCategories(categories)
        }
    }
}

public struct VoiceInkSettingsBackupImportSuccessPlan: Equatable, Sendable {
    public let categories: Set<VoiceInkSettingsBackupCategory>

    public var isConfigureAPIKeysActionVisible: Bool {
        VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories)
    }

    public init(categories: Set<VoiceInkSettingsBackupCategory>) {
        self.categories = categories
    }

    public func applyRuntimeState(
        selectedConfigureAPIKeysAction: Bool,
        navigateToAPIKeySettings: () -> Void
    ) {
        guard isConfigureAPIKeysActionVisible,
              selectedConfigureAPIKeysAction else { return }
        navigateToAPIKeySettings()
    }
}

public enum VoiceInkSettingsBackupImportDiagnostics {
    public static let noGeneralSettingsMessage = "No general settings found in the imported file."
    public static let noVocabularyWordsMessage = "No vocabulary words found in the imported file. Existing items remain unchanged."
    public static let noWordReplacementsMessage = "No word replacements found in the imported file. Existing replacements remain unchanged."
    public static let noDictionaryEntriesImportedMessage = "No new dictionary entries were imported."
    public static let generalSettingsImportedMessage = "Successfully imported general settings."
    public static let noCustomModelsMessage = "No custom models found in the imported file."

    public static func saveFailedDescription(item: String, localizedDescription: String) -> String {
        "Failed to save imported \(item): \(localizedDescription)"
    }

    public static func customPromptsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom prompts."
    }

    public static func powerModeConfigurationsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) Power Mode configurations."
    }

    public static func skippedInvalidReplacementsMessage(count: Int) -> String {
        "Skipped \(count) invalid word replacements from the imported file."
    }

    public static func dictionaryEntriesImportedMessage(
        vocabularyWordCount: Int,
        wordReplacementCount: Int
    ) -> String {
        "Successfully imported \(vocabularyWordCount) vocabulary words and \(wordReplacementCount) word replacements to SwiftData."
    }

    public static func customModelsImportedMessage(count: Int) -> String {
        "Successfully imported \(count) custom model definitions."
    }
}

public enum VoiceInkSettingsBackupImportError: LocalizedError, Sendable {
    case saveFailed(item: String, localizedDescription: String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let item, let localizedDescription):
            VoiceInkSettingsBackupImportDiagnostics.saveFailedDescription(
                item: item,
                localizedDescription: localizedDescription
            )
        }
    }
}

public struct VoiceInkSettingsBackupFile<ShortcutBackup: Codable>: Codable {
    public let version: String
    public let customPrompts: [VoiceInkCustomPrompt]
    public let powerModeConfigs: [PowerModeConfig]
    public let powerModeShortcuts: [String: ShortcutBackup]?
    public let vocabularyWords: [VoiceInkVocabularyWordBackup]?
    public let wordReplacements: [String: String]?
    public let generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?
    public let customEmojis: [String]?
    public let customCloudModels: [VoiceInkCustomCloudModelBackup]?

    private enum CodingKeys: String, CodingKey {
        case version
        case customPrompts
        case powerModeConfigs
        case powerModeShortcuts
        case vocabularyWords
        case wordReplacements
        case generalSettings
        case customEmojis
        case customCloudModels
    }

    public init(
        version: String,
        customPrompts: [VoiceInkCustomPrompt],
        powerModeConfigs: [PowerModeConfig],
        powerModeShortcuts: [String: ShortcutBackup]?,
        vocabularyWords: [VoiceInkVocabularyWordBackup]?,
        wordReplacements: [String: String]?,
        generalSettings: VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>?,
        customEmojis: [String]?,
        customCloudModels: [VoiceInkCustomCloudModelBackup]?
    ) {
        self.version = version
        self.customPrompts = customPrompts
        self.powerModeConfigs = powerModeConfigs
        self.powerModeShortcuts = powerModeShortcuts
        self.vocabularyWords = vocabularyWords
        self.wordReplacements = wordReplacements
        self.generalSettings = generalSettings
        self.customEmojis = customEmojis
        self.customCloudModels = customCloudModels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        customPrompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([VoiceInkVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([VoiceInkCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}

public enum VoiceInkSettingsBackupFileCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }

    public static func encode<ShortcutBackup: Codable>(
        _ backupFile: VoiceInkSettingsBackupFile<ShortcutBackup>,
        encoder: JSONEncoder = makeEncoder()
    ) throws -> Data {
        try encoder.encode(backupFile)
    }

    public static func decode<ShortcutBackup: Codable>(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> VoiceInkSettingsBackupFile<ShortcutBackup> {
        try decoder.decode(VoiceInkSettingsBackupFile<ShortcutBackup>.self, from: data)
    }
}

public struct VoiceInkGeneralSettingsBackupPayload<ShortcutBackup: Codable>: Codable {
    private let primaryRecordingShortcut: ShortcutBackup?
    private let secondaryRecordingShortcut: ShortcutBackup?
    private let pasteLastTranscriptionShortcut: ShortcutBackup?
    private let pasteLastEnhancementShortcut: ShortcutBackup?
    private let retryLastTranscriptionShortcut: ShortcutBackup?
    private let cancelRecorderShortcut: ShortcutBackup?
    private let openHistoryWindowShortcut: ShortcutBackup?
    private let quickAddToDictionaryShortcut: ShortcutBackup?
    private let toggleEnhancementShortcut: ShortcutBackup?
    private let primaryRecordingShortcutRawValue: String?
    private let secondaryRecordingShortcutRawValue: String?
    private let primaryRecordingShortcutModeRawValue: String?
    private let secondaryRecordingShortcutModeRawValue: String?
    private let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    private let isMiddleClickToggleEnabled: Bool?
    private let middleClickActivationDelay: Int?
    private let launchAtLoginEnabled: Bool?
    // Legacy backup wire field. Keep its inverted meaning so existing backup files round-trip.
    private let isMenuBarOnly: Bool?
    private let recorderType: String?
    private let isTranscriptionCleanupEnabled: Bool?
    private let transcriptionRetentionMinutes: Int?
    private let isAudioCleanupEnabled: Bool?
    private let audioRetentionPeriod: Int?
    private let isSoundFeedbackEnabled: Bool?
    private let isSystemMuteEnabled: Bool?
    private let isPauseMediaEnabled: Bool?
    private let audioResumptionDelay: Double?
    private let isTextFormattingEnabled: Bool?
    private let punctuationCleanupMode: PunctuationCleanupMode?
    private let removePunctuation: Bool?
    private let lowercaseTranscription: Bool?
    private let isExperimentalFeaturesEnabled: Bool?
    private let restoreClipboardAfterPaste: Bool?
    private let clipboardRestoreDelay: Double?

    public init(
        shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup],
        preferences: VoiceInkGeneralSettingsBackupPreferences
    ) {
        self.primaryRecordingShortcut = shortcutBackupRecords[.primaryRecording]
        self.secondaryRecordingShortcut = shortcutBackupRecords[.secondaryRecording]
        self.pasteLastTranscriptionShortcut = shortcutBackupRecords[.pasteLastTranscription]
        self.pasteLastEnhancementShortcut = shortcutBackupRecords[.pasteLastEnhancement]
        self.retryLastTranscriptionShortcut = shortcutBackupRecords[.retryLastTranscription]
        self.cancelRecorderShortcut = shortcutBackupRecords[.cancelRecorder]
        self.openHistoryWindowShortcut = shortcutBackupRecords[.openHistoryWindow]
        self.quickAddToDictionaryShortcut = shortcutBackupRecords[.quickAddToDictionary]
        self.toggleEnhancementShortcut = shortcutBackupRecords[.toggleEnhancement]
        self.primaryRecordingShortcutRawValue = preferences.recordingShortcut.primaryRecordingShortcutRawValue
        self.secondaryRecordingShortcutRawValue = preferences.recordingShortcut.secondaryRecordingShortcutRawValue
        self.primaryRecordingShortcutModeRawValue = preferences.recordingShortcut.primaryRecordingShortcutModeRawValue
        self.secondaryRecordingShortcutModeRawValue = preferences.recordingShortcut.secondaryRecordingShortcutModeRawValue
        self.specialShortcutPasteLastTranscriptOnEmptyTap = preferences.recordingShortcut.specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = preferences.recordingShortcut.isMiddleClickToggleEnabled
        self.middleClickActivationDelay = preferences.recordingShortcut.middleClickActivationDelay
        self.launchAtLoginEnabled = preferences.macOSShell.launchAtLoginEnabled
        self.isMenuBarOnly = preferences.macOSShell.isMenuBarOnly
        self.recorderType = preferences.macOSShell.recorderType
        self.isTranscriptionCleanupEnabled = preferences.transcriptionAutoCleanup.isEnabled
        self.transcriptionRetentionMinutes = preferences.transcriptionAutoCleanup.retentionMinutes
        self.isAudioCleanupEnabled = preferences.audioCleanup.isEnabled
        self.audioRetentionPeriod = preferences.audioCleanup.retentionDays
        self.isSoundFeedbackEnabled = preferences.recordingFeedback.isSoundFeedbackEnabled
        self.isSystemMuteEnabled = preferences.recordingFeedback.isSystemMuteEnabled
        self.isPauseMediaEnabled = preferences.recordingFeedback.isPauseMediaEnabled
        self.audioResumptionDelay = preferences.recordingFeedback.audioResumptionDelay
        self.isTextFormattingEnabled = preferences.transcriptionCleanup.isTextFormattingEnabled
        self.punctuationCleanupMode = preferences.transcriptionCleanup.punctuationCleanupMode
        self.removePunctuation = preferences.transcriptionCleanup.removePunctuation
        self.lowercaseTranscription = preferences.transcriptionCleanup.lowercaseTranscription
        self.isExperimentalFeaturesEnabled = preferences.recordingFeedback.isExperimentalFeaturesEnabled
        self.restoreClipboardAfterPaste = preferences.paste.shouldRestoreClipboardAfterPaste
        self.clipboardRestoreDelay = preferences.paste.clipboardRestoreDelay
    }

    public var shortcutBackupRecords: [VoiceInkShortcutActionIdentifier: ShortcutBackup] {
        var records: [VoiceInkShortcutActionIdentifier: ShortcutBackup] = [:]
        records[.primaryRecording] = primaryRecordingShortcut
        records[.secondaryRecording] = secondaryRecordingShortcut
        records[.pasteLastTranscription] = pasteLastTranscriptionShortcut
        records[.pasteLastEnhancement] = pasteLastEnhancementShortcut
        records[.retryLastTranscription] = retryLastTranscriptionShortcut
        records[.cancelRecorder] = cancelRecorderShortcut
        records[.openHistoryWindow] = openHistoryWindowShortcut
        records[.quickAddToDictionary] = quickAddToDictionaryShortcut
        records[.toggleEnhancement] = toggleEnhancementShortcut
        return records
    }

    public var generalSettingsBackupPreferences: VoiceInkGeneralSettingsBackupPreferences {
        VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: recordingShortcutBackupPreferences,
            macOSShell: macOSShellBackupPreferences,
            transcriptionAutoCleanup: transcriptionAutoCleanupBackupPreferences,
            audioCleanup: audioCleanupBackupPreferences,
            recordingFeedback: recordingFeedbackBackupPreferences,
            transcriptionCleanup: transcriptionCleanupBackupPreferences,
            paste: pasteBackupPreferences
        )
    }

    private var recordingShortcutBackupPreferences: VoiceInkRecordingShortcutBackupPreferences {
        VoiceInkRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: primaryRecordingShortcutRawValue,
            secondaryRecordingShortcutRawValue: secondaryRecordingShortcutRawValue,
            primaryRecordingShortcutModeRawValue: primaryRecordingShortcutModeRawValue,
            secondaryRecordingShortcutModeRawValue: secondaryRecordingShortcutModeRawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: isMiddleClickToggleEnabled,
            middleClickActivationDelay: middleClickActivationDelay
        )
    }

    private var recordingFeedbackBackupPreferences: VoiceInkRecordingFeedbackBackupPreferences {
        VoiceInkRecordingFeedbackBackupPreferences(
            isSoundFeedbackEnabled: isSoundFeedbackEnabled,
            isSystemMuteEnabled: isSystemMuteEnabled,
            isPauseMediaEnabled: isPauseMediaEnabled,
            audioResumptionDelay: audioResumptionDelay,
            isExperimentalFeaturesEnabled: isExperimentalFeaturesEnabled
        )
    }

    private var macOSShellBackupPreferences: VoiceInkMacOSShellBackupPreferences {
        VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            showDockIcon: isMenuBarOnly.map { !$0 },
            recorderType: recorderType
        )
    }

    private var pasteBackupPreferences: VoiceInkPasteBackupPreferences {
        VoiceInkPasteBackupPreferences(
            shouldRestoreClipboardAfterPaste: restoreClipboardAfterPaste,
            clipboardRestoreDelay: clipboardRestoreDelay
        )
    }

    private var transcriptionAutoCleanupBackupPreferences: VoiceInkTranscriptionAutoCleanupBackupPreferences {
        VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: isTranscriptionCleanupEnabled,
            retentionMinutes: transcriptionRetentionMinutes
        )
    }

    private var audioCleanupBackupPreferences: VoiceInkAudioCleanupBackupPreferences {
        VoiceInkAudioCleanupBackupPreferences(
            isEnabled: isAudioCleanupEnabled,
            retentionDays: audioRetentionPeriod
        )
    }

    private var transcriptionCleanupBackupPreferences: VoiceInkTranscriptionCleanupBackupPreferences {
        VoiceInkTranscriptionCleanupBackupPreferences(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationCleanupMode: punctuationCleanupMode,
            removePunctuation: removePunctuation,
            lowercaseTranscription: lowercaseTranscription
        )
    }

}

public struct VoiceInkGeneralSettingsBackupPreferences: Equatable, Sendable {
    public let recordingShortcut: VoiceInkRecordingShortcutBackupPreferences
    public let macOSShell: VoiceInkMacOSShellBackupPreferences
    public let transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences
    public let audioCleanup: VoiceInkAudioCleanupBackupPreferences
    public let recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences
    public let transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences
    public let paste: VoiceInkPasteBackupPreferences

    public init(
        recordingShortcut: VoiceInkRecordingShortcutBackupPreferences,
        macOSShell: VoiceInkMacOSShellBackupPreferences,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: VoiceInkAudioCleanupBackupPreferences,
        recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences,
        paste: VoiceInkPasteBackupPreferences
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
    }
}

public struct VoiceInkGeneralSettingsBackupImportPlans: Equatable, Sendable {
    fileprivate let recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan
    fileprivate let macOSShell: VoiceInkMacOSShellBackupImportPlan
    fileprivate let transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan
    fileprivate let audioCleanup: VoiceInkAudioCleanupBackupImportPlan
    fileprivate let recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan
    fileprivate let transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan
    fileprivate let paste: VoiceInkPasteBackupImportPlan

    public init(
        recordingShortcut: VoiceInkRecordingShortcutBackupImportPlan,
        macOSShell: VoiceInkMacOSShellBackupImportPlan,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupImportPlan,
        audioCleanup: VoiceInkAudioCleanupBackupImportPlan,
        recordingFeedback: VoiceInkRecordingFeedbackBackupImportPlan,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupImportPlan,
        paste: VoiceInkPasteBackupImportPlan
    ) {
        self.recordingShortcut = recordingShortcut
        self.macOSShell = macOSShell
        self.transcriptionAutoCleanup = transcriptionAutoCleanup
        self.audioCleanup = audioCleanup
        self.recordingFeedback = recordingFeedback
        self.transcriptionCleanup = transcriptionCleanup
        self.paste = paste
    }

    public func applyRuntimeState(
        to defaults: UserDefaults = .standard,
        applyRecordingShortcutImportPlan: (VoiceInkRecordingShortcutBackupImportPlan) -> Void,
        applyMacOSShellImportPlan: (VoiceInkMacOSShellBackupImportPlan) -> Void,
        applyRecordingFeedbackImportPlan: (VoiceInkRecordingFeedbackBackupImportPlan) -> Void,
        reportImportedGeneralSettings: () -> Void
    ) {
        applyRecordingShortcutImportPlan(recordingShortcut)
        applyMacOSShellImportPlan(macOSShell)
        applyRecordingFeedbackImportPlan(recordingFeedback)

        VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
            self,
            to: defaults
        )
        reportImportedGeneralSettings()
    }
}

public enum VoiceInkGeneralSettingsBackupPolicy {
    public static func backupPreferences(
        recordingShortcut: VoiceInkRecordingShortcutBackupPreferences,
        macOSShell: VoiceInkMacOSShellBackupPreferences,
        transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupBackupPreferences,
        audioCleanup: VoiceInkAudioCleanupBackupPreferences,
        recordingFeedback: VoiceInkRecordingFeedbackBackupPreferences,
        transcriptionCleanup: VoiceInkTranscriptionCleanupBackupPreferences,
        paste: VoiceInkPasteBackupPreferences
    ) -> VoiceInkGeneralSettingsBackupPreferences {
        VoiceInkGeneralSettingsBackupPreferences(
            recordingShortcut: recordingShortcut,
            macOSShell: macOSShell,
            transcriptionAutoCleanup: transcriptionAutoCleanup,
            audioCleanup: audioCleanup,
            recordingFeedback: recordingFeedback,
            transcriptionCleanup: transcriptionCleanup,
            paste: paste
        )
    }

    public static func importPlans(
        from preferences: VoiceInkGeneralSettingsBackupPreferences
    ) -> VoiceInkGeneralSettingsBackupImportPlans {
        VoiceInkGeneralSettingsBackupImportPlans(
            recordingShortcut: VoiceInkRecordingShortcutPreference.backupImportPlan(
                from: preferences.recordingShortcut
            ),
            macOSShell: VoiceInkMacOSShellBackupPreference.backupImportPlan(
                from: preferences.macOSShell
            ),
            transcriptionAutoCleanup: VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: preferences.transcriptionAutoCleanup
            ),
            audioCleanup: VoiceInkAudioCleanupPreference.backupImportPlan(
                from: preferences.audioCleanup
            ),
            recordingFeedback: VoiceInkRecordingFeedbackPreference.backupImportPlan(
                from: preferences.recordingFeedback
            ),
            transcriptionCleanup: VoiceInkTranscriptionCleanupSettings.backupImportPlan(
                from: preferences.transcriptionCleanup
            ),
            paste: VoiceInkPastePreference.backupImportPlan(
                from: preferences.paste
            )
        )
    }

    public static func applyCorePreferenceImportPlans(
        _ importPlans: VoiceInkGeneralSettingsBackupImportPlans,
        to defaults: UserDefaults = .standard
    ) {
        applyTranscriptionAutoCleanupImportPlan(importPlans.transcriptionAutoCleanup, to: defaults)
        applyAudioCleanupImportPlan(importPlans.audioCleanup, to: defaults)
        applyRecordingFeedbackCorePreferenceImportPlan(importPlans.recordingFeedback, to: defaults)
        applyTranscriptionCleanupImportPlan(importPlans.transcriptionCleanup, to: defaults)
        applyPasteImportPlan(importPlans.paste, to: defaults)
    }

    private static func applyTranscriptionAutoCleanupImportPlan(
        _ importPlan: VoiceInkTranscriptionAutoCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionMinutes = importPlan.retentionMinutes {
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(retentionMinutes, to: defaults)
        }
    }

    private static func applyAudioCleanupImportPlan(
        _ importPlan: VoiceInkAudioCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isEnabled = importPlan.isEnabled {
            VoiceInkAudioCleanupPreference.saveIsEnabled(isEnabled, to: defaults)
        }
        if let retentionDays = importPlan.retentionDays {
            VoiceInkAudioCleanupPreference.saveRetentionDays(retentionDays, to: defaults)
        }
    }

    private static func applyRecordingFeedbackCorePreferenceImportPlan(
        _ importPlan: VoiceInkRecordingFeedbackBackupImportPlan,
        to defaults: UserDefaults
    ) {
        importPlan.applyCorePreferenceState { isExperimentalFeaturesEnabled in
            VoiceInkRecordingFeedbackPreference.saveExperimentalFeaturesEnabled(
                isExperimentalFeaturesEnabled,
                to: defaults
            )
        }
    }

    private static func applyTranscriptionCleanupImportPlan(
        _ importPlan: VoiceInkTranscriptionCleanupBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let isTextFormattingEnabled = importPlan.isTextFormattingEnabled {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(
                isTextFormattingEnabled,
                to: defaults
            )
        }
        if let punctuationCleanupMode = importPlan.punctuationCleanupMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode, in: defaults)
        }
        if let lowercaseTranscription = importPlan.lowercaseTranscription {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(
                lowercaseTranscription,
                to: defaults
            )
        }
    }

    private static func applyPasteImportPlan(
        _ importPlan: VoiceInkPasteBackupImportPlan,
        to defaults: UserDefaults
    ) {
        if let shouldRestoreClipboardAfterPaste = importPlan.shouldRestoreClipboardAfterPaste {
            VoiceInkPastePreference.saveShouldRestoreClipboardAfterPaste(
                shouldRestoreClipboardAfterPaste,
                to: defaults
            )
        }
        if let clipboardRestoreDelay = importPlan.clipboardRestoreDelay {
            VoiceInkPastePreference.saveClipboardRestoreDelay(clipboardRestoreDelay, to: defaults)
        }
    }
}

public struct VoiceInkSettingsBackupPresentation: Equatable, Sendable {
    public let defaultFileName: String
    public let exportPanelTitle: String
    public let exportPanelMessage: String
    public let importPanelTitle: String
    public let importPanelMessage: String
    public let importSelectionTitle: String
    public let importSelectionMessage: String
    public let allCategoriesTitle: String
    public let individualCategoriesTitle: String
    public let importActionTitle: String
    public let cancelActionTitle: String
    public let okActionTitle: String
    public let configureAPIKeysActionTitle: String
    public let exportSuccessTitle: String
    public let exportErrorTitle: String
    public let exportCanceledTitle: String
    public let importCanceledTitle: String
    public let importErrorTitle: String
    public let versionMismatchTitle: String
    public let importSuccessTitle: String
    public let exportCanceledMessage: String
    public let importCanceledMessage: String
    public let noSettingsImportedMessage: String
    public let missingFileURLMessage: String
    public let emptyCategorySelectionMessage: String
    public let apiKeyReminderText: String
    public let restartRecommendationText: String

    public static let macOS = VoiceInkSettingsBackupPresentation(
        defaultFileName: "VoiceInk_Settings_Backup.json",
        exportPanelTitle: "Export VoiceInk Settings",
        exportPanelMessage: "Choose a location to save your settings.",
        importPanelTitle: "Import VoiceInk Settings",
        importPanelMessage: "Choose a settings backup, then select what you want to import.",
        importSelectionTitle: "Import Settings",
        importSelectionMessage: "Choose what to import from this backup.",
        allCategoriesTitle: "All",
        individualCategoriesTitle: "Individual categories",
        importActionTitle: "Import",
        cancelActionTitle: "Cancel",
        okActionTitle: "OK",
        configureAPIKeysActionTitle: "Configure API Keys",
        exportSuccessTitle: "Export Successful",
        exportErrorTitle: "Export Error",
        exportCanceledTitle: "Export Canceled",
        importCanceledTitle: "Import Canceled",
        importErrorTitle: "Import Error",
        versionMismatchTitle: "Version Mismatch",
        importSuccessTitle: "Import Successful",
        exportCanceledMessage: "The settings export operation was canceled.",
        importCanceledMessage: "The settings import operation was canceled.",
        noSettingsImportedMessage: "No settings were imported.",
        missingFileURLMessage: "Could not get the file URL from the open panel.",
        emptyCategorySelectionMessage: "Select at least one category to import.",
        apiKeyReminderText: "IMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.",
        restartRecommendationText: "It is recommended to restart VoiceInk for all changes to take full effect."
    )

    public func exportSuccessMessage(fileName: String) -> String {
        "Your settings have been successfully exported to \(fileName)."
    }

    public func exportSaveFailureMessage(localizedDescription: String) -> String {
        "Could not save settings to file: \(localizedDescription)"
    }

    public func exportEncodingFailureMessage(localizedDescription: String) -> String {
        "Could not encode settings to JSON: \(localizedDescription)"
    }

    public func versionMismatchMessage(importedVersion: String, currentVersion: String) -> String {
        "The imported settings file (version \(importedVersion)) is from a different version than your application (version \(currentVersion)). Proceeding with import, but be aware of potential incompatibilities."
    }

    public func importSuccessMessage(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        "Settings imported successfully from \(fileName).\n\nImported: \(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))."
    }

    public func importFailureMessage(localizedDescription: String) -> String {
        "Error importing settings: \(localizedDescription). The file might be corrupted or not in the correct format."
    }

    public func importSuccessInformativeText(
        fileName: String,
        categories: Set<VoiceInkSettingsBackupCategory>
    ) -> String {
        var informativeText = importSuccessMessage(fileName: fileName, categories: categories)
        if VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: categories) {
            informativeText += "\n\n\(apiKeyReminderText)"
        }
        informativeText += "\n\n\(restartRecommendationText)"
        return informativeText
    }
}

public struct VoiceInkEnhancementIntegerOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Int

    public var id: Int { value }
}

public struct VoiceInkEnhancementRetryOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let value: Bool

    public var id: Bool { value }
}

public struct VoiceInkEnhancementSettingsPresentation: Equatable, Sendable {
    public let title: String
    public let closeButtonHelp: String
    public let generalSectionTitle: String
    public let enableEnhancementTitle: String
    public let enableEnhancementHelp: String
    public let enableEnhancementLearnMoreURLString: String
    public let settingsButtonSystemImageName: String
    public let settingsButtonHelp: String
    public let promptsSectionTitle: String
    public let contextSectionTitle: String
    public let clipboardContextTitle: String
    public let clipboardContextHelp: String
    public let screenContextTitle: String
    public let screenContextHelp: String
    public let skipShortEnhancementTitle: String
    public let skipShortEnhancementHelp: String
    public let disclosureSystemImageName: String
    public let minimumWordsPickerTitle: String
    public let shortEnhancementWordOptions: [VoiceInkEnhancementIntegerOption]
    public let timeoutPickerTitle: String
    public let timeoutOptions: [VoiceInkEnhancementIntegerOption]
    public let timeoutRetryPickerTitle: String
    public let timeoutRetryOptions: [VoiceInkEnhancementRetryOption]
    public let requestTimeoutSectionTitle: String
    public let requestTimeoutHelp: String
    public let shortcutsSectionTitle: String
    public let toggleEnhancementShortcutTitle: String
    public let toggleEnhancementShortcutHelp: String
    public let switchPromptShortcutTitle: String
    public let switchPromptShortcutHelp: String
    public let shortcutLearnMoreURLString: String
    public let switchPromptKeyChipTitles: [String]

    public static let macOS = VoiceInkEnhancementSettingsPresentation(
        title: "Enhancement Settings",
        closeButtonHelp: "Close",
        generalSectionTitle: "General",
        enableEnhancementTitle: "Enable Enhancement",
        enableEnhancementHelp: "AI enhancement lets you pass the transcribed audio through LLMs to post-process using different prompts suitable for different use cases like e-mails, summary, writing, etc.",
        enableEnhancementLearnMoreURLString: "https://tryvoiceink.com/docs/enhancements-configuring-models",
        settingsButtonSystemImageName: "gear",
        settingsButtonHelp: "Enhancement settings",
        promptsSectionTitle: "Enhancement Prompts",
        contextSectionTitle: "Context",
        clipboardContextTitle: "Clipboard Context",
        clipboardContextHelp: "Use clipboard text to understand context for better enhancement.",
        screenContextTitle: "Screen Context",
        screenContextHelp: "Capture on-screen text to understand context for better enhancement.",
        skipShortEnhancementTitle: "Skip short transcriptions",
        skipShortEnhancementHelp: "Automatically skip AI enhancement when the transcription has very few words. Short phrases like \"yes\", \"thank you\", or quick commands don't benefit from enhancement.",
        disclosureSystemImageName: "chevron.right",
        minimumWordsPickerTitle: "Minimum words",
        shortEnhancementWordOptions: (1...15).map {
            VoiceInkEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
        },
        timeoutPickerTitle: "Timeout duration",
        timeoutOptions: [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
            VoiceInkEnhancementIntegerOption(title: "\($0) seconds", value: $0)
        },
        timeoutRetryPickerTitle: "On timeout",
        timeoutRetryOptions: [
            VoiceInkEnhancementRetryOption(title: "Fail immediately", value: false),
            VoiceInkEnhancementRetryOption(title: "Retry", value: true)
        ],
        requestTimeoutSectionTitle: "Request Timeout",
        requestTimeoutHelp: "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts).",
        shortcutsSectionTitle: "Shortcuts",
        toggleEnhancementShortcutTitle: "Toggle AI Enhancement",
        toggleEnhancementShortcutHelp: "Quickly enable or disable AI enhancement while recording. Available only when VoiceInk is running and the recorder is visible.",
        switchPromptShortcutTitle: "Switch Enhancement Prompt",
        switchPromptShortcutHelp: "Switch between your saved prompts using ⌘1 through ⌘0 to activate the corresponding prompt in the order they are saved. Available only when VoiceInk is running and the recorder is visible.",
        shortcutLearnMoreURLString: "https://tryvoiceink.com/docs/enhancement-shortcuts",
        switchPromptKeyChipTitles: ["⌘", "1 – 0"]
    )
}

public enum VoiceInkStartupPreferenceMigrationPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

public enum VoiceInkStartupPreferenceMigration {
    public static func migrateLegacyPreferences(
        for platform: VoiceInkStartupPreferenceMigrationPlatform,
        in defaults: UserDefaults = .standard
    ) {
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded(in: defaults)

        switch platform {
        case .iOS:
            break
        case .macOS:
            VoiceInkPasteMethod.migrateLegacyUserDefaultIfNeeded(in: defaults)
        }
    }
}

public enum VoiceInkMacOSLaunchAtLoginDefaultPolicy {
    public static let didApplyDefaultKey = VoiceInkUserDefaultsKey.didApplyLaunchAtLoginDefault
    public static let defaultDidApplyDefault = VoiceInkPreferenceDefault.didApplyLaunchAtLoginDefault

    public static var registeredDefaults: [String: Any] {
        [didApplyDefaultKey: defaultDidApplyDefault]
    }

    public static func shouldEnableByDefaultBeforeRegisteringDefaults(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        !VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults)
            && defaults.object(forKey: didApplyDefaultKey) == nil
    }

    public static func markDefaultApplied(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: didApplyDefaultKey)
    }
}

public struct VoiceInkDefaultSettings: Equatable, Sendable {
    public let audioSessionTimeoutSeconds: Int
    public let punctuationCleanupMode: PunctuationCleanupMode
    public let isTextFormattingEnabled: Bool
    public let isVADEnabled: Bool
    public let lowercaseTranscription: Bool
    public let removeFillerWords: Bool
    public let fillerWords: [String]
    public let selectedTranscriptionLanguage: String
    public let isTranscriptionCleanupEnabled: Bool
    public let transcriptionRetentionMinutes: Int
    public let isAudioCleanupEnabled: Bool
    public let audioRetentionDays: Int
    public let skipShortEnhancement: Bool
    public let shortEnhancementWordThreshold: Int
    public let enhancementTimeoutSeconds: Int
    public let enhancementRetryOnTimeout: Bool

    public init(
        audioSessionTimeoutSeconds: Int = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        isTextFormattingEnabled: Bool = VoiceInkPreferenceDefault.isTextFormattingEnabled,
        isVADEnabled: Bool = VoiceInkPreferenceDefault.isVADEnabled,
        lowercaseTranscription: Bool = VoiceInkPreferenceDefault.lowercaseTranscription,
        removeFillerWords: Bool = VoiceInkPreferenceDefault.removeFillerWords,
        fillerWords: [String] = VoiceInkFillerWords.defaultWords,
        selectedTranscriptionLanguage: String = VoiceInkLanguageCatalog.autoDetectCode,
        isTranscriptionCleanupEnabled: Bool = false,
        transcriptionRetentionMinutes: Int = VoiceInkPreferenceDefault.transcriptionRetentionMinutes,
        isAudioCleanupEnabled: Bool = false,
        audioRetentionDays: Int = VoiceInkPreferenceDefault.audioRetentionDays,
        skipShortEnhancement: Bool = VoiceInkPreferenceDefault.skipShortEnhancement,
        shortEnhancementWordThreshold: Int = VoiceInkPreferenceDefault.shortEnhancementWordThreshold,
        enhancementTimeoutSeconds: Int = VoiceInkPreferenceDefault.enhancementTimeoutSeconds,
        enhancementRetryOnTimeout: Bool = VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    ) {
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.punctuationCleanupMode = punctuationCleanupMode
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.isVADEnabled = isVADEnabled
        self.lowercaseTranscription = lowercaseTranscription
        self.removeFillerWords = removeFillerWords
        self.fillerWords = fillerWords
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.isTranscriptionCleanupEnabled = isTranscriptionCleanupEnabled
        self.transcriptionRetentionMinutes = transcriptionRetentionMinutes
        self.isAudioCleanupEnabled = isAudioCleanupEnabled
        self.audioRetentionDays = audioRetentionDays
        self.skipShortEnhancement = skipShortEnhancement
        self.shortEnhancementWordThreshold = shortEnhancementWordThreshold
        self.enhancementTimeoutSeconds = enhancementTimeoutSeconds
        self.enhancementRetryOnTimeout = enhancementRetryOnTimeout
    }

    public static let iOS = VoiceInkDefaultSettings()
    public static let macOS = VoiceInkDefaultSettings(
        selectedTranscriptionLanguage: VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
    )

    public var transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings {
        VoiceInkTranscriptionCleanupSettings(
            punctuationMode: punctuationCleanupMode,
            isTextFormattingEnabled: isTextFormattingEnabled,
            lowercaseTranscription: lowercaseTranscription,
            removeFillerWords: removeFillerWords
        )
    }

    public func registeredUserDefaults(
        hasCompletedOnboarding: Bool = false,
        currentTranscriptionModel: String? = nil
    ) -> [String: Any] {
        var defaults: [String: Any] = [
            VoiceInkUserDefaultsKey.hasCompletedOnboarding: hasCompletedOnboarding,
            VoiceInkUserDefaultsKey.isTextFormattingEnabled: isTextFormattingEnabled,
            VoiceInkUserDefaultsKey.isVADEnabled: isVADEnabled,
            VoiceInkUserDefaultsKey.removeFillerWords: removeFillerWords,
            PunctuationCleanupMode.legacyRemovePunctuationKey: punctuationCleanupMode == .removeAll,
            VoiceInkUserDefaultsKey.lowercaseTranscription: lowercaseTranscription,
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled: isTranscriptionCleanupEnabled,
            VoiceInkUserDefaultsKey.transcriptionRetentionMinutes: transcriptionRetentionMinutes,
            VoiceInkUserDefaultsKey.isAudioCleanupEnabled: isAudioCleanupEnabled,
            VoiceInkUserDefaultsKey.audioRetentionPeriodDays: audioRetentionDays,
            VoiceInkUserDefaultsKey.skipShortEnhancement: skipShortEnhancement,
            VoiceInkUserDefaultsKey.shortEnhancementWordThreshold: shortEnhancementWordThreshold,
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: enhancementTimeoutSeconds,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: enhancementRetryOnTimeout
        ]

        if let currentTranscriptionModel {
            defaults[VoiceInkUserDefaultsKey.currentTranscriptionModel] = currentTranscriptionModel
        }

        return defaults
    }

    public func registerUserDefaults(
        to defaults: UserDefaults = .standard,
        hasCompletedOnboarding: Bool = false,
        currentTranscriptionModel: String? = nil
    ) {
        defaults.register(defaults: registeredUserDefaults(
            hasCompletedOnboarding: hasCompletedOnboarding,
            currentTranscriptionModel: currentTranscriptionModel
        ))
    }
}

public struct VoiceInkAppSettingsResetState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: VoiceInkProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [VoiceInkWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String
    public let apiKeyProvidersToDelete: [VoiceInkProviderKind]

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: VoiceInkProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [VoiceInkWordReplacementRule],
        customVocabularyTerms: [String],
        selectedTranscriptionLanguage: String,
        apiKeyProvidersToDelete: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.apiKeyState = apiKeyState
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = transcriptionCleanupSettings
        self.fillerWords = fillerWords
        self.wordReplacements = wordReplacements
        self.customVocabularyTerms = customVocabularyTerms
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.apiKeyProvidersToDelete = apiKeyProvidersToDelete
    }

    private var applicationActions: [VoiceInkAppSettingsResetAction] {
        var actions: [VoiceInkAppSettingsResetAction] = [
            .applyResetState(self),
            .clearCoreUserSettings
        ]
        if !apiKeyProvidersToDelete.isEmpty {
            actions.append(.deleteProviderAPIKeys(apiKeyProvidersToDelete))
        }
        return actions
    }
}

fileprivate enum VoiceInkAppSettingsResetAction {
    case applyResetState(VoiceInkAppSettingsResetState)
    case clearCoreUserSettings
    case deleteProviderAPIKeys([VoiceInkProviderKind])
}

public extension VoiceInkAppSettingsResetState {
    func applyRuntimeState(
        setModes: ([Mode]) -> Void,
        setSelectedModeId: (UUID?) -> Void,
        setAPIKeyState: (VoiceInkProviderAPIKeyState) -> Void,
        setAudioSessionTimeoutSeconds: (Int) -> Void,
        setTranscriptionCleanupSettings: (VoiceInkTranscriptionCleanupSettings) -> Void,
        setFillerWords: ([String]) -> Void,
        setWordReplacements: ([VoiceInkWordReplacementRule]) -> Void,
        setCustomVocabularyTerms: ([String]) -> Void,
        setSelectedTranscriptionLanguage: (String) -> Void,
        clearCoreUserSettings: () -> Void,
        deleteProviderAPIKeys: ([VoiceInkProviderKind]) -> Void
    ) {
        for action in applicationActions {
            switch action {
            case .applyResetState(let resetState):
                setModes(resetState.modes)
                setSelectedModeId(resetState.selectedModeId)
                setAPIKeyState(resetState.apiKeyState)
                setAudioSessionTimeoutSeconds(resetState.audioSessionTimeoutSeconds)
                setTranscriptionCleanupSettings(resetState.transcriptionCleanupSettings)
                setFillerWords(resetState.fillerWords)
                setWordReplacements(resetState.wordReplacements)
                setCustomVocabularyTerms(resetState.customVocabularyTerms)
                setSelectedTranscriptionLanguage(resetState.selectedTranscriptionLanguage)
            case .clearCoreUserSettings:
                clearCoreUserSettings()
            case .deleteProviderAPIKeys(let providers):
                deleteProviderAPIKeys(providers)
            }
        }
    }
}

public struct VoiceInkIOSAppSettingsStartupState {
    public let modes: [Mode]
    public let selectedModeId: UUID?
    public let apiKeyState: VoiceInkProviderAPIKeyState
    public let audioSessionTimeoutSeconds: Int
    public let transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings
    public let fillerWords: [String]
    public let wordReplacements: [VoiceInkWordReplacementRule]
    public let customVocabularyTerms: [String]
    public let selectedTranscriptionLanguage: String

    public init(
        modes: [Mode],
        selectedModeId: UUID?,
        apiKeyState: VoiceInkProviderAPIKeyState,
        audioSessionTimeoutSeconds: Int,
        transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings,
        fillerWords: [String],
        wordReplacements: [VoiceInkWordReplacementRule],
        customVocabularyTerms: [String],
        selectedTranscriptionLanguage: String
    ) {
        self.modes = modes
        self.selectedModeId = selectedModeId
        self.apiKeyState = apiKeyState
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = transcriptionCleanupSettings
        self.fillerWords = fillerWords
        self.wordReplacements = wordReplacements
        self.customVocabularyTerms = customVocabularyTerms
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
    }
}

public enum VoiceInkIOSAppSettingsStartupPolicy {
    public static func state(
        from defaults: UserDefaults = .standard,
        verifiedProviders: Set<VoiceInkProviderKind>,
        loadStoredAPIKey: (VoiceInkProviderKind) -> String
    ) -> VoiceInkIOSAppSettingsStartupState {
        VoiceInkIOSAppSettingsStartupState(
            modes: VoiceInkModeStorage.loadModes(from: defaults),
            selectedModeId: VoiceInkModeStorage.loadSelectedModeId(from: defaults),
            apiKeyState: VoiceInkProviderAPIKeyState.loadingStoredKeys(
                verifiedProviders: verifiedProviders,
                loadStoredAPIKey: loadStoredAPIKey
            ),
            audioSessionTimeoutSeconds: VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
            transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings.current(in: defaults),
            fillerWords: VoiceInkFillerWordPreference.words(from: defaults),
            wordReplacements: VoiceInkWordReplacementPreference.rules(from: defaults),
            customVocabularyTerms: VoiceInkCustomVocabularyPreference.terms(from: defaults),
            selectedTranscriptionLanguage: VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults)
        )
    }
}

public struct VoiceInkIOSFirstTimeSetupPlan {
    private let modeSettingsRepairPlan: VoiceInkModeSettingsRepairPlan
    private let shouldSaveHasCompletedOnboarding: Bool

    public init(
        modeSettingsRepairPlan: VoiceInkModeSettingsRepairPlan,
        shouldSaveHasCompletedOnboarding: Bool
    ) {
        self.modeSettingsRepairPlan = modeSettingsRepairPlan
        self.shouldSaveHasCompletedOnboarding = shouldSaveHasCompletedOnboarding
    }

    private var applicationActions: [VoiceInkIOSFirstTimeSetupAction] {
        var actions: [VoiceInkIOSFirstTimeSetupAction] = [
            .applyModeSettingsRepair(modeSettingsRepairPlan)
        ]
        if shouldSaveHasCompletedOnboarding {
            actions.append(.saveHasCompletedOnboarding)
        }
        return actions
    }
}

fileprivate enum VoiceInkIOSFirstTimeSetupAction {
    case applyModeSettingsRepair(VoiceInkModeSettingsRepairPlan)
    case saveHasCompletedOnboarding
}

public extension VoiceInkIOSFirstTimeSetupPlan {
    func applyRuntimeState(
        applyModeSettingsRepair: (VoiceInkModeSettingsRepairPlan) -> Void,
        saveHasCompletedOnboarding: () -> Void
    ) {
        for action in applicationActions {
            switch action {
            case .applyModeSettingsRepair(let plan):
                applyModeSettingsRepair(plan)
            case .saveHasCompletedOnboarding:
                saveHasCompletedOnboarding()
            }
        }
    }
}

public enum VoiceInkIOSFirstTimeSetupPolicy {
    public static func plan(
        modes: [Mode],
        selectedModeId: UUID?,
        selectedTranscriptionLanguage: String
    ) -> VoiceInkIOSFirstTimeSetupPlan {
        VoiceInkIOSFirstTimeSetupPlan(
            modeSettingsRepairPlan: VoiceInkModeSettingsPolicy.defaultModeRepairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            ),
            shouldSaveHasCompletedOnboarding: true
        )
    }
}

public extension VoiceInkDefaultSettings {
    var appSettingsResetState: VoiceInkAppSettingsResetState {
        VoiceInkAppSettingsResetState(
            modes: [],
            selectedModeId: nil,
            apiKeyState: VoiceInkProviderAPIKeyState(),
            audioSessionTimeoutSeconds: audioSessionTimeoutSeconds,
            transcriptionCleanupSettings: transcriptionCleanupSettings,
            fillerWords: fillerWords,
            wordReplacements: [],
            customVocabularyTerms: [],
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            apiKeyProvidersToDelete: VoiceInkProviderKind.userAPIKeyProviders
        )
    }
}

public enum VoiceInkOnboardingPreference {
    public static func hasStoredCompletionState(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding) != nil
    }

    public static func hasCompletedOnboarding(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func saveHasCompletedOnboarding(
        _ completed: Bool = true,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(completed, forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }
}

public struct VoiceInkAudioSessionTimeoutPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let timeoutTitle: String
    public let detailText: String

    public static let iOS = VoiceInkAudioSessionTimeoutPresentation(
        sectionTitle: "Audio Settings",
        timeoutTitle: "Session Timeout",
        detailText: "How long to keep the microphone session active after recording stops. Longer timeouts prevent 'session activation failed' errors when recording frequently, but may use more battery."
    )
}

public enum VoiceInkAudioSessionDeactivationPlan: Equatable, Sendable {
    case immediate
    case delayed(TimeInterval)

    public var executionPlan: VoiceInkAudioSessionDeactivationExecutionPlan {
        switch self {
        case .immediate:
            return VoiceInkAudioSessionDeactivationExecutionPlan(action: .deactivateSession)
        case .delayed:
            return VoiceInkAudioSessionDeactivationExecutionPlan(action: .runCountdownTimer)
        }
    }
}

fileprivate enum VoiceInkAudioSessionDeactivationExecutionAction: Equatable, Sendable {
    case deactivateSession
    case runCountdownTimer
}

public struct VoiceInkAudioSessionDeactivationExecutionPlan: Equatable, Sendable {
    private let action: VoiceInkAudioSessionDeactivationExecutionAction

    fileprivate init(action: VoiceInkAudioSessionDeactivationExecutionAction) {
        self.action = action
    }

    public func applyRuntimeState(
        deactivateSession: () -> Void,
        runCountdownTimer: () -> Void,
        countdownTimerDidStart: () -> Void = {}
    ) {
        switch action {
        case .deactivateSession:
            deactivateSession()
        case .runCountdownTimer:
            runCountdownTimer()
            countdownTimerDidStart()
        }
    }
}

public enum VoiceInkMenuBarPreference {
    public static let showMenuBarIconKey = VoiceInkUserDefaultsKey.showMenuBarIcon
    public static let legacyIsMenuBarOnlyKey = VoiceInkUserDefaultsKey.legacyIsMenuBarOnly
    public static let defaultShowMenuBarIcon = VoiceInkPreferenceDefault.showMenuBarIcon
    public static let defaultShowDockIcon = VoiceInkPreferenceDefault.showDockIcon

    public static var registeredDefaults: [String: Any] {
        [
            showMenuBarIconKey: defaultShowMenuBarIcon,
            legacyIsMenuBarOnlyKey: !defaultShowDockIcon
        ]
    }

    public static func shouldShowMenuBarIcon(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showMenuBarIconKey)
    }

    public static func saveShowMenuBarIcon(_ shouldShow: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(shouldShow, forKey: showMenuBarIconKey)
    }

    public static func shouldShowDockIcon(from defaults: UserDefaults = .standard) -> Bool {
        guard let isMenuBarOnly = defaults.object(forKey: legacyIsMenuBarOnlyKey) as? Bool else {
            return defaultShowDockIcon
        }
        return !isMenuBarOnly
    }

    public static func saveShowDockIcon(_ shouldShow: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(!shouldShow, forKey: legacyIsMenuBarOnlyKey)
    }
}

public enum VoiceInkMacOSMenuBarPresentation {
    public static let toggleRecorderTitle = "Toggle Recorder"
    public static let manageModelsTitle = "Manage Models"
    public static let aiEnhancementToggleTitle = "AI Enhancement"
    public static let noProvidersConnectedText = "No providers connected"
    public static let noModelsAvailableText = "No models available"
    public static let audioInputTitle = "Audio Input"
    public static let noDevicesAvailableText = "No devices available"
    public static let additionalMenuTitle = "Additional"
    public static let clipboardContextTitle = VoiceInkEnhancementSettingsPresentation.macOS.clipboardContextTitle
    public static let contextAwarenessTitle = VoiceInkPowerModePresentation.contextAwarenessDisplayText
    public static let retryLastTranscriptionTitle = VoiceInkRecordingShortcutPreference.macOSSettingsPresentation.retryLastTranscriptionLabel
    public static let copyLastTranscriptionTitle = "Copy Last Transcription"
    public static let historyTitle = VoiceInkMacOSNavigationDestination.history.rawValue
    public static let permissionsTitle = VoiceInkMacOSNavigationDestination.permissions.rawValue
    public static let settingsTitle = VoiceInkMacOSNavigationDestination.settings.rawValue
    public static let showDockIconTitle = "Show Dock Icon"
    public static let hideDockIconTitle = "Hide Dock Icon"
    public static let hideMenuBarIconTitle = "Hide Menu Bar Icon"
    public static let launchAtLoginTitle = "Launch at Login"
    public static let checkForUpdatesTitle = "Check for Updates"
    public static let helpAndSupportTitle = "Help and Support"
    public static let selectionCheckmarkSystemImageName = "checkmark"
    public static let pickerSystemImageName = "chevron.up.chevron.down"

    public static var quitTitle: String {
        "Quit \(VoiceInkAppIdentity.compactDisplayName)"
    }

    public static func transcriptionModelTitle(currentDisplayName: String?) -> String {
        "Transcription Model: \(currentDisplayName ?? noneDisplayText)"
    }

    public static func promptTitle(activePromptTitle: String?) -> String {
        "Prompt: \(activePromptTitle ?? noneDisplayText)"
    }

    public static func aiProviderTitle(selectedProviderName: String) -> String {
        "AI Provider: \(selectedProviderName)"
    }

    public static func aiModelTitle(currentModelName: String) -> String {
        "AI Model: \(currentModelName)"
    }

    public static func dockIconTitle(showDockIcon: Bool) -> String {
        showDockIcon ? hideDockIconTitle : showDockIconTitle
    }

    private static let noneDisplayText = "None"
}

public enum VoiceInkMacOSMenuBarDiagnostics {
    public static let windowDidCloseAccessoryPolicyMessage = "windowDidClose: no visible windows, switching to .accessory policy"
    public static let focusMainWindowActivationPolicyMessage = "focusMainWindow: activation policy set to .regular"
    public static let focusMainWindowFailedMessage = "focusMainWindow: showMainWindow returned nil"
    public static let updateActivationPolicyAccessoryMessage = "updateAppActivationPolicy: switching to .accessory (dock icon hidden)"
    public static let updateActivationPolicyRegularMessage = "updateAppActivationPolicy: switching to .regular (dock icon visible)"
    public static let openMainWindowActivationPolicyMessage = "openMainWindowAndNavigate: activation policy set to .regular"
    public static let openHistoryWindowOpeningMessage = "openHistoryWindow: opening history window"
    public static let openHistoryWindowActivationPolicyMessage = "openHistoryWindow: activation policy set to .regular"

    public static func openMainWindowRequestedMessage(destination: String, showDockIcon: Bool) -> String {
        "openMainWindowAndNavigate: requested destination=\(destination), showDockIcon=\(showDockIcon)"
    }

    public static func openMainWindowFailedMessage(destination: String) -> String {
        "openMainWindowAndNavigate: showMainWindow returned nil — cannot navigate to \(destination)"
    }

    public static func openMainWindowPostingNavigationMessage(destination: String) -> String {
        "openMainWindowAndNavigate: window shown, posting navigation notification for \(destination)"
    }

    public static func openMainWindowNavigationPostedMessage(destination: String) -> String {
        "openMainWindowAndNavigate: navigation notification posted for \(destination)"
    }

    public static func openHistoryWindowDependenciesMissingMessage(
        hasModelContainer: Bool,
        hasEngine: Bool
    ) -> String {
        "openHistoryWindow: dependencies not configured (modelContainer=\(hasModelContainer), engine=\(hasEngine))"
    }
}

public struct VoiceInkMacOSShellBackupPreferences: Codable, Equatable, Sendable {
    public let launchAtLoginEnabled: Bool?
    // Legacy backup wire field. Runtime callers use the positive showDockIcon view.
    public let isMenuBarOnly: Bool?
    public let recorderType: String?

    public var showDockIcon: Bool? {
        isMenuBarOnly.map { !$0 }
    }

    public init(
        launchAtLoginEnabled: Bool?,
        showDockIcon: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.isMenuBarOnly = showDockIcon.map { !$0 }
        self.recorderType = recorderType
    }
}

public struct VoiceInkMacOSShellBackupImportPlan: Equatable, Sendable {
    private let launchAtLoginEnabled: Bool?
    private let showDockIcon: Bool?
    private let recorderType: String?

    public init(
        launchAtLoginEnabled: Bool?,
        showDockIcon: Bool?,
        recorderType: String?
    ) {
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.showDockIcon = showDockIcon
        self.recorderType = recorderType
    }

    public func applyRuntimeState(
        setLaunchAtLoginEnabled: (Bool) -> Void,
        setShowDockIcon: (Bool) -> Void,
        setRecorderType: (String) -> Void
    ) {
        if let launchAtLoginEnabled {
            setLaunchAtLoginEnabled(launchAtLoginEnabled)
        }
        if let showDockIcon {
            setShowDockIcon(showDockIcon)
        }
        if let recorderType {
            setRecorderType(recorderType)
        }
    }
}

public enum VoiceInkMacOSShellBackupPreference {
    public static func backupPreferences(
        launchAtLoginEnabled: Bool,
        showDockIcon: Bool,
        recorderType: String
    ) -> VoiceInkMacOSShellBackupPreferences {
        VoiceInkMacOSShellBackupPreferences(
            launchAtLoginEnabled: launchAtLoginEnabled,
            showDockIcon: showDockIcon,
            recorderType: recorderType
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkMacOSShellBackupPreferences
    ) -> VoiceInkMacOSShellBackupImportPlan {
        VoiceInkMacOSShellBackupImportPlan(
            launchAtLoginEnabled: preferences.launchAtLoginEnabled,
            showDockIcon: preferences.showDockIcon,
            recorderType: preferences.recorderType
        )
    }
}

public enum VoiceInkAudioSessionTimeoutPreference {
    public static let minimumSeconds = 0
    public static let maximumSeconds = 300
    public static let stepSeconds = 15
    public static let countdownUpdateInterval: TimeInterval = 1.0
    public static let settingsPresentation = VoiceInkAudioSessionTimeoutPresentation.iOS

    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
    }

    public static func displayText(for seconds: Int) -> String {
        "\(seconds)s"
    }

    public static func deactivationPlan(for seconds: Int) -> VoiceInkAudioSessionDeactivationPlan {
        seconds <= 0 ? .immediate : .delayed(TimeInterval(seconds))
    }

    public static func remainingTimeAfterCountdownTick(_ remainingTime: TimeInterval) -> TimeInterval {
        remainingTime - countdownUpdateInterval
    }

    public static func saveTimeoutSeconds(_ seconds: Int, to defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }
}

public struct VoiceInkSettingsTogglePresentation: Equatable, Sendable {
    public let title: String
    public let helpText: String
}

public struct VoiceInkMacOSAdvancedTranscriptionSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let vad: VoiceInkSettingsTogglePresentation
    public let modelPrewarm: VoiceInkSettingsTogglePresentation
    public let liveTextPreview: VoiceInkSettingsTogglePresentation

    public static let macOS = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation(
        sectionTitle: "Advanced",
        vad: VoiceInkSettingsTogglePresentation(
            title: "Voice Activity Detection (VAD)",
            helpText: "Use VAD inside batch/final transcription when supported."
        ),
        modelPrewarm: VoiceInkSettingsTogglePresentation(
            title: "Prewarm model (Experimental)",
            helpText: "Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization."
        ),
        liveTextPreview: VoiceInkSettingsTogglePresentation(
            title: "Show Transcript Preview",
            helpText: "Displays in-progress transcript text when the active model provides it."
        )
    )
}

public enum VoiceInkVADPreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.isVADEnabled
    public static let defaultIsEnabled = VoiceInkPreferenceDefault.isVADEnabled
    public static let settingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.vad
    public static let macOSSettingsPresentation = settingsPresentation

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsEnabled
    }

    public static func saveIsEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public struct VoiceInkMacOSLocalWhisperPromptSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let helpText: String
    public let learnMoreURLString: String
    public let saveButtonTitle: String
    public let editButtonTitle: String

    public static let macOS = VoiceInkMacOSLocalWhisperPromptSettingsPresentation(
        sectionTitle: "Output Format",
        helpText: "Only supported for local Whisper models. Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands.",
        learnMoreURLString: "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting",
        saveButtonTitle: "Save",
        editButtonTitle: "Edit"
    )
}

public struct VoiceInkLocalWhisperPromptDraftState: Equatable, Sendable {
    public var text: String
    public var isEditing: Bool

    public init(
        text: String = "",
        isEditing: Bool = false
    ) {
        self.text = text
        self.isEditing = isEditing
    }

    public func editing(prompt: String) -> VoiceInkLocalWhisperPromptDraftState {
        VoiceInkLocalWhisperPromptDraftState(text: prompt, isEditing: true)
    }

    public func saved() -> VoiceInkLocalWhisperPromptDraftState {
        VoiceInkLocalWhisperPromptDraftState(text: text, isEditing: false)
    }

    public func refreshingForSelectedLanguage(
        prompt: String
    ) -> VoiceInkLocalWhisperPromptDraftState {
        guard isEditing else {
            return self
        }
        return VoiceInkLocalWhisperPromptDraftState(text: prompt, isEditing: true)
    }
}

public enum VoiceInkLocalWhisperPromptCatalog {
    public static let customLanguagePromptsKey = "CustomLanguagePrompts"
    public static let settingsPresentation = VoiceInkMacOSLocalWhisperPromptSettingsPresentation.macOS
    public static let macOSSettingsPresentation = settingsPresentation

    public static func promptForSelectedLanguage(
        from defaults: UserDefaults = .standard,
        customPrompts: [String: String]? = nil,
        fallbackLanguage: String = "en"
    ) -> String {
        let language = VoiceInkTranscriptionLanguagePreference.selectedLanguage(
            from: defaults,
            fallback: fallbackLanguage
        )
        return prompt(for: language, customPrompts: customPrompts ?? storedCustomPrompts(from: defaults))
    }

    public static func prompt(for language: String, customPrompts: [String: String] = [:]) -> String {
        if let customPrompt = customPrompts[language], !customPrompt.isEmpty {
            return customPrompt
        }

        return defaultPrompt(for: language)
    }

    public static func storedCustomPrompts(from defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: customLanguagePromptsKey) as? [String: String] ?? [:]
    }

    public static func saveCustomPrompts(_ prompts: [String: String], to defaults: UserDefaults = .standard) {
        defaults.set(prompts, forKey: customLanguagePromptsKey)
    }

    public static func saveCustomPrompt(
        _ prompt: String,
        for language: String,
        to defaults: UserDefaults = .standard
    ) {
        var prompts = storedCustomPrompts(from: defaults)
        prompts[language] = prompt
        saveCustomPrompts(prompts, to: defaults)
    }

    public static func defaultPrompt(for language: String) -> String {
        defaultPromptsByLanguage[language] ?? defaultPromptsByLanguage["default"] ?? ""
    }

    private static let defaultPromptsByLanguage: [String: String] = [
        "en": "Hello, how are you doing? Nice to meet you.",
        "hi": "नमस्ते, कैसे हैं आप? आपसे मिलकर अच्छा लगा।",
        "bn": "নমস্কার, কেমন আছেন? আপনার সাথে দেখা হয়ে ভালো লাগলো।",
        "ja": "こんにちは、お元気ですか？お会いできて嬉しいです。",
        "ko": "안녕하세요, 잘 지내시나요? 만나서 반갑습니다.",
        "zh": "你好，最近好吗？见到你很高兴。",
        "th": "สวัสดีครับ/ค่ะ, สบายดีไหม? ยินดีที่ได้พบคุณ",
        "vi": "Xin chào, bạn khỏe không? Rất vui được gặp bạn.",
        "yue": "你好，最近點呀？見到你好開心。",
        "es": "¡Hola, ¿cómo estás? Encantado de conocerte.",
        "fr": "Bonjour, comment allez-vous? Ravi de vous rencontrer.",
        "de": "Hallo, wie geht es dir? Schön dich kennenzulernen.",
        "it": "Ciao, come stai? Piacere di conoscerti.",
        "pt": "Olá, como você está? Prazer em conhecê-lo.",
        "ru": "Здравствуйте, как ваши дела? Приятно познакомиться.",
        "pl": "Cześć, jak się masz? Miło cię poznać.",
        "nl": "Hallo, hoe gaat het? Aangenaam kennis te maken.",
        "tr": "Merhaba, nasılsın? Tanıştığımıza memnun oldum.",
        "ar": "مرحباً، كيف حالك؟ سعيد بلقائك.",
        "fa": "سلام، حال شما چطور است؟ از آشنایی با شما خوشوقتم.",
        "he": ",שלום, מה שלומך? נעים להכיר",
        "ta": "வணக்கம், எப்படி இருக்கிறீர்கள்? உங்களை சந்தித்ததில் மகிழ்ச்சி.",
        "te": "నమస్కారం, ఎలా ఉన్నారు? కలవడం చాలా సంతోషం.",
        "ml": "നമസ്കാരം, സുഖമാണോ? കണ്ടതിൽ സന്തോഷം.",
        "kn": "ನಮಸ್ಕಾರ, ಹೇಗಿದ್ದೀರಾ? ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಿ ಸಂತೋಷವಾಗಿದೆ.",
        "ur": "السلام علیکم، کیسے ہیں آپ؟ آپ سے مل کر خوشی ہوئی۔",
        "default": ""
    ]
}

public enum VoiceInkTranscriptionPromptPreference {
    public static func storedPrompt(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func localWhisperPrompt(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        storedPrompt(from: defaults) ?? fallback
    }

    public static func localWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard
    ) -> String {
        localWhisperPrompt(
            from: defaults,
            fallback: VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults)
        )
    }

    @discardableResult
    public static func saveLocalWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard,
        customPrompts: [String: String]? = nil,
        fallbackLanguage: String = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    ) -> String {
        let prompt = VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(
            from: defaults,
            customPrompts: customPrompts,
            fallbackLanguage: fallbackLanguage
        )
        savePrompt(prompt, to: defaults)
        return prompt
    }

    public static func saveLocalWhisperCustomPrompt(
        _ prompt: String,
        for language: String,
        to defaults: UserDefaults = .standard
    ) {
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(prompt, for: language, to: defaults)
        // Editing a model's fallback prompt must not replace the preferred language's prompt.
        if language == VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults) {
            saveLocalWhisperPromptForSelectedLanguage(from: defaults)
        }
    }

    public static func requestPrompt(from defaults: UserDefaults = .standard) -> String? {
        requestPrompt(storedPrompt(from: defaults))
    }

    public static func requestPrompt(
        forEffectiveLanguage language: String,
        from defaults: UserDefaults = .standard
    ) -> String? {
        guard language != VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults) else {
            return requestPrompt(from: defaults)
        }
        return requestPrompt(VoiceInkLocalWhisperPromptCatalog.prompt(
            for: language, customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults)
        ))
    }

    public static func requestPrompt(_ prompt: String?) -> String? {
        VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(prompt)
    }

    public static func savePrompt(_ prompt: String, to defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func clearPrompt(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }
}

public enum VoiceInkTranscriptionLanguagePreference {
    // SelectedLanguage stores user intent; model compatibility must never overwrite it.
    public static func storedLanguage(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func selectedLanguage(
        from defaults: UserDefaults = .standard,
        fallback: String = VoiceInkLanguageCatalog.autoDetectCode
    ) -> String {
        storedLanguage(from: defaults) ?? fallback
    }

    public static func selectedMacOSLanguage(from defaults: UserDefaults = .standard) -> String {
        selectedLanguage(
            from: defaults,
            fallback: VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
        )
    }

    public static func selectedLanguage(
        source: VoiceInkTranscriptionLanguageSource,
        from defaults: UserDefaults = .standard,
        isMultilingual: Bool = true,
        assemblyAIUsesRealtime: Bool = false
    ) -> String {
        VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            storedLanguage(from: defaults),
            source: source,
            isMultilingual: isMultilingual,
            assemblyAIUsesRealtime: assemblyAIUsesRealtime
        )
    }

    public static func effectiveLanguage(
        for model: VoiceInkTranscriptionLanguageSelectionFacts,
        from defaults: UserDefaults = .standard
    ) -> String {
        model.compatibleLanguage(storedLanguage(from: defaults))
    }

    public static func requestLanguage(
        for model: VoiceInkTranscriptionLanguageSelectionFacts,
        from defaults: UserDefaults = .standard
    ) -> String? {
        VoiceInkTranscriptionLanguageSupport.requestLanguage(effectiveLanguage(for: model, from: defaults))
    }

    public static func saveSelectedLanguage(
        _ language: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(language, forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func clearSelectedLanguage(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func requestLanguage(from defaults: UserDefaults = .standard) -> String? {
        VoiceInkTranscriptionLanguageSupport.requestLanguage(selectedLanguage(from: defaults))
    }
}

public enum VoiceInkCurrentTranscriptionModelPreference {
    static let legacyModelNameKey = "CurrentModel"

    public static func modelName(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func saveModelName(_ modelName: String, to defaults: UserDefaults = .standard) {
        defaults.set(modelName, forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func clearModelName(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
        defaults.removeObject(forKey: legacyModelNameKey)
    }

    public static func loadPlan(
        savedModelName: String?,
        candidateModelExists: Bool,
        isCandidateAvailableOnCurrentOS: Bool
    ) -> VoiceInkCurrentTranscriptionModelLoadPlan {
        VoiceInkCurrentTranscriptionModelLoadPlan(
            savedModelName: savedModelName,
            candidateModelExists: candidateModelExists,
            isCandidateAvailableOnCurrentOS: isCandidateAvailableOnCurrentOS
        )
    }
}

fileprivate enum VoiceInkCurrentTranscriptionModelLoadAction: Equatable, Sendable {
    case none
    case restoreSavedModel
    case clearStoredModelName
}

public struct VoiceInkCurrentTranscriptionModelLoadPlan: Equatable, Sendable {
    private let action: VoiceInkCurrentTranscriptionModelLoadAction

    public init(
        savedModelName: String?,
        candidateModelExists: Bool,
        isCandidateAvailableOnCurrentOS: Bool
    ) {
        guard savedModelName != nil, candidateModelExists else {
            self.action = .none
            return
        }

        self.action = isCandidateAvailableOnCurrentOS
            ? .restoreSavedModel
            : .clearStoredModelName
    }

    public func applyRuntimeState(
        clearStoredModelName: () -> Void,
        restoreSavedModel: () -> Void
    ) {
        switch action {
        case .none:
            break
        case .restoreSavedModel:
            restoreSavedModel()
        case .clearStoredModelName:
            clearStoredModelName()
        }
    }
}

public enum VoiceInkAIEnhancementPreference {
    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isAIEnhancementEnabled)
    }

    public static func statusDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        isEnabled(from: defaults) ? "Enabled" : "Disabled"
    }
}

public enum VoiceInkAIEnhancementContextPreference {
    public static func useClipboardContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.useClipboardContext)
    }

    public static func saveUseClipboardContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.useClipboardContext)
    }

    public static func useScreenCaptureContext(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }

    public static func saveUseScreenCaptureContext(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.useClipboardContext)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.useScreenCaptureContext)
    }
}

public enum VoiceInkAIEnhancementProviderPreference {
    public static let defaultSelectedProvider = VoiceInkAIEnhancementProviderKind.gemini

    public static func selectedProviderRawValue(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func selectedProviderDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        selectedProviderRawValue(from: defaults) ?? "None selected"
    }

    public static func saveSelectedProviderRawValue(_ rawValue: String, to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func saveSelectedProvider(
        _ provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedProviderRawValue(provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyProviderSelectionPlan(
        _ plan: VoiceInkAIEnhancementProviderSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementProviderKind {
        saveSelectedProvider(plan.selectedProviderToSave, to: defaults)
        return plan.selectedProviderToSave
    }

    public static func selectedProvider(
        default defaultProvider: VoiceInkAIEnhancementProviderKind = VoiceInkAIEnhancementProviderPreference.defaultSelectedProvider,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementProviderKind {
        guard let storedProvider = selectedProviderRawValue(from: defaults),
              let provider = VoiceInkAIEnhancementProviderKind(storedValue: storedProvider)
        else {
            return defaultProvider
        }

        if storedProvider != provider.rawValue {
            saveSelectedProviderRawValue(provider.rawValue, to: defaults)
        }

        return provider
    }

    public static func selectedModels(
        for providers: [VoiceInkAIEnhancementProviderKind] = VoiceInkAIEnhancementProviderKind.allCases,
        from defaults: UserDefaults = .standard
    ) -> [VoiceInkAIEnhancementProviderKind: String] {
        providers.reduce(into: [:]) { models, provider in
            if let model = selectedModel(for: provider.rawValue, from: defaults) {
                models[provider] = model
            }
        }
    }

    public static func selectedModel(
        for providerRawValue: String,
        from defaults: UserDefaults = .standard
    ) -> String? {
        let savedModel = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
        return savedModel?.isEmpty == false ? savedModel : nil
    }

    public static func selectedModelDiagnosticDescription(from defaults: UserDefaults = .standard) -> String {
        guard let providerRawValue = selectedProviderRawValue(from: defaults) else {
            return "None selected"
        }

        return selectedModel(for: providerRawValue, from: defaults) ?? "Default (\(providerRawValue))"
    }

    public static func saveSelectedModel(
        _ model: String,
        for providerRawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        guard !model.isEmpty else { return }
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
    }

    public static func saveSelectedModel(
        _ model: String,
        for provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) {
        saveSelectedModel(model, for: provider.rawValue, to: defaults)
    }

    @discardableResult
    public static func applyModelSelectionPlan(
        _ plan: VoiceInkAIEnhancementModelSelectionPlan,
        to defaults: UserDefaults = .standard
    ) -> String {
        saveSelectedModel(plan.selectedModelToSave, for: plan.provider, to: defaults)
        return plan.selectedModelToSave
    }

    @discardableResult
    public static func applyModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        for provider: VoiceInkAIEnhancementProviderKind,
        to defaults: UserDefaults = .standard
    ) -> String? {
        guard let selectedModel = plan.selectedModelToSave else {
            return nil
        }

        saveSelectedModel(selectedModel, for: provider, to: defaults)
        return selectedModel
    }

    public static func clear(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkAIEnhancementProviderKind] = VoiceInkAIEnhancementProviderKind.allCases
    ) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        providers.forEach {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel($0.rawValue))
        }
    }
}

public enum VoiceInkDynamicAIProviderPreference {
    public static let defaultOllamaBaseURL = VoiceInkPreferenceDefault.ollamaBaseURL
    public static let defaultOllamaRuntimeSelectedModel = VoiceInkAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback

    public static func ollamaBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = defaultOllamaBaseURL
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL) ?? fallback
    }

    public static func saveOllamaBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
    }

    public static func ollamaSelectedModel(
        from defaults: UserDefaults = .standard,
        fallback: String
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel) ?? fallback
    }

    public static func ollamaRuntimeSelectedModel(from defaults: UserDefaults = .standard) -> String {
        ollamaSelectedModel(from: defaults, fallback: defaultOllamaRuntimeSelectedModel)
    }

    public static func saveOllamaSelectedModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
    }

    @discardableResult
    public static func applyOllamaModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        to defaults: UserDefaults = .standard
    ) -> String? {
        guard let selectedModel = plan.selectedModelToSave else {
            return nil
        }

        saveOllamaSelectedModel(selectedModel, to: defaults)
        return selectedModel
    }

    public static func customProviderBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL) ?? fallback
    }

    public static func saveCustomProviderBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
    }

    public static func customProviderModel(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderModel) ?? fallback
    }

    public static func saveCustomProviderModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.customProviderModel)
    }

    public static func openRouterModels(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.openRouterModels) ?? []
    }

    public static func saveOpenRouterModels(_ models: [String], to defaults: UserDefaults = .standard) {
        defaults.set(models, forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }

    @discardableResult
    public static func applyOpenRouterModelRefreshPlan(
        _ plan: VoiceInkAIEnhancementModelRefreshPlan,
        to defaults: UserDefaults = .standard
    ) -> String? {
        saveOpenRouterModels(plan.refreshedModelNames, to: defaults)
        return VoiceInkAIEnhancementProviderPreference.applyModelRefreshPlan(
            plan,
            for: .openRouter,
            to: defaults
        )
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }
}

public enum VoiceInkFillerWordPreference {
    public static func words(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.fillerWords) ?? VoiceInkFillerWords.defaultWords
    }

    public static func saveWords(_ words: [String], to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: VoiceInkUserDefaultsKey.fillerWords)
    }

    public static func clearWords(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.fillerWords)
    }
}

public enum VoiceInkWordReplacementPreference {
    public static func rules(from defaults: UserDefaults = .standard) -> [VoiceInkWordReplacementRule] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.wordReplacements) else {
            return []
        }

        return (try? JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)) ?? []
    }

    public static func saveRules(_ rules: [VoiceInkWordReplacementRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        defaults.set(data, forKey: VoiceInkUserDefaultsKey.wordReplacements)
    }

    public static func clearRules(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.wordReplacements)
    }
}

public enum VoiceInkCustomVocabularyPreference {
    public static func terms(from defaults: UserDefaults = .standard) -> [String] {
        VoiceInkCustomVocabularyTerms.normalized(
            defaults.stringArray(forKey: VoiceInkUserDefaultsKey.customVocabularyTerms) ?? []
        )
    }

    public static func saveTerms(_ terms: [String], to defaults: UserDefaults = .standard) {
        defaults.set(
            VoiceInkCustomVocabularyTerms.normalized(terms),
            forKey: VoiceInkUserDefaultsKey.customVocabularyTerms
        )
    }

    public static func clearTerms(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customVocabularyTerms)
    }
}

public enum VoiceInkAIEnhancementRequestPreference {
    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.integer(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        return stored > 0
            ? TimeInterval(stored)
            : TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
    }

    public static func shouldRetryOnTimeout(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout) as? Bool
            ?? VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public struct VoiceInkTranscriptionAutoCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionMinutes: Int

    public init(isEnabled: Bool, retentionMinutes: Int) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }

    public var effectiveRetentionMinutes: Int {
        max(retentionMinutes, 0)
    }

    public var shouldDeleteCompletedTranscriptionImmediately: Bool {
        retentionMinutes <= 0
    }

    public func cutoffDate(from referenceDate: Date = Date()) -> Date {
        referenceDate.addingTimeInterval(TimeInterval(-effectiveRetentionMinutes * 60))
    }

    private var completionAction: VoiceInkTranscriptionAutoCleanupCompletionAction {
        guard isEnabled else { return .ignore }
        return shouldDeleteCompletedTranscriptionImmediately
            ? .deleteCompletedTranscription
            : .sweepOldTranscriptions
    }

    public func applyCompletionRuntimeState(
        ignore: () -> Void,
        sweepOldTranscriptions: () -> Void,
        deleteCompletedTranscription: () -> Void
    ) {
        switch completionAction {
        case .ignore:
            ignore()
        case .sweepOldTranscriptions:
            sweepOldTranscriptions()
        case .deleteCompletedTranscription:
            deleteCompletedTranscription()
        }
    }
}

fileprivate enum VoiceInkTranscriptionAutoCleanupCompletionAction: Equatable, Sendable {
    case ignore
    case sweepOldTranscriptions
    case deleteCompletedTranscription
}

public struct VoiceInkTranscriptionAutoCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public struct VoiceInkTranscriptionAutoCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionMinutes: Int?

    public init(isEnabled: Bool?, retentionMinutes: Int?) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }
}

public enum VoiceInkTranscriptionAutoCleanupPreference {
    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkTranscriptionAutoCleanupConfiguration {
        VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionMinutes: retentionMinutes(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func retentionMinutes(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) as? Int
            ?? VoiceInkPreferenceDefault.transcriptionRetentionMinutes
    }

    public static func saveRetentionMinutes(_ minutes: Int, to defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func backupPreferences(
        from configuration: VoiceInkTranscriptionAutoCleanupConfiguration
    ) -> VoiceInkTranscriptionAutoCleanupBackupPreferences {
        VoiceInkTranscriptionAutoCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionMinutes: configuration.retentionMinutes
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkTranscriptionAutoCleanupBackupPreferences
    ) -> VoiceInkTranscriptionAutoCleanupBackupImportPlan {
        VoiceInkTranscriptionAutoCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionMinutes: preferences.retentionMinutes
        )
    }
}

public enum VoiceInkTranscriptionAutoCleanupDiagnostics {
    public static let invalidCompletedTranscriptionMessage = "Invalid transcription or missing model context"

    public static func saveAfterCompletedDeletionFailedMessage(errorDescription: String) -> String {
        "Failed to save after transcription deletion: \(errorDescription)"
    }

    public static func oldTranscriptionsCleanedMessage(deletedCount: Int) -> String {
        "Cleaned up \(deletedCount) old transcription(s)"
    }

    public static func transcriptionCleanupFailedMessage(errorDescription: String) -> String {
        "Failed during transcription cleanup: \(errorDescription)"
    }

    public static func orphanAudioFilesCleanedMessage(deletedCount: Int) -> String {
        "Cleaned up \(deletedCount) orphan audio file(s)"
    }

    public static func orphanAudioCleanupFailedMessage(errorDescription: String) -> String {
        "Failed during orphan audio cleanup: \(errorDescription)"
    }
}

public struct VoiceInkAudioCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionDays: Int

    public init(isEnabled: Bool, retentionDays: Int) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }

    public var effectiveRetentionDays: Int {
        max(retentionDays, 0)
    }

    public func cutoffDate(
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: referenceDate) ?? referenceDate
    }
}

public struct VoiceInkAudioCleanupBackupPreferences: Codable, Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public struct VoiceInkAudioCleanupBackupImportPlan: Equatable, Sendable {
    public let isEnabled: Bool?
    public let retentionDays: Int?

    public init(isEnabled: Bool?, retentionDays: Int?) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }
}

public enum VoiceInkAudioCleanupPreference {
    public static let cleanupCheckInterval: TimeInterval = 86_400

    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkAudioCleanupConfiguration {
        VoiceInkAudioCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionDays: retentionDays(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func retentionDays(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays) as? Int
            ?? VoiceInkPreferenceDefault.audioRetentionDays
    }

    public static func saveRetentionDays(_ days: Int, to defaults: UserDefaults = .standard) {
        defaults.set(days, forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func backupPreferences(
        from configuration: VoiceInkAudioCleanupConfiguration
    ) -> VoiceInkAudioCleanupBackupPreferences {
        VoiceInkAudioCleanupBackupPreferences(
            isEnabled: configuration.isEnabled,
            retentionDays: configuration.retentionDays
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkAudioCleanupBackupPreferences
    ) -> VoiceInkAudioCleanupBackupImportPlan {
        VoiceInkAudioCleanupBackupImportPlan(
            isEnabled: preferences.isEnabled,
            retentionDays: preferences.retentionDays
        )
    }
}

public enum VoiceInkModelRuntimePreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.prewarmModelOnWake
    public static let defaultShouldPrewarmModelOnWake = VoiceInkPreferenceDefault.prewarmModelOnWake
    public static let prewarmScheduleDelay: Duration = .seconds(3)
    public static let settingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.modelPrewarm
    public static let macOSSettingsPresentation = settingsPresentation

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultShouldPrewarmModelOnWake
        ]
    }

    public static func shouldPrewarmModelOnWake(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultShouldPrewarmModelOnWake
    }

    public static func saveShouldPrewarmModelOnWake(
        _ shouldPrewarm: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPrewarm, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkRecorderPreviewPreference {
    public static let userDefaultsKey = VoiceInkUserDefaultsKey.showLiveTextPreview
    public static let defaultIsLiveTextPreviewEnabled = VoiceInkPreferenceDefault.showLiveTextPreview
    public static let macOSSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS.liveTextPreview

    public static var registeredDefaults: [String: Any] {
        [
            userDefaultsKey: defaultIsLiveTextPreviewEnabled
        ]
    }

    public static func isLiveTextPreviewEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: userDefaultsKey) as? Bool ?? defaultIsLiveTextPreviewEnabled
    }

    public static func saveIsLiveTextPreviewEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: userDefaultsKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

public enum VoiceInkRecordingShortcutSlot: Sendable {
    case primary
    case secondary
}

public enum VoiceInkRecordingShortcutSelection: String, CaseIterable, Sendable {
    case none = "none"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .custom:
            return "Custom"
        }
    }
}

public enum VoiceInkRecordingShortcutMode: String, CaseIterable, Sendable {
    case special = "special"
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"
    case hybrid = "hybrid"

    public var displayName: String {
        switch self {
        case .special:
            return "Special"
        case .toggle:
            return "Toggle"
        case .pushToTalk:
            return "Push to Talk"
        case .hybrid:
            return "Hybrid"
        }
    }

    public var tracksKeyUpEvidence: Bool {
        self == .special
    }

    public var allowsShortcutInterruption: Bool {
        !tracksKeyUpEvidence
    }
}

public struct VoiceInkShortcutPressContext: Equatable, Sendable {
    public var didPressOtherKeyDuringPress: Bool
    public var didReleaseOtherKeyDuringPress: Bool
    public var hasReliableKeyEvidence: Bool

    public init(
        didPressOtherKeyDuringPress: Bool = false,
        didReleaseOtherKeyDuringPress: Bool = false,
        hasReliableKeyEvidence: Bool = true
    ) {
        self.didPressOtherKeyDuringPress = didPressOtherKeyDuringPress
        self.didReleaseOtherKeyDuringPress = didReleaseOtherKeyDuringPress
        self.hasReliableKeyEvidence = hasReliableKeyEvidence
    }
}

public enum VoiceInkSpecialShortcutKeyEvidencePolicy {
    public static func shouldDiscardShortcut(for context: VoiceInkShortcutPressContext) -> Bool {
        context.didPressOtherKeyDuringPress ||
        context.didReleaseOtherKeyDuringPress ||
        !context.hasReliableKeyEvidence
    }
}

public enum VoiceInkShortcutInterruptionPolicy {
    public static let interruptionWindow: TimeInterval = 1.0

    public static func isWithinInterruptionWindow(pressedAt: TimeInterval, eventTime: TimeInterval) -> Bool {
        eventTime - pressedAt <= interruptionWindow
    }
}

public enum VoiceInkRecordingShortcutTimingPolicy {
    public static let pressCooldown: TimeInterval = 0.08
    public static let hybridPushToTalkThreshold: TimeInterval = 0.5

    public static func isPressWithinCooldown(
        lastPressTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastPressTime else { return false }
        return now.timeIntervalSince(lastPressTime) < pressCooldown
    }

    public static func shouldStopHybridRecording(
        pressDuration: TimeInterval,
        recordingState: VoiceInkRecordingState
    ) -> Bool {
        pressDuration >= hybridPushToTalkThreshold && recordingState == .recording
    }

    public static func sleepNanoseconds(delaySeconds: TimeInterval) -> UInt64 {
        guard delaySeconds.isFinite else { return 0 }
        let safeDelay = max(delaySeconds, 0)
        let nanoseconds = (safeDelay * 1_000_000_000).rounded()
        guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
            return UInt64.max
        }
        return UInt64(nanoseconds)
    }
}

public enum VoiceInkSpecialShortcutEmptyFallbackPolicy {
    public static let emptyTapThreshold: TimeInterval = 0.32
    public static let fallbackLifetime: TimeInterval = 30

    public static func shouldScheduleFallback(
        pressDuration: TimeInterval,
        threshold: TimeInterval = emptyTapThreshold
    ) -> Bool {
        pressDuration < threshold
    }

    public static func shouldConsumeFallback(
        createdAt: Date,
        now: Date = Date(),
        transcriptionStatus: VoiceInkTranscriptionStatus?,
        rawText: String,
        enhancedText: String?,
        lifetime: TimeInterval = fallbackLifetime
    ) -> Bool {
        guard now.timeIntervalSince(createdAt) <= lifetime else { return false }
        guard transcriptionStatus == .completed else { return false }
        guard rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard enhancedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return false }
        return true
    }
}

public enum VoiceInkShortcutActionIdentifier: Hashable, Sendable {
    case primaryRecording
    case secondaryRecording
    case pasteLastTranscription
    case pasteLastEnhancement
    case retryLastTranscription
    case cancelRecorder
    case openHistoryWindow
    case quickAddToDictionary
    case toggleEnhancement
    case powerMode(UUID)
    case miniRecorderEscape
    case miniRecorderPrompt(Int)
    case miniRecorderPowerMode(Int)

    public var storageName: String {
        switch self {
        case .primaryRecording:
            return "primaryRecording"
        case .secondaryRecording:
            return "secondaryRecording"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .toggleEnhancement:
            return "toggleEnhancement"
        case .powerMode(let id):
            return "powerMode_\(id.uuidString)"
        case .miniRecorderEscape:
            return "miniRecorderEscape"
        case .miniRecorderPrompt(let index):
            return "miniRecorderPrompt_\(index)"
        case .miniRecorderPowerMode(let index):
            return "miniRecorderPowerMode_\(index)"
        }
    }

    public var shortcutStorageKey: String {
        "Shortcut_\(storageName)"
    }

    public var isStoredShortcut: Bool {
        switch self {
        case .miniRecorderEscape, .miniRecorderPrompt, .miniRecorderPowerMode:
            return false
        default:
            return true
        }
    }

    public var recordingShortcutSlot: VoiceInkRecordingShortcutSlot? {
        switch self {
        case .primaryRecording:
            return .primary
        case .secondaryRecording:
            return .secondary
        default:
            return nil
        }
    }

    public var selectionKey: String {
        recordingShortcutSlot.map(VoiceInkRecordingShortcutPreference.selectionKey(for:)) ?? shortcutStorageKey
    }

    public var legacySelectionKey: String {
        switch self {
        case .primaryRecording:
            return "selectedHotkey1"
        case .secondaryRecording:
            return "selectedHotkey2"
        default:
            return shortcutStorageKey
        }
    }

    public var modeKey: String {
        recordingShortcutSlot.map(VoiceInkRecordingShortcutPreference.modeKey(for:)) ?? shortcutStorageKey
    }

    public var legacyModeKey: String {
        switch self {
        case .primaryRecording:
            return "hotkeyMode1"
        case .secondaryRecording:
            return "hotkeyMode2"
        default:
            return shortcutStorageKey
        }
    }

    public var legacyCustomRecordingShortcutKey: String {
        switch self {
        case .primaryRecording:
            return "CustomRecordingShortcut_primary"
        case .secondaryRecording:
            return "CustomRecordingShortcut_secondary"
        default:
            return "CustomRecordingShortcut_\(storageName)"
        }
    }

    public var legacyKeyboardShortcutName: String? {
        switch self {
        case .primaryRecording:
            return "toggleMiniRecorder"
        case .secondaryRecording:
            return "toggleMiniRecorder2"
        case .pasteLastTranscription:
            return "pasteLastTranscription"
        case .pasteLastEnhancement:
            return "pasteLastEnhancement"
        case .retryLastTranscription:
            return "retryLastTranscription"
        case .cancelRecorder:
            return "cancelRecorder"
        case .openHistoryWindow:
            return "openHistoryWindow"
        case .quickAddToDictionary:
            return "quickAddToDictionary"
        case .toggleEnhancement:
            return "toggleEnhancement"
        case .powerMode(let id):
            return "powerMode_\(id.uuidString)"
        case .miniRecorderEscape, .miniRecorderPrompt, .miniRecorderPowerMode:
            return nil
        }
    }

    public var legacyKeyboardShortcutStorageKey: String? {
        legacyKeyboardShortcutName.map { "KeyboardShortcuts_\($0)" }
    }

    public static let legacyKeyboardShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary,
        .toggleEnhancement
    ]

    public static let legacyCustomRecordingShortcutActions: [Self] = [
        .primaryRecording,
        .secondaryRecording
    ]
}

public enum VoiceInkShortcutActionPresentation {
    public static let primaryRecordingDisplayName = "Primary Shortcut"
    public static let secondaryRecordingDisplayName = "Secondary Shortcut"
    public static let pasteLastTranscriptionDisplayName = "Paste Last Transcription"
    public static let pasteLastEnhancementDisplayName = "Paste Last Enhanced Transcription"
    public static let retryLastTranscriptionDisplayName = "Retry Last Transcription"
    public static let cancelRecorderDisplayName = "Cancel Recording"
    public static let openHistoryWindowDisplayName = VoiceInkHistoryPresentation.macOSShortcutTip.shortcutLabel
    public static let quickAddToDictionaryDisplayName = "Quick Add to Dictionary"
    public static let toggleEnhancementDisplayName = "Toggle Enhancement"
    public static let fallbackPowerModeDisplayName = "Power Mode"
    public static let miniRecorderEscapeDisplayName = "Mini Recorder Cancel"

    public static func displayName(
        for identifier: VoiceInkShortcutActionIdentifier,
        powerModeName: String? = nil
    ) -> String {
        switch identifier {
        case .primaryRecording:
            return primaryRecordingDisplayName
        case .secondaryRecording:
            return secondaryRecordingDisplayName
        case .pasteLastTranscription:
            return pasteLastTranscriptionDisplayName
        case .pasteLastEnhancement:
            return pasteLastEnhancementDisplayName
        case .retryLastTranscription:
            return retryLastTranscriptionDisplayName
        case .cancelRecorder:
            return cancelRecorderDisplayName
        case .openHistoryWindow:
            return openHistoryWindowDisplayName
        case .quickAddToDictionary:
            return quickAddToDictionaryDisplayName
        case .toggleEnhancement:
            return toggleEnhancementDisplayName
        case .powerMode:
            guard let powerModeName else {
                return fallbackPowerModeDisplayName
            }
            return "\(powerModeName) Power Mode"
        case .miniRecorderEscape:
            return miniRecorderEscapeDisplayName
        case .miniRecorderPrompt(let index):
            return "Select Prompt \(displayNumber(forMiniRecorderIndex: index))"
        case .miniRecorderPowerMode(let index):
            return "Select Power Mode \(displayNumber(forMiniRecorderIndex: index))"
        }
    }

    public static func displayNumber(forMiniRecorderIndex index: Int) -> String {
        index == 9 ? "10" : "\(index + 1)"
    }
}

public enum VoiceInkShortcutValidationIssue: Equatable, Sendable {
    case plainKeyRequiresModifier
    case shiftTypingKeyRequiresAdditionalModifier
    case reservedBySystem
    case alreadyUsedBy(String)
}

public enum VoiceInkShortcutValidationPresentation {
    public static func notificationTitle(
        for issue: VoiceInkShortcutValidationIssue,
        shortcutDisplayString: String
    ) -> String {
        switch issue {
        case .plainKeyRequiresModifier, .shiftTypingKeyRequiresAdditionalModifier:
            return "Shortcut not allowed: \(shortcutDisplayString)"
        case .reservedBySystem:
            return "Shortcut reserved by macOS: \(shortcutDisplayString)"
        case .alreadyUsedBy(let actionName):
            return "Shortcut already used by \(actionName)"
        }
    }
}

public struct VoiceInkMacOSShortcutNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public let actionButtonLabel: String?

    public init(title: String, duration: TimeInterval, actionButtonLabel: String? = nil) {
        self.title = title
        self.duration = duration
        self.actionButtonLabel = actionButtonLabel
    }

    public static let inputMonitoringPermissionRequired = Self(
        title: "Enable Input Monitoring for shortcuts",
        duration: 6,
        actionButtonLabel: "Open Settings"
    )

    public static let accessibilityPermissionRequired = Self(
        title: "Enable Accessibility for shortcuts",
        duration: 6,
        actionButtonLabel: "Open Settings"
    )

    public static let monitorStartFailed = Self(
        title: "Keyboard shortcut monitor could not start",
        duration: 6
    )

    public static func miniRecorderEscapeConfirmation(duration: TimeInterval) -> Self {
        Self(
            title: "Press ESC again to cancel recording",
            duration: duration
        )
    }
}

public enum VoiceInkMiniRecorderEscapeShortcutPolicy {
    public static let doublePressThreshold: TimeInterval = 1.5

    public static var confirmationPresentation: VoiceInkMacOSShortcutNotificationPresentation {
        VoiceInkMacOSShortcutNotificationPresentation.miniRecorderEscapeConfirmation(
            duration: doublePressThreshold
        )
    }

    public static func isSecondPress(
        firstPressTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let firstPressTime else { return false }
        return now.timeIntervalSince(firstPressTime) <= doublePressThreshold
    }

    public static func timeoutNanoseconds(threshold: TimeInterval = doublePressThreshold) -> UInt64 {
        VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: threshold)
    }
}

public enum VoiceInkLegacyRecordingShortcutPreset: String, CaseIterable, Sendable {
    case rightOption
    case leftOption
    case leftControl
    case rightControl
    case fn
    case rightCommand
    case rightShift
    case leftShift
}

public struct VoiceInkMacOSRecordingShortcutSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let primaryShortcutLabel: String
    public let secondaryShortcutLabel: String
    public let addSecondaryShortcutButtonTitle: String
    public let emptyTapPasteLastTranscriptLabel: String
    public let additionalSectionTitle: String
    public let pasteLastTranscriptionOriginalLabel: String
    public let pasteLastTranscriptionEnhancedLabel: String
    public let retryLastTranscriptionLabel: String
    public let cancelRecordingLabel: String
    public let resetToDefaultHelp: String
    public let middleClickRecordingLabel: String
    public let activationDelayLabel: String
    public let activationDelayUnitLabel: String

    public static let macOS = VoiceInkMacOSRecordingShortcutSettingsPresentation(
        sectionTitle: "Shortcuts",
        primaryShortcutLabel: "Primary Shortcut",
        secondaryShortcutLabel: "Secondary Shortcut",
        addSecondaryShortcutButtonTitle: "Add Second Shortcut",
        emptyTapPasteLastTranscriptLabel: "Empty Tap Pastes Last",
        additionalSectionTitle: "Additional Shortcuts",
        pasteLastTranscriptionOriginalLabel: "Paste Last Transcription (Original)",
        pasteLastTranscriptionEnhancedLabel: "Paste Last Transcription (Enhanced)",
        retryLastTranscriptionLabel: "Retry Last Transcription",
        cancelRecordingLabel: "Cancel Recording",
        resetToDefaultHelp: "Reset to default",
        middleClickRecordingLabel: "Middle-Click Recording",
        activationDelayLabel: "Activation Delay",
        activationDelayUnitLabel: "ms"
    )
}

public struct VoiceInkMacOSShortcutRecorderPresentation: Equatable, Sendable {
    public let recordingPlaceholderText: String
    public let idleAccessibilityLabel: String
    public let idleButtonText: String

    public static let macOS = VoiceInkMacOSShortcutRecorderPresentation(
        recordingPlaceholderText: "Press shortcut",
        idleAccessibilityLabel: "Record shortcut",
        idleButtonText: "Record"
    )
}

public struct VoiceInkRecordingShortcutBackupPreferences: Codable, Equatable, Sendable {
    public let primaryRecordingShortcutRawValue: String?
    public let secondaryRecordingShortcutRawValue: String?
    public let primaryRecordingShortcutModeRawValue: String?
    public let secondaryRecordingShortcutModeRawValue: String?
    public let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    public let isMiddleClickToggleEnabled: Bool?
    public let middleClickActivationDelay: Int?

    public init(
        primaryRecordingShortcutRawValue: String?,
        secondaryRecordingShortcutRawValue: String?,
        primaryRecordingShortcutModeRawValue: String?,
        secondaryRecordingShortcutModeRawValue: String?,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool?,
        isMiddleClickToggleEnabled: Bool?,
        middleClickActivationDelay: Int?
    ) {
        self.primaryRecordingShortcutRawValue = primaryRecordingShortcutRawValue
        self.secondaryRecordingShortcutRawValue = secondaryRecordingShortcutRawValue
        self.primaryRecordingShortcutModeRawValue = primaryRecordingShortcutModeRawValue
        self.secondaryRecordingShortcutModeRawValue = secondaryRecordingShortcutModeRawValue
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = isMiddleClickToggleEnabled
        self.middleClickActivationDelay = middleClickActivationDelay
    }
}

public struct VoiceInkRecordingShortcutBackupImportPlan: Equatable, Sendable {
    private let primaryRecordingShortcut: VoiceInkRecordingShortcutSelection?
    private let secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection?
    private let primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?
    private let secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?
    private let specialShortcutPasteLastTranscriptOnEmptyTap: Bool?
    private let isMiddleClickToggleEnabled: Bool?
    private let middleClickActivationDelay: Int?

    public init(
        primaryRecordingShortcut: VoiceInkRecordingShortcutSelection?,
        secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection?,
        primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?,
        secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode?,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool?,
        isMiddleClickToggleEnabled: Bool?,
        middleClickActivationDelay: Int?
    ) {
        self.primaryRecordingShortcut = primaryRecordingShortcut
        self.secondaryRecordingShortcut = secondaryRecordingShortcut
        self.primaryRecordingShortcutMode = primaryRecordingShortcutMode
        self.secondaryRecordingShortcutMode = secondaryRecordingShortcutMode
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialShortcutPasteLastTranscriptOnEmptyTap
        self.isMiddleClickToggleEnabled = isMiddleClickToggleEnabled
        self.middleClickActivationDelay = middleClickActivationDelay
    }

    public func applyRuntimeState(
        setPrimaryRecordingShortcut: (VoiceInkRecordingShortcutSelection) -> Void,
        setSecondaryRecordingShortcut: (VoiceInkRecordingShortcutSelection) -> Void,
        setPrimaryRecordingShortcutMode: (VoiceInkRecordingShortcutMode) -> Void,
        setSecondaryRecordingShortcutMode: (VoiceInkRecordingShortcutMode) -> Void,
        setSpecialShortcutPasteLastTranscriptOnEmptyTap: (Bool) -> Void,
        setMiddleClickToggleEnabled: (Bool) -> Void,
        setMiddleClickActivationDelay: (Int) -> Void
    ) {
        if let primaryRecordingShortcut {
            setPrimaryRecordingShortcut(primaryRecordingShortcut)
        }
        if let secondaryRecordingShortcut {
            setSecondaryRecordingShortcut(secondaryRecordingShortcut)
        }
        if let primaryRecordingShortcutMode {
            setPrimaryRecordingShortcutMode(primaryRecordingShortcutMode)
        }
        if let secondaryRecordingShortcutMode {
            setSecondaryRecordingShortcutMode(secondaryRecordingShortcutMode)
        }
        if let specialShortcutPasteLastTranscriptOnEmptyTap {
            setSpecialShortcutPasteLastTranscriptOnEmptyTap(specialShortcutPasteLastTranscriptOnEmptyTap)
        }
        if let isMiddleClickToggleEnabled {
            setMiddleClickToggleEnabled(isMiddleClickToggleEnabled)
        }
        if let middleClickActivationDelay {
            setMiddleClickActivationDelay(middleClickActivationDelay)
        }
    }
}

public struct VoiceInkShortcutBackupImport: Equatable, Sendable {
    public let actionIdentifier: VoiceInkShortcutActionIdentifier
    public let recordingShortcutSlot: VoiceInkRecordingShortcutSlot?
    public let recordingShortcutSelection: VoiceInkRecordingShortcutSelection?

    public init(
        actionIdentifier: VoiceInkShortcutActionIdentifier,
        recordingShortcutSlot: VoiceInkRecordingShortcutSlot?,
        recordingShortcutSelection: VoiceInkRecordingShortcutSelection?
    ) {
        self.actionIdentifier = actionIdentifier
        self.recordingShortcutSlot = recordingShortcutSlot
        self.recordingShortcutSelection = recordingShortcutSelection
    }
}

public enum VoiceInkShortcutBackupPolicy {
    public static let generalBackupShortcutActionIdentifiers: [VoiceInkShortcutActionIdentifier] = [
        .primaryRecording,
        .secondaryRecording,
        .pasteLastTranscription,
        .pasteLastEnhancement,
        .retryLastTranscription,
        .cancelRecorder,
        .openHistoryWindow,
        .quickAddToDictionary,
        .toggleEnhancement
    ]

    public static func generalBackupShortcutExportPlan(
        availableActionIdentifiers: Set<VoiceInkShortcutActionIdentifier>
    ) -> [VoiceInkShortcutActionIdentifier] {
        generalBackupShortcutActionIdentifiers.filter(availableActionIdentifiers.contains)
    }

    public static func generalBackupShortcutRecords<ShortcutBackup>(
        backupForActionIdentifier: (VoiceInkShortcutActionIdentifier) -> ShortcutBackup?
    ) -> [VoiceInkShortcutActionIdentifier: ShortcutBackup] {
        let candidates = generalBackupShortcutActionIdentifiers
            .reduce(into: [VoiceInkShortcutActionIdentifier: ShortcutBackup]()) { records, actionIdentifier in
                guard let backup = backupForActionIdentifier(actionIdentifier) else {
                    return
                }
                records[actionIdentifier] = backup
            }

        return generalBackupShortcutExportPlan(
            availableActionIdentifiers: Set(candidates.keys)
        ).reduce(into: [VoiceInkShortcutActionIdentifier: ShortcutBackup]()) { records, actionIdentifier in
            records[actionIdentifier] = candidates[actionIdentifier]
        }
    }

    public static func generalBackupShortcutImportPlan(
        importedActionIdentifiers: Set<VoiceInkShortcutActionIdentifier>
    ) -> [VoiceInkShortcutBackupImport] {
        generalBackupShortcutActionIdentifiers.compactMap { actionIdentifier in
            guard importedActionIdentifiers.contains(actionIdentifier) else {
                return nil
            }

            let slot = actionIdentifier.recordingShortcutSlot
            return VoiceInkShortcutBackupImport(
                actionIdentifier: actionIdentifier,
                recordingShortcutSlot: slot,
                recordingShortcutSelection: slot == nil ? nil : .custom
            )
        }
    }
}

public struct VoiceInkShortcutStorageState: Equatable, Sendable {
    public let shortcutData: Data?
    public let clearedValue: Bool?

    public init(shortcutData: Data?, clearedValue: Bool?) {
        self.shortcutData = shortcutData
        self.clearedValue = clearedValue
    }
}

public struct VoiceInkRecordingShortcutSelectionMigrationPlan: Equatable, Sendable {
    public let selection: VoiceInkRecordingShortcutSelection
    public let destinationKey: String?
    public let legacyKeyToRemove: String?
    public let presetToStore: VoiceInkLegacyRecordingShortcutPreset?
    public let defaultPresetToStore: VoiceInkLegacyRecordingShortcutPreset?

    public init(
        selection: VoiceInkRecordingShortcutSelection,
        destinationKey: String?,
        legacyKeyToRemove: String?,
        presetToStore: VoiceInkLegacyRecordingShortcutPreset?,
        defaultPresetToStore: VoiceInkLegacyRecordingShortcutPreset?
    ) {
        self.selection = selection
        self.destinationKey = destinationKey
        self.legacyKeyToRemove = legacyKeyToRemove
        self.presetToStore = presetToStore
        self.defaultPresetToStore = defaultPresetToStore
    }
}

public enum VoiceInkShortcutStoragePreference {
    public static func clearedKey(for shortcutKey: String) -> String {
        "\(shortcutKey)_cleared"
    }

    public static func shortcutData(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> Data? {
        defaults.data(forKey: shortcutKey)
    }

    public static func isShortcutCleared(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: clearedKey(for: shortcutKey))
    }

    public static func saveShortcutData(
        _ data: Data,
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(data, forKey: shortcutKey)
        defaults.removeObject(forKey: clearedKey(for: shortcutKey))
    }

    public static func markShortcutCleared(
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: shortcutKey)
        defaults.set(true, forKey: clearedKey(for: shortcutKey))
    }

    public static func removeShortcutStorage(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: shortcutKey)
        defaults.removeObject(forKey: clearedKey(for: shortcutKey))
    }

    public static func storedState(
        for shortcutKey: String,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkShortcutStorageState {
        let clearedKey = clearedKey(for: shortcutKey)
        return VoiceInkShortcutStorageState(
            shortcutData: shortcutData(for: shortcutKey, from: defaults),
            clearedValue: defaults.object(forKey: clearedKey) == nil ? nil : defaults.bool(forKey: clearedKey)
        )
    }

    public static func restoreStoredState(
        _ state: VoiceInkShortcutStorageState,
        for shortcutKey: String,
        to defaults: UserDefaults = .standard
    ) {
        if let shortcutData = state.shortcutData {
            defaults.set(shortcutData, forKey: shortcutKey)
        } else {
            defaults.removeObject(forKey: shortcutKey)
        }

        let clearedKey = clearedKey(for: shortcutKey)
        if let clearedValue = state.clearedValue {
            defaults.set(clearedValue, forKey: clearedKey)
        } else {
            defaults.removeObject(forKey: clearedKey)
        }
    }
}

public enum VoiceInkRecordingShortcutPreference {
    public static let legacyKeyboardShortcutsMigrationKey = "Shortcut_LegacyKeyboardShortcutsMigrated"
    public static let legacyCustomRecordingShortcutsMigrationKey = "Shortcut_LegacyCustomRecordingShortcutsMigrated"
    public static let minimumMiddleClickActivationDelay = 0
    public static let shortcutDidChangeNotificationName = Notification.Name("ShortcutStoreShortcutDidChange")
    public static let shortcutRecordingDidStartNotificationName = Notification.Name("ShortcutRecorderRecordingDidStart")

    public static let macOSSettingsPresentation = VoiceInkMacOSRecordingShortcutSettingsPresentation.macOS
    public static let macOSRecorderPresentation = VoiceInkMacOSShortcutRecorderPresentation.macOS

    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled: VoiceInkPreferenceDefault.isMiddleClickToggleEnabled,
            VoiceInkUserDefaultsKey.middleClickActivationDelay: VoiceInkPreferenceDefault.middleClickActivationDelay,
            VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap: VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
        ]
    }

    public static func isLegacyKeyboardShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: legacyKeyboardShortcutsMigrationKey)
    }

    public static func markLegacyKeyboardShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: legacyKeyboardShortcutsMigrationKey)
    }

    public static func isLegacyCustomRecordingShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: legacyCustomRecordingShortcutsMigrationKey)
    }

    public static func markLegacyCustomRecordingShortcutsMigrationComplete(
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: legacyCustomRecordingShortcutsMigrationKey)
    }

    public static func shortcutSelectionMigrationPlan(
        for action: VoiceInkShortcutActionIdentifier,
        allowsNone: Bool,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutSelectionMigrationPlan {
        let destinationKey = action.selectionKey
        let legacyKey = action.legacySelectionKey
        let legacyKeyToRemove = legacyKey == destinationKey ? nil : legacyKey

        if let storedValue = nonEmptyString(forKey: destinationKey, from: defaults) {
            return shortcutSelectionMigrationPlan(
                from: storedValue,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                allowsNone: allowsNone
            )
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey, from: defaults) {
            return shortcutSelectionMigrationPlan(
                from: legacyValue,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                allowsNone: allowsNone
            )
        }

        guard !allowsNone else {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .none,
                destinationKey: nil,
                legacyKeyToRemove: nil,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        let slot = action.recordingShortcutSlot ?? .primary
        return VoiceInkRecordingShortcutSelectionMigrationPlan(
            selection: defaultSelection(for: slot),
            destinationKey: destinationKey,
            legacyKeyToRemove: nil,
            presetToStore: nil,
            defaultPresetToStore: action == .primaryRecording ? .leftShift : nil
        )
    }

    public static func applyShortcutSelectionMigrationPlan(
        _ plan: VoiceInkRecordingShortcutSelectionMigrationPlan,
        to defaults: UserDefaults = .standard
    ) {
        if let destinationKey = plan.destinationKey {
            defaults.set(plan.selection.rawValue, forKey: destinationKey)
        }

        if let legacyKeyToRemove = plan.legacyKeyToRemove {
            defaults.removeObject(forKey: legacyKeyToRemove)
        }
    }

    public static func migrateShortcutMode(
        for action: VoiceInkShortcutActionIdentifier,
        in defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutMode {
        let destinationKey = action.modeKey
        let legacyKey = action.legacyModeKey
        let legacyKeyToRemove = legacyKey == destinationKey ? nil : legacyKey

        if let storedValue = nonEmptyString(forKey: destinationKey, from: defaults),
           let mode = VoiceInkRecordingShortcutMode(rawValue: storedValue) {
            if let legacyKeyToRemove {
                defaults.removeObject(forKey: legacyKeyToRemove)
            }
            return mode
        }

        if let legacyValue = nonEmptyString(forKey: legacyKey, from: defaults),
           let mode = VoiceInkRecordingShortcutMode(rawValue: legacyValue) {
            defaults.set(mode.rawValue, forKey: destinationKey)
            if let legacyKeyToRemove {
                defaults.removeObject(forKey: legacyKeyToRemove)
            }
            return mode
        }

        let slot = action.recordingShortcutSlot ?? .secondary
        return defaultMode(for: slot)
    }

    public static func removeLegacyCustomRecordingShortcut(
        for action: VoiceInkShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: action.legacyCustomRecordingShortcutKey)
    }

    public static func removeLegacyKeyboardShortcut(
        for action: VoiceInkShortcutActionIdentifier,
        from defaults: UserDefaults = .standard
    ) {
        guard let key = action.legacyKeyboardShortcutStorageKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func selectionKey(for slot: VoiceInkRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return VoiceInkUserDefaultsKey.primaryRecordingShortcut
        case .secondary:
            return VoiceInkUserDefaultsKey.secondaryRecordingShortcut
        }
    }

    public static func modeKey(for slot: VoiceInkRecordingShortcutSlot) -> String {
        switch slot {
        case .primary:
            return VoiceInkUserDefaultsKey.primaryRecordingShortcutMode
        case .secondary:
            return VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode
        }
    }

    public static func defaultSelection(for slot: VoiceInkRecordingShortcutSlot) -> VoiceInkRecordingShortcutSelection {
        switch slot {
        case .primary:
            return .custom
        case .secondary:
            return .none
        }
    }

    public static func defaultMode(for slot: VoiceInkRecordingShortcutSlot) -> VoiceInkRecordingShortcutMode {
        switch slot {
        case .primary:
            return .special
        case .secondary:
            return .hybrid
        }
    }

    public static func backupPreferences(
        primaryRecordingShortcut: VoiceInkRecordingShortcutSelection,
        secondaryRecordingShortcut: VoiceInkRecordingShortcutSelection,
        primaryRecordingShortcutMode: VoiceInkRecordingShortcutMode,
        secondaryRecordingShortcutMode: VoiceInkRecordingShortcutMode,
        specialShortcutPasteLastTranscriptOnEmptyTap: Bool,
        isMiddleClickToggleEnabled: Bool,
        middleClickActivationDelay: Int
    ) -> VoiceInkRecordingShortcutBackupPreferences {
        VoiceInkRecordingShortcutBackupPreferences(
            primaryRecordingShortcutRawValue: primaryRecordingShortcut.rawValue,
            secondaryRecordingShortcutRawValue: secondaryRecordingShortcut.rawValue,
            primaryRecordingShortcutModeRawValue: primaryRecordingShortcutMode.rawValue,
            secondaryRecordingShortcutModeRawValue: secondaryRecordingShortcutMode.rawValue,
            specialShortcutPasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: isMiddleClickToggleEnabled,
            middleClickActivationDelay: middleClickActivationDelay
        )
    }

    public static func backupImportPlan(
        from backup: VoiceInkRecordingShortcutBackupPreferences
    ) -> VoiceInkRecordingShortcutBackupImportPlan {
        VoiceInkRecordingShortcutBackupImportPlan(
            primaryRecordingShortcut: backup.primaryRecordingShortcutRawValue.flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:)),
            secondaryRecordingShortcut: backup.secondaryRecordingShortcutRawValue.flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:)),
            primaryRecordingShortcutMode: backup.primaryRecordingShortcutModeRawValue.flatMap(VoiceInkRecordingShortcutMode.init(rawValue:)),
            secondaryRecordingShortcutMode: backup.secondaryRecordingShortcutModeRawValue.flatMap(VoiceInkRecordingShortcutMode.init(rawValue:)),
            specialShortcutPasteLastTranscriptOnEmptyTap: backup.specialShortcutPasteLastTranscriptOnEmptyTap,
            isMiddleClickToggleEnabled: backup.isMiddleClickToggleEnabled,
            middleClickActivationDelay: backup.middleClickActivationDelay.map(Self.normalizedMiddleClickActivationDelay)
        )
    }

    public static func selection(
        for slot: VoiceInkRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutSelection? {
        defaults.string(forKey: selectionKey(for: slot)).flatMap(VoiceInkRecordingShortcutSelection.init(rawValue:))
    }

    public static func saveSelection(
        _ selection: VoiceInkRecordingShortcutSelection,
        for slot: VoiceInkRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(selection.rawValue, forKey: selectionKey(for: slot))
    }

    public static func mode(
        for slot: VoiceInkRecordingShortcutSlot,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkRecordingShortcutMode {
        defaults.string(forKey: modeKey(for: slot)).flatMap(VoiceInkRecordingShortcutMode.init(rawValue:))
            ?? defaultMode(for: slot)
    }

    public static func saveMode(
        _ mode: VoiceInkRecordingShortcutMode,
        for slot: VoiceInkRecordingShortcutSlot,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(mode.rawValue, forKey: modeKey(for: slot))
    }

    public static func isMiddleClickToggleEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled) as? Bool
            ?? VoiceInkPreferenceDefault.isMiddleClickToggleEnabled
    }

    public static func saveMiddleClickToggleEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled)
    }

    public static func middleClickActivationDelay(from defaults: UserDefaults = .standard) -> Int {
        normalizedMiddleClickActivationDelay(
            defaults.object(forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay) as? Int
                ?? VoiceInkPreferenceDefault.middleClickActivationDelay
        )
    }

    public static func saveMiddleClickActivationDelay(
        _ delay: Int,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(
            normalizedMiddleClickActivationDelay(delay),
            forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay
        )
    }

    public static func normalizedMiddleClickActivationDelay(_ delay: Int) -> Int {
        max(delay, minimumMiddleClickActivationDelay)
    }

    public static func middleClickActivationDelayFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: minimumMiddleClickActivationDelay)
        return formatter
    }

    public static func shouldPasteLastTranscriptOnEmptyTap(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap) as? Bool
            ?? VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
    }

    public static func saveShouldPasteLastTranscriptOnEmptyTap(
        _ shouldPaste: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPaste, forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcut)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcut)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcutMode)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap)
    }

    private static func shortcutSelectionMigrationPlan(
        from rawValue: String,
        destinationKey: String,
        legacyKeyToRemove: String?,
        allowsNone: Bool
    ) -> VoiceInkRecordingShortcutSelectionMigrationPlan {
        if rawValue == VoiceInkRecordingShortcutSelection.custom.rawValue {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if rawValue == VoiceInkRecordingShortcutSelection.none.rawValue {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: allowsNone ? .none : .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: nil,
                defaultPresetToStore: nil
            )
        }

        if let preset = VoiceInkLegacyRecordingShortcutPreset(rawValue: rawValue) {
            return VoiceInkRecordingShortcutSelectionMigrationPlan(
                selection: .custom,
                destinationKey: destinationKey,
                legacyKeyToRemove: legacyKeyToRemove,
                presetToStore: preset,
                defaultPresetToStore: nil
            )
        }

        return VoiceInkRecordingShortcutSelectionMigrationPlan(
            selection: allowsNone ? .none : .custom,
            destinationKey: destinationKey,
            legacyKeyToRemove: legacyKeyToRemove,
            presetToStore: nil,
            defaultPresetToStore: nil
        )
    }

    private static func nonEmptyString(
        forKey key: String,
        from defaults: UserDefaults
    ) -> String? {
        guard
            let value = defaults.string(forKey: key),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }
}

public enum VoiceInkSharedPreferenceReset {
    public static func clearCoreUserSettings(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders
    ) {
        VoiceInkModeStorage.clear(from: defaults)
        VoiceInkOnboardingPreference.clear(from: defaults)
        VoiceInkProviderAPIKeyVerificationState.clearAll(from: providers, in: defaults)
        VoiceInkAudioSessionTimeoutPreference.clear(from: defaults)
        VoiceInkVADPreference.clear(from: defaults)
        VoiceInkTranscriptionPromptPreference.clearPrompt(from: defaults)
        PunctuationCleanupMode.clearCurrent(in: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)
        VoiceInkFillerWordPreference.clearWords(from: defaults)
        VoiceInkWordReplacementPreference.clearRules(from: defaults)
        VoiceInkCustomVocabularyPreference.clearTerms(from: defaults)
        VoiceInkDictionaryListSortPreference.clear(from: defaults)
        VoiceInkTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)
        VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)
        VoiceInkAIEnhancementProviderPreference.clear(from: defaults)
        VoiceInkDynamicAIProviderPreference.clear(from: defaults)
        VoiceInkLocalCLIPreference.clear(from: defaults)
        VoiceInkAIEnhancementRequestPreference.clear(from: defaults)
        VoiceInkTranscriptionAutoCleanupPreference.clear(from: defaults)
        VoiceInkAudioCleanupPreference.clear(from: defaults)
        VoiceInkAudioPlaybackRate.clear(from: defaults)
        VoiceInkCustomPromptStorage.clear(from: defaults)
        VoiceInkAIEnhancementContextPreference.clear(from: defaults)
        VoiceInkPowerModePreference.clear(from: defaults)
        VoiceInkPowerModeConfigurationPreference.clear(from: defaults)
        VoiceInkPowerModeSessionPreference.clear(from: defaults)
        VoiceInkModelRuntimePreference.clear(from: defaults)
        VoiceInkRecorderPreviewPreference.clear(from: defaults)
        VoiceInkRecordingShortcutPreference.clear(from: defaults)
        VoiceInkAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
    }
}

public enum VoiceInkModeStorage {
    public static func saveModes(
        _ modes: [Mode],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(modes) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.modes)
        }
    }

    public static func loadModes(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [Mode] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.modes),
              let modes = try? decoder.decode([Mode].self, from: data) else {
            return []
        }

        return modes.map { mode in
            var repairedMode = mode
            repairedMode.repairModelSelection()
            return repairedMode
        }
    }

    public static func saveSelectedModeId(_ selectedModeId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedModeId {
            defaults.set(selectedModeId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedModeId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
        }
    }

    public static func loadSelectedModeId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedModeId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.modes)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
    }
}

public enum VoiceInkPowerModeConfigurationPreference {
    public static func saveConfigurations(
        _ configurations: [PowerModeConfig],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(configurations) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
        }
    }

    public static func loadConfigurations(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [PowerModeConfig] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations),
              let configurations = try? decoder.decode([PowerModeConfig].self, from: data) else {
            return []
        }

        return configurations
    }

    public static func saveActiveConfigurationId(
        _ id: UUID?,
        to defaults: UserDefaults = .standard
    ) {
        if let id {
            defaults.set(id.uuidString, forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
        }
    }

    public static func loadActiveConfigurationId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
    }
}

public enum VoiceInkPowerModePreference {
    public static var registeredDefaults: [String: Any] {
        [
            VoiceInkUserDefaultsKey.powerModePersistConfig: VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences
        ]
    }

    public static func isUIEnabled(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag) != nil else {
            return VoiceInkPreferenceDefault.powerModeUIEnabled
        }

        return defaults.bool(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
    }

    public static func saveIsUIEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
    }

    public static func initializeUIFlagIfNeeded(
        hasEnabledConfigurations: Bool,
        in defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag) == nil else {
            return
        }

        saveIsUIEnabled(hasEnabledConfigurations, to: defaults)
    }

    public static func shouldPersistConfiguredPreferences(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig) != nil else {
            return VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences
        }

        return defaults.bool(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }

    public static func saveShouldPersistConfiguredPreferences(
        _ shouldPersist: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(shouldPersist, forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }

    public static func canUseShortcuts(
        hasEnabledConfigurations: Bool,
        from defaults: UserDefaults = .standard
    ) -> Bool {
        isUIEnabled(from: defaults) && hasEnabledConfigurations
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModeUIFlag)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.powerModePersistConfig)
    }
}

public enum VoiceInkPowerModeSessionPreference {
    public static func saveActiveSession(
        _ session: VoiceInkPowerModeSession,
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(session)
        defaults.set(data, forKey: VoiceInkUserDefaultsKey.activePowerModeSession)
    }

    public static func loadActiveSession(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> VoiceInkPowerModeSession? {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.activePowerModeSession) else {
            return nil
        }

        return try decoder.decode(VoiceInkPowerModeSession.self, from: data)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.activePowerModeSession)
    }
}

public enum VoiceInkCustomPromptStorage {
    public static func savePrompts(
        _ prompts: [VoiceInkCustomPrompt],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(prompts) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.customPrompts)
        }
    }

    public static func loadPrompts(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [VoiceInkCustomPrompt] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.customPrompts),
              let prompts = try? decoder.decode([VoiceInkCustomPrompt].self, from: data) else {
            return []
        }

        return prompts
    }

    public static func saveSelectedPromptId(_ selectedPromptId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedPromptId {
            defaults.set(selectedPromptId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        }
    }

    public static func loadSelectedPromptId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedPromptId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
    }
}

public enum VoiceInkProviderAPIKeyVerificationState {
    public static func verifiedProviders(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) -> Set<VoiceInkProviderKind> {
        Set(providers.filter { isVerified($0, in: defaults) })
    }

    public static func isVerified(
        _ provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else {
            return false
        }

        return defaults.bool(forKey: key)
    }

    public static func setVerified(
        _ verified: Bool,
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.set(verified, forKey: key)
    }

    public static func clear(
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func clearAll(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) {
        providers.forEach { clear(for: $0, in: defaults) }
    }
}
