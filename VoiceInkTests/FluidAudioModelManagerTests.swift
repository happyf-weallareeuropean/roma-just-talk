import Foundation
import Testing
import VoiceInkCore
@testable import VoiceInk

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private final class TestDateBox {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

private actor SuspendedFluidAudioDownload {
    private let usesURLCancellation: Bool
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: FluidAudioModelDownloadClient.ProgressHandler?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startCount = 0

    init(usesURLCancellation: Bool = false) {
        self.usesURLCancellation = usesURLCancellation
    }

    func run(
        force: Bool,
        progressHandler: @escaping FluidAudioModelDownloadClient.ProgressHandler
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.progressHandler = progressHandler
                self.startCount += 1
                self.startWaiters.forEach { $0.resume() }
                self.startWaiters.removeAll()
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    func waitUntilStarted() async {
        guard startCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func report(_ status: VoiceInkFluidAudioDownloadStatus) {
        progressHandler?(status)
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }

    private func cancel() {
        let error: any Error = usesURLCancellation ? URLError(.cancelled) : CancellationError()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum TestDownloadError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Test download failed"
    }
}

private final class SequencedDownloadPlan: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Void, Error>]
    private var recordedForces: [Bool] = []
    let installed = LockedBoolean(false)

    init(results: [Result<Void, Error>]) {
        self.results = results
    }

    func run(force: Bool) async throws {
        let result: Result<Void, Error>
        lock.lock()
        recordedForces.append(force)
        result = results.removeFirst()
        lock.unlock()

        try result.get()
        installed.value = true
    }

    var forces: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedForces
    }
}

@Suite(.serialized)
struct FluidAudioModelManagerTests {
    @Test @MainActor
    func silentDownloadBecomesStalledThenRecoversWhenProgressResumes() async {
        let model = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        let installed = LockedBoolean(false)
        let download = SuspendedFluidAudioDownload()
        let startDate = Date(timeIntervalSince1970: 1_000)
        let dateBox = TestDateBox(startDate)
        let manager = FluidAudioModelManager(
            client: FluidAudioModelDownloadClient(
                modelsExist: { _ in installed.value },
                cacheDirectoryExists: { _ in false },
                validateCache: { _ in false },
                downloadAndLoad: { _, force, progressHandler in
                    try await download.run(force: force, progressHandler: progressHandler)
                }
            ),
            staleAfter: 300,
            now: { dateBox.value }
        )

        let task = Task {
            await manager.downloadFluidAudioModel(model)
        }
        await download.waitUntilStarted()

        manager.checkForStalledDownloads(at: startDate.addingTimeInterval(301))
        #expect(manager.downloadIssue(for: model) == .stalled)
        #expect(manager.isFluidAudioModelDownloading(model))

        dateBox.value = startDate.addingTimeInterval(302)
        await download.report(
            VoiceInkFluidAudioDownloadStatus(
                fractionCompleted: 0.2,
                phase: .downloadingFiles(completedFiles: 1, totalFiles: 4)
            )
        )
        await waitUntil {
            manager.downloadIssue(for: model) == nil
        }

        installed.value = true
        await download.finish()
        await task.value

        #expect(!manager.isFluidAudioModelDownloading(model))
        #expect(manager.downloadStatus(for: model) == nil)
        #expect(manager.downloadIssue(for: model) == nil)
        let startCount = await download.startCount
        #expect(startCount == 1)
    }

    @Test(arguments: [false, true]) @MainActor
    func secondCallerJoinsActiveDownloadAndCancellationLeavesRetryState(usesURLCancellation: Bool) async {
        let model = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        let download = SuspendedFluidAudioDownload(usesURLCancellation: usesURLCancellation)
        let manager = FluidAudioModelManager(
            client: FluidAudioModelDownloadClient(
                modelsExist: { _ in false },
                cacheDirectoryExists: { _ in false },
                validateCache: { _ in false },
                downloadAndLoad: { _, force, progressHandler in
                    try await download.run(force: force, progressHandler: progressHandler)
                }
            )
        )

        let first = Task {
            await manager.downloadFluidAudioModel(model)
        }
        await download.waitUntilStarted()
        let second = Task {
            await manager.downloadFluidAudioModel(model)
        }
        await Task.yield()

        manager.cancelFluidAudioModelDownload(model)
        await first.value
        await second.value

        let startCount = await download.startCount
        #expect(startCount == 1)
        #expect(!manager.isFluidAudioModelDownloading(model))
        #expect(manager.downloadIssue(for: model) == .cancelled)
        #expect(manager.downloadStatus(for: model) == nil)
    }

    @Test @MainActor
    func retryForceRedownloadsInvalidExistingCache() async {
        let model = TranscriptionModelRegistry.defaultMacOSFluidAudioModel
        let plan = SequencedDownloadPlan(results: [
            .failure(TestDownloadError.failed),
            .success(())
        ])
        let manager = FluidAudioModelManager(
            client: FluidAudioModelDownloadClient(
                modelsExist: { _ in plan.installed.value },
                cacheDirectoryExists: { _ in true },
                validateCache: { _ in false },
                downloadAndLoad: { _, force, _ in
                    try await plan.run(force: force)
                }
            )
        )

        await manager.downloadFluidAudioModel(model)
        #expect(manager.downloadIssue(for: model) == .failed("Test download failed"))
        #expect(manager.downloadStatus(for: model) == nil)

        await manager.retryFluidAudioModelDownload(model)

        #expect(plan.forces == [false, true])
        #expect(manager.downloadIssue(for: model) == nil)
        #expect(manager.isFluidAudioModelDownloaded(model))
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }
}
