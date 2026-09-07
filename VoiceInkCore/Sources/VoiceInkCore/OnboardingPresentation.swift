import Foundation

public struct VoiceInkOnboardingFeaturePresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let description: String

    public init(iconSystemName: String, title: String, description: String) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
    }
}

public struct VoiceInkOnboardingStepPresentation: Equatable, Sendable {
    public let number: String
    public let title: String
    public let description: String

    public init(number: String, title: String, description: String) {
        self.number = number
        self.title = title
        self.description = description
    }
}

public struct VoiceInkOnboardingWelcomePresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let features: [VoiceInkOnboardingFeaturePresentation]
    public let primaryButtonTitle: String

    public init(
        title: String,
        subtitle: String,
        features: [VoiceInkOnboardingFeaturePresentation],
        primaryButtonTitle: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.features = features
        self.primaryButtonTitle = primaryButtonTitle
    }
}

public struct VoiceInkMacOSOnboardingWelcomePresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let primaryButtonTitle: String
    public let skipButtonTitle: String
    public let typewriterRoles: [String]

    public init(
        title: String,
        subtitle: String,
        primaryButtonTitle: String,
        skipButtonTitle: String,
        typewriterRoles: [String]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButtonTitle = primaryButtonTitle
        self.skipButtonTitle = skipButtonTitle
        self.typewriterRoles = typewriterRoles
    }
}

public struct VoiceInkOnboardingModelDownloadPresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let subtitle: String
    public let continueButtonTitle: String

    public init(
        iconSystemName: String,
        title: String,
        subtitle: String,
        continueButtonTitle: String
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.subtitle = subtitle
        self.continueButtonTitle = continueButtonTitle
    }

    public func primaryAction(
        for rowPresentation: VoiceInkWhisperModelDownloadRowPresentation
    ) -> VoiceInkOnboardingModelDownloadPrimaryAction {
        switch rowPresentation.action {
        case .downloading:
            return .waitForDownload(title: rowPresentation.progress.compactStatusText)
        case .downloaded:
            return .continueSetup(title: continueButtonTitle)
        case .download:
            return .requestDownload(
                title: rowPresentation.downloadButtonTitle,
                systemImageName: rowPresentation.downloadButtonSystemImageName
            )
        }
    }
}

private enum VoiceInkOnboardingModelDownloadPrimaryActionKind: Equatable, Sendable {
    case waitForDownload
    case continueSetup
    case requestDownload
}

public struct VoiceInkOnboardingModelDownloadPrimaryAction: Equatable, Sendable {
    public let title: String
    public let systemImageName: String?
    private let kind: VoiceInkOnboardingModelDownloadPrimaryActionKind

    static func waitForDownload(title: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: nil,
            kind: .waitForDownload
        )
    }

    static func continueSetup(title: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: nil,
            kind: .continueSetup
        )
    }

    static func requestDownload(title: String, systemImageName: String) -> Self {
        VoiceInkOnboardingModelDownloadPrimaryAction(
            title: title,
            systemImageName: systemImageName,
            kind: .requestDownload
        )
    }

    public var isEnabled: Bool {
        runtimeAction(continueSetup: {}, requestDownload: {}) != nil
    }

    public func runtimeAction(
        continueSetup: @escaping () -> Void,
        requestDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        switch kind {
        case .waitForDownload:
            return nil
        case .continueSetup:
            return continueSetup
        case .requestDownload:
            return requestDownload
        }
    }
}

public struct VoiceInkIOSOnboardingModelDownloadSnapshot: Equatable, Sendable {
    public let onboardingPresentation: VoiceInkOnboardingModelDownloadPresentation
    public let model: VoiceInkWhisperModelFileSpec
    public let row: VoiceInkWhisperModelManagementRow
    public let rowPresentation: VoiceInkWhisperModelDownloadRowPresentation
    public let primaryAction: VoiceInkOnboardingModelDownloadPrimaryAction

    public var downloadConfirmation: VoiceInkWhisperModelOperationConfirmationPresentation {
        row.downloadConfirmation
    }

