import Foundation

public struct RuntimeTimingPlan: Codable, Equatable, Sendable {
    public let keyDownOffsetSeconds: TimeInterval
    public let keyUpOffsetSeconds: TimeInterval
    public let releaseTailSeconds: TimeInterval

    public var holdDurationSeconds: TimeInterval {
        keyUpOffsetSeconds - keyDownOffsetSeconds
    }

    public init(
        audioDurationSeconds: TimeInterval,
        audioLeadSeconds: TimeInterval,
        releaseTailSeconds: TimeInterval
    ) throws {
        guard audioDurationSeconds > 0,
              audioLeadSeconds >= 0,
              releaseTailSeconds >= 0,
              audioDurationSeconds + releaseTailSeconds > audioLeadSeconds else {
            throw RuntimeTimingPlanError.invalidTiming
        }

        keyDownOffsetSeconds = audioLeadSeconds
        keyUpOffsetSeconds = audioDurationSeconds + releaseTailSeconds
        self.releaseTailSeconds = releaseTailSeconds
    }

    public func keyUpSystemUptime(
        audioStartedAtSystemUptime: TimeInterval,
        audioFinishedAtSystemUptime: TimeInterval
    ) -> TimeInterval {
        max(
            audioStartedAtSystemUptime + keyUpOffsetSeconds,
            audioFinishedAtSystemUptime + releaseTailSeconds
        )
    }
}

public enum RuntimeTimingPlanError: Error, Equatable, Sendable {
    case invalidTiming
}

public enum RuntimePlaybackReleasePolicy {
    public static let completionGraceSeconds: TimeInterval = 5

    public static func waitsForPlaybackCompletion(
        explicitHoldSeconds: TimeInterval?
    ) -> Bool {
        explicitHoldSeconds == nil
    }
}

public struct RuntimeTargetApp: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case document
        case browser
        case electron

        public var usesDocumentResource: Bool {
            self != .browser
        }

        public var requiresPasteSemantics: Bool {
            self != .document
        }

        public func satisfiesPasteSemantics(
            directAccessibilityInsertionSucceeded: Bool,
            clipboardPasteHandoffCompleted: Bool
        ) -> Bool {
            !requiresPasteSemantics
                || (!directAccessibilityInsertionSucceeded && clipboardPasteHandoffCompleted)
        }
    }

    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let kind: Kind

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        kind: Kind
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.kind = kind
    }

    public static let defaultMatrix: [Self] = [
        Self(id: "textedit", displayName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", kind: .document),
        Self(id: "safari", displayName: "Safari", bundleIdentifier: "com.apple.Safari", kind: .browser),
        Self(id: "chrome", displayName: "Google Chrome", bundleIdentifier: "com.google.Chrome", kind: .browser),
        Self(id: "arc", displayName: "Arc", bundleIdentifier: "company.thebrowser.Browser", kind: .browser),
        Self(id: "zed", displayName: "Zed", bundleIdentifier: "dev.zed.Zed", kind: .document),
        Self(
            id: "vscode",
            displayName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            kind: .electron
        )
    ]
}

public enum RuntimeTextScenario: String, Codable, CaseIterable, Sendable {
    case empty
    case existingText

    public var prefix: String {
        self == .existingText ? "[existing before]" : ""
    }

    public var suffix: String {
        self == .existingText ? "[existing after]" : ""
    }

    public var initialText: String {
        prefix + suffix
    }

    public var cursorUTF16Offset: Int {
        prefix.utf16.count
    }

    public func insertedText(from finalText: String) -> String? {
        guard finalText.hasPrefix(prefix), finalText.hasSuffix(suffix) else {
            return nil
        }
        return String(finalText.dropFirst(prefix.count).dropLast(suffix.count))
    }
}

public struct RuntimeDOMPasteProof: Codable, Equatable, Sendable {
    public let pasteEventCount: Int
    public let pasteInputCount: Int

    public init(pasteEventCount: Int, pasteInputCount: Int) {
        self.pasteEventCount = pasteEventCount
        self.pasteInputCount = pasteInputCount
    }

    public var provesExactlyOnePaste: Bool {
        pasteEventCount == 1 && pasteInputCount == 1
    }

    public static func parse(from text: String) -> Self? {
        var fields: [String: Int] = [:]
        for component in text.split(whereSeparator: \.isWhitespace) {
            let parts = component.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            fields[String(parts[0])] = value
        }
        guard let pasteEventCount = fields["pasteEvents"],
              let pasteInputCount = fields["pasteInputs"] else {
            return nil
        }
        return Self(
            pasteEventCount: pasteEventCount,
            pasteInputCount: pasteInputCount
        )
    }
}

public enum RuntimeTargetIsolationPlan {
    public static func visibilityCalibrationRunID(
        targetID: String,
        textScenario: RuntimeTextScenario
    ) -> String {
        "visibility-calibration-\(targetID)-\(textScenario.rawValue)-r1-\(UUID().uuidString.prefix(6))"
    }

    public static func runID(_ runID: String, belongsToTargetID targetID: String) -> Bool {
        if runID.contains("-\(targetID)-r") {
            return true
        }
        return RuntimeTextScenario.allCases.contains {
            runID.contains("-\(targetID)-\($0.rawValue)-r")
        }
    }

