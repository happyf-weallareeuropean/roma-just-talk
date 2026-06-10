import Foundation
import AppKit
import os

enum SpecialShortcutKeyDownBehavior: String, CaseIterable {
    case startRecording = "startRecording"
    case preloadOnly = "preloadOnly"

    var displayName: String {
        switch self {
        case .startRecording: return "Start Recording"
        case .preloadOnly: return "Preload Only"
        }
    }
}

struct SpecialShortcutOptions: Equatable {
    var keyDownBehavior: SpecialShortcutKeyDownBehavior = .startRecording
    var allowsKeyDownOnlyTrigger = true
    var pasteLastTranscriptOnEmptyTap = true
}

enum SpecialShortcutSettings {
    static let keyDownBehaviorKey = "specialShortcutKeyDownBehavior"
    static let allowsKeyDownOnlyTriggerKey = "specialShortcutAllowsKeyDownOnlyTrigger"
    static let pasteLastTranscriptOnEmptyTapKey = "specialShortcutPasteLastTranscriptOnEmptyTap"
}

@MainActor
class RecordingShortcutManager: ObservableObject {
    @Published var primaryRecordingShortcut: ShortcutSelection {
        didSet {
            UserDefaults.standard.set(primaryRecordingShortcut.rawValue, forKey: "primaryRecordingShortcut")
            refreshShortcutMonitoring()
        }
    }
    @Published var secondaryRecordingShortcut: ShortcutSelection {
        didSet {
            if secondaryRecordingShortcut == .none {
                ShortcutStore.setShortcut(nil, for: .secondaryRecording)
            }
            UserDefaults.standard.set(secondaryRecordingShortcut.rawValue, forKey: "secondaryRecordingShortcut")
            refreshShortcutMonitoring()
        }
    }
    @Published var primaryRecordingShortcutMode: Mode {
        didSet {
            UserDefaults.standard.set(primaryRecordingShortcutMode.rawValue, forKey: "primaryRecordingShortcutMode")
            primaryRecordingShortcutModeSource.primaryMode = primaryRecordingShortcutMode
            refreshShortcutMonitoring()
            NotificationCenter.default.post(name: .powerModeShortcutAvailabilityDidChange, object: nil)
        }
    }
    @Published var secondaryRecordingShortcutMode: Mode {
        didSet {
            UserDefaults.standard.set(secondaryRecordingShortcutMode.rawValue, forKey: "secondaryRecordingShortcutMode")
            refreshShortcutMonitoring()
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMiddleClickToggleEnabled, forKey: "isMiddleClickToggleEnabled")
            refreshShortcutMonitoring()
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            UserDefaults.standard.set(middleClickActivationDelay, forKey: "middleClickActivationDelay")
        }
    }
    @Published var specialShortcutKeyDownBehavior: SpecialShortcutKeyDownBehavior {
        didSet {
            UserDefaults.standard.set(specialShortcutKeyDownBehavior.rawValue, forKey: SpecialShortcutSettings.keyDownBehaviorKey)
            specialOptionsSource.options = specialOptions
        }
    }
    @Published var specialShortcutAllowsKeyDownOnlyTrigger: Bool {
        didSet {
            UserDefaults.standard.set(specialShortcutAllowsKeyDownOnlyTrigger, forKey: SpecialShortcutSettings.allowsKeyDownOnlyTriggerKey)
            specialOptionsSource.options = specialOptions
        }
    }
    @Published var specialShortcutPasteLastTranscriptOnEmptyTap: Bool {
        didSet {
            UserDefaults.standard.set(specialShortcutPasteLastTranscriptOnEmptyTap, forKey: SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey)
            specialOptionsSource.options = specialOptions
        }
    }
    
    private var engine: VoiceInkEngine
    private var recorderUIManager: RecorderUIManager
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    private let powerModeShortcutManager: PowerModeShortcutManager
    private let shortcutMonitor = ShortcutMonitor()
    private var shortcutChangeObserver: NSObjectProtocol?
    private var permissionChangeObserver: NSObjectProtocol?
    private let shortcutModeHandler: RecordingShortcutModeHandler
    private let primaryRecordingShortcutModeSource: RecordingShortcutModeSource
    private let specialOptionsSource: RecordingShortcutSpecialOptionsSource
    private var hasShownInputMonitoringPermissionNotification = false
    private var hasShownAccessibilityPermissionNotification = false
    private var hasShownShortcutMonitorFailureNotification = false

    // MARK: - Helper Properties
    private var canHandleShortcutAction: Bool {
        Self.canHandleShortcutAction(for: engine.recordingState)
    }
    
    // Middle-click event monitoring
    private var middleClickMonitors: [Any?] = []
    private var middleClickTask: Task<Void, Never>?

    enum Mode: String, CaseIterable {
        case special = "special"
        case toggle = "toggle"
        case pushToTalk = "pushToTalk"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .special: return "Special"
            case .toggle: return "Toggle"
            case .pushToTalk: return "Push to Talk"
            case .hybrid: return "Hybrid"
            }
        }
    }

    enum ShortcutSelection: String, CaseIterable {
        case none = "none"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .custom: return "Custom"
            }
        }
    }

    private static func canHandleShortcutAction(for recordingState: RecordingState) -> Bool {
        recordingState != .transcribing &&
        recordingState != .enhancing &&
        recordingState != .busy
    }

    init(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) {
        ShortcutMigration.migrateLegacyShortcutsIfNeeded()

        self.primaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .primaryRecording,
            allowsNone: false
        )
        self.secondaryRecordingShortcut = ShortcutMigration.migrateShortcutSelection(
            action: .secondaryRecording,
            allowsNone: true
        )

        let primaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .primaryRecording
        )
        self.primaryRecordingShortcutMode = primaryRecordingShortcutMode
        self.secondaryRecordingShortcutMode = ShortcutMigration.migrateShortcutMode(
            for: .secondaryRecording
        )

        self.isMiddleClickToggleEnabled = UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled")
        self.middleClickActivationDelay = UserDefaults.standard.integer(forKey: "middleClickActivationDelay")
        let specialKeyDownBehaviorRawValue = UserDefaults.standard.string(forKey: SpecialShortcutSettings.keyDownBehaviorKey)
        let specialKeyDownBehavior = specialKeyDownBehaviorRawValue
            .flatMap(SpecialShortcutKeyDownBehavior.init(rawValue:)) ?? .startRecording
        let specialAllowsKeyDownOnlyTrigger = UserDefaults.standard.bool(forKey: SpecialShortcutSettings.allowsKeyDownOnlyTriggerKey)
        let specialPasteLastTranscriptOnEmptyTap = UserDefaults.standard.bool(forKey: SpecialShortcutSettings.pasteLastTranscriptOnEmptyTapKey)
        self.specialShortcutKeyDownBehavior = specialKeyDownBehavior
        self.specialShortcutAllowsKeyDownOnlyTrigger = specialAllowsKeyDownOnlyTrigger
        self.specialShortcutPasteLastTranscriptOnEmptyTap = specialPasteLastTranscriptOnEmptyTap

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "RecordingShortcutManager")
        let shortcutModeHandler = RecordingShortcutModeHandler(
            logger: logger,
            canHandleShortcutAction: {
                Self.canHandleShortcutAction(for: engine.recordingState)
            },
            isRecorderVisible: {
                recorderUIManager.isActiveForRecordingShortcut(recordingState: engine.recordingState)
            },
            recordingState: {
                engine.recordingState
            },
            toggleMiniRecorder: { powerModeId in
                await recorderUIManager.toggleMiniRecorder(powerModeId: powerModeId)
            },
            cancelRecording: {
                await recorderUIManager.cancelRecording()
            },
            discardRecording: {
                await recorderUIManager.cancelRecording(saveCanceledTranscription: false)
            },
            pasteLastTranscription: {
                LastTranscriptionService.pasteLastTranscription(from: engine.modelContext)
            }
        )

        let primaryRecordingShortcutModeSource = RecordingShortcutModeSource(
            primaryMode: primaryRecordingShortcutMode
        )
        let specialOptionsSource = RecordingShortcutSpecialOptionsSource(
            options: SpecialShortcutOptions(
                keyDownBehavior: specialKeyDownBehavior,
                allowsKeyDownOnlyTrigger: specialAllowsKeyDownOnlyTrigger,
                pasteLastTranscriptOnEmptyTap: specialPasteLastTranscriptOnEmptyTap
            )
        )

        self.engine = engine
        self.recorderUIManager = recorderUIManager
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(engine: engine, recorderUIManager: recorderUIManager)
        self.shortcutModeHandler = shortcutModeHandler
        self.primaryRecordingShortcutModeSource = primaryRecordingShortcutModeSource
        self.specialOptionsSource = specialOptionsSource
        self.powerModeShortcutManager = PowerModeShortcutManager(
            modeProvider: {
                primaryRecordingShortcutModeSource.primaryMode
            },
            specialOptionsProvider: {
                specialOptionsSource.options
            },
            shortcutModeHandler: shortcutModeHandler
        )

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshShortcutMonitoring()
            }
        }

        permissionChangeObserver = NotificationCenter.default.addObserver(
            forName: .appPermissionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePermissionChange()
            }
        }

        Task { @MainActor in
            PermissionRefreshCenter.shared.startObservingApplicationActivation()
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.refreshShortcutMonitoring()
        }
    }

    private func handlePermissionChange() {
        if ShortcutMonitor.preflightListenEventAccess() {
            hasShownInputMonitoringPermissionNotification = false
        }

        if ShortcutMonitor.preflightAccessibilityAccess() {
            hasShownAccessibilityPermissionNotification = false
        }

        hasShownShortcutMonitorFailureNotification = false
        refreshShortcutMonitoring()
    }
    
    private func refreshShortcutMonitoring() {
        removeAllMonitoring()
        
        refreshShortcutMonitor()
        setupMiddleClickMonitoring()
    }
    
    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else { return }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delay = UInt64(self.middleClickActivationDelay) * 1_000_000 // ms to ns
                    try await Task.sleep(nanoseconds: delay)
                    
                    guard self.isMiddleClickToggleEnabled, !Task.isCancelled else { return }
                    
                    Task { @MainActor in
                        guard self.canHandleShortcutAction else { return }
                        await self.recorderUIManager.toggleMiniRecorder()
                    }
                } catch {
                    // Cancelled
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
    }
    
    private func refreshShortcutMonitor() {
        let primaryShortcut = primaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .primaryRecording) : nil
        let secondaryShortcut = secondaryRecordingShortcut == .custom ? ShortcutStore.shortcut(for: .secondaryRecording) : nil
        var shortcuts = ShortcutStore.shortcuts(for: ShortcutAction.globalUtilityActions)
        var interruptibleRecordingActions = Set<ShortcutAction>()

        if let primaryShortcut {
            shortcuts[.primaryRecording] = primaryShortcut
            if primaryRecordingShortcutMode != .special {
                interruptibleRecordingActions.insert(.primaryRecording)
            }
        }

        if let secondaryShortcut {
            shortcuts[.secondaryRecording] = secondaryShortcut
            if secondaryRecordingShortcutMode != .special {
                interruptibleRecordingActions.insert(.secondaryRecording)
            }
        }

        let tracksKeyUpEvidence = shortcuts.keys.contains { recordingMode(for: $0) == .special }

        let isMonitoring = shortcutMonitor.start(
            shortcuts: shortcuts,
            interruptibleActions: interruptibleRecordingActions,
            tracksKeyUpEvidence: tracksKeyUpEvidence,
            onKeyDown: { [weak self] action, eventTime in
                Task { @MainActor in
                    guard let self else { return }
                    guard let mode = self.recordingMode(for: action) else { return }
                    await self.shortcutModeHandler.handleKeyDown(
                        action: action,
                        eventTime: eventTime,
                        mode: mode,
                        specialOptions: self.specialOptions
                    )
                }
            },
            onKeyUp: { [weak self] action, eventTime, context in
                Task { @MainActor in
                    guard let self else { return }
                    if let mode = self.recordingMode(for: action) {
                        await self.shortcutModeHandler.handleKeyUp(
                            action: action,
                            eventTime: eventTime,
                            mode: mode,
                            context: context,
                            specialOptions: self.specialOptions
                        )
                    } else {
                        await self.handleGlobalShortcut(action)
                    }
                }
            },
            onShortcutInterrupted: { [weak self] action, _ in
                Task { @MainActor in
                    guard let self, self.recordingMode(for: action) != nil else { return }
                    await self.shortcutModeHandler.handleInterruption(action: action)
                }
            }
        )

        guard !isMonitoring, !shortcuts.isEmpty else {
            return
        }

        if !ShortcutMonitor.preflightListenEventAccess() {
            guard !hasShownInputMonitoringPermissionNotification else { return }
            hasShownInputMonitoringPermissionNotification = true
            NotificationManager.shared.showNotification(
                title: "Enable Input Monitoring for shortcuts",
                type: .warning,
                duration: 6,
                actionButton: (
                    label: "Open Settings",
                    action: {
                        Task { @MainActor in
                            PermissionGrantCoordinator.grantInputMonitoring()
                        }
                    }
                )
            )
            return
        }

        if !ShortcutMonitor.preflightAccessibilityAccess() {
            guard !hasShownAccessibilityPermissionNotification else { return }
            hasShownAccessibilityPermissionNotification = true
            NotificationManager.shared.showNotification(
                title: "Enable Accessibility for shortcuts",
                type: .warning,
                duration: 6,
                actionButton: (
                    label: "Open Settings",
                    action: {
                        Task { @MainActor in
                            PermissionGrantCoordinator.grantAccessibility()
                        }
                    }
                )
            )
            return
        }

        guard !hasShownShortcutMonitorFailureNotification else { return }
        hasShownShortcutMonitorFailureNotification = true
        NotificationManager.shared.showNotification(
            title: "Keyboard shortcut monitor could not start",
            type: .error,
            duration: 6
        )
    }

    private func recordingMode(for action: ShortcutAction) -> Mode? {
        switch action {
        case .primaryRecording:
            return primaryRecordingShortcutMode
        case .secondaryRecording:
            return secondaryRecordingShortcutMode
        default:
            return nil
        }
    }

    private var specialOptions: SpecialShortcutOptions {
        SpecialShortcutOptions(
            keyDownBehavior: specialShortcutKeyDownBehavior,
            allowsKeyDownOnlyTrigger: specialShortcutAllowsKeyDownOnlyTrigger,
            pasteLastTranscriptOnEmptyTap: specialShortcutPasteLastTranscriptOnEmptyTap
        )
    }

    private func handleGlobalShortcut(_ action: ShortcutAction) async {
        switch action {
        case .pasteLastTranscription:
            LastTranscriptionService.pasteLastTranscription(from: engine.modelContext)
        case .pasteLastEnhancement:
            LastTranscriptionService.pasteLastEnhancement(from: engine.modelContext)
        case .retryLastTranscription:
            LastTranscriptionService.retryLastTranscription(
                from: engine.modelContext,
                transcriptionModelManager: engine.transcriptionModelManager,
                serviceRegistry: engine.serviceRegistry,
                enhancementService: engine.enhancementService
            )
        case .openHistoryWindow:
            HistoryWindowController.shared.showHistoryWindow(
                modelContainer: engine.modelContext.container,
                engine: engine
            )
        case .quickAddToDictionary:
            DictionaryQuickAddManager.shared.toggle(modelContainer: engine.modelContext.container)
        default:
            break
        }
    }

    private func removeAllMonitoring() {
        shortcutMonitor.stop()
        
        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()
        
        shortcutModeHandler.reset()
    }
    
    var isShortcutConfigured: Bool {
        let isPrimaryShortcutConfigured = primaryRecordingShortcut != .none && ShortcutStore.shortcut(for: .primaryRecording) != nil
        let isSecondaryShortcutConfigured = secondaryRecordingShortcut == .none || ShortcutStore.shortcut(for: .secondaryRecording) != nil
        return isPrimaryShortcutConfigured && isSecondaryShortcutConfigured
    }
    
    func updateShortcutStatus() {
        // Called when a shortcut changes
        refreshShortcutMonitoring()
    }
    
    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }

        if let permissionChangeObserver {
            NotificationCenter.default.removeObserver(permissionChangeObserver)
        }

        MainActor.assumeIsolated {
            removeAllMonitoring()
        }
    }
}

