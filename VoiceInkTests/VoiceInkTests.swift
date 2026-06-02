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
        #expect(TranscriptionOutputFilter.filter("mm-hmm... uh-huh, I think so.") == "I think so.")
        #expect(TranscriptionOutputFilter.filter("uh-uh... not that.") == "not that.")
        #expect(TranscriptionOutputFilter.filter("mhmm, this works.") == "this works.")
        #expect(TranscriptionOutputFilter.filter("no no this is fine") == "no no this is fine")
        #expect(TranscriptionOutputFilter.filter("I think this works. I think this works.") == "I think this works.")
        #expect(TranscriptionOutputFilter.filter("Ship the model. ship the model.") == "Ship the model.")
        #expect(TranscriptionOutputFilter.filter("Okay. Okay.") == "Okay. Okay.")
    }

    @Test func insertionPolishUsesCursorContextForMidSentenceFragments() async throws {
        let midSentenceContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "...so this")
        let sentenceStartContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
        let questionContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done?")
        let exclamationContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done!")
        let colonContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Note:")
        let selectedTextContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done?", selectedText: "old")
        let openParenthesisContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "(")
        let wordBeforeParenthesisContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Use")
        let wordBeforeQuoteContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "She said")
        let newLineContext = TranscriptionOutputFilter.TextInsertionContext(precedingText: "Done\n")

        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: midSentenceContext) == "model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("model", context: midSentenceContext) == " model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("Model", context: questionContext) == " Model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("Model", context: exclamationContext) == " Model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("model", context: colonContext) == " model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("Model", context: selectedTextContext) == "Model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("model", context: openParenthesisContext) == "model")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("(model)", context: wordBeforeParenthesisContext) == " (model)")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("\"hello\"", context: wordBeforeQuoteContext) == " \"hello\"")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing("/users", context: wordBeforeParenthesisContext) == "/users")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Comma.", context: midSentenceContext) == ",")
        #expect(TranscriptionOutputFilter.applyInsertionSpacing(",", context: midSentenceContext) == ",")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Question mark.", context: midSentenceContext) == "?")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Model.", context: sentenceStartContext) == "Model")
        #expect(TranscriptionOutputFilter.applyInsertionPolish("Comma.", context: sentenceStartContext) == "Comma")
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

    @Test func transcriptionFilterAppliesSpokenFormattingCommands() async throws {
        #expect(TranscriptionOutputFilter.filter("First line new line second line.") == "First line\nsecond line.")
        #expect(TranscriptionOutputFilter.filter("Intro new paragraph Details.") == "Intro\n\nDetails.")
        #expect(TranscriptionOutputFilter.filter("Todo new line bullet point first item new line bullet point second item.") == "Todo\n- first item\n- second item")
        #expect(TranscriptionOutputFilter.filter("This newlineish word should stay.") == "This newlineish word should stay.")
    }

    @Test func transcriptionFilterAppliesSpokenEnclosureCommands() async throws {
        #expect(TranscriptionOutputFilter.filter("She said open quote hello close quote.") == "She said \"hello\".")
        #expect(TranscriptionOutputFilter.filter("Open quote hello comma world close quote.") == "\"hello, world\".")
        #expect(TranscriptionOutputFilter.filter("Use open parenthesis model close parenthesis now.") == "Use (model) now.")
        #expect(TranscriptionOutputFilter.filter("The quote field stays.") == "The quote field stays.")
    }

    @Test func transcriptionFilterAppliesGuardedSpokenSymbolCommands() async throws {
        #expect(TranscriptionOutputFilter.filter("Use api slash users.") == "Use api/users.")
        #expect(TranscriptionOutputFilter.filter("Use model hyphen beta.") == "Use model-beta.")
        #expect(TranscriptionOutputFilter.filter("Use path backslash temp.") == "Use path\\temp.")
        #expect(TranscriptionOutputFilter.filter("Use the slash command.") == "Use the slash command.")
        #expect(TranscriptionOutputFilter.filter("Add a dash of salt.") == "Add a dash of salt.")
    }

    @Test func transcriptionFilterRemovesCommonASRBoilerplate() async throws {
        #expect(TranscriptionOutputFilter.filter("Thank you for watching.") == "")
        #expect(TranscriptionOutputFilter.filter("Okay. Thank you for watching.") == "Okay.")
        #expect(TranscriptionOutputFilter.filter("Ship it.\nSubtitles by Amara.org community") == "Ship it.")
        #expect(TranscriptionOutputFilter.filter("Thank you for helping.") == "Thank you for helping.")
        #expect(TranscriptionOutputFilter.filter("End with thank you for watching.") == "End with thank you for watching.")
    }

    @Test func transcriptionFilterAppliesConservativeSpokenPunctuationCommands() async throws {
        #expect(TranscriptionOutputFilter.filter("Hello comma world full stop") == "Hello, world.")
        #expect(TranscriptionOutputFilter.filter("Are you coming question mark") == "Are you coming?")
        #expect(TranscriptionOutputFilter.filter("Ship it exclamation mark") == "Ship it!")
        #expect(TranscriptionOutputFilter.filter("Use model semicolon retry colon now") == "Use model; retry: now")
        #expect(TranscriptionOutputFilter.filter("This is a trial period") == "This is a trial period")
        #expect(TranscriptionOutputFilter.filter("Use the Oxford comma") == "Use the Oxford comma")
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
