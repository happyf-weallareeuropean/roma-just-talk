import AppKit
import ApplicationServices
import Foundation
import RuntimeE2ECore

struct RuntimeVisibleTextResult: Codable {
    let text: String?
    let fullText: String?
    let domPasteProof: RuntimeDOMPasteProof?
    let keyUpToAccessibilityTextMilliseconds: Double?
    let keyUpToVisibleMilliseconds: Double?
    let renderedText: RuntimeRenderedTextChangeResult?
    let observationTimings: [RuntimeVisibilityObservationTiming]?
    let role: String?
    let error: String?
}

struct RuntimeVisibilityObservationTiming: Codable {
    let startedAfterKeyUpMilliseconds: Double
    var renderedCaptureMilliseconds: Double?
    var accessibilityReadMilliseconds: Double?
    var precedingAccessibilityReadMilliseconds: Double?
    var domProofMilliseconds: Double?
    var targetRefreshMilliseconds: Double?
    var accessibilityReadSucceeded: Bool?
}

struct RuntimeTargetPreparationInfo: Codable {
    let targetID: String
    let bundleIdentifier: String
    let processIdentifier: Int32
    let testResourcePath: String
    let windowTitleToken: String
    let textScenario: RuntimeTextScenario
    let editableRole: String
    let matchedBy: String
}

struct RuntimeTargetCleanupInfo: Codable {
    let surfaceClosed: Bool
    let temporaryResourceRemoved: Bool
    let terminatedProcessIdentifiers: [Int32]
    let restoredInitiallyRunningApplication: Bool
    let restoredFrontmostApplication: Bool
    let errors: [String]

    var passed: Bool {
        surfaceClosed
            && temporaryResourceRemoved
            && restoredInitiallyRunningApplication
            && restoredFrontmostApplication
            && errors.isEmpty
    }
}

struct RuntimeAbandonedTargetCleanupInfo: Codable {
    let discoveredResources: Int
    let closedSurfaces: Int
    let removedResources: Int
    let unresolvedRunIDs: [String]
    let restoredFrontmostApplication: Bool
    let errors: [String]

    var passed: Bool {
        unresolvedRunIDs.isEmpty && restoredFrontmostApplication && errors.isEmpty
    }
}

final class RuntimePreparedTarget {
    let info: RuntimeTargetPreparationInfo
    private let target: RuntimeTargetApp
    private let appURL: URL
    private let appElement: AXUIElement
    private var windowElement: AXUIElement
    private var textElement: AXUIElement
    private let existingProcessIdentifiers: Set<pid_t>
    private let temporaryDirectoryURL: URL
    private let testResourceURL: URL
    private let previousFrontmostApplication: NSRunningApplication?
    private let renderedTextObserver: RuntimeRenderedTextObserver
    private let textScenario: RuntimeTextScenario
    private let pasteProofToken: String?

    init(
        target: RuntimeTargetApp,
        appURL: URL,
        appElement: AXUIElement,
        windowElement: AXUIElement,
        textElement: AXUIElement,
        processIdentifier: pid_t,
        testResourceURL: URL,
        windowTitleToken: String,
        textScenario: RuntimeTextScenario,
        pasteProofToken: String?,
        matchedBy: String,
        existingProcessIdentifiers: Set<pid_t>,
        temporaryDirectoryURL: URL,
        previousFrontmostApplication: NSRunningApplication?,
        renderedTextObserver: RuntimeRenderedTextObserver
    ) {
        self.target = target
        self.appURL = appURL
        self.appElement = appElement
        self.windowElement = windowElement
        self.textElement = textElement
        self.existingProcessIdentifiers = existingProcessIdentifiers
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.testResourceURL = testResourceURL
        self.previousFrontmostApplication = previousFrontmostApplication
        self.renderedTextObserver = renderedTextObserver
        self.textScenario = textScenario
        self.pasteProofToken = pasteProofToken
        self.info = RuntimeTargetPreparationInfo(
            targetID: target.id,
            bundleIdentifier: target.bundleIdentifier,
            processIdentifier: processIdentifier,
            testResourcePath: testResourceURL.path,
            windowTitleToken: windowTitleToken,
            textScenario: textScenario,
            editableRole: RuntimeAX.stringAttribute(kAXRoleAttribute, from: textElement) ?? "unknown",
            matchedBy: matchedBy
        )
    }

    func refreshRenderedBaseline() -> String? {
        renderedTextObserver.refreshBaseline()
    }