    public static func documentFilename(
        windowTitleToken: String,
        bundleIdentifier: String
    ) -> String {
        let pathExtension = bundleIdentifier == "com.apple.ScriptEditor2"
            ? "applescript"
            : "txt"
        return "\(windowTitleToken).\(pathExtension)"
    }

    public static func chromeArguments(resourceURL: URL) -> [String] {
        [
            "--force-renderer-accessibility",
            "--new-window",
            resourceURL.absoluteString
        ]
    }

    public static func vscodeArguments(resourcePath: String) -> [String] {
        [
            "--force-renderer-accessibility",
            "--disable-extensions",
            "--skip-welcome",
            "--new-window",
            resourcePath
        ]
    }

    public static func matchesAccessibilityBaseline(
        _ observedText: String?,
        scenario: RuntimeTextScenario,
        targetKind: RuntimeTargetApp.Kind
    ) -> Bool {
        guard let observedText else { return false }
        if targetKind == .electron, scenario == .empty, observedText == "\n" {
            return true
        }
        return observedText == scenario.initialText
    }

    public static func browserEditableLabel(windowTitleToken: String) -> String {
        "Roma Runtime E2E target \(windowTitleToken)"
    }
}

public enum RuntimeTargetAvailabilitySelector {
    public static func select(
        configuredTargets: [RuntimeTargetApp],
        runningBundleIdentifiers: Set<String>,
        policy: RuntimeHarnessConfiguration.TargetAvailabilityPolicy
    ) -> [RuntimeTargetApp] {
        switch policy {
        case .runningOnly:
            return configuredTargets.filter {
                runningBundleIdentifiers.contains($0.bundleIdentifier)
            }
        case .launchIfNeeded:
            return configuredTargets
        }
    }
}

public enum RuntimeTargetCatalog {
    public static func restorationTargets(
        configuredTargets: [RuntimeTargetApp]
    ) -> [RuntimeTargetApp] {
        var seenBundleIdentifiers: Set<String> = []
        return (configuredTargets + RuntimeTargetApp.defaultMatrix).filter {
            seenBundleIdentifiers.insert($0.bundleIdentifier).inserted
        }
    }
}

public struct RuntimeLoopbackDeviceControlState: Codable, Equatable, Sendable {
    public let inputMuted: Bool?
    public let outputMuted: Bool?
    public let inputVolume: Double?
    public let outputVolume: Double?

    public init(
        inputMuted: Bool?,
        outputMuted: Bool?,
        inputVolume: Double?,
        outputVolume: Double?
    ) {
        self.inputMuted = inputMuted
        self.outputMuted = outputMuted
        self.inputVolume = inputVolume
        self.outputVolume = outputVolume
    }

    public var preparedForPlayback: Self {
        Self(
            inputMuted: inputMuted.map { _ in false },
            outputMuted: outputMuted.map { _ in false },
            inputVolume: inputVolume.map { _ in 1 },
            outputVolume: outputVolume.map { _ in 1 }
        )
    }
}

public struct RuntimeSystemOutputJournal: Codable, Equatable, Sendable {
    public let originalDeviceUID: String
    public let targetDeviceUID: String?
    public let targetControlState: RuntimeLoopbackDeviceControlState?

    public init(
        originalDeviceUID: String,
        targetDeviceUID: String?,
        targetControlState: RuntimeLoopbackDeviceControlState?
    ) {
        self.originalDeviceUID = originalDeviceUID
        self.targetDeviceUID = targetDeviceUID
        self.targetControlState = targetControlState
    }
}

public enum RuntimeTargetLifecyclePlan {
    public static func shouldRestoreApplication(
        wasRunningBeforePreparation: Bool,
        isRunningAfterCleanup: Bool
    ) -> Bool {
        wasRunningBeforePreparation && !isRunningAfterCleanup
    }
}

public struct RuntimeRunCase: Codable, Equatable, Sendable {
    public let fixtureURL: URL
    public let expectedTranscript: String?
    public let target: RuntimeTargetApp
    public let textScenario: RuntimeTextScenario
    public let repetition: Int

    public init(
        fixtureURL: URL,
        expectedTranscript: String?,
        target: RuntimeTargetApp,
        textScenario: RuntimeTextScenario,
        repetition: Int
    ) {
        self.fixtureURL = fixtureURL
        self.expectedTranscript = expectedTranscript
        self.target = target
        self.textScenario = textScenario
        self.repetition = repetition
    }
}

public struct RuntimeRunPlan: Codable, Equatable, Sendable {
    public let cases: [RuntimeRunCase]

    public init(cases: [RuntimeRunCase]) {
        self.cases = cases
    }

