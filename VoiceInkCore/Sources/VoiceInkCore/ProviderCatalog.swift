import Foundation

public enum VoiceInkProviderModelUse: Sendable {
    case transcription
    case postProcessing
}

public struct VoiceInkProviderModelSelectionPresentation: Equatable, Sendable {
    public let fixedModelName: String?
    public let selectableModels: [String]

    init(fixedModelName: String? = nil, selectableModels: [String] = []) {
        self.fixedModelName = fixedModelName
        self.selectableModels = selectableModels
    }

}

public enum VoiceInkTranscriptionTransport: Sendable {
    case openAICompatible
    case deepgram
    case geminiGenerateContent
    case mistral
    case elevenLabs
    case soniox
    case speechmatics
    case assemblyAI
    case xai
    case localWhisper
    case localFluidAudio
    case nativeApple
    case nvidiaRiva
}

public enum VoiceInkTranscriptionServiceKind: Equatable, Sendable {
    case remote
    case streamingOnly
    case customCloud
    case localWhisper
    case localFluidAudio
    case nativeApple
}

public enum VoiceInkTranscriptionEmptyTextPolicy: Sendable, Equatable {
    case allow
    case rejectEmpty
    case rejectWhitespace

    public func accepts(_ text: String) -> Bool {
        switch self {
        case .allow:
            return true
        case .rejectEmpty:
            return !text.isEmpty
        case .rejectWhitespace:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public enum VoiceInkAPIKeyVerificationTransport: Sendable, Equatable {
    case openAICompatibleModels
    case customAIChat
    case anthropicMessages
    case deepgramProjects
    case geminiModels
    case mistralModels
    case elevenLabsUser
    case sonioxFiles
    case speechmaticsJobs
    case assemblyAITranscripts
    case xaiAPIKey
    case cartesiaVoices
    case nvidiaRivaConfig
}

public enum VoiceInkProviderAccessRequirement: Sendable {
    case userAPIKey(account: String, verificationStateKey: String, verificationTransport: VoiceInkAPIKeyVerificationTransport)
    case localWhisperModel
    case localFluidAudioModel
    case nativeAppleSpeech
    case customCloudModel
    case localEnhancementService
    case bundledService
}

public enum VoiceInkProviderAPIKeyAccount {
    public static let groq = "groqAPIKey"
    public static let deepgram = "deepgramAPIKey"
    public static let cerebras = "cerebrasAPIKey"
    public static let gemini = "geminiAPIKey"
    public static let mistral = "mistralAPIKey"
    public static let elevenLabs = "elevenLabsAPIKey"
    public static let soniox = "sonioxAPIKey"
    public static let speechmatics = "speechmaticsAPIKey"
    public static let assemblyAI = "assemblyAIAPIKey"
    public static let xAI = "xaiAPIKey"
    public static let cartesia = "cartesiaAPIKey"
    public static let nvidia = "nvidiaAPIKey"
    public static let openAI = "openAIAPIKey"
    public static let anthropic = "anthropicAPIKey"
    public static let openRouter = "openRouterAPIKey"
    public static let customAI = "customAPIKey"

    public static func accountIdentifier(forProviderName provider: String) -> String {
        let normalizedProvider = normalized(provider)
        return knownAccountsByProviderName[normalizedProvider] ?? "\(normalizedProvider)APIKey"
    }

    public static func fallbackEnvironmentKey(forProviderName provider: String) -> String? {
        fallbackEnvironmentKeysByProviderName[normalized(provider)]
    }

    public static func customModelAccountIdentifier(forModelId modelId: UUID) -> String {
        "customModel_\(modelId.uuidString)_APIKey"
    }

    private static let knownAccountsByProviderName: [String: String] = [
        "groq": groq,
        "deepgram": deepgram,
        "cerebras": cerebras,
        "gemini": gemini,
        "mistral": mistral,
        "elevenlabs": elevenLabs,
        "soniox": soniox,
        "speechmatics": speechmatics,
        "assemblyai": assemblyAI,
        "xai": xAI,
        "cartesia": cartesia,
        "nvidia": nvidia,
        "openai": openAI,
        "anthropic": anthropic,
        "openrouter": openRouter,
        "custom": customAI
    ]

    private static let fallbackEnvironmentKeysByProviderName: [String: String] = [
        "elevenlabs": "ELEVENLABS_API_KEY",
        "nvidia": "NVIDIA_API_KEY"
    ]

    private static func normalized(_ provider: String) -> String {
        provider.lowercased()
    }
}

public enum VoiceInkProviderCredential {
    public static func nonBlank(_ key: String?) -> String? {
        guard let key,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }
}

public enum VoiceInkAPIKeyReference {
    public static func resolvedValue(
        _ value: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let variableName: String
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}") {
            variableName = String(trimmed.dropFirst(2).dropLast())
        } else if trimmed.hasPrefix("$") {
            variableName = String(trimmed.dropFirst())
        } else {
            return trimmed
        }

        guard !variableName.isEmpty,
              variableName.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
              let resolvedValue = environment[variableName],
              VoiceInkProviderCredential.nonBlank(resolvedValue) != nil else {
            return nil
        }

        return resolvedValue
    }
}

public enum VoiceInkProviderAPIKeyLookup {
    public static func usableAPIKey(
        storedKey: String?,
        provider: VoiceInkProviderKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        usableAPIKey(
            storedKey: storedKey,
            providerName: provider.displayName,
            environment: environment
        )
    }

    public static func usableAPIKey(
        storedKey: String?,
        providerName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let storedKey,
           let resolvedKey = VoiceInkAPIKeyReference.resolvedValue(storedKey, environment: environment),
           let apiKey = VoiceInkProviderCredential.nonBlank(resolvedKey) {
            return apiKey
        }

        guard let environmentKey = VoiceInkProviderAPIKeyAccount.fallbackEnvironmentKey(forProviderName: providerName),
              let value = environment[environmentKey],
              let apiKey = VoiceInkProviderCredential.nonBlank(value) else {
            return nil
        }

        return apiKey
    }
}

public enum VoiceInkSecretPresentation {
    public static let obfuscatedAPIKeyPlaceholder = "••••••••"

