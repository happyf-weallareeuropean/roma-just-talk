import SwiftUI
import Cocoa
import Carbon.HIToolbox
import AVFoundation
import VoiceInkCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage(VoiceInkUserDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true
    @AppStorage(VoiceInkAnnouncementPreference.isEnabledKey) private var enableAnnouncements = VoiceInkAnnouncementPreference.defaultIsEnabled
    @AppStorage(VoiceInkPastePreference.restoreClipboardAfterPasteKey) private var restoreClipboardAfterPaste = VoiceInkPastePreference.defaultRestoreClipboardAfterPaste
    @AppStorage(VoiceInkPastePreference.clipboardRestoreDelayKey) private var clipboardRestoreDelay = VoiceInkPastePreference.defaultClipboardRestoreDelay
    @AppStorage(VoiceInkPasteMethod.userDefaultsKey) private var pasteMethodRawValue = VoiceInkPasteMethod.current().rawValue
    @AppStorage(VoiceInkMenuBarPreference.showMenuBarIconKey) private var showMenuBarIcon = VoiceInkMenuBarPreference.defaultShowMenuBarIcon
    @State private var showResetOnboardingAlert = false
    @State private var hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelRecordingShortcutRecorderResetID = 0

    // Expansion states - all collapsed by default
    @State private var isMiddleClickExpanded = false
    @State private var isSoundFeedbackExpanded = false
    @State private var isRestoreClipboardExpanded = false
    private static let recordingShortcutPresentation = VoiceInkRecordingShortcutPreference.macOSSettingsPresentation
    private static let recorderStylePresentation = VoiceInkRecorderStylePreference.macOSSettingsPresentation
    private static let recordingFeedbackPresentation = VoiceInkRecordingFeedbackPreference.macOSSettingsPresentation
    private static let pasteSettingsPresentation = VoiceInkPastePreference.macOSSettingsPresentation
    private static let resetOnboardingPresentation = VoiceInkMacOSOnboardingPresentation.resetSettingsAlert
    private static let settingsPresentation = VoiceInkMacOSSettingsPresentation.macOS

    private var pasteMethod: Binding<VoiceInkPasteMethod> {
        Binding(
            get: {
                VoiceInkPasteMethod.selection(fromStoredRawValue: pasteMethodRawValue)
            },
            set: { newMethod in
                pasteMethodRawValue = newMethod.rawValue
                VoiceInkPasteMethod.setCurrent(newMethod)
            }
        )
    }

    var body: some View {
        Form {
            // MARK: - Shortcuts
            Section {
                LabeledContent(Self.recordingShortcutPresentation.primaryShortcutLabel) {
                    HStack(spacing: 8) {
                        Spacer()
                        shortcutModePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                        ShortcutRecorder(action: .primaryRecording) {
                            recordingShortcutManager.primaryRecordingShortcut = .custom
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    }
                }

                if recordingShortcutManager.secondaryRecordingShortcut != .none {
                    LabeledContent(Self.recordingShortcutPresentation.secondaryShortcutLabel) {
                        HStack(spacing: 8) {
                            Spacer()
                            shortcutModePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
                            ShortcutRecorder(action: .secondaryRecording) {
                                recordingShortcutManager.secondaryRecordingShortcut = .custom
                                recordingShortcutManager.updateShortcutStatus()
                            }
                            .controlSize(.small)
                            Button {
                                withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .none }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if recordingShortcutManager.secondaryRecordingShortcut == .none {
                    Button(Self.recordingShortcutPresentation.addSecondaryShortcutButtonTitle) {
                        withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                    }
                }

                if usesSpecialShortcutMode {
                    Toggle(
                        Self.recordingShortcutPresentation.emptyTapPasteLastTranscriptLabel,
                        isOn: $recordingShortcutManager.specialShortcutPasteLastTranscriptOnEmptyTap
                    )
                }
            } header: {
                Text(Self.recordingShortcutPresentation.sectionTitle)
            }

            // MARK: - Additional Shortcuts
            Section(Self.recordingShortcutPresentation.additionalSectionTitle) {
                LabeledContent(Self.recordingShortcutPresentation.pasteLastTranscriptionOriginalLabel) {
                    ShortcutRecorder(action: .pasteLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent(Self.recordingShortcutPresentation.pasteLastTranscriptionEnhancedLabel) {
                    ShortcutRecorder(action: .pasteLastEnhancement) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent(Self.recordingShortcutPresentation.retryLastTranscriptionLabel) {
                    ShortcutRecorder(action: .retryLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent(Self.recordingShortcutPresentation.cancelRecordingLabel) {
                    HStack(spacing: 8) {
                        ShortcutRecorder(
                            action: .cancelRecorder,
                            defaultShortcut: Self.defaultCancelRecordingShortcut
                        ) {
                            hasCancelRecordingShortcut = true
                        }
                            .id(cancelRecordingShortcutRecorderResetID)
                            .controlSize(.small)

                        Button {
                            ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                            hasCancelRecordingShortcut = false
                            cancelRecordingShortcutRecorderResetID += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .help(Self.recordingShortcutPresentation.resetToDefaultHelp)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
                    guard let action = notification.object as? ShortcutAction, action == .cancelRecorder else { return }
                    hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
                }

                // Middle-Click
                ExpandableSettingsRow(
                    isExpanded: $isMiddleClickExpanded,
                    isEnabled: $recordingShortcutManager.isMiddleClickToggleEnabled,
                    label: Self.recordingShortcutPresentation.middleClickRecordingLabel
                ) {
                    LabeledContent(Self.recordingShortcutPresentation.activationDelayLabel) {
                        HStack {
                            TextField(
                                "",
                                value: $recordingShortcutManager.middleClickActivationDelay,
                                formatter: VoiceInkRecordingShortcutPreference.middleClickActivationDelayFormatter()
                            )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text(Self.recordingShortcutPresentation.activationDelayUnitLabel)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: - Recording Feedback
            Section(Self.recordingFeedbackPresentation.sectionTitle) {
                // Sound Feedback
                ExpandableSettingsRow(
                    isExpanded: $isSoundFeedbackExpanded,
                    isEnabled: $soundManager.isEnabled,
                    label: Self.recordingFeedbackPresentation.soundFeedbackLabel
                ) {
                    CustomSoundSettingsView()
                }

                Picker(Self.recordingFeedbackPresentation.systemMuteModeLabel, selection: $mediaController.systemMuteMode) {
                    ForEach(VoiceInkSystemMuteMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if mediaController.systemMuteMode != .never {
                    Picker(Self.recordingFeedbackPresentation.audioResumptionDelayLabel, selection: $mediaController.audioResumptionDelay) {
                        ForEach(Self.recordingFeedbackPresentation.audioResumptionDelayOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                }

                // Keep Clipboard Content
                ExpandableSettingsRow(
                    isExpanded: $isRestoreClipboardExpanded,
                    isEnabled: $restoreClipboardAfterPaste,
                    label: Self.pasteSettingsPresentation.keepClipboardContentLabel,
                    infoMessage: Self.pasteSettingsPresentation.keepClipboardContentInfoMessage
                ) {
                    Picker(Self.pasteSettingsPresentation.restoreDelayLabel, selection: $clipboardRestoreDelay) {
                        ForEach(Self.pasteSettingsPresentation.restoreDelayOptions) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                }

                // Paste Method
                Picker(selection: pasteMethod) {
                    ForEach(VoiceInkPasteMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.pasteSettingsPresentation.pasteMethodLabel)
                        InfoTip(Self.pasteSettingsPresentation.pasteMethodHelpMessage)
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: - Power Mode
            PowerModeSection()

            // MARK: - Interface
            Section(Self.recorderStylePresentation.sectionTitle) {
                Picker(Self.recorderStylePresentation.pickerTitle, selection: $recorderUIManager.recorderType) {
                    ForEach(VoiceInkRecorderStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)

            }

            // MARK: - Experimental
            ExperimentalSection()

            // MARK: - General
            Section(Self.settingsPresentation.generalSectionTitle) {
                IconVisibilityToggle(
                    title: Self.settingsPresentation.menuBarTitle,
                    isVisible: $showMenuBarIcon
                )

                IconVisibilityToggle(
                    title: Self.settingsPresentation.dockIconTitle,
                    isVisible: $menuBarManager.showDockIcon
                )

                Toggle(
                    Self.settingsPresentation.launchAtLoginTitle,
                    isOn: $launchAtLoginController.isEnabled
                )

                Toggle(VoiceInkUpdatePresentation.automaticUpdatesTitle, isOn: Binding(
                    get: { updaterViewModel.automaticUpdatesEnabled },
                    set: { updaterViewModel.setAutomaticUpdatesEnabled($0) }
                ))

                Picker(VoiceInkUpdatePresentation.trackTitle, selection: Binding(
                    get: { updaterViewModel.track },
                    set: { updaterViewModel.setTrack($0) }
                )) {
                    ForEach(VoiceInkUpdateTrack.allCases) { track in
                        Text(track.title).tag(track)
                    }
                }

                Toggle(Self.settingsPresentation.showAnnouncementsTitle, isOn: $enableAnnouncements)
                    .onChange(of: enableAnnouncements) { _, newValue in
                        if newValue {
                            AnnouncementsService.shared.start()
                        } else {
                            AnnouncementsService.shared.stop()
                        }
                    }

                HStack {
                    Button(VoiceInkUpdatePresentation.checkNowTitle) {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Link(
                        VoiceInkUpdatePresentation.releaseHistoryTitle,
                        destination: VoiceInkUpdatePreference.releaseHistoryURL
                    )

                    Button(Self.resetOnboardingPresentation.buttonTitle) {
                        showResetOnboardingAlert = true
                    }
                }
            }

            // MARK: - Privacy
            Section {
                AudioCleanupSettingsView()
            } header: {
                Text(Self.settingsPresentation.privacySectionTitle)
            } footer: {
                Text(Self.settingsPresentation.privacyFooterText)
            }

            // MARK: - Backup
            Section {
                LabeledContent(Self.settingsPresentation.exportSettingsLabel) {
                    Button(Self.settingsPresentation.exportButtonTitle) {
                        ImportExportService.shared.exportSettings(
                            enhancementService: enhancementService,
                            recordingShortcutManager: recordingShortcutManager,
                            menuBarManager: menuBarManager,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            soundManager: soundManager,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext
                        )
                    }
                }

                LabeledContent(Self.settingsPresentation.importSettingsLabel) {
                    Button(Self.settingsPresentation.importButtonTitle) {
                        ImportExportService.shared.importSettings(
                            enhancementService: enhancementService,
                            recordingShortcutManager: recordingShortcutManager,
                            menuBarManager: menuBarManager,
                            launchAtLoginController: launchAtLoginController,
                            mediaController: mediaController,
                            playbackController: playbackController,
                            soundManager: soundManager,
                            recorderUIManager: recorderUIManager,
                            modelContext: modelContext,
                            transcriptionModelManager: transcriptionModelManager
                        )
                    }
                }
            } header: {
                Text(Self.settingsPresentation.backupSectionTitle)
            } footer: {
                Text(Self.settingsPresentation.backupFooterText)
            }

            // MARK: - Diagnostics
            Section(Self.settingsPresentation.diagnosticsSectionTitle) {
                DiagnosticsSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(Self.resetOnboardingPresentation.alertTitle, isPresented: $showResetOnboardingAlert) {
            Button(Self.resetOnboardingPresentation.cancelButtonTitle, role: .cancel) { }
            Button(Self.resetOnboardingPresentation.confirmButtonTitle, role: .destructive) {
                DispatchQueue.main.async {
                    VoiceInkMacOSOnboardingProgressStore.reset()
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text(Self.resetOnboardingPresentation.message)
        }
    }

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    private var usesSpecialShortcutMode: Bool {
        recordingShortcutManager.primaryRecordingShortcutMode == .special ||
        (
            recordingShortcutManager.secondaryRecordingShortcut != .none &&
            recordingShortcutManager.secondaryRecordingShortcutMode == .special
        )
    }

    @ViewBuilder
    private func shortcutModePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
        Picker("", selection: binding) {
            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

struct IconVisibilityToggle: View {
    let title: String
    @Binding var isVisible: Bool

    var body: some View {
        Toggle(title, isOn: $isVisible)
            .toggleStyle(
                VisibilityToggleStyle(presentation: VoiceInkMacOSSettingsPresentation.macOS)
            )
    }
}

private struct VisibilityToggleStyle: ToggleStyle {
    let presentation: VoiceInkMacOSSettingsPresentation
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor : hiddenTrackColor)

                    Text(presentation.visibilityValueTitle(isVisible: configuration.isOn))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .frame(width: 48, height: 22)
                        .background {
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    Capsule()
                                        .stroke(thumbBorderColor, lineWidth: thumbBorderWidth)
                                }
                                .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
                        }
                        .padding(2)
                }
                .frame(width: 78, height: 26)
                .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(
                isOn: Binding(
                    get: { configuration.isOn },
                    set: { configuration.isOn = $0 }
                )
            ) {
                configuration.label
            }
            .accessibilityValue(
                Text(presentation.visibilityValueTitle(isVisible: configuration.isOn))
            )
        }
    }

    private var hiddenTrackColor: Color {
        Color.secondary.opacity(colorSchemeContrast == .increased ? 0.55 : 0.3)
    }

    private var thumbBorderColor: Color {
        Color.primary.opacity(colorSchemeContrast == .increased ? 0.4 : 0.08)
    }

    private var thumbBorderWidth: CGFloat {
        colorSchemeContrast == .increased ? 1 : 0.5
    }
}

// MARK: - Expandable Settings Row (entire row clickable)

struct ExpandableSettingsRow<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool
    let label: String
    var infoMessage: String? = nil
    var infoURL: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isHandlingToggleChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row - entire area is tappable
            HStack {
                Toggle(isOn: $isEnabled) {
                    HStack(spacing: 4) {
                        Text(label)
                        if let message = infoMessage {
                            if let url = infoURL {
                                InfoTip(message, learnMoreURL: url)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isEnabled && isExpanded ? 90 : 0))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHandlingToggleChange else { return }
                if isEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Expanded content with proper spacing
            if isEnabled && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.top, 12)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: isEnabled) { _, newValue in
            isHandlingToggleChange = true
            if newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isHandlingToggleChange = false
            }
        }
    }
}

// MARK: - Power Mode Section

struct PowerModeSection: View {
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @AppStorage(VoiceInkUserDefaultsKey.powerModeUIFlag) private var powerModeUIFlag = VoiceInkPreferenceDefault.powerModeUIEnabled
    @AppStorage(VoiceInkUserDefaultsKey.powerModePersistConfig) private var powerModePersistSettings = VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences
    @State private var showDisableAlert = false
    @State private var isExpanded = false

    var body: some View {
        Section {
            ExpandableSettingsRow(
                isExpanded: $isExpanded,
                isEnabled: toggleBinding,
                label: VoiceInkPowerModePresentation.settingsSectionTitle,
                infoMessage: VoiceInkPowerModePresentation.settingsToggleHelpText,
                infoURL: VoiceInkPowerModePresentation.panelLearnMoreURLString
            ) {
                Toggle(isOn: $powerModePersistSettings) {
                    HStack(spacing: 4) {
                        Text(VoiceInkPowerModePresentation.persistConfiguredPreferencesTitle)
                        InfoTip(VoiceInkPowerModePresentation.persistConfiguredPreferencesHelpText)
                    }
                }
            }
        } header: {
            Text(VoiceInkPowerModePresentation.settingsSectionTitle)
        }
        .alert(VoiceInkPowerModePresentation.settingsDisableAlertTitle, isPresented: $showDisableAlert) {
            Button(VoiceInkPowerModePresentation.settingsDisableAlertButtonTitle, role: .cancel) { }
        } message: {
            Text(VoiceInkPowerModePresentation.settingsDisableAlertMessage)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { powerModeUIFlag },
            set: { newValue in
                if newValue {
                    powerModeUIFlag = true
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else if !powerModeManager.configurations.hasEnabledPowerModeConfigurations {
                    powerModeUIFlag = false
                    NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
                } else {
                    showDisableAlert = true
                }
            }
        )
    }
}

// MARK: - Experimental Section

struct ExperimentalSection: View {
    @ObservedObject private var playbackController = PlaybackController.shared
    @ObservedObject private var mediaController = MediaController.shared
    @State private var isPauseMediaExpanded = false
    private static let presentation = VoiceInkRecordingFeedbackPreference.macOSSettingsPresentation

    var body: some View {
        Section {
            ExpandableSettingsRow(
                isExpanded: $isPauseMediaExpanded,
                isEnabled: $playbackController.isPauseMediaEnabled,
                label: Self.presentation.pauseMediaLabel,
                infoMessage: Self.presentation.pauseMediaInfoMessage
            ) {
                Picker(Self.presentation.pauseMediaResumeDelayLabel, selection: $mediaController.audioResumptionDelay) {
                    ForEach(Self.presentation.audioResumptionDelayOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            }
        } header: {
            Text(Self.presentation.experimentalSectionTitle)
        }
    }
}

// MARK: - Text Extension

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