    public static func make(
        fixtureURLs: [URL],
        expectedTranscripts: [String: String],
        targets: [RuntimeTargetApp],
        repetitions: Int
    ) throws -> Self {
        guard repetitions > 0, !targets.isEmpty else {
            throw RuntimeRunPlanError.invalidMatrix
        }

        let supportedExtensions = Set(["wav", "wave", "aif", "aiff", "caf", "m4a", "mp3", "flac"])
        let fixtures = fixtureURLs
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !fixtures.isEmpty else {
            throw RuntimeRunPlanError.noAudioFixtures
        }

        var cases: [RuntimeRunCase] = []
        for fixtureURL in fixtures {
            for target in targets {
                for textScenario in RuntimeTextScenario.allCases {
                    for repetition in 1...repetitions {
                        cases.append(
                            RuntimeRunCase(
                                fixtureURL: fixtureURL,
                                expectedTranscript: expectedTranscripts[fixtureURL.lastPathComponent],
                                target: target,
                                textScenario: textScenario,
                                repetition: repetition
                            )
                        )
                    }
                }
            }
        }
        return Self(cases: cases)
    }
}

public enum RuntimeRunPlanError: Error, Equatable, Sendable {
    case invalidMatrix
    case noAudioFixtures
}

public struct RuntimeHarnessConfiguration: Codable, Equatable, Sendable {
    public enum VoiceInkLifecycle: String, Codable, Sendable {
        case reuse
        case relaunchPerFixture
        case relaunchPerCase
    }

    public enum TargetAvailabilityPolicy: String, Codable, Sendable {
        case runningOnly
        case launchIfNeeded
    }

    public var audioDirectory: String
    public var audioDeviceName: String
    public var voiceInkBundleIdentifier: String
    public var voiceInkAppPath: String?
    public var voiceInkBuildDirectory: String
    public var audioLeadSeconds: TimeInterval
    public var releaseTailSeconds: TimeInterval
    public var explicitHoldSeconds: TimeInterval?
    public var preRollWarmupSeconds: TimeInterval
    public var targetSettleSeconds: TimeInterval
    public var targetTextTimeoutSeconds: TimeInterval
    public var latencyThresholdMilliseconds: Double
    public var maximumWordErrorRate: Double
    public var repetitions: Int
    public var targets: [RuntimeTargetApp]
    public var targetAvailabilityPolicy: TargetAvailabilityPolicy
    public var minimumTargetCount: Int
    public var expectedTranscripts: [String: String]
    public var voiceInkLifecycle: VoiceInkLifecycle

    public init(
        audioDirectory: String,
        audioDeviceName: String,
        voiceInkBundleIdentifier: String,
        voiceInkAppPath: String?,
        voiceInkBuildDirectory: String,
        audioLeadSeconds: TimeInterval,
        releaseTailSeconds: TimeInterval,
        explicitHoldSeconds: TimeInterval?,
        preRollWarmupSeconds: TimeInterval,
        targetSettleSeconds: TimeInterval,
        targetTextTimeoutSeconds: TimeInterval,
        latencyThresholdMilliseconds: Double,
        maximumWordErrorRate: Double,
        repetitions: Int,
        targets: [RuntimeTargetApp],
        targetAvailabilityPolicy: TargetAvailabilityPolicy,
        minimumTargetCount: Int,
        expectedTranscripts: [String: String],
        voiceInkLifecycle: VoiceInkLifecycle
    ) {
        self.audioDirectory = audioDirectory
        self.audioDeviceName = audioDeviceName
        self.voiceInkBundleIdentifier = voiceInkBundleIdentifier
        self.voiceInkAppPath = voiceInkAppPath
        self.voiceInkBuildDirectory = voiceInkBuildDirectory
        self.audioLeadSeconds = audioLeadSeconds
        self.releaseTailSeconds = releaseTailSeconds
        self.explicitHoldSeconds = explicitHoldSeconds
        self.preRollWarmupSeconds = preRollWarmupSeconds
        self.targetSettleSeconds = targetSettleSeconds
        self.targetTextTimeoutSeconds = targetTextTimeoutSeconds
        self.latencyThresholdMilliseconds = latencyThresholdMilliseconds
        self.maximumWordErrorRate = maximumWordErrorRate
        self.repetitions = repetitions
        self.targets = targets
        self.targetAvailabilityPolicy = targetAvailabilityPolicy
        self.minimumTargetCount = minimumTargetCount
        self.expectedTranscripts = expectedTranscripts
        self.voiceInkLifecycle = voiceInkLifecycle
    }

    public static var `default`: Self {
        Self(
            audioDirectory: NSString(string: "~/Downloads/roma jt builds/audio").expandingTildeInPath,
            audioDeviceName: "BlackHole 2ch",
            voiceInkBundleIdentifier: "com.negentropi.RomaJustTalk",
            voiceInkAppPath: nil,
            voiceInkBuildDirectory: NSString(string: "~/Downloads/roma jt builds").expandingTildeInPath,
            audioLeadSeconds: 1.1,
            releaseTailSeconds: 0.15,
            explicitHoldSeconds: nil,
            preRollWarmupSeconds: 2,
            targetSettleSeconds: 1,
            targetTextTimeoutSeconds: 15,
            latencyThresholdMilliseconds: 250,
            maximumWordErrorRate: 0.2,
            repetitions: 3,
            targets: RuntimeTargetApp.defaultMatrix,
            targetAvailabilityPolicy: .runningOnly,
            minimumTargetCount: 4,
            expectedTranscripts: [:],
            voiceInkLifecycle: .reuse
        )
    }
}

