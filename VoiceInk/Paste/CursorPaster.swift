import Foundation
import AppKit
import Carbon
import os
import VoiceInkCore

class CursorPaster {
    fileprivate typealias ClipboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    fileprivate typealias ClipboardSnapshot = [ClipboardItemSnapshot]
    private static let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.cursorPaster
    )
    // Let target apps observe modifier release before the synthesized Cmd-V chord.
    private static let prePasteDelay: TimeInterval = 0.1
    private static let pasteShortcutEventDelay: TimeInterval = 0.01
    @MainActor private static var pasteCommandPosterForTesting: ((Bool) async -> PasteResult)?
    @MainActor private static var accessibilityTextInserterForTesting:
        ((String, CursorTextContextReader.PreparedContext?) -> CursorTextContextReader.SelectedTextInsertionResult)?

    struct PreparedPasteContext {
        fileprivate let changeCount: Int
        fileprivate let savedContents: ClipboardSnapshot
    }

    enum PasteResult: Equatable {
        case textInserted
        case commandPosted
        case commandDeliveryUncertain
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }

        var didDeliverText: Bool {
            self == .textInserted || self == .commandPosted
        }
    }

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    static func preparedTextForPaste(_ text: String) -> String {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(text)
        return plan.text(
            beforeCursor: plan.shouldReadCursorContext ? CursorTextContextReader.textBeforeCursor() : nil
        )
    }

    @MainActor
    static func preparedTextForPaste(
        _ text: String,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>?
    ) async -> String {
        let plan = VoiceInkTranscriptionPasteOutputPolicy.cursorPasteTextPlan(text)
        guard plan.shouldReadCursorContext else { return text }

        let beforeCursor = if let preparedCursorTextContext {
            CursorTextContextReader.textBeforeCursor(
                preparedContext: await preparedCursorTextContext.value
            )
        } else {
            CursorTextContextReader.textBeforeCursor()
        }
        return plan.text(beforeCursor: beforeCursor)
    }

    @MainActor
    static func configurePasteCommandPosterForTesting(
        _ poster: ((Bool) async -> PasteResult)? = nil
    ) {
        pasteCommandPosterForTesting = poster
    }

    @MainActor
    static func configureAccessibilityTextInserterForTesting(
        _ inserter: (
            (String, CursorTextContextReader.PreparedContext?)
                -> CursorTextContextReader.SelectedTextInsertionResult
        )? = nil
    ) {
        accessibilityTextInserterForTesting = inserter
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) -> Task<PasteResult, Never> {
        let traceToken = latencyTraceToken ?? VoiceInkLatencyTrace.shared.currentToken()
        return Task { @MainActor in
            await performPasteSession(
                text,
                preparedContext: preparedContext,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: traceToken
            )
        }
    }

    @MainActor
    static func pasteAtCursorAndWaitUntilPosted(_ text: String) async -> PasteResult {
        await startPasteAtCursor(text).value
    }

    @MainActor
    static func preparePasteContext() -> PreparedPasteContext? {
        guard VoiceInkPastePreference.shouldRestoreClipboardAfterPaste() else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        return PreparedPasteContext(
            changeCount: pasteboard.changeCount,
            savedContents: snapshotClipboard(from: pasteboard)
        )
    }

    @MainActor
    static func preflightPasteAuthorization() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    private static func performPasteSession(
        _ text: String,
        preparedContext: PreparedPasteContext? = nil,
        preparedCursorTextContext: Task<CursorTextContextReader.PreparedContext?, Never>? = nil,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        let latencyTrace = VoiceInkLatencyTrace.shared
        let pasteboard = NSPasteboard.general
        let shouldRestoreClipboard = VoiceInkPastePreference.shouldRestoreClipboardAfterPaste()
        var shouldRetryCommandVMenuDiscovery = false
        let cursorContext = if VoiceInkPasteMethod.current() == .standard {
            await preparedCursorTextContext?.value
        } else {
            nil as CursorTextContextReader.PreparedContext?
        }
        latencyTrace.event(
            "paste_session.enter",
            details: "chars=\(text.count) restoreClipboard=\(shouldRestoreClipboard) method=\(VoiceInkPasteMethod.current().rawValue)",
            token: latencyTraceToken
        )
        if VoiceInkPasteMethod.current() == .standard,
           accessibilityTextInserterForTesting != nil || pasteCommandPosterForTesting == nil {
            let insertionSpan = latencyTrace.begin(
                "paste_session.accessibility_insert",
                token: latencyTraceToken
            )
            let insertionResult = if let accessibilityTextInserterForTesting {
                accessibilityTextInserterForTesting(text, cursorContext)
            } else {
                CursorTextContextReader.insertSelectedText(
                    text,
                    preparedContext: cursorContext
                )
            }
            latencyTrace.end(
                insertionSpan,
                details: "result=\(insertionResult.rawValue)"
            )
            shouldRetryCommandVMenuDiscovery = insertionResult.shouldRetryCommandVMenuDiscovery
            if insertionResult.didInsert {
                latencyTrace.event(
                    "paste_text_inserted",
                    details: "method=\(insertionResult.method ?? "accessibility")",
                    token: latencyTraceToken
                )
                return .textInserted
            }
        }

        let clipboardSnapshotSpan = latencyTrace.begin(
            "paste_session.snapshot_clipboard",
            token: latencyTraceToken
        )
        let savedContents: ClipboardSnapshot = if shouldRestoreClipboard {
            if let preparedContext,
               preparedContext.changeCount == pasteboard.changeCount {
                preparedContext.savedContents
            } else {
                snapshotClipboard(from: pasteboard)
            }
        } else {
            []
        }
        latencyTrace.end(
            clipboardSnapshotSpan,
            details: "items=\(savedContents.count)"
        )
        let sessionID = UUID().uuidString

        let clipboardWriteSpan = latencyTrace.begin(
            "paste_session.write_clipboard",
            token: latencyTraceToken
        )
        guard ClipboardManager.setClipboard(
            text,
            transient: shouldRestoreClipboard,
            sessionID: shouldRestoreClipboard ? sessionID : nil
        ) else {
            latencyTrace.end(clipboardWriteSpan, details: "result=failure")
            logger.error("\(VoiceInkPasteDiagnostics.failedToPrepareClipboardMessage, privacy: .public)")
            return .commandNotPosted
        }
        latencyTrace.end(clipboardWriteSpan, details: "result=success")

        let commandSpan = latencyTrace.begin("paste_session.post_command", token: latencyTraceToken)
        let pasteResult = await postPasteCommand(
            expectedText: text,
            retryCommandVMenuDiscovery: shouldRetryCommandVMenuDiscovery,
            preparedCursorTextContext: cursorContext,
            latencyTraceToken: latencyTraceToken
        )
        latencyTrace.end(
            commandSpan,
            details: "result=\(String(describing: pasteResult))"
        )
        if shouldRestoreClipboard, pasteResult.didPostPasteCommand {
            latencyTrace.event(
                "paste_session.restore_scheduled",
                details: "delayMs=\(String(format: "%.1f", VoiceInkPastePreference.boundedClipboardRestoreDelay() * 1_000))",
                token: latencyTraceToken
            )
            scheduleClipboardRestore(
                savedContents,
                expectedText: text,
                sessionID: sessionID,
                on: pasteboard,
                latencyTraceToken: latencyTraceToken
            )
        } else if shouldRestoreClipboard {
            latencyTrace.event(
                "paste_session.restore_skipped",
                details: "reason=\(String(describing: pasteResult))",
                token: latencyTraceToken
            )
            if pasteResult == .commandNotPosted {
                logger.notice("\(VoiceInkPasteDiagnostics.skippedClipboardRestoreCommandNotPostedMessage, privacy: .public)")
            }
        }

        return pasteResult
    }

    private static func snapshotClipboard(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        }
    }

    @MainActor
    private static func postPasteCommand(
        expectedText: String,
        retryCommandVMenuDiscovery: Bool,
        preparedCursorTextContext: CursorTextContextReader.PreparedContext?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        if let pasteCommandPosterForTesting {
            return await pasteCommandPosterForTesting(retryCommandVMenuDiscovery)
        }

        if VoiceInkPasteMethod.current() == .appleScript {
            let didPost = pasteUsingAppleScript()
            if didPost {
                VoiceInkLatencyTrace.shared.event(
                    "paste_event_posted",
                    details: "method=appleScript",
                    token: latencyTraceToken
                )
            }
            return didPost ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard(
                expectedText: expectedText,
                retryCommandVMenuDiscovery: retryCommandVMenuDiscovery,
                preparedCursorTextContext: preparedCursorTextContext,
                latencyTraceToken: latencyTraceToken
            )
        }
    }

    private static func scheduleClipboardRestore(
        _ savedContents: ClipboardSnapshot,
        expectedText: String,
        sessionID: String,
        on pasteboard: NSPasteboard,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) {
        let delay = VoiceInkPastePreference.boundedClipboardRestoreDelay()

        Task { @MainActor in
            await wait(delay)
            guard pasteboardStillOwnedByPasteSession(pasteboard, expectedText: expectedText, sessionID: sessionID) else {
                VoiceInkLatencyTrace.shared.event(
                    "paste_session.restore_skipped",
                    details: "reason=clipboard_changed",
                    token: latencyTraceToken
                )
                return
            }
            pasteboard.clearContents()
            if !savedContents.isEmpty {
                pasteboard.writeObjects(pasteboardItems(from: savedContents))
            }
            VoiceInkLatencyTrace.shared.event(
                "paste_session.restore_executed",
                details: "items=\(savedContents.count)",
                token: latencyTraceToken
            )
        }
    }

    private static func pasteboardStillOwnedByPasteSession(
        _ pasteboard: NSPasteboard,
        expectedText: String,
        sessionID: String
    ) -> Bool {
        pasteboard.string(forType: .string) == expectedText &&
            pasteboard.string(forType: ClipboardManager.pasteSessionType) == sessionID
    }

    private static func pasteboardItems(from snapshot: ClipboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript("tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode   = makeScript("tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("\(VoiceInkPasteDiagnostics.appleScriptPasteScriptUnavailableMessage, privacy: .public)")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = VoiceInkPasteDiagnostics.appleScriptPasteFailedMessage(
                errorDescription: String(describing: error)
            )
            logger.error("\(message, privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard(
        expectedText: String,
        retryCommandVMenuDiscovery: Bool,
        preparedCursorTextContext: CursorTextContextReader.PreparedContext?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> PasteResult {
        VoiceInkLatencyTrace.shared.event(
            "paste_cgevent.enter",
            token: latencyTraceToken
        )
        guard AXIsProcessTrusted() else {
            VoiceInkLatencyTrace.shared.event(
                "paste_cgevent.accessibility_denied",
                token: latencyTraceToken
            )
            logger.error(
                "\(VoiceInkPasteDiagnostics.accessibilityPermissionRequiredForSimulatedPasteMessage, privacy: .public)"
            )
            return .commandNotPosted
        }

        guard !Task.isCancelled else { return .commandNotPosted }
        // AX menu actions do not synthesize modifiers, so they need no key-release delay.
        let menuAttempt = await CursorTextContextReader.pressFocusedCommandVMenuItem(
            retryIfUnavailable: retryCommandVMenuDiscovery,
            preparedContext: preparedCursorTextContext,
            latencyTraceToken: latencyTraceToken
        )
        let stableTarget: CursorTextContextReader.FocusedPasteTarget?
        switch menuAttempt {
        case .pressed(let targetProcessIdentifier):
            VoiceInkLatencyTrace.shared.event(
                "paste_event_posted",
                details: "method=accessibilityMenuCommandV targetPid=\(targetProcessIdentifier)",
                token: latencyTraceToken
            )
            return .commandPosted
        case .targetChanged(let targetProcessIdentifier):
            VoiceInkLatencyTrace.shared.event(
                "paste_event_delivery_uncertain",
                details: "method=accessibilityMenuCommandV reason=targetChanged targetPid=\(targetProcessIdentifier.map { String($0) } ?? "unknown")",
                token: latencyTraceToken
            )
            return .commandDeliveryUncertain
        case .unavailable(let target):
            stableTarget = target
        }
        guard !Task.isCancelled else { return .commandNotPosted }
        if retryCommandVMenuDiscovery {
            guard let stableTarget else { return .commandNotPosted }
            await wait(prePasteDelay)
            if let keyboardPaste = await CursorTextContextReader.postFocusedCommandVShortcut(
                target: stableTarget,
                expectedText: expectedText,
                latencyTraceToken: latencyTraceToken
            ) {
                switch keyboardPaste.disposition {
                case .delivered:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_posted",
                        details: "method=globalHIDCommandV targetPid=\(keyboardPaste.processIdentifier) disposition=\(keyboardPaste.disposition.rawValue)",
                        token: latencyTraceToken
                    )
                    return .commandPosted
                case .deliveryUncertain:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_delivery_uncertain",
                        details: "method=globalHIDCommandV targetPid=\(keyboardPaste.processIdentifier)",
                        token: latencyTraceToken
                    )
                    return .commandDeliveryUncertain
                }
            }
            guard !Task.isCancelled else { return .commandNotPosted }
            if let contextMenuPaste = await CursorTextContextReader.pressFocusedContextMenuPasteItem(
                target: stableTarget,
                expectedText: expectedText,
               latencyTraceToken: latencyTraceToken
            ) {
                if Task.isCancelled {
                    return .commandDeliveryUncertain
                }
                switch contextMenuPaste.disposition {
                case .delivered:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_posted",
                        details: "method=accessibilityContextMenu targetPid=\(contextMenuPaste.processIdentifier) disposition=\(contextMenuPaste.disposition.rawValue)",
                        token: latencyTraceToken
                    )
                    return .commandPosted
                case .deliveryUncertain:
                    VoiceInkLatencyTrace.shared.event(
                        "paste_event_delivery_uncertain",
                        details: "method=accessibilityContextMenu targetPid=\(contextMenuPaste.processIdentifier)",
                        token: latencyTraceToken
                    )
                    return .commandDeliveryUncertain
                }
            }
            VoiceInkLatencyTrace.shared.event(
                "paste_event_not_posted",
                details: "reason=safeBrowserMethodUnavailable targetPid=\(stableTarget.processIdentifier)",
                token: latencyTraceToken
            )
            return .commandNotPosted
        }
        await wait(prePasteDelay)
        guard !Task.isCancelled else { return .commandNotPosted }
        let targetProcessIdentifier = CursorTextContextReader.focusedProcessIdentifierForPaste()
        // VoiceInk posts from the active login session, so share that session's
        // accumulated keyboard state instead of creating an isolated private state.
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            logger.error("\(VoiceInkPasteDiagnostics.failedToCreateCommandVPasteEventsMessage, privacy: .public)")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags   = .maskCommand
        vUp.flags     = .maskCommand

        let events = [cmdDown, vDown, vUp, cmdUp]
        for (index, event) in events.enumerated() {
            if let targetProcessIdentifier {
                event.postToPid(targetProcessIdentifier)
            } else {
                event.post(tap: .cghidEventTap)
            }
            if index < events.count - 1 {
                await wait(pasteShortcutEventDelay)
            }
        }
        VoiceInkLatencyTrace.shared.event(
            "paste_event_posted",
            details: targetProcessIdentifier.map {
                "method=cgEvent source=combinedSession targetPid=\($0)"
            } ?? "method=cgEvent source=combinedSession target=global",
            token: latencyTraceToken
        )

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Auto Send Keys

    static func performAutoSend(_ key: VoiceInkAutoSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags   = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags   = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
