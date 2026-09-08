import Foundation

public struct VoiceInkPowerModeDeleteConfirmationPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let cancelButtonTitle: String

    public init(
        title: String,
        message: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String
    ) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.cancelButtonTitle = cancelButtonTitle
    }
}

public struct VoiceInkPowerModeValidationAlertPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttonTitle: String

    public init(title: String, message: String, buttonTitle: String) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}

public enum VoiceInkPowerModeRowDetailChipKind: Hashable, Sendable {
    case transcriptionModel
    case selectedLanguage
    case aiModel
    case autoSend
    case contextAwareness
    case prompt
}

public struct VoiceInkPowerModeRowDetailChipPresentation: Equatable, Identifiable, Sendable {
    public let kind: VoiceInkPowerModeRowDetailChipKind
    public let text: String

    public var id: VoiceInkPowerModeRowDetailChipKind {
        kind
    }

    public var systemImageName: String {
        kind.systemImageName
    }

    public var usesAccentStyle: Bool {
        kind.usesAccentStyle
    }

    public init(kind: VoiceInkPowerModeRowDetailChipKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct VoiceInkPowerModeRowDetailPresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let chips: [VoiceInkPowerModeRowDetailChipPresentation]

    public init(isVisible: Bool, chips: [VoiceInkPowerModeRowDetailChipPresentation]) {
        self.isVisible = isVisible
        self.chips = chips
    }
}

public enum VoiceInkPowerModePresentation {
    public static let defaultOverrideDisplayText = "Default"
    public static let closeHelpText = "Close"
    public static let panelTitle = "Power Modes"
    public static let panelSubtitle = "Automate your workflows with context-aware configurations."
    public static let panelInfoTipText = "Automatically apply custom configurations based on the app/website you are using."
    public static let panelLearnMoreURLString = "https://tryvoiceink.com/docs/power-mode"
    public static let settingsSectionTitle = "Power Mode"
    public static let settingsToggleHelpText = "Apply custom settings based on active app or website."
    public static let persistConfiguredPreferencesTitle = "Persist Configured Preferences"
    public static let persistConfiguredPreferencesHelpText = "When enabled, Power Mode preferences stay active after you stop recording instead of reverting to your original preferences. They will only change when a different Power Mode activates."
    public static let settingsDisableAlertTitle = "Power Mode Still Active"
    public static let settingsDisableAlertButtonTitle = "Got it"
    public static let settingsDisableAlertMessage = "Disable or remove your Power Modes first."
    public static let addButtonSystemImageName = "plus"
    public static let reorderButtonTitle = "Reorder"
    public static let reorderButtonSystemImageName = "arrow.up.arrow.down"
    public static let reorderPanelTitle = "Reorder Power Modes"
    public static let reorderPanelCloseHelpText = closeHelpText
    public static let reorderPanelCloseSystemImageName = "xmark"
    public static let reorderHandleSystemImageName = "line.3.horizontal"
    public static let defaultBadgeTitle = defaultOverrideDisplayText
    public static let disabledBadgeTitle = "Disabled"
    public static let emptyPanelTitle = "No Power Modes Yet"
    public static let emptyPanelMessage = "Create first power mode to automate your VoiceInk workflow based on apps/website you are using"
    public static let emptyPanelSystemImageName = "square.grid.2x2.fill"
    public static let sidebarEmptyTitle = "No Power Modes"
    public static let sidebarEmptyMessage = "Add customized power modes for different contexts"
    public static let sidebarEmptyButtonTitle = "Add New Power Mode"
    public static let sidebarEmptySystemImageName = "bolt.circle.fill"
    public static let addIconButtonSystemImageName = "plus.circle.fill"
    public static let popoverTitle = "Select Power Mode"
    public static let popoverEmptyTitle = "No Power Modes Available"
    public static let popoverEmptySystemImageName = "sparkles"
    public static let popoverSelectedSystemImageName = "checkmark"
    public static let recorderButtonFallbackIcon = "✨"
    public static let rowEditActionTitle = "Edit"
    public static let rowEditActionSystemImageName = "pencil"
    public static let formCloseHelpText = closeHelpText
    public static let formCloseSystemImageName = "xmark"
    public static let generalSectionTitle = "General"
    public static let nameFieldPlaceholder = "Name"
    public static let triggerScenariosSectionTitle = "Trigger Scenarios"
    public static let applicationsSectionTitle = "Applications"
    public static let addApplicationHelpText = "Add application"
    public static let noApplicationsText = "No applications added"
    public static let appPickerSearchPlaceholder = "Search apps..."
    public static let appPickerSearchSystemImageName = "magnifyingglass"
    public static let appPickerClearSearchSystemImageName = "xmark.circle.fill"
    public static let appPickerSelectedSystemImageName = "checkmark"
    public static let websitesSectionTitle = "Websites"
    public static let websiteURLFieldPlaceholder = "Enter website URL"
    public static let addWebsiteHelpText = "Add website"
    public static let noWebsitesText = "No websites added"
    public static let transcriptionSectionTitle = "Transcription"
    public static let transcriptionModelPickerTitle = "Model"
    public static let transcriptionLanguageTitle = "Language"
    public static let autodetectedLanguageText = "Autodetected"
    public static let transcriptFormattingDisclosureSystemImageName = "chevron.right"
    public static let aiEnhancementSectionTitle = "AI Enhancement"
    public static let aiEnhancementToggleTitle = aiEnhancementSectionTitle
    public static let advancedSectionTitle = "Advanced"
    public static let formSaveButtonTitle = "Save Changes"
    public static let autoLanguageDisplayText = "Auto"
    public static let englishLanguageDisplayText = "English"
    public static let deleteConfirmationTitle = "Delete Power Mode?"
    public static let deleteConfirmationPrimaryButtonTitle = "Delete"
    public static let formDeleteButtonTitle = deleteConfirmationPrimaryButtonTitle
    public static let rowDeleteActionTitle = deleteConfirmationPrimaryButtonTitle
    public static let rowDeleteActionSystemImageName = "trash"
    public static let deleteConfirmationCancelButtonTitle = "Cancel"
    public static let formCancelButtonTitle = deleteConfirmationCancelButtonTitle
    public static let validationAlertTitle = "Cannot Save Power Mode"
    public static let validationAlertButtonTitle = "OK"
    public static let validationAlertFallbackMessage = "Please fix the validation errors before saving."
    public static let contextAwarenessDisplayText = "Context Awareness"
    public static let defaultPromptDisplayText = "AI"
    public static let aiProviderFormTitle = "AI Provider"
    public static let aiModelFormTitle = "AI Model"
    public static let enhancementPromptFormTitle = "Enhancement Prompt"
    public static let refreshModelsButtonTitle = "Refresh Models"
    public static let refreshModelsButtonHelp = "Refresh models"
    public static let setAsDefaultToggleTitle = "Set as default"
    public static let setAsDefaultHelpText = "Default power mode is used when no specific app or website matches are found."
    public static let autoSendFormTitle = "Auto Send"
    public static let autoSendHelpText = "Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts."
    public static let keyboardShortcutFormTitle = "Keyboard Shortcut"
    public static let keyboardShortcutHelpText = "Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording."
    public static let noTranscriptionModelsAvailableText = "No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab."
    public static let noAIProvidersConnectedText = "No providers connected"
    public static let noAIModelsLoadedText = "No models loaded"
    public static let noAIModelsAvailableText = "No models available"
    public static let noEnhancementPromptsAvailableText = "No prompts available"
    public static let appTriggerSystemImageName = "app.fill"
    public static let websiteTriggerSystemImageName = "globe"
    public static let removeTriggerSystemImageName = "xmark.circle.fill"

    public static func displayName(name: String?, emoji: String?) -> String {
        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return ""
        }
    }

    public static func selectedLanguageDisplayText(
        selectedLanguage: String?,
        languageOptions: [String: String]
    ) -> String {
        guard let selectedLanguage else {
            return defaultOverrideDisplayText
        }

        if selectedLanguage == VoiceInkLanguageCatalog.autoDetectCode {
            return autoLanguageDisplayText
        }

        if selectedLanguage == "en" {
            return englishLanguageDisplayText
        }

        return languageOptions[selectedLanguage] ?? selectedLanguage.uppercased()
    }

    public static func appTriggerCountText(_ count: Int) -> String {
        triggerCountText(count, singular: "App", plural: "Apps")
    }

    public static func websiteTriggerCountText(_ count: Int) -> String {
        triggerCountText(count, singular: "Website", plural: "Websites")
    }

    public static func deleteConfirmation(configName: String) -> VoiceInkPowerModeDeleteConfirmationPresentation {
        VoiceInkPowerModeDeleteConfirmationPresentation(
            title: deleteConfirmationTitle,
            message: "Are you sure you want to delete the '\(configName)' power mode? This action cannot be undone.",
            primaryButtonTitle: deleteConfirmationPrimaryButtonTitle,
            cancelButtonTitle: deleteConfirmationCancelButtonTitle
        )
    }

    public static func validationAlert(errors: [VoiceInkPowerModeValidationError]) -> VoiceInkPowerModeValidationAlertPresentation {
        VoiceInkPowerModeValidationAlertPresentation(
            title: validationAlertTitle,
            message: errors.first?.localizedDescription ?? validationAlertFallbackMessage,
            buttonTitle: validationAlertButtonTitle
        )
    }

    public static func rowDetailPresentation(
        config: PowerModeConfig,
        transcriptionModelDisplayText: String?,
        selectedLanguageDisplayText: String?,
        selectedPromptTitle: String?
    ) -> VoiceInkPowerModeRowDetailPresentation {
        var chips: [VoiceInkPowerModeRowDetailChipPresentation] = []

        if let transcriptionModelDisplayText = visibleNonDefaultDisplayText(transcriptionModelDisplayText) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .transcriptionModel, text: transcriptionModelDisplayText))
        }

        if let selectedLanguageDisplayText = visibleNonDefaultDisplayText(selectedLanguageDisplayText) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .selectedLanguage, text: selectedLanguageDisplayText))
        }

        if config.isAIEnhancementEnabled, let aiModelDisplayText = aiModelDisplayText(config.selectedAIModel) {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .aiModel, text: aiModelDisplayText))
        }

        if config.autoSendKey.isEnabled {
            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .autoSend, text: config.autoSendKey.displayName))
        }

        if config.isAIEnhancementEnabled {
            if config.useScreenCapture {
                chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .contextAwareness, text: contextAwarenessDisplayText))
            }

            chips.append(VoiceInkPowerModeRowDetailChipPresentation(kind: .prompt, text: selectedPromptTitle ?? defaultPromptDisplayText))
        }

        return VoiceInkPowerModeRowDetailPresentation(
            isVisible: transcriptionModelDisplayText != nil || selectedLanguageDisplayText != nil || config.isAIEnhancementEnabled || config.autoSendKey.isEnabled,
            chips: chips
        )
    }

    public static func aiModelDisplayText(_ modelName: String?) -> String? {
        guard let modelName, !modelName.isEmpty else {
            return nil
        }

        return modelName.count > 20 ? String(modelName.prefix(18)) + "..." : modelName
    }

    public static func noAIModelsAvailableText(for provider: VoiceInkAIEnhancementProviderKind) -> String {
        shouldShowRefreshModelsButton(for: provider) ? noAIModelsLoadedText : noAIModelsAvailableText
    }

    public static func shouldShowAIModelOptions(for provider: VoiceInkAIEnhancementProviderKind) -> Bool {
        switch provider {
        case .custom:
            return false
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .localCLI, .mistral, .ollama, .openAI, .openRouter, .soniox, .speechmatics:
            return true
        }
    }

    public static func shouldShowRefreshModelsButton(for provider: VoiceInkAIEnhancementProviderKind) -> Bool {
        VoiceInkAIEnhancementProviderSettingsPresentation.macOS.modelPickerPresentation(
            provider: provider,
            availableModels: []
        ).isRefreshButtonVisible
    }

    public static func recorderButtonIcon(
        hasEnabledConfigurations: Bool,
        activeConfiguration: PowerModeConfig?
    ) -> String {
        guard hasEnabledConfigurations else {
            return recorderButtonFallbackIcon
        }

        return activeConfiguration?.emoji ?? recorderButtonFallbackIcon
    }

    private static func triggerCountText(_ count: Int, singular: String, plural: String) -> String {
        guard count > 0 else {
            return ""
        }
        return count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private static func visibleNonDefaultDisplayText(_ text: String?) -> String? {
        guard let text, text != defaultOverrideDisplayText else {
            return nil
        }
        return text
    }
}