public struct RuntimeVoiceInkCandidate: Codable, Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date

    public init(path: String, modifiedAt: Date) {
        self.path = path
        self.modifiedAt = modifiedAt
    }
}

public struct RuntimeVoiceInkSelection: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case explicit
        case runningBuild
        case buildDirectory
        case running
        case workspaceInstalled
    }

    public let path: String
    public let source: Source

    public init(path: String, source: Source) {
        self.path = path
        self.source = source
    }
}

public enum RuntimeVoiceInkCandidateSelector {
    public static func select(
        explicitPath: String?,
        runningPaths: [String],
        buildDirectoryPath: String,
        buildCandidates: [RuntimeVoiceInkCandidate],
        workspaceInstalledPath: String?
    ) -> RuntimeVoiceInkSelection? {
        if let explicitPath, !explicitPath.isEmpty {
            return RuntimeVoiceInkSelection(path: explicitPath, source: .explicit)
        }

        let buildDirectoryPrefix = URL(fileURLWithPath: buildDirectoryPath, isDirectory: true)
            .standardizedFileURL.path + "/"
        if let runningBuild = runningPaths.first(where: {
            URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(buildDirectoryPrefix)
        }) {
            return RuntimeVoiceInkSelection(path: runningBuild, source: .runningBuild)
        }

        if let newestBuild = buildCandidates.max(by: { $0.modifiedAt < $1.modifiedAt }) {
            return RuntimeVoiceInkSelection(path: newestBuild.path, source: .buildDirectory)
        }
        if let runningPath = runningPaths.first {
            return RuntimeVoiceInkSelection(path: runningPath, source: .running)
        }
        if let workspaceInstalledPath {
            return RuntimeVoiceInkSelection(path: workspaceInstalledPath, source: .workspaceInstalled)
        }
        return nil
    }
}

public enum RuntimeVoiceInkLaunchIdentityPolicy {
    public static func accepts(
        sourceBundlePath: String,
        runningBundlePath: String,
        sourceExecutableSHA256: String,
        runningExecutableSHA256: String,
        requireAppTranslocation: Bool
    ) -> Bool {
        guard !sourceExecutableSHA256.isEmpty,
              sourceExecutableSHA256 == runningExecutableSHA256 else {
            return false
        }

        let sourcePath = URL(fileURLWithPath: sourceBundlePath).standardizedFileURL.path
        let runningPath = URL(fileURLWithPath: runningBundlePath).standardizedFileURL.path
        if !requireAppTranslocation {
            return sourcePath == runningPath
        }

        let components = runningPath.split(separator: "/").map(String.init)
        guard let translocationIndex = components.firstIndex(of: "AppTranslocation"),
              translocationIndex + 3 == components.count - 1,
              components[translocationIndex + 2] == "d",
              components.last?.hasSuffix(".app") == true else {
            return false
        }
        return sourcePath != runningPath
    }
}

public struct RuntimeCaseObservation: Codable, Equatable, Sendable {
    public let visibleText: String?
    public let keyUpToVisibleMilliseconds: Double?
    public let clipboardChanged: Bool
    public let triggerObserved: Bool

    public init(
        visibleText: String?,
        keyUpToVisibleMilliseconds: Double?,
        clipboardChanged: Bool,
        triggerObserved: Bool
    ) {
        self.visibleText = visibleText
        self.keyUpToVisibleMilliseconds = keyUpToVisibleMilliseconds
        self.clipboardChanged = clipboardChanged
        self.triggerObserved = triggerObserved
    }
}

public struct RuntimeCaseAssessment: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case passed
        case preflightFailed
        case targetSetupFailed
        case audioFailed
        case shortcutFailed
        case shortcutTimingMismatch
        case triggerRejected
        case traceMissing
        case microphonePermissionUnavailable
        case transcriptionIncomplete
        case emptyTranscript
        case pasteSemanticsNotProven
        case pasteOperationCountMismatch
        case noPaste
        case clipboardOnly
        case renderNotObserved
        case slow
        case contentMismatch
        case targetCleanupFailed
    }

    public let status: Status
    public let passed: Bool
    public let wordErrorRate: Double?

    public init(status: Status, passed: Bool, wordErrorRate: Double? = nil) {
        self.status = status
        self.passed = passed
        self.wordErrorRate = wordErrorRate
    }

    public static func assess(
        observation: RuntimeCaseObservation,
        expectedTranscript: String?,
        latencyThresholdMilliseconds: Double,
        shortcutHoldMatched: Bool? = nil,
        microphonePermissionUnavailable: Bool? = nil,
        transcriptionCompleted: Bool? = nil,
        transcribedCharacterCount: Int? = nil,
        pasteSemanticsSatisfied: Bool? = nil,
        pasteOperationCountSatisfied: Bool? = nil,
        maximumWordErrorRate: Double = 0.2
    ) -> Self {
        guard observation.triggerObserved else {
            return Self(status: .triggerRejected, passed: false)
        }
        guard shortcutHoldMatched != false else {
            return Self(status: .shortcutTimingMismatch, passed: false)
        }
        guard microphonePermissionUnavailable != true else {
            return Self(status: .microphonePermissionUnavailable, passed: false)
        }
        guard transcriptionCompleted != false else {
            return Self(status: .transcriptionIncomplete, passed: false)
        }
        guard transcribedCharacterCount != 0 else {
            return Self(status: .emptyTranscript, passed: false)
        }
        guard pasteSemanticsSatisfied != false else {
            return Self(status: .pasteSemanticsNotProven, passed: false)
        }
        guard let visibleText = observation.visibleText,
              !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self(
                status: observation.clipboardChanged ? .clipboardOnly : .noPaste,
                passed: false
            )
        }
        guard pasteOperationCountSatisfied != false else {
            return Self(status: .pasteOperationCountMismatch, passed: false)
        }
        guard let latency = observation.keyUpToVisibleMilliseconds else {
            return Self(status: .renderNotObserved, passed: false)
        }
        guard latency <= latencyThresholdMilliseconds else {
            return Self(status: .slow, passed: false)
        }

        if let expectedTranscript,
           !expectedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let wordErrorRate = RuntimeTranscriptQuality.wordErrorRate(
                expected: expectedTranscript,
                actual: visibleText
            )
            guard wordErrorRate <= maximumWordErrorRate else {
                return Self(status: .contentMismatch, passed: false, wordErrorRate: wordErrorRate)
            }
            return Self(status: .passed, passed: true, wordErrorRate: wordErrorRate)
        }
        return Self(status: .passed, passed: true)
    }
}

