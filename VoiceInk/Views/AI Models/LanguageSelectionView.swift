import SwiftUI
import VoiceInkCore

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager
    @AppStorage(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    private var preferredLanguage = VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
    @State private var settingsRevision = 0
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full

    private var selectedLanguage: String {
        languageSelectionFacts?.compatibleLanguage(preferredLanguage) ?? preferredLanguage
    }

    private func updateLanguage(_ language: String) {
        guard preferredLanguage != language else { return }

        // Update UI state - the UserDefaults updating is now automatic with @AppStorage
        preferredLanguage = language

        VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage()
        UserDefaults.standard.synchronize()

        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private var languageSelectionFacts: VoiceInkTranscriptionLanguageSelectionFacts? {
        _ = settingsRevision
        return transcriptionModelManager.currentTranscriptionModel?.transcriptionLanguageSelectionFacts
    }

    private var nativeAppleAssetControl: some View {
        NativeAppleLanguageAssetControl(
            localeIdentifier: selectedLanguage,
            isVisible: true
        )
        .layoutPriority(1)
    }

    private var englishOnlyMenuButton: some View {
        Button {
            // Do nothing, just showing info
        } label: {
            Text(VoiceInkTranscriptionLanguagePresentation.englishOnlyMenuLabel)
                .foregroundColor(.secondary)
        }
        .disabled(true)
    }

    var body: some View {
        Group {
            switch displayMode {
            case .full:
                fullView
            case .menuItem:
                menuItemView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AppSettingsDidChange)) { _ in
            settingsRevision &+= 1
        }
    }

    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageSelectionSection
        }
    }
    
    private var languageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(VoiceInkTranscriptionLanguagePresentation.sectionTitle)
                .font(.headline)

            if let facts = languageSelectionFacts {
                if facts.shouldShowDisabledAutodetectControl {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedLabel)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                } else if facts.shouldShowPicker {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker(
                                VoiceInkTranscriptionLanguagePresentation.menuPickerTitle,
                                selection: Binding(
                                    get: { selectedLanguage },
                                    set: { updateLanguage($0) }
                                )
                            ) {
                                ForEach(
                                    VoiceInkLanguageCatalog.sortedOptions(facts.languageOptions)
                                ) { option in
                                    Text(option.name).tag(option.code)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: facts.showsNativeAppleAssetControl ? 280 : .infinity, alignment: .leading)

                            if facts.showsNativeAppleAssetControl {
                                nativeAppleAssetControl
                            }
                        }

                        Text(
                            VoiceInkTranscriptionLanguagePresentation.multilingualDescription
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } else if facts.shouldShowDefaultLanguageOnly {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VoiceInkTranscriptionLanguagePresentation.englishOnlyLabel)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(
                            VoiceInkTranscriptionLanguagePresentation.englishOnlyDescription
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(VoiceInkModelManagementPresentation.noModelSelectedText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if let facts = languageSelectionFacts {
                if facts.shouldShowDisabledAutodetectControl {
                    Button {
                        // Do nothing, just showing info
                    } label: {
                        Text(VoiceInkTranscriptionLanguagePresentation.autoDetectedLabel)
                            .foregroundColor(.secondary)
                    }
                    .disabled(true)
                } else if facts.shouldShowPicker {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(
                                VoiceInkLanguageCatalog.sortedOptions(facts.languageOptions)
                            ) { option in
                                Button {
                                    updateLanguage(option.code)
                                } label: {
                                    HStack {
                                        Text(option.name)
                                        if selectedLanguage == option.code {
                                            Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(
                                    VoiceInkTranscriptionLanguagePresentation.menuLabel(
                                        selectedLanguage: selectedLanguage,
                                        languages: facts.languageOptions
                                    )
                                )
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                                    .font(.system(size: 10))
                            }
                        }

                        if facts.showsNativeAppleAssetControl {
                            nativeAppleAssetControl
                        }
                    }
                } else if facts.shouldShowDefaultLanguageOnly {
                    englishOnlyMenuButton
                }
            } else {
                englishOnlyMenuButton
            }
        }
    }
}
