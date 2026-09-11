import Foundation
import MLX
import MLXAudioSTT
import MLXLMCommon

struct QwenInferenceContext: Sendable {
    let sessionID: UUID
    let decodeID: UUID
    let acceptedPredecessorID: UUID?
    let isFinal: Bool
}

// Access follows the runtime's single native owner; no tensor crosses the actor boundary.
final class QwenInferenceReuse {
    private struct Identity: Equatable {
        let indices: [Int]
        let shape: [Int]
        let strides: [Int]
        let dtype: String
        let inputBits: [UInt32]
        let melBits: [[UInt32]]
        let anchor: UInt32
        let padding: Int
    }
    private struct Group {
        let identity: Identity
        let output: MLXArray
        let outputBits: [UInt32]
    }
    private struct Seed {
        let sessionID: UUID
        let decodeID: UUID
        var groups: [Group]
        var decoder: DecoderSeed? = nil
    }
    private struct PendingDecoder {
        let ids: [Int]
        let embeddings: MLXArray
        let cache: [KVCache]
    }
    private struct DecoderSeed {
        let ids: [Int]
        let width: Int
        let dtype: String
        let inputBits: [UInt32]
        let cache: [KVCache]
    }
    private var accepted: Seed?
    private var provisional: Seed?
    private var current: Seed?
    private var context: QwenInferenceContext?
    private var pendingDecoder: PendingDecoder?
    private var decoderEligible = false
    private(set) var hits = 0
    private(set) var reusedDecoderTokens = 0

    func begin(_ context: QwenInferenceContext?, samples: Int) {
        self.context = context
        current = nil
        pendingDecoder = nil
        decoderEligible = samples >= 128_040
        hits = 0
        reusedDecoderTokens = 0
        guard let context else { discard(); return }
        if let provisional, provisional.sessionID == context.sessionID,
           provisional.decodeID == context.acceptedPredecessorID {
            accepted = provisional
        }
        provisional = nil
        if accepted?.sessionID != context.sessionID || accepted?.decodeID != context.acceptedPredecessorID {
            accepted = nil
        }
        if !context.isFinal {
            current = Seed(sessionID: context.sessionID, decodeID: context.decodeID, groups: [])
        }
    }

    // Called after the actual stream drain, even when decoding throws.
    func complete(_ result: QwenDecodeResult?) {
        defer { current = nil; context = nil; pendingDecoder = nil; decoderEligible = false }
        guard let context else { return }
        if context.isFinal { accepted = nil; provisional = nil; return }
        if let result, case .eos = result.termination {
            if let pendingDecoder, let input = bits(pendingDecoder.embeddings) {
                current?.decoder = DecoderSeed(ids: pendingDecoder.ids,
                    width: pendingDecoder.embeddings.dim(2),
                    dtype: String(describing: pendingDecoder.embeddings.dtype),
                    inputBits: input, cache: pendingDecoder.cache)
            }
            provisional = current
        }
    }

    func discard() {
        accepted = nil; provisional = nil; current = nil; context = nil
        pendingDecoder = nil; decoderEligible = false
    }

    var shouldPrepareDecoderInput: Bool {
        guard let context else { return false }
        return context.isFinal ? accepted?.decoder != nil : decoderEligible
    }

    // The existing owner captures bits only after the live inference has drained.
    func recordDecoderInput(ids: [Int], embeddings: MLXArray, cache: [KVCache]) {
        guard decoderEligible, current != nil, embeddings.ndim == 3,
              embeddings.dim(0) == 1, embeddings.dim(1) == ids.count,
              embeddings.dim(2) > 0 else { return }
        pendingDecoder = PendingDecoder(ids: ids, embeddings: embeddings, cache: cache)
    }

