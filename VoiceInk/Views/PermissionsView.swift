import SwiftUI
import AVFoundation
import Cocoa
import CoreGraphics
import PermissionFlow

@MainActor
class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isInputMonitoringEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var isKeyboardShortcutSet = false
    @Published var inputMonitoringNeedsRelaunch = false
    @Published var screenRecordingNeedsRelaunch = false
    private let permissionFlowGuide = PermissionFlowGuide()
    private var permissionRefreshTimer: Timer?
    private var permissionRefreshPollsRemaining = 0
    
    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()
        
        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        permissionRefreshTimer?.invalidate()
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appPermissionsDidChange),
            name: .appPermissionsDidChange,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }

    @objc private func appPermissionsDidChange() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkInputMonitoringPermission()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
        checkKeyboardShortcut()
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        isAccessibilityEnabled = accessibilityEnabled
    }
    
    func checkScreenRecordingPermission() {
        isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
        if isScreenRecordingEnabled {
            screenRecordingNeedsRelaunch = false
        }
    }
    
    func requestScreenRecordingPermission() {
        screenRecordingNeedsRelaunch = false
        permissionFlowGuide.open(.screenRecording)
        startPermissionRefreshPolling()
        markRelaunchNeededIfPermissionStillInactive(.screenRecording)
    }
    
    func checkAudioPermissionStatus() {
        audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestAudioPermission() {
        PermissionGrantCoordinator.grantMicrophone { [weak self] status in
            self?.audioPermissionStatus = status
            self?.startPermissionRefreshPolling()
        }
    }

    func openMicrophoneSettings() {
        requestAudioPermission()
    }

    func checkInputMonitoringPermission() {
        isInputMonitoringEnabled = ShortcutMonitor.preflightListenEventAccess()
        if isInputMonitoringEnabled {
            inputMonitoringNeedsRelaunch = false
        }
    }

    func requestInputMonitoringPermission() {
        inputMonitoringNeedsRelaunch = false
        let granted = ShortcutMonitor.requestListenEventAccess()
        isInputMonitoringEnabled = granted || ShortcutMonitor.preflightListenEventAccess()
        permissionFlowGuide.open(.inputMonitoring)
        startPermissionRefreshPolling()
        markRelaunchNeededIfPermissionStillInactive(.inputMonitoring)
    }

    nonisolated static func openInputMonitoringSettings() {
        Task { @MainActor in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    nonisolated static func openAccessibilitySettings() {
        Task { @MainActor in
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        permissionFlowGuide.open(.accessibility)
        startPermissionRefreshPolling()
    }
    
    func checkKeyboardShortcut() {
        isKeyboardShortcutSet = ShortcutStore.shortcut(for: .primaryRecording) != nil
    }

    private func startPermissionRefreshPolling() {
        PermissionRefreshCenter.shared.beginPolling()
        permissionRefreshTimer?.invalidate()
        permissionRefreshPollsRemaining = 120
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.checkAllPermissions()
                self.permissionRefreshPollsRemaining -= 1

                if self.permissionRefreshPollsRemaining <= 0 {
                    timer.invalidate()
                    self.permissionRefreshTimer = nil
                }
            }
        }
    }

    private enum RelaunchSensitivePermission {
        case inputMonitoring
        case screenRecording
    }

    private func markRelaunchNeededIfPermissionStillInactive(_ permission: RelaunchSensitivePermission) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch permission {
                case .inputMonitoring:
                    self.checkInputMonitoringPermission()
                    if !self.isInputMonitoringEnabled {
                        self.inputMonitoringNeedsRelaunch = true
                    }
                case .screenRecording:
                    self.checkScreenRecordingPermission()
                    if !self.isScreenRecordingEnabled {
                        self.screenRecordingNeedsRelaunch = true
                    }
                }
            }
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var relaunchRequired: Bool = false
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if let message = infoTipMessage {
                            if let link = infoTipLink, !link.isEmpty {
                                InfoTip(message, learnMoreURL: link)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator with refresh
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        
                        // Reset the animation after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    
                    if isGranted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            
            if !isGranted {
                if relaunchRequired {
                    Text("If you already turned this on in System Settings, relaunch roma-just-talk to activate it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                CompactHeroSection(
                    icon: "shield.lefthalf.filled",
                    title: "App Permissions",
                    description: "Microphone and shortcut access are needed for recording. Screen context is optional."
                )
                
                // Permission Cards
                VStack(spacing: 16) {
                    // Keyboard Shortcut Permission
                    PermissionCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Set up a keyboard shortcut to use roma-just-talk anywhere",
                        isGranted: recordingShortcutManager.isShortcutConfigured,
                        buttonTitle: "Configure Shortcut",
                        buttonAction: {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Settings"]
                            )
                        },
                        checkPermission: { permissionManager.checkKeyboardShortcut() }
                    )

                    // Input Monitoring Permission
                    PermissionCard(
                        icon: "keyboard.badge.eye",
                        title: "Input Monitoring Access",
                        description: "Allow roma-just-talk to listen for your recording hotkey globally",
                        isGranted: permissionManager.isInputMonitoringEnabled,
                        buttonTitle: permissionManager.inputMonitoringNeedsRelaunch ? "Relaunch to Apply" : "Grant",
                        buttonAction: {
                            if permissionManager.inputMonitoringNeedsRelaunch {
                                AppRelauncher.relaunch()
                            } else {
                                permissionManager.requestInputMonitoringPermission()
                            }
                        },
                        checkPermission: { permissionManager.checkInputMonitoringPermission() },
                        relaunchRequired: permissionManager.inputMonitoringNeedsRelaunch,
                        infoTipMessage: "roma-just-talk uses Input Monitoring only to detect your configured recording shortcut while other apps are active."
                    )
                    
                    // Audio Permission
                    PermissionCard(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "Allow roma-just-talk to record your voice for transcription",
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonTitle: "Grant",
                        buttonAction: {
                            permissionManager.requestAudioPermission()
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        icon: "hand.raised",
                        title: "Accessibility Access",
                        description: "Add roma-just-talk to Accessibility, then turn its switch on",
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonTitle: "Grant",
                        buttonAction: {
                            permissionManager.requestAccessibilityPermission()
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() },
                        infoTipMessage: "macOS requires you to enable the roma-just-talk switch yourself. Dragging the app into the list only adds it when it is missing."
                    )
                    
                    // Screen Recording Permission
                    PermissionCard(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Context (Optional)",
                        description: "Use visible screen text to improve transcript enhancement when you choose.",
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonTitle: permissionManager.screenRecordingNeedsRelaunch ? "Relaunch to Apply" : "Enable",
                        buttonAction: {
                            if permissionManager.screenRecordingNeedsRelaunch {
                                AppRelauncher.relaunch()
                            } else {
                                permissionManager.requestScreenRecordingPermission()
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() },
                        relaunchRequired: permissionManager.screenRecordingNeedsRelaunch,
                        infoTipMessage: "roma-just-talk captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
                        infoTipLink: "https://tryvoiceink.com/docs/contextual-awareness"
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }
}

#Preview {
    PermissionsView()
} 