private extension VoiceInkPowerModeRowDetailChipKind {
    var systemImageName: String {
        switch self {
        case .transcriptionModel:
            return "waveform"
        case .selectedLanguage:
            return "globe"
        case .aiModel:
            return "cpu"
        case .autoSend:
            return "keyboard"
        case .contextAwareness:
            return "camera.viewfinder"
        case .prompt:
            return "sparkles"
        }
    }

    var usesAccentStyle: Bool {
        self == .prompt
    }
}

public enum VoiceInkPowerModeBrowser: Equatable, Sendable {
    case safari
    case arc
    case chrome
    case edge
    case firefox
    case brave
    case opera
    case vivaldi
    case orion
    case zen
    case yandex

    public var scriptName: String {
        switch self {
        case .safari: return "safariURL"
        case .arc: return "arcURL"
        case .chrome: return "chromeURL"
        case .edge: return "edgeURL"
        case .firefox: return "firefoxURL"
        case .brave: return "braveURL"
        case .opera: return "operaURL"
        case .vivaldi: return "vivaldiURL"
        case .orion: return "orionURL"
        case .zen: return "zenURL"
        case .yandex: return "yandexURL"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .arc: return "company.thebrowser.Browser"
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .firefox: return "org.mozilla.firefox"
        case .brave: return "com.brave.Browser"
        case .opera: return "com.operasoftware.Opera"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .orion: return "com.kagi.kagimacOS"
        case .zen: return "app.zen-browser.zen"
        case .yandex: return "ru.yandex.desktop.yandex-browser"
        }
    }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .arc: return "Arc"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .firefox: return "Firefox"
        case .brave: return "Brave"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion: return "Orion"
        case .zen: return "Zen Browser"
        case .yandex: return "Yandex Browser"
        }
    }

    public static let allCases: [VoiceInkPowerModeBrowser] = [
        .safari,
        .arc,
        .chrome,
        .edge,
        .brave,
        .opera,
        .vivaldi,
        .orion,
        .yandex
    ]
}

public enum VoiceInkPowerModeBrowserURLDiagnostics {
    public static let loggerCategory = "browser.applescript"

    public static func scriptNotFoundMessage(scriptName: String) -> String {
        "❌ AppleScript file not found: \(scriptName).scpt"
    }

    public static func attemptingExecutionMessage(browserDisplayName: String) -> String {
        "🔍 Attempting to execute AppleScript for \(browserDisplayName)"
    }

    public static func browserNotRunningMessage(browserDisplayName: String) -> String {
        "❌ Browser not running: \(browserDisplayName)"
    }

    public static func executingScriptMessage(browserDisplayName: String) -> String {
        "▶️ Executing AppleScript for \(browserDisplayName)"
    }

    public static func emptyOutputMessage(browserDisplayName: String) -> String {
        "❌ Empty output from AppleScript for \(browserDisplayName)"
    }

    public static func scriptErrorMessage(browserDisplayName: String, output: String) -> String {
        "❌ AppleScript error for \(browserDisplayName): \(output)"
    }

    public static func successMessage(browserDisplayName: String, output: String) -> String {
        "✅ Successfully retrieved URL from \(browserDisplayName): \(output)"
    }

    public static func outputDecodeFailedMessage(browserDisplayName: String) -> String {
        "❌ Failed to decode output from AppleScript for \(browserDisplayName)"
    }

    public static func executionFailedMessage(
        browserDisplayName: String,
        localizedDescription: String
    ) -> String {
        "❌ AppleScript execution failed for \(browserDisplayName): \(localizedDescription)"
    }

    public static func runningStatusMessage(browserDisplayName: String, isRunning: Bool) -> String {
        "\(browserDisplayName) running status: \(isRunning)"
    }
}

public enum VoiceInkPowerModeBrowserDetectionDiagnostics {
    public static let loggerCategory = "browser.detection"

    public static func urlLookupFailedMessage(
        browserDisplayName: String,
        localizedDescription: String
    ) -> String {
        "❌ Failed to get URL from \(browserDisplayName): \(localizedDescription)"
    }
}

public enum VoiceInkPowerModeCustomEmojiAddResult: Equatable, Sendable {
    case added(emoji: String, customEmojis: [String])
    case empty
    case invalid
    case duplicate

    public var addedEmoji: String? {
        guard case .added(let emoji, _) = self else {
            return nil
        }
        return emoji
    }
}

public struct VoiceInkPowerModeEmojiRemovalAlertPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttonTitle: String

    public init(title: String, message: String, buttonTitle: String) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
    }
}

public struct VoiceInkPowerModeEmojiInputDraft: Equatable, Sendable {
    public let text: String
    public let feedbackMessage: String
    public let canSubmit: Bool

    public init(text: String, feedbackMessage: String, canSubmit: Bool) {
        self.text = text
        self.feedbackMessage = feedbackMessage
        self.canSubmit = canSubmit
    }
}

public enum VoiceInkPowerModeEmojiCatalog {
    public static let customEmojisKey = "userAddedEmojis"
    public static let defaultEmojis = ["🏢", "🏠", "💼", "🎮", "📱", "📺", "🎵", "📚", "✏️", "🎨", "🧠", "⚙️", "💻", "🌐", "📝", "📊", "🔍", "💬", "📈", "🔧"]

    public static func customEmojis(from defaults: UserDefaults = .standard) -> [String] {
        defaults.array(forKey: customEmojisKey) as? [String] ?? []
    }

    public static func saveCustomEmojis(
        _ customEmojis: [String],
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(customEmojis, forKey: customEmojisKey)
    }

    public static func allEmojis(customEmojis: [String]) -> [String] {
        defaultEmojis + customEmojis
    }

    public static func isCustomEmoji(_ emoji: String, customEmojis: [String]) -> Bool {
        customEmojis.contains(emoji)
    }

    public static func addCustomEmoji(
        _ emoji: String,
        customEmojis: [String]
    ) -> VoiceInkPowerModeCustomEmojiAddResult {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmoji.isEmpty else {
            return .empty
        }

        guard isValidEmoji(trimmedEmoji) else {
            return .invalid
        }

        guard !allEmojis(customEmojis: customEmojis).contains(trimmedEmoji) else {
            return .duplicate
        }

        return .added(emoji: trimmedEmoji, customEmojis: customEmojis + [trimmedEmoji])
    }

    public static func removeCustomEmoji(
        _ emoji: String,
        customEmojis: [String]
    ) -> [String]? {
        guard let index = customEmojis.firstIndex(of: emoji) else {
            return nil
        }

        var updatedEmojis = customEmojis
        updatedEmojis.remove(at: index)
        return updatedEmojis
    }

    public static func isValidEmoji(_ value: String) -> Bool {
        guard !value.isEmpty, value.count == 1, let character = value.first else {
            return false
        }

        let scalars = character.unicodeScalars
        if scalars.count > 1 {
            return scalars.contains { $0.properties.isEmoji }
        }
        return scalars.first?.properties.isEmojiPresentation == true
    }

    public static func firstValidEmojiCharacter(in value: String) -> String {
        for character in value {
            let emoji = String(character)
            if isValidEmoji(emoji) {
                return emoji
            }
        }
        return ""
    }
}

public enum VoiceInkPowerModeEmojiInputPresentation {
    public static let customEmojiFieldPlaceholder = "➕"
    public static let addButtonTitle = "Add"
    public static let cancelButtonTitle = "Cancel"
    public static let tipText = "Tip: Use ⌃⌘Space for emoji picker or paste an emoji."
    public static let addEmojiAccessibilityLabel = "Add Emoji"
    public static let addEmojiSystemImageName = "plus.circle.fill"
    public static let addCustomEmojiHelpText = "Add custom emoji"
    public static let removeCustomEmojiSystemImageName = "xmark.circle.fill"
    public static let emptySubmitMessage = "Emoji cannot be empty."
    public static let invalidPreviewMessage = "Invalid emoji."
    public static let invalidSubmitMessage = "Invalid emoji character."
    public static let duplicateMessage = "Emoji already exists!"
    public static let inUseAlertTitle = "Emoji in Use"
    public static let inUseAlertButtonTitle = "OK"

    public static func isErrorMessage(_ message: String) -> Bool {
        message == duplicateMessage
            || message == invalidPreviewMessage
            || message == invalidSubmitMessage
            || message == emptySubmitMessage
    }

    public static func inputDraft(
        for rawText: String,
        customEmojis: [String]
    ) -> VoiceInkPowerModeEmojiInputDraft {
        let text = VoiceInkPowerModeEmojiCatalog.firstValidEmojiCharacter(in: rawText)

        guard !text.isEmpty else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: "", canSubmit: false)
        }

        guard !VoiceInkPowerModeEmojiCatalog.allEmojis(customEmojis: customEmojis).contains(text) else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: duplicateMessage, canSubmit: false)
        }

        guard VoiceInkPowerModeEmojiCatalog.isValidEmoji(text) else {
            return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: invalidPreviewMessage, canSubmit: false)
        }

        return VoiceInkPowerModeEmojiInputDraft(text: text, feedbackMessage: "", canSubmit: true)
    }

    public static func submitFeedbackMessage(for result: VoiceInkPowerModeCustomEmojiAddResult) -> String {
        switch result {
        case .added:
            return ""
        case .empty:
            return emptySubmitMessage
        case .invalid:
            return invalidSubmitMessage
        case .duplicate:
            return duplicateMessage
        }
    }

    public static func inUseAlert(emoji: String) -> VoiceInkPowerModeEmojiRemovalAlertPresentation {
        VoiceInkPowerModeEmojiRemovalAlertPresentation(
            title: inUseAlertTitle,
            message: "The emoji \"\(emoji)\" is currently used by one or more Power Modes and cannot be removed.",
            buttonTitle: inUseAlertButtonTitle
        )
    }
}