public enum RuntimeFailureBoundary: String, Codable, Equatable, Sendable {
    case none
    case targetPreparation
    case audioInjection
    case shortcutInjection
    case shortcutDelivery
    case traceCollection
    case voiceInkTrigger
    case voiceInkShortcutEvidence
    case voiceInkMicrophonePermission
    case voiceInkTranscription
    case voiceInkPasteHandoff
    case pasteDeliveryOrTargetVisibility
    case latencyBudget
    case contentQuality
    case targetCleanup
}

public struct RuntimeCaseEvidence: Codable, Equatable, Sendable {
    public let targetPrepared: Bool
    public let audioPlaybackStarted: Bool
    public let shortcutDownPosted: Bool
    public let shortcutUpPosted: Bool
    public let emergencyShortcutReleasePosted: Bool
    public let voiceInkTriggerObserved: Bool
    public let voiceInkShortcutHoldMatched: Bool?
    public let voiceInkShortcutEvidenceRejected: Bool
    public let voiceInkTranscriptionCompleted: Bool
    public let voiceInkClipboardWriteSucceeded: Bool
    public let voiceInkPasteEventPosted: Bool
    public let voiceInkTextDeliveryHandoffSucceeded: Bool
    public let systemClipboardChangeObserved: Bool
    public let targetAccessibilityTextObserved: Bool
    public let targetVisibleTextObserved: Bool
    public let targetCleanupPassed: Bool?
    public let voiceInkMicrophonePermissionUnavailable: Bool?

    public init(
        targetPrepared: Bool,
        audioPlaybackStarted: Bool,
        shortcutDownPosted: Bool,
        shortcutUpPosted: Bool,
        emergencyShortcutReleasePosted: Bool,
        voiceInkTriggerObserved: Bool,
        voiceInkShortcutHoldMatched: Bool?,
        voiceInkShortcutEvidenceRejected: Bool,
        voiceInkTranscriptionCompleted: Bool,
        voiceInkClipboardWriteSucceeded: Bool,
        voiceInkPasteEventPosted: Bool,
        voiceInkTextDeliveryHandoffSucceeded: Bool,
        systemClipboardChangeObserved: Bool,
        targetAccessibilityTextObserved: Bool,
        targetVisibleTextObserved: Bool,
        targetCleanupPassed: Bool?,
        voiceInkMicrophonePermissionUnavailable: Bool? = nil
    ) {
        self.targetPrepared = targetPrepared
        self.audioPlaybackStarted = audioPlaybackStarted
        self.shortcutDownPosted = shortcutDownPosted
        self.shortcutUpPosted = shortcutUpPosted
        self.emergencyShortcutReleasePosted = emergencyShortcutReleasePosted
        self.voiceInkTriggerObserved = voiceInkTriggerObserved
        self.voiceInkShortcutHoldMatched = voiceInkShortcutHoldMatched
        self.voiceInkShortcutEvidenceRejected = voiceInkShortcutEvidenceRejected
        self.voiceInkTranscriptionCompleted = voiceInkTranscriptionCompleted
        self.voiceInkClipboardWriteSucceeded = voiceInkClipboardWriteSucceeded
        self.voiceInkPasteEventPosted = voiceInkPasteEventPosted
        self.voiceInkTextDeliveryHandoffSucceeded = voiceInkTextDeliveryHandoffSucceeded
        self.systemClipboardChangeObserved = systemClipboardChangeObserved
        self.targetAccessibilityTextObserved = targetAccessibilityTextObserved
        self.targetVisibleTextObserved = targetVisibleTextObserved
        self.targetCleanupPassed = targetCleanupPassed
        self.voiceInkMicrophonePermissionUnavailable = voiceInkMicrophonePermissionUnavailable
    }
}