@MainActor
private final class RecordingShortcutModeSource {
    var primaryMode: RecordingShortcutManager.Mode

    init(primaryMode: RecordingShortcutManager.Mode) {
        self.primaryMode = primaryMode
    }
}

@MainActor
private final class RecordingShortcutSpecialOptionsSource {
    var options: SpecialShortcutOptions

    init(options: SpecialShortcutOptions) {
        self.options = options
    }
}

@MainActor
final class RecordingShortcutModeHandler {
    private let logger: Logger
    private let canHandleShortcutAction: @MainActor () -> Bool
    private let isRecorderVisible: @MainActor () -> Bool
    private let recordingState: @MainActor () -> RecordingState
    private let toggleMiniRecorder: @MainActor (UUID?) async -> Void
    private let cancelRecording: @MainActor () async -> Void
    private let discardRecording: @MainActor () async -> Void
    private let pasteLastTranscription: @MainActor () -> Void

    private var shortcutPressStartTime: TimeInterval?
    private var isHandsFreeRecording = false
    private var isShortcutPressed = false
    private var activeRecordingShortcutAction: ShortcutAction?
    private var interruptedRecordingActions = Set<ShortcutAction>()
    private var activeShortcutCanCancelAccidentalStart = false
    private var activeSpecialOptions = SpecialShortcutOptions()
    private var lastShortcutPressTime: Date?