public struct PowerModeConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]?
    public var urlConfigs: [VoiceInkPowerModeURLConfig]?
    public var isAIEnhancementEnabled: Bool
    public var selectedPrompt: String?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var useScreenCapture: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isEnabled: Bool
    public var isDefault: Bool

    public var selectedPromptUUID: UUID? {
        selectedPrompt.flatMap(UUID.init)
    }

    public var selectedAIProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }

    public func selectedPromptTitle(in prompts: [VoiceInkCustomPrompt]) -> String? {
        guard let selectedPromptUUID else { return nil }
        return prompts.first { $0.id == selectedPromptUUID }?.title
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, appConfigs, urlConfigs, isAIEnhancementEnabled, selectedPrompt, selectedLanguage, isTextFormattingEnabled, punctuationCleanupMode, removePunctuation, lowercaseTranscription, useScreenCapture, selectedAIProvider, selectedAIModel, isAutoSendEnabled, autoSendKey, isEnabled, isDefault
        case selectedWhisperModel
        case selectedTranscriptionModelName
    }

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig]? = nil,
        urlConfigs: [VoiceInkPowerModeURLConfig]? = nil,
        isAIEnhancementEnabled: Bool,
        selectedPrompt: String? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPrompt = selectedPrompt
        self.useScreenCapture = useScreenCapture
        self.autoSendKey = autoSendKey
        self.selectedAIProvider = selectedAIProvider ?? VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
        self.selectedAIModel = selectedAIModel
        self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? VoiceInkCurrentTranscriptionModelPreference.modelName()
        self.selectedLanguage = selectedLanguage ?? VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage()
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        appConfigs = try container.decodeIfPresent([VoiceInkPowerModeAppConfig].self, forKey: .appConfigs)
        urlConfigs = try container.decodeIfPresent([VoiceInkPowerModeURLConfig].self, forKey: .urlConfigs)
        isAIEnhancementEnabled = try container.decode(Bool.self, forKey: .isAIEnhancementEnabled)
        selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled) ?? false
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            let removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation) ?? false
            punctuationCleanupMode = removePunctuation ? .removeAll : .keep
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription) ?? false
        useScreenCapture = try container.decode(Bool.self, forKey: .useScreenCapture)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .autoSendKey),
           let newKey = VoiceInkAutoSendKey(rawValue: rawValue) {
            autoSendKey = newKey
        } else if let oldBool = try container.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled), oldBool {
            autoSendKey = .enter
        } else {
            autoSendKey = .none
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        if let newModelName = try container.decodeIfPresent(String.self, forKey: .selectedTranscriptionModelName) {
            selectedTranscriptionModelName = newModelName
        } else if let oldModelName = try container.decodeIfPresent(String.self, forKey: .selectedWhisperModel) {
            selectedTranscriptionModelName = oldModelName
        } else {
            selectedTranscriptionModelName = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encodeIfPresent(appConfigs, forKey: .appConfigs)
        try container.encodeIfPresent(urlConfigs, forKey: .urlConfigs)
        try container.encode(isAIEnhancementEnabled, forKey: .isAIEnhancementEnabled)
        try container.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encode(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encode(punctuationCleanupMode == .removeAll, forKey: .removePunctuation)
        try container.encode(lowercaseTranscription, forKey: .lowercaseTranscription)
        try container.encode(useScreenCapture, forKey: .useScreenCapture)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encode(autoSendKey, forKey: .autoSendKey)
        try container.encodeIfPresent(selectedTranscriptionModelName, forKey: .selectedTranscriptionModelName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isDefault, forKey: .isDefault)
    }

    public static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool {
        lhs.id == rhs.id
    }
}

public struct VoiceInkPowerModeTranscriptionMetadata: Equatable, Sendable {
    public static let inactive = VoiceInkPowerModeTranscriptionMetadata(name: nil, emoji: nil)

    public let name: String?
    public let emoji: String?

    public init(name: String?, emoji: String?) {
        self.name = name
        self.emoji = emoji
    }

    public static func active(from config: PowerModeConfig?) -> Self {
        guard let config,
              config.isEnabled else {
            return .inactive
        }

        return VoiceInkPowerModeTranscriptionMetadata(
            name: config.name,
            emoji: config.emoji
        )
    }
}

public struct VoiceInkPowerModeConfigurationDraft: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]
    public var urlConfigs: [VoiceInkPowerModeURLConfig]
    public var isAIEnhancementEnabled: Bool
    public var selectedPromptId: UUID?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var useScreenCapture: Bool
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isDefault: Bool

    public init(
        id: UUID,
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig] = [],
        urlConfigs: [VoiceInkPowerModeURLConfig] = [],
        isAIEnhancementEnabled: Bool,
        selectedPromptId: UUID? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPromptId = selectedPromptId
        self.selectedTranscriptionModelName = selectedTranscriptionModelName
        self.selectedLanguage = selectedLanguage
        self.useScreenCapture = useScreenCapture
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.autoSendKey = autoSendKey
        self.isDefault = isDefault
    }
}

public struct VoiceInkPowerModeConfigurationFormState: Equatable, Sendable {
    public static let addDefaultName = ""
    public static let addDefaultEmoji = "✏️"

    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]
    public var urlConfigs: [VoiceInkPowerModeURLConfig]
    public var isAIEnhancementEnabled: Bool
    public var selectedPromptId: UUID?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var useScreenCapture: Bool
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isDefault: Bool
    public var isTranscriptFormattingExpanded: Bool

    public init(
        id: UUID,
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig] = [],
        urlConfigs: [VoiceInkPowerModeURLConfig] = [],
        isAIEnhancementEnabled: Bool,
        selectedPromptId: UUID? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isDefault: Bool = false,
        isTranscriptFormattingExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPromptId = selectedPromptId
        self.selectedTranscriptionModelName = selectedTranscriptionModelName
        self.selectedLanguage = selectedLanguage
        self.useScreenCapture = useScreenCapture
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.autoSendKey = autoSendKey
        self.isDefault = isDefault
        self.isTranscriptFormattingExpanded = isTranscriptFormattingExpanded
    }

    public static func adding(
        id: UUID = UUID(),
        selectedAIProvider: String? = VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
    ) -> Self {
        Self(
            id: id,
            name: addDefaultName,
            emoji: addDefaultEmoji,
            isAIEnhancementEnabled: false,
            selectedAIProvider: selectedAIProvider
        )
    }

    public static func editing(_ config: PowerModeConfig) -> Self {
        Self(
            id: config.id,
            name: config.name,
            emoji: config.emoji,
            appConfigs: config.appConfigs ?? [],
            urlConfigs: config.urlConfigs ?? [],
            isAIEnhancementEnabled: config.isAIEnhancementEnabled,
            selectedPromptId: config.selectedPromptUUID,
            selectedTranscriptionModelName: config.selectedTranscriptionModelName,
            selectedLanguage: config.selectedLanguage,
            useScreenCapture: config.useScreenCapture,
            isTextFormattingEnabled: config.isTextFormattingEnabled,
            punctuationCleanupMode: config.punctuationCleanupMode,
            lowercaseTranscription: config.lowercaseTranscription,
            selectedAIProvider: config.selectedAIProvider,
            selectedAIModel: config.selectedAIModel,
            autoSendKey: config.autoSendKey,
            isDefault: config.isDefault,
            isTranscriptFormattingExpanded: config.isTextFormattingEnabled
                || config.punctuationCleanupMode != .keep
                || config.lowercaseTranscription
        )
    }
}

public struct VoiceInkPowerModeEnhancementSelection: Equatable, Sendable {
    public var selectedPromptId: UUID?
    public var selectedAIProvider: String?
    public var selectedAIModel: String?

    public init(
        selectedPromptId: UUID?,
        selectedAIProvider: String?,
        selectedAIModel: String?
    ) {
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
    }

    public func fillingMissingProviderAndModel(
        currentProvider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        treatsEmptyModelAsMissing: Bool
    ) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider ?? currentProvider.rawValue,
            selectedAIModel: selectedAIModel.isMissing(treatsEmptyAsMissing: treatsEmptyModelAsMissing) ? currentModel : selectedAIModel
        )
    }

    public func resolvedProviderForPicker(
        currentProvider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderKind {
        selectedProviderKind ?? currentProvider
    }

    public func selectedProviderForModelOptions(
        currentProvider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider == nil ? currentProvider : selectedProviderKind
    }

    public func selectingProvider(_ provider: VoiceInkAIEnhancementProviderKind) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: provider.rawValue,
            selectedAIModel: nil
        )
    }

    public func selectingDefaultModelForSelectedProvider(
        defaultModelForProvider: (VoiceInkAIEnhancementProviderKind) -> String
    ) -> Self {
        guard let selectedProviderKind else {
            return self
        }

        return Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: defaultModelForProvider(selectedProviderKind)
        )
    }

    public func providerChangePlan(
        defaultModelForProvider: (VoiceInkAIEnhancementProviderKind) -> String
    ) -> VoiceInkPowerModeEnhancementProviderChangePlan {
        guard selectedProviderKind != nil else {
            return VoiceInkPowerModeEnhancementProviderChangePlan(selectionToApply: nil)
        }

        return VoiceInkPowerModeEnhancementProviderChangePlan(
            selectionToApply: selectingDefaultModelForSelectedProvider(
                defaultModelForProvider: defaultModelForProvider
            )
        )
    }

    public func selectedModelForPicker(currentModel: String) -> String {
        guard let selectedAIModel, !selectedAIModel.isEmpty else {
            return currentModel
        }

        return selectedAIModel
    }

    public func selectingModel(_ model: String) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: model
        )
    }

    public func selectingPromptAfterEnabling(prompts: [VoiceInkCustomPrompt]) -> Self {
        Self(
            selectedPromptId: VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(
                selectedPromptId,
                prompts: prompts
            ),
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel
        )
    }

    public func selectingPromptForEnhancementState(
        isEnabled: Bool,
        prompts: [VoiceInkCustomPrompt]
    ) -> Self {
        guard isEnabled else { return self }

        return selectingPromptAfterEnabling(prompts: prompts)
    }

    public func togglePlan(
        isEnabled: Bool,
        currentProvider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        prompts: [VoiceInkCustomPrompt]
    ) -> VoiceInkPowerModeEnhancementTogglePlan {
        guard isEnabled else {
            return VoiceInkPowerModeEnhancementTogglePlan(selectionToApply: nil)
        }

        return VoiceInkPowerModeEnhancementTogglePlan(
            selectionToApply: fillingMissingProviderAndModel(
                currentProvider: currentProvider,
                currentModel: currentModel,
                treatsEmptyModelAsMissing: false
            )
            .selectingPromptForEnhancementState(
                isEnabled: isEnabled,
                prompts: prompts
            )
        )
    }

    private var selectedProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }
}

public struct VoiceInkPowerModeEnhancementProviderChangePlan: Equatable, Sendable {
    public let selectionToApply: VoiceInkPowerModeEnhancementSelection?

    public init(selectionToApply: VoiceInkPowerModeEnhancementSelection?) {
        self.selectionToApply = selectionToApply
    }

    public func applyRuntimeState(
        applyEnhancementSelection: (VoiceInkPowerModeEnhancementSelection) -> Void
    ) {
        guard let selectionToApply else { return }
        applyEnhancementSelection(selectionToApply)
    }
}

public struct VoiceInkPowerModeEnhancementTogglePlan: Equatable, Sendable {
    public let selectionToApply: VoiceInkPowerModeEnhancementSelection?

    public init(selectionToApply: VoiceInkPowerModeEnhancementSelection?) {
        self.selectionToApply = selectionToApply
    }

    public func applyRuntimeState(
        applyEnhancementSelection: (VoiceInkPowerModeEnhancementSelection) -> Void
    ) {
        guard let selectionToApply else { return }
        applyEnhancementSelection(selectionToApply)
    }
}

enum VoiceInkPowerModeLanguageControl: Equatable, Sendable {
    case disabledAutodetect
    case picker
    case hiddenDefault
}

public struct VoiceInkPowerModeTranscriptionModelFacts: Equatable, Sendable {
    public var name: String
    public var disablesLanguageSelection: Bool
    public var isMultilingual: Bool
    public var languageOptions: [String: String]
    public var prefersNativeAppleEnglish: Bool

    var languageControl: VoiceInkPowerModeLanguageControl {
        if disablesLanguageSelection {
            return .disabledAutodetect
        }

        return isMultilingual ? .picker : .hiddenDefault
    }

    public var shouldShowAutodetectOnlyLanguage: Bool {
        languageControl == .disabledAutodetect
    }

    public var shouldShowLanguagePicker: Bool {
        languageControl == .picker
    }

    public var shouldApplyDefaultLanguageIfMissing: Bool {
        languageControl == .hiddenDefault
    }

    public var shouldRepairSelectedLanguageForPowerMode: Bool {
        languageControl != .disabledAutodetect
    }

    public init(
        name: String,
        languageSource: VoiceInkTranscriptionLanguageSource,
        isMultilingual: Bool,
        languageOptions: [String: String]
    ) {
        self.init(
            name: name,
            disablesLanguageSelection: languageSource.disablesTranscriptionLanguageSelection,
            isMultilingual: isMultilingual,
            languageOptions: languageOptions,
            prefersNativeAppleEnglish: languageSource.prefersNativeAppleEnglishFallback
        )
    }

    public init(
        name: String,
        disablesLanguageSelection: Bool,
        isMultilingual: Bool,
        languageOptions: [String: String],
        prefersNativeAppleEnglish: Bool
    ) {
        self.name = name
        self.disablesLanguageSelection = disablesLanguageSelection
        self.isMultilingual = isMultilingual
        self.languageOptions = languageOptions
        self.prefersNativeAppleEnglish = prefersNativeAppleEnglish
    }
}

public struct VoiceInkPowerModeTranscriptionSelection: Equatable, Sendable {
    public var selectedModelName: String?
    public var selectedLanguage: String?