public enum RuntimeFailureBoundaryPolicy {
    public static func classify(
        assessment: RuntimeCaseAssessment,
        evidence: RuntimeCaseEvidence,
        hasLatencyTrace: Bool
    ) -> RuntimeFailureBoundary {
        guard evidence.targetPrepared else { return .targetPreparation }
        guard evidence.audioPlaybackStarted else { return .audioInjection }
        guard evidence.shortcutDownPosted, evidence.shortcutUpPosted else { return .shortcutInjection }
        guard hasLatencyTrace else { return .traceCollection }
        guard evidence.voiceInkTriggerObserved else { return .voiceInkTrigger }
        if evidence.voiceInkShortcutEvidenceRejected { return .voiceInkShortcutEvidence }
        if evidence.voiceInkShortcutHoldMatched == false { return .shortcutDelivery }
        if evidence.voiceInkMicrophonePermissionUnavailable == true {
            return .voiceInkMicrophonePermission
        }
        guard evidence.voiceInkTranscriptionCompleted else { return .voiceInkTranscription }
        if assessment.status == .emptyTranscript { return .voiceInkTranscription }
        if assessment.status == .pasteSemanticsNotProven { return .voiceInkPasteHandoff }
        guard evidence.voiceInkTextDeliveryHandoffSucceeded else {
            return .voiceInkPasteHandoff
        }
        guard evidence.targetVisibleTextObserved else { return .pasteDeliveryOrTargetVisibility }
        if assessment.status == .pasteOperationCountMismatch {
            return .pasteDeliveryOrTargetVisibility
        }
        if assessment.status == .slow { return .latencyBudget }
        if assessment.status == .contentMismatch { return .contentQuality }
        if evidence.targetCleanupPassed == false { return .targetCleanup }
        return .none
    }
}

public enum RuntimeStatistics {
    public static func percentile(_ percentile: Double, values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(ceil((percentile / 100) * Double(sorted.count))) - 1
        return sorted[max(0, min(index, sorted.count - 1))]
    }
}

public struct RuntimeRenderedPixelDifference: Equatable, Sendable {
    public let changedPixels: Int
    public let comparedPixels: Int
    public let requiredChangedPixels: Int

    public var passed: Bool {
        changedPixels >= requiredChangedPixels
    }
}

public enum RuntimeRenderedTextChangePolicy {
    public static let channelThreshold: UInt8 = 24

    public static func requiredChangedPixels(for _: Int) -> Int {
        80
    }

    public static func maximumStableJitterPixels(requiredChangedPixels: Int) -> Int {
        max(8, requiredChangedPixels / 4)
    }

    public static func compareRGBA(
        baseline: [UInt8],
        current: [UInt8]
    ) -> RuntimeRenderedPixelDifference? {
        guard baseline.count == current.count,
              baseline.count.isMultiple(of: 4) else {
            return nil
        }

        var changedPixels = 0
        for offset in stride(from: 0, to: baseline.count, by: 4) {
            let red = abs(Int(baseline[offset]) - Int(current[offset]))
            let green = abs(Int(baseline[offset + 1]) - Int(current[offset + 1]))
            let blue = abs(Int(baseline[offset + 2]) - Int(current[offset + 2]))
            if max(red, green, blue) >= Int(channelThreshold) {
                changedPixels += 1
            }
        }

        let pixelCount = baseline.count / 4
        return RuntimeRenderedPixelDifference(
            changedPixels: changedPixels,
            comparedPixels: pixelCount,
            requiredChangedPixels: requiredChangedPixels(for: pixelCount)
        )
    }
}

public struct RuntimeRenderedTextStabilitySample: Equatable, Sendable {
    public let baselineDifference: RuntimeRenderedPixelDifference
    public let interFrameChangedPixels: Int?
    public let stable: Bool
}

public struct RuntimeRenderedTextStabilityTracker: Sendable {
    private let baseline: [UInt8]
    private var previousPassingFrame: [UInt8]?

    public init(baseline: [UInt8]) {
        self.baseline = baseline
    }

    public mutating func observe(
        current: [UInt8]
    ) -> RuntimeRenderedTextStabilitySample? {
        guard let baselineDifference = RuntimeRenderedTextChangePolicy.compareRGBA(
            baseline: baseline,
            current: current
        ) else {
            return nil
        }
        guard baselineDifference.passed else {
            previousPassingFrame = nil
            return RuntimeRenderedTextStabilitySample(
                baselineDifference: baselineDifference,
                interFrameChangedPixels: nil,
                stable: false
            )
        }

        let interFrameChangedPixels = previousPassingFrame.flatMap {
            RuntimeRenderedTextChangePolicy.compareRGBA(
                baseline: $0,
                current: current
            )?.changedPixels
        }
        previousPassingFrame = current
        let stable = interFrameChangedPixels.map {
            $0 <= RuntimeRenderedTextChangePolicy.maximumStableJitterPixels(
                requiredChangedPixels: baselineDifference.requiredChangedPixels
            )
        } ?? false
        return RuntimeRenderedTextStabilitySample(
            baselineDifference: baselineDifference,
            interFrameChangedPixels: interFrameChangedPixels,
            stable: stable
        )
    }
}

