import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var whisperPrompt: WhisperPrompt
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("IsTextFormattingEnabled") private var isTextFormattingEnabled = true
    @AppStorage(PunctuationCleanupMode.userDefaultsKey) private var punctuationCleanupModeRaw = PunctuationCleanupMode.current().rawValue
    @AppStorage("LowercaseTranscription") private var lowercaseTranscription = false
    @AppStorage("IsVADEnabled") private var isVADEnabled = true
    @AppStorage("AppendTrailingSpace") private var appendTrailingSpace = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = true
    @AppStorage("showLiveTextPreview") private var showLiveTextPreview = false
    @AppStorage(LiveTranscriptionSettings.modeKey) private var liveTranscriptionModeRaw = LiveTranscriptionSettings.defaultMode.rawValue
    @AppStorage(LiveTranscriptionSettings.autoDisableCloudModelsKey) private var autoDisableCloudModels = LiveTranscriptionSettings.defaultAutoDisablesCloudModels
    @AppStorage(LiveTranscriptionSettings.autoDisableLowBatteryLocalModelsKey) private var autoDisableLowBatteryLocalModels = LiveTranscriptionSettings.defaultAutoDisablesLowBatteryLocalModels
    @AppStorage(LiveTranscriptionSettings.lowBatteryThresholdPercentKey) private var lowBatteryThresholdPercent = LiveTranscriptionSettings.defaultLowBatteryThresholdPercent
    @State private var customPrompt: String = ""
    @State private var isEditing: Bool = false

    private var punctuationCleanupMode: Binding<PunctuationCleanupMode> {
        Binding(
            get: {
                PunctuationCleanupMode(rawValue: punctuationCleanupModeRaw) ?? PunctuationCleanupMode.current()
            },
            set: { newMode in
                punctuationCleanupModeRaw = newMode.rawValue
                PunctuationCleanupMode.setCurrent(newMode)
            }
        )
    }

    private var liveTranscriptionMode: Binding<LiveTranscriptionMode> {
        Binding(
            get: {
                LiveTranscriptionMode(rawValue: liveTranscriptionModeRaw) ?? LiveTranscriptionSettings.defaultMode
            },
            set: { newMode in
                liveTranscriptionModeRaw = newMode.rawValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        TextEditor(text: $customPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 40, maxHeight: 80)
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)

                        Button("Save") {
                            whisperPrompt.setCustomPrompt(customPrompt, for: selectedLanguage)
                            isEditing = false
                        }
                    } else {
                        Text(whisperPrompt.getLanguagePrompt(for: selectedLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") {
                            customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
                            isEditing = true
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Output Format")
                    InfoTip(
                        "Only supported for local Whisper models. Unlike GPT, Voice Models(whisper) follows the style of your prompt rather than instructions. Use examples of your desired output format instead of commands.",
                        learnMoreURL: "https://cookbook.openai.com/examples/whisper_prompting_guide#comparison-with-gpt-prompting"
                    )
                }
            }

            Section {
                Toggle(isOn: $isTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text("Paragraph breaks")
                        InfoTip("Apply intelligent text formatting to break large block of text into paragraphs.")
                    }
                }
                .toggleStyle(.switch)

                Picker(selection: punctuationCleanupMode) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Punctuation")
                        InfoTip("Keep preserves punctuation as transcribed. Remove all strips punctuation marks from the transcribed text. Remove trailing period only removes a final period from the transcribed text.")
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: $lowercaseTranscription) {
                    HStack(spacing: 4) {
                        Text("Lowercase output")
                        InfoTip("Convert transcription output to lowercase.")
                    }
                }
                .toggleStyle(.switch)

                FillerWordsSettingsView()
            } header: {
                Text("Transcript Formatting")
            }

            Section {
                Toggle(isOn: $appendTrailingSpace) {
                    HStack(spacing: 4) {
                        Text("Add Space After Paste")
                        InfoTip("Add a trailing space after pasted transcription output.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isVADEnabled) {
                    HStack(spacing: 4) {
                        Text("Voice Activity Detection (VAD)")
                        InfoTip("Detect speech segments and filter out silence before transcription work. Also gates real-time chunks with the local Silero model when available.")
                    }
                }
                .toggleStyle(.switch)

                Picker(selection: liveTranscriptionMode) {
                    ForEach(LiveTranscriptionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Real-time Transcription")
                        InfoTip("Start processing audio while recording. Per-model Real-time switches can still disable specific models.")
                    }
                }
                .pickerStyle(.segmented)

                if liveTranscriptionMode.wrappedValue == .auto {
                    Toggle(isOn: $autoDisableCloudModels) {
                        HStack(spacing: 4) {
                            Text("Auto: Disable Cloud Models")
                            InfoTip("When enabled, Auto uses batch mode for cloud transcription models that have a batch endpoint.")
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $autoDisableLowBatteryLocalModels) {
                        HStack(spacing: 4) {
                            Text("Auto: Disable Local Models on Low Battery")
                            InfoTip("When enabled, Auto uses batch mode for local models while running on battery below the cutoff.")
                        }
                    }
                    .toggleStyle(.switch)

                    if autoDisableLowBatteryLocalModels {
                        Stepper(
                            "Battery cutoff: \(lowBatteryThresholdPercent)%",
                            value: $lowBatteryThresholdPercent,
                            in: 1...100,
                            step: 5
                        )
                    }
                }

                Toggle(isOn: $prewarmModelOnWake) {
                    HStack(spacing: 4) {
                        Text("Prewarm model (Experimental)")
                        InfoTip("Turn this on if transcriptions with local models are taking longer than expected. Runs silent background transcription on app launch and wake to trigger optimization.")
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $showLiveTextPreview) {
                    HStack(spacing: 4) {
                        Text("Show Live Text Preview")
                        InfoTip("Displays the live transcript preview in the recorder while speaking. Only applies when real-time transcription is active.")
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedLanguage) { oldValue, newValue in
            if isEditing {
                customPrompt = whisperPrompt.getLanguagePrompt(for: selectedLanguage)
            }
        }
    }
}