    func prepareDecoderCache(ids: [Int], embeddings: MLXArray, promptCount: Int) throws
        -> (cache: [KVCache], reused: Int)? {
        guard context?.isFinal == true, let seed = accepted?.decoder else { return nil }
        accepted?.decoder = nil
        guard embeddings.ndim == 3, embeddings.dim(0) == 1,
              embeddings.dim(1) == ids.count, embeddings.dim(2) == seed.width,
              String(describing: embeddings.dtype) == seed.dtype,
              promptCount > 0, promptCount <= ids.count,
              let input = bits(embeddings) else { return nil }
        let limit = min(seed.ids.count, promptCount - 1)
        var retained = 0
        for row in 0..<limit {
            let range = (row * seed.width)..<((row + 1) * seed.width)
            guard ids[row] == seed.ids[row],
                  input[range].elementsEqual(seed.inputBits[range]) else { break }
            retained += 1
        }
        guard retained > 0 else { return nil }
        // Never carry generated text or changed audio positions into the final suffix.
        guard !seed.cache.isEmpty, seed.cache.allSatisfy({
            $0.isTrimmable && $0.offset >= seed.ids.count
        }) else { throw QwenDecodeError.invalidDecoderCache }
        for entry in seed.cache {
            let remove = entry.offset - retained
            guard entry.trim(remove) == remove, entry.offset == retained else {
                throw QwenDecodeError.invalidDecoderCache
            }
        }
        reusedDecoderTokens = retained
        return (seed.cache, retained)
    }

    func install(model: Qwen3ASRModel, features: MLXArray, samples: Int) {
        guard let context, samples >= 128_040 else {
            model.setTransformerBatchReuse(lookup: nil, store: nil)
            return
        }
        if context.isFinal {
            guard let accepted, !accepted.groups.isEmpty else {
                model.setTransformerBatchReuse(lookup: nil, store: nil)
                return
            }
            model.setTransformerBatchReuse(lookup: { [self] batch, indices in
                guard let key = identity(batch, indices: indices, features: features, samples: samples),
                      let group = accepted.groups.first(where: { $0.identity == key }),
                      bits(group.output) == group.outputBits else { return nil }
                hits += 1
                return group.output
            }, store: nil)
        } else {
            model.setTransformerBatchReuse(lookup: nil, store: { [self] batch, indices, output in
                guard let key = identity(batch, indices: indices, features: features, samples: samples),
                      let original = bits(output) else { return }
                let copy = MLXArray(original.map { Float(bitPattern: $0) }).reshaped(output.shape).asType(output.dtype)
                eval(copy)
                guard bits(copy) == original else { return }
                current?.groups.append(Group(identity: key, output: copy, outputBits: original))
            })
        }
    }

    private func bits(_ value: MLXArray) -> [UInt32]? {
        guard [.float32, .float16, .bfloat16].contains(value.dtype) else { return nil }
        let values = value.asType(.float32).asArray(Float.self)
        guard values.allSatisfy(\.isFinite) else { return nil }
        return values.map(\.bitPattern)
    }

    private func identity(_ batch: MLXArray, indices: [Int], features: MLXArray, samples: Int) -> Identity? {
        eval(batch, features)
        guard let input = bits(batch), let mel = bits(features), features.shape.count == 3,
              features.dim(0) == 1, features.dim(1) == 128 else { return nil }
        let frames = features.dim(2)
        // Whole groups only; a reflected or incomplete tail invalidates the group.
        guard indices.allSatisfy({ $0 >= 0 && ($0 + 1) * 800 <= frames && samples >= 128_000 * ($0 + 1) + 40 }) else { return nil }
        var windows: [[UInt32]] = []
        for index in indices {
            var window: [UInt32] = []
            for band in 0..<128 {
                let start = band * frames + index * 800
                window.append(contentsOf: mel[start..<(start + 800)])
            }
            windows.append(window)
        }
        let anchor = features.max().item(Float.self)
        guard anchor.isFinite else { return nil }
        return Identity(indices: indices, shape: batch.shape, strides: batch.strides,
                        dtype: String(describing: batch.dtype), inputBits: input, melBits: windows,
                        anchor: anchor.bitPattern, padding: min(100, frames))
    }
}
