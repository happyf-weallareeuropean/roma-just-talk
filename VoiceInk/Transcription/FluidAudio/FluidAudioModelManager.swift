import Foundation
import Combine
import FluidAudio
#if os(macOS)
import AppKit
#endif
import os
import VoiceInkCore

enum FluidAudioModelDownloadIssue: Equatable {
    case stalled
    case failed(String)
    case cancelled

    var message: String {
        switch self {
        case .stalled:
            return "No progress recently. You can keep waiting, cancel, or retry."
        case .failed(let message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download canceled."
        }
    }

    var systemImage: String {
        switch self {
        case .stalled:
            return "exclamationmark.triangle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "xmark.circle"
        }
    }
}

struct FluidAudioModelDownloadClient {
    typealias ProgressHandler = @Sendable (VoiceInkFluidAudioDownloadStatus) -> Void
    typealias DownloadOperation = (AsrModelVersion, Bool, @escaping ProgressHandler) async throws -> Void

    let modelsExist: (AsrModelVersion) -> Bool
    let cacheDirectoryExists: (AsrModelVersion) -> Bool
    let validateCache: (AsrModelVersion) async throws -> Bool
    let downloadAndLoad: DownloadOperation

    static let live = FluidAudioModelDownloadClient(
        modelsExist: { version in
            AsrModels.modelsExist(
                at: AsrModels.defaultCacheDirectory(for: version),
                version: version
            )
        },
        cacheDirectoryExists: { version in
            FileManager.default.fileExists(
                atPath: AsrModels.defaultCacheDirectory(for: version).path
            )
        },
        validateCache: { version in
            try await AsrModels.isModelValid(version: version)
        },
        downloadAndLoad: { version, force, reportProgress in
            let progressHandler: DownloadUtils.ProgressHandler = { progress in
                reportProgress(VoiceInkFluidAudioDownloadStatus(progress: progress))
            }
            let directory = try await AsrModels.download(
                force: force,
                version: version,
                progressHandler: progressHandler
            )
            _ = try await AsrModels.load(
                from: directory,
                version: version,
                progressHandler: progressHandler
            )
        }
    )
}

@MainActor
class FluidAudioModelManager: ObservableObject {
    static let shared = FluidAudioModelManager()

    private struct ActiveDownload {
        let id: UUID
        let task: Task<Void, Never>
    }