public struct RuntimeRenderedTextLatencySample: Equatable, Sendable {
    public let stabilitySample: RuntimeRenderedTextStabilitySample
    public let firstPersistentChangeAtSystemUptime: TimeInterval?
}

public struct RuntimeRenderedTextLatencyTracker: Sendable {
    private var stabilityTracker: RuntimeRenderedTextStabilityTracker
    private var candidateChangeAtSystemUptime: TimeInterval?

    public init(baseline: [UInt8]) {
        stabilityTracker = RuntimeRenderedTextStabilityTracker(baseline: baseline)
    }

    public mutating func observe(
        current: [UInt8],
        atSystemUptime observedAtSystemUptime: TimeInterval
    ) -> RuntimeRenderedTextLatencySample? {
        guard let sample = stabilityTracker.observe(current: current) else {
            return nil
        }

        if !sample.baselineDifference.passed {
            candidateChangeAtSystemUptime = nil
        } else if sample.interFrameChangedPixels == nil || !sample.stable {
            candidateChangeAtSystemUptime = observedAtSystemUptime
        }

        return RuntimeRenderedTextLatencySample(
            stabilitySample: sample,
            firstPersistentChangeAtSystemUptime: sample.stable
                ? candidateChangeAtSystemUptime ?? observedAtSystemUptime
                : nil
        )
    }
}

public enum RuntimeTextVisibilityAttribution {
    public static func renderedLatency(
        accessibilityText: String?,
        renderedLatency: Double?
    ) -> Double? {
        guard let accessibilityText,
              !accessibilityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return renderedLatency
    }
}