    public init(
        onboardingPresentation: VoiceInkOnboardingModelDownloadPresentation = VoiceInkIOSOnboardingPresentation.modelDownload,
        model: VoiceInkWhisperModelFileSpec = VoiceInkIOSOnboardingPresentation.defaultDownloadModel,
        row: VoiceInkWhisperModelManagementRow
    ) {
        self.onboardingPresentation = onboardingPresentation
        self.model = model
        self.row = row
        self.rowPresentation = row.presentation
        self.primaryAction = onboardingPresentation.primaryAction(for: row.presentation)
    }

    public func confirmedDownloadRuntimeAction(
        startDownload: @escaping () -> Void
    ) -> (() -> Void)? {
        row.confirmedDownloadRuntimeAction(startDownload: startDownload)
    }
}

public extension VoiceInkWhisperModelManagementSnapshot {
    func iOSOnboardingModelDownloadSnapshot(
        fileManager: FileManager = .default
    ) -> VoiceInkIOSOnboardingModelDownloadSnapshot {
        let model = VoiceInkIOSOnboardingPresentation.defaultDownloadModel
        return VoiceInkIOSOnboardingModelDownloadSnapshot(
            onboardingPresentation: VoiceInkIOSOnboardingPresentation.modelDownload,
            model: model,
            row: managementRow(for: model, fileManager: fileManager)
        )
    }
}

public struct VoiceInkMacOSOnboardingModelDownloadPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let nextButtonTitle: String
    public let skipButtonTitle: String

    public init(
        title: String,
        subtitle: String,
        nextButtonTitle: String,
        skipButtonTitle: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.nextButtonTitle = nextButtonTitle
        self.skipButtonTitle = skipButtonTitle
    }
}

public struct VoiceInkMacOSOnboardingTutorialPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let shortcutTitle: String
    public let instructionSteps: [String]
    public let completeButtonTitle: String
    public let skipButtonTitle: String
    public let placeholderIconSystemName: String
    public let placeholderText: String

    public init(
        title: String,
        subtitle: String,
        shortcutTitle: String,
        instructionSteps: [String],
        completeButtonTitle: String,
        skipButtonTitle: String,
        placeholderIconSystemName: String,
        placeholderText: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.shortcutTitle = shortcutTitle
        self.instructionSteps = instructionSteps
        self.completeButtonTitle = completeButtonTitle
        self.skipButtonTitle = skipButtonTitle
        self.placeholderIconSystemName = placeholderIconSystemName
        self.placeholderText = placeholderText
    }
}

public enum VoiceInkIOSOnboardingTutorialPresentation {
    public static let iconSystemName = "wand.and.stars"
    public static let title = "Try It Out"
    public static let subtitle = "Record a short phrase and confirm that transcription works before finishing setup."
    public static let instructionSteps = [
        VoiceInkOnboardingStepPresentation(number: "1", title: "Start", description: "Tap Start Recording."),
        VoiceInkOnboardingStepPresentation(number: "2", title: "Speak", description: "Say a short phrase clearly."),
        VoiceInkOnboardingStepPresentation(number: "3", title: "Stop", description: "Tap Stop Recording."),
        VoiceInkOnboardingStepPresentation(number: "4", title: "Confirm", description: "Wait for your transcript to appear.")
    ]
    public static let startButtonTitle = "Start Recording"
    public static let retryButtonTitle = "Try Again"
    public static let continueButtonTitle = "Continue"
    public static let skipButtonTitle = "Skip for now"
    public static let readyTitle = "Ready to test"
    public static let readyDetail = "Your recording uses the same mode and transcription pipeline as the app."
    public static let processingTitle = "Transcribing…"
    public static let processingDetail = "Keep the app open while your test recording is processed."
    public static let successTitle = "Transcription works"
    public static let failureTitle = "Transcription failed"
    public static let emptyTranscriptMessage = "No speech was transcribed. Try recording again."
}

public enum VoiceInkIOSOnboardingTutorialState: Equatable, Sendable {
    case ready
    case processing
    case succeeded(String)
    case failed(String)

