import Foundation
import MLX
import MLXLMCommon
import Testing
@testable import VoiceInkQwen

@Suite(.serialized)
struct QwenInferenceReuseTests {
    private let samples = 128_040
    private func embeddings(_ values: [Float]) -> MLXArray {
        MLXArray(values).reshaped(1, values.count / 4, 4)
    }
    private func cache(_ count: Int, layers: Int = 2) -> [KVCache] {
        (0..<layers).map { layer in
            let entry = KVCacheSimple()
            let values = MLXArray((0..<(count * 4)).map { Float($0 + layer * 1000) })
                .reshaped(1, 1, count, 4)
            let (keys, output) = entry.update(keys: values, values: values + 100)
            eval(keys, output)
            return entry
        }
    }
    private func result(_ termination: QwenDecodeTermination) -> QwenDecodeResult {
        QwenDecodeResult(generatedText: "words", generationTokens: 2, termination: termination)
    }
    private func completedSeed(_ reuse: QwenInferenceReuse, session: UUID, decode: UUID,
                               values: [Float], ids: [Int], predecessor: UUID? = nil,
                               termination: QwenDecodeTermination = .eos(151645)) {
        reuse.begin(.init(sessionID: session, decodeID: decode,
                          acceptedPredecessorID: predecessor, isFinal: false), samples: samples)
        reuse.recordDecoderInput(ids: ids, embeddings: embeddings(values), cache: cache(ids.count + 3))
        reuse.complete(result(termination))
    }

    @Test func changedInputTrimsEveryLayerAndDropsGeneratedSuffix() throws {
        try Device.withDefaultDevice(.cpu) {
            let reuse = QwenInferenceReuse(), session = UUID(), decode = UUID()
            let values = (0..<32).map(Float.init), ids = Array(1...8)
            completedSeed(reuse, session: session, decode: decode, values: values, ids: ids)
            reuse.begin(.init(sessionID: session, decodeID: UUID(),
                              acceptedPredecessorID: decode, isFinal: true), samples: samples + 5600)
            var changed = values; changed[4 * 5] += 1
            let candidate = try reuse.prepareDecoderCache(ids: ids,
                embeddings: embeddings(changed), promptCount: ids.count)
            let prepared = try #require(candidate)
            #expect(prepared.reused == 5)
            #expect(reuse.reusedDecoderTokens == 5)
            for (layer, entry) in prepared.cache.enumerated() {
                #expect(entry.offset == 5)
                #expect(entry.state[0].asArray(Float.self) == (0..<20).map { Float($0 + layer * 1000) })
                // Updating the suffix must overwrite old generated positions, retaining the prefix.
                let next = MLXArray.ones([1, 1, 2, 4]) * -1
                let (keys, values) = entry.update(keys: next, values: next)
                eval(keys, values)
                #expect(entry.offset == 7)
                #expect(Array(keys.asArray(Float.self).suffix(8)) == Array(repeating: -1, count: 8))
            }
            let consumed = try reuse.prepareDecoderCache(ids: ids, embeddings: embeddings(changed), promptCount: 8)
            #expect(consumed == nil)
        }
    }

    @Test(arguments: [false, true])
    func cancelledOrCappedLiveWorkCannotReplaceAcceptedSeed(capped: Bool) throws {
        try Device.withDefaultDevice(.cpu) {
            let reuse = QwenInferenceReuse(), session = UUID(), accepted = UUID()
            let values = (0..<32).map(Float.init), ids = Array(1...8)
            completedSeed(reuse, session: session, decode: accepted, values: values, ids: ids)
            reuse.begin(.init(sessionID: session, decodeID: UUID(),
                              acceptedPredecessorID: accepted, isFinal: false), samples: samples + 5600)
            reuse.recordDecoderInput(ids: ids, embeddings: embeddings(values.map { $0 + 100 }), cache: cache(11))
            reuse.complete(capped ? result(.tokenLimit) : nil)
            reuse.begin(.init(sessionID: session, decodeID: UUID(),
                              acceptedPredecessorID: accepted, isFinal: true), samples: samples + 5700)
            let candidate = try reuse.prepareDecoderCache(ids: ids,
                embeddings: embeddings(values), promptCount: 8)
            let prepared = try #require(candidate)
            #expect(prepared.reused == 7)
            #expect(prepared.cache.allSatisfy { $0.offset == 7 })
        }
    }

    @Test(arguments: ["session", "predecessor", "discard", "short"])
    func invalidOwnershipAndShortInputKeepFreshDecode(reason: String) throws {
        try Device.withDefaultDevice(.cpu) {
            let reuse = QwenInferenceReuse(), session = UUID(), decode = UUID()
            let values = (0..<32).map(Float.init), ids = Array(1...8)
            reuse.begin(.init(sessionID: session, decodeID: decode,
                              acceptedPredecessorID: nil, isFinal: false), samples: reason == "short" ? 128_039 : samples)
            #expect(reuse.shouldPrepareDecoderInput == (reason != "short"))
            reuse.recordDecoderInput(ids: ids, embeddings: embeddings(values), cache: cache(11))
            reuse.complete(result(.eos(151645)))
            if reason == "discard" { reuse.discard() }
            reuse.begin(.init(sessionID: reason == "session" ? UUID() : session, decodeID: UUID(),
                              acceptedPredecessorID: reason == "predecessor" ? UUID() : decode,
                              isFinal: true), samples: samples + 5600)
            #expect(!reuse.shouldPrepareDecoderInput)
            let candidate = try reuse.prepareDecoderCache(ids: ids, embeddings: embeddings(values), promptCount: 8)
            #expect(candidate == nil)
        }
    }

    @Test(arguments: ["first-embedding", "first-token", "interior-token", "unchanged"])
    func exactIdentityAndFinalLogitBoundary(change: String) throws {
        try Device.withDefaultDevice(.cpu) {
            let reuse = QwenInferenceReuse(), session = UUID(), decode = UUID()
            var values = (0..<32).map(Float.init), ids = Array(1...8)
            completedSeed(reuse, session: session, decode: decode, values: values, ids: ids)
            reuse.begin(.init(sessionID: session, decodeID: UUID(),
                              acceptedPredecessorID: decode, isFinal: true), samples: samples + 5600)
            if change == "first-embedding" { values[0] += 1 }
            if change == "first-token" { ids[0] += 100 }
            if change == "interior-token" { ids[3] += 100 }
            let prepared = try reuse.prepareDecoderCache(ids: ids, embeddings: embeddings(values), promptCount: 8)
            if change.hasPrefix("first-") { #expect(prepared == nil) }
            else { #expect(prepared?.reused == (change == "unchanged" ? 7 : 3)) }
            reuse.complete(result(.eos(151645)))
            #expect(!reuse.shouldPrepareDecoderInput)
        }
    }
}
