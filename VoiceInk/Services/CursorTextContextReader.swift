import AppKit
import Foundation
import VoiceInkCore

enum CursorTextContextReader {
    private static let webAreaRole = "AXWebArea"
    // Bound malformed Accessibility parent chains without missing deeply nested web editors.
    private static let insertionAncestorTraversalLimit = 64
    private static let commandVMenuTraversalLimit = 2_048
    // Give cold web-editor Accessibility menu discovery one bounded retry.
    private static let commandVMenuTraversalAttempts = 2
    private static let commandVMenuTraversalRetryDelay: TimeInterval = 0.25
    private static let commandVMenuTraversalTimeout: TimeInterval = 0.25
    private static let contextMenuTraversalAttempts = 4
    private static let contextMenuTraversalRetryDelay: TimeInterval = 0.05
    private static let pasteDeliveryObservationAttempts = 6
    private static let pasteDeliveryObservationDelay: TimeInterval = 0.05

    enum SelectedTextInsertionResult: String {
        case inserted
        case insertedWithoutSelection
        case insertedViaValue
        case insertedViaValueWithoutSelection
        case unsupported
        case notApplied

        var didInsert: Bool {
            switch self {
            case .inserted, .insertedWithoutSelection, .insertedViaValue,
                 .insertedViaValueWithoutSelection:
                true
            case .unsupported, .notApplied:
                false
            }
        }

        var method: String? {
            switch self {
            case .inserted:
                "accessibilitySelectedText"
            case .insertedWithoutSelection:
                "accessibilitySelectedTextSelectionUnverified"
            case .insertedViaValue:
                "accessibilityValue"
            case .insertedViaValueWithoutSelection:
                "accessibilityValueSelectionUnverified"
            case .unsupported, .notApplied:
                nil
            }
        }

        var shouldRetryCommandVMenuDiscovery: Bool {
            self == .unsupported
        }
    }

    enum PasteDeliveryDisposition: String, Equatable {
        case delivered
        case deliveryUncertain
    }

    struct ContextMenuPasteResult {
        let processIdentifier: pid_t
        let disposition: PasteDeliveryDisposition
    }

    struct CommandVShortcutPasteResult {
        let processIdentifier: pid_t
        let disposition: PasteDeliveryDisposition
    }

    private struct ContextMenuAnchor {
        let point: CGPoint
        let boundsMethod: String
    }

    private struct ContextMenuBoundsProbe {
        let bounds: CGRect?
        let details: String
    }

    struct ContextMenuNeighborRanges {
        let previousOuter: CFRange?
        let previous: CFRange?
        let next: CFRange?
        let nextOuter: CFRange?
    }

    @MainActor
    final class FocusedPasteTarget: Sendable {
        fileprivate let focusedElement: AXUIElement
        let processIdentifier: pid_t
        fileprivate let text: String?
        fileprivate let selectedRange: CFRange?

        fileprivate init(
            focusedElement: AXUIElement,
            processIdentifier: pid_t,
            text: String?,
            selectedRange: CFRange?
        ) {
            self.focusedElement = focusedElement
            self.processIdentifier = processIdentifier
            self.text = text
            self.selectedRange = selectedRange
        }
    }

    enum CommandVMenuAttempt {
        case pressed(pid_t)
        case unavailable(FocusedPasteTarget?)
        case targetChanged(pid_t?)
    }

    @MainActor
    final class PreparedContext: Sendable {
        fileprivate let focusedElement: AXUIElement
        fileprivate let selectedRange: CFRange?
        fileprivate let text: String?

        fileprivate init(
            focusedElement: AXUIElement,
            selectedRange: CFRange?,
            text: String?
        ) {
            self.focusedElement = focusedElement
            self.selectedRange = selectedRange
            self.text = text
        }
    }

    @MainActor
    static func textBeforeCursor(
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> String? {
        guard VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: maximumLength),
              AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = focusedElement(from: systemWideElement),
              let prefix = textBeforeCursor(in: focusedElement, maximumLength: maximumLength) else {
            return nil
        }

        return prefix
    }

    @MainActor
    static func prepareTextBeforeCursor(
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> PreparedContext? {
        guard VoiceInkCursorTextContextPolicy.shouldAttemptRead(maximumLength: maximumLength),
              AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = focusedElement(from: systemWideElement) else {
            return nil
        }
        return PreparedContext(
            focusedElement: focusedElement,
            selectedRange: selectedTextRange(from: focusedElement),
            text: textBeforeCursor(in: focusedElement, maximumLength: maximumLength)
        )
    }

    @MainActor
    static func textBeforeCursor(
        preparedContext: PreparedContext?,
        maximumLength: Int = VoiceInkCursorTextContextPolicy.defaultMaximumLength
    ) -> String? {
        guard let preparedContext,
              AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()),
              CFEqual(focusedElement, preparedContext.focusedElement),
              preparedContext.selectedRange != nil,
              preparedContext.text != nil,
              sameRange(
                selectedTextRange(from: focusedElement),
                preparedContext.selectedRange
              ) else {
            return textBeforeCursor(maximumLength: maximumLength)
        }
        return preparedContext.text
    }