    private let shortcutPressCooldown: TimeInterval = 0.5
    private let hybridPressThreshold: TimeInterval = 0.5
    private let emptyTapThreshold: TimeInterval = 0.32

    init(
        logger: Logger,
        canHandleShortcutAction: @escaping @MainActor () -> Bool,
        isRecorderVisible: @escaping @MainActor () -> Bool,
        recordingState: @escaping @MainActor () -> RecordingState,
        toggleMiniRecorder: @escaping @MainActor (UUID?) async -> Void,
        cancelRecording: @escaping @MainActor () async -> Void,
        discardRecording: @escaping @MainActor () async -> Void = {},
        pasteLastTranscription: @escaping @MainActor () -> Void = {}
    ) {
        self.logger = logger
        self.canHandleShortcutAction = canHandleShortcutAction
        self.isRecorderVisible = isRecorderVisible
        self.recordingState = recordingState
        self.toggleMiniRecorder = toggleMiniRecorder
        self.cancelRecording = cancelRecording
        self.discardRecording = discardRecording
        self.pasteLastTranscription = pasteLastTranscription
    }

    func reset() {
        isShortcutPressed = false
        shortcutPressStartTime = nil
        isHandsFreeRecording = false
        activeRecordingShortcutAction = nil
        interruptedRecordingActions.removeAll()
        activeShortcutCanCancelAccidentalStart = false
        activeSpecialOptions = SpecialShortcutOptions()
    }

