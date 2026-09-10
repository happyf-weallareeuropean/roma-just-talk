import Foundation
import MLX
import MLXAudioSTT

struct QwenEncoderContext: Sendable {
    let sessionID: UUID
    let decodeID: UUID
    let acceptedPredecessorID: UUID?
    let isFinal: Bool
}

// Access follows the runtime's single native owner; no tensor crosses the actor boundary.
final class QwenEncoderReuse {
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
    }
    private var accepted: Seed?
    private var provisional: Seed?
    private var current: Seed?
    private var context: QwenEncoderContext?
    private(set) var hits = 0

    func begin(_ context: QwenEncoderContext?) {
        self.context = context
        current = nil
        hits = 0
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
        defer { current = nil; context = nil }
        guard let context else { return }
        if context.isFinal { accepted = nil; provisional = nil; return }
        if let result, case .eos = result.termination { provisional = current }
    }

    func discard() {
        accepted = nil; provisional = nil; current = nil; context = nil
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
