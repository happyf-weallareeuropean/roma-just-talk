import AppKit
import ApplicationServices
import SwiftUI
import XCTest
import VoiceInkCore
@testable import VoiceInk

// Host the production view; interact through a trusted public accessibility client.
// Only network completion and existing model files are controlled.
final class OnboardingRegionViewTests: XCTestCase {
    @MainActor func testLateTaiwanDraftBlocksCachedEnglishContinueWithoutPersistingIt() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let fixture = OnboardingTestWindow()
        defer { fixture.close() }
        try await fixture.waitForLookup()
        let continueButton = try await fixture.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        fixture.manager.refreshAllAvailableModels()
        fixture.manager.refreshAllAvailableModels()
        await fixture.region.respond("TW")
        try await fixture.waitForLabel(QwenModel().displayName)
        let suggestedContinueButton = try await fixture.continueButton()
        XCTAssertFalse(suggestedContinueButton.isAccessibilityEnabled())
        XCTAssertEqual(fixture.manager.currentTranscriptionModel?.name, fixture.englishName)
        XCTAssertNil(preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel))
        XCTAssertNil(preferences.persisted(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage))
        XCTAssertNil(VoiceInkLocalOnboardingModelPreference.choice())
        attach(fixture, name: "Taiwan draft with cached English")
    }

    @MainActor func testExplicitEnglishAccessibilityActionWinsBeforeTaiwanResponse() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let fixture = OnboardingTestWindow()
        defer { fixture.close() }
        try await fixture.waitForLookup()
        try await fixture.press(label: "English only")
        try await fixture.waitUntil { preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel) == fixture.englishName }
        await fixture.region.respond("TW")
        try await fixture.waitUntil { fixture.regionLookupFinished }
        let continueButton = try await fixture.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        XCTAssertEqual(fixture.manager.currentTranscriptionModel?.name, fixture.englishName)
        XCTAssertEqual(VoiceInkLocalOnboardingModelPreference.choice(), .englishOnly)
        try await fixture.waitForLabel(TranscriptionModelRegistry.defaultMacOSFluidAudioModel.displayName)
        attach(fixture, name: "Explicit English survives delayed Taiwan")
    }

    @MainActor func testAdvancedDisclosureRejectsPendingTaiwanSuggestion() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let fixture = OnboardingTestWindow()
        defer { fixture.close() }
        try await fixture.waitForLookup()
        try await fixture.press(identifier: "onboarding-model-advanced")
        try await fixture.waitForLabel(VoiceInkModelManagementPresentation.defaultModelTitle)
        await fixture.region.respond("TW")
        try await fixture.waitUntil { fixture.regionLookupFinished }
        XCTAssertEqual(fixture.manager.currentTranscriptionModel?.name, fixture.englishName)
        XCTAssertNil(preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel))
        XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(), "en")
        let continueButton = try await fixture.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        attach(fixture, name: "Advanced choice rejects delayed country")
    }

    @MainActor func testSkipUnmountsPendingLookupWithoutCommittingSuggestedModel() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let fixture = OnboardingTestWindow()
        defer { fixture.close() }
        try await fixture.waitForLookup()
        try await fixture.press(identifier: "onboarding-model-skip")
        try await fixture.waitUntil { fixture.didAdvance }
        XCTAssertEqual(VoiceInkMacOSOnboardingProgressStore.stage(), .tutorial)
        fixture.close(resumePendingLookup: false)
        await fixture.region.respond("TW")
        try await fixture.waitUntil { fixture.regionLookupFinished }
        XCTAssertNil(preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel))
        XCTAssertNil(VoiceInkLocalOnboardingModelPreference.choice())
    }

    @MainActor func testReopeningPreservesExplicitEnglishWithoutAnotherLookup() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let first = OnboardingTestWindow()
        defer { first.close() }
        try await first.waitForLookup()
        try await first.press(label: "English only")
        try await first.waitUntil { VoiceInkLocalOnboardingModelPreference.choice() == .englishOnly }
        await first.region.respond("TW")
        first.close()
        let reopened = OnboardingTestWindow()
        defer { reopened.close() }
        _ = try await reopened.continueButton()
        try await reopened.waitUntil { reopened.regionLookupFinished }
        let requests = await reopened.region.requestCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(reopened.manager.currentTranscriptionModel?.name, reopened.englishName)
        XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(), "en")
        let continueButton = try await reopened.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        attach(reopened, name: "Reopened explicit English")
    }

    @MainActor func testContinueConfirmsCachedEnglishAcrossOnboardingReset() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let first = OnboardingTestWindow()
        defer { first.close() }
        try await first.waitForLookup()
        let continueButton = try await first.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        try await first.press(identifier: "onboarding-model-continue")
        try await first.waitUntil { first.didAdvance }
        first.close(resumePendingLookup: false)
        await first.region.respond("TW")
        try await first.waitUntil { first.regionLookupFinished }
        XCTAssertEqual(preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel), first.englishName)
        XCTAssertEqual(VoiceInkLocalOnboardingModelPreference.choice(), .englishOnly)
        XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(), "en")
        XCTAssertNil(preferences.persisted(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage))

        // Settings' Reset onboarding action clears progress, preserving model choices.
        VoiceInkMacOSOnboardingProgressStore.reset()
        let reopened = OnboardingTestWindow()
        defer { reopened.close() }
        _ = try await reopened.continueButton()
        try await reopened.waitForLookupOrCompletion()
        await reopened.region.respond("TW")
        try await reopened.waitUntil { reopened.regionLookupFinished }
        let requests = await reopened.region.requestCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(reopened.manager.currentTranscriptionModel?.name, reopened.englishName)
        try await reopened.waitForLabel(TranscriptionModelRegistry.defaultMacOSFluidAudioModel.displayName)
        let reopenedContinue = try await reopened.continueButton()
        XCTAssertTrue(reopenedContinue.isAccessibilityEnabled())
        attach(reopened, name: "Continue preserves English after onboarding reset")
    }

    @MainActor private func attach(_ fixture: OnboardingTestWindow, name: String) {
        let tree = XCTAttachment(string: fixture.treeDescription())
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        guard let view = fixture.window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            image.name = name
            image.lifetime = .keepAlways
            add(image)
        }
    }
}

