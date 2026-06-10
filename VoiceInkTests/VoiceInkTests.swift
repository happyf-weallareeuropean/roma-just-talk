//
//  VoiceInkTests.swift
//  VoiceInkTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
import Carbon.HIToolbox
import os
@testable import VoiceInk

struct VoiceInkTests {

    @Test func freshDefaultsHideMenuBarIcon() async throws {
        #expect(AppDefaults.registeredDefaults[AppDefaults.Keys.showMenuBarIcon] as? Bool == false)
        #expect(AppDefaults.registeredDefaults["IsMenuBarOnly"] as? Bool == true)
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.keyDownBehaviorKey] as? String == SpecialShortcutKeyDownBehavior.startRecording.rawValue)
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.allowsKeyDownOnlyTriggerKey] as? Bool == true)
        #expect(AppDefaults.registeredDefaults[SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey] as? Bool == true)
    }

    @Test func resolvesAPIKeyEnvironmentReference() async throws {
        let environment = ["ELEVENLABS_API_KEY": "test-key"]

        #expect(APIKeyManager.resolveAPIKeyReference("$ELEVENLABS_API_KEY", environment: environment) == "test-key")
        #expect(APIKeyManager.resolveAPIKeyReference("${ELEVENLABS_API_KEY}", environment: environment) == "test-key")
        #expect(APIKeyManager.resolveAPIKeyReference("literal-key", environment: environment) == "literal-key")
        #expect(APIKeyManager.resolveAPIKeyReference("$MISSING", environment: environment) == nil)
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

    @Test @MainActor func specialModeStopsWhenNoOtherKeyWasReleased() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didReleaseOtherKeyDuringPress: false)
        )

        #expect(toggleCount == 2)
        #expect(cancelCount == 0)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCancelsWhenAnotherKeyWasReleased() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didReleaseOtherKeyDuringPress: true)
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
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

    @Test @MainActor func inputMonitoringGrantUsesPermissionFlowGuide() async throws {
        var didBeginPolling = false
        var didRequestAccess = false
        var didOpenGuide = false
        var reportedGrant: Bool?

        let client = PermissionGrantCoordinator.Client(
            beginPolling: { didBeginPolling = true },
            microphoneStatus: { .authorized },
            requestMicrophone: { _ in },
            openMicrophonePane: {},
            requestInputMonitoring: {
                didRequestAccess = true
                return false
            },
            isInputMonitoringGranted: { false },
            openInputMonitoringPane: { didOpenGuide = true },
            requestAccessibility: { true },
            openAccessibilityPane: {},
            openScreenRecordingPane: {}
        )

        PermissionGrantCoordinator.grantInputMonitoring(client: client) { granted in
            reportedGrant = granted
        }

        #expect(didBeginPolling)
        #expect(didRequestAccess)
        #expect(didOpenGuide)
        #expect(reportedGrant == false)
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
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 1)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [.option],
            eventTime: 2.5
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 0)

        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: [],
            eventTime: 3
        )
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyUpCount == 1)
    }

    @Test func modifierOnlyShortcutTracksOtherKeyDownWithoutReleaseEvidence() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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
        monitor.handleModifierOnlyFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 3
        )

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)])
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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(keyDownCount == 0)
    }

    @Test func modifierOnlyShortcutMarksOtherKeyUpAsTyping() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test func modifierOnlyShortcutTracksOtherModifierPressAndRelease() async throws {
        let monitor = ShortcutMonitor()
        var contexts: [ShortcutPressContext] = []

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

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(contexts == [ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: true)])
    }

    @Test @MainActor func specialModeAllowsKeyDownOnlyTypingByDefault() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
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
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false)
        )

        #expect(toggleCount == 2)
        #expect(cancelCount == 0)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModeCanCancelKeyDownOnlyTypingWhenFlexIsOff() async throws {
        var sessionActive = false
        var toggleCount = 0
        var cancelCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { sessionActive ? .recording : .idle },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                sessionActive.toggle()
            },
            cancelRecording: {
                cancelCount += 1
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .startRecording,
            allowsKeyDownOnlyTrigger: false,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(didPressOtherKeyDuringPress: true, didReleaseOtherKeyDuringPress: false),
            specialOptions: specialOptions
        )

        #expect(toggleCount == 1)
        #expect(cancelCount == 1)
        #expect(!sessionActive)
    }

    @Test @MainActor func specialModePreloadOnlyStartsAndStopsOnKeyUp() async throws {
        var recordingState = RecordingState.idle
        var sessionActive = false
        var toggleCount = 0

        let handler = RecordingShortcutModeHandler(
            logger: Logger(subsystem: "VoiceInkTests", category: "RecordingShortcutModeHandler"),
            canHandleShortcutAction: { true },
            isRecorderVisible: { sessionActive },
            recordingState: { recordingState },
            toggleMiniRecorder: { _ in
                toggleCount += 1
                if recordingState == .idle {
                    recordingState = .recording
                    sessionActive = true
                } else {
                    recordingState = .transcribing
                    sessionActive = true
                }
            },
            cancelRecording: {
                recordingState = .idle
                sessionActive = false
            }
        )

        let specialOptions = SpecialShortcutOptions(
            keyDownBehavior: .preloadOnly,
            allowsKeyDownOnlyTrigger: true,
            pasteLastTranscriptOnEmptyTap: true
        )

        await handler.handleKeyDown(
            action: .primaryRecording,
            eventTime: 1,
            mode: .special,
            specialOptions: specialOptions
        )

        #expect(toggleCount == 0)
        #expect(recordingState == .idle)

        await handler.handleKeyUp(
            action: .primaryRecording,
            eventTime: 2,
            mode: .special,
            context: ShortcutPressContext(),
            specialOptions: specialOptions
        )

        #expect(toggleCount == 2)
        #expect(recordingState == .transcribing)
    }

}
