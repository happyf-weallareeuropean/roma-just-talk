import AppKit
import Foundation
import RuntimeE2ECore

struct RuntimeCaseReport: Codable {
    let id: String
    let fixturePath: String
    let expectedTranscript: String?
    let target: RuntimeTargetApp
    let textScenario: RuntimeTextScenario
    let repetition: Int
    let startedAt: Date
    let finishedAt: Date
    let timingPlan: RuntimeTimingPlan?
    let targetPreparation: RuntimeTargetPreparationInfo?
    let audioPlayback: RuntimeAudioPlaybackResult?
    let shortcutDown: RuntimeShortcutEventResult?
    let shortcutUp: RuntimeShortcutEventResult?
    let actualAudioLeadMilliseconds: Double?
    let actualHoldMilliseconds: Double?
    let voiceInkObservedHoldMilliseconds: Double?
    let shortcutHoldDeltaMilliseconds: Double?
    let voiceInkKeyUpToPasteEventMilliseconds: Double?
    let voiceInkKeyUpToPipelineCompleteMilliseconds: Double?
    let voiceInkKeyUpToInteractionSettledMilliseconds: Double?
    let pasteEventToVisibleMilliseconds: Double?
    let visibleText: RuntimeVisibleTextResult?
    let clipboardChanged: Bool
    let latencyTrace: RuntimeLatencyTrace?
    let evidence: RuntimeCaseEvidence
    let failureBoundary: RuntimeFailureBoundary
    let targetCleanup: RuntimeTargetCleanupInfo?
    let assessment: RuntimeCaseAssessment
    let error: String?
}

struct RuntimeAppSummary: Codable {
    let targetID: String
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let noPasteCases: Int
    let p50AccessibilityTextMilliseconds: Double?
    let p95AccessibilityTextMilliseconds: Double?
    let p50VisibleMilliseconds: Double?
    let p95VisibleMilliseconds: Double?
    let maxVisibleMilliseconds: Double?
}

struct RuntimeRunSummary: Codable {
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let noPasteCases: Int
    let p50AccessibilityTextMilliseconds: Double?
    let p95AccessibilityTextMilliseconds: Double?
    let p50VisibleMilliseconds: Double?
    let p95VisibleMilliseconds: Double?
    let maxVisibleMilliseconds: Double?
    let p50PipelineCompleteMilliseconds: Double?
    let p95PipelineCompleteMilliseconds: Double?
    let p50InteractionSettledMilliseconds: Double?
    let p95InteractionSettledMilliseconds: Double?
    let apps: [RuntimeAppSummary]
    let passed: Bool
}

struct RuntimeHarnessReport: Codable {
    var schemaVersion = 8
    let startedAt: Date
    var finishedAt: Date?
    let configuration: RuntimeHarnessConfiguration
    let preflight: RuntimePreflightReport
    var abandonedTargetCleanup: RuntimeAbandonedTargetCleanupInfo?
    var voiceInkSession: RuntimeVoiceInkSessionInfo?
    var cases: [RuntimeCaseReport]
    var summary: RuntimeRunSummary
    var restoredOriginalState: Bool
    var fatalError: String?
}

enum RuntimeHarnessRunner {
    private static let shortcutHoldToleranceMilliseconds: Double = 150

