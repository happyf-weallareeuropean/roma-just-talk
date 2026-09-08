import Foundation
import RuntimeE2ECore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(
    _ actual: Double,
    equals expected: Double,
    accuracy: Double = 0.000_001,
    _ message: String
) throws {
    guard abs(actual - expected) <= accuracy else {
        throw CheckFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw CheckFailure(description: message)
    }
}

do {
    let plan = try RuntimeTimingPlan(
        audioDurationSeconds: 12.03125,
        audioLeadSeconds: 1.1,
        releaseTailSeconds: 0.15
    )

    try require(plan.keyDownOffsetSeconds, equals: 1.1, "key-down offset")
    try require(plan.keyUpOffsetSeconds, equals: 12.18125, "key-up offset")
    try require(plan.holdDurationSeconds, equals: 11.08125, "hold duration")
    try require(
        plan.keyUpSystemUptime(
            audioStartedAtSystemUptime: 100,
            audioFinishedAtSystemUptime: 112.8
        ),
        equals: 112.95,
        "key-up must follow real playback completion and the release tail"
    )
    try require(
        RuntimePlaybackReleasePolicy.waitsForPlaybackCompletion(explicitHoldSeconds: nil),
        "fixture-timed runs must wait for real playback completion"
    )
    try require(
        !RuntimePlaybackReleasePolicy.waitsForPlaybackCompletion(explicitHoldSeconds: 2),
        "explicit-hold probes must keep their requested schedule"
    )
    print("PASS speech starts 1.1 seconds before key-down and release follows fixture")

    let fixtures = [
        URL(fileURLWithPath: "/audio/normal noisy clear.wav"),
        URL(fileURLWithPath: "/audio/normal wispering.wav")
    ]
    let targets = RuntimeTargetApp.defaultMatrix
    let runPlan = try RuntimeRunPlan.make(
        fixtureURLs: fixtures,
        expectedTranscripts: ["normal noisy clear.wav": "expected noisy speech"],
        targets: targets,
        repetitions: 2
    )

    try require(targets.count == 6, "default target matrix should contain six apps")
    try require(
        runPlan.cases.count == 48,
        "two fixtures x six apps x two text scenarios x two repetitions should create forty-eight cases"
    )
    try require(
        runPlan.cases.first?.expectedTranscript == "expected noisy speech",
        "fixture answer should flow into each case when supplied"
    )
    try require(
        runPlan.cases.contains { $0.fixtureURL.lastPathComponent == "normal wispering.wav" && $0.expectedTranscript == nil },
        "fixtures without answers should remain runnable without content assertions"
    )
    try require(
        Set(runPlan.cases.map(\.textScenario)) == Set(RuntimeTextScenario.allCases),
        "every runtime matrix must cover empty and existing-text cursor baselines"
    )
    let existingTextScenario = RuntimeTextScenario.existingText
    try require(
        existingTextScenario.insertedText(
            from: existingTextScenario.prefix + "dictated text" + existingTextScenario.suffix
        ) == "dictated text",
        "existing-text cases must preserve both sides and isolate inserted text"
    )
    try require(
        existingTextScenario.insertedText(from: "dictated text") == nil,
        "existing-text cases must fail if either side is lost"
    )
    let singlePasteProof = RuntimeDOMPasteProof.parse(
        from: "Roma Runtime E2E Paste Proof pasteEvents=1 pasteInputs=1"
    )
    try require(
        singlePasteProof?.provesExactlyOnePaste == true,
        "browser proof must accept exactly one paste event and one paste-backed input"
    )
    try require(
        !RuntimeDOMPasteProof(pasteEventCount: 2, pasteInputCount: 2)
            .provesExactlyOnePaste,
        "browser proof must reject duplicate paste operations"
    )
    try require(
        RuntimeTargetIsolationPlan.runID(
            "fixture-chrome-existingText-r1-ABC123",
            belongsToTargetID: "chrome"
        ),
        "abandoned-target cleanup must recognize text-scenario run IDs"
    )
    try require(
        RuntimeTargetIsolationPlan.runID("fixture-chrome-r1-ABC123", belongsToTargetID: "chrome"),
        "abandoned-target cleanup must retain legacy run-ID support"
    )
    for target in targets {
        for scenario in RuntimeTextScenario.allCases {
            let calibrationRunID = RuntimeTargetIsolationPlan.visibilityCalibrationRunID(
                targetID: target.id,
                textScenario: scenario
            )
            try require(
                RuntimeTargetIsolationPlan.runID(calibrationRunID, belongsToTargetID: target.id),
                "interrupted visibility calibration must be recoverable for its actual target"
            )
            for otherTarget in targets where otherTarget.id != target.id {
                try require(
                    !RuntimeTargetIsolationPlan.runID(calibrationRunID, belongsToTargetID: otherTarget.id),
                    "calibration cleanup must not claim a different target's resources"
                )
            }
        }
    }
    print("PASS fixture/app/text-scenario/repetition matrix carries optional transcript answers")

    try require(targets.contains { $0.kind == .electron }, "default matrix should cover an Electron editor")
    try require(RuntimeTargetApp.Kind.electron.usesDocumentResource, "Electron editors should open isolated files")
    try require(RuntimeTargetApp.Kind.electron.requiresPasteSemantics, "Electron editors must exercise native paste events")
    try require(!RuntimeTargetApp.Kind.document.requiresPasteSemantics, "native documents may retain direct AX insertion")
    try require(
        !RuntimeTargetApp.Kind.electron.satisfiesPasteSemantics(
            directAccessibilityInsertionSucceeded: true,
            clipboardPasteHandoffCompleted: false
        ),
        "Electron direct AX insertion must fail paste-semantics validation"
    )
    try require(
        RuntimeTargetApp.Kind.electron.satisfiesPasteSemantics(
            directAccessibilityInsertionSucceeded: false,
            clipboardPasteHandoffCompleted: true
        ),
        "Electron clipboard insertion must satisfy paste-semantics validation"
    )
    try require(
        RuntimeTargetApp.Kind.document.satisfiesPasteSemantics(
            directAccessibilityInsertionSucceeded: true,
            clipboardPasteHandoffCompleted: false
        ),
        "native document AX insertion must remain allowed"
    )

    let noPaste = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: false,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440
    )
    try require(noPaste.status == .noPaste, "missing target text should be classified as noPaste")
    try require(!noPaste.passed, "noPaste must fail the case")
    print("PASS missing target insertion is an explicit noPaste failure")

    let duplicateBrowserPaste = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "dictated textdictated text",
            keyUpToVisibleMilliseconds: 100,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 250,
        pasteOperationCountSatisfied: false
    )
    try require(
        duplicateBrowserPaste.status == .pasteOperationCountMismatch
            && !duplicateBrowserPaste.passed,
        "visible browser text must fail when DOM reports duplicate paste operations"
    )
    print("PASS browser target requires exactly one paste-backed DOM input")

    let emptyTranscript = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        transcribedCharacterCount: 0
    )
    try require(
        emptyTranscript.status == .emptyTranscript,
        "a successful zero-character transcription must not be blamed on paste delivery"
    )
    print("PASS empty transcription remains distinct from clipboard and target failures")

    let shortcutTimingMismatch = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        shortcutHoldMatched: false,
        transcriptionCompleted: false
    )
    try require(
        shortcutTimingMismatch.status == .shortcutTimingMismatch,
        "an app-observed hold that disagrees with the posted hold must remain an input-delivery failure"
    )

    let incompleteTranscription = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440,
        shortcutHoldMatched: true,
        transcriptionCompleted: false
    )
    try require(
        incompleteTranscription.status == .transcriptionIncomplete,
        "an incomplete VoiceInk trace must not be classified from unrelated clipboard changes"
    )
    print("PASS shortcut delivery and incomplete transcription remain distinct from paste failures")

    let pendingMicrophoneTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=B1B2B3B4 seq=0 t=0.0ms delta=0.0ms event=engine.permission.request",
        "[LATENCY] trace=B1B2B3B4 seq=1 t=0.9ms delta=0.9ms event=permission.authorization_status.end durationMs=0.1 status=undetermined",
        "[LATENCY] trace=B1B2B3B4 seq=2 t=3402.8ms delta=3401.9ms event=shortcut.key_up_handler state=idle"
    ])
    try require(
        pendingMicrophoneTrace?.microphonePermissionUnavailable == true,
        "an unanswered microphone authorization request must remain distinct from transcription"
    )
    let deniedMicrophoneTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=B5B6B7B8 seq=0 t=0.0ms delta=0.0ms event=engine.permission.denied"
    ])
    try require(
        deniedMicrophoneTrace?.microphonePermissionUnavailable == true,
        "an explicit microphone denial must remain distinct from transcription"
    )
    let rejectedMicrophoneCallbackTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=B9B0B1B2 seq=0 t=0.0ms delta=0.0ms event=engine.permission.callback granted=false"
    ])
    try require(
        rejectedMicrophoneCallbackTrace?.microphonePermissionUnavailable == true,
        "a rejected microphone callback must remain distinct from transcription"
    )
    let grantedMicrophoneTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=B3B4B5B6 seq=0 t=0.0ms delta=0.0ms event=engine.permission.request",
        "[LATENCY] trace=B3B4B5B6 seq=1 t=0.9ms delta=0.9ms event=permission.authorization_status.end durationMs=0.1 status=undetermined",
        "[LATENCY] trace=B3B4B5B6 seq=2 t=140.0ms delta=139.1ms event=engine.permission.callback granted=true"
    ])
    try require(
        grantedMicrophoneTrace?.microphonePermissionUnavailable == false,
        "a granted microphone callback must not become a permission failure"
    )
    let unavailableMicrophoneAssessment = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: nil,
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: false,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 250,
        shortcutHoldMatched: true,
        microphonePermissionUnavailable: pendingMicrophoneTrace?.microphonePermissionUnavailable,
        transcriptionCompleted: false
    )
    try require(
        unavailableMicrophoneAssessment.status == .microphonePermissionUnavailable,
        "pending microphone authorization must not be reported as transcription failure"
    )
    let unavailableMicrophoneEvidence = RuntimeCaseEvidence(
        targetPrepared: true,
        audioPlaybackStarted: true,
        shortcutDownPosted: true,
        shortcutUpPosted: true,
        emergencyShortcutReleasePosted: false,
        voiceInkTriggerObserved: true,
        voiceInkShortcutHoldMatched: true,
        voiceInkShortcutEvidenceRejected: false,
        voiceInkTranscriptionCompleted: false,
        voiceInkClipboardWriteSucceeded: false,
        voiceInkPasteEventPosted: false,
        voiceInkTextDeliveryHandoffSucceeded: false,
        systemClipboardChangeObserved: false,
        targetAccessibilityTextObserved: false,
        targetVisibleTextObserved: false,
        targetCleanupPassed: true,
        voiceInkMicrophonePermissionUnavailable: true
    )
    try require(
        RuntimeFailureBoundaryPolicy.classify(
            assessment: unavailableMicrophoneAssessment,
            evidence: unavailableMicrophoneEvidence,
            hasLatencyTrace: true
        ) == .voiceInkMicrophonePermission,
        "microphone authorization must have its own VoiceInk failure boundary"
    )
    print("PASS pending microphone authorization remains distinct from transcription failure")

    let unrenderedPaste = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "AX already contains text",
            keyUpToVisibleMilliseconds: nil,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 440
    )
    try require(
        unrenderedPaste.status == .renderNotObserved,
        "AX text without rendered pixels must remain a distinct failure"
    )
    print("PASS AX text cannot masquerade as rendered visibility")

    let defaults = RuntimeHarnessConfiguration.default
    try require(defaults.audioDirectory.hasSuffix("/Downloads/roma jt builds/audio"), "default audio directory")
    try require(defaults.audioDeviceName == "BlackHole 2ch", "default loopback device")
    try require(defaults.targets == RuntimeTargetApp.defaultMatrix, "default app matrix")
    try require(defaults.repetitions == 3, "default repetitions")
    try require(defaults.audioLeadSeconds, equals: 1.1, "default audio lead")
    try require(defaults.latencyThresholdMilliseconds, equals: 250, "default latency budget")
    try require(
        defaults.targetAvailabilityPolicy == .runningOnly,
        "local default must not launch closed target apps"
    )
    try require(defaults.minimumTargetCount == 4, "runtime coverage must require four distinct apps")
    let runningTargets = RuntimeTargetAvailabilitySelector.select(
        configuredTargets: targets,
        runningBundleIdentifiers: ["com.google.Chrome", "dev.zed.Zed"],
        policy: .runningOnly
    )
    try require(
        runningTargets.map(\.id) == ["chrome", "zed"],
        "running-only coverage should preserve configured order and skip closed apps"
    )
    let originalLoopbackState = RuntimeLoopbackDeviceControlState(
        inputMuted: true,
        outputMuted: true,
        inputVolume: 0.875,
        outputVolume: 0.875
    )
    try require(
        originalLoopbackState.preparedForPlayback
            == RuntimeLoopbackDeviceControlState(
                inputMuted: false,
                outputMuted: false,
                inputVolume: 1,
                outputVolume: 1
            ),
        "loopback playback must unmute and normalize every restorable control"
    )
    let unsupportedLoopbackControls = RuntimeLoopbackDeviceControlState(
        inputMuted: nil,
        outputMuted: false,
        inputVolume: nil,
        outputVolume: 0.5
    )
    try require(
        unsupportedLoopbackControls.preparedForPlayback
            == RuntimeLoopbackDeviceControlState(
                inputMuted: nil,
                outputMuted: false,
                inputVolume: nil,
                outputVolume: 1
            ),
        "missing CoreAudio controls must stay untouched instead of inventing state"
    )
    let legacyOutputJournal = try JSONDecoder().decode(
        RuntimeSystemOutputJournal.self,
        from: Data(#"{"originalDeviceUID":"legacy-output"}"#.utf8)
    )
    try require(
        legacyOutputJournal.targetDeviceUID == nil
            && legacyOutputJournal.targetControlState == nil,
        "output-only crash journals from older helpers must remain recoverable"
    )
    try require(
        RuntimeTargetLifecyclePlan.shouldRestoreApplication(
            wasRunningBeforePreparation: true,
            isRunningAfterCleanup: false
        ),
        "cleanup must restore an initially running app that its isolated surface closes"
    )
    try require(
        !RuntimeTargetLifecyclePlan.shouldRestoreApplication(
            wasRunningBeforePreparation: false,
            isRunningAfterCleanup: false
        ),
        "running-only cleanup must not launch an app that was closed before preparation"
    )
    print("PASS loopback controls and running-target lifecycle are deterministic and reversible")
    let restorationTargets = RuntimeTargetCatalog.restorationTargets(
        configuredTargets: [
            targets[1],
            RuntimeTargetApp(
                id: "repo-prompt",
                displayName: "Repo Prompt",
                bundleIdentifier: "com.pvncher.repoprompt",
                kind: .document
            )
        ]
    )
    try require(
        restorationTargets.map(\.bundleIdentifier).contains("com.google.Chrome"),
        "custom runs must retain default target metadata for abandoned-resource cleanup"
    )
    try require(
        restorationTargets.filter { $0.bundleIdentifier == "com.apple.Safari" }.count == 1,
        "restoration target catalog must deduplicate configured and default apps"
    )
    print("PASS zero-config run covers supplied fixtures without launching closed target apps")

    let targetTitle = "Roma Runtime E2E fixture-textedit-r1-ABC123"
    try require(
        RuntimeTargetIsolationPlan.documentFilename(
            windowTitleToken: targetTitle,
            bundleIdentifier: "com.apple.TextEdit"
        )
            == "\(targetTitle).txt",
        "document filename must preserve the window-title token used for scoped cleanup"
    )
    try require(
        RuntimeTargetIsolationPlan.documentFilename(
            windowTitleToken: targetTitle,
            bundleIdentifier: "com.apple.ScriptEditor2"
        ) == "\(targetTitle).applescript",
        "Script Editor targets must use its editable document type"
    )
    try require(
        RuntimeTargetIsolationPlan.chromeArguments(
            resourceURL: URL(fileURLWithPath: "/tmp/\(targetTitle).html")
        ) == [
            "--force-renderer-accessibility",
            "--new-window",
            "file:///tmp/\(targetTitle.replacingOccurrences(of: " ", with: "%20")).html"
        ],
        "Chrome fixtures must carry renderer accessibility and an explicit file URL"
    )
    try require(
        RuntimeTargetIsolationPlan.vscodeArguments(resourcePath: "/tmp/\(targetTitle).txt") == [
            "--force-renderer-accessibility",
            "--disable-extensions",
            "--skip-welcome",
            "--new-window",
            "/tmp/\(targetTitle).txt"
        ],
        "VS Code fixtures must launch an isolated accessible editor instance"
    )
    try require(
        RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            "\n",
            scenario: .empty,
            targetKind: .electron
        ),
        "Electron's accessible empty-line sentinel must count as an empty baseline"
    )
    try require(
        !RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            "\n",
            scenario: .empty,
            targetKind: .document
        ),
        "native document targets must retain exact empty-text matching"
    )
    try require(
        RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            RuntimeTextScenario.existingText.initialText,
            scenario: .existingText,
            targetKind: .electron
        ),
        "Electron's prefilled baseline must retain exact surrounding text"
    )
    try require(
        RuntimeTargetIsolationPlan.browserEditableLabel(windowTitleToken: targetTitle)
            .contains(targetTitle),
        "browser textarea label must carry the unique target token"
    )
    print("PASS target resources preserve identity, launch arguments, and editor baselines")

    let selectedVoiceInk = RuntimeVoiceInkCandidateSelector.select(
        explicitPath: nil,
        runningPaths: ["/Applications/VoiceInk.app"],
        buildDirectoryPath: "/Users/felix/Downloads/roma jt builds",
        buildCandidates: [
            RuntimeVoiceInkCandidate(path: "/Users/felix/Downloads/roma jt builds/older.app", modifiedAt: Date(timeIntervalSince1970: 1)),
            RuntimeVoiceInkCandidate(path: "/Users/felix/Downloads/roma jt builds/current.app", modifiedAt: Date(timeIntervalSince1970: 2))
        ],
        workspaceInstalledPath: "/Applications/VoiceInk.app"
    )
    try require(selectedVoiceInk?.path.hasSuffix("/current.app") == true, "newest build artifact should beat unrelated installed app")
    try require(selectedVoiceInk?.source == .buildDirectory, "selection source should identify the build directory")
    print("PASS exact newest build artifact is selected instead of unrelated installed VoiceInk")

    let sourceRoma = "/Volumes/Roma Distribution E2E/roma just talk.app"
    let translocatedRoma = "/private/var/folders/aa/bb/T/AppTranslocation/UUID/d/roma just talk.app"
    try require(
        RuntimeVoiceInkLaunchIdentityPolicy.accepts(
            sourceBundlePath: sourceRoma,
            runningBundlePath: translocatedRoma,
            sourceExecutableSHA256: "same-sha",
            runningExecutableSHA256: "same-sha",
            requireAppTranslocation: true
        ),
        "distribution runtime must accept the same executable through App Translocation"
    )
    try require(
        !RuntimeVoiceInkLaunchIdentityPolicy.accepts(
            sourceBundlePath: sourceRoma,
            runningBundlePath: sourceRoma,
            sourceExecutableSHA256: "same-sha",
            runningExecutableSHA256: "same-sha",
            requireAppTranslocation: true
        ),
        "distribution runtime must reject an untranslocated relaunch"
    )
    try require(
        !RuntimeVoiceInkLaunchIdentityPolicy.accepts(
            sourceBundlePath: sourceRoma,
            runningBundlePath: translocatedRoma,
            sourceExecutableSHA256: "source-sha",
            runningExecutableSHA256: "other-sha",
            requireAppTranslocation: true
        ),
        "distribution runtime must reject a translocated app with different bytes"
    )
    print("PASS distribution runtime launch identity requires translocation and matching bytes")

    let contentPass = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "Hello, ROMA runtime!",
            keyUpToVisibleMilliseconds: 200,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: "hello roma runtime",
        latencyThresholdMilliseconds: 440
    )
    try require(contentPass.status == .passed, "case and punctuation should not fail transcript QA")
    try require(contentPass.wordErrorRate == 0, "normalized identical transcript should have zero WER")

    let contentMismatch = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "completely different words",
            keyUpToVisibleMilliseconds: 200,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: "hello roma runtime",
        latencyThresholdMilliseconds: 440
    )
    try require(contentMismatch.status == .contentMismatch, "materially wrong transcript should fail content QA")
    print("PASS optional transcript answers enforce normalized word-error quality")

    let latencyBoundaryPass = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "visible",
            keyUpToVisibleMilliseconds: 250,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 250
    )
    let latencyBoundaryFail = RuntimeCaseAssessment.assess(
        observation: RuntimeCaseObservation(
            visibleText: "visible",
            keyUpToVisibleMilliseconds: 251,
            clipboardChanged: true,
            triggerObserved: true
        ),
        expectedTranscript: nil,
        latencyThresholdMilliseconds: 250
    )
    try require(latencyBoundaryPass.status == .passed, "250ms must satisfy the local latency contract")
    try require(latencyBoundaryFail.status == .slow, "251ms must fail the local latency contract")
    print("PASS local rendered-latency contract is exact at 250ms")

    let trace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=A1B2C3D4 seq=0 t=0.0ms delta=0.0ms event=shortcut.key_down_source keyCode=56",
        "[LATENCY] trace=A1B2C3D4 seq=1 t=1100.0ms delta=1100.0ms event=shortcut.key_up_handler duration=1.1",
        "[LATENCY] trace=A1B2C3D4 seq=2 t=1200.0ms delta=100.0ms event=paste_session.write_clipboard.end result=success",
        "[LATENCY] trace=A1B2C3D4 seq=3 t=1300.0ms delta=100.0ms event=paste_event_posted chars=18",
        "[LATENCY] trace=A1B2C3D4 seq=4 t=1500.0ms delta=200.0ms event=pipeline.complete",
        "[LATENCY] trace=A1B2C3D4 seq=5 t=1800.0ms delta=300.0ms event=ui.engine_toggle.end"
    ])
    try require(trace?.traceID == "A1B2C3D4", "trace ID should be parsed")
    try require(trace?.triggerObserved == true, "key-down trace event should prove trigger acceptance")
    try require(trace?.pasteEventPosted == true, "paste event should be recognized")
    try require(trace?.textDeliveryHandoffCompleted == true, "clipboard paste should require write and command proof")
    try require(trace?.clipboardPasteHandoffCompleted == true, "clipboard trace should prove paste semantics")
    try require(trace?.directTextInsertionSucceeded == false, "clipboard trace must not report direct AX insertion")
    try require(trace?.events.map(\.sequence) == [0, 1, 2, 3, 4, 5], "trace events should stay sequence ordered")
    try require(
        trace?.keyUpToPasteEventMilliseconds ?? -1,
        equals: 200,
        "trace should separate VoiceInk key-up-to-paste handoff from target visibility"
    )
    try require(
        trace?.keyUpToPipelineCompleteMilliseconds ?? -1,
        equals: 400,
        "trace should expose post-paste pipeline completion"
    )
    let accessibilityInsertTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=E5F6A7B8 seq=0 t=1000.0ms delta=0.0ms event=shortcut.key_up_handler",
        "[LATENCY] trace=E5F6A7B8 seq=1 t=1080.0ms delta=80.0ms event=paste_text_inserted method=accessibility"
    ])
    try require(
        accessibilityInsertTrace?.pasteEventPosted == true,
        "direct Accessibility insertion should count as VoiceInk text delivery"
    )
    try require(
        accessibilityInsertTrace?.textDeliveryHandoffCompleted == true,
        "direct Accessibility insertion should not require a clipboard-write event"
    )
    try require(
        accessibilityInsertTrace?.directTextInsertionSucceeded == true,
        "direct Accessibility insertion must remain distinguishable from paste semantics"
    )
    try require(
        accessibilityInsertTrace?.clipboardPasteHandoffCompleted == false,
        "direct Accessibility insertion must not masquerade as clipboard paste"
    )
    try require(
        accessibilityInsertTrace?.keyUpToPasteEventMilliseconds ?? -1,
        equals: 80,
        "direct Accessibility insertion should expose its key-up-to-delivery latency"
    )
    let incompleteClipboardTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=C9D0E1F2 seq=0 t=1000.0ms delta=0.0ms event=shortcut.key_up_handler",
        "[LATENCY] trace=C9D0E1F2 seq=1 t=1080.0ms delta=80.0ms event=paste_event_posted method=cgEvent"
    ])
    try require(
        incompleteClipboardTrace?.textDeliveryHandoffCompleted == false,
        "clipboard paste must retain separate write and command proof"
    )
    for kind in [RuntimeTargetApp.Kind.browser, .electron] {
        let incompleteWebPaste = RuntimeCaseAssessment.assess(
            observation: RuntimeCaseObservation(
                visibleText: "visible text from an unproven source",
                keyUpToVisibleMilliseconds: 100,
                clipboardChanged: true,
                triggerObserved: true
            ),
            expectedTranscript: nil,
            latencyThresholdMilliseconds: 250,
            transcriptionCompleted: true,
            transcribedCharacterCount: 36,
            pasteSemanticsSatisfied: incompleteClipboardTrace.map {
                kind.satisfiesPasteSemantics(
                    directAccessibilityInsertionSucceeded: $0.directTextInsertionSucceeded,
                    clipboardPasteHandoffCompleted: $0.clipboardPasteHandoffCompleted
                )
            }
        )
        try require(
            incompleteWebPaste.status == .pasteSemanticsNotProven && !incompleteWebPaste.passed,
            "\(kind.rawValue) visible text must fail when its parsed trace lacks clipboard-write proof"
        )
    }
    try require(
        trace?.keyUpToInteractionSettledMilliseconds ?? -1,
        equals: 700,
        "trace should expose the final interaction-settled boundary"
    )
    print("PASS latency trace separates paste, pipeline completion, and settled interaction")

    let executorTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=E1E2E3E4 seq=0 t=100.0ms delta=100.0ms event=streaming_service.drain_continuation.executor_enqueued sentChunks=12",
        "[LATENCY] trace=E1E2E3E4 seq=1 t=612.4ms delta=512.4ms event=streaming_service.drain_continuation.executor_resumed queueDelayMs=512.4"
    ])
    try require(
        executorTrace?.events.last?.executorQueueDelayMilliseconds ?? -1,
        equals: 512.4,
        "executor resume events should expose their queue delay"
    )
    try require(
        executorTrace?.maximumExecutorQueueDelayMilliseconds ?? -1,
        equals: 512.4,
        "trace should expose its worst executor queue delay"
    )
    print("PASS latency trace preserves executor enqueue-to-resume timing")

    let shortcutTimingTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=A1A2A3A4 seq=0 t=0.0ms delta=0.0ms event=shortcut.key_down_physical mode=special",
        "[LATENCY] trace=A1A2A3A4 seq=1 t=166.2ms delta=166.2ms event=shortcut.key_up_handler state=recording"
    ])
    try require(
        shortcutTimingTrace?.observedShortcutHoldMilliseconds ?? -1,
        equals: 166.2,
        "trace should expose the shortcut hold VoiceInk actually observed"
    )
    let rejectedShortcutTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=A5A6A7A8 seq=0 t=0.0ms delta=0.0ms event=shortcut.key_down_physical mode=special",
        "[LATENCY] trace=A5A6A7A8 seq=1 t=166.2ms delta=166.2ms event=shortcut.key_up_handler pressedOtherKey=true releasedOtherKey=false reliable=true",
        "[LATENCY] trace=A5A6A7A8 seq=2 t=166.2ms delta=0.0ms event=shortcut.key_evidence_rejected pressedOtherKey=true releasedOtherKey=false reliable=true"
    ])
    try require(
        rejectedShortcutTrace?.shortcutKeyEvidenceRejected == true,
        "trace should distinguish rejected key evidence from transcription failure"
    )
    let rejectedEvidence = RuntimeCaseEvidence(
        targetPrepared: true,
        audioPlaybackStarted: true,
        shortcutDownPosted: true,
        shortcutUpPosted: true,
        emergencyShortcutReleasePosted: false,
        voiceInkTriggerObserved: true,
        voiceInkShortcutHoldMatched: false,
        voiceInkShortcutEvidenceRejected: rejectedShortcutTrace?.shortcutKeyEvidenceRejected == true,
        voiceInkTranscriptionCompleted: false,
        voiceInkClipboardWriteSucceeded: false,
        voiceInkPasteEventPosted: false,
        voiceInkTextDeliveryHandoffSucceeded: false,
        systemClipboardChangeObserved: false,
        targetAccessibilityTextObserved: false,
        targetVisibleTextObserved: false,
        targetCleanupPassed: true
    )
    try require(
        RuntimeFailureBoundaryPolicy.classify(
            assessment: RuntimeCaseAssessment(status: .transcriptionIncomplete, passed: false),
            evidence: rejectedEvidence,
            hasLatencyTrace: true
        ) == .voiceInkShortcutEvidence,
        "explicit key-evidence rejection should outrank inferred hold or transcription failures"
    )
    print("PASS latency trace exposes the VoiceInk-observed shortcut hold")

    let emptyTranscriptTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=F1F2F3F4 seq=0 t=100.0ms delta=100.0ms event=pipeline.transcribe.end durationMs=52.0 result=success rawChars=0"
    ])
    try require(
        emptyTranscriptTrace?.transcribedCharacterCount == 0,
        "trace parsing must preserve a zero-character transcription result"
    )
    let failedTranscriptTrace = RuntimeLatencyTrace.parse(messages: [
        "[LATENCY] trace=F5F6F7F8 seq=0 t=100.0ms delta=100.0ms event=pipeline.transcribe.end durationMs=52.0 result=failure rawChars=0"
    ])
    try require(
        failedTranscriptTrace?.transcribedCharacterCount == nil,
        "failed transcription attempts must not masquerade as successful empty transcripts"
    )
    print("PASS latency trace exposes the transcription character count")

    let stablePixels = [UInt8](repeating: 128, count: 400 * 4)
    var caretOnlyPixels = stablePixels
    for pixel in 0..<40 {
        caretOnlyPixels[pixel * 4] = 0
    }
    let caretOnlyDifference = RuntimeRenderedTextChangePolicy.compareRGBA(
        baseline: stablePixels,
        current: caretOnlyPixels
    )
    try require(caretOnlyDifference?.passed == false, "caret-sized changes must not count as rendered text")

    var renderedTextPixels = stablePixels
    for pixel in 0..<120 {
        renderedTextPixels[pixel * 4] = 0
    }
    let renderedTextDifference = RuntimeRenderedTextChangePolicy.compareRGBA(
        baseline: stablePixels,
        current: renderedTextPixels
    )
    try require(renderedTextDifference?.passed == true, "text-sized pixel changes must count as rendered text")
    try require(
        RuntimeRenderedTextChangePolicy.requiredChangedPixels(for: 402_560) == 80,
        "large editable regions must not raise the rendered-text threshold"
    )

    var transientTextPixels = renderedTextPixels
    for pixel in 120..<180 {
        transientTextPixels[pixel * 4] = 0
    }
    var stabilityTracker = RuntimeRenderedTextStabilityTracker(baseline: stablePixels)
    try require(
        stabilityTracker.observe(current: renderedTextPixels)?.stable == false,
        "the first changed frame cannot establish stability"
    )
    try require(
        stabilityTracker.observe(current: transientTextPixels)?.stable == false,
        "two materially different changed frames must not establish stability"
    )
    try require(
        stabilityTracker.observe(current: transientTextPixels)?.stable == true,
        "two mutually stable changed frames must establish rendered text"
    )

    var renderedLatencyTracker = RuntimeRenderedTextLatencyTracker(baseline: stablePixels)
    try require(
        renderedLatencyTracker.observe(
            current: renderedTextPixels,
            atSystemUptime: 1
        )?.firstPersistentChangeAtSystemUptime == nil,
        "the first changed frame must remain provisional"
    )
    try require(
        renderedLatencyTracker.observe(
            current: transientTextPixels,
            atSystemUptime: 2
        )?.firstPersistentChangeAtSystemUptime == nil,
        "a materially different frame must replace the provisional render timestamp"
    )
    try require(
        renderedLatencyTracker.observe(
            current: transientTextPixels,
            atSystemUptime: 3
        )?.firstPersistentChangeAtSystemUptime == 2,
        "stable render proof must report the first persistent frame, not the verification frame"
    )

    try require(
        RuntimeTextVisibilityAttribution.renderedLatency(
            accessibilityText: nil,
            renderedLatency: 180
        ) == nil,
        "pixel changes alone must not be attributed to inserted text"
    )
    try require(
        RuntimeTextVisibilityAttribution.renderedLatency(
            accessibilityText: "AX arrived later",
            renderedLatency: 180
        ) ?? -1,
        equals: 180,
        "AX arriving later must preserve the independently sampled render time"
    )
    print("PASS rendered-text policy rejects noise, requires stability, and remains AX-independent")

    // D048AC: two stable nontext frames at22/61ms must not become later AX text proof.
    var nontextPixels = stablePixels
    for pixel in 0..<100 { nontextPixels[pixel * 4] = 0 }
    var insertedPixels = nontextPixels
    for pixel in 150..<270 { insertedPixels[pixel * 4] = 0 }
    var association = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    try require(association.observe(current: nontextPixels, atSystemUptime: 0.022,
                                    accessibilityText: "", precedingAccessibilityText: "") == nil, "empty AX cannot accept early pixels")
    try require(association.observe(current: nontextPixels, atSystemUptime: 0.061,
                                    accessibilityText: "", precedingAccessibilityText: "") == nil, "stable nontext pixels remain baseline")
    try require(association.observe(current: nontextPixels, atSystemUptime: 0.182,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == nil,
                "first AX text with only the old pixels cannot prove rendering")
    try require(association.observe(current: nontextPixels, atSystemUptime: 0.200,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == nil,
                "resetting to the original baseline must not resurrect old pixels")
    _ = association.observe(current: insertedPixels, atSystemUptime: 0.220, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(association.observe(current: insertedPixels, atSystemUptime: 0.250,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == 0.220,
                "delayed paint reports the first genuine frame, not confirmation")

    var caretAfterInsertion = insertedPixels
    for pixel in 300..<310 { caretAfterInsertion[pixel * 4] = 0 }
    try require(association.observe(current: caretAfterInsertion, atSystemUptime: 0.280,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == 0.220,
                "later caret changes must not move already proved unchanged-text timing")
    try require(association.observe(current: nontextPixels, atSystemUptime: 0.310,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == nil,
                "disappeared glyphs must invalidate proof even if AX is stale")
    _ = association.observe(current: insertedPixels, atSystemUptime: 0.340, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(association.observe(current: insertedPixels, atSystemUptime: 0.370,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == 0.340,
                "reappearing glyphs need new persistent proof")

    var rerenderedPixels = insertedPixels
    for pixel in 280..<380 { rerenderedPixels[pixel * 4] = 0 }
    try require(association.observe(current: rerenderedPixels, atSystemUptime: 0.400,
                                    accessibilityText: "inserted", precedingAccessibilityText: "inserted")?
                    .firstPersistentChangeAtSystemUptime == nil,
                "material re-render with stale AX requires fresh persistent pixels")

    var paintFirst = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    _ = paintFirst.observe(current: nontextPixels, atSystemUptime: 0.061, accessibilityText: "", precedingAccessibilityText: "")
    _ = paintFirst.observe(current: insertedPixels, atSystemUptime: 0.180, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(paintFirst.observe(current: insertedPixels, atSystemUptime: 0.210,
                                  accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == 0.180,
                "paint after confirmed AX and before following AX read keeps its capture timestamp")
    // Changed AX text needs new pixels, even after the old text already had valid proof.
    _ = paintFirst.observe(current: insertedPixels, atSystemUptime: 0.240, accessibilityText: "replacement", precedingAccessibilityText: "replacement")
    try require(paintFirst.observe(current: insertedPixels, atSystemUptime: 0.270,
                                  accessibilityText: "replacement", precedingAccessibilityText: "replacement")?.firstPersistentChangeAtSystemUptime == nil,
                "replacement text cannot reuse old glyphs")
    var replacementPixels = insertedPixels
    for pixel in 270..<390 { replacementPixels[pixel * 4] = 0 }
    _ = paintFirst.observe(current: replacementPixels, atSystemUptime: 0.300, accessibilityText: "replacement", precedingAccessibilityText: "replacement")
    try require(paintFirst.observe(current: replacementPixels, atSystemUptime: 0.330,
                                  accessibilityText: "replacement", precedingAccessibilityText: "replacement")?.firstPersistentChangeAtSystemUptime == 0.300,
                "replacement accepts its own persistent glyph change")

    var unknown = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    _ = unknown.observe(current: nontextPixels, atSystemUptime: 0.020, accessibilityText: nil, precedingAccessibilityText: nil)
    _ = unknown.observe(current: insertedPixels, atSystemUptime: 0.050, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(unknown.observe(current: insertedPixels, atSystemUptime: 0.080,
                                accessibilityText: "inserted", precedingAccessibilityText: "inserted") == nil && unknown.associationError != nil,
                "unknown AX cannot establish which pixels preceded insertion")
    _ = unknown.observe(current: nontextPixels, atSystemUptime: 0.110, accessibilityText: "", precedingAccessibilityText: "")
    _ = unknown.observe(current: insertedPixels, atSystemUptime: 0.140, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(unknown.observe(current: insertedPixels, atSystemUptime: 0.170,
                                accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == 0.140
                && unknown.associationError == nil,
                "a confirmed empty frame recovers association after AX rediscovery")
    var malformed = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    let wrongSurfaceText = RuntimeTextScenario.existingText.insertedText(from: "unrelated text")
    try require(wrongSurfaceText == nil, "missing existing-text markers are unknown, not empty")
    _ = malformed.observe(current: nontextPixels, atSystemUptime: 0.020, accessibilityText: wrongSurfaceText, precedingAccessibilityText: wrongSurfaceText)
    _ = malformed.observe(current: insertedPixels, atSystemUptime: 0.050, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(malformed.observe(current: insertedPixels, atSystemUptime: 0.080,
                                  accessibilityText: "inserted", precedingAccessibilityText: "inserted") == nil,
                "malformed scenario text must not establish a confirmed empty baseline")
    var laggedAX = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    _ = laggedAX.observe(current: insertedPixels, atSystemUptime: 0.180, accessibilityText: "", precedingAccessibilityText: "")
    _ = laggedAX.observe(current: insertedPixels, atSystemUptime: 0.210, accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(laggedAX.observe(current: insertedPixels, atSystemUptime: 0.240,
                                 accessibilityText: "inserted", precedingAccessibilityText: "inserted")?.firstPersistentChangeAtSystemUptime == nil,
                "paint paired with empty AX cannot be backdated after AX catches up")
    var spanningRead = RuntimeRenderedTextAssociationTracker(baseline: stablePixels)
    _ = spanningRead.observe(current: nontextPixels, atSystemUptime: 0.022,
                             accessibilityText: "", precedingAccessibilityText: "")
    _ = spanningRead.observe(current: nontextPixels, atSystemUptime: 0.061,
                             accessibilityText: "", precedingAccessibilityText: "")
    try require(spanningRead.observe(current: insertedPixels, atSystemUptime: 0.150,
                                     accessibilityText: "inserted", precedingAccessibilityText: "") == nil,
                "a capture spanning an AX transition must not claim an ambiguous timestamp")
    _ = spanningRead.observe(current: insertedPixels, atSystemUptime: 0.180,
                             accessibilityText: "inserted", precedingAccessibilityText: "inserted")
    try require(spanningRead.observe(current: insertedPixels, atSystemUptime: 0.210,
                                     accessibilityText: "inserted", precedingAccessibilityText: "inserted")?
                    .firstPersistentChangeAtSystemUptime == 0.180,
                "matching AX bracket establishes a later genuine captured timestamp, not an AX timestamp")
    print("PASS rendered association rejects pre-text/unknown/replaced pixels and preserves matched paint time")

    let latencies = [100.0, 200.0, 300.0, 400.0, 500.0]
    try require(RuntimeStatistics.percentile(50, values: latencies) ?? -1, equals: 300, "p50 latency")
    try require(RuntimeStatistics.percentile(95, values: latencies) ?? -1, equals: 500, "p95 latency")
    print("PASS report statistics expose median and p95 visible-text latency")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
