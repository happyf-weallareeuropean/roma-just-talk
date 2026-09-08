import SwiftUI
import AppKit
import OSLog
import VoiceInkCore

class WindowManager: NSObject {
    static let shared = WindowManager()

    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier(VoiceInkMacOSWindowIdentity.mainIdentifierRawValue)
    private static let onboardingWindowIdentifier = NSUserInterfaceItemIdentifier(VoiceInkMacOSWindowIdentity.onboardingIdentifierRawValue)
    private static let mainWindowAutosaveName = NSWindow.FrameAutosaveName(VoiceInkMacOSWindowIdentity.mainFrameAutosaveName)

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: VoiceInkMacOSLogCategory.windowManager)
    private weak var mainWindow: NSWindow?
    private var didApplyInitialPlacement = false
    private var mainFrameBeforeOnboarding: NSRect?

    private override init() {
        super.init()
    }
    
    func configureWindow(_ window: NSWindow) {
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier && $0 != window }) {
            logger.notice("\(VoiceInkMacOSWindowIdentity.configureWindowDuplicateDetectedMessage, privacy: .public)")
            window.close()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        logger.notice("\(VoiceInkMacOSWindowIdentity.configureWindowRegisteringMainMessage, privacy: .public)")
        
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = VoiceInkMacOSWindowIdentity.mainTitle
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 0, height: 0)
        window.setFrameAutosaveName(Self.mainWindowAutosaveName)
        applyInitialPlacementIfNeeded(to: window)
        registerMainWindowIfNeeded(window)
        window.orderFrontRegardless()
    }
    
    func configureOnboardingPanel(_ window: NSWindow) {
        guard window.identifier != Self.onboardingWindowIdentifier else { return }
        if window.identifier == Self.mainWindowIdentifier {
            // Keep this live frame while the same window temporarily hosts setup.
            mainFrameBeforeOnboarding = window.frame
            window.setFrameAutosaveName("")
            didApplyInitialPlacement = false
        }
        window.identifier = Self.onboardingWindowIdentifier
        
        NSApplication.shared.setActivationPolicy(.regular)

        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.title = VoiceInkMacOSWindowIdentity.onboardingTitle
        window.isOpaque = true
        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            let preferredFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 950, height: 730))
            // AppKit minima are frame sizes, including the title bar, not content sizes.
            window.minSize = NSSize(width: min(900, visibleFrame.width), height: min(780, visibleFrame.height))
            let size = NSSize(
                width: min(max(preferredFrame.width, window.minSize.width), visibleFrame.width),
                height: min(max(preferredFrame.height, window.minSize.height), visibleFrame.height)
            )
            window.setFrame(NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ), display: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
    }
    
    func showMainWindow() -> NSWindow? {
        guard let window = resolveMainWindow() else {
            return nil
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }
    
    func hideMainWindow() {
        guard let window = resolveMainWindow() else {
            return
        }
        window.orderOut(nil)
    }
    
    func currentMainWindow() -> NSWindow? {
        resolveMainWindow()
    }
    
    private func registerMainWindowIfNeeded(_ window: NSWindow) {
        // Only register the primary content window, identified by the hidden title bar style
        if window.identifier == nil || window.identifier != Self.mainWindowIdentifier {
            registerMainWindow(window)
        }
    }
    
    private func applyInitialPlacementIfNeeded(to window: NSWindow) {
        guard !didApplyInitialPlacement else { return }
        // Attempt to restore previous frame if one exists; otherwise fall back to a centered placement
        if let frame = mainFrameBeforeOnboarding {
            window.setFrame(frame, display: true)
            mainFrameBeforeOnboarding = nil
        } else if !window.setFrameUsingName(Self.mainWindowAutosaveName) {
            window.center()
        }
        didApplyInitialPlacement = true
    }
    
    private func resolveMainWindow() -> NSWindow? {
        if let window = mainWindow {
            return window
        }

        logger.notice("\(VoiceInkMacOSWindowIdentity.resolveMainWindowSearchingMessage(windowCount: NSApplication.shared.windows.count), privacy: .public)")

        if let window = NSApplication.shared.windows.first(where: { $0.identifier == Self.mainWindowIdentifier }) {
            logger.notice("\(VoiceInkMacOSWindowIdentity.resolveMainWindowRecoveredMessage, privacy: .public)")
            mainWindow = window
            window.delegate = self
            return window
        }

        let windowIDs = VoiceInkMacOSWindowIdentity.identifierListDebugText(
            NSApplication.shared.windows.map { $0.identifier?.rawValue }
        )
        logger.error("\(VoiceInkMacOSWindowIdentity.resolveMainWindowFailedMessage(windowCount: NSApplication.shared.windows.count, identifiers: windowIDs), privacy: .public)")
        return nil
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.identifier == Self.mainWindowIdentifier {
            logger.notice("\(VoiceInkMacOSWindowIdentity.windowWillCloseMainMessage, privacy: .public)")
            window.orderOut(nil)
            mainWindow = nil
            didApplyInitialPlacement = false
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
} 