    public static func obfuscatedAPIKey(_ key: String) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        let count = trimmedKey.count
        if count <= 6 {
            return String(repeating: "•", count: count)
        }

        let prefixCount = min(4, count)
        let suffixCount = min(4, max(0, count - prefixCount))
        let start = trimmedKey.prefix(prefixCount)
        let end = trimmedKey.suffix(suffixCount)
        let middleCount = max(4, count - prefixCount - suffixCount)
        return "\(start)\(String(repeating: "•", count: middleCount))\(end)"
    }

    public static func obfuscatedAPIKeyOrPlaceholder(_ key: String) -> String {
        obfuscatedAPIKey(key) ?? obfuscatedAPIKeyPlaceholder
    }
}

public struct VoiceInkProviderAPIKeyDraft: Equatable, Sendable {
    private let enteredKey: String?
    private let storedRuntimeKey: String?

    public init(enteredKey: String?, storedRuntimeKey: String?) {
        self.enteredKey = enteredKey
        self.storedRuntimeKey = storedRuntimeKey
    }

    public var hasEnteredKey: Bool {
        enteredKeyForVerification != nil
    }

    public var canVerify: Bool {
        verificationCandidate != nil
    }

    public var verificationCandidate: String? {
        enteredKeyForVerification ?? VoiceInkProviderCredential.nonBlank(storedRuntimeKey)
    }

    public var keyToSaveAfterSuccessfulVerification: String? {
        enteredKeyForVerification
    }

    private var enteredKeyForVerification: String? {
        let trimmed = enteredKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct VoiceInkProviderAPIKeyVerificationApplicationPlan: Equatable, Sendable {
    public let progress: VoiceInkProviderAPIKeyVerificationProgress
    public let keyToSave: String?
    public let shouldMarkKeyVerified: Bool

    public init(
        progress: VoiceInkProviderAPIKeyVerificationProgress,
        keyToSave: String?,
        shouldMarkKeyVerified: Bool
    ) {
        self.progress = progress
        self.keyToSave = keyToSave
        self.shouldMarkKeyVerified = shouldMarkKeyVerified
    }

    public static let unsupportedProvider = VoiceInkProviderAPIKeyVerificationApplicationPlan(
        progress: .unsupportedProviderFailure,
        keyToSave: nil,
        shouldMarkKeyVerified: false
    )
}

public struct VoiceInkProviderAPIKeyVerificationPersistencePlan: Equatable, Sendable {
    public let keyToSave: String?
    public let verificationFlagToPersist: Bool

    public init(
        keyToSave: String?,
        verificationFlagToPersist: Bool
    ) {
        self.keyToSave = keyToSave
        self.verificationFlagToPersist = verificationFlagToPersist
    }
}

fileprivate enum VoiceInkProviderAPIKeyVerificationPersistenceAction: Equatable, Sendable {
    case saveKey(String)
    case persistVerificationFlag(Bool)
}

public struct VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan: Equatable, Sendable {
    fileprivate let actions: [VoiceInkProviderAPIKeyVerificationPersistenceAction]

    fileprivate init(actions: [VoiceInkProviderAPIKeyVerificationPersistenceAction]) {
        self.actions = actions
    }
}

public extension VoiceInkProviderAPIKeyVerificationPersistencePlan {
    var applicationPlan: VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan {
        var actions: [VoiceInkProviderAPIKeyVerificationPersistenceAction] = []
        if let keyToSave {
            actions.append(.saveKey(keyToSave))
        }
        actions.append(.persistVerificationFlag(verificationFlagToPersist))
        return VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan(actions: actions)
    }
}

extension VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan {
    func applyRuntimeState(
        saveKey: (String) -> Void,
        persistVerificationFlag: (Bool) -> Void
    ) {
        for action in actions {
            switch action {
            case .saveKey(let key):
                saveKey(key)
            case .persistVerificationFlag(let flag):
                persistVerificationFlag(flag)
            }
        }
    }
}

public extension VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan {
    func applySuccessPersistence(
        saveKey: (String) -> Void
    ) -> Bool {
        var verificationFlagToPersist = false
        applyRuntimeState(
            saveKey: saveKey,
            persistVerificationFlag: { verificationFlagToPersist = $0 }
        )

        return verificationFlagToPersist
    }
}

public extension VoiceInkProviderAPIKeyVerificationApplicationPlan {
    var successPersistencePlan: VoiceInkProviderAPIKeyVerificationPersistencePlan? {
        guard shouldMarkKeyVerified else { return nil }
        return VoiceInkProviderAPIKeyVerificationPersistencePlan(
            keyToSave: keyToSave,
            verificationFlagToPersist: true
        )
    }

    var successPersistenceApplicationPlan: VoiceInkProviderAPIKeyVerificationPersistenceApplicationPlan? {
        successPersistencePlan?.applicationPlan
    }

    func applySuccessPersistence(
        saveKey: (String) -> Void
    ) -> Bool {
        guard let successPersistenceApplicationPlan else { return false }
        return successPersistenceApplicationPlan.applySuccessPersistence(saveKey: saveKey)
    }
}

enum VoiceInkProviderAPIKeyVerificationControl: Equatable, Sendable {
    case progress
    case verifyButton(isDisabled: Bool)

    var isProgressVisible: Bool {
        switch self {
        case .progress:
            return true
        case .verifyButton:
            return false
        }
    }

    var isVerifyButtonDisabled: Bool {
        switch self {
        case .progress:
            return true
        case .verifyButton(let isDisabled):
            return isDisabled
        }
    }

    func runtimeAction(
        verify: @escaping () -> Void
    ) -> (() -> Void)? {
        switch self {
        case .progress:
            return nil
        case .verifyButton(let isDisabled):
            return isDisabled ? nil : verify
        }
    }
}

public struct VoiceInkProviderAPIKeyFormControlPresentation: Equatable, Sendable {
    public let isSaveButtonDisabled: Bool
    let verificationControl: VoiceInkProviderAPIKeyVerificationControl

    init(
        isSaveButtonDisabled: Bool,
        verificationControl: VoiceInkProviderAPIKeyVerificationControl
    ) {
        self.isSaveButtonDisabled = isSaveButtonDisabled
        self.verificationControl = verificationControl
    }

    public var isVerificationProgressVisible: Bool {
        verificationControl.isProgressVisible
    }

    public var isVerifyButtonDisabled: Bool {
        verificationControl.isVerifyButtonDisabled
    }

    public func verifyRuntimeAction(
        verify: @escaping () -> Void
    ) -> (() -> Void)? {
        verificationControl.runtimeAction(verify: verify)
    }

    public func saveRuntimeAction(
        save: @escaping () -> Void
    ) -> (() -> Void)? {
        isSaveButtonDisabled ? nil : save
    }
}

public struct VoiceInkProviderAPIKeyCardControlPresentation: Equatable, Sendable {
    public let isAPIKeyFieldDisabled: Bool
    public let isVerifyProgressVisible: Bool
    public let isVerifyButtonDisabled: Bool
    public let verifyButtonTitle: String
    public let verifyButtonSystemImageName: String
    public let isVerifyButtonSuccess: Bool
    public let inlineFeedback: VoiceInkProviderAPIKeyVerificationFeedback?

    public init(
        isAPIKeyFieldDisabled: Bool,
        isVerifyProgressVisible: Bool,
        isVerifyButtonDisabled: Bool,
        verifyButtonTitle: String,
        verifyButtonSystemImageName: String,
        isVerifyButtonSuccess: Bool,
        inlineFeedback: VoiceInkProviderAPIKeyVerificationFeedback?
    ) {
        self.isAPIKeyFieldDisabled = isAPIKeyFieldDisabled
        self.isVerifyProgressVisible = isVerifyProgressVisible
        self.isVerifyButtonDisabled = isVerifyButtonDisabled
        self.verifyButtonTitle = verifyButtonTitle
        self.verifyButtonSystemImageName = verifyButtonSystemImageName
        self.isVerifyButtonSuccess = isVerifyButtonSuccess
        self.inlineFeedback = inlineFeedback
    }
}

public struct VoiceInkProviderAPIKeyStoredKeyPresentation: Equatable, Sendable {
    public let feedback: VoiceInkProviderAPIKeyVerificationFeedback
    public let obfuscatedKey: String?

    public init(
        feedback: VoiceInkProviderAPIKeyVerificationFeedback,
        obfuscatedKey: String?
    ) {
        self.feedback = feedback
        self.obfuscatedKey = obfuscatedKey
    }
}

public struct VoiceInkProviderAPIKeyEditPlan: Equatable, Sendable {
    public let formState: VoiceInkProviderAPIKeyFormState
    public let verificationFlagToPersist: Bool?

    public init(
        formState: VoiceInkProviderAPIKeyFormState,
        verificationFlagToPersist: Bool?
    ) {
        self.formState = formState
        self.verificationFlagToPersist = verificationFlagToPersist
    }
}

public extension VoiceInkProviderAPIKeyDraft {
    func verificationApplicationPlan(
        for result: VoiceInkAPIKeyVerificationResult
    ) -> VoiceInkProviderAPIKeyVerificationApplicationPlan {
        guard result.isValid else {
            return VoiceInkProviderAPIKeyVerificationApplicationPlan(
                progress: .failure(message: result.errorMessage),
                keyToSave: nil,
                shouldMarkKeyVerified: false
            )
        }

        return VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .success,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            shouldMarkKeyVerified: true
        )
    }

    static func missingVerificationCandidatePlan(
        message: String? = nil
    ) -> VoiceInkProviderAPIKeyVerificationApplicationPlan {
        VoiceInkProviderAPIKeyVerificationApplicationPlan(
            progress: .failure(message: message),
            keyToSave: nil,
            shouldMarkKeyVerified: false
        )
    }
}

public struct VoiceInkProviderAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress
    public var isEditing: Bool