    func waitForVisibleText(
        keyUpAtSystemUptime: TimeInterval,
        timeoutSeconds: TimeInterval
    ) -> RuntimeVisibleTextResult {
        let finalTextSettleSeconds: TimeInterval = 0.25
        let targetRefreshIntervalSeconds: TimeInterval = 0.25
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastTargetRefreshSystemUptime = ProcessInfo.processInfo.systemUptime
        var lastError: String?
        var accessibilityText: String?
        var fullText: String?
        var domPasteProof: RuntimeDOMPasteProof?
        var accessibilityLatency: Double?
        var stableFullText: String?
        var stableSinceSystemUptime: TimeInterval?
        var renderedText: RuntimeRenderedTextChangeResult?
        var renderedError = renderedTextObserver.beginObservation()
        var observationTimings: [RuntimeVisibilityObservationTiming] = []

        while Date() < deadline {
            var timing = RuntimeVisibilityObservationTiming(
                startedAfterKeyUpMilliseconds:
                    (ProcessInfo.processInfo.systemUptime - keyUpAtSystemUptime) * 1_000
            )
            defer { observationTimings.append(timing) }
            let precedingReadStarted = ProcessInfo.processInfo.systemUptime
            let precedingText = RuntimeAX.text(from: textElement)
            timing.precedingAccessibilityReadMilliseconds =
                (ProcessInfo.processInfo.systemUptime - precedingReadStarted) * 1_000
            var capturedFrame: RuntimeCapturedTextFrame?
            if renderedError == nil {
                let captureStarted = ProcessInfo.processInfo.systemUptime
                do {
                    capturedFrame = try renderedTextObserver.captureFrame()
                } catch {
                    renderedError = String(describing: error)
                    renderedText = nil
                }
                timing.renderedCaptureMilliseconds =
                    (ProcessInfo.processInfo.systemUptime - captureStarted) * 1_000
            }

            let now = ProcessInfo.processInfo.systemUptime
            let currentText = RuntimeAX.text(from: textElement)
            timing.accessibilityReadMilliseconds =
                (ProcessInfo.processInfo.systemUptime - now) * 1_000
            timing.accessibilityReadSucceeded = currentText != nil
            if let capturedFrame {
                let inserted = currentText.flatMap { textScenario.insertedText(from: $0) }
                do {
                    renderedText = try renderedTextObserver.observeCapturedFrame(
                        capturedFrame,
                        accessibilityText: inserted,
                        precedingAccessibilityText: precedingText.flatMap { textScenario.insertedText(from: $0) },
                        keyUpAtSystemUptime: keyUpAtSystemUptime
                    )
                } catch {
                    renderedError = String(describing: error)
                    renderedText = nil
                }
            }
            if let currentText {
                fullText = currentText
                if let insertedText = textScenario.insertedText(from: currentText),
                   !insertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if stableFullText != currentText {
                        stableFullText = currentText
                        stableSinceSystemUptime = now
                        accessibilityText = insertedText
                        accessibilityLatency = max(0, now - keyUpAtSystemUptime) * 1_000
                    }
                } else if stableFullText != nil {
                    stableFullText = nil
                    stableSinceSystemUptime = nil
                    accessibilityText = nil
                    accessibilityLatency = nil
                }
            } else {
                stableFullText = nil
                stableSinceSystemUptime = nil
                accessibilityText = nil
                accessibilityLatency = nil
            }
            // A valid empty value is expected before insertion. Periodic rediscovery still
            // recovers detached elements that keep returning their last cached value.
            if currentText == nil || (accessibilityText == nil
                && now - lastTargetRefreshSystemUptime >= targetRefreshIntervalSeconds) {
                let refreshStarted = ProcessInfo.processInfo.systemUptime
                if let refreshedWindow = RuntimeAX.window(
                    containing: info.windowTitleToken,
                    in: appElement
                ) {
                    windowElement = refreshedWindow
                }
                if let refreshed = RuntimeAX.editableElement(
                    in: windowElement,
                    identifying: target.kind == .browser
                        ? RuntimeTargetIsolationPlan.browserEditableLabel(windowTitleToken: info.windowTitleToken)
                        : info.windowTitleToken
                ) ?? (target.kind == .browser ? nil : RuntimeAX.firstEditableElement(in: windowElement)) {
                    textElement = refreshed
                } else {
                    lastError = "Unique target surface no longer exposes an editable AX element"
                }
                timing.targetRefreshMilliseconds =
                    (ProcessInfo.processInfo.systemUptime - refreshStarted) * 1_000
                lastTargetRefreshSystemUptime = ProcessInfo.processInfo.systemUptime
            }

            let finalTextIsStable = stableSinceSystemUptime.map {
                now - $0 >= finalTextSettleSeconds
            } ?? false
            if finalTextIsStable,
               (renderedText?.keyUpToRenderedTextMilliseconds != nil || renderedError != nil
                || renderedTextObserver.associationError != nil) {
                break
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.016))
        }

        // The controlled page retains cumulative paste/input counts. Inspect the final
        // receipt after sampling so tree traversal cannot delay a rendered observation.
        if let pasteProofToken {
            let proofStarted = ProcessInfo.processInfo.systemUptime
            domPasteProof = RuntimeAX.domPasteProof(
                in: windowElement,
                identifying: pasteProofToken
            )
            var timing = RuntimeVisibilityObservationTiming(
                startedAfterKeyUpMilliseconds: (proofStarted - keyUpAtSystemUptime) * 1_000
            )
            timing.domProofMilliseconds =
                (ProcessInfo.processInfo.systemUptime - proofStarted) * 1_000
            observationTimings.append(timing)
        }

        if renderedText == nil {
            renderedText = renderedTextObserver.failureResult(
                error: renderedError ?? renderedTextObserver.associationError
                    ?? "Stable rendered pixels associated with inserted AX text were not observed before timeout"
            )
        }
        let visibleLatency = RuntimeTextVisibilityAttribution.renderedLatency(
            accessibilityText: accessibilityText,
            renderedLatency: renderedText?.keyUpToRenderedTextMilliseconds
        )
        var errors: [String] = []
        if accessibilityText == nil {
            errors.append(lastError ?? "Target never exposed non-empty inserted text through Accessibility")
        }
        if let renderedError = renderedText?.error {
            errors.append(renderedError)
        }
        return RuntimeVisibleTextResult(
            text: accessibilityText,
            fullText: fullText,
            domPasteProof: domPasteProof,
            keyUpToAccessibilityTextMilliseconds: accessibilityLatency,
            keyUpToVisibleMilliseconds: visibleLatency,
            renderedText: renderedText,
            observationTimings: observationTimings,
            role: RuntimeAX.stringAttribute(kAXRoleAttribute, from: textElement),
            error: errors.isEmpty ? nil : errors.joined(separator: "; ")
        )
    }

    func cleanup() -> RuntimeTargetCleanupInfo {
        var errors: [String] = []
        let runningApplication = NSRunningApplication(processIdentifier: info.processIdentifier)
        let application = runningApplication.flatMap {
            !$0.isTerminated && $0.bundleIdentifier == target.bundleIdentifier ? $0 : nil
        }

        var documentReadyToClose = true
        if target.kind.usesDocumentResource {
            if let application,
               RuntimeAX.clear(
                textElement: textElement,
                targetKind: target.kind,
                application: application,
                windowElement: windowElement
            ) {
                if !RuntimeAX.saveClearedDocumentIfNeeded(
                    fileURL: testResourceURL,
                    application: application,
                    windowElement: windowElement,
                    textElement: textElement
                ) {
                    errors.append("Could not save the cleared temporary document before closing it")
                    documentReadyToClose = false
                }
            } else {
                errors.append("Could not clear the temporary document before closing it")
                documentReadyToClose = false
            }
        }

        var surfaceClosed = documentReadyToClose && RuntimeAX.closeSurface(
            application: application,
            token: info.windowTitleToken,
            in: appElement,
            timeoutSeconds: 3,
            useCloseButtonFallback: target.bundleIdentifier == "com.apple.TextEdit"
        )

        var terminatedProcessIdentifiers: [Int32] = []
        if documentReadyToClose {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
            for application in running where !existingProcessIdentifiers.contains(application.processIdentifier) {
                if application.terminate(),
                   RuntimeAX.waitForTermination(application, timeoutSeconds: 3) {
                    terminatedProcessIdentifiers.append(application.processIdentifier)
                } else {
                    errors.append("Could not terminate newly launched target process \(application.processIdentifier)")
                }
            }
        }
        if !surfaceClosed {
            surfaceClosed = RuntimeAX.waitForSurfaceToClose(
                token: info.windowTitleToken,
                in: appElement,
                timeoutSeconds: 1
            )
        }
        if !surfaceClosed, documentReadyToClose {
            errors.append("Could not close the uniquely tokened target surface")
        }
        let restoredInitiallyRunningApplication =
            RuntimeTargetController.restoreInitiallyRunningApplicationIfNeeded(
                appURL: appURL,
                bundleIdentifier: target.bundleIdentifier,
                existingProcessIdentifiers: existingProcessIdentifiers
            )
        if !restoredInitiallyRunningApplication {
            errors.append("Could not restore target app that was running before preparation")
        }

        let temporaryResourceRemoved: Bool
        if documentReadyToClose, surfaceClosed {
            do {
                try FileManager.default.removeItem(at: temporaryDirectoryURL)
                temporaryResourceRemoved = true
            } catch {
                temporaryResourceRemoved = !FileManager.default.fileExists(atPath: temporaryDirectoryURL.path)
                if !temporaryResourceRemoved {
                    errors.append("Could not remove temporary target resource: \(error)")
                }
            }
        } else {
            temporaryResourceRemoved = false
            errors.append(
                documentReadyToClose
                    ? "Preserved temporary target resource because its surface remains open"
                    : "Preserved temporary target resource because its cleared content was not saved"
            )
        }

        let restoredFrontmostApplication: Bool
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            restoredFrontmostApplication = previousFrontmostApplication.activate()
        } else {
            restoredFrontmostApplication = true
        }

        return RuntimeTargetCleanupInfo(
            surfaceClosed: surfaceClosed,
            temporaryResourceRemoved: temporaryResourceRemoved,
            terminatedProcessIdentifiers: terminatedProcessIdentifiers,
            restoredInitiallyRunningApplication: restoredInitiallyRunningApplication,
            restoredFrontmostApplication: restoredFrontmostApplication,
            errors: errors
        )
    }
}

