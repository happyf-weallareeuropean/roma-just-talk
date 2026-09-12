import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import AppIntents
import FluidAudio
import VoiceInkCore

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool

    @StateObject private var engine: VoiceInkEngine
    @StateObject private var whisperModelManager: WhisperModelManager
    @StateObject private var fluidAudioModelManager: FluidAudioModelManager
    @StateObject private var qwenModelManager: QwenModelManager
    @StateObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var recorderUIManager: RecorderUIManager
    @StateObject private var recordingShortcutManager: RecordingShortcutManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var launchAtLoginController = LaunchAtLoginController()
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage(VoiceInkUserDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(VoiceInkAnnouncementPreference.isEnabledKey) private var enableAnnouncements = VoiceInkAnnouncementPreference.defaultIsEnabled
    @AppStorage(VoiceInkMenuBarPreference.showMenuBarIconKey) private var showMenuBarIcon = VoiceInkMenuBarPreference.defaultShowMenuBarIcon

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()

        VoiceInkPowerModePreference.initializeUIFlagIfNeeded(
            hasEnabledConfigurations: PowerModeManager.shared.configurations.hasEnabledPowerModeConfigurations
        )

        let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "Initialization")
        // Keep existing model order stable; append new models after synced entities.
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            SessionMetric.self
        ])
        var initializationFailed = false
        let resolvedContainer: ModelContainer

        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            resolvedContainer = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            resolvedContainer = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            DispatchQueue.main.async {
                let presentation = VoiceInkAppIdentity.storageFallbackWarningPresentation
                let alert = NSAlert()
                alert.messageText = presentation.title
                alert.informativeText = presentation.message
                alert.alertStyle = .warning
                alert.addButton(withTitle: presentation.buttonTitle)
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("\(VoiceInkStorageStartupDiagnostics.modelContainerInitializationFailedMessage, privacy: .public)")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            resolvedContainer = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                preconditionFailure(VoiceInkStorageStartupDiagnostics.modelContainerUnavailablePreconditionMessage)
            }()
        }

        container = resolvedContainer
        containerInitializationFailed = initializationFailed

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: resolvedContainer.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)

        // 1. Create modelsDirectory URL
        let modelsDirectory = VoiceInkMacOSStorageDirectories.modelsDirectory

        // 2. Create model managers
        let whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        let fluidAudioModelManager = FluidAudioModelManager()
        let qwenModelManager = QwenModelManager(cacheDirectory: modelsDirectory.appendingPathComponent("Qwen", isDirectory: true))
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager,
            qwenModelManager: qwenModelManager
        )

        // 3. Create UI manager
        let recorderUIManager = RecorderUIManager()

        // 4. Create engine
        let engine = VoiceInkEngine(
            modelContext: resolvedContainer.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            qwenRuntimeResult: qwenModelManager.runtimeResult,
            enhancementService: enhancementService
        )

        // 5. Configure circular deps
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
        engine.recorderUIManager = recorderUIManager

        // 6. Initialize model state
        // Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
        VoiceInkStreamingKeysMigration.run()
        whisperModelManager.createModelsDirectoryIfNeeded()
        whisperModelManager.loadAvailableModels()
        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()
        // A fresh install chooses its local model in onboarding before downloading it.
        if VoiceInkLocalOnboardingModelPreference.shouldDownloadModelAtStartup(
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding),
            persistedModelName: VoiceInkLocalOnboardingModelPreference.persistedModelName()
        ), let fluidAudioModel = transcriptionModelManager.currentTranscriptionModel as? FluidAudioModel {
            Task {
                await fluidAudioModelManager.downloadFluidAudioModel(fluidAudioModel)
            }
        }

        _whisperModelManager = StateObject(wrappedValue: whisperModelManager)
        _fluidAudioModelManager = StateObject(wrappedValue: fluidAudioModelManager)
        _qwenModelManager = StateObject(wrappedValue: qwenModelManager)
        Task { await qwenModelManager.refresh() }
        _transcriptionModelManager = StateObject(wrappedValue: transcriptionModelManager)
        _recorderUIManager = StateObject(wrappedValue: recorderUIManager)
        _engine = StateObject(wrappedValue: engine)

        // 7. Create other services that depend on engine
        let recordingShortcutManager = RecordingShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        _recordingShortcutManager = StateObject(wrappedValue: recordingShortcutManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: resolvedContainer, engine: engine)

        _activeWindowService = StateObject(wrappedValue: ActiveWindowService.shared)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: resolvedContainer.mainContext,
            qwenRuntimeResult: qwenModelManager.runtimeResult,
            serviceRegistry: engine.serviceRegistry
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
            await engine.recorder.startPreRollBuffering()
            DictionaryService.warmWordReplacementCache(using: resolvedContainer.mainContext)
        }

        AppShortcuts.updateAppShortcutParameters()

        let migrationTask = SessionMetricMigrationService.shared.runIfNeeded(modelContainer: resolvedContainer)
        let mainContext = resolvedContainer.mainContext
        Task {
            await migrationTask?.value
            TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: mainContext)
        }
    }

    // MARK: - Container Creation Helpers

    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Create app-specific Application Support directory URL
            let appSupportURL = VoiceInkMacOSStorageDirectories.appSupportDirectory

            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Define storage locations
            let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
            let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")
            let statsStoreURL = appSupportURL.appendingPathComponent("stats.store")

            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                url: defaultStoreURL,
                cloudKitDatabase: .none
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            #if LOCAL_BUILD
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
            #else
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private(VoiceInkAppIdentity.iCloudContainerIdentifier)
            #endif
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: dictionaryCloudKit
            )

            // Recorder session metrics configuration
            let statsSchema = Schema([SessionMetric.self])
            let statsConfig = ModelConfiguration(
                "stats",
                schema: statsSchema,
                url: statsStoreURL,
                cloudKitDatabase: .none
            )

            // Initialize container
            return try ModelContainer(
                for: schema,
                configurations: transcriptConfig, dictionaryConfig, statsConfig
            )
        } catch {
            logger.error("❌ Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Transcript configuration
            let transcriptSchema = Schema([Transcription.self])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                isStoredInMemoryOnly: true
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                isStoredInMemoryOnly: true
            )

            let statsSchema = Schema([SessionMetric.self])
            let statsConfig = ModelConfiguration(
                "stats",
                schema: statsSchema,
                isStoredInMemoryOnly: true
            )

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig, statsConfig)
        } catch {
            logger.error("❌ Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup(VoiceInkAppIdentity.compactDisplayName, id: "main") {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(engine)
                    .environmentObject(whisperModelManager)
                    .environmentObject(fluidAudioModelManager)
                    .environmentObject(qwenModelManager)
                    .environmentObject(transcriptionModelManager)
                    .environmentObject(recorderUIManager)
                    .environmentObject(recordingShortcutManager)
                    .environmentObject(updaterViewModel)
                    .environmentObject(menuBarManager)
                    .environmentObject(launchAtLoginController)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .modelContainer(container)
                    .onAppear {
                        // Check if container initialization failed
                        if containerInitializationFailed {
                            let presentation = VoiceInkAppIdentity.storageFailurePresentation
                            let alert = NSAlert()
                            alert.messageText = presentation.title
                            alert.informativeText = presentation.message
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: presentation.buttonTitle)
                            alert.runModal()

                            NSApplication.shared.terminate(nil)
                            return
                        }

                        if enableAnnouncements {
                            AnnouncementsService.shared.start()
                        }

                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !VoiceInkTranscriptionAutoCleanupPreference.isEnabled() {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }

                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: .transcribeAudio)
                            )
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(
                                    name: .openFileForTranscription,
                                    object: nil,
                                    userInfo: VoiceInkMacOSFileTranscriptionRequest.userInfo(url: pendingURL)
                                )
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                    }
                    .background(WindowAccessor(configurationID: VoiceInkMacOSWindowIdentity.mainIdentifierRawValue) { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        AnnouncementsService.shared.stop()
                        whisperModelManager.unloadModel()

                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(recordingShortcutManager)
                    .environmentObject(engine)
                    .environmentObject(whisperModelManager)
                    .environmentObject(fluidAudioModelManager)
                    .environmentObject(qwenModelManager)
                    .environmentObject(transcriptionModelManager)
                    .environmentObject(recorderUIManager)
                    .environmentObject(aiService)
                    .environmentObject(enhancementService)
                    .background(WindowAccessor(configurationID: VoiceInkMacOSWindowIdentity.onboardingIdentifierRawValue) { window in
                        WindowManager.shared.configureOnboardingPanel(window)
                    })
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 950, height: 730)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(qwenModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(recordingShortcutManager)
                .environmentObject(menuBarManager)
                .environmentObject(launchAtLoginController)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)

            Image(nsImage: image)
                .background(MainWindowRequestHandler())
        }
        .menuBarExtraStyle(.menu)

        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Dock Icon") {
                menuBarManager.showDockIcon.toggle()
            }
        }
        #endif
    }
}