private actor DelayedOnboardingRegion {
    private var completion: CheckedContinuation<String?, Never>?
    private(set) var requestCount = 0
    func lookup() async -> String? {
        requestCount += 1
        return await withCheckedContinuation { completion = $0 }
    }
    func respond(_ country: String?) {
        completion?.resume(returning: country)
        completion = nil
    }
}

@MainActor private final class OnboardingTestWindow {
    let region = DelayedOnboardingRegion()
    let window: NSWindow
    let manager: TranscriptionModelManager
    let englishName = TranscriptionModelRegistry.defaultMacOSFluidAudioModel.name
    private let whisper: WhisperModelManager
    private let fluid: FluidAudioModelManager
    private let qwen: QwenModelManager
    private(set) var didAdvance = false
    private(set) var regionLookupFinished = false
    private var isClosed = false
    private var lastAXElements: [OnboardingTestAXElement] = []
    private let fixtureTitle = "Roma Onboarding AX Fixture \(ProcessInfo.processInfo.processIdentifier) \(UUID().uuidString)"
    private let previousActivationPolicy = NSApplication.shared.activationPolicy()

    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-view-\(UUID().uuidString)")
        whisper = WhisperModelManager(modelsDirectory: folder)
        fluid = FluidAudioModelManager(client: FluidAudioModelDownloadClient(
            modelsExist: { _ in true }, cacheDirectoryExists: { _ in true },
            validateCache: { _ in true }, downloadAndLoad: { _, _, _ in
                XCTFail("This interaction test must not download or load a model")
            }
        ))
        qwen = QwenModelManager(cacheDirectory: folder.appendingPathComponent("Qwen"))
        manager = TranscriptionModelManager(whisperModelManager: whisper, fluidAudioModelManager: fluid, qwenModelManager: qwen)
        manager.refreshAllAvailableModels()
        manager.loadCurrentTranscriptionModel()
        // Exercise a subsequent metadata refresh before the picker exists.
        manager.refreshAllAvailableModels()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 900),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = fixtureTitle
        window.isReleasedWhenClosed = false
        let region = region
        let view = OnboardingModelDownloadView(
            hasCompletedOnboarding: .constant(false),
            lookupCountry: { await region.lookup() },
            onRegionLookupFinished: { [weak self] in self?.regionLookupFinished = true },
            onAdvance: { [weak self] in self?.didAdvance = true }
        )
        .environmentObject(manager)
        .environmentObject(whisper)
        .environmentObject(fluid)
        .environmentObject(qwen)
        window.contentView = NSHostingView(rootView: view)
        WindowManager.shared.configureOnboardingPanel(window)
        window.title = fixtureTitle
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func close(resumePendingLookup: Bool = true) {
        guard !isClosed else { return }
        isClosed = true
        window.contentView = nil
        window.orderOut(nil)
        window.close()
        NSApplication.shared.setActivationPolicy(previousActivationPolicy)
        if resumePendingLookup { Task { await region.respond(nil) } }
    }

    // Yield MainActor while the trusted client requests this fixture’s AX tree.
    func queryExternalAccessibility(mode: String = "query", match: String? = nil, attemptsRemaining: Int = 3) async throws {
        try await waitUntil { self.window.isKeyWindow && NSApplication.shared.isActive }
        let executable = "/tmp/roma-onboarding-diagnostic/ExternalAXProbe"
        let process = Process()
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-onboarding-external-ax-\(ProcessInfo.processInfo.processIdentifier).json")
        let errorURL = reportURL.appendingPathExtension("stderr")
        FileManager.default.createFile(atPath: reportURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: reportURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), window.title, mode] + (match.map { [$0] } ?? [])
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if process.isRunning {
            process.terminate()
            XCTFail("External AX helper exceeded 12 seconds; report: \(reportURL.path)")
            throw Failure.missing("External AX helper timeout")
        }
        let report = (try? String(contentsOf: reportURL, encoding: .utf8)) ?? "missing report"
        let stderr = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        print("ROMA_EXTERNAL_AX_REPORT: \(report)\n\(stderr)")
        XCTContext.runActivity(named: "External AX probe") { activity in
            let attachment = XCTAttachment(string: report + "\n" + stderr)
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        // SwiftUI can replace a node during animation. Retry the whole snapshot,
        // never an already executed press, and still require a complete final receipt.
        if attemptsRemaining > 1,
           let data = report.data(using: .utf8),
           let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           receipt["queryIncomplete"] as? Bool == true,
           receipt["actionError"] as? Int != 0,
           let calls = receipt["calls"] as? [[String: Any]],
           calls.contains(where: { ($0["errorCode"] as? Int) == Int(AXError.cannotComplete.rawValue) }),
           process.terminationStatus == 0 || process.terminationStatus == 75 {
            try await Task.sleep(for: .milliseconds(100))
            try await queryExternalAccessibility(mode: mode, match: match, attemptsRemaining: attemptsRemaining - 1)
            return
        }
        guard process.terminationStatus == 0 else {
            XCTFail("External AX helper failed with \(process.terminationStatus)")
            throw Failure.missing("External AX helper failure")
        }
        guard let data = report.data(using: .utf8),
              let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              receipt["trusted"] as? Bool == true,
              receipt["activeBefore"] as? Bool == true,
              receipt["activeAfter"] as? Bool == true,
              receipt["hostPID"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),
              receipt["parentPID"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),
              receipt["deadlineExceeded"] as? Bool == false,
              receipt["traversalBounded"] as? Bool == false,
              receipt["queryIncomplete"] as? Bool == false,
              let windows = receipt["fixtureWindows"] as? [[String: Any]],
              windows.count == 1,
              windows[0]["AXTitle"] as? String == window.title else {
            XCTFail("External AX probe did not verify this trusted fixture window")
            throw Failure.missing("External AX readiness failed")
        }
        if mode != "query" {
            guard receipt["actionError"] as? Int == 0,
                  receipt["actionMatchCount"] as? Int == 1 else {
                XCTFail("External AX action did not target one actionable control successfully")
                throw Failure.missing("External AX press failed")
            }
        }
        lastAXElements = []
        func visit(_ node: [String: Any]) {
            lastAXElements.append(OnboardingTestAXElement(node: node))
            for child in node["children"] as? [[String: Any]] ?? [] { visit(child) }
        }
        visit(windows[0])
    }

    func contains(label: String) async throws -> Bool {
        try await queryExternalAccessibility()
        return lastAXElements.contains { $0.label == label }
    }

    func press(label: String) async throws {
        try await queryExternalAccessibility(mode: "press-label", match: label)
    }

    func press(identifier: String) async throws {
        try await queryExternalAccessibility(mode: "press-id", match: identifier)
    }

    func continueButton() async throws -> OnboardingTestAXElement {
        try await queryExternalAccessibility()
        guard let button = lastAXElements.first(where: { $0.identifier == "onboarding-model-continue" }) else {
            recordFailure("Continue button missing from the trusted accessibility tree")
            throw Failure.missing("Continue button missing")
        }
        guard button.enabled != nil else {
            recordFailure("Continue enabled state missing from the accessibility receipt")
            throw Failure.missing("Continue enabled state unavailable")
        }
        return button
    }

    func waitForLookup() async throws {
        _ = try await continueButton()
        for _ in 0..<100 {
            if await region.requestCount == 1 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        recordFailure("Production view did not start its injected lookup")
        throw Failure.missing("Production view did not start its injected lookup")
    }

    func waitForLookupOrCompletion() async throws {
        for _ in 0..<100 {
            let requests = await region.requestCount
            if regionLookupFinished || requests > 0 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.missing("Lookup neither started nor completed")
    }

    func waitForLabel(_ label: String) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        repeat {
            if try await contains(label: label) { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ProcessInfo.processInfo.systemUptime < deadline
        recordFailure("Accessibility label did not appear: \(label)")
        throw Failure.missing("Accessibility label missing: \(label)")
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        recordFailure("UI condition timed out")
        throw Failure.missing("UI condition timed out\n\(treeDescription())")
    }

    private func recordFailure(_ message: String) {
        let root = window.contentView
        let children = root?.accessibilityChildren() ?? []
        let childContracts = children.map { "\(type(of: $0)): NSObject=\($0 is NSObject), NSAccessibilityProtocol=\($0 is any NSAccessibilityProtocol)" }
        let navigation = root?.accessibilityChildrenInNavigationOrder() ?? []
        let windowChildren = window.accessibilityChildren() ?? []
        let rawTree = "root=\(String(describing: root)) rawChildren=\(childContracts) navigation=\(navigation.map { String(describing: type(of: $0)) }) windowChildren=\(windowChildren.map { String(describing: type(of: $0)) }) visible=\(window.isVisible) key=\(window.isKeyWindow) active=\(NSApplication.shared.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") frontmostPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) policy=\(NSApplication.shared.activationPolicy().rawValue) screens=\(NSScreen.screens.count)"
        let details = "\(message)\n\(rawTree)\n\(treeDescription())"
        print("ROMA_ONBOARDING_TEST_FAILURE: \(details)")
        XCTFail(details)
        XCTContext.runActivity(named: message) { activity in
            let tree = XCTAttachment(string: details)
            tree.lifetime = .keepAlways
            activity.add(tree)
            if let root, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    image.lifetime = .keepAlways
                    activity.add(image)
                }
            }
        }
    }

    func treeDescription() -> String {
        lastAXElements.map { "role=\($0.role) id=\($0.identifier) label=\($0.label) value=\($0.value) enabled=\($0.isAccessibilityEnabled())" }.joined(separator: "\n")
    }

    private enum Failure: Error { case missing(String) }
}