    func handleKeyDown(
        action: ShortcutAction,
        eventTime: TimeInterval,
        mode: RecordingShortcutManager.Mode,
        specialOptions: SpecialShortcutOptions = SpecialShortcutOptions(),
        powerModeId: UUID? = nil
    ) async {
        if interruptedRecordingActions.remove(action) != nil {
            return
        }

        if let lastTrigger = lastShortcutPressTime,
           Date().timeIntervalSince(lastTrigger) < shortcutPressCooldown {
            return
        }

        guard !isShortcutPressed else { return }
        isShortcutPressed = true
        activeRecordingShortcutAction = action
        activeShortcutCanCancelAccidentalStart = canCurrentShortcutPressCancelAccidentalStart
        activeSpecialOptions = specialOptions
        lastShortcutPressTime = Date()
        shortcutPressStartTime = eventTime

        switch mode {
        case .special:
            switch specialOptions.keyDownBehavior {
            case .startRecording:
                await startRecordingIfNeeded(mode: mode, powerModeId: powerModeId)
            case .preloadOnly:
                logger.notice("handleShortcutKeyDown: preloading special shortcut without starting recording")
            }

        case .pushToTalk:
            await startRecordingIfNeeded(mode: mode, powerModeId: powerModeId)

        case .toggle, .hybrid:
            if isHandsFreeRecording {
                isHandsFreeRecording = false
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyDown: toggling mini recorder (hands-free toggle)")
                await toggleMiniRecorder(powerModeId)
                return
            }

            if !isRecorderVisible() {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyDown: toggling mini recorder (key down while not visible)")
                await toggleMiniRecorder(powerModeId)
            }
        }
    }