    public init(selectedModelName: String?, selectedLanguage: String?) {
        self.selectedModelName = selectedModelName
        self.selectedLanguage = selectedLanguage
    }

    public func selectedModelNameForPicker(currentModelName: String?) -> String? {
        selectedModelName ?? currentModelName
    }

    public func selectingModelName(_ modelName: String?) -> Self {
        Self(selectedModelName: modelName, selectedLanguage: selectedLanguage)
    }

    public func selectedLanguageForPicker(storedLanguage: String) -> String? {
        selectedLanguage ?? storedLanguage
    }

    public func selectingLanguage(_ language: String?) -> Self {
        Self(selectedModelName: selectedModelName, selectedLanguage: language)
    }

    public func selectingAutodetectLanguage() -> Self {
        selectingLanguage(VoiceInkLanguageCatalog.autoDetectCode)
    }

    public func selectingDefaultLanguageIfMissing(_ defaultLanguage: String) -> Self {
        guard selectedLanguage == nil else {
            return self
        }

        return selectingLanguage(defaultLanguage)
    }

    public func selectingCompatibleLanguage(
        for model: VoiceInkPowerModeTranscriptionModelFacts,
        storedLanguage: String?
    ) -> Self {
        switch model.languageControl {
        case .disabledAutodetect:
            return selectingAutodetectLanguage()
        case .picker, .hiddenDefault:
            return selectingLanguage(
                VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                    selectedLanguage ?? storedLanguage,
                    languages: model.languageOptions,
                    prefersNativeAppleEnglish: model.prefersNativeAppleEnglish
                )
            )
        }
    }

    public func modelChangePlan(
        selectedModelFacts: VoiceInkPowerModeTranscriptionModelFacts?,
        storedLanguage: String?
    ) -> VoiceInkPowerModeTranscriptionModelChangePlan {
        guard let selectedModelFacts else {
            return VoiceInkPowerModeTranscriptionModelChangePlan(selectionToApply: nil)
        }

        return VoiceInkPowerModeTranscriptionModelChangePlan(
            selectionToApply: selectingCompatibleLanguage(
                for: selectedModelFacts,
                storedLanguage: storedLanguage
            )
        )
    }

    public func languageControlAppearPlan(
        for model: VoiceInkPowerModeTranscriptionModelFacts,
        defaultLanguage: String
    ) -> VoiceInkPowerModeTranscriptionLanguageControlAppearPlan {
        switch model.languageControl {
        case .disabledAutodetect:
            return VoiceInkPowerModeTranscriptionLanguageControlAppearPlan(
                selectionToApply: selectingAutodetectLanguage()
            )
        case .picker:
            return VoiceInkPowerModeTranscriptionLanguageControlAppearPlan(selectionToApply: nil)
        case .hiddenDefault:
            return VoiceInkPowerModeTranscriptionLanguageControlAppearPlan(
                selectionToApply: selectingDefaultLanguageIfMissing(defaultLanguage)
            )
        }
    }
}

public struct VoiceInkPowerModeTranscriptionModelChangePlan: Equatable, Sendable {
    public let selectionToApply: VoiceInkPowerModeTranscriptionSelection?

    public init(selectionToApply: VoiceInkPowerModeTranscriptionSelection?) {
        self.selectionToApply = selectionToApply
    }

    public func applyRuntimeState(
        applyTranscriptionSelection: (VoiceInkPowerModeTranscriptionSelection) -> Void
    ) {
        guard let selectionToApply else { return }
        applyTranscriptionSelection(selectionToApply)
    }
}

public struct VoiceInkPowerModeTranscriptionLanguageControlAppearPlan: Equatable, Sendable {
    public let selectionToApply: VoiceInkPowerModeTranscriptionSelection?

    public init(selectionToApply: VoiceInkPowerModeTranscriptionSelection?) {
        self.selectionToApply = selectionToApply
    }

    public func applyRuntimeState(
        applyTranscriptionSelection: (VoiceInkPowerModeTranscriptionSelection) -> Void
    ) {
        guard let selectionToApply else { return }
        applyTranscriptionSelection(selectionToApply)
    }
}

public struct VoiceInkPowerModeConfigurationFormAppearPlan: Equatable, Sendable {
    public let enhancementSelection: VoiceInkPowerModeEnhancementSelection
    public let transcriptionSelection: VoiceInkPowerModeTranscriptionSelection?

    public init(
        enhancementSelection: VoiceInkPowerModeEnhancementSelection,
        transcriptionSelection: VoiceInkPowerModeTranscriptionSelection?
    ) {
        self.enhancementSelection = enhancementSelection
        self.transcriptionSelection = transcriptionSelection
    }

    public func applyRuntimeState(
        applyEnhancementSelection: (VoiceInkPowerModeEnhancementSelection) -> Void,
        applyTranscriptionSelection: (VoiceInkPowerModeTranscriptionSelection) -> Void
    ) {
        applyEnhancementSelection(enhancementSelection)

        if let transcriptionSelection {
            applyTranscriptionSelection(transcriptionSelection)
        }
    }
}

public struct VoiceInkPowerModeTranscriptionModelResourceFacts: Equatable, Sendable {
    public var name: String
    public var loadsLocalWhisperModel: Bool

    public init(name: String, languageSource: VoiceInkTranscriptionLanguageSource) {
        self.init(
            name: name,
            loadsLocalWhisperModel: languageSource.loadsLocalWhisperModelResource
        )
    }

    public init(name: String, loadsLocalWhisperModel: Bool) {
        self.name = name
        self.loadsLocalWhisperModel = loadsLocalWhisperModel
    }
}

private enum VoiceInkPowerModeTranscriptionModelResourceAction: Equatable, Sendable {
    case none
    case cleanupOnly
    case cleanupAndLoadLocalModel(String)
}

public struct VoiceInkPowerModeTranscriptionModelResourcePlan: Equatable, Sendable {
    private let selectedModelName: String?
    private let action: VoiceInkPowerModeTranscriptionModelResourceAction

    private init(
        selectedModelName: String?,
        action: VoiceInkPowerModeTranscriptionModelResourceAction
    ) {
        self.selectedModelName = selectedModelName
        self.action = action
    }

    public func applyRuntimeState(
        setDefaultTranscriptionModelNamed: (String) async -> Bool,
        cleanupModelResources: () async -> Void,
        loadDownloadedLocalModelNamed: (String) async throws -> Void,
        handleLocalModelLoadFailure: (String, Error) async -> Void
    ) async {
        guard let selectedModelName,
              await setDefaultTranscriptionModelNamed(selectedModelName) else {
            return
        }

        switch action {
        case .none:
            break
        case .cleanupOnly:
            await cleanupModelResources()
        case .cleanupAndLoadLocalModel(let modelName):
            await cleanupModelResources()
            do {
                try await loadDownloadedLocalModelNamed(modelName)
            } catch {
                await handleLocalModelLoadFailure(modelName, error)
            }
        }
    }

    public static func plan(
        selectedModelName: String?,
        currentModelName: String?,
        availableModels: [VoiceInkPowerModeTranscriptionModelResourceFacts],
        availableLocalModelNames: Set<String>
    ) -> Self {
        guard let selectedModelName,
              let selectedModel = availableModels.first(where: { $0.name == selectedModelName }),
              currentModelName != selectedModelName else {
            return Self(selectedModelName: nil, action: .none)
        }

        guard selectedModel.loadsLocalWhisperModel else {
            return Self(selectedModelName: selectedModelName, action: .cleanupOnly)
        }

        guard availableLocalModelNames.contains(selectedModelName) else {
            return Self(selectedModelName: selectedModelName, action: .cleanupOnly)
        }

        return Self(
            selectedModelName: selectedModelName,
            action: .cleanupAndLoadLocalModel(selectedModelName)
        )
    }
}

public struct VoiceInkPowerModeShortcutImport: Equatable, Sendable {
    public var backupKey: String
    public var id: UUID

    public init(backupKey: String, id: UUID) {
        self.backupKey = backupKey
        self.id = id
    }
}

fileprivate struct VoiceInkPowerModeShortcutExportRequest: Equatable, Sendable {
    var backupKey: String
    var id: UUID

    init(backupKey: String, id: UUID) {
        self.backupKey = backupKey
        self.id = id
    }
}

public struct VoiceInkPowerModeBackupImportPlan: Equatable, Sendable {
    private var existingConfigurationIdsToClear: [UUID]
    private var importedConfigurations: [PowerModeConfig]
    private var shortcutImports: [VoiceInkPowerModeShortcutImport]
    private var hasCustomEmojiBackupRecord: Bool
    private var customEmojisToImport: [String]

    private var importedConfigurationCount: Int {
        importedConfigurations.count
    }

    fileprivate init(
        existingConfigurationIdsToClear: [UUID],
        importedConfigurations: [PowerModeConfig],
        shortcutImports: [VoiceInkPowerModeShortcutImport],
        hasCustomEmojiBackupRecord: Bool,
        customEmojisToImport: [String]
    ) {
        self.existingConfigurationIdsToClear = existingConfigurationIdsToClear
        self.importedConfigurations = importedConfigurations
        self.shortcutImports = shortcutImports
        self.hasCustomEmojiBackupRecord = hasCustomEmojiBackupRecord
        self.customEmojisToImport = customEmojisToImport
    }

    public func applyRuntimeState<ShortcutBackup>(
        removeShortcutStorageForConfiguration: (UUID) -> Void,
        setImportedConfigurations: ([PowerModeConfig]) -> Void,
        shortcutBackup: (String) -> ShortcutBackup?,
        importShortcut: (ShortcutBackup, UUID) -> Void,
        saveConfigurations: () -> Void,
        addCustomEmoji: (String) -> Void,
        reportImportedConfigurationCount: (Int) -> Void
    ) {
        for id in existingConfigurationIdsToClear {
            removeShortcutStorageForConfiguration(id)
        }

        setImportedConfigurations(importedConfigurations)

        for shortcutImport in shortcutImports {
            guard let backup = shortcutBackup(shortcutImport.backupKey) else { continue }
            importShortcut(backup, shortcutImport.id)
        }

        saveConfigurations()

        if hasCustomEmojiBackupRecord {
            for emoji in customEmojisToImport {
                addCustomEmoji(emoji)
            }
        }

        reportImportedConfigurationCount(importedConfigurationCount)
    }
}

public struct VoiceInkPowerModeBackupExportPlan: Equatable, Sendable {
    private var configurationsToExport: [PowerModeConfig]
    private var shortcutRequests: [VoiceInkPowerModeShortcutExportRequest]
    private var customEmojisToExport: [String]

    fileprivate init(
        configurationsToExport: [PowerModeConfig],
        shortcutRequests: [VoiceInkPowerModeShortcutExportRequest],
        customEmojisToExport: [String]
    ) {
        self.configurationsToExport = configurationsToExport
        self.shortcutRequests = shortcutRequests
        self.customEmojisToExport = customEmojisToExport
    }

    public func applyRuntimeState<ShortcutBackup>(
        backupForConfiguration: (UUID) -> ShortcutBackup?,
        setConfigurations: ([PowerModeConfig]) -> Void,
        setShortcutBackups: ([String: ShortcutBackup]?) -> Void,
        setCustomEmojis: ([String]) -> Void
    ) {
        setConfigurations(configurationsToExport)
        setShortcutBackups(
            VoiceInkPowerModePolicy.powerModeShortcutBackups(
                for: shortcutRequests,
                backupForConfiguration: backupForConfiguration
            )
        )
        setCustomEmojis(customEmojisToExport)
    }
}

public struct VoiceInkPowerModeLanguageApplicationPlan: Equatable, Sendable {
    private var languageToSave: String?

    private var shouldPostLanguageDidChange: Bool {
        languageToSave != nil
    }

    private init(languageToSave: String?) {
        self.languageToSave = languageToSave
    }

    public func applyRuntimeState(
        saveSelectedLanguage: (String) -> Void,
        postLanguageDidChange: () -> Void
    ) {
        guard shouldPostLanguageDidChange,
              let languageToSave else { return }

        saveSelectedLanguage(languageToSave)
        postLanguageDidChange()
    }

