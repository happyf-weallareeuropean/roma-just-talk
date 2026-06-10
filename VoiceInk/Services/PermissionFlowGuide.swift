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

    struct Client {
        var beginPolling: () -> Void
        var microphoneStatus: () -> AVAuthorizationStatus
        var requestMicrophone: (@escaping (Bool) -> Void) -> Void
        var openMicrophonePane: () -> Void
        var requestInputMonitoring: () -> Bool
        var isInputMonitoringGranted: () -> Bool
        var openInputMonitoringPane: () -> Void
        var requestAccessibility: () -> Bool
        var openAccessibilityPane: () -> Void
        var openScreenRecordingPane: () -> Void
    }

    private static var liveClient: Client {
        Client(
            beginPolling: { PermissionRefreshCenter.shared.beginPolling() },
            microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
            requestMicrophone: { completion in
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
            },
            openMicrophonePane: {
                permissionFlowGuide.open(.microphone)
            },
            requestInputMonitoring: {
                ShortcutMonitor.requestListenEventAccess()
            },
            isInputMonitoringGranted: {
                ShortcutMonitor.preflightListenEventAccess()
            },
            openInputMonitoringPane: {
                permissionFlowGuide.open(.inputMonitoring)
            },
            requestAccessibility: {
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                return AXIsProcessTrustedWithOptions(options)
            },
            openAccessibilityPane: {
                permissionFlowGuide.open(.accessibility)
            },
            openScreenRecordingPane: {
                permissionFlowGuide.open(.screenRecording)
            }
        )
    }

    static func grantMicrophone(
        client: Client = liveClient,
        statusUpdate: ((AVAuthorizationStatus) -> Void)? = nil
    ) {
        client.beginPolling()
        let currentStatus = client.microphoneStatus()

        switch currentStatus {
        case .authorized:
            statusUpdate?(.authorized)
        case .notDetermined:
            client.requestMicrophone { granted in
                Task { @MainActor in
                    let status = granted ? AVAuthorizationStatus.authorized : client.microphoneStatus()
                    statusUpdate?(status)
                    client.beginPolling()
                    if !granted {
                        client.openMicrophonePane()
                    }
                }
            }
        case .denied, .restricted:
            statusUpdate?(currentStatus)
            client.openMicrophonePane()
        @unknown default:
            statusUpdate?(currentStatus)
            client.openMicrophonePane()
        }
    }

    static func grantInputMonitoring(
        client: Client = liveClient,
        statusUpdate: ((Bool) -> Void)? = nil
    ) {
        client.beginPolling()
        let granted = client.requestInputMonitoring() || client.isInputMonitoringGranted()
        statusUpdate?(granted)
        client.openInputMonitoringPane()
    }

    static func grantAccessibility(
        client: Client = liveClient,
        statusUpdate: ((Bool) -> Void)? = nil
    ) {
        client.beginPolling()
        let granted = client.requestAccessibility()
        statusUpdate?(granted)
        client.openAccessibilityPane()
    }

    static func grantScreenRecording(client: Client = liveClient) {
        client.beginPolling()
        client.openScreenRecordingPane()
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
