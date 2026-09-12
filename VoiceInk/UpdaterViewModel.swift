import AppKit
import Combine
import Sparkle
import VoiceInkCore

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticUpdatesEnabled = false
    @Published private(set) var status = VoiceInkUpdateStatus.idle
    @Published private(set) var releaseNotesURL: URL?
    @Published private(set) var track: VoiceInkUpdateTrack

    private var updater: SPUUpdater!
    private var cancellation: (() -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedContentLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0
    private var currentVersion: String?
    private var userInitiatedCheck = false

    override init() {
        track = VoiceInkUpdatePreference.track()
        super.init()

        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )

        do {
            try updater.start()
        } catch {
            status = VoiceInkUpdateStatus(phase: .failed, detail: error.localizedDescription)
        }

        canCheckForUpdates = updater.canCheckForUpdates
        automaticUpdatesEnabled = updater.automaticallyChecksForUpdates
            && updater.automaticallyDownloadsUpdates

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        Publishers.CombineLatest(
            updater.publisher(for: \.automaticallyChecksForUpdates),
            updater.publisher(for: \.automaticallyDownloadsUpdates)
        )
            .map { $0 && $1 }
            .assign(to: &$automaticUpdatesEnabled)

        #if UPDATE_E2E
        DispatchQueue.main.async { [weak self] in
            self?.updater.checkForUpdatesInBackground()
        }
        #endif
    }

    func setAutomaticUpdatesEnabled(_ value: Bool) {
        updater.automaticallyDownloadsUpdates = value
        updater.automaticallyChecksForUpdates = value
        if !value {
            cancelUpdate()
        }
    }

    func setTrack(_ value: VoiceInkUpdateTrack) {
        guard value != track else { return }
        cancelUpdate()
        track = value
        VoiceInkUpdatePreference.saveTrack(value)
        updater.resetUpdateCycle()
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    func cancelUpdate() {
        if let readyReply {
            self.readyReply = nil
            readyReply(.skip)
        } else if let cancellation {
            self.cancellation = nil
            cancellation()
        }
        resetVisibleState()
    }

    func relaunchToUpdate() {
        guard let readyReply else { return }
        self.readyReply = nil
        status = VoiceInkUpdateStatus(phase: .installing, version: currentVersion)
        readyReply(.install)
    }

    func dismissStatus() {
        guard status.phase == .upToDate || status.phase == .failed else { return }
        resetVisibleState()
    }

    private func resetVisibleState() {
        cancellation = nil
        readyReply = nil
        expectedContentLength = 0
        downloadedLength = 0
        currentVersion = nil
        releaseNotesURL = nil
        userInitiatedCheck = false
        status = .idle
    }

    private func showTransient(_ newStatus: VoiceInkUpdateStatus) {
        status = newStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard self?.status == newStatus else { return }
            self?.resetVisibleState()
        }
    }
}

extension UpdaterViewModel: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if UPDATE_E2E
        if let override = ProcessInfo.processInfo.environment["ROMA_UPDATE_FEED_URL"],
           let url = URL(string: override),
           url.host == "127.0.0.1" || url.host == "localhost" {
            return override
        }
        #endif
        return track.feedURL.absoluteString
    }
}

extension UpdaterViewModel: SPUUserDriver {
    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: true,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiatedCheck = true
        self.cancellation = cancellation
        status = VoiceInkUpdateStatus(phase: .checking)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        cancellation = nil
        currentVersion = appcastItem.displayVersionString
        releaseNotesURL = appcastItem.infoURL as URL?

        guard !appcastItem.isInformationOnlyUpdate else {
            showTransient(VoiceInkUpdateStatus(
                phase: .failed,
                version: currentVersion,
                detail: "This release must be downloaded from Release History."
            ))
            reply(.dismiss)
            return
        }

        switch state.stage {
        case .notDownloaded:
            status = VoiceInkUpdateStatus(phase: .downloading, version: currentVersion, progress: 0)
            reply(.install)
        case .downloaded:
            status = VoiceInkUpdateStatus(phase: .preparing, version: currentVersion)
            reply(.install)
        case .installing:
            status = VoiceInkUpdateStatus(phase: .ready, version: currentVersion)
            readyReply = reply
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        if userInitiatedCheck {
            showTransient(VoiceInkUpdateStatus(phase: .upToDate))
        } else {
            resetVisibleState()
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancellation = nil
        showTransient(VoiceInkUpdateStatus(phase: .failed, detail: error.localizedDescription))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        downloadedLength = 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength += length
        let progress = expectedContentLength > 0
            ? Double(downloadedLength) / Double(expectedContentLength)
            : nil
        status = VoiceInkUpdateStatus(
            phase: .downloading,
            version: currentVersion,
            progress: progress
        )
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        status = VoiceInkUpdateStatus(phase: .preparing, version: currentVersion)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = VoiceInkUpdateStatus(phase: .preparing, version: currentVersion, progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        status = VoiceInkUpdateStatus(phase: .ready, version: currentVersion)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        status = VoiceInkUpdateStatus(phase: .installing, version: currentVersion)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        if status.phase != .installing {
            resetVisibleState()
        }
    }

    func showUpdateInFocus() {}
}