    func handleKeyUp(
        action: ShortcutAction,
        eventTime: TimeInterval,
        mode: RecordingShortcutManager.Mode,
        context: ShortcutPressContext = ShortcutPressContext(),
        specialOptions: SpecialShortcutOptions = SpecialShortcutOptions(),
        powerModeId: UUID? = nil
    ) async {
        guard isShortcutPressed, activeRecordingShortcutAction == action else { return }
        isShortcutPressed = false
        activeRecordingShortcutAction = nil
        activeShortcutCanCancelAccidentalStart = false

        switch mode {
        case .special:
            let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
            let options = activeSpecialOptions
            let hasTypingEvidence = context.didPressOtherKeyDuringPress || context.didReleaseOtherKeyDuringPress

            if hasTypingEvidence {
                logger.notice("handleShortcutKeyUp: cancelling special shortcut; typing evidence during hold")
                if isRecorderVisible() {
                    await cancelRecording()
                }
            } else if options.pasteLastTranscriptOnEmptyTap,
                      isEmptyTap(pressDuration: pressDuration) {
                logger.notice("handleShortcutKeyUp: pasting last transcription for empty special tap")
                pasteLastTranscription()
                if isRecorderVisible() {
                    await discardRecording()
                }
            } else if isRecorderVisible() {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyUp: stopping recording (special shortcut, duration=\(pressDuration, privacy: .public)s)")
                await toggleMiniRecorder(powerModeId)
            } else if options.keyDownBehavior == .preloadOnly {
                logger.notice("handleShortcutKeyUp: committing preloaded special shortcut")
                await commitPreloadedSpecialShortcut(powerModeId: powerModeId)
            }

        case .toggle:
            isHandsFreeRecording = true

        case .pushToTalk:
            if isRecorderVisible() {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyUp: stopping recording (push-to-talk key up)")
                await toggleMiniRecorder(powerModeId)
            }

        case .hybrid:
            let pressDuration = shortcutPressStartTime.map { eventTime - $0 } ?? 0
            if pressDuration >= hybridPressThreshold && recordingState() == .recording {
                guard canHandleShortcutAction() else { return }
                logger.notice("handleShortcutKeyUp: stopping recording (hybrid push-to-talk, duration=\(pressDuration, privacy: .public)s)")
                await toggleMiniRecorder(powerModeId)
            } else {
                isHandsFreeRecording = true
            }
        }

        shortcutPressStartTime = nil
        activeSpecialOptions = SpecialShortcutOptions()
    }