    static func run(
        configuration: RuntimeHarnessConfiguration,
        reportURL: URL
    ) throws -> RuntimeHarnessReport {
        let preflight = RuntimePreflight.run(configuration: configuration)
        guard preflight.passed else {
            var report = RuntimeHarnessReport(
                startedAt: Date(),
                finishedAt: Date(),
                configuration: configuration,
                preflight: preflight,
                abandonedTargetCleanup: nil,
                voiceInkSession: nil,
                cases: [],
                summary: summarize(cases: []),
                restoredOriginalState: true,
                fatalError: preflight.failures.joined(separator: "; ")
            )
            try write(report: report, to: reportURL)
            report.summary = summarize(cases: report.cases)
            return report
        }

        guard let audioDevice = preflight.requestedAudioDevice else {
            throw RuntimeAudioPlaybackError.audioDeviceNotFound
        }
        let fixtureURLs = preflight.audioFixtures.map { URL(fileURLWithPath: $0.path) }
        let selectedTargetIDs = Set(preflight.selectedTargetIDs)
        let selectedTargets = configuration.targets.filter { selectedTargetIDs.contains($0.id) }
        let runPlan = try RuntimeRunPlan.make(
            fixtureURLs: fixtureURLs,
            expectedTranscripts: configuration.expectedTranscripts,
            targets: selectedTargets,
            repetitions: configuration.repetitions
        )
        let fixtureDurations = Dictionary(
            uniqueKeysWithValues: preflight.audioFixtures.compactMap { fixture in
                fixture.durationSeconds.map { (fixture.path, $0) }
            }
        )

        var report = RuntimeHarnessReport(
            startedAt: Date(),
            finishedAt: nil,
            configuration: configuration,
            preflight: preflight,
            abandonedTargetCleanup: nil,
            voiceInkSession: nil,
            cases: [],
            summary: summarize(cases: []),
            restoredOriginalState: false,
            fatalError: nil
        )
        try write(report: report, to: reportURL)

        let abandonedTargetCleanup = RuntimeTargetController.restoreAbandonedTargets(
            targets: RuntimeTargetCatalog.restorationTargets(
                configuredTargets: configuration.targets
            )
        )
        report.abandonedTargetCleanup = abandonedTargetCleanup
        if !abandonedTargetCleanup.passed {
            report.finishedAt = Date()
            report.restoredOriginalState = true
            report.fatalError = "Could not restore abandoned runtime target surfaces"
            try write(report: report, to: reportURL)
            return report
        }
        try write(report: report, to: reportURL)

        let outputSession = try RuntimeSystemOutputSession.start(targetDevice: audioDevice)
        var voiceInkSession: RuntimeVoiceInkSession?
        do {
            let session = try RuntimeVoiceInkSession.start(
                configuration: configuration,
                audioDeviceUID: audioDevice.uid
            )
            voiceInkSession = session
            report.voiceInkSession = session.info
            Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)

            var seenTraceIDs = Set((try? RuntimeLatencyLogReader.recent().traces.map(\.traceID)) ?? [])
            var previousFixturePath: String?
            for (caseIndex, runCase) in runPlan.cases.enumerated() {
                if shouldRelaunchVoiceInk(
                    lifecycle: configuration.voiceInkLifecycle,
                    previousFixturePath: previousFixturePath,
                    currentFixturePath: runCase.fixtureURL.path,
                    caseIndex: caseIndex
                ) {
                    try session.relaunchForRun(bundleIdentifier: configuration.voiceInkBundleIdentifier)
                    Thread.sleep(forTimeInterval: configuration.preRollWarmupSeconds)
                }
                previousFixturePath = runCase.fixtureURL.path

                let caseReport = try executeCase(
                    runCase,
                    configuration: configuration,
                    audioDevice: audioDevice,
                    fixtureDurationSeconds: fixtureDurations[runCase.fixtureURL.path],
                    seenTraceIDs: &seenTraceIDs
                )
                report.cases.append(caseReport)
                report.summary = summarize(cases: report.cases)
                try write(report: report, to: reportURL)
                printCaseProgress(caseReport, index: caseIndex + 1, total: runPlan.cases.count)
            }

            try session.restore()
            try outputSession.restore()
            report.restoredOriginalState = true
            report.finishedAt = Date()
            report.summary = summarize(cases: report.cases)
            try write(report: report, to: reportURL)
            return report
        } catch {
            try? voiceInkSession?.restore()
            try? outputSession.restore()
            report.restoredOriginalState = true
            report.finishedAt = Date()
            report.fatalError = String(describing: error)
            report.summary = summarize(cases: report.cases)
            try? write(report: report, to: reportURL)
            throw error
        }
    }

    private static func executeCase(
        _ runCase: RuntimeRunCase,
        configuration: RuntimeHarnessConfiguration,
        audioDevice: RuntimeAudioDevice,
        fixtureDurationSeconds: TimeInterval?,
        seenTraceIDs: inout Set<String>
    ) throws -> RuntimeCaseReport {
        let startedAt = Date()
        let runID = makeRunID(runCase)
        var phase = "target"
        var preparedTarget: RuntimePreparedTarget?
        var playback: RuntimeAudioPlayback?
        var timingPlan: RuntimeTimingPlan?
        var audioResult: RuntimeAudioPlaybackResult?
        var shortcutDown: RuntimeShortcutEventResult?
        var shortcutUp: RuntimeShortcutEventResult?
        var visibleText: RuntimeVisibleTextResult?
        var latencyTrace: RuntimeLatencyTrace?
        var clipboardChanged = false
        var audioPlaybackStarted = false
        var emergencyShortcutReleasePosted = false
        var voiceInkObservedHoldMilliseconds: Double?
        var shortcutHoldDeltaMilliseconds: Double?
        var voiceInkShortcutHoldMatched: Bool?
        var assessment = RuntimeCaseAssessment(status: .targetSetupFailed, passed: false)
        var errorText: String?

        do {
            guard let fixtureDurationSeconds else {
                throw RuntimeHarnessRunError.fixtureDurationMissing(runCase.fixtureURL.path)
            }
            let plan = try timingPlanForCase(
                fixtureDurationSeconds: fixtureDurationSeconds,
                configuration: configuration
            )
            timingPlan = plan
            let target = try RuntimeTargetController.prepare(
                target: runCase.target,
                textScenario: runCase.textScenario,
                runID: runID,
                settleSeconds: configuration.targetSettleSeconds,
                availabilityPolicy: configuration.targetAvailabilityPolicy
            )
            preparedTarget = target

            phase = "audio"
            let audio = RuntimeAudioPlayback(
                fixtureURL: runCase.fixtureURL,
                device: audioDevice,
                expectedDurationSeconds: fixtureDurationSeconds
            )
            playback = audio
            let clipboardChangeCount = NSPasteboard.general.changeCount
            let audioStartedAt = try audio.start()
            audioPlaybackStarted = true

            phase = "shortcut"
            waitUntilSystemUptime(audioStartedAt + plan.keyDownOffsetSeconds)
            let down = try RuntimeShortcutInjector.postLeftShiftDown()
            shortcutDown = down
            let renderedBaselineDelay = min(0.5, plan.holdDurationSeconds / 2)
            waitUntilSystemUptime(down.postedAtSystemUptime + renderedBaselineDelay)
            if let baselineError = target.refreshRenderedBaseline() {
                errorText = baselineError
            }
            if RuntimePlaybackReleasePolicy.waitsForPlaybackCompletion(
                explicitHoldSeconds: configuration.explicitHoldSeconds
            ) {
                phase = "audio"
                let completedPlayback = try audio.waitUntilFinished()
                audioResult = completedPlayback
                waitUntilSystemUptime(
                    plan.keyUpSystemUptime(
                        audioStartedAtSystemUptime: audioStartedAt,
                        audioFinishedAtSystemUptime: completedPlayback.finishedAtSystemUptime
                    )
                )
            } else {
                waitUntilSystemUptime(audioStartedAt + plan.keyUpOffsetSeconds)
            }
            phase = "shortcut"
            let up = try RuntimeShortcutInjector.postLeftShiftUp()
            shortcutUp = up

            phase = "observation"
            visibleText = target.waitForVisibleText(
                keyUpAtSystemUptime: up.postedAtSystemUptime,
                timeoutSeconds: configuration.targetTextTimeoutSeconds
            )
            if audioResult == nil {
                audioResult = try audio.waitUntilFinished()
            }
            clipboardChanged = NSPasteboard.general.changeCount != clipboardChangeCount

            latencyTrace = try waitForCompletedTrace(
                excluding: &seenTraceIDs,
                timeoutSeconds: 3
            )

            let postedHoldMilliseconds = (up.postedAtSystemUptime - down.postedAtSystemUptime) * 1_000
            voiceInkObservedHoldMilliseconds = latencyTrace?.observedShortcutHoldMilliseconds
            shortcutHoldDeltaMilliseconds = voiceInkObservedHoldMilliseconds.map {
                $0 - postedHoldMilliseconds
            }
            voiceInkShortcutHoldMatched = shortcutHoldDeltaMilliseconds.map {
                abs($0) <= shortcutHoldToleranceMilliseconds
            }
            if voiceInkShortcutHoldMatched == false,
               let voiceInkObservedHoldMilliseconds,
               let shortcutHoldDeltaMilliseconds {
                let timingError = String(
                    format: "Posted shortcut hold %.1fms; VoiceInk observed %.1fms (delta %.1fms)",
                    postedHoldMilliseconds,
                    voiceInkObservedHoldMilliseconds,
                    shortcutHoldDeltaMilliseconds
                )
                errorText = [errorText, timingError]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
            }

            let observation = RuntimeCaseObservation(
                visibleText: visibleText?.text,
                keyUpToVisibleMilliseconds: visibleText?.keyUpToVisibleMilliseconds,
                clipboardChanged: clipboardChanged,
                triggerObserved: latencyTrace?.triggerObserved == true
            )
            assessment = RuntimeCaseAssessment.assess(
                observation: observation,
                expectedTranscript: runCase.expectedTranscript,
                latencyThresholdMilliseconds: configuration.latencyThresholdMilliseconds,
                shortcutHoldMatched: voiceInkShortcutHoldMatched,
                microphonePermissionUnavailable: latencyTrace.map(\.microphonePermissionUnavailable),
                transcriptionCompleted: latencyTrace.map(\.transcriptionCompleted),
                transcribedCharacterCount: latencyTrace?.transcribedCharacterCount,
                pasteSemanticsSatisfied: latencyTrace.map {
                    runCase.target.kind.satisfiesPasteSemantics(
                        directAccessibilityInsertionSucceeded: $0.directTextInsertionSucceeded,
                        clipboardPasteHandoffCompleted: $0.clipboardPasteHandoffCompleted
                    )
                },
                pasteOperationCountSatisfied: runCase.target.kind == .browser
                    ? visibleText?.domPasteProof?.provesExactlyOnePaste == true
                    : nil,
                maximumWordErrorRate: configuration.maximumWordErrorRate
            )
            if assessment.status == .pasteSemanticsNotProven {
                let semanticsError = if latencyTrace?.directTextInsertionSucceeded == true {
                    "Web-backed target received direct Accessibility insertion instead of paste semantics"
                } else {
                    "Web-backed target did not prove clipboard write plus paste command"
                }
                errorText = [errorText, semanticsError]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
            }
            if assessment.status == .pasteOperationCountMismatch {
                let proof = visibleText?.domPasteProof
                let proofError = "Browser DOM observed pasteEvents=\(proof?.pasteEventCount ?? -1) pasteInputs=\(proof?.pasteInputCount ?? -1); expected exactly one of each"
                errorText = [errorText, proofError]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
            }
            if latencyTrace == nil,
               visibleText?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                assessment = RuntimeCaseAssessment(status: .traceMissing, passed: false)
            }
            if let visibleError = visibleText?.error {
                errorText = [errorText, visibleError]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")
            }
        } catch {
            errorText = String(describing: error)
            assessment = RuntimeCaseAssessment(
                status: failureStatus(for: phase),
                passed: false
            )
        }

        if shortcutDown != nil, shortcutUp == nil,
           let emergencyUp = try? RuntimeShortcutInjector.postLeftShiftUp() {
            shortcutUp = emergencyUp
            emergencyShortcutReleasePosted = true
        }
        var playbackCleanupError: Error?
        do {
            try playback?.stop()
        } catch {
            playbackCleanupError = error
        }
        let targetCleanup = preparedTarget?.cleanup()
        if let targetCleanup, !targetCleanup.passed {
            let cleanupError = targetCleanup.errors.joined(separator: "; ")
            errorText = [errorText, cleanupError]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            if assessment.passed {
                assessment = RuntimeCaseAssessment(status: .targetCleanupFailed, passed: false)
            }
        }
        if let playbackCleanupError {
            throw playbackCleanupError
        }

        let targetAccessibilityTextObserved = visibleText?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let targetVisibleTextObserved = visibleText?.keyUpToVisibleMilliseconds != nil
        let evidence = RuntimeCaseEvidence(
            targetPrepared: preparedTarget != nil,
            audioPlaybackStarted: audioPlaybackStarted,
            shortcutDownPosted: shortcutDown != nil,
            shortcutUpPosted: shortcutUp != nil,
            emergencyShortcutReleasePosted: emergencyShortcutReleasePosted,
            voiceInkTriggerObserved: latencyTrace?.triggerObserved == true,
            voiceInkShortcutHoldMatched: voiceInkShortcutHoldMatched,
            voiceInkShortcutEvidenceRejected: latencyTrace?.shortcutKeyEvidenceRejected == true,
            voiceInkTranscriptionCompleted: latencyTrace?.transcriptionCompleted == true,
            voiceInkClipboardWriteSucceeded: latencyTrace?.clipboardWriteSucceeded == true,
            voiceInkPasteEventPosted: latencyTrace?.pasteEventPosted == true,
            voiceInkTextDeliveryHandoffSucceeded: latencyTrace?.textDeliveryHandoffCompleted == true,
            systemClipboardChangeObserved: clipboardChanged,
            targetAccessibilityTextObserved: targetAccessibilityTextObserved,
            targetVisibleTextObserved: targetVisibleTextObserved,
            targetCleanupPassed: targetCleanup?.passed,
            voiceInkMicrophonePermissionUnavailable: latencyTrace.map(\.microphonePermissionUnavailable)
        )
        let failureBoundary = RuntimeFailureBoundaryPolicy.classify(
            assessment: assessment,
            evidence: evidence,
            hasLatencyTrace: latencyTrace != nil
        )
        let voiceInkKeyUpToPasteEventMilliseconds = latencyTrace?.keyUpToPasteEventMilliseconds
        let voiceInkKeyUpToPipelineCompleteMilliseconds = latencyTrace?.keyUpToPipelineCompleteMilliseconds
        let voiceInkKeyUpToInteractionSettledMilliseconds = latencyTrace?.keyUpToInteractionSettledMilliseconds
        let pasteEventToVisibleMilliseconds = visibleText?.keyUpToVisibleMilliseconds.flatMap { visible in
            // Keep signed evidence: direct AX can precede completion, and an early pixel
            // false positive must not masquerade as an instantaneous paste.
            voiceInkKeyUpToPasteEventMilliseconds.map { visible - $0 }
        }
        return RuntimeCaseReport(
            id: runID,
            fixturePath: runCase.fixtureURL.path,
            expectedTranscript: runCase.expectedTranscript,
            target: runCase.target,
            textScenario: runCase.textScenario,
            repetition: runCase.repetition,
            startedAt: startedAt,
            finishedAt: Date(),
            timingPlan: timingPlan,
            targetPreparation: preparedTarget?.info,
            audioPlayback: audioResult,
            shortcutDown: shortcutDown,
            shortcutUp: shortcutUp,
            actualAudioLeadMilliseconds: shortcutDown.map { down in
                audioResult.map { (down.postedAtSystemUptime - $0.startedAtSystemUptime) * 1_000 }
            } ?? nil,
            actualHoldMilliseconds: shortcutDown.flatMap { down in
                shortcutUp.map { ($0.postedAtSystemUptime - down.postedAtSystemUptime) * 1_000 }
            },
            voiceInkObservedHoldMilliseconds: voiceInkObservedHoldMilliseconds,
            shortcutHoldDeltaMilliseconds: shortcutHoldDeltaMilliseconds,
            voiceInkKeyUpToPasteEventMilliseconds: voiceInkKeyUpToPasteEventMilliseconds,
            voiceInkKeyUpToPipelineCompleteMilliseconds: voiceInkKeyUpToPipelineCompleteMilliseconds,
            voiceInkKeyUpToInteractionSettledMilliseconds: voiceInkKeyUpToInteractionSettledMilliseconds,
            pasteEventToVisibleMilliseconds: pasteEventToVisibleMilliseconds,
            visibleText: visibleText,
            clipboardChanged: clipboardChanged,
            latencyTrace: latencyTrace,
            evidence: evidence,
            failureBoundary: failureBoundary,
            targetCleanup: targetCleanup,
            assessment: assessment,
            error: errorText
        )
    }

    private static func timingPlanForCase(
        fixtureDurationSeconds: TimeInterval,
        configuration: RuntimeHarnessConfiguration
    ) throws -> RuntimeTimingPlan {
        if let holdSeconds = configuration.explicitHoldSeconds {
            return try RuntimeTimingPlan(
                audioDurationSeconds: configuration.audioLeadSeconds + holdSeconds,
                audioLeadSeconds: configuration.audioLeadSeconds,
                releaseTailSeconds: 0
            )
        }
        return try RuntimeTimingPlan(
            audioDurationSeconds: fixtureDurationSeconds,
            audioLeadSeconds: configuration.audioLeadSeconds,
            releaseTailSeconds: configuration.releaseTailSeconds
        )
    }

    private static func shouldRelaunchVoiceInk(
        lifecycle: RuntimeHarnessConfiguration.VoiceInkLifecycle,
        previousFixturePath: String?,
        currentFixturePath: String,
        caseIndex: Int
    ) -> Bool {
        switch lifecycle {
        case .reuse:
            return false
        case .relaunchPerFixture:
            return caseIndex > 0 && previousFixturePath != currentFixturePath
        case .relaunchPerCase:
            return caseIndex > 0
        }
    }

    private static func failureStatus(for phase: String) -> RuntimeCaseAssessment.Status {
        switch phase {
        case "target": return .targetSetupFailed
        case "audio": return .audioFailed
        case "shortcut": return .shortcutFailed
        default: return .traceMissing
        }
    }

    private static func makeRunID(_ runCase: RuntimeRunCase) -> String {
        let fixture = runCase.fixtureURL.deletingPathExtension().lastPathComponent
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(fixture).replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        return "\(collapsed)-\(runCase.target.id)-\(runCase.textScenario.rawValue)-r\(runCase.repetition)-\(UUID().uuidString.prefix(6))"
    }

    private static func waitUntilSystemUptime(_ target: TimeInterval) {
        while true {
            let remaining = target - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(remaining, 0.005))
        }
    }

    private static func waitForCompletedTrace(
        excluding seenTraceIDs: inout Set<String>,
        timeoutSeconds: TimeInterval
    ) throws -> RuntimeLatencyTrace? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var candidate: RuntimeLatencyTrace?
        var observedTraceIDs = seenTraceIDs
        repeat {
            let snapshot = try RuntimeLatencyLogReader.recent()
            observedTraceIDs.formUnion(snapshot.traces.map(\.traceID))
            let newTraces = snapshot.traces.filter { !seenTraceIDs.contains($0.traceID) }
            if let triggered = newTraces.last(where: \.triggerObserved) {
                candidate = triggered
                if triggered.keyUpToInteractionSettledMilliseconds != nil {
                    seenTraceIDs = observedTraceIDs
                    return triggered
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.25))
        } while Date() < deadline
        seenTraceIDs = observedTraceIDs
        return candidate
    }

    private static func summarize(cases: [RuntimeCaseReport]) -> RuntimeRunSummary {
        let latencies = cases.compactMap(\.visibleText?.keyUpToVisibleMilliseconds)
        let accessibilityLatencies = cases.compactMap(\.visibleText?.keyUpToAccessibilityTextMilliseconds)
        let pipelineCompleteLatencies = cases.compactMap(\.voiceInkKeyUpToPipelineCompleteMilliseconds)
        let interactionSettledLatencies = cases.compactMap(\.voiceInkKeyUpToInteractionSettledMilliseconds)
        let appSummaries = Dictionary(grouping: cases, by: { $0.target.id })
            .map { targetID, appCases -> RuntimeAppSummary in
                let appLatencies = appCases.compactMap(\.visibleText?.keyUpToVisibleMilliseconds)
                let appAccessibilityLatencies = appCases.compactMap(
                    \.visibleText?.keyUpToAccessibilityTextMilliseconds
                )
                let passed = appCases.filter(\.assessment.passed).count
                return RuntimeAppSummary(
                    targetID: targetID,
                    totalCases: appCases.count,
                    passedCases: passed,
                    failedCases: appCases.count - passed,
                    noPasteCases: appCases.filter { isVisiblePasteFailure($0.assessment.status) }.count,
                    p50AccessibilityTextMilliseconds: RuntimeStatistics.percentile(
                        50,
                        values: appAccessibilityLatencies
                    ),
                    p95AccessibilityTextMilliseconds: RuntimeStatistics.percentile(
                        95,
                        values: appAccessibilityLatencies
                    ),
                    p50VisibleMilliseconds: RuntimeStatistics.percentile(50, values: appLatencies),
                    p95VisibleMilliseconds: RuntimeStatistics.percentile(95, values: appLatencies),
                    maxVisibleMilliseconds: appLatencies.max()
                )
            }
            .sorted { $0.targetID < $1.targetID }
        let passed = cases.filter(\.assessment.passed).count
        return RuntimeRunSummary(
            totalCases: cases.count,
            passedCases: passed,
            failedCases: cases.count - passed,
            noPasteCases: cases.filter { isVisiblePasteFailure($0.assessment.status) }.count,
            p50AccessibilityTextMilliseconds: RuntimeStatistics.percentile(
                50,
                values: accessibilityLatencies
            ),
            p95AccessibilityTextMilliseconds: RuntimeStatistics.percentile(
                95,
                values: accessibilityLatencies
            ),
            p50VisibleMilliseconds: RuntimeStatistics.percentile(50, values: latencies),
            p95VisibleMilliseconds: RuntimeStatistics.percentile(95, values: latencies),
            maxVisibleMilliseconds: latencies.max(),
            p50PipelineCompleteMilliseconds: RuntimeStatistics.percentile(
                50,
                values: pipelineCompleteLatencies
            ),
            p95PipelineCompleteMilliseconds: RuntimeStatistics.percentile(
                95,
                values: pipelineCompleteLatencies
            ),
            p50InteractionSettledMilliseconds: RuntimeStatistics.percentile(
                50,
                values: interactionSettledLatencies
            ),
            p95InteractionSettledMilliseconds: RuntimeStatistics.percentile(
                95,
                values: interactionSettledLatencies
            ),
            apps: appSummaries,
            passed: !cases.isEmpty && passed == cases.count
        )
    }

    private static func isVisiblePasteFailure(_ status: RuntimeCaseAssessment.Status) -> Bool {
        status == .noPaste || status == .clipboardOnly || status == .renderNotObserved
    }

    private static func write(report: RuntimeHarnessReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static func printCaseProgress(
        _ report: RuntimeCaseReport,
        index: Int,
        total: Int
    ) {
        let latency = report.visibleText?.keyUpToVisibleMilliseconds.map {
            String(format: "%.1fms", $0)
        } ?? "n/a"
        let accessibilityLatency = report.visibleText?.keyUpToAccessibilityTextMilliseconds.map {
            String(format: "%.1fms", $0)
        } ?? "n/a"
        print(
            "[\(index)/\(total)] \(report.target.displayName) | "
            + "\(URL(fileURLWithPath: report.fixturePath).lastPathComponent) | \(report.textScenario.rawValue) | "
            + "\(report.assessment.status.rawValue) | rendered=\(latency) ax=\(accessibilityLatency) | "
            + "boundary=\(report.failureBoundary.rawValue)"
        )
    }
}

enum RuntimeHarnessRunError: Error, CustomStringConvertible {
    case fixtureDurationMissing(String)

    var description: String {
        switch self {
        case .fixtureDurationMissing(let path):
            return "Fixture duration is unavailable: \(path)"
        }
    }
}