    public init(
        enteredKey: String = "",
        verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle,
        isEditing: Bool = true
    ) {
        self.enteredKey = enteredKey
        self.verificationProgress = verificationProgress
        self.isEditing = isEditing
    }

    public static func loaded(storedKey: String, isVerified: Bool) -> Self {
        Self(
            enteredKey: storedKey,
            verificationProgress: .idle,
            isEditing: !isVerified
        )
    }

    public func draft(storedRuntimeKey: String?) -> VoiceInkProviderAPIKeyDraft {
        VoiceInkProviderAPIKeyDraft(
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public func editingStoredKey(_ storedKey: String) -> Self {
        Self(
            enteredKey: storedKey,
            verificationProgress: .idle,
            isEditing: true
        )
    }

    public func iOSStoredKeyEditPlan(storedKey: String) -> VoiceInkProviderAPIKeyEditPlan {
        VoiceInkProviderAPIKeyEditPlan(
            formState: editingStoredKey(storedKey),
            verificationFlagToPersist: false
        )
    }

    public func keyEdited() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .idle,
            isEditing: isEditing
        )
    }

    public func verifying() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .verifying,
            isEditing: isEditing
        )
    }

    public func applyingVerificationPlan(_ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan) -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: plan.progress,
            isEditing: plan.shouldMarkKeyVerified ? false : isEditing
        )
    }

    public func verificationStartPlan(
        storedRuntimeKey: String?,
        missingCandidatePolicy: VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy
    ) -> VoiceInkProviderAPIKeyVerificationStartPlan {
        let draft = self.draft(storedRuntimeKey: storedRuntimeKey)
        guard let candidate = draft.verificationCandidate else {
            switch missingCandidatePolicy {
            case .keepCurrentState:
                return VoiceInkProviderAPIKeyVerificationStartPlan(
                    formState: self,
                    draft: draft,
                    candidate: nil
                )
            case .applyFailurePlan:
                return VoiceInkProviderAPIKeyVerificationStartPlan(
                    formState: verifying().applyingVerificationPlan(
                        VoiceInkProviderAPIKeyDraft.missingVerificationCandidatePlan()
                    ),
                    draft: draft,
                    candidate: nil
                )
            }
        }

        return VoiceInkProviderAPIKeyVerificationStartPlan(
            formState: verifying(),
            draft: draft,
            candidate: candidate
        )
    }

    public func verificationCompletionPlan(
        startPlan: VoiceInkProviderAPIKeyVerificationStartPlan,
        result: VoiceInkAPIKeyVerificationResult
    ) -> VoiceInkProviderAPIKeyVerificationCompletionPlan {
        verificationCompletionPlan(
            applicationPlan: startPlan.draft.verificationApplicationPlan(for: result)
        )
    }

    public func verificationCompletionPlan(
        applicationPlan: VoiceInkProviderAPIKeyVerificationApplicationPlan
    ) -> VoiceInkProviderAPIKeyVerificationCompletionPlan {
        VoiceInkProviderAPIKeyVerificationCompletionPlan(
            formState: applyingVerificationPlan(applicationPlan),
            applicationPlan: applicationPlan
        )
    }

    public func iOSVisibleResultFeedback(isProviderReady: Bool) -> VoiceInkProviderAPIKeyVerificationFeedback? {
        guard !isProviderReady else {
            return nil
        }

        return verificationProgress.iOSResultFeedback
    }

    public func iOSStoredKeyPresentation(storedKey: String) -> VoiceInkProviderAPIKeyStoredKeyPresentation? {
        guard !isEditing else {
            return nil
        }

        return VoiceInkProviderAPIKeyStoredKeyPresentation(
            feedback: VoiceInkProviderAPIKeyVerificationProgress.iOSVerifiedKeyFeedback,
            obfuscatedKey: VoiceInkSecretPresentation.obfuscatedAPIKey(storedKey)
        )
    }

    public func iOSControlPresentation(storedRuntimeKey: String?) -> VoiceInkProviderAPIKeyFormControlPresentation {
        let draft = draft(storedRuntimeKey: storedRuntimeKey)
        return VoiceInkProviderAPIKeyFormControlPresentation(
            isSaveButtonDisabled: !draft.hasEnteredKey,
            verificationControl: verificationProgress.isVerifying
                ? .progress
                : .verifyButton(isDisabled: !draft.canVerify)
        )
    }

    public func macOSCardControlPresentation(storedRuntimeKey: String?) -> VoiceInkProviderAPIKeyCardControlPresentation {
        let draft = draft(storedRuntimeKey: storedRuntimeKey)
        return VoiceInkProviderAPIKeyCardControlPresentation(
            isAPIKeyFieldDisabled: verificationProgress.isVerifying,
            isVerifyProgressVisible: verificationProgress.isVerifying,
            isVerifyButtonDisabled: !draft.canVerify || verificationProgress.isVerifying,
            verifyButtonTitle: verificationProgress.macOSVerifyButtonTitle,
            verifyButtonSystemImageName: verificationProgress.macOSVerifyButtonSystemImageName,
            isVerifyButtonSuccess: verificationProgress.isSuccess,
            inlineFeedback: verificationProgress.macOSInlineFeedback
        )
    }
}