private struct OnboardingTestAXElement {
    let role: String
    let identifier: String
    let label: String
    let value: String
    let enabled: Bool?

    init(node: [String: Any]) {
        role = node["AXRole"] as? String ?? ""
        identifier = node["AXIdentifier"] as? String ?? ""
        value = node["AXValue"] as? String ?? ""
        label = [node["AXDescription"], node["AXTitle"], node["AXValue"]]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
        enabled = node["AXEnabled"] as? Bool
    }

    func isAccessibilityEnabled() -> Bool { enabled == true }
}

@MainActor private final class OnboardingTestPreferences {
    private let defaults = UserDefaults.standard
    private let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    private let keys = [VoiceInkUserDefaultsKey.currentTranscriptionModel,
                        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage,
                        "macOSOnboardingLocalModelChoice", "macOSOnboardingStage", "macOSOnboardingPermissionKind"]
    private var previous: [String: Any] = [:]
    private var registration: [String: Any] = [:]

    init() {
        previous = defaults.persistentDomain(forName: domain) ?? [:]
        registration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.register(defaults: [VoiceInkUserDefaultsKey.currentTranscriptionModel: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
                                    VoiceInkUserDefaultsKey.selectedTranscriptionLanguage: "en"])
    }
    func persisted(_ key: String) -> String? { defaults.persistentDomain(forName: domain)?[key] as? String }
    func restore() {
        for key in keys {
            if let value = previous[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.setVolatileDomain(registration, forName: UserDefaults.registrationDomain)
    }
}
