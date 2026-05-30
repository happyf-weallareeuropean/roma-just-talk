import AppKit
import PermissionFlow

@MainActor
final class PermissionFlowGuide: ObservableObject {
    private let controller = PermissionFlow.makeController()

    func open(_ pane: PermissionFlowPane) {
        controller.authorize(
            pane: pane,
            suggestedAppURLs: Self.currentAppBundleURLs(),
            sourceFrameInScreen: Self.clickSourceFrameInScreen()
        )
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