public enum VoiceInkProviderAPIKeyMissingVerificationCandidatePolicy: Equatable, Sendable {
    case keepCurrentState
    case applyFailurePlan
}

public struct VoiceInkProviderAPIKeyVerificationStartPlan: Equatable, Sendable {
    private let formState: VoiceInkProviderAPIKeyFormState
    fileprivate let draft: VoiceInkProviderAPIKeyDraft
    private let candidate: String?

    init(
        formState: VoiceInkProviderAPIKeyFormState,
        draft: VoiceInkProviderAPIKeyDraft,
        candidate: String?
    ) {
        self.formState = formState
        self.draft = draft
        self.candidate = candidate
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (VoiceInkProviderAPIKeyFormState) -> Void,
        verifyCandidate: (String) -> Result
    ) -> Result? {
        setFormState(formState)
        guard let candidate else {
            return nil
        }

        return verifyCandidate(candidate)
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (VoiceInkProviderAPIKeyFormState) -> Void,
        verifyCandidate: (String) async -> Result
    ) async -> Result? {
        setFormState(formState)
        guard let candidate else {
            return nil
        }

        return await verifyCandidate(candidate)
    }
}

public struct VoiceInkProviderAPIKeyVerificationCompletionPlan: Equatable, Sendable {
    public let formState: VoiceInkProviderAPIKeyFormState
    public let applicationPlan: VoiceInkProviderAPIKeyVerificationApplicationPlan

    public init(
        formState: VoiceInkProviderAPIKeyFormState,
        applicationPlan: VoiceInkProviderAPIKeyVerificationApplicationPlan
    ) {
        self.formState = formState
        self.applicationPlan = applicationPlan
    }

    @discardableResult
    public func applyRuntimeState<Result>(
        setFormState: (VoiceInkProviderAPIKeyFormState) -> Void,
        applyVerificationPlan: (VoiceInkProviderAPIKeyVerificationApplicationPlan) -> Result
    ) -> Result {
        setFormState(formState)
        return applyVerificationPlan(applicationPlan)
    }
}

public struct VoiceInkProviderAPIKeyFormPresentation: Equatable, Sendable {
    public let navigationTitle: String
    public let apiKeySectionTitle: String
    public let apiKeyPlaceholder: String
    public let saveButtonTitle: String
    public let saveButtonSystemImageName: String
    public let verifyButtonTitle: String
    public let verifyButtonSystemImageName: String
    public let changeButtonTitle: String
    public let consoleSectionTitle: String
    public let consoleLinkTitle: String
    public let consoleLeadingSystemImageName: String
    public let consoleTrailingSystemImageName: String

    public static func make(for provider: VoiceInkProviderKind) -> Self {
        let displayName = provider.displayName
        return VoiceInkProviderAPIKeyFormPresentation(
            navigationTitle: displayName,
            apiKeySectionTitle: "\(displayName) API Key",
            apiKeyPlaceholder: "\(displayName) API Key",
            saveButtonTitle: "Save",
            saveButtonSystemImageName: "checkmark.circle.fill",
            verifyButtonTitle: "Verify",
            verifyButtonSystemImageName: "checkmark.seal",
            changeButtonTitle: "Change",
            consoleSectionTitle: "Get API Key",
            consoleLinkTitle: "\(displayName) API Console",
            consoleLeadingSystemImageName: "link",
            consoleTrailingSystemImageName: "arrow.up.right.square"
        )
    }
}