public enum RuntimeTranscriptQuality {
    public static func normalizedWords(_ text: String) -> [String] {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalizedScalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(normalizedScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public static func wordErrorRate(expected: String, actual: String) -> Double {
        let expectedWords = normalizedWords(expected)
        let actualWords = normalizedWords(actual)
        guard !expectedWords.isEmpty else {
            return actualWords.isEmpty ? 0 : 1
        }

        var previous = Array(0...actualWords.count)
        for (expectedIndex, expectedWord) in expectedWords.enumerated() {
            var current = [expectedIndex + 1] + Array(repeating: 0, count: actualWords.count)
            for (actualIndex, actualWord) in actualWords.enumerated() {
                let substitution = previous[actualIndex] + (expectedWord == actualWord ? 0 : 1)
                let insertion = current[actualIndex] + 1
                let deletion = previous[actualIndex + 1] + 1
                current[actualIndex + 1] = min(substitution, insertion, deletion)
            }
            previous = current
        }
        return Double(previous[actualWords.count]) / Double(expectedWords.count)
    }
}

public struct RuntimeLatencyTraceEvent: Codable, Equatable, Sendable {
    public let traceID: String
    public let sequence: Int
    public let totalMilliseconds: Double
    public let deltaMilliseconds: Double
    public let name: String
    public let details: String

    public var executorQueueDelayMilliseconds: Double? {
        guard name.hasSuffix(".executor_resumed") else { return nil }
        let prefix = "queueDelayMs="
        return details
            .split(separator: " ")
            .first { $0.hasPrefix(prefix) }
            .flatMap { Double($0.dropFirst(prefix.count)) }
    }

    public init(
        traceID: String,
        sequence: Int,
        totalMilliseconds: Double,
        deltaMilliseconds: Double,
        name: String,
        details: String
    ) {
        self.traceID = traceID
        self.sequence = sequence
        self.totalMilliseconds = totalMilliseconds
        self.deltaMilliseconds = deltaMilliseconds
        self.name = name
        self.details = details
    }
}

public struct RuntimeLatencyTrace: Codable, Equatable, Sendable {
    public let traceID: String
    public let events: [RuntimeLatencyTraceEvent]

    public var triggerObserved: Bool {
        events.contains { $0.name.hasPrefix("shortcut.key_down") }
    }

    public var shortcutKeyEvidenceRejected: Bool {
        events.contains { $0.name == "shortcut.key_evidence_rejected" }
    }

    public var pasteEventPosted: Bool {
        events.contains(where: Self.isTextDeliveryEvent)
    }

    public var textDeliveryHandoffCompleted: Bool {
        directTextInsertionSucceeded || clipboardPasteHandoffCompleted
    }

    public var directTextInsertionSucceeded: Bool {
        events.contains { $0.name == "paste_text_inserted" }
    }

    public var clipboardPasteHandoffCompleted: Bool {
        clipboardWriteSucceeded && pasteCommandPosted
    }

    public var transcriptionCompleted: Bool {
        events.contains {
            $0.name == "pipeline.transcribe.end" && $0.details.contains("result=success")
        }
    }

    public var microphonePermissionUnavailable: Bool {
        if events.contains(where: {
            $0.name == "engine.permission.denied" ||
                ($0.name == "engine.permission.callback" && $0.details.contains("granted=false"))
        }) {
            return true
        }
        guard events.contains(where: { $0.name == "engine.permission.request" }),
              events.contains(where: {
                  $0.name == "permission.authorization_status.end" &&
                      $0.details.contains("status=undetermined")
              }) else {
            return false
        }
        return !events.contains(where: { $0.name == "engine.permission.callback" })
    }

    public var transcribedCharacterCount: Int? {
        guard let event = events.last(where: {
            $0.name == "pipeline.transcribe.end" && $0.details.contains("result=success")
        }) else {
            return nil
        }
        let prefix = "rawChars="
        return event.details
            .split(separator: " ")
            .first { $0.hasPrefix(prefix) }
            .flatMap { Int($0.dropFirst(prefix.count)) }
    }

    public var observedShortcutHoldMilliseconds: Double? {
        guard let keyDown = events.first(where: { $0.name == "shortcut.key_down_physical" }),
              let keyUp = events.last(where: { $0.name == "shortcut.key_up_handler" }),
              keyUp.totalMilliseconds >= keyDown.totalMilliseconds else {
            return nil
        }
        return keyUp.totalMilliseconds - keyDown.totalMilliseconds
    }

    public var clipboardWriteSucceeded: Bool {
        events.contains {
            $0.name == "paste_session.write_clipboard.end" && $0.details.contains("result=success")
        }
    }

    public var keyUpToPasteEventMilliseconds: Double? {
        millisecondsAfterKeyUp(toFirstEventMatching: Self.isTextDeliveryEvent)
    }

    public var keyUpToPipelineCompleteMilliseconds: Double? {
        millisecondsAfterKeyUp(toFirstEventMatching: { $0.name == "pipeline.complete" })
    }

    public var keyUpToInteractionSettledMilliseconds: Double? {
        millisecondsAfterKeyUp(toLastEventMatching: { $0.name == "ui.engine_toggle.end" })
    }

    public var maximumExecutorQueueDelayMilliseconds: Double? {
        events.compactMap(\.executorQueueDelayMilliseconds).max()
    }

    public init(traceID: String, events: [RuntimeLatencyTraceEvent]) {
        self.traceID = traceID
        self.events = events.sorted { $0.sequence < $1.sequence }
    }

    // Report fields retain their historical "paste event" names. Direct AX insertion is the
    // equivalent product handoff boundary and must not be classified as a missing paste.
    private static func isTextDeliveryEvent(_ event: RuntimeLatencyTraceEvent) -> Bool {
        isPasteCommandEvent(event) || event.name == "paste_text_inserted"
    }

    private var pasteCommandPosted: Bool {
        events.contains(where: Self.isPasteCommandEvent)
    }

    private static func isPasteCommandEvent(_ event: RuntimeLatencyTraceEvent) -> Bool {
        event.name == "paste_event_posted" || event.name == "paste.event_posted"
    }

    private func millisecondsAfterKeyUp(
        toFirstEventMatching predicate: (RuntimeLatencyTraceEvent) -> Bool
    ) -> Double? {
        millisecondsAfterKeyUp(event: events.first(where: predicate))
    }

    private func millisecondsAfterKeyUp(
        toLastEventMatching predicate: (RuntimeLatencyTraceEvent) -> Bool
    ) -> Double? {
        millisecondsAfterKeyUp(event: events.last(where: predicate))
    }

    private func millisecondsAfterKeyUp(event: RuntimeLatencyTraceEvent?) -> Double? {
        guard let keyUp = events.last(where: { $0.name == "shortcut.key_up_handler" }),
              let event,
              event.totalMilliseconds >= keyUp.totalMilliseconds else {
            return nil
        }
        return event.totalMilliseconds - keyUp.totalMilliseconds
    }

    public static func parse(messages: [String]) -> Self? {
        parseAll(messages: messages).last
    }

    public static func parseAll(messages: [String]) -> [Self] {
        let pattern = #"\[LATENCY\] trace=([^ ]+) seq=([0-9]+) t=([0-9.]+)ms delta=([0-9.]+)ms event=([^ ]+)(?: (.*))?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var grouped: [String: [RuntimeLatencyTraceEvent]] = [:]
        var traceOrder: [String] = []
        for message in messages {
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = expression.firstMatch(in: message, range: range),
                  let traceID = capture(1, match: match, source: message),
                  let sequenceText = capture(2, match: match, source: message),
                  let totalText = capture(3, match: match, source: message),
                  let deltaText = capture(4, match: match, source: message),
                  let name = capture(5, match: match, source: message),
                  let sequence = Int(sequenceText),
                  let total = Double(totalText),
                  let delta = Double(deltaText) else {
                continue
            }
            if grouped[traceID] == nil {
                traceOrder.append(traceID)
            }
            grouped[traceID, default: []].append(
                RuntimeLatencyTraceEvent(
                    traceID: traceID,
                    sequence: sequence,
                    totalMilliseconds: total,
                    deltaMilliseconds: delta,
                    name: name,
                    details: capture(6, match: match, source: message) ?? ""
                )
            )
        }
        return traceOrder.compactMap { traceID in
            grouped[traceID].map { Self(traceID: traceID, events: $0) }
        }
    }

    private static func capture(
        _ index: Int,
        match: NSTextCheckingResult,
        source: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: source) else {
            return nil
        }
        return String(source[swiftRange])
    }
}
