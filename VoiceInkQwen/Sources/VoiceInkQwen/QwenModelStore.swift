import Foundation
import HuggingFace

/// Owns one revision directory. Only a fully verified staging directory becomes installed.
actor QwenModelStore {
    typealias ProgressHandler = @Sendable (QwenDownloadProgress) -> Void
    typealias Download = @Sendable (QwenSnapshot, URL, @escaping ProgressHandler) async throws -> Void

    private let root: URL
    private let directory: URL
    private let snapshot: QwenSnapshot
    private let download: Download
    private var active: (id: UUID, task: Task<URL, Error>)?
    private var deleting = false

    init(root: URL, snapshot: QwenSnapshot, download: @escaping Download = QwenModelStore.downloadSnapshot) {
        self.root = root
        directory = root.appendingPathComponent(snapshot.revision, isDirectory: true)
        self.snapshot = snapshot
        self.download = download
    }

    deinit { active?.task.cancel() }

    func isInstalled() -> Bool {
        !deleting && active == nil && snapshot.isPresent(at: directory)
    }

    func cachedDirectory() throws -> URL {
        guard !deleting else { throw QwenRuntimeError.busy }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw QwenRuntimeError.notInstalled
        }
        try snapshot.verify(at: directory)
        return directory
    }

    func install(progress: @escaping ProgressHandler) async throws -> URL {
        guard !deleting, active == nil else { throw QwenRuntimeError.busy }
        if let cached = try? cachedDirectory() {
            progress(.init(phase: .ready, fractionCompleted: 1))
            return cached
        }
        try Task.checkCancellation()
        let id = UUID()
        let task = Task.detached { [root, directory, snapshot, download] in
            let files = FileManager.default
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            let staging = root.appendingPathComponent(".download-\(id.uuidString)", isDirectory: true)
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? files.removeItem(at: staging) }
            try await download(snapshot, staging, progress)
            progress(.init(phase: .verifying, fractionCompleted: 1))
            try snapshot.verify(at: staging, includingTokenizer: false)
            try snapshot.copyTokenizer(to: staging)
            try Task.checkCancellation()
            let destination = directory
            if files.fileExists(atPath: destination.path) {
                // Replacement preserves the previous complete install if the atomic operation fails.
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: destination)
            }
            progress(.init(phase: .ready, fractionCompleted: 1))
            return destination
        }
        active = (id, task)
        defer { if active?.id == id { active = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancelAndDrain() async {
        guard let active else { return }
        active.task.cancel()
        _ = await active.task.result
        if self.active?.id == active.id { self.active = nil }
    }

    func delete() async throws {
        guard !deleting else { throw QwenRuntimeError.busy }
        deleting = true
        defer { deleting = false }
        await cancelAndDrain()
        let destination = directory
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    private static func downloadSnapshot(
        _ snapshot: QwenSnapshot, to directory: URL, progress: @escaping ProgressHandler
    ) async throws {
        // No credential discovery, mutable revision, global cache, or fallback model request.
        let client = HubClient(host: HubClient.defaultHost, bearerToken: nil, cache: nil)
        try await downloadFiles(snapshot, to: directory, client: client, progress: progress)
    }

    static func downloadFiles(
        _ snapshot: QwenSnapshot, to directory: URL, client: HubClient,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let repo = Repo.ID(rawValue: snapshot.repo) else {
            throw QwenRuntimeError.invalidFile("snapshot.json")
        }
        // Hub 0.10.0's snapshot API throws after a successful cacheless download.
        // The manifest already supplies exact filenames; single-file downloads need no cache.
        let total = DownloadProgress(Progress(totalUnitCount: snapshot.files.reduce(0) { $0 + $1.bytes }))
        let files = snapshot.files.sorted { $0.bytes > $1.bytes }.map { file in
            (file, DownloadProgress(Progress(totalUnitCount: file.bytes,
                parent: total.value, pendingUnitCount: file.bytes)))
        }
        progress(.init(phase: .downloading, fractionCompleted: 0))
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask {
                try await withThrowingTaskGroup(of: Void.self) { downloads in
                    for (index, entry) in files.enumerated() {
                        if index >= 2 { try await downloads.next() }
                        try Task.checkCancellation()
                        downloads.addTask {
                            let (file, fileProgress) = entry
                            _ = try await client.downloadFile(
                                at: file.file, from: repo,
                                to: directory.appendingPathComponent(file.file),
                                revision: snapshot.revision, progress: fileProgress.value,
                                transport: .lfs
                            )
                            try Task.checkCancellation()
                        }
                    }
                    try await downloads.waitForAll()
                }
            }
            tasks.addTask {
                while true {
                    try await Task.sleep(for: .milliseconds(100))
                    progress(.init(phase: .downloading, fractionCompleted: total.value.fractionCompleted))
                }
            }
            // Only the downloader completes normally. Drain the sampler before ready/cleanup.
            try await tasks.next()
            tasks.cancelAll()
        }
        try Task.checkCancellation()
        progress(.init(phase: .downloading, fractionCompleted: 1))
    }
}

// Foundation Progress synchronizes its counters internally; the references never change.
private final class DownloadProgress: @unchecked Sendable {
    let value: Progress
    init(_ value: Progress) { self.value = value }
}
