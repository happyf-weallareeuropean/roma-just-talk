import AppKit
import AVFoundation
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

@MainActor
enum PermissionGrantCoordinator {
    private static let permissionFlowGuide = PermissionFlowGuide()

    static func grantMicrophone(statusUpdate: ((AVAuthorizationStatus) -> Void)? = nil) {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            statusUpdate?(.authorized)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    let status = granted ? AVAuthorizationStatus.authorized : AVCaptureDevice.authorizationStatus(for: .audio)
                    statusUpdate?(status)
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
