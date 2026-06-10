import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import PermissionFlow

@MainActor
final class PermissionFlowGuide: ObservableObject {
    private lazy var controller = PermissionFlow.makeController(
        configuration: .init(
            requiredAppURLs: Self.currentAppBundleURLs(),
            promptForAccessibilityTrust: true
        )
    )

    func open(_ pane: PermissionFlowPane) {
        let controller = controller
        controller.authorize(
            pane: pane,
            suggestedAppURLs: Self.currentAppBundleURLs(),
            sourceFrameInScreen: Self.clickSourceFrameInScreen()
        )

        if pane.supportsFloatingAuthorizationPanel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Task { @MainActor in
                    controller.showPanel()
                }
            }
        }

        PermissionRefreshCenter.shared.beginPolling()
    }

    private static func currentAppBundleURLs() -> [URL] {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        return bundleURL.pathExtension.lowercased() == "app" ? [bundleURL] : []
    }

    private static func clickSourceFrameInScreen() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }
}

struct AppPermissionSnapshot: Equatable {
    var microphone: AVAuthorizationStatus
    var accessibility: Bool
    var inputMonitoring: Bool
    var screenRecording: Bool

    static func current() -> AppPermissionSnapshot {
        AppPermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio),
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: ShortcutMonitor.preflightListenEventAccess(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }
}

@MainActor
final class PermissionRefreshCenter: NSObject {
    static let shared = PermissionRefreshCenter()

    private var timer: Timer?
    private var pollsRemaining = 0
    private var lastSnapshot = AppPermissionSnapshot.current()
    private var isObservingApplicationActivation = false

    private override init() {
        super.init()
    }

    func startObservingApplicationActivation() {
        guard !isObservingApplicationActivation else { return }
        isObservingApplicationActivation = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func beginPolling() {
        startObservingApplicationActivation()
        refreshPermissions()
        pollsRemaining = 120

        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.refreshPermissions()
                self.pollsRemaining -= 1

                if self.pollsRemaining <= 0 {
                    timer.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    @objc private func applicationDidBecomeActive() {
        beginPolling()
    }

    private func refreshPermissions() {
        let snapshot = AppPermissionSnapshot.current()
        guard snapshot != lastSnapshot else { return }

        lastSnapshot = snapshot
        NotificationCenter.default.post(name: .appPermissionsDidChange, object: self)
    }
}

@MainActor
enum AppRelauncher {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 0.6; /usr/bin/open \"$1\"",
            "voiceink-relaunch",
            Bundle.main.bundleURL.path
        ]

        do {
            try task.run()
            NSApplication.shared.terminate(nil)
        } catch {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
enum PermissionGrantCoordinator {
    private static let permissionFlowGuide = PermissionFlowGuide()

    static func grantMicrophone(statusUpdate: ((AVAuthorizationStatus) -> Void)? = nil) {
        PermissionRefreshCenter.shared.beginPolling()
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            statusUpdate?(.authorized)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    let status = granted ? AVAuthorizationStatus.authorized : AVCaptureDevice.authorizationStatus(for: .audio)
                    statusUpdate?(status)
                    PermissionRefreshCenter.shared.beginPolling()
                    if !granted {
                        permissionFlowGuide.open(.microphone)
                    }
                }
            }
        case .denied, .restricted:
            statusUpdate?(currentStatus)
            permissionFlowGuide.open(.microphone)
        @unknown default:
            statusUpdate?(currentStatus)
            permissionFlowGuide.open(.microphone)
        }
    }

    static func grantInputMonitoring(statusUpdate: ((Bool) -> Void)? = nil) {
        PermissionRefreshCenter.shared.beginPolling()
        let granted = ShortcutMonitor.requestListenEventAccess() || ShortcutMonitor.preflightListenEventAccess()
        statusUpdate?(granted)
        permissionFlowGuide.open(.inputMonitoring)
    }

    static func grantAccessibility(statusUpdate: ((Bool) -> Void)? = nil) {
        PermissionRefreshCenter.shared.beginPolling()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        statusUpdate?(granted)
        permissionFlowGuide.open(.accessibility)
    }

    static func openPermissionsAndGrantMicrophone() {
        NSApplication.shared.setActivationPolicy(.regular)
        NotificationCenter.default.post(
            name: .openMainWindowRequested,
            object: nil,
            userInfo: ["destination": "Permissions"]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                grantMicrophone()
            }
        }
    }
}