    public static func completed(
        with outcome: VoiceInkStoredAudioRetranscriptionOutcome
    ) -> Self {
        switch outcome {
        case .succeeded(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .failed(VoiceInkIOSOnboardingTutorialPresentation.emptyTranscriptMessage)
                : .succeeded(text)
        case .failed(let reason):
            return .failed(reason)
        case .canceled:
            return .failed(VoiceInkTranscriptPresentation.canceledTranscriptionText)
        }
    }

    public var canComplete: Bool {
        guard case .succeeded(let text) = self else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct VoiceInkMacOSResetOnboardingPresentation: Equatable, Sendable {
    public let buttonTitle: String
    public let alertTitle: String
    public let cancelButtonTitle: String
    public let confirmButtonTitle: String
    public let message: String

    public init(
        buttonTitle: String,
        alertTitle: String,
        cancelButtonTitle: String,
        confirmButtonTitle: String,
        message: String
    ) {
        self.buttonTitle = buttonTitle
        self.alertTitle = alertTitle
        self.cancelButtonTitle = cancelButtonTitle
        self.confirmButtonTitle = confirmButtonTitle
        self.message = message
    }
}

enum VoiceInkMacOSSetupStepKind: String, Equatable, Sendable {
    case shortcut
    case accessibility
    case screenContext
    case modelDownload
}

public struct VoiceInkMacOSSetupStepPresentation: Identifiable, Equatable, Sendable {
    let kind: VoiceInkMacOSSetupStepKind
    public let isOptional: Bool
    public let iconSystemName: String
    public let title: String
    public let description: String

    public var id: String { kind.rawValue }

    init(
        kind: VoiceInkMacOSSetupStepKind,
        isOptional: Bool,
        iconSystemName: String,
        title: String,
        description: String
    ) {
        self.kind = kind
        self.isOptional = isOptional
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
    }

    public func isCompleted(
        isShortcutConfigured: Bool,
        isAccessibilityEnabled: Bool,
        isScreenRecordingEnabled: Bool,
        hasCurrentTranscriptionModel: Bool
    ) -> Bool {
        switch kind {
        case .shortcut:
            return isShortcutConfigured
        case .accessibility:
            return isAccessibilityEnabled
        case .screenContext:
            return isScreenRecordingEnabled
        case .modelDownload:
            return hasCurrentTranscriptionModel
        }
    }
}

public struct VoiceInkOnboardingReadyPresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let subtitle: String
    public let steps: [VoiceInkOnboardingStepPresentation]
    public let primaryButtonTitle: String

    public init(
        iconSystemName: String,
        title: String,
        subtitle: String,
        steps: [VoiceInkOnboardingStepPresentation],
        primaryButtonTitle: String
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.subtitle = subtitle
        self.steps = steps
        self.primaryButtonTitle = primaryButtonTitle
    }
}

public struct VoiceInkIOSKeyboardReadinessObservation: Equatable, Sendable {
    public let hasFullAccess: Bool
    public let observedAt: Date

    public init(hasFullAccess: Bool, observedAt: Date) {
        self.hasFullAccess = hasFullAccess
        self.observedAt = observedAt
    }
}

public enum VoiceInkIOSKeyboardReadinessStatus: Equatable, Sendable {
    case unverified
    case fullAccessRequired
    case ready
}

public enum VoiceInkIOSKeyboardReadinessPolicy {
    public static func status(
        observation: VoiceInkIOSKeyboardReadinessObservation?,
        verificationStartedAt: Date
    ) -> VoiceInkIOSKeyboardReadinessStatus {
        guard let observation, observation.observedAt >= verificationStartedAt else {
            return .unverified
        }

        return observation.hasFullAccess ? .ready : .fullAccessRequired
    }
}

public struct VoiceInkIOSKeyboardReadinessStatusPresentation: Equatable, Sendable {
    public let iconSystemName: String
    public let title: String
    public let detail: String

    public init(iconSystemName: String, title: String, detail: String) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.detail = detail
    }
}

public enum VoiceInkMacOSOnboardingPresentation {
    public static let welcome = VoiceInkMacOSOnboardingWelcomePresentation(
        title: "Welcome to the Future of Typing",
        subtitle: "A New Way to Type",
        primaryButtonTitle: "Get Started",
        skipButtonTitle: "Skip Tour",
        typewriterRoles: [
            "Your Writing Assistant",
            "Your Vibe-Coding Assistant",
            "Works Everywhere on Mac with a click",
            "100% offline & private"
        ]
    )

    public static let modelDownload = VoiceInkMacOSOnboardingModelDownloadPresentation(
        title: "Download AI Model",
        subtitle: "Choose a local model and download it for offline dictation, or select another option. You can also skip setup for now.",
        nextButtonTitle: "Next",
        skipButtonTitle: "Skip for now"
    )

