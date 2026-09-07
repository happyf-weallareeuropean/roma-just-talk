//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
import VoiceInkCore
import SwiftData
import AppKit
import Carbon.HIToolbox
import os
@testable import VoiceInk

@Suite(.serialized)
struct VoiceInkTests {

    @Test func freshDefaultsHideMenuBarAndDockIcons() async throws {
        #expect(AppDefaults.registeredDefaults[VoiceInkMenuBarPreference.showMenuBarIconKey] as? Bool == false)
        #expect(AppDefaults.registeredDefaults[VoiceInkMenuBarPreference.legacyIsMenuBarOnlyKey] as? Bool == true)
        #expect(AppDefaults.registeredDefaults[VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap] as? Bool == true)
    }

    @Test func automaticSystemMuteFollowsAirPodsOutput() {
        #expect(!MediaController.shouldMuteAudio(
            mode: .automatic,
            outputDeviceModelName: "AirPods Pro",
            outputDeviceName: "Felix Buds"
        ))
        #expect(!MediaController.shouldMuteAudio(
            mode: .automatic,
            outputDeviceModelName: nil,
            outputDeviceName: "AIRPODS MAX"
        ))
        #expect(MediaController.shouldMuteAudio(
            mode: .automatic,
            outputDeviceModelName: "WH-1000XM5",
            outputDeviceName: "AirPods"
        ))
        #expect(MediaController.shouldMuteAudio(
            mode: .automatic,
            outputDeviceModelName: nil,
            outputDeviceName: "MacBook Pro Speakers"
        ))
        #expect(MediaController.shouldMuteAudio(
            mode: .automatic,
            outputDeviceModelName: nil,
            outputDeviceName: nil
        ))
        #expect(MediaController.shouldMuteAudio(
            mode: .always,
            outputDeviceModelName: "AirPods Max",
            outputDeviceName: "Felix Headphones"
        ))
        #expect(!MediaController.shouldMuteAudio(
            mode: .never,
            outputDeviceModelName: "MacBook Pro Speakers",
            outputDeviceName: "MacBook Pro Speakers"
        ))
    }

    @Test @MainActor func unconfirmedPasteCommandDoesNotRestoreOverTranscriptClipboard() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let restoreDelayValue = defaults.object(forKey: "clipboardRestoreDelay")
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(restoreDelayValue, forKey: "clipboardRestoreDelay")
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(true, forKey: "restoreClipboardAfterPaste")
        defaults.set(0.01, forKey: "clipboardRestoreDelay")
        var postCount = 0
        for expectedResult in [
            CursorPaster.PasteResult.commandNotPosted,
            .commandDeliveryUncertain
        ] {
            pasteboard.clearContents()
            pasteboard.setString("previous clipboard", forType: .string)
            postCount = 0
            CursorPaster.configurePasteCommandPosterForTesting { _ in
                postCount += 1
                return expectedResult
            }

            let result = await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text")
            try await Task.sleep(nanoseconds: 350_000_000)

            #expect(result == expectedResult)
            #expect(postCount == 1)
            #expect(!result.didDeliverText)
            #expect(pasteboard.string(forType: .string) == "dictated text")
        }
    }

    @Test @MainActor func accessibilityInsertDeliversWithoutTouchingClipboard() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let pasteMethodValue = defaults.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configureAccessibilityTextInserterForTesting()
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(pasteMethodValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(true, forKey: "restoreClipboardAfterPaste")
        defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        var postedCommand = false
        var insertionResult = CursorTextContextReader.SelectedTextInsertionResult.inserted
        CursorPaster.configureAccessibilityTextInserterForTesting { text, _ in
            text == "dictated text" ? insertionResult : .notApplied
        }
        CursorPaster.configurePasteCommandPosterForTesting { _ in
            postedCommand = true
            return .commandPosted
        }

        for result in [
            CursorTextContextReader.SelectedTextInsertionResult.inserted,
            .insertedWithoutSelection,
            .insertedViaValue,
            .insertedViaValueWithoutSelection
        ] {
            insertionResult = result
            #expect(await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text") == .textInserted)
        }
        #expect(!postedCommand)
        #expect(pasteboard.string(forType: .string) == "previous clipboard")
    }

    @Test @MainActor func nonInsertedAccessibilityResultsFallBackToPasteCommand() async throws {
        let defaults = UserDefaults.standard
        let restoreValue = defaults.object(forKey: "restoreClipboardAfterPaste")
        let pasteMethodValue = defaults.object(forKey: VoiceInkPasteMethod.userDefaultsKey)
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        defer {
            CursorPaster.configureAccessibilityTextInserterForTesting()
            CursorPaster.configurePasteCommandPosterForTesting()
            restoreDefault(restoreValue, forKey: "restoreClipboardAfterPaste")
            restoreDefault(pasteMethodValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
            pasteboard.clearContents()
            if let originalClipboard {
                pasteboard.setString(originalClipboard, forType: .string)
            }
        }

        defaults.set(false, forKey: "restoreClipboardAfterPaste")
        defaults.set(VoiceInkPasteMethod.standard.rawValue, forKey: VoiceInkPasteMethod.userDefaultsKey)
        var insertionResult = CursorTextContextReader.SelectedTextInsertionResult.notApplied
        var postedCommandCount = 0
        var retryCommandVMenuDiscoveryValues: [Bool] = []
        CursorPaster.configureAccessibilityTextInserterForTesting { _, _ in insertionResult }
        CursorPaster.configurePasteCommandPosterForTesting { retryCommandVMenuDiscovery in
            postedCommandCount += 1
            retryCommandVMenuDiscoveryValues.append(retryCommandVMenuDiscovery)
            return .commandPosted
        }

        for result in [
            CursorTextContextReader.SelectedTextInsertionResult.notApplied,
            .unsupported
        ] {
            insertionResult = result
            pasteboard.clearContents()
            pasteboard.setString("previous clipboard", forType: .string)

            #expect(await CursorPaster.pasteAtCursorAndWaitUntilPosted("dictated text") == .commandPosted)
            #expect(pasteboard.string(forType: .string) == "dictated text")
        }

        #expect(postedCommandCount == 2)
        #expect(retryCommandVMenuDiscoveryValues == [false, true])
    }

    @Test func accessibilityInsertionObservationRejectsSilentAXSuccess() {
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "",
            rangeBeforeInsertion: CFRange(location: 0, length: 0),
            insertedText: "dictated text",
            textAfterInsertion: "",
            rangeAfterInsertion: CFRange(location: 0, length: 0)
        ))
    }

    @Test func directAccessibilityInsertionSkipsWebBackedEditors() {
        #expect(CursorTextContextReader.shouldUseDirectAccessibilityInsertion(
            ancestorRoles: ["AXTextArea", "AXGroup", "AXWindow"]
        ))
        #expect(!CursorTextContextReader.shouldUseDirectAccessibilityInsertion(
            ancestorRoles: ["AXTextArea", "AXGroup", "AXWebArea", "AXWindow"]
        ))
    }

    @Test func accessibilityCommandVMenuMatchRequiresEnabledPlainShortcut() {
        #expect(CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: "V",
            virtualKey: nil,
            modifiers: 0,
            enabled: true
        ))
        #expect(CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: nil,
            virtualKey: 0x09,
            modifiers: 0,
            enabled: true
        ))
        #expect(!CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: "v",
            virtualKey: 0x09,
            modifiers: 1,
            enabled: true
        ))
        #expect(!CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: "v",
            virtualKey: 0x09,
            modifiers: 0,
            enabled: false
        ))
        #expect(!CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: "c",
            virtualKey: 0x08,
            modifiers: 0,
            enabled: true
        ))
        #expect(CursorTextContextReader.isPlainCommandVShortcut(
            commandCharacter: "v",
            virtualKey: 0x09,
            modifiers: 0
        ))
        #expect(!CursorTextContextReader.isPlainCommandVShortcut(
            commandCharacter: "v",
            virtualKey: 0x09,
            modifiers: 1
        ))
        #expect(CursorTextContextReader.updatedCommandVShortcutTitles(
            [],
            adding: "  Einfügen  "
        ) == ["einfügen"])
    }

    @Test func accessibilityMenuBatchPreservesUnsupportedAttributeSlots() throws {
        var unsupported = AXError.attributeUnsupported
        let error = try #require(AXValueCreate(.axError, &unsupported))
        let child = AXUIElementCreateApplication(123)
        let attributes = CursorTextContextReader.commandVMenuAttributes(
            from: child,
            copyMultiple: { _, _, _, values in
                values.pointee = [
                    kAXMenuItemRole, "Einfügen", error, NSNumber(value: 0x09),
                    NSNumber(value: 0), NSNumber(value: true), [child],
                ] as CFArray
                return .success
            },
            copySingle: { _, _, _ in
                #expect(false, "A successful batch must not repeat individual AX reads")
                return .failure
            }
        )
        #expect(attributes.role == kAXMenuItemRole)
        #expect(attributes.title == "Einfügen")
        #expect(attributes.commandCharacter == nil)
        #expect(attributes.virtualKey == 0x09)
        #expect(attributes.modifiers == 0)
        #expect(attributes.enabled)
        #expect(attributes.children.count == 1)
        #expect(CFEqual(attributes.children[0], child))
        #expect(CursorTextContextReader.isPlainCommandVMenuItem(
            commandCharacter: attributes.commandCharacter,
            virtualKey: attributes.virtualKey,
            modifiers: attributes.modifiers,
            enabled: attributes.enabled
        ))
    }

    @Test func accessibilityMenuBatchRejectsMissingOrInvalidShortcutState() throws {
        var noValue = AXError.noValue
        let error = try #require(AXValueCreate(.axError, &noValue))
        for unavailable in [NSNull(), error] as [Any] {
            let attributes = CursorTextContextReader.CommandVMenuAttributes(values: [
                kAXMenuItemRole, "Paste", "v", unavailable, unavailable, unavailable, unavailable,
            ])
            #expect(attributes.virtualKey == nil)
            #expect(attributes.modifiers == nil)
            #expect(!attributes.enabled)
            #expect(attributes.children.isEmpty)
            #expect(!CursorTextContextReader.isPlainCommandVMenuItem(
                commandCharacter: attributes.commandCharacter,
                virtualKey: attributes.virtualKey,
                modifiers: attributes.modifiers,
                enabled: true
            ))
        }
        let truncated = CursorTextContextReader.CommandVMenuAttributes(values: [kAXMenuItemRole])
        #expect(truncated.title == nil)
        #expect(!truncated.enabled)
        #expect(truncated.children.isEmpty)
    }

    @Test func accessibilityMenuBatchFailureRetainsScalarChildrenAndShortcut() {
        let child = AXUIElementCreateApplication(123)
        for failure in [AXError.cannotComplete, .notImplemented, .attributeUnsupported, .success] {
            var reads: [String] = []
            let attributes = CursorTextContextReader.commandVMenuAttributes(
                from: child,
                copyMultiple: { _, _, options, values in
                    #expect(options.rawValue == 0)
                    values.pointee = [kAXMenuItemRole] as CFArray
                    return failure
                },
                copySingle: { _, attribute, value in
                    reads.append(attribute as String)
                    switch attribute as String {
                    case kAXRoleAttribute: value.pointee = kAXMenuItemRole as CFString
                    case kAXTitleAttribute: value.pointee = "Paste" as CFString
                    case kAXMenuItemCmdCharAttribute: return .attributeUnsupported
                    case kAXMenuItemCmdVirtualKeyAttribute: value.pointee = NSNumber(value: 0x09)
                    case kAXMenuItemCmdModifiersAttribute: value.pointee = NSNumber(value: 0)
                    case kAXEnabledAttribute: value.pointee = NSNumber(value: true)
                    case kAXChildrenAttribute: value.pointee = [child] as CFArray
                    default: return .attributeUnsupported
                    }
                    return .success
                }
            )
            #expect(reads == CursorTextContextReader.CommandVMenuAttributes.names)
            #expect(attributes.children.count == 1)
            #expect(CFEqual(attributes.children[0], child))
            #expect(CursorTextContextReader.isPlainCommandVMenuItem(
                commandCharacter: attributes.commandCharacter,
                virtualKey: attributes.virtualKey,
                modifiers: attributes.modifiers,
                enabled: attributes.enabled
            ))
        }
    }

    @Test func browserPasteTargetRejectsFocusTextAndSelectionDrift() {
        let capturedRange = CFRange(location: 7, length: 0)
        #expect(CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: true,
            capturedText: "before after",
            currentText: "before after",
            capturedRange: capturedRange,
            currentRange: capturedRange
        ))
        #expect(!CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: false,
            capturedText: "before after",
            currentText: "before after",
            capturedRange: capturedRange,
            currentRange: capturedRange
        ))
        #expect(!CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: true,
            capturedText: "before after",
            currentText: "before typed after",
            capturedRange: capturedRange,
            currentRange: capturedRange
        ))
        #expect(!CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: true,
            capturedText: "before after",
            currentText: "before after",
            capturedRange: capturedRange,
            currentRange: CFRange(location: 8, length: 0)
        ))
        #expect(!CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: true,
            capturedText: nil,
            currentText: nil,
            capturedRange: capturedRange,
            currentRange: capturedRange
        ))
        #expect(!CursorTextContextReader.pasteTargetSnapshotMatches(
            capturedEditorFocused: true,
            capturedText: "before after",
            currentText: "before after",
            capturedRange: nil,
            currentRange: nil
        ))
    }

    @Test func browserContextMenuRightClickIsBalancedAndPositionBound() throws {
        let point = CGPoint(x: 123, y: 456)
        let events = try #require(CursorTextContextReader.rightClickContextMenuEvents(
            at: point,
            source: CGEventSource(stateID: .combinedSessionState)
        ))
        #expect(events.map(\.type) == [.rightMouseDown, .rightMouseUp])
        #expect(events.allSatisfy { $0.location == point })
        #expect(events.allSatisfy {
            $0.getIntegerValueField(.mouseEventClickState) == 1
        })
    }

    @Test func browserCommandVShortcutPostsOneBalancedChord() throws {
        let events = try #require(CursorTextContextReader.commandVShortcutEvents(
            source: CGEventSource(stateID: .combinedSessionState)
        ))
        var postedEvents: [CGEvent] = []
        let postedPaste = CursorTextContextReader.postCommandVShortcutEvents(
            events,
            targetIsCurrent: { true },
            post: { postedEvents.append($0) }
        )

        #expect(postedPaste)
        #expect(postedEvents.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(postedEvents.map {
            $0.getIntegerValueField(.keyboardEventKeycode)
        } == [0x37, 0x09, 0x09, 0x37])
        #expect(postedEvents.dropLast().allSatisfy { $0.flags == .maskCommand })
        #expect(postedEvents.last?.flags == [])
    }

    @Test func browserCommandVShortcutAbortsBeforeVAndReleasesCommandOnDrift() throws {
        let events = try #require(CursorTextContextReader.commandVShortcutEvents(
            source: CGEventSource(stateID: .combinedSessionState)
        ))
        var continuationChecks = 0
        var postedEvents: [CGEvent] = []
        let postedPaste = CursorTextContextReader.postCommandVShortcutEvents(
            events,
            targetIsCurrent: {
                continuationChecks += 1
                return continuationChecks == 1
            },
            post: { postedEvents.append($0) }
        )

        #expect(!postedPaste)
        #expect(continuationChecks == 2)
        #expect(postedEvents.map {
            $0.getIntegerValueField(.keyboardEventKeycode)
        } == [0x37, 0x37])
        #expect(postedEvents.map(\.type) == [.flagsChanged, .flagsChanged])
        #expect(postedEvents.first?.flags == .maskCommand)
        #expect(postedEvents.last?.flags == [])
    }

    @Test func browserContextMenuPointRequiresUsableBoundsAndEditorHit() {
        let bounds = CGRect(x: -10, y: 20, width: 0, height: 16)
        let displayBounds = [CGRect(x: -100, y: 0, width: 200, height: 1_000)]
        var inspectedPoints: [CGPoint] = []
        let point = CursorTextContextReader.verifiedContextMenuPoint(
            in: bounds,
            displayBounds: displayBounds
        ) {
            inspectedPoints.append($0)
            return inspectedPoints.count == 2
        }
        #expect(point == CGPoint(x: -9, y: 28))
        #expect(inspectedPoints == [CGPoint(x: -10, y: 28), CGPoint(x: -9, y: 28)])

        #expect(CursorTextContextReader.verifiedContextMenuPoint(
            in: bounds,
            displayBounds: displayBounds,
            hitTestMatchesEditor: { _ in false }
        ) == nil)
        #expect(CursorTextContextReader.verifiedContextMenuPoint(
            in: CGRect(x: 0, y: 0, width: 1, height: 0),
            displayBounds: displayBounds,
            hitTestMatchesEditor: { _ in true }
        ) == nil)
        #expect(CursorTextContextReader.verifiedContextMenuPoint(
            in: CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: 1, height: 1),
            displayBounds: displayBounds,
            hitTestMatchesEditor: { _ in true }
        ) == nil)
        #expect(CursorTextContextReader.verifiedContextMenuPoint(
            in: CGRect(x: 1_000, y: 1_000, width: 1, height: 16),
            displayBounds: displayBounds,
            hitTestMatchesEditor: { _ in true }
        ) == nil)
    }

    @Test func browserContextMenuRectAcceptsAccessibilityAndChromiumValues() throws {
        let expected = CGRect(x: 12, y: 34, width: 0, height: 18)
        var axRect = expected
        let axValue = try #require(AXValueCreate(.cgRect, &axRect))
        #expect(CursorTextContextReader.contextMenuRect(from: axValue) == expected)

        let nsValue = NSValue(rect: expected)
        #expect(CursorTextContextReader.contextMenuRect(
            from: nsValue as CFTypeRef
        ) == expected)
        #expect(CursorTextContextReader.contextMenuRect(
            from: NSValue(point: expected.origin) as CFTypeRef
        ) == nil)
        #expect(CursorTextContextReader.contextMenuRect(
            from: "not a rectangle" as CFString
        ) == nil)
    }

    @Test func browserContextMenuRectConvertsChromiumScreenCoordinates() {
        #expect(CursorTextContextReader.accessibilityScreenRect(
            fromAppKitScreenRect: CGRect(x: 10, y: 140, width: 0, height: 40),
            primaryScreenMaxY: 200
        ) == CGRect(x: 10, y: 20, width: 0, height: 40))
        #expect(CursorTextContextReader.accessibilityScreenRect(
            fromAppKitScreenRect: CGRect(x: -40, y: -60, width: 30, height: 40),
            primaryScreenMaxY: 200
        ) == CGRect(x: -40, y: 220, width: 30, height: 40))
    }

    @Test func browserCaretFallbackUsesAdjacentComposedCharacters() throws {
        let existingText = "[existing before][existing after]"
        let middle = CursorTextContextReader.contextMenuNeighborRanges(
            around: CFRange(location: 17, length: 0),
            in: existingText
        )
        let previous = try #require(middle.previous)
        let next = try #require(middle.next)
        #expect(middle.previousOuter?.location == 15)
        #expect(previous.location == 16)
        #expect(previous.length == 1)
        #expect(next.location == 17)
        #expect(next.length == 1)
        #expect(middle.nextOuter?.location == 18)

        let emoji = "👨‍👩‍👧‍👦"
        let emojiLength = (emoji as NSString).length
        let afterEmoji = CursorTextContextReader.contextMenuNeighborRanges(
            around: CFRange(location: 1 + emojiLength, length: 0),
            in: "a\(emoji)b"
        )
        let previousEmoji = try #require(afterEmoji.previous)
        #expect(afterEmoji.previousOuter?.location == 0)
        #expect(previousEmoji.location == 1)
        #expect(previousEmoji.length == emojiLength)
        #expect(afterEmoji.next?.location == 1 + emojiLength)
        #expect(afterEmoji.nextOuter == nil)
        let insideEmoji = CursorTextContextReader.contextMenuNeighborRanges(
            around: CFRange(location: 2, length: 0),
            in: "a\(emoji)b"
        )
        #expect(insideEmoji.previous == nil)
        #expect(insideEmoji.next == nil)

        let empty = CursorTextContextReader.contextMenuNeighborRanges(
            around: CFRange(location: 0, length: 0),
            in: ""
        )
        #expect(empty.previous == nil)
        #expect(empty.next == nil)
        #expect(empty.previousOuter == nil)
        #expect(empty.nextOuter == nil)
        let selection = CursorTextContextReader.contextMenuNeighborRanges(
            around: CFRange(location: 1, length: 1),
            in: "ab"
        )
        #expect(selection.previous == nil)
        #expect(selection.next == nil)
        #expect(selection.previousOuter == nil)
        #expect(selection.nextOuter == nil)
    }

    @Test func browserCaretFallbackFindsSharedLTRAndRTLBoundary() throws {
        let ltr = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: CGRect(x: 10, y: 20, width: 5, height: 16),
            next: CGRect(x: 15, y: 22, width: 5, height: 16),
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: false
        ).first)
        #expect(ltr == CGRect(x: 15, y: 22, width: 0, height: 14))

        let rtl = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: CGRect(x: 20, y: 20, width: 5, height: 16),
            next: CGRect(x: 15, y: 20, width: 5, height: 16),
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: false
        ).first)
        #expect(rtl == CGRect(x: 20, y: 20, width: 0, height: 16))
    }

    @Test func browserCaretFallbackFindsLTRAndRTLEdges() throws {
        let ltrEnd = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: CGRect(x: 10, y: 20, width: 5, height: 16),
            previous: CGRect(x: 15, y: 20, width: 5, height: 16),
            next: nil,
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: true
        ).first)
        #expect(ltrEnd == CGRect(x: 20, y: 20, width: 0, height: 16))

        let rtlEnd = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: CGRect(x: 20, y: 20, width: 5, height: 16),
            previous: CGRect(x: 15, y: 20, width: 5, height: 16),
            next: nil,
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: true
        ).first)
        #expect(rtlEnd == CGRect(x: 15, y: 20, width: 0, height: 16))

        let ltrStart = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: nil,
            next: CGRect(x: 10, y: 20, width: 5, height: 16),
            nextOuter: CGRect(x: 15, y: 20, width: 5, height: 16),
            isAtStart: true,
            isAtEnd: false
        ).first)
        #expect(ltrStart == CGRect(x: 10, y: 20, width: 0, height: 16))

        let rtlStart = try #require(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: nil,
            next: CGRect(x: 20, y: 20, width: 5, height: 16),
            nextOuter: CGRect(x: 15, y: 20, width: 5, height: 16),
            isAtStart: true,
            isAtEnd: false
        ).first)
        #expect(rtlStart == CGRect(x: 25, y: 20, width: 0, height: 16))
    }

    @Test func browserCaretFallbackRejectsAmbiguousEdges() {
        #expect(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: CGRect(x: 10, y: 20, width: 5, height: 16),
            next: nil,
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: true
        ).isEmpty)
        #expect(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: nil,
            next: nil,
            nextOuter: nil,
            isAtStart: true,
            isAtEnd: true
        ).isEmpty)
        #expect(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: CGRect(x: 10, y: 20, width: 5, height: 16),
            next: CGRect(x: 10, y: 50, width: 5, height: 16),
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: false
        ).isEmpty)
        #expect(CursorTextContextReader.contextMenuCaretBoundaryBounds(
            previousOuter: nil,
            previous: CGRect(x: 10, y: 20, width: 5, height: 16),
            next: CGRect(x: 10, y: 20, width: 5, height: 16),
            nextOuter: nil,
            isAtStart: false,
            isAtEnd: false
        ).isEmpty)
    }

    @Test func browserContextMenuCandidateRequiresTriggerPointProvenance() {
        let point = CGPoint(x: 100, y: 200)
        #expect(CursorTextContextReader.attributableContextMenuCandidates(
            ["competing", "captured"],
            triggerPoint: point,
            ownsTriggerPoint: { candidate, receivedPoint in
                candidate == "captured" && receivedPoint == point
            }
        ) == ["captured"])
        #expect(CursorTextContextReader.attributableContextMenuCandidates(
            ["competing"],
            triggerPoint: point,
            ownsTriggerPoint: { _, _ in false }
        ).isEmpty)
        #expect(CursorTextContextReader.attributableContextMenuCandidates(
            ["accessibility-action"],
            triggerPoint: nil,
            ownsTriggerPoint: { _, _ in false }
        ) == ["accessibility-action"])
    }

    @Test func accessibilityInsertionObservationAcceptsTextOrCursorMutation() {
        #expect(CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after",
            rangeAfterInsertion: CFRange(location: 16, length: 0)
        ))
        #expect(CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: nil,
            rangeBeforeInsertion: CFRange(location: 0, length: 0),
            insertedText: "👋",
            textAfterInsertion: nil,
            rangeAfterInsertion: CFRange(location: 2, length: 0)
        ))
    }

    @Test func accessibilityInsertionObservationRejectsUnrelatedTextMutation() {
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before unrelated after",
            rangeAfterInsertion: CFRange(location: 16, length: 0)
        ))
        #expect(!CursorTextContextReader.insertionWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after",
            rangeAfterInsertion: CFRange(location: 0, length: 0)
        ))
        #expect(CursorTextContextReader.replacementTextWasObserved(
            textBeforeInsertion: "before after",
            rangeBeforeInsertion: CFRange(location: 7, length: 0),
            insertedText: "dictated ",
            textAfterInsertion: "before dictated after"
        ))
    }

    @Test func accessibilityValueReplacementUsesUTF16Selection() throws {
        let replacement = try #require(CursorTextContextReader.valueReplacement(
            textBeforeInsertion: "before 👋 after",
            rangeBeforeInsertion: CFRange(location: 7, length: 2),
            insertedText: "dictated"
        ))

        #expect(replacement.text == "before dictated after")
        #expect(replacement.selectedRange.location == 15)
        #expect(replacement.selectedRange.length == 0)
    }

    @Test func accessibilityValueReplacementRejectsInvalidRange() {
        #expect(CursorTextContextReader.valueReplacement(
            textBeforeInsertion: "text",
            rangeBeforeInsertion: CFRange(location: 5, length: 0),
            insertedText: "dictated"
        ) == nil)
    }

    @Test func accessibilityValueReplacementRequiresExactRangeRestore() {
        let expectedRange = CFRange(location: 8, length: 0)

        #expect(CursorTextContextReader.valueReplacementWasObserved(
            text: "dictated",
            selectedRange: expectedRange,
            textAfterInsertion: "dictated",
            rangeAfterInsertion: expectedRange
        ))
        #expect(!CursorTextContextReader.valueReplacementWasObserved(
            text: "dictated",
            selectedRange: expectedRange,
            textAfterInsertion: "dictated",
            rangeAfterInsertion: CFRange(location: 0, length: 8)
        ))
    }

    @Test @MainActor func sessionMetricRecorderAcceptsSnapshotModelName() throws {
        let container = try makeSessionMetricContainer()
        let context = container.mainContext
        let transcription = Transcription(
            text: "quick release wins",
            duration: 2,
            transcriptionDuration: 0.5,
            transcriptionStatus: .completed
        )
        context.insert(transcription)
        try context.save()

        let didInsertMetric = try SessionMetricRecorder.recordRecorderSession(
            transcription: transcription,
            modelDisplayName: "Snapshot Model",
            in: context,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        try context.save()

        let metrics = try context.fetch(FetchDescriptor<SessionMetric>())
        #expect(didInsertMetric)
        #expect(metrics.count == 1)
        #expect(metrics.first?.transcriptionModelName == "Snapshot Model")
        #expect(metrics.first?.wordCount == 3)
        #expect(metrics.first?.speedFactor == 4.0)
    }

    @Test func resolvesAPIKeyEnvironmentReference() async throws {
        let environment = ["ELEVENLABS_API_KEY": "test-key"]

        #expect(VoiceInkAPIKeyReference.resolvedValue("$ELEVENLABS_API_KEY", environment: environment) == "test-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("${ELEVENLABS_API_KEY}", environment: environment) == "test-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("literal-key", environment: environment) == "literal-key")
        #expect(VoiceInkAPIKeyReference.resolvedValue("$MISSING", environment: environment) == nil)
    }

    @Test @MainActor func dictionaryServiceUsesWarmedWordReplacementCacheUntilInvalidated() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        context.insert(WordReplacement(originalText: "voice ink", replacementText: "roma"))
        try context.save()

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")

        context.insert(WordReplacement(originalText: "quick release", replacementText: "instant paste"))
        try context.save()

        #expect(DictionaryService.applyWordReplacements(to: "quick release", using: context) == "quick release")

        DictionaryService.invalidateWordReplacementCache()
        #expect(DictionaryService.applyWordReplacements(to: "quick release", using: context) == "instant paste")
    }

    @Test @MainActor func dictionaryServiceIgnoresDisabledWordReplacements() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        context.insert(
            WordReplacement(
                originalText: "voice ink",
                replacementText: "roma",
                isEnabled: false
            )
        )
        try context.save()

        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")
    }

    @Test @MainActor func dictionaryServiceWordReplacementSaveInvalidatesWarmedWordReplacementCache() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")

        let submission = VoiceInkWordReplacementDraftState(
            original: "voice ink",
            replacement: "roma"
        ).submitting(existingRules: [])
        let appliedSubmission = DictionaryService.applyWordReplacementSubmission(
            submission,
            context: context
        )

        #expect(appliedSubmission.alertPresentation == nil)
        #expect(appliedSubmission.plan.shouldComplete)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")
    }

    @Test @MainActor func dictionaryServiceWordReplacementRemovalInvalidatesWarmedWordReplacementCache() throws {
        let container = try makeWordReplacementContainer()
        let context = container.mainContext
        DictionaryService.invalidateWordReplacementCache()
        defer { DictionaryService.invalidateWordReplacementCache() }

        let replacement = WordReplacement(originalText: "voice ink", replacementText: "roma")
        context.insert(replacement)
        try context.save()

        DictionaryService.warmWordReplacementCache(using: context)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "roma")

        #expect(DictionaryService.removeWordReplacement(replacement, context: context) == nil)
        #expect(DictionaryService.applyWordReplacements(to: "voice ink", using: context) == "voice ink")
    }

    @Test @MainActor func dictionaryServiceVocabularyRemovalDeletesWord() throws {
        let container = try makeVocabularyContainer()
        let context = container.mainContext
        let word = VocabularyWord(word: "roma")
        context.insert(word)
        context.insert(VocabularyWord(word: "voice ink"))
        try context.save()

        #expect(DictionaryService.removeVocabularyWord(word, context: context) == nil)

        let words = try context.fetch(FetchDescriptor<VocabularyWord>())
            .map(\.word)
            .sorted()
        #expect(words == ["voice ink"])
    }

    @Test @MainActor func aiEnhancementServiceCachesPromptTriggerEligibility() throws {
        let savedPrompts = UserDefaults.standard.data(forKey: "customPrompts")
        let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId")
        defer {
            if let savedPrompts {
                UserDefaults.standard.set(savedPrompts, forKey: "customPrompts")
            } else {
                UserDefaults.standard.removeObject(forKey: "customPrompts")
            }
            if let savedPromptId {
                UserDefaults.standard.set(savedPromptId, forKey: "selectedPromptId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPromptId")
            }
        }

        let container = try makeWordReplacementContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        service.customPrompts = []

        #expect(!service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.isEmpty)

        let triggerPrompt = VoiceInkCustomPrompt(
            title: "Fast Trigger",
            promptText: "Clean this",
            triggerWords: ["clean"]
        )
        service.customPrompts = [triggerPrompt]

        #expect(service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.map(\.id) == [triggerPrompt.id])

        service.customPrompts = [
            VoiceInkCustomPrompt(
                title: "Blank Trigger",
                promptText: "Clean this",
                triggerWords: ["   "]
            )
        ]

        #expect(!service.hasPromptTriggerWords)
        #expect(service.promptDetectionPrompts.isEmpty)
    }

    @Test @MainActor func promptDetectionUsesCachedTriggerPrompts() throws {
        let savedPrompts = UserDefaults.standard.data(forKey: "customPrompts")
        let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId")
        defer {
            if let savedPrompts {
                UserDefaults.standard.set(savedPrompts, forKey: "customPrompts")
            } else {
                UserDefaults.standard.removeObject(forKey: "customPrompts")
            }
            if let savedPromptId {
                UserDefaults.standard.set(savedPromptId, forKey: "selectedPromptId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPromptId")
            }
        }

        let container = try makeWordReplacementContainer()
        let service = AIEnhancementService(modelContext: container.mainContext)
        let triggerPrompt = VoiceInkCustomPrompt(
            title: "Assistant Trigger",
            promptText: "Answer directly",
            triggerWords: ["answer"]
        )
        service.customPrompts = [
            VoiceInkCustomPrompt(title: "No Trigger", promptText: "Clean this"),
            triggerPrompt
        ]

        let detection = VoiceInkPromptDetectionPolicy.analyzeText(
            "answer what is this?",
            prompts: service.promptDetectionPrompts,
            isEnhancementEnabled: false,
            selectedPromptId: nil
        )

        #expect(detection.shouldEnableAI)
        #expect(detection.selectedPromptId == triggerPrompt.id)
        #expect(detection.processedText == "What is this?")
    }

    @Test @MainActor func noneRecorderStyleStartsSessionWithoutShowingRecorderWindow() async throws {
        let oldRecorderType = UserDefaults.standard.string(forKey: "RecorderType")
        defer {
            if let oldRecorderType {
                UserDefaults.standard.set(oldRecorderType, forKey: "RecorderType")
            } else {
                UserDefaults.standard.removeObject(forKey: "RecorderType")
            }
        }

        UserDefaults.standard.set("none", forKey: "RecorderType")
        let manager = RecorderUIManager()

        manager.beginRecorderSession()

        #expect(manager.isRecorderSessionActive)
        #expect(!manager.isMiniRecorderVisible)
        #expect(manager.miniWindowManager == nil)
        #expect(manager.notchWindowManager == nil)
    }

    @Test @MainActor func idleNoneRecorderSessionDoesNotBlockNextShortcutStart() async throws {
        let oldRecorderType = UserDefaults.standard.string(forKey: "RecorderType")
        defer {
            if let oldRecorderType {
                UserDefaults.standard.set(oldRecorderType, forKey: "RecorderType")
            } else {
                UserDefaults.standard.removeObject(forKey: "RecorderType")
            }
        }

        UserDefaults.standard.set("none", forKey: "RecorderType")
        let manager = RecorderUIManager()

        manager.beginRecorderSession()

        #expect(manager.isRecorderSessionActive)
        #expect(!manager.isActiveForRecordingShortcut(recordingState: .idle))
        #expect(manager.isActiveForRecordingShortcut(recordingState: .starting))
        #expect(manager.isActiveForRecordingShortcut(recordingState: .recording))
    }

    @Test @MainActor func activeRecorderToggleDefersStopInsteadOfCancelingWhileStarting() async throws {
        var events: [String] = []

        for state in [
            VoiceInkRecordingState.starting,
            .recording,
            .transcribing,
            .enhancing,
            .idle,
            .busy,
        ] {
            await state.applyRecorderUIToggleRuntimeState(
                toggleRecord: { events.append("toggle") },
                cancelRecording: { events.append("cancel") },
                dismissRecorder: { events.append("dismiss") }
            )
        }

        #expect(events == [
            "toggle",
            "toggle",
            "cancel",
            "cancel",
            "dismiss",
            "dismiss",
        ])
    }

    @Test @MainActor func pushToTalkUsesActiveSessionWhenRecorderWindowIsNone() async throws {
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .pushToTalk
        )

        #expect(toggleCount == 1)
        #expect(sessionActive)

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .pushToTalk
        )

        #expect(toggleCount == 2)
        #expect(!sessionActive)
    }

    @Test @MainActor func shortcutCooldownAllowsFastBackToBackPressAfterDuplicateGuard() async throws {
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .pushToTalk
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.1,
            mode: .pushToTalk
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .pushToTalk
        )
        #expect(toggleCount == 2)

        try await Task.sleep(nanoseconds: 100_000_000)

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1.3,
            mode: .pushToTalk
        )

        #expect(toggleCount == 3)
        #expect(sessionActive)
    }

    @Test @MainActor func specialModeStartsRecordingImmediatelyOnKeyDown() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                recordingState = .recording
                sessionActive = true
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )

        #expect(toggleCount == 1)
        #expect(recordingState == .recording)
        #expect(sessionActive)
    }

    @Test @MainActor func specialModeCleanReleaseStopsRecording() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
                recordingState = sessionActive ? .recording : .idle
            },
            cancelRecording: {}
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .special,
            context: VoiceInkShortcutPressContext()
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeUnsafeKeyEvidenceCancelsStartedRecording() async throws {
        var recordingState = VoiceInkRecordingState.idle
        var sessionActive = false
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                recordingState = .recording
                sessionActive = true
            },
            cancelRecording: {
                cancelCount += 1
                recordingState = .idle
                sessionActive = false
            }
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special
        )
        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 1.2,
            mode: .special,
            context: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)
        )

        #expect(cancelCount == 1)
        #expect(recordingState == .idle)
        #expect(!sessionActive)
    }

    @Test func shortcutKeyEvidenceTraceDetailsIdentifyEveryCause() {
        #expect(RecordingShortcutModeHandler.keyEvidenceTraceDetails(
            VoiceInkShortcutPressContext(
                didPressOtherKeyDuringPress: true,
                didReleaseOtherKeyDuringPress: false,
                hasReliableKeyEvidence: false
            )
        ) == "pressedOtherKey=true releasedOtherKey=false reliable=false")
    }

    @Test func inputMonitoringPermissionUsesInjectedSystemClient() async throws {
        var didRequestAccess = false
        let client = InputMonitoringPermission.Client(
            preflight: { false },
            request: {
                didRequestAccess = true
                return true
            }
        )

        #expect(!InputMonitoringPermission.isGranted(client: client))
        #expect(InputMonitoringPermission.requestAccess(client: client))
        #expect(didRequestAccess)
    }

    @Test func accessibilityPermissionUsesInjectedSystemClient() async throws {
        var didRequestAccess = false
        let client = AccessibilityPermission.Client(
            preflight: { false },
            request: {
                didRequestAccess = true
                return true
            }
        )

        #expect(!AccessibilityPermission.isGranted(client: client))
        #expect(AccessibilityPermission.requestAccess(client: client))
        #expect(didRequestAccess)
    }

    @Test @MainActor func permissionNotificationSuppressionScopesNestUntilLastScopeEnds() {
        let suppression = PermissionNotificationSuppression()

        #expect(!suppression.isSuppressingPermissionPrompts)

        let firstScope = suppression.beginScope()
        let secondScope = suppression.beginScope()

        #expect(suppression.isSuppressingPermissionPrompts)

        suppression.endScope(firstScope)
        #expect(suppression.isSuppressingPermissionPrompts)

        suppression.endScope(secondScope)
        #expect(!suppression.isSuppressingPermissionPrompts)
    }

    @Test func macOnboardingProgressStorePersistsStageAndPermissionCursor() {
        let defaults = UserDefaults(suiteName: "MacOnboardingProgressStoreTests")!
        defaults.removePersistentDomain(forName: "MacOnboardingProgressStoreTests")
        defer {
            defaults.removePersistentDomain(forName: "MacOnboardingProgressStoreTests")
        }

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .welcome)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == nil)

        VoiceInkMacOSOnboardingProgressStore.saveStage(.permissions, in: defaults)
        VoiceInkMacOSOnboardingProgressStore.savePermissionKind(.inputMonitoring, in: defaults)

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .permissions)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == .inputMonitoring)

        VoiceInkMacOSOnboardingProgressStore.reset(in: defaults)

        #expect(VoiceInkMacOSOnboardingProgressStore.stage(in: defaults) == .welcome)
        #expect(VoiceInkMacOSOnboardingProgressStore.permissionKind(in: defaults) == nil)
    }

    @Test func modifierOnlyShortcutsUseNSEventMonitorPath() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0
        var keyUpCount = 0

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_RightOption),
                    modifierFlags: [.option]
                )
            ],
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, _ in keyUpCount += 1 }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 1
        )
        await drainMainQueue()
        #expect(keyDownCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2
        )
        await drainMainQueue()
        #expect(keyDownCount == 1)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2.5
        )
        await drainMainQueue()
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [],
            eventTime: 3
        )
        await drainMainQueue()
        #expect(keyUpCount == 1)
    }

    @Test func modifierOnlyShortcutTracksOtherKeyDownWithoutReleaseEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []
        var contextUpdates: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) },
            onPressContextChanged: { _, context in contextUpdates.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 2
        )
        #expect(await eventually { contextUpdates.count == 1 })
        #expect(contextUpdates == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutUsesEventTapOrderingWhenTrackingKeyEvidence() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_S),
            modifierFlags: [.shift],
            eventTime: 2
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { keyDownCount == 1 && contexts.count == 1 })
        #expect(keyDownCount == 1)
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutTracksSystemDefinedEvidenceDuringPress() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleSystemDefinedForTesting(eventTime: 2)
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
    }

    @Test func modifierOnlyShortcutMarksSecureInputAsUnreliableEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { true })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 2
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(hasReliableKeyEvidence: false)])
    }

    @Test func modifierOnlyShortcutChecksPressedNonModifierKeysAtRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { false })
        )
        ShortcutMonitor.configureKeyboardStateClientForTesting(
            KeyboardState.Client(isKeyPressed: { keyCode in keyCode == UInt16(kVK_ANSI_X) })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 2
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlySpecialShortcutDoesNotStartWithoutKeyEvidenceTap() async throws {
        let monitor = ShortcutMonitor()
        var keyDownCount = 0

        ShortcutMonitor.configurePermissionClientsForTesting(
            inputMonitoringClient: InputMonitoringPermission.Client(
                preflight: { false },
                request: { false }
            ),
            accessibilityClient: AccessibilityPermission.Client(
                preflight: { true },
                request: { true }
            )
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetPermissionClientsForTesting()
        }

        let started = monitor.start(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            tracksKeyUpEvidence: true,
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, _ in }
        )

        #expect(!started)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )

        #expect(!(await eventually { keyDownCount > 0 }))
    }

    @Test func modifierOnlyShortcutMarksOtherKeyUpAsTyping() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { false })
        )
        ShortcutMonitor.configureKeyboardStateClientForTesting(
            KeyboardState.Client(isKeyPressed: { _ in false })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
            ShortcutMonitor.resetKeyboardStateClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleKeyDownForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 2
        )
        monitor.handleKeyUpForTesting(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            eventTime: 3
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 4
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlyShortcutTracksOtherModifierPressAndRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [VoiceInkShortcutPressContext] = []

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { _, _, context in contexts.append(context) }
        )

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.shift, .option],
            eventTime: 2
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.shift],
            eventTime: 3
        )
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 4
        )

        #expect(await eventually { contexts.count == 1 })
        #expect(contexts == [VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test @MainActor func shortcutRecorderCancelRestoresStoredShortcut() throws {
        let action = ShortcutAction.powerMode(UUID())
        let originalShortcut = Shortcut.key(keyCode: UInt16(kVK_F13), modifierFlags: [])

        try withTemporaryShortcutStorage(for: action) {
            ShortcutStore.setShortcut(originalShortcut, for: action)

            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })

            #expect(ShortcutStore.shortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))

            recorder.cancel()

            #expect(ShortcutStore.shortcut(for: action) == originalShortcut)
            #expect(!ShortcutStore.isShortcutCleared(for: action))
        }
    }

    @Test @MainActor func shortcutRecorderCancelRestoresDefaultShortcutState() throws {
        let action = ShortcutAction.powerMode(UUID())

        try withTemporaryShortcutStorage(for: action) {
            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))

            recorder.cancel()

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(!ShortcutStore.isShortcutCleared(for: action))
        }
    }

    @Test @MainActor func shortcutRecorderCancelPreservesClearedShortcutState() throws {
        let action = ShortcutAction.powerMode(UUID())

        try withTemporaryShortcutStorage(for: action) {
            ShortcutStore.setShortcut(nil, for: action)

            let recorder = ShortcutRecorderModel()
            recorder.start(action: action, onCapture: { _ in })
            recorder.cancel()

            #expect(ShortcutStore.rawShortcut(for: action) == nil)
            #expect(ShortcutStore.isShortcutCleared(for: action))
        }
    }

    private func makeWordReplacementContainer() throws -> ModelContainer {
        let schema = Schema([WordReplacement.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeVocabularyContainer() throws -> ModelContainer {
        let schema = Schema([VocabularyWord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSessionMetricContainer() throws -> ModelContainer {
        let schema = Schema([Transcription.self, SessionMetric.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func withTemporaryShortcutStorage(for action: ShortcutAction, _ body: () throws -> Void) throws {
        ShortcutStore.removeShortcutStorage(for: action)
        defer { ShortcutStore.removeShortcutStorage(for: action) }
        try body()
    }

    private func restoreDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<20 {
            await drainMainQueue()
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await drainMainQueue()
        return predicate()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

}