public struct VoiceInkProviderAPIKeyCardPresentation: Equatable, Sendable {
    public let configureButtonTitle: String
    public let configureButtonSystemImageName: String
    public let removeAPIKeyButtonTitle: String
    public let removeAPIKeyButtonSystemImageName: String
    public let configurationSectionTitle: String
    public let apiKeyFieldPlaceholder: String

    public init(providerDisplayName: String) {
        self.configureButtonTitle = "Configure"
        self.configureButtonSystemImageName = "gear"
        self.removeAPIKeyButtonTitle = "Remove API Key"
        self.removeAPIKeyButtonSystemImageName = "trash"
        self.configurationSectionTitle = "API Key Configuration"
        self.apiKeyFieldPlaceholder = "Enter your \(providerDisplayName) API key"
    }
}

public enum VoiceInkProviderAPIKeyVerificationTone: Equatable, Sendable {
    case success
    case failure
}

public struct VoiceInkProviderAPIKeyVerificationFeedback: Equatable, Sendable {
    public let text: String
    public let systemImageName: String?
    public let tone: VoiceInkProviderAPIKeyVerificationTone

    public init(
        text: String,
        systemImageName: String? = nil,
        tone: VoiceInkProviderAPIKeyVerificationTone
    ) {
        self.text = text
        self.systemImageName = systemImageName
        self.tone = tone
    }

    public var effectiveSystemImageName: String {
        systemImageName ?? "info.circle"
    }
}

public enum VoiceInkProviderAPIKeyVerificationProgress: Equatable, Sendable {
    case idle
    case verifying
    case success
    case failure(message: String?)

    public static let unsupportedProviderFailureMessage = "Unsupported provider"
    public static let unsupportedProviderFailure: VoiceInkProviderAPIKeyVerificationProgress = .failure(
        message: unsupportedProviderFailureMessage
    )

    public var isVerifying: Bool {
        self == .verifying
    }

    public var isSuccess: Bool {
        self == .success
    }

    public var macOSVerifyButtonTitle: String {
        isVerifying ? "Verifying..." : "Verify"
    }

    public var macOSVerifyButtonSystemImageName: String {
        isSuccess ? "checkmark" : "checkmark.shield"
    }

    public var macOSInlineFeedback: VoiceInkProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: "API key verified successfully!",
                tone: .success
            )
        case .failure(let message):
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: message ?? "Verification failed",
                tone: .failure
            )
        }
    }

    public var iOSResultFeedback: VoiceInkProviderAPIKeyVerificationFeedback? {
        switch self {
        case .idle, .verifying:
            return nil
        case .success:
            return Self.iOSVerifiedKeyFeedback
        case .failure:
            return VoiceInkProviderAPIKeyVerificationFeedback(
                text: "Verification failed",
                systemImageName: "xmark.seal",
                tone: .failure
            )
        }
    }

    public static let iOSVerifiedKeyFeedback = VoiceInkProviderAPIKeyVerificationFeedback(
        text: "Key verified",
        systemImageName: "checkmark.seal.fill",
        tone: .success
    )
}

public enum VoiceInkProviderEndpoint: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://api.groq.com/openai")!
        case .openAI:
            return URL(string: "https://api.openai.com")!
        case .deepgram:
            return URL(string: "https://api.deepgram.com")!
        case .cerebras:
            return URL(string: "https://api.cerebras.ai")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        }
    }

    public static var geminiNativeAPIBaseURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    public static var mistralAPIBaseURL: URL {
        URL(string: "https://api.mistral.ai")!
    }

    public static var elevenLabsAPIBaseURL: URL {
        URL(string: "https://api.elevenlabs.io")!
    }

    public static var xaiAPIBaseURL: URL {
        URL(string: "https://api.x.ai")!
    }

    public static var sonioxAPIBaseURL: URL {
        URL(string: "https://api.soniox.com/v1")!
    }

    public static var speechmaticsAPIBaseURL: URL {
        URL(string: "https://asr.api.speechmatics.com/v2")!
    }

    public static var assemblyAIAPIBaseURL: URL {
        URL(string: "https://api.assemblyai.com")!
    }

    public static var cartesiaAPIBaseURL: URL {
        URL(string: "https://api.cartesia.ai")!
    }

    public static var anthropicAPIBaseURL: URL {
        URL(string: "https://api.anthropic.com")!
    }

    public static var openRouterAPIBaseURL: URL {
        URL(string: "https://openrouter.ai/api")!
    }

    public var chatCompletionsURL: URL? {
        switch self {
        case .groq, .openAI, .cerebras, .gemini:
            return Self.openAICompatibleChatCompletionsURL(from: apiBaseURL)
        case .deepgram:
            return nil
        }
    }

    public var deepgramListenURL: URL? {
        switch self {
        case .deepgram:
            return Self.deepgramListenURL(from: apiBaseURL)
        case .groq, .openAI, .cerebras, .gemini:
            return nil
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")!
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .deepgram:
            return URL(string: "https://console.deepgram.com/api-keys")!
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/")!
        case .gemini:
            return URL(string: "https://makersuite.google.com/app/apikey")!
        }
    }

    public static func openAICompatibleModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func openAICompatibleChatCompletionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/chat/completions")
    }

    public static func openAICompatibleAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func deepgramListenURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/listen")
    }

    public static func deepgramProjectsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/projects")
    }

    public static func geminiGenerateContentURL(from baseURL: URL, model: String) -> URL {
        baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(model):generateContent")
    }

    public static func geminiModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("models")
    }

    public static func mistralAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func mistralModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func elevenLabsSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/speech-to-text")
    }

    public static func elevenLabsUserURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/user")
    }

    public static func xaiSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/stt")
    }

    public static func xaiAPIKeyURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/api-key")
    }

    public static func sonioxFilesURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("files")
    }

    public static func sonioxTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("transcriptions")
    }

    public static func sonioxTranscriptionURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func sonioxTranscriptURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionURL(from: baseURL, id: id).appendingPathComponent("transcript")
    }

    public static func speechmaticsJobsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("jobs")
    }

    public static func speechmaticsJobURL(from baseURL: URL, id: String) -> URL {
        speechmaticsJobsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func speechmaticsTranscriptURL(from baseURL: URL, id: String) -> URL {
        let url = speechmaticsJobURL(from: baseURL, id: id).appendingPathComponent("transcript")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "txt")]
        return components.url!
    }

    public static func assemblyAIUploadURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v2/upload")
    }

    public static func assemblyAITranscriptsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v2/transcript")
    }

    public static func assemblyAITranscriptURL(from baseURL: URL, id: String) -> URL {
        assemblyAITranscriptsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func cartesiaVoicesURL(from baseURL: URL) -> URL {
        let url = baseURL.appendingPathComponent("voices")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "1")]
        return components.url!
    }
}

