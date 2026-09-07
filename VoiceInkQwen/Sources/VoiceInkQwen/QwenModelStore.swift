import Foundation
import HuggingFace

/// Owns one revision directory. Only a fully verified staging directory becomes installed.
actor QwenModelStore {
    typealias ProgressHandler = @Sendable (QwenDownloadProgress) -> Void
    typealias Download = @Sendable (QwenSnapshot, URL, @escaping ProgressHandler) async throws -> Void

    private let root: URL
    private let snapshot: QwenSnapshot
    private let download: Download
    private var active: (id: UUID, task: Task<URL, Error>)?
    private var deleting = false

    init(root: URL, snapshot: QwenSnapshot, download: @escaping Download = QwenModelStore.downloadSnapshot) {
        self.root = root
        self.snapshot = snapshot
        self.download = download
    }

    deinit { active?.task.cancel() }

    func isInstalled() -> Bool {
        !deleting && active == nil && snapshot.isPresent(at: root.appendingPathComponent(snapshot.revision))
    }

    func cachedDirectory() throws -> URL {
        guard !deleting else { throw QwenRuntimeError.busy }
        let directory = root.appendingPathComponent(snapshot.revision)
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
        let task = Task.detached { [root, snapshot, download] in
            let files = FileManager.default
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            let staging = root.appendingPathComponent(".download-\(id.uuidString)")
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? files.removeItem(at: staging) }
            try await download(snapshot, staging, progress)
            progress(.init(phase: .verifying, fractionCompleted: 1))
            try snapshot.verify(at: staging, includingTokenizer: false)
            try snapshot.copyTokenizer(to: staging)
            try Task.checkCancellation()
            let destination = root.appendingPathComponent(snapshot.revision)
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
        let destination = root.appendingPathComponent(snapshot.revision)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    private static func downloadSnapshot(
        _ snapshot: QwenSnapshot, to directory: URL, progress: @escaping ProgressHandler
    ) async throws {
        guard let repo = Repo.ID(rawValue: snapshot.repo) else {
            throw QwenRuntimeError.invalidFile("snapshot.json")
        }
        // No credential discovery, mutable revision, global cache, or fallback model request.
        let client = HubClient(host: HubClient.defaultHost, bearerToken: nil, cache: nil)
        _ = try await client.downloadSnapshot(
            of: repo, to: directory, revision: snapshot.revision,
            matching: snapshot.files.map(\.file), maxConcurrentDownloads: 2
        ) { value in
            progress(.init(phase: .downloading, fractionCompleted: value.fractionCompleted))
        }
        try Task.checkCancellation()
    }
}