    public static let tutorial = VoiceInkMacOSOnboardingTutorialPresentation(
        title: "Try It Out!",
        subtitle: "Let's test your roma-just-talk setup.",
        shortcutTitle: "Your Shortcut",
        instructionSteps: [
            "Click the text area on the right",
            "Press your shortcut key",
            "Speak something",
            "Press your shortcut key again"
        ],
        completeButtonTitle: "Complete Setup",
        skipButtonTitle: "Skip for now",
        placeholderIconSystemName: "wand.and.stars",
        placeholderText: "Click here and start speaking..."
    )

    public static let resetSettingsAlert = VoiceInkMacOSResetOnboardingPresentation(
        buttonTitle: "Reset Onboarding",
        alertTitle: "Reset Onboarding",
        cancelButtonTitle: "Cancel",
        confirmButtonTitle: "Reset",
        message: "You'll see the introduction screens again the next time you launch the app."
    )
}

public enum VoiceInkMacOSSetupPresentation {
    public static let title = "Welcome to VoiceInk"
    public static let subtitle = "Complete the setup to get started"
    public static let helpText = "Need help? Check the Help menu for support options"
    public static let actionSystemImageName = "arrow.right"
    public static let completedSystemImageName = "checkmark.circle.fill"
    public static let optionalSystemImageName = "circle"
    public static let requiredSystemImageName = "chevron.right"

    public static let steps = [
        VoiceInkMacOSSetupStepPresentation(
            kind: .shortcut,
            isOptional: false,
            iconSystemName: "command",
            title: "Set Keyboard Shortcut",
            description: "Use VoiceInk anywhere with a shortcut."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .accessibility,
            isOptional: false,
            iconSystemName: "hand.raised.fill",
            title: "Enable Accessibility",
            description: "Paste transcribed text at your cursor."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .screenContext,
            isOptional: true,
            iconSystemName: "video.fill",
            title: "Screen Context (Optional)",
            description: "Use visible text for better transcript enhancement when you choose."
        ),
        VoiceInkMacOSSetupStepPresentation(
            kind: .modelDownload,
            isOptional: false,
            iconSystemName: "arrow.down.to.line",
            title: "Download Model",
            description: "Choose an AI model to start transcribing."
        )
    ]

    public static func actionButtonTitle(
        isShortcutConfigured: Bool,
        isAccessibilityEnabled: Bool,
        hasTranscriptionModel: Bool
    ) -> String {
        if !isShortcutConfigured {
            return "Configure Shortcut"
        }
        if !isAccessibilityEnabled {
            return "Enable Accessibility"
        }
        if !hasTranscriptionModel {
            return "Download Model"
        }
        return "Get Started"
    }
}

public enum VoiceInkIOSOnboardingStep: String, CaseIterable, Equatable, Sendable {
    case welcome
    case microphoneSetup
    case modelDownload
    case keyboardSetup
    case tutorial
    case ready

    public static let initial = VoiceInkIOSOnboardingStep.welcome

    public var nextStep: VoiceInkIOSOnboardingStep? {
        switch self {
        case .welcome:
            return .microphoneSetup
        case .microphoneSetup:
            return .modelDownload
        case .modelDownload:
            return .keyboardSetup
        case .keyboardSetup:
            return .tutorial
        case .tutorial:
            return .ready
        case .ready:
            return nil
        }
    }

    public mutating func advance() {
        guard let followingStep = nextStep else { return }
        self = followingStep
    }
}

public enum VoiceInkIOSOnboardingProgressStore {
    private static let stepKey = "iOSOnboardingStep"

    public static func step(in defaults: UserDefaults = .standard) -> VoiceInkIOSOnboardingStep {
        defaults.string(forKey: stepKey)
            .flatMap(VoiceInkIOSOnboardingStep.init(rawValue:)) ?? .initial
    }

    public static func save(
        _ step: VoiceInkIOSOnboardingStep,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(step.rawValue, forKey: stepKey)
    }

    public static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: stepKey)
    }
}

public enum VoiceInkIOSOnboardingPresentation {
    public static let appIconFallbackSystemImageName = "app.fill"