    @MainActor
    static func focusedProcessIdentifierForPaste() -> pid_t? {
        guard AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return nil
        }
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(focusedElement, &processIdentifier) == .success else {
            return nil
        }
        guard processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return processIdentifier
    }

    @MainActor
    static func pressFocusedCommandVMenuItem(
        retryIfUnavailable: Bool,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> CommandVMenuAttempt {
        guard AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return .unavailable(nil)
        }
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(focusedElement, &processIdentifier) == .success,
              processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .unavailable(nil)
        }
        let target = FocusedPasteTarget(
            focusedElement: focusedElement,
            processIdentifier: processIdentifier,
            text: textValue(from: focusedElement),
            selectedRange: selectedTextRange(from: focusedElement)
        )
        let application = AXUIElementCreateApplication(processIdentifier)

        let traversalAttempts = retryIfUnavailable ? commandVMenuTraversalAttempts : 1
        for attempt in 0..<traversalAttempts {
            guard !Task.isCancelled,
                  pasteTargetIsCurrent(target) else {
                return .targetChanged(processIdentifier)
            }
            guard let menuBar = elementAttribute(
                kAXMenuBarAttribute as CFString,
                from: application
            ) else {
                VoiceInkLatencyTrace.shared.event(
                    "paste_command_v_menu_lookup",
                    details: "attempt=\(attempt + 1) result=noMenuBar",
                    token: latencyTraceToken
                )
                guard attempt < traversalAttempts - 1 else {
                    return .unavailable(target)
                }
                // Let the Accessibility server process cold menu discovery before retrying.
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(commandVMenuTraversalRetryDelay * 1_000_000_000)
                    )
                } catch {
                    return .targetChanged(processIdentifier)
                }
                continue
            }
            let searchResult = plainCommandVMenuItem(in: menuBar)
            VoiceInkLatencyTrace.shared.event(
                "paste_command_v_menu_lookup",
                details: "attempt=\(attempt + 1) result=\(searchResult.menuItem == nil ? "missing" : "found") visited=\(searchResult.visitedNodes) enqueued=\(searchResult.enqueuedNodes) candidates=\(searchResult.shortcutCandidates) disabled=\(searchResult.disabledShortcutCandidates) limitExhausted=\(searchResult.limitExhausted) timeout=\(searchResult.timedOut)",
                token: latencyTraceToken
            )
            if let menuItem = searchResult.menuItem {
                // The app's plain Cmd-V command is target-affine, unlike a global key event.
                guard !Task.isCancelled,
                      pasteTargetIsCurrent(target) else {
                    return .targetChanged(processIdentifier)
                }
                guard AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success else {
                    return .unavailable(target)
                }
                return .pressed(processIdentifier)
            }
            guard attempt < traversalAttempts - 1 else {
                return .unavailable(target)
            }
            guard pasteTargetIsCurrent(target) else {
                return .targetChanged(processIdentifier)
            }
            // Let the Accessibility server process cold menu discovery before retrying.
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(commandVMenuTraversalRetryDelay * 1_000_000_000)
                )
            } catch {
                return .targetChanged(processIdentifier)
            }
        }
        return .unavailable(target)
    }

    static func commandVShortcutEvents(source: CGEventSource?) -> [CGEvent]? {
        guard let commandDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x37,
            keyDown: true
        ), let vDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09,
            keyDown: true
        ), let vUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09,
            keyDown: false
        ), let commandUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x37,
            keyDown: false
        ) else {
            return nil
        }
        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandUp.flags = []
        return [commandDown, vDown, vUp, commandUp]
    }

    static func postCommandVShortcutEvents(
        _ events: [CGEvent],
        targetIsCurrent: () -> Bool,
        post: (CGEvent) -> Void
    ) -> Bool {
        guard events.count == 4, targetIsCurrent() else { return false }
        post(events[0])
        guard targetIsCurrent() else {
            post(events[3])
            return false
        }
        for event in events.dropFirst() {
            post(event)
        }
        return true
    }

    @MainActor
    static func postFocusedCommandVShortcut(
        target: FocusedPasteTarget,
        expectedText: String,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> CommandVShortcutPasteResult? {
        guard !Task.isCancelled,
              !expectedText.isEmpty,
              AXIsProcessTrusted() else {
            return nil
        }
        let processIdentifier = target.processIdentifier
        guard pasteTargetIsCurrent(target),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == processIdentifier else {
            return CommandVShortcutPasteResult(
                processIdentifier: processIdentifier,
                disposition: .deliveryUncertain
            )
        }
        guard let events = commandVShortcutEvents(
            source: CGEventSource(stateID: .combinedSessionState)
        ) else {
            return nil
        }

        // Chromium needs the normal window-server route. Recheck after Command-down,
        // then post V and both releases without an actor suspension between events.
        let postedPaste = postCommandVShortcutEvents(
            events,
            targetIsCurrent: {
                !Task.isCancelled
                    && pasteTargetIsCurrent(target)
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier
                        == processIdentifier
            },
            post: { $0.post(tap: .cghidEventTap) }
        )
        guard postedPaste else {
            VoiceInkLatencyTrace.shared.event(
                "paste_command_v_keyboard_aborted",
                details: "reason=targetChangedOrCancelled targetPid=\(processIdentifier)",
                token: latencyTraceToken
            )
            return CommandVShortcutPasteResult(
                processIdentifier: processIdentifier,
                disposition: .deliveryUncertain
            )
        }
        VoiceInkLatencyTrace.shared.event(
            "paste_command_v_keyboard_delivery",
            details: "method=globalHID source=combinedSession targetPid=\(processIdentifier) eventCount=\(events.count)",
            token: latencyTraceToken
        )
        let delivered = await pasteWasObserved(
            focusedElement: target.focusedElement,
            processIdentifier: processIdentifier,
            textBeforePaste: target.text,
            selectedRangeBeforePaste: target.selectedRange,
            expectedText: expectedText
        )
        let disposition: PasteDeliveryDisposition = delivered
            ? .delivered
            : .deliveryUncertain
        VoiceInkLatencyTrace.shared.event(
            "paste_command_v_keyboard_observation",
            details: "targetPid=\(processIdentifier) disposition=\(disposition.rawValue)",
            token: latencyTraceToken
        )
        return CommandVShortcutPasteResult(
            processIdentifier: processIdentifier,
            disposition: disposition
        )
    }

    @MainActor
    static func pressFocusedContextMenuPasteItem(
        target: FocusedPasteTarget,
        expectedText: String,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async -> ContextMenuPasteResult? {
        guard !Task.isCancelled,
              !expectedText.isEmpty,
              AXIsProcessTrusted() else {
            return nil
        }
        let focusedElement = target.focusedElement
        let processIdentifier = target.processIdentifier
        guard processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        guard pasteTargetIsCurrent(target) else {
            return ContextMenuPasteResult(
                processIdentifier: processIdentifier,
                disposition: .deliveryUncertain
            )
        }

        guard let textBeforePaste = target.text,
              let selectedRangeBeforePaste = target.selectedRange else {
            return nil
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        let menusBeforeShow = menuSnapshots(in: application)
        let applicationSearch = plainCommandVMenuItem(in: application)
        guard capturedEditorIsFocused(
            focusedElement,
            processIdentifier: processIdentifier
        ) else {
            VoiceInkLatencyTrace.shared.event(
                "paste_context_menu_aborted",
                details: "reason=focusChangedBeforeTrigger targetPid=\(processIdentifier)",
                token: latencyTraceToken
            )
            return ContextMenuPasteResult(
                processIdentifier: processIdentifier,
                disposition: .deliveryUncertain
            )
        }

        let showResult = performShowMenuAction(
            startingAt: focusedElement,
            processIdentifier: processIdentifier
        )
        VoiceInkLatencyTrace.shared.event(
            "paste_context_menu_show",
            details: "method=elementAccessibility targetPid=\(processIdentifier) result=\(showResult.rawValue)",
            token: latencyTraceToken
        )
        let contextMenuPoint: CGPoint?
        if showResult != .success {
            let anchor = postCaretContextMenuClick(
                to: target,
                latencyTraceToken: latencyTraceToken
            )
            VoiceInkLatencyTrace.shared.event(
                "paste_context_menu_show",
                details: "method=caretRightClick targetPid=\(processIdentifier) bounds=\(anchor?.boundsMethod ?? "unavailable") result=\(anchor == nil ? "unavailable" : "posted")",
                token: latencyTraceToken
            )
            guard let anchor else { return nil }
            contextMenuPoint = anchor.point
        } else {
            contextMenuPoint = nil
        }

        for attempt in 0..<contextMenuTraversalAttempts {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(contextMenuTraversalRetryDelay * 1_000_000_000)
                )
            } catch {
                cancelMenus(contextMenuElements(
                    in: application,
                    since: menusBeforeShow,
                    triggerPoint: contextMenuPoint
                ))
                return ContextMenuPasteResult(
                    processIdentifier: processIdentifier,
                    disposition: .deliveryUncertain
                )
            }
            let contextMenus = contextMenuElements(
                in: application,
                since: menusBeforeShow,
                triggerPoint: contextMenuPoint
            )
            guard !Task.isCancelled,
                  capturedEditorIsFocused(
                    focusedElement,
                    processIdentifier: processIdentifier
                  ) else {
                cancelMenus(contextMenus)
                return ContextMenuPasteResult(
                    processIdentifier: processIdentifier,
                    disposition: .deliveryUncertain
                )
            }
            let searchResults = contextMenus.map {
                plainCommandVMenuItem(
                    in: $0,
                    matchingTitles: applicationSearch.commandVShortcutTitles
                )
            }
            let searchResult = searchResults.first { $0.menuItem != nil }
                ?? searchResults.max { $0.visitedNodes < $1.visitedNodes }
            VoiceInkLatencyTrace.shared.event(
                "paste_context_menu_lookup",
                details: "attempt=\(attempt + 1) result=\(searchResult?.menuItem == nil ? "missing" : "found") activatedMenus=\(contextMenus.count) visited=\(searchResult?.visitedNodes ?? 0) enqueued=\(searchResult?.enqueuedNodes ?? 0) candidates=\(searchResult?.shortcutCandidates ?? 0) disabled=\(searchResult?.disabledShortcutCandidates ?? 0) titleFallbacks=\(searchResult?.titleFallbackCandidates ?? 0) limitExhausted=\(searchResult?.limitExhausted ?? false) timeout=\(searchResult?.timedOut ?? false)",
                token: latencyTraceToken
            )
            if let menuItem = searchResult?.menuItem {
                guard !Task.isCancelled,
                      capturedEditorIsFocused(
                        focusedElement,
                        processIdentifier: processIdentifier
                      ),
                      textValue(from: focusedElement) == textBeforePaste,
                      sameRange(
                        selectedTextRange(from: focusedElement),
                        selectedRangeBeforePaste
                      ) else {
                    cancelMenus(contextMenus)
                    return ContextMenuPasteResult(
                        processIdentifier: processIdentifier,
                        disposition: .deliveryUncertain
                    )
                }
                let pressResult = AXUIElementPerformAction(
                    menuItem,
                    kAXPressAction as CFString
                )
                VoiceInkLatencyTrace.shared.event(
                    "paste_context_menu_press",
                    details: "targetPid=\(processIdentifier) result=\(pressResult.rawValue) role=\(role(from: menuItem) ?? "unknown") title=\(normalizedMenuTitle(stringAttribute(kAXTitleAttribute as CFString, from: menuItem)) ?? "unknown")",
                    token: latencyTraceToken
                )
                guard pressResult == .success else {
                    cancelMenus(contextMenus)
                    return ContextMenuPasteResult(
                        processIdentifier: processIdentifier,
                        disposition: .deliveryUncertain
                    )
                }
                let delivered = await pasteWasObserved(
                    focusedElement: focusedElement,
                    processIdentifier: processIdentifier,
                    textBeforePaste: textBeforePaste,
                    selectedRangeBeforePaste: selectedRangeBeforePaste,
                    expectedText: expectedText
                )
                if !delivered {
                    cancelMenus(contextMenus)
                }
                return ContextMenuPasteResult(
                    processIdentifier: processIdentifier,
                    disposition: delivered ? .delivered : .deliveryUncertain
                )
            }
        }

        cancelMenus(contextMenuElements(
            in: application,
            since: menusBeforeShow,
            triggerPoint: contextMenuPoint
        ))
        return ContextMenuPasteResult(
            processIdentifier: processIdentifier,
            disposition: .deliveryUncertain
        )
    }

    private struct CommandVMenuSearchResult {
        let menuItem: AXUIElement?
        let visitedNodes: Int
        let enqueuedNodes: Int
        let shortcutCandidates: Int
        let disabledShortcutCandidates: Int
        let titleFallbackCandidates: Int
        let commandVShortcutTitles: Set<String>
        let limitExhausted: Bool
        let timedOut: Bool
    }

    struct CommandVMenuAttributes {
        static let names = [
            kAXRoleAttribute, kAXTitleAttribute, kAXMenuItemCmdCharAttribute,
            kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdModifiersAttribute,
            kAXEnabledAttribute, kAXChildrenAttribute,
        ]

        let role: String?
        let title: String?
        let commandCharacter: String?
        let virtualKey: Int?
        let modifiers: UInt32?
        let enabled: Bool
        let children: [AXUIElement]

        init(values: [Any]) {
            func value<T>(_ index: Int, as type: T.Type) -> T? {
                guard values.indices.contains(index) else { return nil }
                return values[index] as? T
            }
            // Unsupported attributes occupy their original slots as CFNull or AXError values.
            role = value(0, as: String.self)
            title = value(1, as: String.self)
            commandCharacter = value(2, as: String.self)
            virtualKey = value(3, as: NSNumber.self)?.intValue
            modifiers = value(4, as: NSNumber.self)?.uint32Value
            enabled = value(5, as: NSNumber.self)?.boolValue == true
            children = value(6, as: [AXUIElement].self) ?? []
        }
    }

    static func commandVMenuAttributes(
        from element: AXUIElement,
        copyMultiple: (
            AXUIElement, CFArray, AXCopyMultipleAttributeOptions, UnsafeMutablePointer<CFArray?>
        ) -> AXError = AXUIElementCopyMultipleAttributeValues,
        copySingle: (
            AXUIElement, CFString, UnsafeMutablePointer<CFTypeRef?>
        ) -> AXError = AXUIElementCopyAttributeValue
    ) -> CommandVMenuAttributes {
        var values: CFArray?
        let result = copyMultiple(
            element,
            CommandVMenuAttributes.names as CFArray,
            [],
            &values
        )
        if result == .success,
           let values = values as? [Any],
           values.count == CommandVMenuAttributes.names.count {
            return CommandVMenuAttributes(values: values)
        }
        // A failed bulk read must not hide children that individual AX reads can still retrieve.
        return CommandVMenuAttributes(values: CommandVMenuAttributes.names.map { attribute in
            var value: CFTypeRef?
            guard copySingle(element, attribute as CFString, &value) == .success,
                  let value else { return NSNull() }
            return value
        })
    }

    private static func plainCommandVMenuItem(
        in menuBar: AXUIElement,
        matchingTitles: Set<String> = []
    ) -> CommandVMenuSearchResult {
        let deadline = Date().addingTimeInterval(commandVMenuTraversalTimeout)
        var queue = [menuBar]
        var index = 0
        var shortcutCandidates = 0
        var disabledShortcutCandidates = 0
        var shortcutTitles = matchingTitles
        var enabledTitledMenuItems: [(element: AXUIElement, title: String)] = []
        while index < queue.count,
              index < commandVMenuTraversalLimit,
              Date() < deadline {
            let element = queue[index]
            index += 1
            let attributes = commandVMenuAttributes(from: element)
            if attributes.role == kAXMenuItemRole as String {
                let title = attributes.title
                let commandCharacter = attributes.commandCharacter
                let virtualKey = attributes.virtualKey
                let modifiers = attributes.modifiers
                let enabled = attributes.enabled
                if isPlainCommandVShortcut(
                    commandCharacter: commandCharacter,
                    virtualKey: virtualKey,
                    modifiers: modifiers
                ) {
                    shortcutCandidates += 1
                    shortcutTitles = updatedCommandVShortcutTitles(
                        shortcutTitles,
                        adding: title
                    )
                    if enabled {
                        return CommandVMenuSearchResult(
                            menuItem: element,
                            visitedNodes: index,
                            enqueuedNodes: queue.count,
                            shortcutCandidates: shortcutCandidates,
                            disabledShortcutCandidates: disabledShortcutCandidates,
                            titleFallbackCandidates: 0,
                            commandVShortcutTitles: shortcutTitles,
                            limitExhausted: false,
                            timedOut: false
                        )
                    }
                    disabledShortcutCandidates += 1
                } else if enabled,
                          let normalizedTitle = normalizedMenuTitle(title) {
                    enabledTitledMenuItems.append((element, normalizedTitle))
                }
            }

            let remainingCapacity = commandVMenuTraversalLimit - queue.count
            guard remainingCapacity > 0 else { continue }
            queue.append(contentsOf: attributes.children.prefix(remainingCapacity))
        }
        let titleFallbackItems = enabledTitledMenuItems.filter {
            shortcutTitles.contains($0.title)
        }
        if let titleFallbackItem = titleFallbackItems.first {
            return CommandVMenuSearchResult(
                menuItem: titleFallbackItem.element,
                visitedNodes: index,
                enqueuedNodes: queue.count,
                shortcutCandidates: shortcutCandidates,
                disabledShortcutCandidates: disabledShortcutCandidates,
                titleFallbackCandidates: titleFallbackItems.count,
                commandVShortcutTitles: shortcutTitles,
                limitExhausted: false,
                timedOut: false
            )
        }
        let hasUnvisitedNodes = index < queue.count
        return CommandVMenuSearchResult(
            menuItem: nil,
            visitedNodes: index,
            enqueuedNodes: queue.count,
            shortcutCandidates: shortcutCandidates,
            disabledShortcutCandidates: disabledShortcutCandidates,
            titleFallbackCandidates: titleFallbackItems.count,
            commandVShortcutTitles: shortcutTitles,
            limitExhausted: hasUnvisitedNodes && index >= commandVMenuTraversalLimit,
            timedOut: hasUnvisitedNodes && Date() >= deadline
        )
    }

    private static func normalizedMenuTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func updatedCommandVShortcutTitles(
        _ titles: Set<String>,
        adding title: String?
    ) -> Set<String> {
        guard let normalizedTitle = normalizedMenuTitle(title) else { return titles }
        var updatedTitles = titles
        updatedTitles.insert(normalizedTitle)
        return updatedTitles
    }

    @MainActor
    private static func performShowMenuAction(
        startingAt capturedElement: AXUIElement,
        processIdentifier: pid_t
    ) -> AXError {
        var currentElement: AXUIElement? = capturedElement
        for _ in 0..<insertionAncestorTraversalLimit {
            guard let element = currentElement else { break }
            if actionNames(from: element).contains(kAXShowMenuAction as String) {
                guard capturedEditorIsFocused(
                    capturedElement,
                    processIdentifier: processIdentifier
                ) else {
                    return .cannotComplete
                }
                return AXUIElementPerformAction(
                    element,
                    kAXShowMenuAction as CFString
                )
            }
            currentElement = parentElement(from: element)
        }
        return .actionUnsupported
    }

    static func rightClickContextMenuEvents(
        at point: CGPoint,
        source: CGEventSource?
    ) -> [CGEvent]? {
        guard let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ),
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else {
            return nil
        }
        mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
        mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
        return [mouseDown, mouseUp]
    }

    @MainActor
    private static func postCaretContextMenuClick(
        to target: FocusedPasteTarget,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) -> ContextMenuAnchor? {
        guard pasteTargetIsCurrent(target),
              let selectedRange = target.selectedRange,
              let text = target.text,
              let anchor = verifiedContextMenuAnchor(
                range: selectedRange,
                text: text,
                in: target.focusedElement,
                latencyTraceToken: latencyTraceToken
              ),
              pasteTargetIsCurrent(target),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == target.processIdentifier,
              let hitElement = elementAtPosition(anchor.point),
              element(hitElement, belongsTo: target.focusedElement),
              let events = rightClickContextMenuEvents(
                at: anchor.point,
                source: CGEventSource(stateID: .combinedSessionState)
              ) else {
            return nil
        }
        // PID-directed mouse events never reached cold Chromium's hit-testing.
        // Global HID delivery is safe here because focus, PID, and hit target were revalidated.
        for event in events {
            event.post(tap: .cghidEventTap)
        }
        VoiceInkLatencyTrace.shared.event(
            "paste_context_menu_click_delivery",
            details: "method=globalHID targetPid=\(target.processIdentifier) eventCount=\(events.count)",
            token: latencyTraceToken
        )
        return anchor
    }

    @MainActor
    private static func verifiedContextMenuAnchor(
        range: CFRange,
        text: String,
        in editor: AXUIElement,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) -> ContextMenuAnchor? {
        let rangeProbe = boundsForRange(range, in: editor)
        let rangePoint = rangeProbe.bounds.flatMap {
            verifiedContextMenuPoint(in: $0, matching: editor)
        }
        traceContextMenuBoundsProbe(
            rangeProbe,
            method: "range",
            matchedPoint: rangePoint,
            latencyTraceToken: latencyTraceToken
        )
        if let point = rangePoint {
            return ContextMenuAnchor(point: point, boundsMethod: "range")
        }

        // Chromium reports a zero rectangle for collapsed contenteditable ranges.
        // Adjacent glyph bounds locate the same caret without changing selection.
        let neighborRanges = contextMenuNeighborRanges(around: range, in: text)
        let previousProbe = neighborRanges.previous.map { boundsForRange($0, in: editor) }
        let nextProbe = neighborRanges.next.map { boundsForRange($0, in: editor) }
        let previousOuterProbe = neighborRanges.next == nil
            ? neighborRanges.previousOuter.map { boundsForRange($0, in: editor) }
            : nil
        let nextOuterProbe = neighborRanges.previous == nil
            ? neighborRanges.nextOuter.map { boundsForRange($0, in: editor) }
            : nil
        var neighborDetails = [
            contextMenuRangeProbeDescription(
                neighborRanges.previous,
                probe: previousProbe,
                label: "previous"
            ),
            contextMenuRangeProbeDescription(
                neighborRanges.next,
                probe: nextProbe,
                label: "next"
            )
        ]
        if neighborRanges.next == nil {
            neighborDetails.append(contextMenuRangeProbeDescription(
                neighborRanges.previousOuter,
                probe: previousOuterProbe,
                label: "previousOuter"
            ))
        }
        if neighborRanges.previous == nil {
            neighborDetails.append(contextMenuRangeProbeDescription(
                neighborRanges.nextOuter,
                probe: nextOuterProbe,
                label: "nextOuter"
            ))
        }
        for (index, bounds) in contextMenuCaretBoundaryBounds(
            previousOuter: previousOuterProbe?.bounds,
            previous: previousProbe?.bounds,
            next: nextProbe?.bounds,
            nextOuter: nextOuterProbe?.bounds,
            isAtStart: neighborRanges.previous == nil,
            isAtEnd: neighborRanges.next == nil
        ).enumerated() {
            let neighborProbe = ContextMenuBoundsProbe(
                bounds: bounds,
                details: "candidate=\(index + 1) \(neighborDetails.joined(separator: " "))"
            )
            let neighborPoint = verifiedContextMenuPoint(in: bounds, matching: editor)
            traceContextMenuBoundsProbe(
                neighborProbe,
                method: "adjacentCharacter",
                matchedPoint: neighborPoint,
                latencyTraceToken: latencyTraceToken
            )
            if let point = neighborPoint {
                return ContextMenuAnchor(point: point, boundsMethod: "adjacentCharacter")
            }
        }

        // An empty editor has only one possible caret position.
        if text.isEmpty {
            let editorProbe = boundsForEditor(editor)
            let editorPoint = editorProbe.bounds.flatMap {
                verifiedContextMenuPoint(in: $0, matching: editor)
            }
            traceContextMenuBoundsProbe(
                editorProbe,
                method: "emptyEditorFrame",
                matchedPoint: editorPoint,
                latencyTraceToken: latencyTraceToken
            )
            if let point = editorPoint {
                return ContextMenuAnchor(point: point, boundsMethod: "emptyEditorFrame")
            }
        }
        return nil
    }

    static func contextMenuNeighborRanges(
        around selectedRange: CFRange,
        in text: String
    ) -> ContextMenuNeighborRanges {
        let text = text as NSString
        let location = selectedRange.location
        guard selectedRange.length == 0,
              location >= 0,
              location <= text.length,
              location == text.length
                || text.rangeOfComposedCharacterSequence(at: location).location == location else {
            return ContextMenuNeighborRanges(
                previousOuter: nil,
                previous: nil,
                next: nil,
                nextOuter: nil
            )
        }
        let previous = location > 0
            ? contextMenuCFRange(text.rangeOfComposedCharacterSequence(at: location - 1))
            : nil
        let next = location < text.length
            ? contextMenuCFRange(text.rangeOfComposedCharacterSequence(at: location))
            : nil
        let previousOuter = previous.flatMap { range in
            range.location > 0
                ? contextMenuCFRange(text.rangeOfComposedCharacterSequence(at: range.location - 1))
                : nil
        }
        let nextOuter = next.flatMap { range in
            let location = range.location + range.length
            return location < text.length
                ? contextMenuCFRange(text.rangeOfComposedCharacterSequence(at: location))
                : nil
        }
        return ContextMenuNeighborRanges(
            previousOuter: previousOuter,
            previous: previous,
            next: next,
            nextOuter: nextOuter
        )
    }

    private static func contextMenuCFRange(_ range: NSRange) -> CFRange {
        CFRange(location: range.location, length: range.length)
    }

    static func contextMenuCaretBoundaryBounds(
        previousOuter: CGRect?,
        previous: CGRect?,
        next: CGRect?,
        nextOuter: CGRect?,
        isAtStart: Bool,
        isAtEnd: Bool
    ) -> [CGRect] {
        if let previous,
           let next {
            let minimumY = max(previous.minY, next.minY)
            let maximumY = min(previous.maxY, next.maxY)
            if maximumY > minimumY {
                let edgePairs = [
                    (previous.maxX, next.minX),
                    (previous.minX, next.maxX)
                ]
                let distances = edgePairs.map { abs($0.0 - $0.1) }
                guard distances[0] != distances[1] else { return [] }
                let closestPair = distances[0] < distances[1] ? edgePairs[0] : edgePairs[1]
                return [CGRect(
                    x: (closestPair.0 + closestPair.1) / 2,
                    y: minimumY,
                    width: 0,
                    height: maximumY - minimumY
                )]
            }
            return []
        }

        if isAtEnd,
           let previousOuter,
           let previous,
           contextMenuBoundsShareLine(previousOuter, previous),
           previousOuter.midX != previous.midX {
            let x = previous.midX > previousOuter.midX ? previous.maxX : previous.minX
            return [contextMenuCaretBounds(atX: x, matching: previous)]
        }
        if isAtStart,
           let next,
           let nextOuter,
           contextMenuBoundsShareLine(next, nextOuter),
           next.midX != nextOuter.midX {
            let x = next.midX < nextOuter.midX ? next.minX : next.maxX
            return [contextMenuCaretBounds(atX: x, matching: next)]
        }
        return []
    }

    private static func contextMenuBoundsShareLine(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        max(lhs.minY, rhs.minY) < min(lhs.maxY, rhs.maxY)
    }

    private static func contextMenuCaretBounds(atX x: CGFloat, matching bounds: CGRect) -> CGRect {
        CGRect(x: x, y: bounds.minY, width: 0, height: bounds.height)
    }

    private static func contextMenuRangeProbeDescription(
        _ range: CFRange?,
        probe: ContextMenuBoundsProbe?,
        label: String
    ) -> String {
        guard let range else { return "\(label)=none" }
        return "\(label)=\(range.location):\(range.length) \(probe?.details ?? "bounds=none")"
    }

    private static func verifiedContextMenuPoint(
        in bounds: CGRect,
        matching editor: AXUIElement
    ) -> CGPoint? {
        verifiedContextMenuPoint(
            in: bounds,
            displayBounds: activeDisplayBounds()
        ) { point in
            guard let hitElement = elementAtPosition(point) else { return false }
            return element(hitElement, belongsTo: editor)
        }
    }

    static func verifiedContextMenuPoint(
        in bounds: CGRect,
        displayBounds: [CGRect],
        hitTestMatchesEditor: (CGPoint) -> Bool
    ) -> CGPoint? {
        guard contextMenuBoundsAreUsable(bounds) else {
            return nil
        }
        let points = [
            CGPoint(x: bounds.midX, y: bounds.midY),
            CGPoint(x: bounds.midX + 1, y: bounds.midY),
            CGPoint(x: bounds.midX - 1, y: bounds.midY)
        ]
        let maximumCoordinate = CGFloat(Float.greatestFiniteMagnitude)
        guard points.allSatisfy({ point in
            point.x.isFinite
                && point.y.isFinite
                && abs(point.x) <= maximumCoordinate
                && abs(point.y) <= maximumCoordinate
        }) else {
            return nil
        }
        return points.first { point in
            displayBounds.contains(where: { $0.contains(point) })
                && hitTestMatchesEditor(point)
        }
    }

    private static func contextMenuBoundsAreUsable(_ bounds: CGRect) -> Bool {
        bounds.width >= 0
            && bounds.height > 0
            && bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.width.isFinite
            && bounds.height.isFinite
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }
        let capacity = displayCount
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        let result = displays.withUnsafeMutableBufferPointer { buffer in
            CGGetActiveDisplayList(capacity, buffer.baseAddress, &displayCount)
        }
        guard result == .success else { return [] }
        return displays.prefix(Int(displayCount)).map(CGDisplayBounds)
    }

    private static func element(_ candidate: AXUIElement, belongsTo ancestor: AXUIElement) -> Bool {
        var currentElement: AXUIElement? = candidate
        for _ in 0..<insertionAncestorTraversalLimit {
            guard let element = currentElement else { return false }
            if CFEqual(element, ancestor) { return true }
            currentElement = parentElement(from: element)
        }
        return false
    }

    @MainActor
    private static func pasteTargetIsCurrent(_ target: FocusedPasteTarget) -> Bool {
        pasteTargetSnapshotMatches(
            capturedEditorFocused: capturedEditorIsFocused(
                target.focusedElement,
                processIdentifier: target.processIdentifier
            ),
            capturedText: target.text,
            currentText: textValue(from: target.focusedElement),
            capturedRange: target.selectedRange,
            currentRange: selectedTextRange(from: target.focusedElement)
        )
    }

    static func pasteTargetSnapshotMatches(
        capturedEditorFocused: Bool,
        capturedText: String?,
        currentText: String?,
        capturedRange: CFRange?,
        currentRange: CFRange?
    ) -> Bool {
        guard capturedEditorFocused,
              let capturedText,
              let currentText,
              let capturedRange,
              let currentRange else {
            return false
        }
        return capturedText == currentText
            && sameRange(capturedRange, currentRange)
    }

    @MainActor
    private static func capturedEditorIsFocused(
        _ capturedElement: AXUIElement,
        processIdentifier: pid_t
    ) -> Bool {
        guard let currentElement = focusedElement(from: AXUIElementCreateSystemWide()),
              CFEqual(currentElement, capturedElement) else {
            return false
        }
        var currentProcessIdentifier = pid_t()
        return AXUIElementGetPid(currentElement, &currentProcessIdentifier) == .success
            && currentProcessIdentifier == processIdentifier
    }

    private static func actionNames(from element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success,
              let value else {
            return []
        }
        return value as? [String] ?? []
    }

    private static func menuElements(in application: AXUIElement) -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(commandVMenuTraversalTimeout)
        var queue = [application]
        var index = 0
        var menus: [AXUIElement] = []
        while index < queue.count,
              index < commandVMenuTraversalLimit,
              Date() < deadline {
            let element = queue[index]
            index += 1
            if role(from: element) == kAXMenuRole as String {
                menus.append(element)
            }
            let remainingCapacity = commandVMenuTraversalLimit - queue.count
            guard remainingCapacity > 0 else { continue }
            queue.append(contentsOf: childElements(from: element).prefix(remainingCapacity))
        }
        return menus
    }

    private struct MenuSnapshot {
        let element: AXUIElement
        let visibleChildCount: Int?
    }

    private static func menuSnapshots(in application: AXUIElement) -> [MenuSnapshot] {
        menuElements(in: application).map {
            MenuSnapshot(
                element: $0,
                visibleChildCount: visibleChildElements(from: $0)?.count
            )
        }
    }

    private static func activatedMenuElements(
        in application: AXUIElement,
        since previousMenus: [MenuSnapshot]
    ) -> [AXUIElement] {
        menuSnapshots(in: application).compactMap { current in
            guard let previous = previousMenus.first(where: {
                CFEqual(current.element, $0.element)
            }) else {
                return current.element
            }
            guard previous.visibleChildCount == 0,
                  let currentVisibleChildCount = current.visibleChildCount,
                  currentVisibleChildCount > 0 else {
                return nil
            }
            return current.element
        }
    }

    private static func contextMenuElements(
        in application: AXUIElement,
        since previousMenus: [MenuSnapshot],
        triggerPoint: CGPoint?
    ) -> [AXUIElement] {
        attributableContextMenuCandidates(
            activatedMenuElements(in: application, since: previousMenus),
            triggerPoint: triggerPoint
        ) { menu, point in
            guard let hitElement = elementAtPosition(point) else { return false }
            return element(hitElement, belongsTo: menu)
        }
    }

    static func attributableContextMenuCandidates<Menu>(
        _ candidates: [Menu],
        triggerPoint: CGPoint?,
        ownsTriggerPoint: (Menu, CGPoint) -> Bool
    ) -> [Menu] {
        guard let triggerPoint else { return candidates }
        return candidates.filter { ownsTriggerPoint($0, triggerPoint) }
    }

    private static func cancelMenus(_ menus: [AXUIElement]) {
        for menu in menus {
            _ = cancelMenu(menu)
        }
    }

    private static func cancelMenu(_ menu: AXUIElement) -> Bool {
        actionNames(from: menu).contains(kAXCancelAction as String)
            && AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success
    }

    @MainActor
    private static func pasteWasObserved(
        focusedElement: AXUIElement,
        processIdentifier: pid_t,
        textBeforePaste: String?,
        selectedRangeBeforePaste: CFRange?,
        expectedText: String
    ) async -> Bool {
        guard let textBeforePaste,
              let selectedRangeBeforePaste else {
            return false
        }
        for attempt in 0..<pasteDeliveryObservationAttempts {
            guard !Task.isCancelled,
                  capturedEditorIsFocused(
                    focusedElement,
                    processIdentifier: processIdentifier
                  ) else {
                return false
            }
            if replacementTextWasObserved(
                textBeforeInsertion: textBeforePaste,
                rangeBeforeInsertion: selectedRangeBeforePaste,
                insertedText: expectedText,
                textAfterInsertion: textValue(from: focusedElement)
            ) {
                return !Task.isCancelled && capturedEditorIsFocused(
                    focusedElement,
                    processIdentifier: processIdentifier
                )
            }
            guard attempt < pasteDeliveryObservationAttempts - 1 else { break }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(pasteDeliveryObservationDelay * 1_000_000_000)
                )
            } catch {
                return false
            }
        }
        return false
    }

    static func isPlainCommandVMenuItem(
        commandCharacter: String?,
        virtualKey: Int?,
        modifiers: UInt32?,
        enabled: Bool
    ) -> Bool {
        enabled && isPlainCommandVShortcut(
            commandCharacter: commandCharacter,
            virtualKey: virtualKey,
            modifiers: modifiers
        )
    }

    static func isPlainCommandVShortcut(
        commandCharacter: String?,
        virtualKey: Int?,
        modifiers: UInt32?
    ) -> Bool {
        guard modifiers == 0 else { return false }
        return commandCharacter?.caseInsensitiveCompare("v") == .orderedSame
            || virtualKey == 0x09
    }

    @MainActor
    static func insertSelectedText(
        _ text: String,
        preparedContext: PreparedContext?
    ) -> SelectedTextInsertionResult {
        guard !text.isEmpty,
              AXIsProcessTrusted(),
              let focusedElement = focusedElement(from: AXUIElementCreateSystemWide()),
              let selectedRange = selectedTextRange(from: focusedElement),
              let role = role(from: focusedElement),
              VoiceInkCursorTextContextPolicy.isTextInputRole(role),
              shouldUseDirectAccessibilityInsertion(
                  ancestorRoles: insertionAncestorRoles(startingAt: focusedElement)
              ) else {
            return .unsupported
        }

        if let preparedContext {
            guard CFEqual(focusedElement, preparedContext.focusedElement),
                  sameRange(selectedRange, preparedContext.selectedRange) else {
                return .unsupported
            }
        }

        let textBeforeInsertion = textValue(from: focusedElement)
        let canSetSelectedText = isAttributeSettable(
            kAXSelectedTextAttribute as CFString,
            on: focusedElement
        )
        if canSetSelectedText,
           AXUIElementSetAttributeValue(
               focusedElement,
               kAXSelectedTextAttribute as CFString,
               text as CFString
           ) == .success {
            if insertionWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement),
                rangeAfterInsertion: selectedTextRange(from: focusedElement)
            ) {
                return .inserted
            }
            let textWasInsertedImmediately = replacementTextWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement)
            )

            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
            if insertionWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement),
                rangeAfterInsertion: selectedTextRange(from: focusedElement)
            ) {
                return .inserted
            }
            if textWasInsertedImmediately || replacementTextWasObserved(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text,
                textAfterInsertion: textValue(from: focusedElement)
            ) {
                return .insertedWithoutSelection
            }
        }

        guard let textBeforeInsertion,
              textValue(from: focusedElement) == textBeforeInsertion,
              sameRange(selectedTextRange(from: focusedElement), selectedRange),
              let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: selectedRange,
                insertedText: text
              ),
              isAttributeSettable(kAXValueAttribute as CFString, on: focusedElement),
              setSelectedTextRange(selectedRange, on: focusedElement),
              AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                replacement.text as CFString
              ) == .success else {
            return canSetSelectedText ? .notApplied : .unsupported
        }

        if textValue(from: focusedElement) != replacement.text {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        guard textValue(from: focusedElement) == replacement.text else {
            return .notApplied
        }

        if valueReplacementWasObserved(
            text: replacement.text,
            selectedRange: replacement.selectedRange,
            textAfterInsertion: textValue(from: focusedElement),
            rangeAfterInsertion: selectedTextRange(from: focusedElement)
        ) || setSelectedTextRange(replacement.selectedRange, on: focusedElement) {
            return .insertedViaValue
        }

        // Text is already present. Never post a fallback paste that could duplicate it.
        return .insertedViaValueWithoutSelection
    }

    static func valueReplacement(
        textBeforeInsertion: String,
        rangeBeforeInsertion: CFRange,
        insertedText: String
    ) -> (text: String, selectedRange: CFRange)? {
        let source = textBeforeInsertion as NSString
        guard rangeBeforeInsertion.location >= 0,
              rangeBeforeInsertion.length >= 0,
              rangeBeforeInsertion.location <= source.length,
              rangeBeforeInsertion.length <= source.length - rangeBeforeInsertion.location else {
            return nil
        }

        return (
            source.replacingCharacters(
                in: NSRange(
                    location: rangeBeforeInsertion.location,
                    length: rangeBeforeInsertion.length
                ),
                with: insertedText
            ),
            CFRange(
                location: rangeBeforeInsertion.location + insertedText.utf16.count,
                length: 0
            )
        )
    }

    static func valueReplacementWasObserved(
        text: String,
        selectedRange: CFRange,
        textAfterInsertion: String?,
        rangeAfterInsertion: CFRange?
    ) -> Bool {
        textAfterInsertion == text && sameRange(rangeAfterInsertion, selectedRange)
    }

    static func insertionWasObserved(
        textBeforeInsertion: String?,
        rangeBeforeInsertion: CFRange,
        insertedText: String,
        textAfterInsertion: String?,
        rangeAfterInsertion: CFRange?
    ) -> Bool {
        if let textBeforeInsertion,
           let textAfterInsertion {
            guard let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: rangeBeforeInsertion,
                insertedText: insertedText
            ) else {
                return false
            }
            return valueReplacementWasObserved(
                text: replacement.text,
                selectedRange: replacement.selectedRange,
                textAfterInsertion: textAfterInsertion,
                rangeAfterInsertion: rangeAfterInsertion
            )
        }

        guard !insertedText.isEmpty,
              let rangeAfterInsertion else {
            return false
        }
        return rangeAfterInsertion.location
                == rangeBeforeInsertion.location + insertedText.utf16.count
            && rangeAfterInsertion.length == 0
    }

    static func replacementTextWasObserved(
        textBeforeInsertion: String?,
        rangeBeforeInsertion: CFRange,
        insertedText: String,
        textAfterInsertion: String?
    ) -> Bool {
        guard let textBeforeInsertion,
              let textAfterInsertion,
              let replacement = valueReplacement(
                textBeforeInsertion: textBeforeInsertion,
                rangeBeforeInsertion: rangeBeforeInsertion,
                insertedText: insertedText
              ) else {
            return false
        }
        return textAfterInsertion == replacement.text
    }

    static func shouldUseDirectAccessibilityInsertion(ancestorRoles: [String]) -> Bool {
        // Web editors need Cmd-V so their DOM paste/input handlers update application state.
        !ancestorRoles.contains(webAreaRole)
    }

    private static func textBeforeCursor(in focusedElement: AXUIElement, maximumLength: Int) -> String? {
        let elements = contextCandidateElements(startingAt: focusedElement)

        for element in elements {
            guard let selectedRange = selectedTextRange(from: element),
                  let prefixLength = VoiceInkCursorTextContextPolicy.prefixLength(
                    cursorLocation: selectedRange.location,
                    maximumLength: maximumLength
                  ) else {
                continue
            }

            guard prefixLength > 0 else { return "" }

            let prefixRange = CFRange(
                location: selectedRange.location - prefixLength,
                length: prefixLength
            )

            if let prefix = stringForRange(prefixRange, in: element)
                ?? valuePrefix(prefixRange, in: element) {
                return prefix
            }
        }

        for element in elements {
            if let suffix = valueSuffix(in: element, maximumLength: maximumLength) {
                return suffix
            }
        }

        return nil
    }

    private static func contextCandidateElements(startingAt element: AXUIElement) -> [AXUIElement] {
        var elements = [element]
        var currentElement = element

        for _ in 0..<VoiceInkCursorTextContextPolicy.parentTraversalLimit {
            guard let parent = parentElement(from: currentElement) else {
                break
            }

            elements.append(parent)
            currentElement = parent
        }

        return elements
    }

    private static func insertionAncestorRoles(startingAt element: AXUIElement) -> [String] {
        var roles: [String] = []
        var currentElement: AXUIElement? = element

        for _ in 0..<insertionAncestorTraversalLimit {
            guard let element = currentElement else { break }
            if let role = role(from: element) {
                roles.append(role)
            }
            currentElement = parentElement(from: element)
        }

        return roles
    }

    private static func parentElement(from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func elementAtPosition(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &element
        ) == .success else {
            return nil
        }
        return element
    }

    private static func childElements(from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }

    private static func visibleChildElements(from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXVisibleChildrenAttribute as CFString,
            &value
        ) == .success,
              let values = value as? [AXUIElement] else {
            return nil
        }
        return values
    }

    private static func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func numberAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? NSNumber
    }

    private static func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
              let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    @MainActor
    private static func boundsForRange(
        _ range: CFRange,
        in element: AXUIElement
    ) -> ContextMenuBoundsProbe {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return ContextMenuBoundsProbe(
                bounds: nil,
                details: "query=parameterUnavailable"
            )
        }
        var value: CFTypeRef?
        let queryResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard queryResult == .success,
              let value else {
            return ContextMenuBoundsProbe(
                bounds: nil,
                details: "query=\(queryResult.rawValue) value=none"
            )
        }
        return contextMenuBoundsProbe(queryResult: queryResult, value: value)
    }

    @MainActor
    private static func boundsForEditor(_ element: AXUIElement) -> ContextMenuBoundsProbe {
        var positionValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )
        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return ContextMenuBoundsProbe(
                bounds: nil,
                details: "positionQuery=\(positionResult.rawValue) sizeQuery=\(sizeResult.rawValue) value=unavailable"
            )
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize else {
            return ContextMenuBoundsProbe(
                bounds: nil,
                details: "positionQuery=\(positionResult.rawValue) sizeQuery=\(sizeResult.rawValue) value=unexpected"
            )
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return ContextMenuBoundsProbe(
                bounds: nil,
                details: "positionQuery=\(positionResult.rawValue) sizeQuery=\(sizeResult.rawValue) value=decodeFailed"
            )
        }
        let bounds = CGRect(origin: position, size: size)
        return ContextMenuBoundsProbe(
            bounds: bounds,
            details: "positionQuery=\(positionResult.rawValue) sizeQuery=\(sizeResult.rawValue) screen=\(contextMenuRectDescription(bounds))"
        )
    }

    @MainActor
    private static func contextMenuBoundsProbe(
        queryResult: AXError,
        value: CFTypeRef
    ) -> ContextMenuBoundsProbe {
        let rawBounds = contextMenuRect(from: value)
        let screenBounds = contextMenuScreenRect(from: value)
        return ContextMenuBoundsProbe(
            bounds: screenBounds,
            details: "query=\(queryResult.rawValue) value=\(contextMenuValueKind(value)) raw=\(contextMenuRectDescription(rawBounds)) screen=\(contextMenuRectDescription(screenBounds))"
        )
    }

    @MainActor
    private static func traceContextMenuBoundsProbe(
        _ probe: ContextMenuBoundsProbe,
        method: String,
        matchedPoint: CGPoint?,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) {
        let onDisplay = probe.bounds.map { bounds in
            let point = CGPoint(x: bounds.midX, y: bounds.midY)
            return activeDisplayBounds().contains(where: { $0.contains(point) })
        }
        VoiceInkLatencyTrace.shared.event(
            "paste_context_menu_bounds",
            details: "method=\(method) \(probe.details) onDisplay=\(onDisplay.map { String($0) } ?? "unknown") editorMatch=\(matchedPoint != nil)",
            token: latencyTraceToken
        )
    }

    private static func contextMenuValueKind(_ value: CFTypeRef) -> String {
        if CFGetTypeID(value) == AXValueGetTypeID() {
            return "ax:\(String(describing: AXValueGetType(value as! AXValue)))"
        }
        if let nsValue = value as? NSValue {
            return "ns:\(String(cString: nsValue.objCType))"
        }
        return "cf:\(CFGetTypeID(value))"
    }

    private static func contextMenuRectDescription(_ bounds: CGRect?) -> String {
        guard let bounds else { return "none" }
        return "\(bounds.origin.x),\(bounds.origin.y),\(bounds.width),\(bounds.height)"
    }

    @MainActor
    private static func contextMenuScreenRect(from value: CFTypeRef) -> CGRect? {
        guard let bounds = contextMenuRect(from: value) else { return nil }
        guard CFGetTypeID(value) != AXValueGetTypeID() else { return bounds }
        guard let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY else {
            return nil
        }
        return accessibilityScreenRect(
            fromAppKitScreenRect: bounds,
            primaryScreenMaxY: primaryScreenMaxY
        )
    }

    static func accessibilityScreenRect(
        fromAppKitScreenRect bounds: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: primaryScreenMaxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    static func contextMenuRect(from value: CFTypeRef) -> CGRect? {
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = value as! AXValue
            guard AXValueGetType(axValue) == .cgRect else { return nil }
            var bounds = CGRect.zero
            return AXValueGetValue(axValue, .cgRect, &bounds) ? bounds : nil
        }
        guard let nsValue = value as? NSValue,
              strcmp(nsValue.objCType, NSValue(rect: .zero).objCType) == 0 else {
            return nil
        }
        return nsValue.rectValue
    }

    private static func setSelectedTextRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        guard isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: element) else {
            return false
        }

        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else {
            return false
        }
        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success else {
            return false
        }
        if sameRange(selectedTextRange(from: element), range) {
            return true
        }

        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        return sameRange(selectedTextRange(from: element), range)
    }

    private static func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &isSettable) == .success
            && isSettable.boolValue
    }

    private static func sameRange(_ lhs: CFRange?, _ rhs: CFRange?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case (.some(let lhs), .some(let rhs)):
            lhs.location == rhs.location && lhs.length == rhs.length
        default:
            false
        }
    }

    private static func stringForRange(_ range: CFRange, in element: AXUIElement) -> String? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }

        return value as? String
    }

    private static func valuePrefix(_ range: CFRange, in element: AXUIElement) -> String? {
        guard let text = textValue(from: element),
              let stringRange = Range(NSRange(location: range.location, length: range.length), in: text) else {
            return nil
        }

        return String(text[stringRange])
    }

    private static func valueSuffix(in element: AXUIElement, maximumLength: Int) -> String? {
        guard let role = role(from: element),
              VoiceInkCursorTextContextPolicy.isTextInputRole(role),
              let text = textValue(from: element) else {
            return nil
        }

        return VoiceInkCursorTextContextPolicy.valueSuffix(
            from: text,
            role: role,
            maximumLength: maximumLength
        )
    }

    private static func textValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
              let text = value as? String else {
            return nil
        }
        return text
    }

    private static func role(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success,
              let role = value as? String else {
            return nil
        }

        return role
    }
}
