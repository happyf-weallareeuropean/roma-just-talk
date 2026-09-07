import Foundation
import Testing
@testable import VoiceInkQwen

@Test func completeInstallReopensWithoutNetwork() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("verified fixture".utf8)
    let snapshot = try fixtureSnapshot(bytes)
    let store = QwenModelStore(root: root, snapshot: snapshot) { _, directory, _ in
        try bytes.write(to: directory.appendingPathComponent("model.safetensors"))
    }
    let installed = try await store.install { _ in }
    #expect(installed.hasDirectoryPath)
    #expect(installed == root.appendingPathComponent(snapshot.revision, isDirectory: true))
    try snapshot.verify(at: installed)
    let offline = QwenModelStore(root: root, snapshot: snapshot) { _, _, _ in
        Issue.record("A verified offline cache must not contact the network")
        throw QwenRuntimeError.notInstalled
    }
    #expect(try await offline.install { _ in } == installed)
    #expect(try await offline.cachedDirectory() == installed)
    try Data(repeating: 0, count: bytes.count).write(to: installed.appendingPathComponent("model.safetensors"))
    await #expect(throws: QwenRuntimeError.self) { try await offline.cachedDirectory() }
    #expect(try await store.install { _ in } == installed)
    try snapshot.verify(at: installed)
    try await offline.delete()
    #expect(!FileManager.default.fileExists(atPath: installed.path))
}

@Test(.timeLimit(.minutes(1))) func deleteWaitsForCancelledDownloadToActuallyExit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = DownloadGate()
    let bytes = Data("verified fixture".utf8)
    let snapshot = try fixtureSnapshot(bytes)
    let store = QwenModelStore(root: root, snapshot: snapshot) { _, directory, _ in
        try bytes.write(to: directory.appendingPathComponent("model.safetensors"))
        await withTaskCancellationHandler {
            await gate.hold()
        } onCancel: {
            Task { await gate.markCancelled() }
        }
        // Intentionally delayed cancellation response models an in-flight networking callback.
    }
    let install = Task { try await store.install { _ in } }
    await gate.waitUntilStarted()
    let deletion = Task {
        try await store.delete()
        await gate.markDeleted()
    }
    await gate.waitUntilCancelled()
    #expect(await gate.deleted == false)
    let staging = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(staging.contains { $0.hasPrefix(".download-") })
    await gate.release()
    _ = await install.result
    try await deletion.value
    #expect(await gate.deleted)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test(.timeLimit(.minutes(1))) func secondInstallerHasExplicitOwnershipFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = DownloadGate()
    let bytes = Data("verified fixture".utf8)
    let snapshot = try fixtureSnapshot(bytes)
    let store = QwenModelStore(root: root, snapshot: snapshot) { _, directory, _ in
        try bytes.write(to: directory.appendingPathComponent("model.safetensors"))
        await gate.hold()
    }
    let first = Task { try await store.install { _ in } }
    await gate.waitUntilStarted()
    // Known-bad joins the first task; release independently so RED finishes rather than hangs.
    let release = Task {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        await gate.release()
    }
    var rejectedAsBusy = false
    do {
        _ = try await store.install { _ in }
    } catch QwenRuntimeError.busy {
        rejectedAsBusy = true
    }
    await gate.release()
    release.cancel()
    _ = await first.result
    #expect(rejectedAsBusy)
}

private func fixtureSnapshot(_ bytes: Data) throws -> QwenSnapshot {
    let bundled = try QwenSnapshot.bundled()
    return QwenSnapshot(
        repo: "test/model", revision: "fixture",
        files: [.init(file: "model.safetensors", bytes: Int64(bytes.count), sha256: digest(bytes))],
        tokenizer: bundled.tokenizer
    )
}

private actor DownloadGate {
    private var started = false
    private var cancelled = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var cancelWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var deleted = false

    func hold() async {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func waitUntilCancelled() async {
        if cancelled { return }
        await withCheckedContinuation { cancelWaiter = $0 }
    }

    func markCancelled() {
        cancelled = true
        cancelWaiter?.resume()
        cancelWaiter = nil
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func markDeleted() { deleted = true }
}