    public static let welcome = VoiceInkOnboardingWelcomePresentation(
        title: VoiceInkAppIdentity.welcomeTitle,
        subtitle: "Transform your thoughts into text effortlessly.",
        features: [
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "mic.fill",
                title: "Instant Recording",
                description: "Capture your thoughts with a single tap, anytime, anywhere."
            ),
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "bolt.fill",
                title: "Accurate Transcription",
                description: "Leverage powerful AI models for precise speech-to-text conversion."
            ),
            VoiceInkOnboardingFeaturePresentation(
                iconSystemName: "icloud.slash.fill",
                title: "Works Offline",
                description: "Transcribe without an internet connection using local models."
            )
        ],
        primaryButtonTitle: "Get Started"
    )

    public static let modelDownload = VoiceInkOnboardingModelDownloadPresentation(
        iconSystemName: "cpu",
        title: "Offline Transcription",
        subtitle: "Download a local model to transcribe audio even without an internet connection.",
        continueButtonTitle: "Continue"
    )

    public static let defaultDownloadModel: VoiceInkWhisperModelFileSpec = VoiceInkWhisperModelFiles.baseModel

    public static let ready = VoiceInkOnboardingReadyPresentation(
        iconSystemName: "checkmark.circle.fill",
        title: "You're All Set!",
        subtitle: "Start recording your thoughts and ideas.",
        steps: [
            VoiceInkOnboardingStepPresentation(
                number: "1",
                title: "Record",
                description: "Tap the record button to capture your thoughts."
            ),
            VoiceInkOnboardingStepPresentation(
                number: "2",
                title: "Transcribe",
                description: "AI converts your speech to text automatically."
            ),
            VoiceInkOnboardingStepPresentation(
                number: "3",
                title: "Save & Organize",
                description: "Your notes are saved and ready for review."
            )
        ],
        primaryButtonTitle: VoiceInkAppIdentity.startUsingTitle
    )
}

public enum VoiceInkIOSKeyboardSetupPresentation {
    public static let navigationTitle = "Keyboard Setup"
    public static let iconSystemName = "keyboard"
    public static let title = "Enable the Keyboard"
    public static let subtitle = "Add roma just talk as a keyboard and allow Full Access so dictation can return text to the field where you started."
    public static let openSettingsButtonTitle = "Open App Settings"
    public static let openSettingsButtonSystemImageName = "gear"
    public static let testFieldTitle = "Verify Keyboard"
    public static let testFieldPlaceholder = "Tap here, then select roma just talk"
    public static let testFieldHelp = "Use the globe key to select roma just talk. Readiness updates when the keyboard appears."
    public static let continueButtonTitle = "Continue"
    public static let skipButtonTitle = "Set Up Later"
    public static let settingsRowTitle = "Keyboard Setup"
    public static let settingsRowSystemImageName = "keyboard"
    public static let instructions = [
        VoiceInkOnboardingStepPresentation(
            number: "1",
            title: "Add the Keyboard",
            description: "In Settings, open General > Keyboard > Keyboards > Add New Keyboard and choose roma just talk."
        ),
        VoiceInkOnboardingStepPresentation(
            number: "2",
            title: "Allow Full Access",
            description: "Open roma just talk in the keyboard list and turn on Allow Full Access."
        ),
        VoiceInkOnboardingStepPresentation(
            number: "3",
            title: "Verify Here",
            description: "Return to this screen, tap the test field, and select roma just talk with the globe key."
        )
    ]

    public static func status(
        _ readiness: VoiceInkIOSKeyboardReadinessStatus
    ) -> VoiceInkIOSKeyboardReadinessStatusPresentation {
        switch readiness {
        case .unverified:
            return VoiceInkIOSKeyboardReadinessStatusPresentation(
                iconSystemName: "keyboard",
                title: "Keyboard Not Verified",
                detail: "Complete the steps below, then activate roma just talk in the test field."
            )
        case .fullAccessRequired:
            return VoiceInkIOSKeyboardReadinessStatusPresentation(
                iconSystemName: "exclamationmark.triangle.fill",
                title: "Full Access Is Off",
                detail: "Turn on Allow Full Access in Settings, then activate the keyboard here again."
            )
        case .ready:
            return VoiceInkIOSKeyboardReadinessStatusPresentation(
                iconSystemName: "checkmark.circle.fill",
                title: "Keyboard Ready",
                detail: "roma just talk was activated with Full Access on this screen."
            )
        }
    }
}