enum RuntimeTargetController {
    static let temporaryTargetsRootURL = URL(
        fileURLWithPath: "/tmp/roma-runtime-e2e-targets",
        isDirectory: true
    )

    private struct TestResource {
        let url: URL
        let windowTitleToken: String
        let pasteProofToken: String?
    }

    private struct TargetSurface {
        let application: NSRunningApplication
        let appElement: AXUIElement
        let windowElement: AXUIElement
        let textElement: AXUIElement
        let matchedBy: String
    }

    static func prepare(
        target: RuntimeTargetApp,
        textScenario: RuntimeTextScenario = .empty,
        runID: String,
        settleSeconds: TimeInterval,
        availabilityPolicy: RuntimeHarnessConfiguration.TargetAvailabilityPolicy
    ) throws -> RuntimePreparedTarget {
        guard AXIsProcessTrusted() else {
            throw RuntimeTargetControllerError.accessibilityNotGranted
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            throw RuntimeTargetControllerError.applicationNotFound(target.bundleIdentifier)
        }

        let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        var existingApplications = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
        if availabilityPolicy == .runningOnly, existingApplications.isEmpty {
            let deadline = Date().addingTimeInterval(2)
            while existingApplications.isEmpty, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                existingApplications = NSRunningApplication.runningApplications(
                    withBundleIdentifier: target.bundleIdentifier
                )
            }
        }
        if availabilityPolicy == .runningOnly, existingApplications.isEmpty {
            throw RuntimeTargetControllerError.targetNotRunning(target.bundleIdentifier)
        }
        let existingProcessIdentifiers = Set(existingApplications.map(\.processIdentifier))
        let temporaryDirectoryURL = temporaryTargetsRootURL
            .appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        let resource = try createTestResource(
            target: target,
            textScenario: textScenario,
            title: "Roma Runtime E2E \(runID)",
            directoryURL: temporaryDirectoryURL
        )
        do {
            try launch(
                appURL: appURL,
                appName: appURL.lastPathComponent,
                bundleIdentifier: target.bundleIdentifier,
                resourceURL: resource.url
            )
            var surface = try waitForTargetSurface(
                bundleIdentifier: target.bundleIdentifier,
                targetKind: target.kind,
                windowTitleToken: resource.windowTitleToken,
                timeoutSeconds: 15
            )
            guard let preparedSurface = establishBaseline(
                surface: surface,
                bundleIdentifier: target.bundleIdentifier,
                windowTitleToken: resource.windowTitleToken,
                textScenario: textScenario,
                targetKind: target.kind,
                settleSeconds: settleSeconds
            ) else {
                throw RuntimeTargetControllerError.couldNotPrepareTarget
            }
            surface = preparedSurface
            guard let editableFrame = RuntimeAX.observationFrame(
                for: surface.textElement,
                fallbackWindow: surface.windowElement
            ) else {
                throw RuntimeTargetControllerError.renderObservationUnavailable(
                    "Target editor has no usable screen rectangle"
                )
            }
            let renderedTextObserver: RuntimeRenderedTextObserver
            do {
                renderedTextObserver = try RuntimeRenderedTextObserver(editableFrame: editableFrame)
            } catch {
                throw RuntimeTargetControllerError.renderObservationUnavailable(String(describing: error))
            }

            return RuntimePreparedTarget(
                target: target,
                appURL: appURL,
                appElement: surface.appElement,
                windowElement: surface.windowElement,
                textElement: surface.textElement,
                processIdentifier: surface.application.processIdentifier,
                testResourceURL: resource.url,
                windowTitleToken: resource.windowTitleToken,
                textScenario: textScenario,
                pasteProofToken: resource.pasteProofToken,
                matchedBy: surface.matchedBy,
                existingProcessIdentifiers: existingProcessIdentifiers,
                temporaryDirectoryURL: temporaryDirectoryURL,
                previousFrontmostApplication: previousFrontmostApplication,
                renderedTextObserver: renderedTextObserver
            )
        } catch {
            cleanupFailedPreparation(
                target: target,
                appURL: appURL,
                bundleIdentifier: target.bundleIdentifier,
                windowTitleToken: resource.windowTitleToken,
                existingProcessIdentifiers: existingProcessIdentifiers,
                temporaryDirectoryURL: temporaryDirectoryURL,
                previousFrontmostApplication: previousFrontmostApplication,
                testResourceURL: resource.url
            )
            throw error
        }
    }

    static func restoreAbandonedTargets(
        targets: [RuntimeTargetApp]
    ) -> RuntimeAbandonedTargetCleanupInfo {
        guard AXIsProcessTrusted() else {
            return RuntimeAbandonedTargetCleanupInfo(
                discoveredResources: 0,
                closedSurfaces: 0,
                removedResources: 0,
                unresolvedRunIDs: [],
                restoredFrontmostApplication: false,
                errors: ["Accessibility is not granted; abandoned target surfaces were not inspected"]
            )
        }

        let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        let resourceURLs = (try? FileManager.default.contentsOfDirectory(
            at: temporaryTargetsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var closedSurfaces = 0
        var removedResources = 0
        var unresolvedRunIDs: [String] = []
        var errors: [String] = []

        for resourceURL in resourceURLs {
            let runID = resourceURL.lastPathComponent
            guard let target = targets.first(where: {
                RuntimeTargetIsolationPlan.runID(runID, belongsToTargetID: $0.id)
            }) else {
                unresolvedRunIDs.append(runID)
                continue
            }
            let tokens = [
                "Roma Runtime E2E \(runID)",
                "Roma-Runtime-E2E-\(runID)"
            ]
            var matchedSurface: TargetSurface?
            var matchedToken: String?
            for token in tokens {
                if let surface = try? waitForTargetSurface(
                    bundleIdentifier: target.bundleIdentifier,
                    targetKind: target.kind,
                    windowTitleToken: token,
                    timeoutSeconds: 0.5
                ) {
                    matchedSurface = surface
                    matchedToken = token
                    break
                }
            }

            if let surface = matchedSurface, let matchedToken {
                var documentReadyToClose = true
                if target.kind.usesDocumentResource {
                    let resourceTokens = [matchedToken] + tokens.filter { $0 != matchedToken }
                    let testResourceURL = resourceTokens
                        .map {
                            resourceURL.appendingPathComponent(
                                RuntimeTargetIsolationPlan.documentFilename(
                                    windowTitleToken: $0,
                                    bundleIdentifier: target.bundleIdentifier
                                )
                            )
                        }
                        .first { FileManager.default.fileExists(atPath: $0.path) }
                    if let testResourceURL,
                       RuntimeAX.clear(
                        textElement: surface.textElement,
                        targetKind: target.kind,
                        application: surface.application,
                        windowElement: surface.windowElement
                    ) {
                        documentReadyToClose = RuntimeAX.saveClearedDocumentIfNeeded(
                            fileURL: testResourceURL,
                            application: surface.application,
                            windowElement: surface.windowElement,
                            textElement: surface.textElement
                        )
                    } else {
                        documentReadyToClose = false
                    }
                }
                guard documentReadyToClose else {
                    unresolvedRunIDs.append(runID)
                    errors.append("Could not save abandoned target \(runID); preserved its surface and resource")
                    continue
                }
                guard RuntimeAX.closeSurface(
                    application: surface.application,
                    token: matchedToken,
                    in: surface.appElement,
                    timeoutSeconds: 2,
                    useCloseButtonFallback: target.bundleIdentifier == "com.apple.TextEdit"
                ) else {
                    unresolvedRunIDs.append(runID)
                    errors.append("Could not close abandoned target \(runID); preserved its resource")
                    continue
                }
                closedSurfaces += 1
            }

            do {
                try FileManager.default.removeItem(at: resourceURL)
                removedResources += 1
            } catch {
                unresolvedRunIDs.append(runID)
                errors.append("Could not remove abandoned target \(runID): \(error)")
            }
        }

        let restoredFrontmostApplication: Bool
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            restoredFrontmostApplication = previousFrontmostApplication.activate()
        } else {
            restoredFrontmostApplication = true
        }

        return RuntimeAbandonedTargetCleanupInfo(
            discoveredResources: resourceURLs.count,
            closedSurfaces: closedSurfaces,
            removedResources: removedResources,
            unresolvedRunIDs: unresolvedRunIDs.sorted(),
            restoredFrontmostApplication: restoredFrontmostApplication,
            errors: errors
        )
    }

    private static func createTestResource(
        target: RuntimeTargetApp,
        textScenario: RuntimeTextScenario,
        title: String,
        directoryURL: URL
    ) throws -> TestResource {
        switch target.kind {
        case .browser:
            let url = directoryURL.appendingPathComponent("target.html")
            let escapedTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let editableLabel = RuntimeTargetIsolationPlan.browserEditableLabel(
                windowTitleToken: title
            )
            let escapedInitialText = textScenario.initialText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let pasteProofToken = "Roma Runtime E2E Paste Proof \(title)"
            let escapedPasteProofToken = pasteProofToken
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = """
            <!doctype html>
            <meta charset="utf-8">
            <title>\(escapedTitle)</title>
            <style>
              body { margin: 40px; font: 18px -apple-system, sans-serif; }
              #target { width: 900px; height: 420px; padding: 8px; border: 1px solid; font: 20px -apple-system, sans-serif; white-space: pre-wrap; }
              #paste-proof { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
            </style>
            <div>\(editableLabel)</div>
            <div id="target" role="textbox" aria-label="\(editableLabel)" aria-multiline="true" contenteditable="true" spellcheck="false">\(escapedInitialText)</div>
            <div id="paste-proof" role="status" aria-label="\(escapedPasteProofToken) pasteEvents=0 pasteInputs=0">\(escapedPasteProofToken) pasteEvents=0 pasteInputs=0</div>
            <script>
              const target = document.getElementById('target');
              const pasteProof = document.getElementById('paste-proof');
              const pasteProofToken = '\(escapedPasteProofToken)';
              const cursorOffset = \(textScenario.cursorUTF16Offset);
              let acceptedText = target.textContent;
              let pasteEventCount = 0;
              let pasteInputCount = 0;
              const updatePasteProof = () => {
                const proof = `${pasteProofToken} pasteEvents=${pasteEventCount} pasteInputs=${pasteInputCount}`;
                pasteProof.textContent = proof;
                pasteProof.setAttribute('aria-label', proof);
              };
              const placeCursor = () => {
                const node = target.firstChild || target.appendChild(document.createTextNode(''));
                const range = document.createRange();
                range.setStart(node, Math.min(cursorOffset, node.length));
                range.collapse(true);
                const selection = getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
              };
              let pasteObserved = false;
              target.addEventListener('paste', () => {
                pasteObserved = true;
                pasteEventCount += 1;
                updatePasteProof();
              });
              target.addEventListener('input', event => {
                if (pasteObserved || event.inputType === 'insertFromPaste') {
                  acceptedText = target.textContent;
                  pasteInputCount += 1;
                  updatePasteProof();
                }
                pasteObserved = false;
              });
              const observer = new MutationObserver(() => {
                if (target.textContent === acceptedText) return;
                target.textContent = acceptedText;
                placeCursor();
              });
              addEventListener('load', () => {
                target.focus();
                placeCursor();
                observer.observe(target, { childList: true, characterData: true, subtree: true });
              });
            </script>
            """
            try Data(html.utf8).write(to: url, options: .atomic)
            return TestResource(
                url: url,
                windowTitleToken: title,
                pasteProofToken: pasteProofToken
            )
        case .document, .electron:
            let filename = RuntimeTargetIsolationPlan.documentFilename(
                windowTitleToken: title,
                bundleIdentifier: target.bundleIdentifier
            )
            let url = directoryURL.appendingPathComponent(filename)
            try Data(textScenario.initialText.utf8).write(to: url, options: .atomic)
            return TestResource(url: url, windowTitleToken: title, pasteProofToken: nil)
        }
    }

    private static func launch(
        appURL: URL,
        appName: String,
        bundleIdentifier: String,
        resourceURL: URL
    ) throws {
        let process = Process()
        let launchesAsynchronously: Bool
        if bundleIdentifier == "com.google.Chrome"
            || bundleIdentifier == "com.microsoft.VSCode" {
            guard let launcherURL = Bundle(url: appURL)?.executableURL,
                  FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
                throw RuntimeTargetControllerError.launcherNotFound(appName, appURL.path)
            }
            process.executableURL = launcherURL
            process.arguments = bundleIdentifier == "com.google.Chrome"
                ? RuntimeTargetIsolationPlan.chromeArguments(resourceURL: resourceURL)
                : RuntimeTargetIsolationPlan.vscodeArguments(resourcePath: resourceURL.path)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            launchesAsynchronously = true
        } else if bundleIdentifier == "com.coteditor.CotEditor" {
            let relativeLauncherPath = "Contents/SharedSupport/bin/cot"
            let launcherURL = appURL.appendingPathComponent(relativeLauncherPath)
            guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
                throw RuntimeTargetControllerError.launcherNotFound(appName, launcherURL.path)
            }
            process.executableURL = launcherURL
            process.arguments = [resourceURL.path]
            launchesAsynchronously = false
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleIdentifier, resourceURL.path]
            launchesAsynchronously = false
        }
        try process.run()
        if launchesAsynchronously {
            // GUI processes may remain attached; bounded surface discovery is the launch result.
            return
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeTargetControllerError.launchFailed(appName, process.terminationStatus)
        }
    }

    private static func waitForTargetSurface(
        bundleIdentifier: String,
        targetKind: RuntimeTargetApp.Kind,
        windowTitleToken: String,
        timeoutSeconds: TimeInterval
    ) throws -> TargetSurface {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let applications = orderedApplications(bundleIdentifier: bundleIdentifier)
            for application in applications {
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                // A browser window can exist before its editor; never accept the address bar.
                if targetKind != .browser,
                   let windowElement = RuntimeAX.window(containing: windowTitleToken, in: appElement),
                   let textElement = RuntimeAX.firstEditableElement(in: windowElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "windowTitle"
                    )
                }

                if let textElement = RuntimeAX.editableElement(
                    in: appElement,
                    identifying: targetKind == .browser
                        ? RuntimeTargetIsolationPlan.browserEditableLabel(windowTitleToken: windowTitleToken)
                        : windowTitleToken
                ), let windowElement = RuntimeAX.window(for: textElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "editableIdentifier"
                    )
                }

                if targetKind != .browser,
                   let markerElement = RuntimeAX.element(
                    in: appElement,
                    identifying: windowTitleToken
                ), let windowElement = RuntimeAX.window(for: markerElement),
                   let textElement = RuntimeAX.focusedEditableElement(
                       in: appElement,
                       matchingWindow: windowElement
                   ) ?? RuntimeAX.firstEditableElement(in: windowElement) {
                    return TargetSurface(
                        application: application,
                        appElement: appElement,
                        windowElement: windowElement,
                        textElement: textElement,
                        matchedBy: "surfaceMarker"
                    )
                }
            }

            if let application = applications.first {
                _ = application.activate(options: [.activateAllWindows])
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeTargetControllerError.targetSurfaceTimedOut(bundleIdentifier)
    }

    private static func establishBaseline(
        surface: TargetSurface,
        bundleIdentifier: String,
        windowTitleToken: String,
        textScenario: RuntimeTextScenario,
        targetKind: RuntimeTargetApp.Kind,
        settleSeconds: TimeInterval
    ) -> TargetSurface? {
        var candidate = surface
        for attempt in 0..<2 {
            RuntimeAX.focus(
                application: candidate.application,
                windowElement: candidate.windowElement,
                textElement: candidate.textElement
            )
            if RuntimeAX.prepareBaseline(
                textScenario,
                textElement: candidate.textElement,
                targetKind: targetKind
            ) {
                Thread.sleep(forTimeInterval: settleSeconds)
                if RuntimeAX.matchesBaseline(
                    textScenario,
                    textElement: candidate.textElement,
                    targetKind: targetKind
                ) {
                    return candidate
                }
            }
            guard attempt == 0,
                  let refreshed = try? waitForTargetSurface(
                    bundleIdentifier: bundleIdentifier,
                    targetKind: targetKind,
                    windowTitleToken: windowTitleToken,
                    timeoutSeconds: 2
                  ) else {
                continue
            }
            candidate = refreshed
        }
        return nil
    }

    private static func orderedApplications(bundleIdentifier: String) -> [NSRunningApplication] {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier == bundleIdentifier else {
            return Array(applications.reversed())
        }
        return [frontmost] + Array(
            applications
                .filter { $0.processIdentifier != frontmost.processIdentifier }
                .reversed()
        )
    }

    private static func cleanupFailedPreparation(
        target: RuntimeTargetApp,
        appURL: URL,
        bundleIdentifier: String,
        windowTitleToken: String,
        existingProcessIdentifiers: Set<pid_t>,
        temporaryDirectoryURL: URL,
        previousFrontmostApplication: NSRunningApplication?,
        testResourceURL: URL
    ) {
        var preparedSurface: TargetSurface?
        var surfaceClosed = false
        var safeToTerminate = false
        if let surface = try? waitForTargetSurface(
            bundleIdentifier: bundleIdentifier,
            targetKind: target.kind,
            windowTitleToken: windowTitleToken,
            timeoutSeconds: 1
        ) {
            preparedSurface = surface
            var documentReadyToClose = true
            if target.kind.usesDocumentResource {
                if RuntimeAX.clear(
                    textElement: surface.textElement,
                    targetKind: target.kind,
                    application: surface.application,
                    windowElement: surface.windowElement
                ) {
                    documentReadyToClose = RuntimeAX.saveClearedDocumentIfNeeded(
                        fileURL: testResourceURL,
                        application: surface.application,
                        windowElement: surface.windowElement,
                        textElement: surface.textElement
                    )
                } else {
                    documentReadyToClose = false
                }
            }
            safeToTerminate = documentReadyToClose
            if documentReadyToClose {
                surfaceClosed = RuntimeAX.closeSurface(
                    application: surface.application,
                    token: windowTitleToken,
                    in: surface.appElement,
                    timeoutSeconds: 2,
                    useCloseButtonFallback: target.bundleIdentifier == "com.apple.TextEdit"
                )
            } else {
                surfaceClosed = false
            }
        }

        if safeToTerminate {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            where !existingProcessIdentifiers.contains(application.processIdentifier) {
                if application.terminate() {
                    _ = RuntimeAX.waitForTermination(application, timeoutSeconds: 3)
                }
            }
        }
        if !surfaceClosed, let preparedSurface {
            surfaceClosed = RuntimeAX.waitForSurfaceToClose(
                token: windowTitleToken,
                in: preparedSurface.appElement,
                timeoutSeconds: 1
            )
        }
        _ = restoreInitiallyRunningApplicationIfNeeded(
            appURL: appURL,
            bundleIdentifier: bundleIdentifier,
            existingProcessIdentifiers: existingProcessIdentifiers
        )
        if safeToTerminate, surfaceClosed {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            _ = previousFrontmostApplication.activate()
        }
    }

    fileprivate static func restoreInitiallyRunningApplicationIfNeeded(
        appURL: URL,
        bundleIdentifier: String,
        existingProcessIdentifiers: Set<pid_t>
    ) -> Bool {
        let isRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
        guard RuntimeTargetLifecyclePlan.shouldRestoreApplication(
            wasRunningBeforePreparation: !existingProcessIdentifiers.isEmpty,
            isRunningAfterCleanup: isRunning
        ) else {
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", appURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0 else { return false }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).isEmpty {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
    }
}

