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

    @Test func transcriptionFilterCleansPauseNoiseAndRepeatedWords() async throws {
        let oldRemoveFillerWords = UserDefaults.standard.object(forKey: "RemoveFillerWords")
        defer {
            if let oldRemoveFillerWords {
                UserDefaults.standard.set(oldRemoveFillerWords, forKey: "RemoveFillerWords")
            } else {
                UserDefaults.standard.removeObject(forKey: "RemoveFillerWords")
            }
        }

        UserDefaults.standard.set(true, forKey: "RemoveFillerWords")

        #expect(TranscriptionOutputFilter.filter("[Model.]") == "Model.")
        #expect(TranscriptionOutputFilter.filter("hmm.... eh... I I think think this this works.") == "I think this works.")
        #expect(TranscriptionOutputFilter.filter("no no this is fine") == "no no this is fine")
    }

    @Test func insertionPolishUsesCursorContextForMidSentenceFragments() async throws {
        let midSentenceContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "...so this")
        let sentenceStartContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
        let newLineContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done\n")

        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: midSentenceContext) == "model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("model", context: midSentenceContext) == " model")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: sentenceStartContext) == "Model")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: newLineContext) == "Model")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: nil) == "model")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("VoiceInk.", context: nil) == "VoiceInk")
    }

    @Test func transcriptionFilterAppliesBoundedBacktrackingCorrections() async throws {
        #expect(TranscriptionOutputFilter.filter("Let's meet at two, wait no, three.") == "Let's meet at three.")
        #expect(TranscriptionOutputFilter.filter("The meeting is on Tuesday, sorry not that, actually Wednesday.") == "The meeting is on Wednesday.")
        #expect(TranscriptionOutputFilter.filter("Use model wait no models.") == "Use models.")
        #expect(TranscriptionOutputFilter.filter("Let's meet at two... actually three.") == "Let's meet at three.")
        #expect(TranscriptionOutputFilter.filter("I actually think this works.") == "I actually think this works.")
        #expect(TranscriptionOutputFilter.filter("I mean this is wrong wait no right.") == "I mean this is right.")
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
            onKeyUp: { _, _ in keyUpCount += 1 }
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

}