public enum VoiceInkIOSAppIconSource: Equatable, Sendable {
    case assetName(String)
    case fallbackSystemImageName(String)
}

public enum VoiceInkIOSAppIconPolicy {
    private static let bundleIconsKey = "CFBundleIcons"
    private static let bundlePrimaryIconKey = "CFBundlePrimaryIcon"
    private static let bundleIconFilesKey = "CFBundleIconFiles"

    public static func bundleIconFiles(from infoDictionary: [String: Any]?) -> [String]? {
        guard let iconsDictionary = infoDictionary?[bundleIconsKey] as? [String: Any],
              let primaryIconsDictionary = iconsDictionary[bundlePrimaryIconKey] as? [String: Any] else {
            return nil
        }

        return primaryIconsDictionary[bundleIconFilesKey] as? [String]
    }

    public static func source(
        iconFiles: [String]?,
        canLoadImageNamed: (String) -> Bool
    ) -> VoiceInkIOSAppIconSource {
        guard let iconName = iconFiles?.last, canLoadImageNamed(iconName) else {
            return .fallbackSystemImageName(VoiceInkIOSOnboardingPresentation.appIconFallbackSystemImageName)
        }

        return .assetName(iconName)
    }
}

public enum VoiceInkMacOSOnboardingPermissionKind: String, Equatable, Sendable {
    case microphone
    case audioDeviceSelection
    case accessibility
    case inputMonitoring
    case screenRecording
    case keyboardShortcut
}

public enum VoiceInkMacOSOnboardingStage: String, Equatable, Sendable {
    case welcome
    case permissions
    case modelDownload
    case tutorial

    public var resumesPermissionsView: Bool {
        self != .welcome
    }

    public var resumesModelDownload: Bool {
        self == .modelDownload || self == .tutorial
    }

    public var resumesTutorial: Bool {
        self == .tutorial
    }
}

public enum VoiceInkMacOSOnboardingProgressStore {
    private static let stageKey = "macOSOnboardingStage"
    private static let permissionKindKey = "macOSOnboardingPermissionKind"

    public static func stage(in defaults: UserDefaults = .standard) -> VoiceInkMacOSOnboardingStage {
        defaults.string(forKey: stageKey)
            .flatMap(VoiceInkMacOSOnboardingStage.init(rawValue:)) ?? .welcome
    }

    public static func saveStage(
        _ stage: VoiceInkMacOSOnboardingStage,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(stage.rawValue, forKey: stageKey)
    }

    public static func permissionKind(
        in defaults: UserDefaults = .standard
    ) -> VoiceInkMacOSOnboardingPermissionKind? {
        defaults.string(forKey: permissionKindKey)
            .flatMap(VoiceInkMacOSOnboardingPermissionKind.init(rawValue:))
    }

    public static func savePermissionKind(
        _ kind: VoiceInkMacOSOnboardingPermissionKind,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(kind.rawValue, forKey: permissionKindKey)
    }

    public static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: stageKey)
        defaults.removeObject(forKey: permissionKindKey)
    }
}

public struct VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation: Equatable, Sendable {
    public let emptyStateTitle: String
    public let pickerLabel: String
    public let selectedDevicePlaceholder: String
    public let unknownDeviceName: String
    public let recommendationText: String

    public init(
        emptyStateTitle: String,
        pickerLabel: String,
        selectedDevicePlaceholder: String,
        unknownDeviceName: String,
        recommendationText: String
    ) {
        self.emptyStateTitle = emptyStateTitle
        self.pickerLabel = pickerLabel
        self.selectedDevicePlaceholder = selectedDevicePlaceholder
        self.unknownDeviceName = unknownDeviceName
        self.recommendationText = recommendationText
    }
}

public struct VoiceInkMacOSOnboardingPermissionPresentation: Identifiable, Equatable, Sendable {
    public let kind: VoiceInkMacOSOnboardingPermissionKind
    public let title: String
    public let description: String
    public let iconSystemName: String
    public let audioDeviceSelection: VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation?

    public var id: VoiceInkMacOSOnboardingPermissionKind { kind }

