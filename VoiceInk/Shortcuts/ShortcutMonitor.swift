import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

enum InputMonitoringPermission {
    struct Client {
        var preflight: () -> Bool
        var request: () -> Bool
    }

    static let systemClient = Client(
        preflight: CGPreflightListenEventAccess,
        request: CGRequestListenEventAccess
    )

    static func isGranted(client: Client = systemClient) -> Bool {
        client.preflight()
    }

    @discardableResult
    static func requestAccess(client: Client = systemClient) -> Bool {
        client.request()
    }
}

enum AccessibilityPermission {
    struct Client {
        var preflight: () -> Bool
        var request: () -> Bool
    }

    static let systemClient = Client(
        preflight: AXIsProcessTrusted,
        request: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    )

    static func isGranted(client: Client = systemClient) -> Bool {
        client.preflight()
    }

    @discardableResult
    static func requestAccess(client: Client = systemClient) -> Bool {
        client.request()
    }
}

final class ShortcutMonitor {
    fileprivate enum EventKind {
        case keyDown
        case keyUp
        case flagsChanged
    }

    private struct ShortcutState {
        var shortcut: Shortcut
        var isDown = false
        var pressedAt: TimeInterval?
        var isInterrupted = false
    }

    private var shortcuts: [ShortcutAction: ShortcutState] = [:]
    private var interruptibleActions: Set<ShortcutAction> = []
    private var onKeyDown: ((ShortcutAction, TimeInterval) -> Void)?
    private var onKeyUp: ((ShortcutAction, TimeInterval) -> Void)?
    private var onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ShortcutMonitor")

    private static var hasRequestedListenEventAccess = false
    private static var hasRequestedAccessibilityAccess = false
    private static let shortcutInterruptionWindow: TimeInterval = 1.0

    deinit {
        stop()
    }

    @discardableResult
    func start(
        shortcuts: [ShortcutAction: Shortcut],
        interruptibleActions: Set<ShortcutAction> = [],
        onKeyDown: @escaping (ShortcutAction, TimeInterval) -> Void,
        onKeyUp: @escaping (ShortcutAction, TimeInterval) -> Void,
        onShortcutInterrupted: ((ShortcutAction, TimeInterval) -> Void)? = nil
    ) -> Bool {
        stop()

        for (action, shortcut) in shortcuts {
            self.shortcuts[action] = ShortcutState(shortcut: shortcut)
        }

        guard !self.shortcuts.isEmpty else {
            logger.notice("start: no shortcuts configured")
            return true
        }

        self.interruptibleActions = interruptibleActions
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onShortcutInterrupted = onShortcutInterrupted
        logger.notice("start: installing event tap for \(self.shortcuts.count, privacy: .public) shortcut(s)")

        return installEventTap()
    }

