import SwiftUI
import VoiceInkCore

struct ModelSettingsView: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var preferredLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    @AppStorage(VoiceInkVADPreference.userDefaultsKey)
    private var isVADEnabled = VoiceInkVADPreference.defaultIsEnabled
    @AppStorage(VoiceInkAppendTrailingSpacePreference.userDefaultsKey)
    private var appendTrailingSpace = VoiceInkAppendTrailingSpacePreference.defaultIsEnabled
    @AppStorage(VoiceInkModelRuntimePreference.userDefaultsKey)
    private var prewarmModelOnWake = VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake
    @AppStorage(VoiceInkRecorderPreviewPreference.userDefaultsKey)
    private var showLiveTextPreview = VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled
    @State private var promptDraftState = VoiceInkLocalWhisperPromptDraftState()
    @State private var cleanupSettingsRevision = 0
    private let advancedSettingsPresentation = VoiceInkMacOSAdvancedTranscriptionSettingsPresentation.macOS
    private let appendTrailingSpacePresentation = VoiceInkAppendTrailingSpacePreference.macOSSettingsPresentation
    private let cleanupPresentation = VoiceInkTranscriptionCleanupPresentation.macOS
    private let localWhisperPromptPresentation = VoiceInkLocalWhisperPromptCatalog.macOSSettingsPresentation

    private var selectedLanguage: String {
        transcriptionModelManager.currentTranscriptionModel?.transcriptionLanguageSelectionFacts
            .compatibleLanguage(preferredLanguage) ?? preferredLanguage
    }

    private func languagePrompt(for language: String) -> String {
        VoiceInkLocalWhisperPromptCatalog.prompt(
            for: language,
            customPrompts: VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts()
        )
    }

    private func saveCustomPrompt(_ prompt: String, for language: String) {
        VoiceInkTranscriptionPromptPreference.saveLocalWhisperCustomPrompt(prompt, for: language)
        UserDefaults.standard.synchronize()
    }

    private var currentCleanupSettings: VoiceInkTranscriptionCleanupSettings {
        _ = cleanupSettingsRevision
        return VoiceInkTranscriptionCleanupSettings.current()
    }

    private func cleanupBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<VoiceInkTranscriptionCleanupSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentCleanupSettings[keyPath: keyPath] },
            set: { newValue in
                let previousSettings = VoiceInkTranscriptionCleanupSettings.current()
                guard previousSettings[keyPath: keyPath] != newValue else { return }

                let updatedSettings = previousSettings.updating(keyPath, to: newValue)
                updatedSettings.saveChangedValues(from: previousSettings)
                cleanupSettingsRevision &+= 1
            }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if promptDraftState.isEditing {
                        TextEditor(text: $promptDraftState.text)
                            .font(.system(size: 12))
                            .frame(minHeight: 40, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)

                        Button(localWhisperPromptPresentation.saveButtonTitle) {
                            saveCustomPrompt(promptDraftState.text, for: selectedLanguage)
                            promptDraftState = promptDraftState.saved()
                        }
                    } else {
                        Text(languagePrompt(for: selectedLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(localWhisperPromptPresentation.editButtonTitle) {
                            promptDraftState = promptDraftState.editing(
                                prompt: languagePrompt(for: selectedLanguage)
                            )
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text(localWhisperPromptPresentation.sectionTitle)
                    InfoTip(
                        localWhisperPromptPresentation.helpText,
                        learnMoreURL: localWhisperPromptPresentation.learnMoreURLString
                    )
                }
            }

            Section {
                Toggle(isOn: cleanupBinding(\.isTextFormattingEnabled)) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.paragraphBreaksToggleTitle)
                        if let helpText = cleanupPresentation.paragraphBreaksHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                Picker(selection: cleanupBinding(\.punctuationMode)) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.punctuationPickerTitle)
                        if let helpText = cleanupPresentation.punctuationHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: cleanupBinding(\.lowercaseTranscription)) {
                    HStack(spacing: 4) {
                        Text(cleanupPresentation.lowercaseToggleTitle)
                        if let helpText = cleanupPresentation.lowercaseHelpText {
                            InfoTip(helpText)
                        }
                    }
                }
                .toggleStyle(.switch)

                FillerWordsSettingsView(removeFillerWords: cleanupBinding(\.removeFillerWords))
            } header: {
                Text(cleanupPresentation.sectionTitle)
            }

            Section {
                Toggle(isOn: $appendTrailingSpace) {
                    HStack(spacing: 4) {
                        Text(appendTrailingSpacePresentation.toggleTitle)
                        InfoTip(appendTrailingSpacePresentation.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isVADEnabled) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.vad.title)
                        InfoTip(advancedSettingsPresentation.vad.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $prewarmModelOnWake) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.modelPrewarm.title)
                        InfoTip(advancedSettingsPresentation.modelPrewarm.helpText)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $showLiveTextPreview) {
                    HStack(spacing: 4) {
                        Text(advancedSettingsPresentation.liveTextPreview.title)
                        InfoTip(advancedSettingsPresentation.liveTextPreview.helpText)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text(advancedSettingsPresentation.sectionTitle)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedLanguage) { _, _ in
            promptDraftState = promptDraftState.refreshingForSelectedLanguage(
                prompt: languagePrompt(for: selectedLanguage)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            cleanupSettingsRevision &+= 1
        }
    }
}
