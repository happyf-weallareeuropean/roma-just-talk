import SwiftUI
import AVFoundation
import AppKit
import PermissionFlow
import VoiceInkCore

struct OnboardingPermissionsView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @State private var currentPermissionIndex = 0
    @State private var permissionStates = Array(
        repeating: false,
        count: VoiceInkMacOSOnboardingPermissionPresentation.all.count
    )
    @State private var showAnimation = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: CGFloat = 0
    @State private var showModelDownload: Bool
    @State private var relaunchRequiredStates = Array(
        repeating: false,
        count: VoiceInkMacOSOnboardingPermissionPresentation.all.count
    )
    @StateObject private var permissionFlowGuide = PermissionFlowGuide()
    
    private let permissions = VoiceInkMacOSOnboardingPermissionPresentation.all

    init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._showModelDownload = State(
            initialValue: VoiceInkMacOSOnboardingProgressStore.stage().resumesModelDownload
        )
    }

    private var audioDeviceSelectionPresentation: VoiceInkMacOSOnboardingAudioDeviceSelectionPresentation {
        permissions[currentPermissionIndex].audioDeviceSelection
            ?? VoiceInkMacOSOnboardingPermissionPresentation.audioDeviceSelectionPresentation
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    // Reusable background
                    OnboardingBackgroundView()
                    
                    VStack(spacing: 24) {
                        ScrollView(.vertical) {
                            VStack(spacing: 40) {
                                // Progress indicator
                                HStack(spacing: 8) {
                                    ForEach(0..<permissions.count, id: \.self) { index in
                                        Circle()
                                            .fill(index <= currentPermissionIndex ? Color.accentColor : Color.white.opacity(0.1))
                                            .frame(width: 8, height: 8)
                                            .scaleEffect(index == currentPermissionIndex ? 1.2 : 1.0)
                                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPermissionIndex)
                                    }
                                }
                                .padding(.top, 40)
                        
                                // Current permission card
                                VStack(spacing: 30) {
                                    // Permission icon
                                    ZStack {
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.1))
                                            .frame(width: 100, height: 100)
                                
                                        if permissionStates[currentPermissionIndex] {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 50))
                                                .foregroundColor(.accentColor)
                                                .transition(.scale.combined(with: .opacity))
                                        } else {
                                            Image(systemName: permissions[currentPermissionIndex].iconSystemName)
                                                .font(.system(size: 40))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .scaleEffect(scale)
                                    .opacity(opacity)

                                    // Permission text
                                    VStack(spacing: 12) {
                                        HStack(spacing: 8) {
                                            Text(permissions[currentPermissionIndex].title)
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)

                                            if let infoMessage = permissions[currentPermissionIndex].screenContextInfoMessage {
                                                if let infoURL = permissions[currentPermissionIndex].screenContextInfoURLString {
                                                    InfoTip(infoMessage, learnMoreURL: infoURL)
                                                } else {
                                                    InfoTip(infoMessage)
                                                }
                                            }
                                        }
                                
                                        Text(permissions[currentPermissionIndex].description)
                                            .font(.body)
                                            .foregroundColor(.white.opacity(0.7))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                    }
                                    .scaleEffect(scale)
                                    .opacity(opacity)
                            
                                    // Audio device selection (only shown for audio device selection step)
                                    if permissions[currentPermissionIndex].kind == .audioDeviceSelection {
                                        VStack(spacing: 20) {
                                            if audioDeviceManager.availableDevices.isEmpty {
                                                VStack(spacing: 12) {
                                                    Image(systemName: "mic.slash.circle.fill")
                                                        .font(.system(size: 36))
                                                        .symbolRenderingMode(.hierarchical)
                                                        .foregroundStyle(.secondary)
                                            
                                                    Text(audioDeviceSelectionPresentation.emptyStateTitle)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding()
                                            } else {
                                                styledPicker(
                                                    label: audioDeviceSelectionPresentation.pickerLabel,
                                                    selectedValue: audioDeviceManager.selectedDeviceID ?? 0,
                                                    displayValue: audioDeviceManager.availableDevices.first { $0.id == audioDeviceManager.selectedDeviceID }?.name ?? audioDeviceSelectionPresentation.selectedDevicePlaceholder,
                                                    options: audioDeviceManager.availableDevices.map { $0.id },
                                                    optionDisplayName: { deviceId in
                                                        audioDeviceManager.availableDevices.first { $0.id == deviceId }?.name ?? audioDeviceSelectionPresentation.unknownDeviceName
                                                    },
                                                    onSelection: { deviceId in
                                                        audioDeviceManager.selectDevice(id: deviceId)
                                                        audioDeviceManager.selectInputMode(.custom)
                                                        withAnimation {
                                                            permissionStates[currentPermissionIndex] = true
                                                            showAnimation = true
                                                        }
                                                    }
                                                )
                                                .onAppear {
                                                    if !audioDeviceManager.availableDevices.isEmpty {
                                                        if let deviceID = audioDeviceManager.findBestAvailableDevice() {
                                                            audioDeviceManager.selectDevice(id: deviceID)
                                                            audioDeviceManager.selectInputMode(.custom)
                                                            withAnimation {
                                                                permissionStates[currentPermissionIndex] = true
                                                                showAnimation = true
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Text(audioDeviceSelectionPresentation.recommendationText)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                        }
                                        .scaleEffect(scale)
                                        .opacity(opacity)
                                    }
                            
                                    // Keyboard shortcut recorder (only shown for keyboard shortcut step)
                                    if permissions[currentPermissionIndex].kind == .keyboardShortcut {
                                        shortcutView { isConfigured in
                                            withAnimation {
                                                permissionStates[currentPermissionIndex] = isConfigured
                                                showAnimation = isConfigured
                                            }
                                        }
                                        .scaleEffect(scale)
                                        .opacity(opacity)
                                    }
                                }
                                .frame(maxWidth: 400)
                                .padding(.vertical, 40)

                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Action buttons
                        VStack(spacing: 16) {
                            Button(action: requestPermission) {
                                Text(permissions[currentPermissionIndex].buttonTitle(
                                    isGranted: permissionStates[currentPermissionIndex],
                                    requiresRelaunch: relaunchRequiredStates[currentPermissionIndex]
                                ))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 50)
                                    .background(Color.accentColor)
                                    .cornerRadius(25)
                            }
                            .buttonStyle(ScaleButtonStyle())

                            if relaunchRequiredStates[currentPermissionIndex] {
                                Text(VoiceInkMacOSOnboardingPermissionPresentation.relaunchRequiredMessage)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.65))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 360)
                            }
                            
                            if !permissionStates[currentPermissionIndex] && 
                               permissions[currentPermissionIndex].canSkipWhenNotGranted {
                                SkipButton(text: VoiceInkMacOSOnboardingPermissionPresentation.skipButtonTitle) {
                                    moveToNext()
                                }
                            }
                        }
                        .opacity(opacity)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
            }
            
            if showModelDownload {
                OnboardingModelDownloadView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            refreshPermissionStates()
            resumeSavedPermissionProgress()
            animateIn()
            // Ensure audio devices are loaded
            audioDeviceManager.loadAvailableDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appPermissionsDidChange)) { _ in
            refreshPermissionStates()
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1
            opacity = 1
        }
    }
    
    private func resetAnimation() {
        scale = 0.8
        opacity = 0
        animateIn()
    }
    
    private func refreshPermissionStates() {
        // Check microphone permission
        permissionStates[0] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if permissionStates[0] { relaunchRequiredStates[0] = false }
        
        // Check if device is selected
        permissionStates[1] = audioDeviceManager.selectedDeviceID != nil
        if permissionStates[1] { relaunchRequiredStates[1] = false }
        
        // Check accessibility permission
        permissionStates[2] = AXIsProcessTrusted()
        if permissionStates[2] { relaunchRequiredStates[2] = false }

        // Check input monitoring permission
        permissionStates[3] = ShortcutMonitor.preflightListenEventAccess()
        if permissionStates[3] { relaunchRequiredStates[3] = false }
        
        // Check screen recording permission
        permissionStates[4] = CGPreflightScreenCaptureAccess()
        if permissionStates[4] { relaunchRequiredStates[4] = false }
        
        // Check keyboard shortcut
        permissionStates[5] = recordingShortcutManager.isShortcutConfigured
        if permissionStates[5] { relaunchRequiredStates[5] = false }
    }

    private func resumeSavedPermissionProgress() {
        guard !showModelDownload else { return }

        let savedIndex = VoiceInkMacOSOnboardingProgressStore.permissionKind().flatMap { savedKind in
            permissions.firstIndex { $0.kind == savedKind }
        } ?? currentPermissionIndex

        currentPermissionIndex = firstUnfinishedPermissionIndex(startingAt: savedIndex)
        saveCurrentPermissionProgress()
    }

    private func firstUnfinishedPermissionIndex(startingAt index: Int) -> Int {
        var index = min(max(index, 0), permissions.count - 1)

        while index < permissions.count - 1, permissionStates[index] {
            index += 1
        }

        return index
    }

    private func saveCurrentPermissionProgress() {
        VoiceInkMacOSOnboardingProgressStore.saveStage(.permissions)
        VoiceInkMacOSOnboardingProgressStore.savePermissionKind(permissions[currentPermissionIndex].kind)
    }
    
    private func requestPermission() {
        saveCurrentPermissionProgress()

        if relaunchRequiredStates[currentPermissionIndex] {
            AppRelauncher.relaunch()
            return
        }

        if permissionStates[currentPermissionIndex] {
            moveToNext()
            return
        }
        
        switch permissions[currentPermissionIndex].kind {
        case .microphone:
            let permissionIndex = currentPermissionIndex
            PermissionGrantCoordinator.grantMicrophone { status in
                let granted = status == .authorized
                permissionStates[permissionIndex] = granted
                if granted {
                    withAnimation {
                        showAnimation = true
                    }
                    audioDeviceManager.loadAvailableDevices()
                }
            }
            
        case .audioDeviceSelection:
            audioDeviceManager.loadAvailableDevices()

            if audioDeviceManager.availableDevices.isEmpty {
                audioDeviceManager.selectInputMode(.custom)
                withAnimation {
                    permissionStates[currentPermissionIndex] = true
                    showAnimation = true
                }
                moveToNext()
                return
            }

            if let deviceID = audioDeviceManager.findBestAvailableDevice() {
                audioDeviceManager.selectDevice(id: deviceID)
                audioDeviceManager.selectInputMode(.custom)
                withAnimation {
                    permissionStates[currentPermissionIndex] = true
                    showAnimation = true
                }
            }
            moveToNext()

        case .accessibility:
            let permissionIndex = currentPermissionIndex
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options)
            permissionFlowGuide.open(.accessibility)
            
            // Start checking for permission status
            Timer.scheduledTimer(
                withTimeInterval: VoiceInkMacOSPermissionTimingPolicy.pollingInterval,
                repeats: true
            ) { timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    permissionStates[permissionIndex] = true
                    withAnimation {
                        showAnimation = true
                    }
                }
            }

        case .inputMonitoring:
            relaunchRequiredStates[currentPermissionIndex] = false
            let granted = ShortcutMonitor.requestListenEventAccess()
            permissionStates[currentPermissionIndex] = granted || ShortcutMonitor.preflightListenEventAccess()
            permissionFlowGuide.open(.inputMonitoring)

            let permissionIndex = currentPermissionIndex
            Timer.scheduledTimer(
                withTimeInterval: VoiceInkMacOSPermissionTimingPolicy.pollingInterval,
                repeats: true
            ) { timer in
                if ShortcutMonitor.preflightListenEventAccess() {
                    timer.invalidate()
                    permissionStates[permissionIndex] = true
                    relaunchRequiredStates[permissionIndex] = false
                    withAnimation {
                        showAnimation = true
                    }
                }
            }
            markRelaunchNeededIfPermissionStillInactive(
                at: permissionIndex,
                isActive: ShortcutMonitor.preflightListenEventAccess
            )
            
        case .screenRecording:
            relaunchRequiredStates[currentPermissionIndex] = false
            permissionFlowGuide.open(.screenRecording)
            
            let permissionIndex = currentPermissionIndex
            // Start checking for permission status
            Timer.scheduledTimer(
                withTimeInterval: VoiceInkMacOSPermissionTimingPolicy.pollingInterval,
                repeats: true
            ) { timer in
                if CGPreflightScreenCaptureAccess() {
                    timer.invalidate()
                    permissionStates[permissionIndex] = true
                    relaunchRequiredStates[permissionIndex] = false
                    withAnimation {
                        showAnimation = true
                    }
                }
            }
            markRelaunchNeededIfPermissionStillInactive(
                at: permissionIndex,
                isActive: CGPreflightScreenCaptureAccess
            )
            
        case .keyboardShortcut:
            // The shortcut recorder handles this step directly.
            break
        }
    }
    
    private func moveToNext() {
        if currentPermissionIndex < permissions.count - 1 {
            withAnimation {
                currentPermissionIndex += 1
                saveCurrentPermissionProgress()
                resetAnimation()
            }
        } else {
            VoiceInkMacOSOnboardingProgressStore.saveStage(.modelDownload)
            withAnimation {
                showModelDownload = true
            }
        }
    }
    
    private func markRelaunchNeededIfPermissionStillInactive(at index: Int, isActive: @escaping () -> Bool) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VoiceInkMacOSPermissionTimingPolicy.relaunchRequiredDelay
        ) {
            Task { @MainActor in
                guard index < permissionStates.count else { return }

                if isActive() {
                    permissionStates[index] = true
                    relaunchRequiredStates[index] = false
                } else {
                    relaunchRequiredStates[index] = true
                }
            }
        }
    }

    @ViewBuilder
    private func styledPicker<T: Hashable>(
        label: String,
        selectedValue: T,
        displayValue: String,
        options: [T],
        optionDisplayName: @escaping (T) -> String,
        onSelection: @escaping (T) -> Void
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Spacer()
                
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            onSelection(option)
                        }) {
                            HStack {
                                Text(optionDisplayName(option))
                                if selectedValue == option {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(displayValue)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func shortcutView(onConfigured: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            Spacer()

            Text("Shortcut:")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            ShortcutRecorder(action: .primaryRecording) {
                recordingShortcutManager.primaryRecordingShortcut = .custom
                recordingShortcutManager.updateShortcutStatus()
                onConfigured(ShortcutStore.shortcut(for: .primaryRecording) != nil)
            }
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .onAppear {
            recordingShortcutManager.primaryRecordingShortcut = .custom
            onConfigured(ShortcutStore.shortcut(for: .primaryRecording) != nil)
        }
    }
}