    public static func plan(selectedLanguage: String?) -> Self {
        // Power Mode stores an explicit choice or restores a snapshot of user intent.
        Self(languageToSave: selectedLanguage)
    }

}

public struct VoiceInkPowerModeSessionApplicationFacts: Equatable, Sendable {
    public var currentModelName: String?
    public var availableModelResourceFacts: [VoiceInkPowerModeTranscriptionModelResourceFacts]
    public var availableLocalModelNames: Set<String>

    public init(
        currentModelName: String?,
        availableModelResourceFacts: [VoiceInkPowerModeTranscriptionModelResourceFacts],
        availableLocalModelNames: Set<String>
    ) {
        self.currentModelName = currentModelName
        self.availableModelResourceFacts = availableModelResourceFacts
        self.availableLocalModelNames = availableLocalModelNames
    }
}

public struct VoiceInkPowerModeSessionApplicationPlan: Equatable, Sendable {
    private var preferenceApplication: VoiceInkPowerModePreferenceApplication
    private var modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan
    private var languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan
    private var shouldPostConfigurationApplied: Bool

    private init(
        preferenceApplication: VoiceInkPowerModePreferenceApplication,
        modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan,
        languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan,
        shouldPostConfigurationApplied: Bool
    ) {
        self.preferenceApplication = preferenceApplication
        self.modelResourcePlan = modelResourcePlan
        self.languageApplicationPlan = languageApplicationPlan
        self.shouldPostConfigurationApplied = shouldPostConfigurationApplied
    }

    public func applyRuntimeState(
        applyPreferenceApplication: (VoiceInkPowerModePreferenceApplication) -> Void,
        applyModelResourcePlan: (VoiceInkPowerModeTranscriptionModelResourcePlan) async -> Void,
        applyLanguageApplicationPlan: (VoiceInkPowerModeLanguageApplicationPlan) -> Void,
        postConfigurationApplied: () -> Void
    ) async {
        applyPreferenceApplication(preferenceApplication)
        await applyModelResourcePlan(modelResourcePlan)
        applyLanguageApplicationPlan(languageApplicationPlan)

        if shouldPostConfigurationApplied {
            postConfigurationApplied()
        }
    }

    public static func applying(
        config: PowerModeConfig,
        facts: VoiceInkPowerModeSessionApplicationFacts
    ) -> Self {
        plan(
            preferenceApplication: config.powerModePreferenceApplication,
            selectedModelName: config.selectedTranscriptionModelName,
            selectedLanguage: config.selectedLanguage,
            facts: facts,
            shouldPostConfigurationApplied: true
        )
    }

    public static func restoring(
        state: VoiceInkPowerModeApplicationState,
        facts: VoiceInkPowerModeSessionApplicationFacts
    ) -> Self {
        plan(
            preferenceApplication: state.powerModePreferenceRestore,
            selectedModelName: state.transcriptionModelName,
            selectedLanguage: state.selectedLanguage,
            facts: facts,
            shouldPostConfigurationApplied: false
        )
    }

    private static func plan(
        preferenceApplication: VoiceInkPowerModePreferenceApplication,
        selectedModelName: String?,
        selectedLanguage: String?,
        facts: VoiceInkPowerModeSessionApplicationFacts,
        shouldPostConfigurationApplied: Bool
    ) -> Self {
        Self(
            preferenceApplication: preferenceApplication,
            modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
                selectedModelName: selectedModelName,
                currentModelName: facts.currentModelName,
                availableModels: facts.availableModelResourceFacts,
                availableLocalModelNames: facts.availableLocalModelNames
            ),
            languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan.plan(
                selectedLanguage: selectedLanguage
            ),
            shouldPostConfigurationApplied: shouldPostConfigurationApplied
        )
    }
}

public struct VoiceInkPowerModeApplicationState: Codable, Equatable, Sendable {
    public var isEnhancementEnabled: Bool
    public var useScreenCaptureContext: Bool
    public var selectedPromptId: String?
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var selectedLanguage: String?
    public var transcriptionModelName: String?
    public var isTextFormattingEnabled: Bool?
    public var punctuationCleanupMode: PunctuationCleanupMode?
    public var removePunctuation: Bool?
    public var lowercaseTranscription: Bool?

    public var selectedPromptUUID: UUID? {
        selectedPromptId.flatMap(UUID.init)
    }

    public var selectedAIProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }

    public var cleanupRestore: VoiceInkPowerModeCleanupRestore {
        VoiceInkPowerModeCleanupRestore(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationMode: punctuationCleanupMode ?? removePunctuation.map { $0 ? .removeAll : .keep },
            lowercaseTranscription: lowercaseTranscription
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isEnhancementEnabled
        case useScreenCaptureContext
        case selectedPromptId
        case selectedAIProvider
        case selectedAIModel
        case selectedLanguage
        case transcriptionModelName
        case isTextFormattingEnabled
        case punctuationCleanupMode
        case removePunctuation
        case lowercaseTranscription
    }

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        selectedPromptId: String? = nil,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        selectedLanguage: String? = nil,
        transcriptionModelName: String? = nil,
        isTextFormattingEnabled: Bool? = nil,
        punctuationCleanupMode: PunctuationCleanupMode? = nil,
        removePunctuation: Bool? = nil,
        lowercaseTranscription: Bool? = nil
    ) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.useScreenCaptureContext = useScreenCaptureContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.removePunctuation = removePunctuation
        self.lowercaseTranscription = lowercaseTranscription
    }

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        selectedPromptId: UUID? = nil,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        selectedLanguage: String? = nil,
        transcriptionModelName: String? = nil,
        cleanupSettings: VoiceInkTranscriptionCleanupSettings
    ) {
        self.init(
            isEnhancementEnabled: isEnhancementEnabled,
            useScreenCaptureContext: useScreenCaptureContext,
            selectedPromptId: selectedPromptId?.uuidString,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel,
            selectedLanguage: selectedLanguage,
            transcriptionModelName: transcriptionModelName,
            isTextFormattingEnabled: cleanupSettings.isTextFormattingEnabled,
            punctuationCleanupMode: cleanupSettings.punctuationMode,
            removePunctuation: cleanupSettings.removesAllPunctuation,
            lowercaseTranscription: cleanupSettings.lowercaseTranscription
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnhancementEnabled = try container.decode(Bool.self, forKey: .isEnhancementEnabled)
        useScreenCaptureContext = try container.decode(Bool.self, forKey: .useScreenCaptureContext)
        selectedPromptId = try container.decodeIfPresent(String.self, forKey: .selectedPromptId)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled)
        removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation)
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            punctuationCleanupMode = removePunctuation.map { $0 ? .removeAll : .keep }
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnhancementEnabled, forKey: .isEnhancementEnabled)
        try container.encode(useScreenCaptureContext, forKey: .useScreenCaptureContext)
        try container.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encodeIfPresent(transcriptionModelName, forKey: .transcriptionModelName)
        try container.encodeIfPresent(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encodeIfPresent(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encodeIfPresent(removePunctuation, forKey: .removePunctuation)
        try container.encodeIfPresent(lowercaseTranscription, forKey: .lowercaseTranscription)
    }
}

public struct VoiceInkPowerModeCleanupRestore: Equatable, Sendable {
    public let isTextFormattingEnabled: Bool?
    public let punctuationMode: PunctuationCleanupMode?
    public let lowercaseTranscription: Bool?

    public init(
        isTextFormattingEnabled: Bool?,
        punctuationMode: PunctuationCleanupMode?,
        lowercaseTranscription: Bool?
    ) {
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationMode = punctuationMode
        self.lowercaseTranscription = lowercaseTranscription
    }
}

enum VoiceInkPowerModePromptSelectionApplication: Equatable, Sendable {
    case leaveUnchanged
    case set(UUID?)
}

public struct VoiceInkPowerModePreferenceApplication: Equatable, Sendable {
    private let isEnhancementEnabled: Bool
    private let useScreenCaptureContext: Bool
    private let promptSelection: VoiceInkPowerModePromptSelectionApplication
    private let selectedAIProvider: VoiceInkAIEnhancementProviderKind?
    private let selectedAIModel: String?
    private let cleanupRestore: VoiceInkPowerModeCleanupRestore

    init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        promptSelection: VoiceInkPowerModePromptSelectionApplication,
        selectedAIProvider: VoiceInkAIEnhancementProviderKind?,
        selectedAIModel: String?,
        cleanupRestore: VoiceInkPowerModeCleanupRestore
    ) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.useScreenCaptureContext = useScreenCaptureContext
        self.promptSelection = promptSelection
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.cleanupRestore = cleanupRestore
    }

    public func applyRuntimeState(
        setEnhancementEnabled: (Bool) -> Void,
        setUseScreenCaptureContext: (Bool) -> Void,
        setSelectedPromptId: (UUID?) -> Void,
        setSelectedAIProvider: (VoiceInkAIEnhancementProviderKind) -> Void,
        selectAIModel: (String) -> Void,
        saveTextFormattingEnabled: (Bool) -> Void,
        setPunctuationCleanupMode: (PunctuationCleanupMode) -> Void,
        saveLowercaseTranscription: (Bool) -> Void
    ) {
        setEnhancementEnabled(isEnhancementEnabled)
        setUseScreenCaptureContext(useScreenCaptureContext)

        switch promptSelection {
        case .leaveUnchanged:
            break
        case .set(let selectedPromptId):
            setSelectedPromptId(selectedPromptId)
        }

        if let selectedAIProvider {
            setSelectedAIProvider(selectedAIProvider)
        }
        if let selectedAIModel {
            selectAIModel(selectedAIModel)
        }

        if let isTextFormattingEnabled = cleanupRestore.isTextFormattingEnabled {
            saveTextFormattingEnabled(isTextFormattingEnabled)
        }
        if let punctuationCleanupMode = cleanupRestore.punctuationMode {
            setPunctuationCleanupMode(punctuationCleanupMode)
        }
        if let lowercaseTranscription = cleanupRestore.lowercaseTranscription {
            saveLowercaseTranscription(lowercaseTranscription)
        }
    }
}

public extension PowerModeConfig {
    var powerModePreferenceApplication: VoiceInkPowerModePreferenceApplication {
        let appliesEnhancementSettings = isAIEnhancementEnabled

        return VoiceInkPowerModePreferenceApplication(
            isEnhancementEnabled: isAIEnhancementEnabled,
            useScreenCaptureContext: useScreenCapture,
            promptSelection: appliesEnhancementSettings
                ? selectedPromptUUID.map { .set($0) } ?? .leaveUnchanged
                : .leaveUnchanged,
            selectedAIProvider: appliesEnhancementSettings ? selectedAIProviderKind : nil,
            selectedAIModel: appliesEnhancementSettings ? selectedAIModel : nil,
            cleanupRestore: VoiceInkPowerModeCleanupRestore(
                isTextFormattingEnabled: isTextFormattingEnabled,
                punctuationMode: punctuationCleanupMode,
                lowercaseTranscription: lowercaseTranscription
            )
        )
    }
}

public extension VoiceInkPowerModeApplicationState {
    var powerModePreferenceRestore: VoiceInkPowerModePreferenceApplication {
        VoiceInkPowerModePreferenceApplication(
            isEnhancementEnabled: isEnhancementEnabled,
            useScreenCaptureContext: useScreenCaptureContext,
            promptSelection: .set(selectedPromptUUID),
            selectedAIProvider: selectedAIProviderKind,
            selectedAIModel: selectedAIModel,
            cleanupRestore: cleanupRestore
        )
    }
}

private extension Optional where Wrapped == String {
    func isMissing(treatsEmptyAsMissing: Bool) -> Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return treatsEmptyAsMissing && value.isEmpty
        }
    }
}

public struct VoiceInkPowerModeSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var originalState: VoiceInkPowerModeApplicationState

    public init(id: UUID, startTime: Date, originalState: VoiceInkPowerModeApplicationState) {
        self.id = id
        self.startTime = startTime
        self.originalState = originalState
    }
}