    public init(
        kind: VoiceInkMacOSOnboardingPermissionKind,
        title: String,
        description: String,
        iconSystemName: String,
        audioDeviceSelection: VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation? = nil
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.iconSystemName = iconSystemName
        self.audioDeviceSelection = audioDeviceSelection
    }

    public static let relaunchRequiredMessage =
        "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."

    public static let skipButtonTitle = "Skip for now"

    public static let audioDeviceSelectionPresentation = VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation(
        emptyStateTitle: "No microphones found",
        pickerLabel: "Microphone:",
        selectedDevicePlaceholder: "Select Device",
        unknownDeviceName: "Unknown Device",
        recommendationText: "For best results, using your Mac's built-in microphone is recommended."
    )

    public static let screenContextInfoHelpMessage =
        "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored."

    public static let screenContextInfoLearnMoreURLString = "https://tryvoiceink.com/docs/contextual-awareness"

    public static let all = [
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .microphone,
            title: "Microphone Access",
            description: "Enable your microphone to start speaking and converting your voice to text instantly.",
            iconSystemName: "waveform"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .audioDeviceSelection,
            title: "Microphone Selection",
            description: "Select the audio input device you want to use with roma-just-talk.",
            iconSystemName: "headphones",
            audioDeviceSelection: audioDeviceSelectionPresentation
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .accessibility,
            title: "Accessibility Access",
            description: "Add roma-just-talk to Accessibility, then turn its switch on.",
            iconSystemName: "accessibility"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .inputMonitoring,
            title: "Input Monitoring",
            description: "Allow roma-just-talk to detect your recording shortcut while other apps are active.",
            iconSystemName: "keyboard.badge.eye"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .screenRecording,
            title: "Screen Context (Optional)",
            description: "Enable screen context only if you want roma-just-talk to use visible text for transcript enhancement.",
            iconSystemName: "rectangle.inset.filled.and.person.filled"
        ),
        VoiceInkMacOSOnboardingPermissionPresentation(
            kind: .keyboardShortcut,
            title: "Keyboard Shortcut",
            description: "Set up a keyboard shortcut to quickly access roma-just-talk from anywhere.",
            iconSystemName: "keyboard"
        )
    ]

    public var screenContextInfoMessage: String? {
        kind == .screenRecording ? Self.screenContextInfoHelpMessage : nil
    }

    public var screenContextInfoURLString: String? {
        kind == .screenRecording ? Self.screenContextInfoLearnMoreURLString : nil
    }

    public var canSkipWhenNotGranted: Bool {
        kind != .audioDeviceSelection
    }

    public func buttonTitle(isGranted: Bool, requiresRelaunch: Bool) -> String {
        if requiresRelaunch {
            return "Relaunch to Apply"
        }

        switch kind {
        case .keyboardShortcut:
            return isGranted ? "Continue" : "Set Shortcut"
        case .audioDeviceSelection:
            return "Continue"
        case .screenRecording:
            return isGranted ? "Continue" : "Enable"
        case .microphone, .accessibility, .inputMonitoring:
            return isGranted ? "Continue" : "Grant"
        }
    }
}

public enum VoiceInkMacOSPermissionSettingsCardKind: String, Equatable, Sendable {
    case inputMonitoring
    case microphone
    case accessibility
    case screenContext
}

public struct VoiceInkMacOSPermissionSettingsCardPresentation: Identifiable, Equatable, Sendable {
    public let kind: VoiceInkMacOSPermissionSettingsCardKind
    public let iconSystemName: String
    public let title: String
    public let description: String
    public let grantButtonTitle: String
    public let relaunchButtonTitle: String?
    public let infoTipMessage: String?
    public let infoTipURLString: String?

    public var id: VoiceInkMacOSPermissionSettingsCardKind { kind }

    public init(
        kind: VoiceInkMacOSPermissionSettingsCardKind,
        iconSystemName: String,
        title: String,
        description: String,
        grantButtonTitle: String,
        relaunchButtonTitle: String? = nil,
        infoTipMessage: String? = nil,
        infoTipURLString: String? = nil
    ) {
        self.kind = kind
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
        self.grantButtonTitle = grantButtonTitle
        self.relaunchButtonTitle = relaunchButtonTitle
        self.infoTipMessage = infoTipMessage
        self.infoTipURLString = infoTipURLString
    }