enum RuntimeAX {
    private static let editableRoles = Set([kAXTextAreaRole as String, kAXTextFieldRole as String])

    static func firstEditableElement(in root: AXUIElement) -> AXUIElement? {
        editableElement(in: root, identifying: nil)
    }

    static func editableElement(in root: AXUIElement, identifying token: String?) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0
        var visited = 0
        var best: (score: Int, element: AXUIElement)?
        while nextIndex < queue.count && visited < 10_000 {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1
            if isEditable(element) {
                let identifyingText = identifyingText(from: element)
                if let token,
                   identifyingText.localizedCaseInsensitiveContains(token) {
                    return element
                }
                if token == nil {
                    let score = editableScore(element)
                    if best == nil || score > best!.score {
                        best = (score, element)
                    }
                }
            }
            guard depth < 24 else { continue }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
        }
        return best?.element
    }

    static func element(in root: AXUIElement, identifying token: String) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nextIndex = 0
        var visited = 0
        while nextIndex < queue.count && visited < 10_000 {
            let (element, depth) = queue[nextIndex]
            nextIndex += 1
            visited += 1
            if identifyingText(from: element).localizedCaseInsensitiveContains(token) {
                return element
            }
            guard depth < 24 else { continue }
            queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
        }
        return nil
    }

    static func domPasteProof(
        in root: AXUIElement,
        identifying token: String
    ) -> RuntimeDOMPasteProof? {
        guard let proofElement = element(in: root, identifying: token) else { return nil }
        let proofText = [identifyingText(from: proofElement), text(from: proofElement)]
            .compactMap { $0 }
            .joined(separator: " ")
        return RuntimeDOMPasteProof.parse(from: proofText)
    }

    static func focusedEditableElement(
        in appElement: AXUIElement,
        matchingWindow windowElement: AXUIElement
    ) -> AXUIElement? {
        guard let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: appElement),
              isEditable(focusedElement),
              let focusedWindow = window(for: focusedElement),
              CFEqual(focusedWindow, windowElement) else {
            return nil
        }
        return focusedElement
    }

    static func text(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let value else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        return (value as? NSAttributedString)?.string
    }

    static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func observationFrame(
        for textElement: AXUIElement,
        fallbackWindow: AXUIElement
    ) -> CGRect? {
        // Empty Electron text areas can be zero-sized; use the nearest visible editor container.
        var currentElement: AXUIElement? = textElement
        for _ in 0..<24 {
            guard let element = currentElement else { break }
            if let candidate = frame(of: element), isUsableObservationFrame(candidate) {
                return candidate
            }
            currentElement = elementAttribute(kAXParentAttribute, from: element)
        }
        guard let fallback = frame(of: fallbackWindow), isUsableObservationFrame(fallback) else {
            return nil
        }
        return fallback
    }

    static func window(for element: AXUIElement) -> AXUIElement? {
        if let window = elementAttribute(kAXWindowAttribute, from: element) {
            return window
        }

        var current = element
        for _ in 0..<24 {
            if stringAttribute(kAXRoleAttribute, from: current) == kAXWindowRole as String {
                return current
            }
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else {
                return nil
            }
            current = parent
        }
        return nil
    }

    static func window(containing token: String, in appElement: AXUIElement) -> AXUIElement? {
        elementArrayAttribute(kAXWindowsAttribute, from: appElement).first { window in
            stringAttribute(kAXTitleAttribute, from: window)?
                .localizedCaseInsensitiveContains(token) == true
        }
    }

    @discardableResult
    static func focus(
        application: NSRunningApplication,
        windowElement: AXUIElement,
        textElement: AXUIElement,
        requireFrontmostApplication: Bool = true
    ) -> Bool {
        guard !application.isTerminated else { return false }
        _ = application.activate(options: [.activateAllWindows])
        AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            windowElement,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            windowElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            textElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: appElement)
            if !application.isTerminated,
               (!requireFrontmostApplication
                   || NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier),
               let focusedWindow,
               CFEqual(focusedWindow, windowElement) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return false
    }

    static func clear(
        textElement: AXUIElement,
        targetKind: RuntimeTargetApp.Kind,
        application: NSRunningApplication,
        windowElement: AXUIElement
    ) -> Bool {
        if AXUIElementSetAttributeValue(
            textElement,
            kAXValueAttribute as CFString,
            "" as CFString
        ) == .success,
        waitForBaselineText(.empty, targetKind: targetKind, in: textElement, timeoutSeconds: 1) {
            return true
        }

        guard focus(
            application: application,
            windowElement: windowElement,
            textElement: textElement
        ) else { return false }
        postKey(keyCode: 0, flags: .maskCommand, processIdentifier: application.processIdentifier)
        postKey(keyCode: 51, flags: [], processIdentifier: application.processIdentifier)
        return waitForBaselineText(.empty, targetKind: targetKind, in: textElement, timeoutSeconds: 2)
    }

    static func prepareBaseline(
        _ scenario: RuntimeTextScenario,
        textElement: AXUIElement,
        targetKind: RuntimeTargetApp.Kind
    ) -> Bool {
        if !RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            text(from: textElement),
            scenario: scenario,
            targetKind: targetKind
        ) {
            _ = AXUIElementSetAttributeValue(
                textElement,
                kAXValueAttribute as CFString,
                scenario.initialText as CFString
            )
        }
        guard waitForBaselineText(
            scenario,
            targetKind: targetKind,
            in: textElement,
            timeoutSeconds: 1
        ) else {
            return false
        }
        guard scenario != .empty else {
            return true
        }
        let expectedRange = CFRange(location: scenario.cursorUTF16Offset, length: 0)
        if targetKind == .electron {
            // VS Code can report a successful AX range change while its real caret stays at zero.
            return positionElectronBaselineCursor(scenario, textElement: textElement)
        }
        return setSelectedTextRange(expectedRange, on: textElement)
    }

    private static func positionElectronBaselineCursor(
        _ scenario: RuntimeTextScenario,
        textElement: AXUIElement
    ) -> Bool {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(textElement, &processIdentifier) == .success,
              let windowElement = window(for: textElement) else { return false }
        let appElement = AXUIElementCreateApplication(processIdentifier)
        func hasOwnedBaselineEditor() -> Bool {
            guard AXIsProcessTrusted(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
                  let focused = focusedEditableElement(in: appElement, matchingWindow: windowElement),
                  CFEqual(focused, textElement),
                  text(from: focused) == scenario.initialText else {
                return false
            }
            return true
        }
        func postOwnedKey(_ keyCode: UInt16, flags: CGEventFlags) -> Bool {
            guard hasOwnedBaselineEditor(),
                  postKey(keyCode: keyCode, flags: flags, processIdentifier: processIdentifier) else {
                return false
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.03))
            return true
        }
        guard postOwnedKey(123, flags: .maskCommand) else { return false }
        for _ in 0..<scenario.cursorUTF16Offset {
            guard postOwnedKey(124, flags: []) else { return false }
        }
        return waitForSelectedTextRange(
            CFRange(location: scenario.cursorUTF16Offset, length: 0),
            on: textElement,
            timeoutSeconds: 1
        ) && hasOwnedBaselineEditor()
    }

    static func matchesBaseline(
        _ scenario: RuntimeTextScenario,
        textElement: AXUIElement,
        targetKind: RuntimeTargetApp.Kind
    ) -> Bool {
        guard RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            text(from: textElement),
            scenario: scenario,
            targetKind: targetKind
        ) else {
            return false
        }
        guard scenario != .empty else {
            return true
        }
        return sameRange(
            selectedTextRange(from: textElement),
            CFRange(location: scenario.cursorUTF16Offset, length: 0)
        )
    }

    static func saveClearedDocumentIfNeeded(
        fileURL: URL,
        application: NSRunningApplication,
        windowElement: AXUIElement,
        textElement: AXUIElement
    ) -> Bool {
        let editedBeforeSave = boolAttribute(kAXEditedAttribute, from: windowElement)
        let fileWasEmpty = fileIsEmpty(fileURL)
        // Cleanup already verified the empty AX baseline; an empty fixture has nothing left to persist.
        if fileWasEmpty == true {
            return true
        }
        let modificationDateBeforeSave = fileModificationDate(fileURL)
        guard focus(
            application: application,
            windowElement: windowElement,
            textElement: textElement
        ) else { return false }
        postKey(
            keyCode: 1,
            flags: .maskCommand,
            processIdentifier: application.processIdentifier
        )
        let requiresEditedAcknowledgement = editedBeforeSave == true
        let requiresFileAcknowledgement = fileWasEmpty != true
        let requiresModificationAcknowledgement = editedBeforeSave == nil && fileWasEmpty != false
        let deadline = Date().addingTimeInterval(2)
        repeat {
            let editAcknowledged = !requiresEditedAcknowledgement
                || boolAttribute(kAXEditedAttribute, from: windowElement) == false
            let fileAcknowledged = !requiresFileAcknowledgement
                || fileIsEmpty(fileURL) == true
            let modificationAcknowledged = !requiresModificationAcknowledgement
                || modificationDateBeforeSave != fileModificationDate(fileURL)
            if editAcknowledged && fileAcknowledged && modificationAcknowledged {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        } while Date() < deadline
        return false
    }

    private static func fileIsEmpty(_ url: URL) -> Bool? {
        try? Data(contentsOf: url).isEmpty
    }

    private static func fileModificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func waitForSurfaceToClose(
        token: String,
        in appElement: AXUIElement,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !surfaceExistsInWindows(token: token, in: appElement) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return !surfaceExistsInWindows(token: token, in: appElement)
    }

    static func closeSurface(
        application: NSRunningApplication?,
        token: String,
        in appElement: AXUIElement,
        timeoutSeconds: TimeInterval,
        useCloseButtonFallback: Bool
    ) -> Bool {
        guard let application else {
            return reportCloseFailure("application unavailable", token: token, in: appElement)
        }
        var discardedSheetCount = 0
        // A scoped surface may outlive one close attempt; retry only while its unique token exists.
        for _ in 0..<2 {
            guard let currentWindow = surfaceWindow(token: token, in: appElement) else {
                return true
            }
            guard let currentTextElement = editableElement(in: currentWindow, identifying: token)
                ?? focusedEditableElement(in: appElement, matchingWindow: currentWindow)
                ?? firstEditableElement(in: currentWindow) else {
                return reportCloseFailure("editable element unavailable", token: token, in: appElement)
            }
            guard focus(
                application: application,
                windowElement: currentWindow,
                textElement: currentTextElement,
                requireFrontmostApplication: false
            ) else {
                return reportCloseFailure("window focus failed", token: token, in: appElement)
            }
            postKey(
                keyCode: 13,
                flags: .maskCommand,
                processIdentifier: application.processIdentifier
            )
            if discardChangesSheetIfPresent(
                    in: currentWindow,
                    processIdentifier: application.processIdentifier,
                    timeoutSeconds: 0.5
               ) {
                discardedSheetCount += 1
            }
            if waitForSurfaceToClose(
                token: token,
                in: appElement,
                timeoutSeconds: timeoutSeconds
            ) {
                return true
            }
        }
        guard useCloseButtonFallback else {
            return reportCloseFailure("keyboard close attempts exhausted", token: token, in: appElement)
        }
        guard let currentWindow = surfaceWindow(token: token, in: appElement),
              let currentTextElement = editableElement(in: currentWindow, identifying: token)
                ?? focusedEditableElement(in: appElement, matchingWindow: currentWindow)
                ?? firstEditableElement(in: currentWindow) else {
            return reportCloseFailure("fallback surface unavailable", token: token, in: appElement)
        }
        guard focus(
            application: application,
            windowElement: currentWindow,
            textElement: currentTextElement,
            requireFrontmostApplication: false
        ) else {
            return reportCloseFailure("fallback focus failed", token: token, in: appElement)
        }
        guard let closeButton = elementAttribute(kAXCloseButtonAttribute, from: currentWindow) else {
            return reportCloseFailure("close button unavailable", token: token, in: appElement)
        }
        let closeAction = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        guard closeAction == .success else {
            return reportCloseFailure(
                "close button action failed: \(closeAction.rawValue)",
                token: token,
                in: appElement
            )
        }
        if discardChangesSheetIfPresent(
            in: currentWindow,
            processIdentifier: application.processIdentifier,
            timeoutSeconds: 0.5
        ) {
            discardedSheetCount += 1
        }
        if waitForSurfaceToClose(
            token: token,
            in: appElement,
            timeoutSeconds: timeoutSeconds
        ) {
            return true
        }
        return reportCloseFailure(
            "close button left surface open; discardedSheets=\(discardedSheetCount)",
            token: token,
            in: appElement
        )
    }

    static func waitForTermination(
        _ application: NSRunningApplication,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if application.isTerminated {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return application.isTerminated
    }

    private static func discardChangesSheetIfPresent(
        in windowElement: AXUIElement,
        processIdentifier: pid_t,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            let hasSheet = elementArrayAttribute(kAXChildrenAttribute, from: windowElement)
                .contains {
                    stringAttribute(kAXRoleAttribute, from: $0) == kAXSheetRole as String
                }
            if hasSheet {
                // Standard macOS document sheets map Command-D to the non-saving close action.
                postKey(
                    keyCode: 2,
                    flags: .maskCommand,
                    processIdentifier: processIdentifier
                )
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        } while Date() < deadline
        return false
    }

    private static func reportCloseFailure(
        _ reason: String,
        token: String,
        in appElement: AXUIElement
    ) -> Bool {
        let details: String
        if let windowElement = surfaceWindow(token: token, in: appElement) {
            let titleMatchesToken = stringAttribute(kAXTitleAttribute, from: windowElement)?
                .localizedCaseInsensitiveContains(token) == true
            let documentMatchesToken = stringAttribute(kAXDocumentAttribute, from: windowElement)?
                .localizedCaseInsensitiveContains(token) == true
            let edited = boolAttribute(kAXEditedAttribute, from: windowElement)
                .map(String.init(describing:)) ?? "<nil>"
            let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: appElement)
            let isFocused = focusedWindow.map { CFEqual($0, windowElement) } ?? false
            var queue: [(AXUIElement, Int)] = [(windowElement, 0)]
            var index = 0
            var roleCounts: [String: Int] = [:]
            var buttonCount = 0
            var discardButtonCount = 0
            var traversalTruncated = false
            var depthLimitReached = false
            let traversalDeadline = Date().addingTimeInterval(0.25)
            while index < queue.count, index < 200, Date() < traversalDeadline {
                let (element, depth) = queue[index]
                index += 1
                let role = stringAttribute(kAXRoleAttribute, from: element) ?? "<nil>"
                roleCounts[role, default: 0] += 1
                if role == kAXButtonRole as String {
                    buttonCount += 1
                    let title = stringAttribute(kAXTitleAttribute, from: element) ?? ""
                    if ["don't save", "delete", "revert changes"].contains(title.lowercased()) {
                        discardButtonCount += 1
                    }
                }
                if depth < 6 {
                    let children = elementArrayAttribute(kAXChildrenAttribute, from: element)
                    let remainingCapacity = max(0, 200 - queue.count)
                    traversalTruncated = traversalTruncated || children.count > remainingCapacity
                    queue.append(contentsOf: children.prefix(remainingCapacity).map { ($0, depth + 1) })
                } else {
                    depthLimitReached = true
                }
            }
            let timeLimitReached = index < queue.count
            let roleSummary = roleCounts
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            details = "titleMatchesToken=\(titleMatchesToken) documentMatchesToken=\(documentMatchesToken) "
                + "edited=\(edited) focused=\(isFocused) roles=\(roleSummary) "
                + "buttons=\(buttonCount) discardButtons=\(discardButtonCount) "
                + "queueTruncated=\(traversalTruncated) depthLimitReached=\(depthLimitReached) "
                + "timeLimitReached=\(timeLimitReached)"
        } else {
            details = "surface=<absent>"
        }
        let message = "Runtime E2E close attempt failed: \(reason); token=\(token); \(details)\n"
        FileHandle.standardError.write(Data(message.utf8))
        return false
    }

    @discardableResult
    static func postKey(
        keyCode: UInt16,
        flags: CGEventFlags,
        processIdentifier: pid_t? = nil
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        if let processIdentifier {
            down.postToPid(processIdentifier)
            up.postToPid(processIdentifier)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, from: element),
              editableRoles.contains(role) else {
            return false
        }
        return boolAttribute(kAXEnabledAttribute, from: element) != false
    }

    private static func isUsableObservationFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= 16
            && frame.height >= 16
    }

    private static func editableScore(_ element: AXUIElement) -> Int {
        let role = stringAttribute(kAXRoleAttribute, from: element)
        var score = role == kAXTextAreaRole as String ? 20 : 10
        if identifyingText(from: element).localizedCaseInsensitiveContains("Roma Runtime E2E") {
            score += 100
        }
        return score
    }

    private static func identifyingText(from element: AXUIElement) -> String {
        [
            stringAttribute(kAXDescriptionAttribute, from: element),
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXIdentifierAttribute, from: element),
            stringAttribute(kAXHelpAttribute, from: element)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func waitForBaselineText(
        _ scenario: RuntimeTextScenario,
        targetKind: RuntimeTargetApp.Kind,
        in element: AXUIElement,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
                text(from: element),
                scenario: scenario,
                targetKind: targetKind
            ) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return RuntimeTargetIsolationPlan.matchesAccessibilityBaseline(
            text(from: element),
            scenario: scenario,
            targetKind: targetKind
        )
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
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private static func setSelectedTextRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(
                  element,
                  kAXSelectedTextRangeAttribute as CFString,
                  value
              ) == .success else {
            return false
        }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if sameRange(selectedTextRange(from: element), range) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return sameRange(selectedTextRange(from: element), range)
    }

    private static func waitForSelectedTextRange(
        _ range: CFRange,
        on element: AXUIElement,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if sameRange(selectedTextRange(from: element), range) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return sameRange(selectedTextRange(from: element), range)
    }

    private static func sameRange(_ lhs: CFRange?, _ rhs: CFRange?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.location == rhs.location && lhs.length == rhs.length
    }

    private static func surfaceExistsInWindows(token: String, in appElement: AXUIElement) -> Bool {
        surfaceWindow(token: token, in: appElement) != nil
    }

    private static func surfaceWindow(token: String, in appElement: AXUIElement) -> AXUIElement? {
        elementArrayAttribute(kAXWindowsAttribute, from: appElement).first { windowElement in
            stringAttribute(kAXTitleAttribute, from: windowElement)?
                .localizedCaseInsensitiveContains(token) == true
                || editableElement(in: windowElement, identifying: token) != nil
                || element(in: windowElement, identifying: token) != nil
        }
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        return value as? Bool
    }

    private static func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let values = value as? [AXUIElement] else {
            return []
        }
        return values
    }
}

enum RuntimeTargetControllerError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case applicationNotFound(String)
    case targetNotRunning(String)
    case launcherNotFound(String, String)
    case launchFailed(String, Int32)
    case targetSurfaceTimedOut(String)
    case couldNotPrepareTarget
    case renderObservationUnavailable(String)

    var description: String {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility is not granted to the runtime harness"
        case .applicationNotFound(let identifier):
            return "Target app is not installed: \(identifier)"
        case .targetNotRunning(let identifier):
            return "Target app closed after preflight and running-only policy forbids launching it: \(identifier)"
        case .launcherNotFound(let name, let path):
            return "Target app launcher is missing for \(name): \(path)"
        case .launchFailed(let name, let exitCode):
            return "Could not open the test resource in target app \(name) (open exit \(exitCode))"
        case .targetSurfaceTimedOut(let identifier):
            return "Target app did not expose the uniquely identified test surface: \(identifier)"
        case .couldNotPrepareTarget:
            return "Could not establish the requested target-text baseline and cursor"
        case .renderObservationUnavailable(let message):
            return "Could not establish rendered-text observation: \(message)"
        }
    }
}