public struct VoiceInkPowerModeSessionBeginPlan: Equatable, Sendable {
    private var startsNewSession: Bool

    private var shouldInstallSettingsObserver: Bool {
        startsNewSession
    }

    fileprivate init(startsNewSession: Bool) {
        self.startsNewSession = startsNewSession
    }

    public static func plan(activeSession: VoiceInkPowerModeSession?) -> Self {
        Self(startsNewSession: activeSession == nil)
    }

    private func sessionToSave(
        id: UUID,
        startTime: Date,
        originalState: @autoclosure () -> VoiceInkPowerModeApplicationState
    ) -> VoiceInkPowerModeSession? {
        guard startsNewSession else { return nil }
        return VoiceInkPowerModeSession(
            id: id,
            startTime: startTime,
            originalState: originalState()
        )
    }

    public func applyRuntimeState(
        id: UUID,
        startTime: Date,
        originalState: @autoclosure () -> VoiceInkPowerModeApplicationState,
        saveSession: (VoiceInkPowerModeSession) -> Void,
        installSettingsObserver: () -> Void
    ) {
        guard let session = sessionToSave(
            id: id,
            startTime: startTime,
            originalState: originalState()
        ) else { return }

        saveSession(session)

        if shouldInstallSettingsObserver {
            installSettingsObserver()
        }
    }
}

public struct VoiceInkPowerModeSessionSnapshotPlan: Equatable, Sendable {
    private var activeSession: VoiceInkPowerModeSession?

    private var shouldCaptureCurrentState: Bool {
        activeSession != nil
    }

    fileprivate init(activeSession: VoiceInkPowerModeSession?) {
        self.activeSession = activeSession
    }

    public static func plan(
        isApplyingPowerModeConfiguration: Bool,
        activeSession: VoiceInkPowerModeSession?
    ) -> Self {
        guard !isApplyingPowerModeConfiguration else {
            return Self(activeSession: nil)
        }

        return Self(activeSession: activeSession)
    }

    private func sessionToSave(
        currentState: VoiceInkPowerModeApplicationState
    ) -> VoiceInkPowerModeSession? {
        guard var activeSession else { return nil }
        activeSession.originalState = currentState
        return activeSession
    }

    public func applyRuntimeState(
        currentState: @autoclosure () -> VoiceInkPowerModeApplicationState,
        saveSession: (VoiceInkPowerModeSession) -> Void
    ) {
        guard shouldCaptureCurrentState,
              let session = sessionToSave(currentState: currentState()) else { return }

        saveSession(session)
    }
}

public struct VoiceInkPowerModeSessionRecoveryPlan: Equatable, Sendable {
    private let shouldRecover: Bool

    fileprivate init(shouldRecover: Bool) {
        self.shouldRecover = shouldRecover
    }

    public static func plan(activeSession: VoiceInkPowerModeSession?) -> Self {
        Self(shouldRecover: activeSession != nil)
    }

    public func applyRuntimeState(
        logRecoveringAbandonedSession: () -> Void,
        scheduleEndSession: () -> Void
    ) {
        guard shouldRecover else { return }

        logRecoveringAbandonedSession()
        scheduleEndSession()
    }
}

public enum VoiceInkPowerModeSessionDiagnostics {
    public static let notConfiguredMessage = "SessionManager not configured."
    public static let recoveringAbandonedSessionMessage = "Recovering abandoned Power Mode session."

    public static func localModelLoadFailedMessage(modelName: String, errorDescription: String) -> String {
        "Power Mode: Failed to load local model '\(modelName)': \(errorDescription)"
    }

    public static func saveFailedMessage(errorDescription: String) -> String {
        "Error saving Power Mode session: \(errorDescription)"
    }

    public static func loadFailedMessage(errorDescription: String) -> String {
        "Error loading Power Mode session: \(errorDescription)"
    }
}

public struct VoiceInkPowerModeActivationPlan: Equatable, Sendable {
    private let configuration: PowerModeConfig?

    private init(configuration: PowerModeConfig?) {
        self.configuration = configuration
    }

    public static func activating(_ configuration: PowerModeConfig?) -> Self {
        Self(configuration: configuration)
    }

    public func applyRuntimeState(
        setActiveConfiguration: (PowerModeConfig) async -> Void,
        beginSession: (PowerModeConfig) async -> Void
    ) async {
        guard let configuration else { return }

        await setActiveConfiguration(configuration)
        await beginSession(configuration)
    }
}

public struct VoiceInkPowerModeActiveConfigurationRestorePlan: Equatable, Sendable {
    private let activeConfiguration: PowerModeConfig?

    private init(activeConfiguration: PowerModeConfig?) {
        self.activeConfiguration = activeConfiguration
    }

    public static func restoring(
        configurations: [PowerModeConfig],
        activeConfigurationID: UUID?
    ) -> Self {
        guard let activeConfigurationID else {
            return Self(activeConfiguration: nil)
        }

        return Self(activeConfiguration: configurations.powerModeConfiguration(with: activeConfigurationID))
    }

    public func applyRuntimeState(setActiveConfiguration: (PowerModeConfig?) -> Void) {
        setActiveConfiguration(activeConfiguration)
    }
}

public struct VoiceInkPowerModeRecordingFinishPlan: Equatable, Sendable {
    private let shouldRestorePowerModeSession: Bool

    private init(shouldRestorePowerModeSession: Bool) {
        self.shouldRestorePowerModeSession = shouldRestorePowerModeSession
    }

    public static func finishingRecording(shouldPersistConfiguredPreferences: Bool) -> Self {
        Self(shouldRestorePowerModeSession: !shouldPersistConfiguredPreferences)
    }

    @MainActor
    public func applyRuntimeState(
        endSession: @MainActor () async -> Void,
        clearActiveConfiguration: @MainActor () -> Void
    ) async {
        guard shouldRestorePowerModeSession else { return }

        await endSession()
        clearActiveConfiguration()
    }
}

public struct VoiceInkPowerModeAutomaticResolutionPlan: Equatable, Sendable {
    private let configurations: [PowerModeConfig]
    private let explicitID: UUID?

    private init(configurations: [PowerModeConfig], explicitID: UUID?) {
        self.configurations = configurations
        self.explicitID = explicitID
    }

    public static func resolving(
        configurations: [PowerModeConfig],
        explicitID: UUID? = nil
    ) -> Self {
        Self(configurations: configurations, explicitID: explicitID)
    }

    public func applyRuntimeState(
        frontmostApplicationBundleIdentifier: () async -> String?,
        readCurrentWebsiteURL: (VoiceInkPowerModeBrowser) async throws -> String,
        logBrowserURLFailure: (String) -> Void
    ) async -> PowerModeConfig? {
        if let config = configurations.resolvedPowerModeConfiguration(explicitID: explicitID) {
            return config
        }

        guard configurations.hasEnabledAutomaticRules else {
            return nil
        }

        guard let bundleIdentifier = await frontmostApplicationBundleIdentifier() else {
            return nil
        }

        var currentWebsiteURL: String?
        if configurations.hasEnabledURLRules,
           let browser = VoiceInkPowerModeBrowser.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            do {
                currentWebsiteURL = try await readCurrentWebsiteURL(browser)
            } catch {
                logBrowserURLFailure(
                    VoiceInkPowerModeBrowserDetectionDiagnostics.urlLookupFailedMessage(
                        browserDisplayName: browser.displayName,
                        localizedDescription: error.localizedDescription
                    )
                )
            }
        }

        return configurations.resolvedPowerModeConfiguration(
            websiteURL: currentWebsiteURL,
            appBundleIdentifier: bundleIdentifier
        )
    }
}

public struct VoiceInkPowerModeConfigurationMutationPlan: Equatable, Sendable {
    public let didMutate: Bool
    private let updatedConfigurations: [PowerModeConfig]
    private let shouldApplyConfigurations: Bool
    private let shortcutConfigurationIdToRemove: UUID?
    private let shouldSaveConfigurations: Bool
    private let shouldPostShortcutAvailabilityChange: Bool

    private init(
        originalConfigurations: [PowerModeConfig],
        updatedConfigurations: [PowerModeConfig],
        didMutate: Bool,
        shouldApplyConfigurations: Bool? = nil,
        shortcutConfigurationIdToRemove: UUID? = nil,
        shouldSaveConfigurations: Bool,
        detectsShortcutAvailabilityChange: Bool
    ) {
        self.didMutate = didMutate
        self.updatedConfigurations = updatedConfigurations
        self.shouldApplyConfigurations = shouldApplyConfigurations ?? didMutate
        self.shortcutConfigurationIdToRemove = shortcutConfigurationIdToRemove
        self.shouldSaveConfigurations = shouldSaveConfigurations
        self.shouldPostShortcutAvailabilityChange = shouldSaveConfigurations
            && detectsShortcutAvailabilityChange
            && originalConfigurations.enabledPowerModeConfigurationIds != updatedConfigurations.enabledPowerModeConfigurationIds
    }

    public func applyRuntimeState(
        setConfigurations: ([PowerModeConfig]) -> Void,
        removeShortcutStorageForConfiguration: (UUID) -> Void,
        saveConfigurations: () -> Void,
        postShortcutAvailabilityDidChange: () -> Void
    ) {
        if let shortcutConfigurationIdToRemove {
            removeShortcutStorageForConfiguration(shortcutConfigurationIdToRemove)
        }

        if shouldApplyConfigurations {
            setConfigurations(updatedConfigurations)
        }

        guard shouldSaveConfigurations else { return }
        saveConfigurations()

        if shouldPostShortcutAvailabilityChange {
            postShortcutAvailabilityDidChange()
        }
    }

    public static func saving(
        _ config: PowerModeConfig,
        mode: VoiceInkPowerModeSaveMode,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.savePowerModeConfiguration(config, mode: mode)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldApplyConfigurations: didMutate || config.isDefault,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: true
        )
    }

    public static func removing(
        id: UUID,
        from configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.removePowerModeConfiguration(with: id)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shortcutConfigurationIdToRemove: id,
            shouldSaveConfigurations: true,
            detectsShortcutAvailabilityChange: true
        )
    }

    public static func updating(
        _ config: PowerModeConfig,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.updatePowerModeConfiguration(config)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: true
        )
    }

    public static func moving(
        fromOffsets offsets: IndexSet,
        toOffset: Int,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        updatedConfigurations.movePowerModeConfigurations(fromOffsets: offsets, toOffset: toOffset)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: updatedConfigurations != configurations,
            shouldSaveConfigurations: true,
            detectsShortcutAvailabilityChange: false
        )
    }

    public static func settingEnabled(
        id: UUID,
        isEnabled: Bool,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.setPowerModeConfiguration(id: id, isEnabled: isEnabled)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: true
        )
    }

    public static func addingAppConfig(
        _ appConfig: VoiceInkPowerModeAppConfig,
        toConfigurationID configID: UUID,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.addPowerModeAppConfig(appConfig, toConfigurationID: configID)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: false
        )
    }

    public static func removingAppConfig(
        id appConfigID: UUID,
        fromConfigurationID configID: UUID,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.removePowerModeAppConfig(id: appConfigID, fromConfigurationID: configID)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: false
        )
    }

    public static func addingURLConfig(
        _ urlConfig: VoiceInkPowerModeURLConfig,
        toConfigurationID configID: UUID,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.addPowerModeURLConfig(urlConfig, toConfigurationID: configID)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: false
        )
    }

    public static func removingURLConfig(
        id urlConfigID: UUID,
        fromConfigurationID configID: UUID,
        in configurations: [PowerModeConfig]
    ) -> Self {
        var updatedConfigurations = configurations
        let didMutate = updatedConfigurations.removePowerModeURLConfig(id: urlConfigID, fromConfigurationID: configID)
        return Self(
            originalConfigurations: configurations,
            updatedConfigurations: updatedConfigurations,
            didMutate: didMutate,
            shouldSaveConfigurations: didMutate,
            detectsShortcutAvailabilityChange: false
        )
    }
}

public extension Array where Element == PowerModeConfig {
    var powerModePolicyRules: [VoiceInkPowerModeRule] {
        map(\.powerModePolicyRule)
    }

