import Foundation
import MLX
import MLXAudioSTT

public enum QwenDecodeTermination: Equatable, Sendable {
    case eos(Int)
    case tokenLimit
}

public struct QwenDecodeResult: Sendable {
    public let generatedText: String
    public let generationTokens: Int
    public let termination: QwenDecodeTermination
    var reusedEncoderBatches = 0
}

public enum QwenDecodeError: Error, Sendable {
    case invalidAudio
    case invalidTokenLimit
    case tokenizerUnavailable
    case promptRoundTripMismatch
}

/// Raw greedy decoding shared by complete-audio transcription and cumulative streaming.
/// The caller owns serial model access, the task-local Metal stream and its final drain.
public enum QwenGreedyDecoder {
    public static func decode(
        model: Qwen3ASRModel,
        samples: [Float],
        prefix: String = "",
        language: String? = nil,
        maxTokens: Int = 256
    ) throws -> QwenDecodeResult {
        try decodeBody(model: model, samples: samples, prefix: prefix,
                       language: language, maxTokens: maxTokens, disposeCache: { Memory.clearCache() })
    }

    // Runtime ownership extends through the GPU drain and the subsequent cache disposal.
    static func decodeRetainingCache(
        model: Qwen3ASRModel,
        samples: [Float],
        prefix: String = "",
        language: String? = nil,
        maxTokens: Int = 256,
        encoderReuse: QwenEncoderReuse? = nil
    ) throws -> QwenDecodeResult {
        try decodeBody(model: model, samples: samples, prefix: prefix,
                       language: language, maxTokens: maxTokens, encoderReuse: encoderReuse, disposeCache: {})
    }

    private static func decodeBody(
        model: Qwen3ASRModel, samples: [Float], prefix: String, language: String?,
        maxTokens: Int, encoderReuse: QwenEncoderReuse? = nil, disposeCache: () -> Void
    ) throws -> QwenDecodeResult {
        try Task.checkCancellation()
        // The centered frontend reflects 200 samples; reject unsupported tiny inputs.
        guard samples.count > 200, samples.allSatisfy(\.isFinite) else {
            throw QwenDecodeError.invalidAudio
        }
        guard maxTokens > 0 else { throw QwenDecodeError.invalidTokenLimit }
        guard let tokenizer = model.tokenizer else { throw QwenDecodeError.tokenizerUnavailable }
        defer { model.setTransformerBatchReuse(lookup: nil, store: nil); disposeCache() }

        let checkpoint: (String) throws -> Void = { _ in try Task.checkCancellation() }
        try Task.checkCancellation()
        let (features, mask, count) = model.preprocessAudio(MLXArray(samples))
        encoderReuse?.install(model: model, features: features, samples: samples.count)
        try Task.checkCancellation()
        let base = model.buildPrompt(numAudioTokens: count, language: language)
            .asArray(Int32.self).map(Int.init)
        let prompt = tokenizer.decode(tokens: base, skipSpecialTokens: false)
        guard tokenizer.encode(text: prompt) == base else {
            throw QwenDecodeError.promptRoundTripMismatch
        }
        // Retokenize the whole prompt; independently tokenized fragments can merge differently.
        let ids = MLXArray(tokenizer.encode(text: prompt + prefix).map(Int32.init))
            .expandedDimensions(axis: 0)
        try Task.checkCancellation()
        let cache = model.makeCache()
        var logits = try model(inputIds: ids, inputFeatures: features, featureAttentionMask: mask,
            cache: cache, checkpoint: checkpoint)
        try Task.checkCancellation()
        eval(logits)
        try Task.checkCancellation()
        var generated: [Int] = []
        var termination = QwenDecodeTermination.tokenLimit
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            let token = logits[0..., -1, 0...].argMax(axis: -1).item(Int.self)
            if token == 151645 || token == 151643 {
                termination = .eos(token)
                break
            }
            generated.append(token)
            if generated.count == maxTokens { break }
            logits = try model(inputIds: MLXArray([Int32(token)]).expandedDimensions(axis: 0),
                cache: cache, checkpoint: checkpoint)
            try Task.checkCancellation()
            eval(logits)
            try Task.checkCancellation()
        }
        // A reached output cap is terminal, even if release supersedes this pass.
        // Cancellation before reaching the cap is still checked inside the loop.
        if case .eos = termination { try Task.checkCancellation() }
        return QwenDecodeResult(generatedText: tokenizer.decode(tokens: generated),
            generationTokens: generated.count, termination: termination, reusedEncoderBatches: encoderReuse?.hits ?? 0)
    }
}
