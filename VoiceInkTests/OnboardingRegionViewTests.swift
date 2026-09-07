import AppKit
import SwiftUI
import XCTest
import VoiceInkCore
@testable import VoiceInk

// Host the production SwiftUI view and use its accessibility actions. Only network
// completion and existing model files are controlled; no production preference overrides.
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
        try fixture.press(label: "English only")
        try await fixture.waitUntil { preferences.persisted(VoiceInkUserDefaultsKey.currentTranscriptionModel) == fixture.englishName }
        await fixture.region.respond("TW")
        try await fixture.waitUntil { fixture.regionLookupFinished }
        let continueButton = try await fixture.continueButton()
        XCTAssertTrue(continueButton.isAccessibilityEnabled())
        XCTAssertEqual(fixture.manager.currentTranscriptionModel?.name, fixture.englishName)
        XCTAssertEqual(VoiceInkLocalOnboardingModelPreference.choice(), .englishOnly)
        XCTAssertFalse(fixture.contains(label: QwenModel().displayName))
        attach(fixture, name: "Explicit English survives delayed Taiwan")
    }

    @MainActor func testAdvancedDisclosureRejectsPendingTaiwanSuggestion() async throws {
        let preferences = OnboardingTestPreferences()
        defer { preferences.restore() }
        let fixture = OnboardingTestWindow()
        defer { fixture.close() }
        try await fixture.waitForLookup()
        try fixture.press(label: "Other models and language settings")
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
        try fixture.press(label: VoiceInkMacOSOnboardingPresentation.modelDownload.skipButtonTitle)
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
        try first.press(label: "English only")
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
        window.isReleasedWhenClosed = false
        let region = region
        let view = OnboardingModelDownloadView(
            hasCompletedOnboarding: .constant(false),
            lookupCountry: { await region.lookup() },
            onRegionLookupFinished: { [weak self] in self?.regionLookupFinished = true },
            onAdvance: { [weak self] in self?.didAdvance = true }
        )
        .environmentObject(manager)
        .environmentObject(fluid)
        .environmentObject(qwen)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func close(resumePendingLookup: Bool = true) {
        guard !isClosed else { return }
        isClosed = true
        window.contentView = nil
        window.orderOut(nil)
        window.close()
        if resumePendingLookup { Task { await region.respond(nil) } }
    }

    func elements() -> [any NSAccessibilityProtocol] {
        var result: [any NSAccessibilityProtocol] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any) {
            guard let element = object as? any NSAccessibilityProtocol,
                  seen.insert(ObjectIdentifier(element as AnyObject)).inserted else { return }
            result.append(element)
            for child in element.accessibilityChildren() ?? [] { visit(child) }
        }
        if let view = window.contentView { visit(view) }
        return result
    }

    func contains(label: String) -> Bool { elements().contains { $0.accessibilityLabel() == label } }

    func press(label: String) throws {
        let matches = elements().filter { $0.accessibilityLabel() == label }
        guard matches.contains(where: { $0.accessibilityPerformPress() }) else {
            throw Failure.missing("No actionable element: \(label)\n\(treeDescription())")
        }
    }

    func continueButton() async throws -> any NSAccessibilityProtocol {
        try await waitUntil { self.elements().contains { $0.accessibilityIdentifier() == "onboarding-model-continue" } }
        return elements().first { $0.accessibilityIdentifier() == "onboarding-model-continue" }!
    }

    func waitForLookup() async throws {
        _ = try await continueButton()
        for _ in 0..<100 {
            if await region.requestCount == 1 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.missing("Production view did not start its injected lookup")
    }

    func waitForLabel(_ label: String) async throws { try await waitUntil { self.contains(label: label) } }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            window.contentView?.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.missing("UI condition timed out\n\(treeDescription())")
    }

    func treeDescription() -> String {
        elements().map { "role=\(String(describing: $0.accessibilityRole())) id=\($0.accessibilityIdentifier() ?? "") label=\($0.accessibilityLabel() ?? "") value=\(String(describing: $0.accessibilityValue())) enabled=\($0.isAccessibilityEnabled())" }.joined(separator: "\n")
    }

    private enum Failure: Error { case missing(String) }
}

@MainActor private final class OnboardingTestPreferences {
    private let defaults = UserDefaults.standard
    private let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    private let keys = [VoiceInkUserDefaultsKey.currentTranscriptionModel,
                        VoiceInkUserDefaultsKey.selectedTranscriptionLanguage,
                        "macOSOnboardingLocalModelChoice", "macOSOnboardingStage"]
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