    var enabledPowerModeConfigurations: [PowerModeConfig] {
        filter(\.isEnabled)
    }

    var hasEnabledPowerModeConfigurations: Bool {
        contains(where: \.isEnabled)
    }

    var enabledPowerModeConfigurationIds: Set<UUID> {
        Set(enabledPowerModeConfigurations.map(\.id))
    }

    func powerModeConfigurationForMiniRecorderShortcut(index: Int) -> PowerModeConfig? {
        let enabledConfigurations = enabledPowerModeConfigurations
        guard enabledConfigurations.indices.contains(index) else {
            return nil
        }

        return enabledConfigurations[index]
    }

    func powerModeShortcutEntries<ShortcutValue>(
        shortcutForConfiguration: (UUID) -> ShortcutValue?
    ) -> [(configuration: PowerModeConfig, shortcut: ShortcutValue)] {
        enabledPowerModeConfigurations.compactMap { configuration in
            shortcutForConfiguration(configuration.id).map { shortcut in
                (configuration, shortcut)
            }
        }
    }

    func powerModeShortcutConfigurationId(
        for id: UUID,
        shortcutExists: (UUID) -> Bool
    ) -> UUID? {
        guard let configuration = powerModeConfiguration(with: id),
              configuration.isEnabled,
              shortcutExists(configuration.id) else {
            return nil
        }

        return configuration.id
    }

    var hasPowerModeDefaultConfiguration: Bool {
        contains { $0.isDefault }
    }

    var hasEnabledAutomaticRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: powerModePolicyRules)
    }

    var hasEnabledURLRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: powerModePolicyRules)
    }

    func powerModeConfiguration(with id: UUID) -> PowerModeConfig? {
        first { $0.id == id }
    }

    func powerModeConfiguration(forWebsiteURL url: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: url,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    func powerModeConfiguration(forAppBundleIdentifier bundleIdentifier: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forAppBundleIdentifier: bundleIdentifier,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    var defaultPowerModeConfiguration: PowerModeConfig? {
        guard let defaultRule = VoiceInkPowerModePolicy.defaultRule(
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: defaultRule.id)
    }

    func resolvedPowerModeConfiguration(
        explicitID: UUID? = nil,
        websiteURL: String? = nil,
        appBundleIdentifier: String? = nil
    ) -> PowerModeConfig? {
        if let explicitID,
           let config = powerModeConfiguration(with: explicitID) {
            return config
        }

        guard websiteURL != nil || appBundleIdentifier != nil else {
            return nil
        }

        guard hasEnabledAutomaticRules else {
            return nil
        }

        if let websiteURL,
           let config = powerModeConfiguration(forWebsiteURL: websiteURL) {
            return config
        }

        if let appBundleIdentifier,
           let config = powerModeConfiguration(forAppBundleIdentifier: appBundleIdentifier) {
            return config
        }

        return defaultPowerModeConfiguration
    }

    func containsPowerModeEmoji(_ emoji: String) -> Bool {
        contains { $0.emoji == emoji }
    }

    @discardableResult
    mutating func appendPowerModeConfigurationIfMissing(_ config: PowerModeConfig) -> Bool {
        guard powerModeConfiguration(with: config.id) == nil else {
            return false
        }

        append(config)
        return true
    }

    @discardableResult
    mutating func updatePowerModeConfiguration(_ config: PowerModeConfig) -> Bool {
        guard let index = firstIndex(where: { $0.id == config.id }) else {
            return false
        }

        self[index] = config
        return true
    }

    @discardableResult
    mutating func savePowerModeConfiguration(
        _ config: PowerModeConfig,
        mode: VoiceInkPowerModeSaveMode
    ) -> Bool {
        if config.isDefault {
            setPowerModeDefaultConfiguration(id: config.id)
        }

        switch mode {
        case .add:
            return appendPowerModeConfigurationIfMissing(config)
        case .edit:
            return updatePowerModeConfiguration(config)
        }
    }

    @discardableResult
    mutating func removePowerModeConfiguration(with id: UUID) -> Bool {
        let originalCount = count
        removeAll { $0.id == id }
        return count != originalCount
    }

    mutating func movePowerModeConfigurations(fromOffsets offsets: IndexSet, toOffset: Int) {
        let validOffsets = offsets
            .filter { indices.contains($0) }
            .sorted()
        guard !validOffsets.isEmpty else { return }

        let configurationsToMove = validOffsets.map { self[$0] }
        for index in validOffsets.reversed() {
            remove(at: index)
        }

        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let insertionIndex = Swift.max(0, Swift.min(toOffset - removedBeforeDestination, count))
        insert(contentsOf: configurationsToMove, at: insertionIndex)
    }

    mutating func setPowerModeDefaultConfiguration(id configID: UUID) {
        for index in indices {
            self[index].isDefault = false
        }

        if let index = firstIndex(where: { $0.id == configID }) {
            self[index].isDefault = true
        }
    }

    @discardableResult
    mutating func setPowerModeConfiguration(id configID: UUID, isEnabled: Bool) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].isEnabled = isEnabled
        return true
    }

    @discardableResult
    mutating func addPowerModeAppConfig(
        _ appConfig: VoiceInkPowerModeAppConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].appConfigs ?? []
        configs.append(appConfig)
        self[index].appConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeAppConfig(
        id appConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].appConfigs?.removeAll { $0.id == appConfigID }
        return true
    }

    @discardableResult
    mutating func addPowerModeURLConfig(
        _ urlConfig: VoiceInkPowerModeURLConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].urlConfigs ?? []
        configs.append(urlConfig)
        self[index].urlConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeURLConfig(
        id urlConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].urlConfigs?.removeAll { $0.id == urlConfigID }
        return true
    }
}

public extension PowerModeConfig {
    var powerModePolicyRule: VoiceInkPowerModeRule {
        VoiceInkPowerModeRule(
            id: id,
            name: name,
            appRules: (appConfigs ?? []).map(\.rule),
            websiteRules: (urlConfigs ?? []).map(\.rule),
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }
}

public struct VoiceInkPowerModeAppConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var appName: String

    public init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    public static func == (lhs: VoiceInkPowerModeAppConfig, rhs: VoiceInkPowerModeAppConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeAppRule {
        VoiceInkPowerModeAppRule(bundleIdentifier: bundleIdentifier, appName: appName)
    }
}

public struct VoiceInkPowerModeAppRule: Equatable, Sendable {
    public let bundleIdentifier: String
    public let appName: String

    public init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}

public enum VoiceInkPowerModeAppPickerPolicy {
    public static func matchesSearch(
        appName: String,
        bundleIdentifier: String,
        searchText: String
    ) -> Bool {
        guard !searchText.isEmpty else { return true }

        return appName.localizedCaseInsensitiveContains(searchText)
            || bundleIdentifier.localizedCaseInsensitiveContains(searchText)
    }

    public static func filteredItems<Item>(
        _ items: [Item],
        searchText: String,
        appName: (Item) -> String,
        bundleIdentifier: (Item) -> String
    ) -> [Item] {
        guard !searchText.isEmpty else { return items }

        return items.filter {
            matchesSearch(
                appName: appName($0),
                bundleIdentifier: bundleIdentifier($0),
                searchText: searchText
            )
        }
    }
}

public extension Array where Element == VoiceInkPowerModeAppConfig {
    func containsPowerModeAppConfig(bundleIdentifier: String) -> Bool {
        contains { $0.bundleIdentifier == bundleIdentifier }
    }

    mutating func togglePowerModeAppConfig(bundleIdentifier: String, appName: String) {
        if let index = firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            remove(at: index)
        } else {
            append(VoiceInkPowerModeAppConfig(bundleIdentifier: bundleIdentifier, appName: appName))
        }
    }
}

public struct VoiceInkPowerModeURLConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: String

    public init(id: UUID = UUID(), url: String) {
        self.id = id
        self.url = url
    }

    public static func == (lhs: VoiceInkPowerModeURLConfig, rhs: VoiceInkPowerModeURLConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeWebsiteRule {
        VoiceInkPowerModeWebsiteRule(url: url)
    }
}

public struct VoiceInkPowerModeWebsiteRule: Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct VoiceInkPowerModeRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let appRules: [VoiceInkPowerModeAppRule]
    public let websiteRules: [VoiceInkPowerModeWebsiteRule]
    public let isEnabled: Bool
    public let isDefault: Bool

    public init(
        id: UUID,
        name: String,
        appRules: [VoiceInkPowerModeAppRule] = [],
        websiteRules: [VoiceInkPowerModeWebsiteRule] = [],
        isEnabled: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.appRules = appRules
        self.websiteRules = websiteRules
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}

public enum VoiceInkAutoSendKey: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case enter = "enter"
    case shiftEnter = "shiftEnter"
    case commandEnter = "commandEnter"

    public static let allCases: [VoiceInkAutoSendKey] = [
        .none,
        .enter,
        .shiftEnter,
        .commandEnter
    ]

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .enter:
            return "Return (⏎)"
        case .shiftEnter:
            return "Shift + Return (⇧⏎)"
        case .commandEnter:
            return "Command + Return (⌘⏎)"
        }
    }

    public var isEnabled: Bool {
        self != .none
    }
}

public enum VoiceInkAutoSendPolicy {
    public static let defaultDelayAfterPasteNanoseconds: UInt64 = 120_000_000

    public static func delayAfterPasteNanoseconds(for key: VoiceInkAutoSendKey) -> UInt64? {
        key.isEnabled ? defaultDelayAfterPasteNanoseconds : nil
    }
}

public enum VoiceInkPowerModeSaveMode: Equatable, Sendable {
    case add
    case edit(UUID)
}

public enum VoiceInkPowerModeConfigurationMode: Hashable, Sendable {
    case add
    case edit(PowerModeConfig)

    public var isAdding: Bool {
        if case .add = self {
            return true
        }
        return false
    }

    public var title: String {
        switch self {
        case .add:
            return "Add Power Mode"
        case .edit:
            return "Edit Power Mode"
        }
    }

    public var saveMode: VoiceInkPowerModeSaveMode {
        switch self {
        case .add:
            return .add
        case .edit(let config):
            return .edit(config.id)
        }
    }

    public func formState(
        existingConfigurations: [PowerModeConfig],
        newID: UUID = UUID(),
        selectedAIProvider: String? = VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
    ) -> VoiceInkPowerModeConfigurationFormState {
        switch self {
        case .add:
            return .adding(id: newID, selectedAIProvider: selectedAIProvider)
        case .edit(let config):
            return .editing(existingConfigurations.powerModeConfiguration(with: config.id) ?? config)
        }
    }

    public func appearPlan(
        enhancementSelection: VoiceInkPowerModeEnhancementSelection,
        isAIEnhancementEnabled: Bool,
        prompts: [VoiceInkCustomPrompt],
        currentAIProvider: VoiceInkAIEnhancementProviderKind,
        currentAIModel: String,
        transcriptionSelection: VoiceInkPowerModeTranscriptionSelection,
        selectedTranscriptionModelFacts: VoiceInkPowerModeTranscriptionModelFacts?,
        storedLanguage: String?
    ) -> VoiceInkPowerModeConfigurationFormAppearPlan {
        var nextEnhancementSelection = enhancementSelection

        if isAdding {
            nextEnhancementSelection = nextEnhancementSelection.fillingMissingProviderAndModel(
                currentProvider: currentAIProvider,
                currentModel: currentAIModel,
                treatsEmptyModelAsMissing: true
            )
        }

        nextEnhancementSelection = nextEnhancementSelection.selectingPromptForEnhancementState(
            isEnabled: isAIEnhancementEnabled,
            prompts: prompts
        )

        let nextTranscriptionSelection: VoiceInkPowerModeTranscriptionSelection?
        if let selectedTranscriptionModelFacts,
           selectedTranscriptionModelFacts.shouldRepairSelectedLanguageForPowerMode {
            nextTranscriptionSelection = transcriptionSelection.selectingCompatibleLanguage(
                for: selectedTranscriptionModelFacts,
                storedLanguage: storedLanguage
            )
        } else {
            nextTranscriptionSelection = nil
        }

        return VoiceInkPowerModeConfigurationFormAppearPlan(
            enhancementSelection: nextEnhancementSelection,
            transcriptionSelection: nextTranscriptionSelection
        )
    }