    func stop() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        shortcuts = [:]
        interruptibleActions = []
        onKeyDown = nil
        onKeyUp = nil
        onShortcutInterrupted = nil
    }

    private func installEventTap() -> Bool {
        guard Self.ensureListenEventAccessForMonitoring() else {
            logger.error("installEventTap: listen-event access is not granted")
            return false
        }

        guard Self.ensureAccessibilityAccessForMonitoring() else {
            logger.error("installEventTap: accessibility access is not granted")
            return false
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.resetPressedShortcutsAfterTapInterruption()
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let shouldSuppress = monitor.handleCGEvent(type: type, event: event)
            return shouldSuppress ? nil : Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("installEventTap: CGEvent.tapCreate failed")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            logger.error("installEventTap: failed to create run loop source")
            return false
        }

        self.eventTap = eventTap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("installEventTap: installed")
        return true
    }

    static func preflightListenEventAccess() -> Bool {
        InputMonitoringPermission.isGranted()
    }

    @discardableResult
    static func requestListenEventAccess() -> Bool {
        InputMonitoringPermission.requestAccess()
    }

    static func preflightAccessibilityAccess() -> Bool {
        AccessibilityPermission.isGranted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        AccessibilityPermission.requestAccess()
    }

    private static func ensureListenEventAccessForMonitoring() -> Bool {
        if preflightListenEventAccess() {
            return true
        }

        guard !hasRequestedListenEventAccess else {
            return false
        }

        hasRequestedListenEventAccess = true
        return requestListenEventAccess()
    }

    private static func ensureAccessibilityAccessForMonitoring() -> Bool {
        if preflightAccessibilityAccess() {
            return true
        }

        guard !hasRequestedAccessibilityAccess else {
            return false
        }

        hasRequestedAccessibilityAccess = true
        return requestAccessibilityAccess()
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard let eventKind = EventKind(type) else {
            return false
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handleEvent(
            kind: eventKind,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventTime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func resetPressedShortcutsAfterTapInterruption() {
        let eventTime = ProcessInfo.processInfo.systemUptime
        let pressedActions = shortcuts.compactMap { action, state in
            state.isDown ? action : nil
        }

        guard !pressedActions.isEmpty else {
            return
        }

        for action in pressedActions {
            if var state = shortcuts[action] {
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
            }
            dispatchKeyUp(for: action, eventTime: eventTime)
        }
    }

    private func handleEvent(
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) -> Bool {
        var shouldSuppress = false

        if kind == .keyDown {
            handleShortcutInterruptions(keyCode: keyCode, eventTime: eventTime)
        }

        for action in Array(shortcuts.keys) {
            guard var state = shortcuts[action] else {
                continue
            }

            if state.shortcut.isModifierOnly {
                handleModifierOnlyShortcut(
                    action: action,
                    state: state,
                    kind: kind,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    eventTime: eventTime
                )
                continue
            }

            let transition = transitionForKeyShortcut(
                state.shortcut,
                isDown: state.isDown,
                kind: kind,
                keyCode: keyCode,
                modifierFlags: modifierFlags
            )

            switch transition {
            case .none:
                break
            case .suppress:
                shouldSuppress = true
            case .keyDown:
                state.isDown = true
                state.pressedAt = eventTime
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyDown(for: action, eventTime: eventTime)
            case .keyUp:
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                shouldSuppress = true
                dispatchKeyUp(for: action, eventTime: eventTime)
            }
        }

        return shouldSuppress
    }

    private enum ShortcutTransition {
        case none
        case suppress
        case keyDown
        case keyUp
    }

    private func transitionForKeyShortcut(
        _ shortcut: Shortcut,
        isDown: Bool,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutTransition {
        switch kind {
        case .keyDown:
            guard shortcut.matchesKeyEvent(keyCode: keyCode, modifierFlags: modifierFlags) else {
                return .none
            }

            return isDown ? .suppress : .keyDown
        case .keyUp:
            return isDown && keyCode == shortcut.keyCode ? .keyUp : .none
        case .flagsChanged:
            guard isDown else {
                return .none
            }

            let currentFlags = Shortcut.normalizedModifierFlags(
                modifierFlags,
                forKeyCode: shortcut.keyCode
            )
            return currentFlags.isSuperset(of: shortcut.modifierFlags) ? .suppress : .keyUp
        }
    }

    private func handleModifierOnlyShortcut(
        action: ShortcutAction,
        state: ShortcutState,
        kind: EventKind,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventTime: TimeInterval
    ) {
        var state = state

        guard kind == .flagsChanged else {
            return
        }

        if state.isDown {
            if state.shortcut.shouldReleaseModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
                state.isDown = false
                state.pressedAt = nil
                state.isInterrupted = false
                shortcuts[action] = state
                dispatchKeyUp(for: action, eventTime: eventTime)
            }

            return
        }

        if state.shortcut.matchesModifierEvent(keyCode: keyCode, modifierFlags: modifierFlags) {
            state.isDown = true
            state.pressedAt = eventTime
            state.isInterrupted = false
            shortcuts[action] = state
            dispatchKeyDown(for: action, eventTime: eventTime)
        }
    }

    private func handleShortcutInterruptions(keyCode: UInt16, eventTime: TimeInterval) {
        guard !Shortcut.isModifierKeyCode(keyCode) else {
            return
        }

        for action in interruptibleActions {
            guard var state = shortcuts[action],
                  state.isDown,
                  !state.isInterrupted,
                  let pressedAt = state.pressedAt,
                  eventTime - pressedAt <= Self.shortcutInterruptionWindow,
                  state.shortcut.isInterruptedByAdditionalKeyDown(keyCode: keyCode)
            else {
                continue
            }

            state.isInterrupted = true
            shortcuts[action] = state
            dispatchShortcutInterrupted(for: action, eventTime: eventTime)
        }
    }

    private func dispatchKeyDown(for action: ShortcutAction, eventTime: TimeInterval) {
        logger.notice("dispatchKeyDown: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onKeyDown] in
            onKeyDown?(action, eventTime)
        }
    }

    private func dispatchKeyUp(for action: ShortcutAction, eventTime: TimeInterval) {
        logger.notice("dispatchKeyUp: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onKeyUp] in
            onKeyUp?(action, eventTime)
        }
    }

    private func dispatchShortcutInterrupted(for action: ShortcutAction, eventTime: TimeInterval) {
        logger.notice("dispatchShortcutInterrupted: action=\(action.storageName, privacy: .public)")
        DispatchQueue.main.async { [onShortcutInterrupted] in
            onShortcutInterrupted?(action, eventTime)
        }
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << Int(type.rawValue))
    }
}

private extension ShortcutMonitor.EventKind {
    init?(_ type: CGEventType) {
        switch type {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }
}
