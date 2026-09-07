import CryptoKit
import Foundation
import Testing
@testable import VoiceInkQwen

@Test func tokenizerMatchesEveryPinnedTokenAndMerge() throws {
    let snapshot = try QwenSnapshot.bundled()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try snapshot.copyTokenizer(to: directory)
    try snapshot.tokenizer.verify(at: directory)
    let tokenizer = try json(directory.appendingPathComponent("tokenizer.json"))
    let model = try #require(tokenizer["model"] as? [String: Any])
    let vocab = try #require(model["vocab"] as? [String: Int])
    let merges = try #require(model["merges"] as? [String])
    let fixtureRoot = try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
    let reference = try json(fixtureRoot.appendingPathComponent("tokenizer-semantics.json"))
    let vocabRows = vocab.sorted { $0.value < $1.value }.map { ($0.key, Optional($0.value)) }
    #expect(vocab.count == reference["vocab_count"] as? Int)
    #expect(semanticHash(vocabRows) == reference["vocab_sha256"] as? String)
    #expect(merges.count == reference["merges_count"] as? Int)
    #expect(semanticHash(merges.map { ($0, nil) }) == reference["ordered_merges_sha256"] as? String)

    let config = try json(fixtureRoot.appendingPathComponent("tokenizer_config.json"))
    let sourceTokens = try #require(config["added_tokens_decoder"] as? [String: [String: Any]])
    let generatedTokens = try #require(tokenizer["added_tokens"] as? [[String: Any]])
    #expect(sourceTokens.count == generatedTokens.count)
    for token in generatedTokens {
        let id = try #require(token["id"] as? Int)
        let original = try #require(sourceTokens[String(id)])
        #expect(token["content"] as? String == original["content"] as? String)
        for key in ["single_word", "lstrip", "rstrip", "normalized", "special"] {
            #expect(token[key] as? Bool == (original[key] as? Bool ?? false))
        }
    }
    // Known-bad semantic controls must fail the same complete-map/order checks.
    var changedIDs = vocabRows
    changedIDs[0].1 = (changedIDs[0].1 ?? 0) + 1
    #expect(semanticHash(changedIDs) != reference["vocab_sha256"] as? String)
    var changedOrder = merges
    changedOrder.swapAt(0, 1)
    #expect(semanticHash(changedOrder.map { ($0, nil) }) != reference["ordered_merges_sha256"] as? String)
}

@Test func cacheRejectsSameSizeCorruptionAndUnlistedWeights() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = Data("valid".utf8)
    let weights = QwenSnapshot.File(file: "model.safetensors", bytes: 5, sha256: digest(data))
    try data.write(to: directory.appendingPathComponent(weights.file))
    try weights.verify(at: directory)
    try Data("wrong".utf8).write(to: directory.appendingPathComponent(weights.file))
    #expect(throws: QwenRuntimeError.self) { try weights.verify(at: directory) }
    try data.write(to: directory.appendingPathComponent(weights.file))
    let snapshot = QwenSnapshot(repo: "test/model", revision: "fixture", files: [weights], tokenizer: weights)
    try snapshot.verify(at: directory, includingTokenizer: false)
    try data.write(to: directory.appendingPathComponent("unexpected.safetensors"))
    #expect(throws: QwenRuntimeError.self) { try snapshot.verify(at: directory, includingTokenizer: false) }
}

private func json(_ url: URL) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func semanticHash(_ rows: [(String, Int?)]) -> String {
    var hash = SHA256()
    for (text, id) in rows {
        let data = Data(text.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
        hash.update(data: data)
        if let id {
            var value = UInt64(id).bigEndian
            withUnsafeBytes(of: &value) { hash.update(data: Data($0)) }
        }
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