public enum VoiceInkProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini
    case mistral
    case elevenLabs
    case soniox
    case speechmatics
    case assemblyAI
    case xai
    case cartesia
    case nvidia
    case anthropic
    case openRouter
    case customAI
    case ollama
    case customCloud
    case localWhisper
    case localFluidAudio
    case nativeApple
    case voiceInk

    public var id: String { rawValue }

    public var apiKeyFormPresentation: VoiceInkProviderAPIKeyFormPresentation {
        VoiceInkProviderAPIKeyFormPresentation.make(for: self)
    }

    public var displayName: String {
        persistedValue
    }

    private var persistedValue: String {
        switch self {
        case .groq:
            return "Groq"
        case .openAI:
            return "OpenAI"
        case .deepgram:
            return "Deepgram"
        case .cerebras:
            return "Cerebras"
        case .gemini:
            return "Gemini"
        case .mistral:
            return "Mistral"
        case .elevenLabs:
            return "ElevenLabs"
        case .soniox:
            return "Soniox"
        case .speechmatics:
            return "Speechmatics"
        case .assemblyAI:
            return "AssemblyAI"
        case .xai:
            return "xAI"
        case .cartesia:
            return "Cartesia"
        case .nvidia:
            return "NVIDIA"
        case .anthropic:
            return "Anthropic"
        case .openRouter:
            return "OpenRouter"
        case .customAI:
            return "Custom"
        case .ollama:
            return "Ollama"
        case .customCloud:
            return "Custom Cloud"
        case .localWhisper:
            return "Local (Whisper)"
        case .localFluidAudio:
            return "Local (Parakeet)"
        case .nativeApple:
            return "Native Apple"
        case .voiceInk:
            return "VoiceInk"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let provider = Self.provider(forPersistedValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid provider: \(value)"
            )
        }
        self = provider
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(persistedValue)
    }

    private static func provider(forPersistedValue value: String) -> VoiceInkProviderKind? {
        allCases.first { provider in
            provider.persistedValue == value || provider.rawValue == value
        }
    }

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.apiBaseURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.apiBaseURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.apiBaseURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.apiBaseURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.apiBaseURL
        case .mistral:
            return VoiceInkProviderEndpoint.mistralAPIBaseURL
        case .elevenLabs:
            return VoiceInkProviderEndpoint.elevenLabsAPIBaseURL
        case .soniox:
            return VoiceInkProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return VoiceInkProviderEndpoint.speechmaticsAPIBaseURL
        case .assemblyAI:
            return VoiceInkProviderEndpoint.assemblyAIAPIBaseURL
        case .xai:
            return VoiceInkProviderEndpoint.xaiAPIBaseURL
        case .cartesia:
            return VoiceInkProviderEndpoint.cartesiaAPIBaseURL
        case .nvidia:
            return URL(string: "https://grpc.nvcf.nvidia.com")!
        case .anthropic:
            return VoiceInkProviderEndpoint.anthropicAPIBaseURL
        case .openRouter:
            return VoiceInkProviderEndpoint.openRouterAPIBaseURL
        case .customAI:
            return URL(
                string: VoiceInkDynamicAIProviderPreference.customProviderBaseURL()
            ) ?? URL(string: "http://localhost")!
        case .ollama:
            return URL(
                string: VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
            ) ?? URL(string: VoiceInkDynamicAIProviderPreference.defaultOllamaBaseURL)!
        case .customCloud:
            return URL(string: "http://localhost")!
        case .localWhisper:
            return URL(string: "http://localhost")!
        case .localFluidAudio:
            return URL(string: "https://github.com/FluidInference/FluidAudio")!
        case .nativeApple:
            return URL(string: "https://developer.apple.com/documentation/speech")!
        case .voiceInk:
            return VoiceInkProviderEndpoint.groq.apiBaseURL
        }
    }

    public var transcriptionAPIBaseURL: URL {
        switch self {
        case .gemini:
            return VoiceInkProviderEndpoint.geminiNativeAPIBaseURL
        case .groq, .openAI, .deepgram, .cerebras, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .nvidia, .anthropic, .openRouter, .customAI, .ollama, .customCloud, .localWhisper, .localFluidAudio, .nativeApple, .voiceInk:
            return apiBaseURL
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.consoleURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.consoleURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.consoleURL
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")!
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")!
        case .soniox:
            return URL(string: "https://console.soniox.com/")!
        case .speechmatics:
            return URL(string: "https://portal.speechmatics.com/manage-access/")!
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/dashboard/api-keys")!
        case .xai:
            return URL(string: "https://console.x.ai/")!
        case .cartesia:
            return URL(string: "https://play.cartesia.ai/keys")!
        case .nvidia:
            return URL(string: "https://build.nvidia.com/nvidia/parakeet-ctc-0_6b-zh-tw/api")!
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openRouter:
            return URL(string: "https://openrouter.ai/settings/keys")!
        case .customAI:
            return URL(string: "https://voiceink.app")!
        case .ollama:
            return URL(string: "https://ollama.com")!
        case .customCloud:
            return URL(string: "https://voiceink.app")!
        case .localWhisper:
            return URL(string: "https://github.com/ggerganov/whisper.cpp")!
        case .localFluidAudio:
            return URL(string: "https://github.com/FluidInference/FluidAudio")!
        case .nativeApple:
            return URL(string: "https://developer.apple.com/documentation/speech")!
        case .voiceInk:
            return URL(string: "https://voiceink.app")!
        }
    }

    public var transcriptionTransport: VoiceInkTranscriptionTransport {
        switch self {
        case .deepgram:
            return .deepgram
        case .gemini:
            return .geminiGenerateContent
        case .mistral:
            return .mistral
        case .elevenLabs:
            return .elevenLabs
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .assemblyAI:
            return .assemblyAI
        case .xai:
            return .xai
        case .nvidia:
            return .nvidiaRiva
        case .cartesia, .customCloud, .anthropic, .openRouter, .customAI, .ollama:
            return .openAICompatible
        case .localWhisper:
            return .localWhisper
        case .localFluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        case .groq, .openAI, .cerebras, .voiceInk:
            return .openAICompatible
        }
    }

    public var transcriptionServiceKind: VoiceInkTranscriptionServiceKind {
        if self == .cartesia {
            return .streamingOnly
        }
        if self == .customCloud {
            return .customCloud
        }

        switch transcriptionTransport {
        case .openAICompatible, .deepgram, .geminiGenerateContent, .mistral, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .nvidiaRiva:
            return .remote
        case .localWhisper:
            return .localWhisper
        case .localFluidAudio:
            return .localFluidAudio
        case .nativeApple:
            return .nativeApple
        }
    }

    public var transcriptionEmptyTextPolicy: VoiceInkTranscriptionEmptyTextPolicy {
        switch self {
        case .groq, .deepgram, .gemini:
            return .rejectEmpty
        case .soniox, .speechmatics, .assemblyAI, .nvidia, .localFluidAudio, .nativeApple:
            return .rejectWhitespace
        case .openAI, .cerebras, .mistral, .elevenLabs, .xai, .cartesia, .anthropic, .openRouter, .customAI, .ollama, .customCloud, .localWhisper, .voiceInk:
            return .allow
        }
    }

    public var accessRequirement: VoiceInkProviderAccessRequirement {
        switch self {
        case .groq:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.groq,
                verificationStateKey: "groqKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .openAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.openAI,
                verificationStateKey: "openAIKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .deepgram:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.deepgram,
                verificationStateKey: "deepgramKeyVerified",
                verificationTransport: .deepgramProjects
            )
        case .cerebras:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.cerebras,
                verificationStateKey: "cerebrasKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .gemini:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.gemini,
                verificationStateKey: "geminiKeyVerified",
                verificationTransport: .geminiModels
            )
        case .mistral:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.mistral,
                verificationStateKey: "mistralKeyVerified",
                verificationTransport: .mistralModels
            )
        case .elevenLabs:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.elevenLabs,
                verificationStateKey: "elevenLabsKeyVerified",
                verificationTransport: .elevenLabsUser
            )
        case .soniox:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.soniox,
                verificationStateKey: "sonioxKeyVerified",
                verificationTransport: .sonioxFiles
            )
        case .speechmatics:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.speechmatics,
                verificationStateKey: "speechmaticsKeyVerified",
                verificationTransport: .speechmaticsJobs
            )
        case .assemblyAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.assemblyAI,
                verificationStateKey: "assemblyAIKeyVerified",
                verificationTransport: .assemblyAITranscripts
            )
        case .xai:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.xAI,
                verificationStateKey: "xaiKeyVerified",
                verificationTransport: .xaiAPIKey
            )
        case .nvidia:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.nvidia,
                verificationStateKey: "nvidiaKeyVerified",
                verificationTransport: .nvidiaRivaConfig
            )
        case .cartesia:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.cartesia,
                verificationStateKey: "cartesiaKeyVerified",
                verificationTransport: .cartesiaVoices
            )
        case .anthropic:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.anthropic,
                verificationStateKey: "anthropicKeyVerified",
                verificationTransport: .anthropicMessages
            )
        case .openRouter:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.openRouter,
                verificationStateKey: "openRouterKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .customAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.customAI,
                verificationStateKey: "customAIKeyVerified",
                verificationTransport: .customAIChat
            )
        case .ollama:
            return .localEnhancementService
        case .customCloud:
            return .customCloudModel
        case .localWhisper:
            return .localWhisperModel
        case .localFluidAudio:
            return .localFluidAudioModel
        case .nativeApple:
            return .nativeAppleSpeech
        case .voiceInk:
            return .bundledService
        }
    }

    public var apiKeyAccount: String? {
        guard case let .userAPIKey(account, _, _) = accessRequirement else {
            return nil
        }
        return account
    }

    public var apiKeyVerificationStateKey: String? {
        guard case let .userAPIKey(_, verificationStateKey, _) = accessRequirement else {
            return nil
        }
        return verificationStateKey
    }

    public var requiresUserAPIKey: Bool {
        guard case .userAPIKey = accessRequirement else {
            return false
        }
        return true
    }

    public func runtimeAPIKey(userAPIKey: String) -> String {
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKey
        case .localWhisperModel:
            return "local"
        case .localFluidAudioModel:
            return "local-fluidaudio"
        case .nativeAppleSpeech:
            return "native-apple"
        case .customCloudModel:
            return "custom-cloud"
        case .localEnhancementService:
            return "local-ollama"
        case .bundledService:
            return ""
        }
    }

    public func runtimeAPIKeyIfAvailable(userAPIKey: String) -> String? {
        VoiceInkProviderCredential.nonBlank(runtimeAPIKey(userAPIKey: userAPIKey))
    }

    public var isSupportedOnCurrentOS: Bool {
        guard self == .nvidia else { return true }
        if #available(macOS 15, iOS 18, *) { return true }
        return false
    }

    public func isReady(
        userAPIKey: String,
        userAPIKeyVerified: Bool,
        localWhisperModelAvailable: Bool,
        localFluidAudioModelAvailable: Bool = false,
        nativeAppleSpeechAvailable: Bool = false,
        customCloudModelAvailable: Bool = false,
        localEnhancementServiceAvailable: Bool = false
    ) -> Bool {
        guard isSupportedOnCurrentOS else { return false }
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKeyVerified && VoiceInkProviderCredential.nonBlank(userAPIKey) != nil
        case .localWhisperModel:
            return localWhisperModelAvailable
        case .localFluidAudioModel:
            return localFluidAudioModelAvailable
        case .nativeAppleSpeech:
            return nativeAppleSpeechAvailable
        case .customCloudModel:
            return customCloudModelAvailable
        case .localEnhancementService:
            return localEnhancementServiceAvailable
        case .bundledService:
            return false
        }
    }

    public static var userAPIKeyProviders: [VoiceInkProviderKind] {
        allCases.filter(\.requiresUserAPIKey)
    }

    public static func availableProviders(
        for use: VoiceInkProviderModelUse,
        isProviderReady: (VoiceInkProviderKind) -> Bool
    ) -> [VoiceInkProviderKind] {
        allCases.filter { provider in
            provider.isSelectable(for: use) && isProviderReady(provider)
        }
    }

    public var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        guard case let .userAPIKey(_, _, verificationTransport) = accessRequirement else {
            return nil
        }
        return verificationTransport
    }

    public var canVerifyAPIKey: Bool {
        apiKeyVerificationTransport != nil
    }

    public var transcriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .deepgram:
            return .deepgram
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .elevenLabs:
            return .elevenLabs
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .assemblyAI:
            return .assemblyAI
        case .xai:
            return .xai
        case .cartesia:
            return .cartesia
        case .nvidia:
            return .nvidia
        case .anthropic, .openRouter, .customAI, .ollama, .customCloud:
            return nil
        case .localWhisper:
            return .local
        case .localFluidAudio:
            return nil
        case .nativeApple:
            return .nativeApple
        case .voiceInk:
            return nil
        case .cerebras:
            return nil
        }
    }

    public var aiModelProvider: VoiceInkAIModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .cerebras:
            return .cerebras
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .anthropic:
            return .anthropic
        case .openRouter:
            return .openRouter
        case .customAI:
            return nil
        case .ollama:
            return nil
        case .deepgram, .elevenLabs, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .nvidia, .customCloud, .localWhisper, .localFluidAudio, .nativeApple, .voiceInk:
            return nil
        }
    }

    public var postProcessingChatCompletionsURL: URL? {
        guard supportsModelUse(.postProcessing) else {
            return nil
        }
        if self == .anthropic {
            return aiModelProvider?.postProcessingRequestURL
        }
        if self == .customAI {
            return URL(string: VoiceInkDynamicAIProviderPreference.customProviderBaseURL())
        }
        return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: apiBaseURL)
    }

    public var postProcessingDefaultModel: String? {
        if self == .ollama {
            return VoiceInkProviderCredential.nonBlank(
                VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
            )
        }
        if self == .customAI {
            return VoiceInkProviderCredential.nonBlank(
                VoiceInkDynamicAIProviderPreference.customProviderModel()
            )
        }
        if let fixedModel = fixedModel(for: .postProcessing) {
            return fixedModel
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return VoiceInkAIModelCatalog.defaultModel(for: provider)
    }

    public var postProcessingModels: [String]? {
        if self == .ollama {
            return postProcessingDefaultModel.map { [$0] } ?? []
        }
        if self == .customAI {
            return postProcessingDefaultModel.map { [$0] } ?? []
        }
        if self == .openRouter {
            let cachedModels = VoiceInkDynamicAIProviderPreference.openRouterModels()
            return cachedModels.isEmpty
                ? [VoiceInkAIModelCatalog.defaultModel(for: .openRouter)]
                : cachedModels
        }
        if let fixedModel = fixedModel(for: .postProcessing) {
            return [fixedModel]
        }

        guard let provider = aiModelProvider else {
            return nil
        }
        return VoiceInkAIModelCatalog.availableModels(for: provider)
    }

    public func fixedModel(for _: VoiceInkProviderModelUse) -> String? {
        nil
    }

    public func supportsModelUse(_ use: VoiceInkProviderModelUse) -> Bool {
        if self == .customCloud {
            return use == .transcription
        }
        return fixedModel(for: use) != nil || !models(for: use).isEmpty
    }

    public func isSelectable(for use: VoiceInkProviderModelUse) -> Bool {
        switch accessRequirement {
        case .bundledService:
            return false
        case .userAPIKey, .localWhisperModel, .localFluidAudioModel, .nativeAppleSpeech, .customCloudModel, .localEnhancementService:
            return supportsModelUse(use)
        }
    }

    public func defaultModel(for use: VoiceInkProviderModelUse) -> String? {
        switch use {
        case .transcription:
            fixedModel(for: use) ?? models(for: use).first
        case .postProcessing:
            postProcessingDefaultModel
        }
    }

    public func selectedModel(_ currentModel: String, for use: VoiceInkProviderModelUse) -> String {
        if self == .customCloud, use == .transcription {
            return currentModel
        }
        if let fixedModel = fixedModel(for: use) {
            return fixedModel
        }

        let availableModels = models(for: use)
        if availableModels.contains(currentModel) {
            return currentModel
        }

        return defaultModel(for: use) ?? ""
    }

    public func modelSelectionPresentation(for use: VoiceInkProviderModelUse) -> VoiceInkProviderModelSelectionPresentation {
        if let fixedModel = fixedModel(for: use) {
            return VoiceInkProviderModelSelectionPresentation(fixedModelName: fixedModel)
        }

        return VoiceInkProviderModelSelectionPresentation(selectableModels: models(for: use))
    }

    public func models(for use: VoiceInkProviderModelUse) -> [String] {
        switch use {
        case .transcription:
            if self == .localFluidAudio {
                return VoiceInkTranscriptionModelCatalog.fluidAudioModels.map(\.name)
            }
            guard let provider = transcriptionModelProvider else { return [] }
            return VoiceInkTranscriptionModelCatalog.modelNames(for: provider)
        case .postProcessing:
            return postProcessingModels ?? []
        }
    }
}