private struct MainWindowRequestHandler: View {
    @Environment(\.openWindow) private var openWindow
    private static let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "MainWindowRequestHandler")

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindowRequested)) { notification in
                let destination = VoiceInkMacOSNavigationRequest.destination(from: notification)
                    ?? VoiceInkMacOSNavigationRequest.defaultDestination.rawValue
                openMainWindowAndNavigate(to: destination)
            }
    }

    private func openMainWindowAndNavigate(to destination: String) {
        Self.logger.notice("openMainWindowAndNavigate: requested destination=\(destination, privacy: .public)")
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")

        Self.focusAndNavigate(to: destination, attempt: 1)
    }

    private static func focusAndNavigate(to destination: String, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if WindowManager.shared.showMainWindow() == nil, attempt < 6 {
                logger.notice("focusAndNavigate: main window not ready, retry \(attempt, privacy: .public)")
                focusAndNavigate(to: destination, attempt: attempt + 1)
                return
            }

            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: VoiceInkMacOSNavigationRequest.userInfo(destination: destination)
            )
            logger.notice("focusAndNavigate: navigation notification posted for \(destination, privacy: .public)")
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        if updaterViewModel.status.canRelaunch {
            Button(updaterViewModel.status.title, action: updaterViewModel.relaunchToUpdate)
        } else {
            Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
                .disabled(!updaterViewModel.canCheckForUpdates)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configurationID: String
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> AccessView {
        let view = AccessView()
        view.update(configurationID: configurationID, callback: callback)
        return view
    }

    func updateNSView(_ view: AccessView, context: Context) {
        view.update(configurationID: configurationID, callback: callback)
    }

    final class AccessView: NSView {
        private var configurationID = ""
        private var callback: ((NSWindow) -> Void)?
        private weak var configuredWindow: NSWindow?
        private var appliedConfigurationID: String?
        private var configurationPending = false

        func update(configurationID: String, callback: @escaping (NSWindow) -> Void) {
            self.configurationID = configurationID
            self.callback = callback
            scheduleConfiguration()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        private func scheduleConfiguration() {
            guard !configurationPending else { return }
            configurationPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configurationPending = false
                guard let window = self.window,
                      self.configuredWindow !== window || self.appliedConfigurationID != self.configurationID else { return }
                // SwiftUI can reuse this NSView when switching between main and setup.
                self.configuredWindow = window
                self.appliedConfigurationID = self.configurationID
                self.callback?(window)
            }
        }
    }
}