    public var grantedIconSystemName: String {
        "\(iconSystemName).fill"
    }

    public func buttonTitle(requiresRelaunch: Bool) -> String {
        if requiresRelaunch, let relaunchButtonTitle {
            return relaunchButtonTitle
        }
        return grantButtonTitle
    }
}

public enum VoiceInkMacOSPermissionSettingsPresentation {
    public static let headerIconSystemName = "shield.lefthalf.filled"
    public static let headerTitle = "App Permissions"
    public static let headerDescription =
        "Microphone and shortcut access are needed for recording. Screen context is optional."
    public static let relaunchRequiredMessage =
        "If you already turned this on in System Settings, relaunch roma-just-talk to activate it."
    public static let refreshButtonSystemImageName = "arrow.clockwise"
    public static let grantedStatusSystemImageName = "checkmark.seal.fill"
    public static let deniedStatusSystemImageName = "xmark.seal.fill"
    public static let actionSystemImageName = "arrow.right"

    public static let inputMonitoringCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .inputMonitoring,
        iconSystemName: "keyboard.badge.eye",
        title: "Input Monitoring Access",
        description: "Allow roma-just-talk to listen for your recording hotkey globally",
        grantButtonTitle: "Grant",
        relaunchButtonTitle: "Relaunch to Apply",
        infoTipMessage: "roma-just-talk uses Input Monitoring only to detect your configured recording shortcut while other apps are active."
    )

    public static let microphoneCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .microphone,
        iconSystemName: "mic",
        title: "Microphone Access",
        description: "Allow roma-just-talk to record your voice for transcription",
        grantButtonTitle: "Grant"
    )

    public static let accessibilityCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .accessibility,
        iconSystemName: "hand.raised",
        title: "Accessibility Access",
        description: "Add roma-just-talk to Accessibility, then turn its switch on",
        grantButtonTitle: "Grant",
        infoTipMessage: "macOS requires you to enable the roma-just-talk switch yourself. Dragging the app into the list only adds it when it is missing."
    )

    public static let dashboardAccessibilityCallout = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .accessibility,
        iconSystemName: "hand.raised",
        title: "Accessibility Access",
        description: "VoiceInk needs Accessibility permission to work reliably across your entire Mac",
        grantButtonTitle: "Open System Settings",
        infoTipMessage: "VoiceInk uses Accessibility to work reliably across apps."
    )

    public static let screenContextCard = VoiceInkMacOSPermissionSettingsCardPresentation(
        kind: .screenContext,
        iconSystemName: "rectangle.on.rectangle",
        title: "Screen Context (Optional)",
        description: "Use visible screen text to improve transcript enhancement when you choose.",
        grantButtonTitle: "Enable",
        relaunchButtonTitle: "Relaunch to Apply",
        infoTipMessage: "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
        infoTipURLString: "https://tryvoiceink.com/docs/contextual-awareness"
    )
}

public struct VoiceInkMacOSPermissionPollingState: Equatable, Sendable {
    public private(set) var pollsRemaining: Int

    public static let stopped = VoiceInkMacOSPermissionPollingState(pollsRemaining: 0)

    public var isActive: Bool {
        pollsRemaining > 0
    }

    public init(pollsRemaining: Int) {
        self.pollsRemaining = max(0, pollsRemaining)
    }

    public static func started(limit: Int = VoiceInkMacOSPermissionTimingPolicy.refreshPollLimit) -> Self {
        VoiceInkMacOSPermissionPollingState(pollsRemaining: limit)
    }

    @discardableResult
    public mutating func consumePollAndShouldStop() -> Bool {
        guard pollsRemaining > 0 else {
            return true
        }

        pollsRemaining -= 1
        return pollsRemaining <= 0
    }
}

public enum VoiceInkMacOSPermissionTimingPolicy {
    public static let pollingInterval: TimeInterval = 0.5
    public static let refreshPollLimit = 120
    public static let relaunchRequiredDelay: TimeInterval = 6.0
    public static let manualRefreshAnimationResetDelay: TimeInterval = 0.5
    public static let floatingAuthorizationPanelDelay: TimeInterval = 0.25
    public static let openPermissionsGrantMicrophoneDelay: TimeInterval = 0.2
}
