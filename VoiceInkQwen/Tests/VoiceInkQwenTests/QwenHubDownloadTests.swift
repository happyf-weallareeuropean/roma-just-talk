import Foundation
import HuggingFace
import Testing
@testable import VoiceInkQwen

@Suite(.serialized) struct QwenHubDownloadTests {
    @Test func cachelessHubInstallPublishesAndReopensOffline() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanUp() }
        let store = fixture.store()
        let installed = try await store.install { HubFixture.routes.record($0) }
        try fixture.snapshot.verify(at: installed)
        let requests = HubFixture.routes.requests
        #expect(requests.count == fixture.snapshot.files.count)
        #expect(Set(requests.compactMap(\.url?.path)) == Set(fixture.filePaths))
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(HubFixture.routes.phases.last == .ready)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [fixture.snapshot.revision])

        // A new owner must reopen the exact installation without even constructing a request.
        HubFixture.routes.setResponses([:])
        let reopened = fixture.store()
        #expect(try await reopened.install { _ in } == installed)
        #expect(try await reopened.cachedDirectory() == installed)
        #expect(HubFixture.routes.requests.isEmpty)
    }

    @Test func pinnedSnapshotAPIThrowsAfterWritingAllCachelessFiles() async throws {
        let fixture = try HubFixture()
        defer { fixture.cleanUp() }
        let destination = fixture.root.appendingPathComponent("known-bad", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Exact production call before the fix. This establishes the failure is post-transfer.
        await #expect(throws: HubCacheError.self) {
            _ = try await fixture.client.downloadSnapshot(
                of: "test/model", to: destination, revision: fixture.snapshot.revision,
                matching: fixture.snapshot.files.map(\.file), maxConcurrentDownloads: 2
            )
        }
        for file in fixture.snapshot.files { try file.verify(at: destination) }
    }

    @Test func corruptHubDownloadNeverBecomesInstalled() async throws {
        let fixture = try HubFixture(corrupt: true)
        defer { fixture.cleanUp() }
        let store = fixture.store()
        await #expect(throws: QwenRuntimeError.self) {
            _ = try await store.install { HubFixture.routes.record($0) }
        }
        #expect(await store.isInstalled() == false)
        #expect(!HubFixture.routes.phases.contains(.ready))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test func failedHubDownloadNeverPublishesStaging() async throws {
        let fixture = try HubFixture(missing: true)
        defer { fixture.cleanUp() }
        let store = fixture.store()
        await #expect(throws: (any Error).self) {
            _ = try await store.install { HubFixture.routes.record($0) }
        }
        #expect(await store.isInstalled() == false)
        #expect(!HubFixture.routes.phases.contains(.ready))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func cancellationStopsHeldHubTransferBeforeCleanup() async throws {
        let fixture = try HubFixture(hold: true)
        defer { fixture.cleanUp() }
        let store = fixture.store()
        let install = Task { try await store.install { HubFixture.routes.record($0) } }
        defer { install.cancel() }
        for _ in 0..<200 {
            if HubFixture.routes.heldCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(HubFixture.routes.heldCount > 0)
        install.cancel()
        await store.cancelAndDrain()
        let result = await install.result
        if case .success = result { Issue.record("Cancelled HTTP transfer published an install") }
        #expect(HubFixture.routes.stoppedCount == HubFixture.routes.heldCount)
        #expect(await store.isInstalled() == false)
        #expect(!HubFixture.routes.phases.contains(.ready))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
        let phases = HubFixture.routes.phases
        // Cross the sampler interval after drain to catch a late progress callback.
        try await Task.sleep(for: .milliseconds(150))
        #expect(HubFixture.routes.phases == phases)
    }
}

private struct HubFixture {
    static let routes = HubRoutes()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let snapshot: QwenSnapshot
    let session: URLSession
    let client: HubClient
    var filePaths: [String] { snapshot.files.map { "/test/model/resolve/\(snapshot.revision)/\($0.file)" } }

    init(corrupt: Bool = false, missing: Bool = false, hold: Bool = false) throws {
        let revision = "1234567890123456789012345678901234567890"
        let bodies = ["model.safetensors": Data("public fixture weights".utf8),
                      "config.json": Data("{}".utf8), "generation_config.json": Data("{}\n".utf8)]
        snapshot = QwenSnapshot(repo: "test/model", revision: revision,
            files: bodies.map { .init(file: $0.key, bytes: Int64($0.value.count), sha256: digest($0.value)) },
            tokenizer: try QwenSnapshot.bundled().tokenizer)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HubFixtureProtocol.self]
        session = URLSession(configuration: configuration)
        client = HubClient(session: session, host: URL(string: "https://qwen-fixture.invalid")!, bearerToken: nil, cache: nil)
        var responses = Dictionary(uniqueKeysWithValues: bodies.map {
            ("/test/model/resolve/\(revision)/\($0.key)", $0.value)
        })
        let tree = bodies.map { ["path": $0.key, "type": "file", "oid": "fixture", "size": $0.value.count] as [String: Any] }
        responses["/api/models/test/model/tree/\(revision)"] = try JSONSerialization.data(withJSONObject: tree)
        if corrupt { responses["/test/model/resolve/\(revision)/model.safetensors"] = Data(repeating: 0, count: bodies["model.safetensors"]!.count) }
        if missing { responses.removeValue(forKey: "/test/model/resolve/\(revision)/model.safetensors") }
        Self.routes.setResponses(responses, hold: hold)
    }

    func store() -> QwenModelStore {
        QwenModelStore(root: root, snapshot: snapshot) { [client] snapshot, directory, progress in
            try await QwenModelStore.downloadFiles(snapshot, to: directory, client: client, progress: progress)
        }
    }

    func cleanUp() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class HubRoutes: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Data] = [:]
    private var seen: [URLRequest] = []
    private var progress: [QwenDownloadProgress.Phase] = []
    private var hold = false
    private var held = 0
    private var stopped = 0
    var requests: [URLRequest] { lock.withLock { seen } }
    var phases: [QwenDownloadProgress.Phase] { lock.withLock { progress } }
    var heldCount: Int { lock.withLock { held } }
    var stoppedCount: Int { lock.withLock { stopped } }
    func record(_ value: QwenDownloadProgress) { lock.withLock { progress.append(value.phase) } }
    func setResponses(_ values: [String: Data], hold: Bool = false) {
        lock.withLock { responses = values; seen = []; progress = []; self.hold = hold; held = 0; stopped = 0 }
    }
    func holdTransfer(_ request: URLRequest) -> Bool {
        lock.withLock {
            guard hold, request.url?.lastPathComponent == "model.safetensors" else { return false }
            seen.append(request)
            held += 1
            return true
        }
    }
    func stoppedTransfer() { lock.withLock { stopped += 1 } }
    func response(for request: URLRequest) throws -> Data {
        try lock.withLock {
            seen.append(request)
            guard request.url?.host == "qwen-fixture.invalid", request.httpMethod == "GET",
                  let path = request.url?.path, let data = responses[path] else {
                throw URLError(.resourceUnavailable)
            }
            return data
        }
    }
}

private final class HubFixtureProtocol: URLProtocol {
    private let stateLock = NSLock()
    private var held = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if stateLock.withLock({
            held = HubFixture.routes.holdTransfer(request)
            return held
        }) { return }
        do {
            let data = try HubFixture.routes.response(for: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {
        stateLock.withLock {
            if held { HubFixture.routes.stoppedTransfer(); held = false }
        }
    }
}