    public func dismissalPlan(
        didSaveConfiguration: Bool
    ) -> VoiceInkPowerModeConfigurationFormDismissalPlan {
        VoiceInkPowerModeConfigurationFormDismissalPlan(
            shouldRemoveUnsavedShortcut: isAdding && !didSaveConfiguration
        )
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }

    public static func == (
        lhs: VoiceInkPowerModeConfigurationMode,
        rhs: VoiceInkPowerModeConfigurationMode
    ) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

public struct VoiceInkPowerModeConfigurationFormDismissalPlan: Equatable, Sendable {
    public let shouldRemoveUnsavedShortcut: Bool

    public init(shouldRemoveUnsavedShortcut: Bool) {
        self.shouldRemoveUnsavedShortcut = shouldRemoveUnsavedShortcut
    }

    public func applyRuntimeState(
        removeUnsavedShortcut: () -> Void
    ) {
        guard shouldRemoveUnsavedShortcut else { return }
        removeUnsavedShortcut()
    }
}

public struct VoiceInkPowerModeConfigurationFormSavePlan: Equatable, Sendable {
    public let validationErrors: [VoiceInkPowerModeValidationError]
    private let configurationToSave: PowerModeConfig?
    private let saveMode: VoiceInkPowerModeSaveMode?

    init(
        validationErrors: [VoiceInkPowerModeValidationError],
        configurationToSave: PowerModeConfig?,
        saveMode: VoiceInkPowerModeSaveMode?
    ) {
        self.validationErrors = validationErrors
        self.configurationToSave = configurationToSave
        self.saveMode = saveMode
    }

    public func applyRuntimeState(
        setValidationErrors: ([VoiceInkPowerModeValidationError]) -> Void,
        showValidationAlert: () -> Void,
        saveConfiguration: (PowerModeConfig, VoiceInkPowerModeSaveMode) -> Void,
        markSaved: () -> Void,
        dismiss: () -> Void
    ) {
        setValidationErrors(validationErrors)

        if !validationErrors.isEmpty {
            showValidationAlert()
            return
        }

        guard let configurationToSave, let saveMode else { return }
        saveConfiguration(configurationToSave, saveMode)
        markSaved()
        dismiss()
    }
}

public enum VoiceInkPowerModeValidationError: Error, Equatable, Identifiable, Sendable {
    case emptyName
    case duplicateName(String)
    case duplicateAppTrigger(String, String)
    case duplicateWebsiteTrigger(String, String)

    public var id: String {
        switch self {
        case .emptyName:
            return "emptyName"
        case .duplicateName:
            return "duplicateName"
        case .duplicateAppTrigger:
            return "duplicateAppTrigger"
        case .duplicateWebsiteTrigger:
            return "duplicateWebsiteTrigger"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .emptyName:
            return "Power mode name cannot be empty."
        case .duplicateName(let name):
            return "A power mode with the name '\(name)' already exists."
        case .duplicateAppTrigger(let appName, let powerModeName):
            return "The app '\(appName)' is already configured in the '\(powerModeName)' power mode."
        case .duplicateWebsiteTrigger(let website, let powerModeName):
            return "The website '\(website)' is already configured in the '\(powerModeName)' power mode."
        }
    }
}

public enum VoiceInkPowerModePolicy {
    public static func powerModeBackupExportPlan(
        configurations: [PowerModeConfig],
        customEmojis: [String]
    ) -> VoiceInkPowerModeBackupExportPlan {
        VoiceInkPowerModeBackupExportPlan(
            configurationsToExport: configurations,
            shortcutRequests: configurations.map {
                VoiceInkPowerModeShortcutExportRequest(backupKey: $0.id.uuidString, id: $0.id)
            },
            customEmojisToExport: customEmojis
        )
    }

    fileprivate static func powerModeShortcutBackups<Backup>(
        for requests: [VoiceInkPowerModeShortcutExportRequest],
        backupForConfiguration: (UUID) -> Backup?
    ) -> [String: Backup]? {
        let backups = Dictionary(uniqueKeysWithValues: requests.compactMap { request -> (String, Backup)? in
            guard let backup = backupForConfiguration(request.id) else {
                return nil
            }

            return (request.backupKey, backup)
        })

        return backups.isEmpty ? nil : backups
    }

    public static func powerModeShortcutImports(
        backupKeys: [String],
        importedConfigurations: [PowerModeConfig]
    ) -> [VoiceInkPowerModeShortcutImport] {
        let importedConfigurationIds = Set(importedConfigurations.map(\.id))
        return backupKeys.compactMap { backupKey in
            guard let id = UUID(uuidString: backupKey),
                  importedConfigurationIds.contains(id) else {
                return nil
            }

            return VoiceInkPowerModeShortcutImport(backupKey: backupKey, id: id)
        }
    }

    public static func powerModeBackupImportPlan(
        existingConfigurations: [PowerModeConfig],
        importedConfigurations: [PowerModeConfig],
        backupShortcutKeys: [String],
        customEmojis: [String]?
    ) -> VoiceInkPowerModeBackupImportPlan {
        VoiceInkPowerModeBackupImportPlan(
            existingConfigurationIdsToClear: existingConfigurations.map(\.id),
            importedConfigurations: importedConfigurations,
            shortcutImports: powerModeShortcutImports(
                backupKeys: backupShortcutKeys,
                importedConfigurations: importedConfigurations
            ),
            hasCustomEmojiBackupRecord: customEmojis != nil,
            customEmojisToImport: customEmojis ?? []
        )
    }

    public static func normalizedWebsiteURL(_ url: String) -> String {
        url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func websiteConfigForFormInput(_ input: String) -> VoiceInkPowerModeURLConfig? {
        guard !input.isEmpty else { return nil }
        return VoiceInkPowerModeURLConfig(url: normalizedWebsiteURL(input))
    }

    public static func addingWebsiteConfig(
        forFormInput input: String,
        to existingConfigs: [VoiceInkPowerModeURLConfig]
    ) -> [VoiceInkPowerModeURLConfig]? {
        guard let websiteConfig = websiteConfigForFormInput(input) else { return nil }
        return existingConfigs + [websiteConfig]
    }

    public static func removingAppConfig(
        id: UUID,
        from existingConfigs: [VoiceInkPowerModeAppConfig]
    ) -> [VoiceInkPowerModeAppConfig] {
        existingConfigs.filter { $0.id != id }
    }

    public static func removingWebsiteConfig(
        id: UUID,
        from existingConfigs: [VoiceInkPowerModeURLConfig]
    ) -> [VoiceInkPowerModeURLConfig] {
        existingConfigs.filter { $0.id != id }
    }

    public static func canSaveConfigurationName(_ name: String) -> Bool {
        !name.isEmpty
    }

    public static func configuration(
        from draft: VoiceInkPowerModeConfigurationDraft,
        mode: VoiceInkPowerModeConfigurationMode
    ) -> PowerModeConfig {
        switch mode {
        case .add:
            return PowerModeConfig(
                id: draft.id,
                name: draft.name,
                emoji: draft.emoji,
                appConfigs: draft.appConfigs.isEmpty ? nil : draft.appConfigs,
                urlConfigs: draft.urlConfigs.isEmpty ? nil : draft.urlConfigs,
                isAIEnhancementEnabled: draft.isAIEnhancementEnabled,
                selectedPrompt: draft.selectedPromptId?.uuidString,
                selectedTranscriptionModelName: draft.selectedTranscriptionModelName,
                selectedLanguage: draft.selectedLanguage,
                useScreenCapture: draft.useScreenCapture,
                isTextFormattingEnabled: draft.isTextFormattingEnabled,
                punctuationCleanupMode: draft.punctuationCleanupMode,
                lowercaseTranscription: draft.lowercaseTranscription,
                selectedAIProvider: draft.selectedAIProvider,
                selectedAIModel: draft.selectedAIModel,
                autoSendKey: draft.autoSendKey,
                isDefault: draft.isDefault
            )
        case .edit(let config):
            var updatedConfig = config
            updatedConfig.name = draft.name
            updatedConfig.emoji = draft.emoji
            updatedConfig.isAIEnhancementEnabled = draft.isAIEnhancementEnabled
            updatedConfig.selectedPrompt = draft.selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = draft.selectedTranscriptionModelName
            updatedConfig.selectedLanguage = draft.selectedLanguage
            updatedConfig.isTextFormattingEnabled = draft.isTextFormattingEnabled
            updatedConfig.punctuationCleanupMode = draft.punctuationCleanupMode
            updatedConfig.lowercaseTranscription = draft.lowercaseTranscription
            updatedConfig.appConfigs = draft.appConfigs.isEmpty ? nil : draft.appConfigs
            updatedConfig.urlConfigs = draft.urlConfigs.isEmpty ? nil : draft.urlConfigs
            updatedConfig.useScreenCapture = draft.useScreenCapture
            updatedConfig.autoSendKey = draft.autoSendKey
            updatedConfig.selectedAIProvider = draft.selectedAIProvider
            updatedConfig.selectedAIModel = draft.selectedAIModel
            updatedConfig.isDefault = draft.isDefault
            return updatedConfig
        }
    }

    public static func formSavePlan(
        draft: VoiceInkPowerModeConfigurationDraft,
        mode: VoiceInkPowerModeConfigurationMode,
        existing rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeConfigurationFormSavePlan {
        let config = configuration(from: draft, mode: mode)
        let validationErrors = validateForSave(
            candidate: config.powerModePolicyRule,
            mode: mode.saveMode,
            existing: rules
        )

        return VoiceInkPowerModeConfigurationFormSavePlan(
            validationErrors: validationErrors,
            configurationToSave: validationErrors.isEmpty ? config : nil,
            saveMode: validationErrors.isEmpty ? mode.saveMode : nil
        )
    }

    public static func hasEnabledAutomaticRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && (
                rule.isDefault ||
                !rule.appRules.isEmpty ||
                !rule.websiteRules.isEmpty
            )
        }
    }

    public static func hasEnabledWebsiteRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && !rule.websiteRules.isEmpty
        }
    }

    public static func matchingRule(
        forWebsiteURL url: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        let normalizedURL = normalizedWebsiteURL(url)

        for rule in rules where rule.isEnabled {
            for websiteRule in rule.websiteRules {
                let normalizedRuleURL = normalizedWebsiteURL(websiteRule.url)
                if normalizedURL.contains(normalizedRuleURL) {
                    return rule
                }
            }
        }

        return nil
    }

    public static func matchingRule(
        forAppBundleIdentifier bundleIdentifier: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.appRules.contains { appRule in
                appRule.bundleIdentifier == bundleIdentifier
            }
        }
    }

    public static func defaultRule(in rules: [VoiceInkPowerModeRule]) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.isDefault
        }
    }

    public static func validateForSave(
        candidate: VoiceInkPowerModeRule,
        mode: VoiceInkPowerModeSaveMode,
        existing rules: [VoiceInkPowerModeRule]
    ) -> [VoiceInkPowerModeValidationError] {
        var errors: [VoiceInkPowerModeValidationError] = []

        if candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        let comparableRules = rules.filter { rule in
            switch mode {
            case .add:
                return true
            case .edit(let editedID):
                return rule.id != editedID
            }
        }

        if comparableRules.contains(where: { $0.name == candidate.name }) {
            errors.append(.duplicateName(candidate.name))
        }

        for appRule in candidate.appRules {
            for existingRule in comparableRules {
                if existingRule.appRules.contains(where: { $0.bundleIdentifier == appRule.bundleIdentifier }) {
                    errors.append(.duplicateAppTrigger(appRule.appName, existingRule.name))
                }
            }
        }

        for websiteRule in candidate.websiteRules {
            for existingRule in comparableRules {
                if existingRule.websiteRules.contains(where: { $0.url == websiteRule.url }) {
                    errors.append(.duplicateWebsiteTrigger(websiteRule.url, existingRule.name))
                }
            }
        }

        return errors
    }
}