    func handleInterruption(action: ShortcutAction) async {
        guard isShortcutPressed, activeRecordingShortcutAction == action else {
            if canCurrentShortcutPressCancelAccidentalStart {
                interruptedRecordingActions.insert(action)
            }
            return
        }

        guard activeShortcutCanCancelAccidentalStart else { return }

        logger.notice("handleShortcutInterruption: cancelling recording shortcut that became part of a larger key chord")
        reset()
        await cancelRecording()
    }

    private var canCurrentShortcutPressCancelAccidentalStart: Bool {
        !isRecorderVisible() && recordingState() == .idle
    }

    private func isEmptyTap(pressDuration: TimeInterval) -> Bool {
        pressDuration < emptyTapThreshold
    }

    private func startRecordingIfNeeded(mode: RecordingShortcutManager.Mode, powerModeId: UUID?) async {
        if !isRecorderVisible() {
            guard canHandleShortcutAction() else { return }
            logger.notice("handleShortcutKeyDown: starting recording (\(mode.rawValue, privacy: .public) key down)")
            await toggleMiniRecorder(powerModeId)
        }
    }

    private func commitPreloadedSpecialShortcut(powerModeId: UUID?) async {
        guard canHandleShortcutAction() else { return }
        await toggleMiniRecorder(powerModeId)

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            switch recordingState() {
            case .recording:
                guard canHandleShortcutAction() else { return }
                await toggleMiniRecorder(powerModeId)
                return
            case .idle, .starting:
                try? await Task.sleep(nanoseconds: 20_000_000)
            case .transcribing, .enhancing, .busy:
                return
            }
        }

        logger.error("handleShortcutKeyUp: timed out committing preloaded special shortcut")
        await cancelRecording()
    }
}