    @Published private var downloadStatuses: [String: VoiceInkFluidAudioDownloadStatus] = [:]
    @Published private var downloadIssues: [String: FluidAudioModelDownloadIssue] = [:]
    private var activeDownloads: [String: ActiveDownload] = [:]
    private var watchdogTasks: [String: Task<Void, Never>] = [:]
    private var downloadStartedAt: [String: Date] = [:]
    private var lastProgressAt: [String: Date] = [:]
    private var lastLoggedDownloadPercents: [String: Int] = [:]
    private var lastLoggedDownloadMessages: [String: String] = [:]

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let client: FluidAudioModelDownloadClient
    private let staleAfter: TimeInterval
    private let now: () -> Date
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "FluidAudioModelManager")

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        AsrModelVersion(
            VoiceInkTranscriptionModelCatalog.fluidAudioModelVersion(forModelName: modelName)
        )
    }

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        VoiceInkTranscriptionModelCatalog
            .fluidAudioLanguageHintCode(from: languageCode, forModelName: modelName)
            .flatMap(Language.init(rawValue:))
    }

    init(
        client: FluidAudioModelDownloadClient = .live,
        staleAfter: TimeInterval = 5 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.staleAfter = staleAfter
        self.now = now
    }

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        guard activeDownloads[modelName] == nil,
              downloadIssues[modelName] == nil else {
            return false
        }
        return client.modelsExist(FluidAudioModelManager.asrVersion(for: modelName))
    }

    func isFluidAudioModelDownloading(named modelName: String) -> Bool {
        activeDownloads[modelName] != nil
    }

    func downloadStatus(forModelNamed modelName: String) -> VoiceInkFluidAudioDownloadStatus? {
        downloadStatuses[modelName]
    }

    func downloadIssue(forModelNamed modelName: String) -> FluidAudioModelDownloadIssue? {
        downloadIssues[modelName]
    }

    #if os(macOS)
    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloading(named: model.name)
    }

    func downloadStatus(for model: FluidAudioModel) -> VoiceInkFluidAudioDownloadStatus? {
        downloadStatus(forModelNamed: model.name)
    }

    func downloadIssue(for model: FluidAudioModel) -> FluidAudioModelDownloadIssue? {
        downloadIssue(forModelNamed: model.name)
    }
    #endif

    // MARK: - Download

    func downloadFluidAudioModel(named modelName: String) async {
        if isFluidAudioModelDownloaded(named: modelName) {
            logger.notice("FluidAudio download skipped; model already downloaded: \(modelName, privacy: .public)")
            clearDownloadPresentation(for: modelName)
            onModelsChanged?()
            return
        }

        if let activeDownload = activeDownloads[modelName] {
            logger.notice("FluidAudio download joined existing task: \(modelName, privacy: .public)")
            await activeDownload.task.value
            return
        }

        await startDownload(modelName: modelName, force: false)
    }

    #if os(macOS)
    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        await downloadFluidAudioModel(named: model.name)
    }
    #endif

    func cancelFluidAudioModelDownload(named modelName: String) {
        guard let activeDownload = activeDownloads[modelName] else { return }
        logger.notice("FluidAudio download cancellation requested: \(modelName, privacy: .public)")
        activeDownload.task.cancel()
    }

    #if os(macOS)
    func cancelFluidAudioModelDownload(_ model: FluidAudioModel) {
        cancelFluidAudioModelDownload(named: model.name)
    }
    #endif

    func retryFluidAudioModelDownload(named modelName: String) async {
        if let activeDownload = activeDownloads[modelName] {
            logger.notice("FluidAudio download retry cancelling existing task: \(modelName, privacy: .public)")
            activeDownload.task.cancel()
            await activeDownload.task.value
        }

        let version = FluidAudioModelManager.asrVersion(for: modelName)
        let cacheExists = client.cacheDirectoryExists(version)
        if cacheExists {
            do {
                if try await client.validateCache(version) {
                    logger.notice("FluidAudio retry found a valid completed cache: \(modelName, privacy: .public)")
                    clearDownloadPresentation(for: modelName)
                    onModelsChanged?()
                    return
                }
            } catch {
                logger.error(
                    "FluidAudio cache validation failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        await startDownload(modelName: modelName, force: cacheExists)
    }

    #if os(macOS)
    func retryFluidAudioModelDownload(_ model: FluidAudioModel) async {
        await retryFluidAudioModelDownload(named: model.name)
    }
    #endif

    func checkForStalledDownloads(at date: Date? = nil) {
        let checkDate = date ?? now()
        for (modelName, activeDownload) in activeDownloads {
            guard let progressDate = lastProgressAt[modelName],
                  checkDate.timeIntervalSince(progressDate) >= staleAfter,
                  downloadIssues[modelName] != .stalled else {
                continue
            }

            downloadIssues[modelName] = .stalled
            logger.error(
                "FluidAudio download has made no progress: \(modelName, privacy: .public), downloadID=\(activeDownload.id.uuidString, privacy: .public), silentSeconds=\(Int(checkDate.timeIntervalSince(progressDate)), privacy: .public)"
            )
        }
    }

    private func startDownload(modelName: String, force: Bool) async {
        let downloadID = UUID()
        let startedAt = now()
        logger.notice(
            "FluidAudio download starting: \(modelName, privacy: .public), downloadID=\(downloadID.uuidString, privacy: .public), force=\(force, privacy: .public)"
        )

        downloadStartedAt[modelName] = startedAt
        lastProgressAt[modelName] = startedAt
        downloadIssues[modelName] = nil
        let initialStatus = VoiceInkFluidAudioDownloadStatus(
            fractionCompleted: 0.0,
            phase: .preparingDownload
        )
        downloadStatuses[modelName] = initialStatus
        logDownloadProgressIfNeeded(initialStatus, for: modelName)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runDownload(modelName: modelName, downloadID: downloadID, force: force)
        }
        activeDownloads[modelName] = ActiveDownload(id: downloadID, task: task)
        startWatchdog(for: modelName, downloadID: downloadID)
        await task.value
    }

    private func runDownload(modelName: String, downloadID: UUID, force: Bool) async {
        let version = FluidAudioModelManager.asrVersion(for: modelName)
        let reportProgress: FluidAudioModelDownloadClient.ProgressHandler = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(status, for: modelName, downloadID: downloadID)
            }
        }

        do {
            try await client.downloadAndLoad(version, force, reportProgress)
            try Task.checkCancellation()
            guard client.modelsExist(version) else {
                throw FluidAudioModelManagerError.completedWithoutModels
            }
            finishDownload(modelName: modelName, downloadID: downloadID, result: .success(()))
        } catch where Task.isCancelled || error is CancellationError {
            // URLSession may report URLError.cancelled after the owning task is canceled.
            let result: Result<Void, Error> = client.modelsExist(version)
                ? .success(())
                : .failure(CancellationError())
            finishDownload(modelName: modelName, downloadID: downloadID, result: result)
        } catch {
            finishDownload(modelName: modelName, downloadID: downloadID, result: .failure(error))
        }
    }

    private func startWatchdog(for modelName: String, downloadID: UUID) {
        watchdogTasks[modelName]?.cancel()
        watchdogTasks[modelName] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled,
                      self?.activeDownloads[modelName]?.id == downloadID else {
                    return
                }
                self?.checkForStalledDownloads()
            }
        }
    }

    private func finishDownload(
        modelName: String,
        downloadID: UUID,
        result: Result<Void, Error>
    ) {
        guard activeDownloads[modelName]?.id == downloadID else { return }

        watchdogTasks[modelName]?.cancel()
        watchdogTasks[modelName] = nil
        activeDownloads[modelName] = nil
        lastProgressAt[modelName] = nil

        let elapsed = Int(now().timeIntervalSince(downloadStartedAt[modelName] ?? now()))
        switch result {
        case .success:
            logger.notice(
                "FluidAudio download finished: \(modelName, privacy: .public), downloadID=\(downloadID.uuidString, privacy: .public), elapsedSeconds=\(elapsed, privacy: .public)"
            )
            clearDownloadPresentation(for: modelName)
        case .failure(let error) where error is CancellationError:
            logger.notice(
                "FluidAudio download cancelled: \(modelName, privacy: .public), downloadID=\(downloadID.uuidString, privacy: .public), elapsedSeconds=\(elapsed, privacy: .public)"
            )
            downloadStatuses[modelName] = nil
            downloadIssues[modelName] = .cancelled
            clearDownloadLogState(for: modelName)
        case .failure(let error):
            logger.error(
                "FluidAudio download failed: \(modelName, privacy: .public), downloadID=\(downloadID.uuidString, privacy: .public), elapsedSeconds=\(elapsed, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
            )
            downloadStatuses[modelName] = nil
            downloadIssues[modelName] = .failed(error.localizedDescription)
            clearDownloadLogState(for: modelName)
        }

        downloadStartedAt[modelName] = nil
        onModelsChanged?()
    }

    // MARK: - Delete

    func deleteFluidAudioModel(named modelName: String) {
        let cacheDirectory = cacheDirectory(forModelNamed: modelName)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        } catch {
            logger.error(
                "FluidAudio model deletion failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }

        clearDownloadPresentation(for: modelName)
        onModelDeleted?(modelName)
    }

    #if os(macOS)
    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        deleteFluidAudioModel(named: model.name)
    }
    #endif

    // MARK: - Finder

    #if os(macOS)
    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        showFluidAudioModelInFinder(named: model.name)
    }

    func showFluidAudioModelInFinder(named modelName: String) {
        let cacheDirectory = cacheDirectory(forModelNamed: modelName)

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }
    #endif

    // MARK: - Private helpers

    private func cacheDirectory(forModelNamed modelName: String) -> URL {
        cacheDirectory(for: FluidAudioModelManager.asrVersion(for: modelName))
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    private func clearDownloadPresentation(for modelName: String) {
        downloadStatuses[modelName] = nil
        downloadIssues[modelName] = nil
        clearDownloadLogState(for: modelName)
    }

    private func clearDownloadLogState(for modelName: String) {
        lastLoggedDownloadPercents[modelName] = nil
        lastLoggedDownloadMessages[modelName] = nil
    }

    private func updateDownloadProgress(
        _ status: VoiceInkFluidAudioDownloadStatus,
        for modelName: String,
        downloadID: UUID
    ) {
        guard activeDownloads[modelName]?.id == downloadID else { return }

        downloadStatuses[modelName] = status
        lastProgressAt[modelName] = now()
        if downloadIssues[modelName] == .stalled {
            downloadIssues[modelName] = nil
            logger.notice("FluidAudio download resumed after a silent interval: \(modelName, privacy: .public)")
        }
        logDownloadProgressIfNeeded(status, for: modelName)
    }

    private func logDownloadProgressIfNeeded(_ status: VoiceInkFluidAudioDownloadStatus, for modelName: String) {
        let percent = status.percent
        let previousPercent = lastLoggedDownloadPercents[modelName]
        let previousMessage = lastLoggedDownloadMessages[modelName]
        let shouldLog = previousPercent == nil
            || previousMessage != status.message
            || percent >= (previousPercent ?? 0) + 5
            || percent == 100

        guard shouldLog else { return }

        lastLoggedDownloadPercents[modelName] = percent
        lastLoggedDownloadMessages[modelName] = status.message
        let elapsed = Int(now().timeIntervalSince(downloadStartedAt[modelName] ?? now()))
        let downloadID = activeDownloads[modelName]?.id.uuidString ?? "unknown"
        logger.notice(
            "FluidAudio download progress: \(modelName, privacy: .public), downloadID=\(downloadID, privacy: .public), percent=\(percent, privacy: .public), message=\(status.message, privacy: .public), elapsedSeconds=\(elapsed, privacy: .public)"
        )
    }
}

private enum FluidAudioModelManagerError: LocalizedError {
    case completedWithoutModels

    var errorDescription: String? {
        "The download completed, but the required model files are missing."
    }
}

private extension VoiceInkFluidAudioDownloadStatus {
    init(progress: DownloadUtils.DownloadProgress) {
        self.init(
            fractionCompleted: progress.fractionCompleted,
            phase: Self.downloadPhase(for: progress)
        )
    }

    static func downloadPhase(for progress: DownloadUtils.DownloadProgress) -> VoiceInkFluidAudioDownloadPhase {
        switch progress.phase {
        case .listing:
            return .listingFiles
        case .downloading(let completedFiles, let totalFiles):
            guard totalFiles > 0 else {
                return .checkingCachedModels
            }
            return .downloadingFiles(completedFiles: completedFiles, totalFiles: totalFiles)
        case .compiling(let modelName):
            guard !modelName.isEmpty else {
                return .finalizingModels
            }
            return .compiling(modelComponentName: modelName)
        }
    }
}

private extension AsrModelVersion {
    init(_ version: VoiceInkFluidAudioModelVersion) {
        switch version {
        case .v2:
            self = .v2
        case .v3:
            self = .v3
        }
    }
}
