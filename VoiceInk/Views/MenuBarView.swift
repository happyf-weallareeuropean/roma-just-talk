import SwiftUI
import VoiceInkCore

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var engine: VoiceInkEngine
    @EnvironmentObject var recorderUIManager: RecorderUIManager
    @EnvironmentObject var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject var whisperModelManager: WhisperModelManager
    @EnvironmentObject var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @State private var menuRefreshTrigger = false
    @State private var isHovered = false
    @AppStorage(VoiceInkMenuBarPreference.showMenuBarIconKey) private var showMenuBarIcon = VoiceInkMenuBarPreference.defaultShowMenuBarIcon
    
    var body: some View {
        VStack {
            Button(VoiceInkMacOSMenuBarPresentation.toggleRecorderTitle) {
                recorderUIManager.handleToggleMiniRecorder()
            }

            Divider()

            Menu {
                ForEach(transcriptionModelManager.usableModels, id: \.id) { model in
                    Button {
                        Task {
                            transcriptionModelManager.setDefaultTranscriptionModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if transcriptionModelManager.currentTranscriptionModel?.id == model.id {
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                Divider()

                Button(VoiceInkMacOSMenuBarPresentation.manageModelsTitle) {
                    openMainWindowAndNavigate(to: VoiceInkMacOSNavigationDestination.aiModels.rawValue)
                }
            } label: {
                HStack {
                    Text(VoiceInkMacOSMenuBarPresentation.transcriptionModelTitle(
                        currentDisplayName: transcriptionModelManager.currentTranscriptionModel?.displayName
                    ))
                    Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Divider()
            
            Toggle(VoiceInkMacOSMenuBarPresentation.aiEnhancementToggleTitle, isOn: $enhancementService.isEnhancementEnabled)
            
            Menu {
                ForEach(enhancementService.allPrompts) { prompt in
                    Button {
                        enhancementService.setActivePrompt(prompt)
                    } label: {
                        HStack {
                            Image(systemName: prompt.icon)
                                .foregroundColor(.accentColor)
                            Text(prompt.title)
                            if enhancementService.selectedPromptId == prompt.id {
                                Spacer()
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(VoiceInkMacOSMenuBarPresentation.promptTitle(activePromptTitle: enhancementService.activePrompt?.title))
                    Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Menu {
                ForEach(aiService.connectedProviders, id: \.self) { provider in
                    Button {
                        aiService.selectedProvider = provider
                    } label: {
                        HStack {
                            Text(provider.rawValue)
                            if aiService.selectedProvider == provider {
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if aiService.connectedProviders.isEmpty {
                    Text(VoiceInkMacOSMenuBarPresentation.noProvidersConnectedText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(VoiceInkMacOSMenuBarPresentation.aiProviderTitle(selectedProviderName: aiService.selectedProvider.rawValue))
                    Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            Menu {
                ForEach(aiService.availableModels, id: \.self) { model in
                    Button {
                        aiService.selectModel(model)
                    } label: {
                        HStack {
                            Text(model)
                            if aiService.currentModel == model {
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if aiService.availableModels.isEmpty {
                    Text(VoiceInkMacOSMenuBarPresentation.noModelsAvailableText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(VoiceInkMacOSMenuBarPresentation.aiModelTitle(currentModelName: aiService.currentModel))
                    Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }
            
            LanguageSelectionView(transcriptionModelManager: transcriptionModelManager, displayMode: .menuItem)

            Menu {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button {
                        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: device.id)
                    } label: {
                        HStack {
                            Text(device.name)
                            if audioDeviceManager.getCurrentDevice() == device.id {
                                Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                            }
                        }
                    }
                }

                if audioDeviceManager.availableDevices.isEmpty {
                    Text(VoiceInkMacOSMenuBarPresentation.noDevicesAvailableText)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Text(VoiceInkMacOSMenuBarPresentation.audioInputTitle)
                    Image(systemName: VoiceInkMacOSMenuBarPresentation.pickerSystemImageName)
                        .font(.system(size: 10))
                }
            }

            Menu(VoiceInkMacOSMenuBarPresentation.additionalMenuTitle) {
                Button {
                    enhancementService.useClipboardContext.toggle()
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text(VoiceInkMacOSMenuBarPresentation.clipboardContextTitle)
                        Spacer()
                        if enhancementService.useClipboardContext {
                            Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                        }
                    }
                }

                Button {
                    enhancementService.useScreenCaptureContext.toggle()
                    menuRefreshTrigger.toggle()
                } label: {
                    HStack {
                        Text(VoiceInkMacOSMenuBarPresentation.contextAwarenessTitle)
                        Spacer()
                        if enhancementService.useScreenCaptureContext {
                            Image(systemName: VoiceInkMacOSMenuBarPresentation.selectionCheckmarkSystemImageName)
                        }
                    }
                }
            }
            .id("additional-menu-\(menuRefreshTrigger)")
            
            Divider()

            Button(VoiceInkMacOSMenuBarPresentation.retryLastTranscriptionTitle) {
                LastTranscriptionService.retryLastTranscription(
                    from: engine.modelContext,
                    transcriptionModelManager: transcriptionModelManager,
                    serviceRegistry: engine.serviceRegistry,
                    enhancementService: enhancementService
                )
            }

            Button(VoiceInkMacOSMenuBarPresentation.copyLastTranscriptionTitle) {
                LastTranscriptionService.copyLastTranscription(from: engine.modelContext)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button(VoiceInkMacOSMenuBarPresentation.historyTitle) {
                menuBarManager.openHistoryWindow()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button(VoiceInkMacOSMenuBarPresentation.permissionsTitle) {
                openMainWindowAndNavigate(to: VoiceInkMacOSNavigationDestination.permissions.rawValue)
            }
            
            Button(VoiceInkMacOSMenuBarPresentation.settingsTitle) {
                openMainWindowAndNavigate(to: VoiceInkMacOSNavigationDestination.settings.rawValue)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(VoiceInkMacOSMenuBarPresentation.dockIconTitle(showDockIcon: menuBarManager.showDockIcon)) {
                menuBarManager.toggleDockIcon()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button(VoiceInkMacOSMenuBarPresentation.hideMenuBarIconTitle) {
                showMenuBarIcon = false
            }
            
            Toggle(
                VoiceInkMacOSMenuBarPresentation.launchAtLoginTitle,
                isOn: $launchAtLoginController.isEnabled
            )
            
            Divider()

            if updaterViewModel.status.canRelaunch {
                Button(updaterViewModel.status.title) {
                    updaterViewModel.relaunchToUpdate()
                }
            } else {
                Button(VoiceInkMacOSMenuBarPresentation.checkForUpdatesTitle) {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)

                if updaterViewModel.status.isVisible {
                    Text(updaterViewModel.status.title)
                }
            }
            
            Button(VoiceInkMacOSMenuBarPresentation.helpAndSupportTitle) {
                EmailSupport.openSupportEmail()
            }
            
            Divider()

            Button(VoiceInkMacOSMenuBarPresentation.quitTitle) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func openMainWindowAndNavigate(to destination: String) {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            _ = WindowManager.shared.showMainWindow()
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: destination)
            )
        }
    }
}
