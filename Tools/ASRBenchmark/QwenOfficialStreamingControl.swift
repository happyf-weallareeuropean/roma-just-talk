// Official cumulative-audio / suffix-rollback policy executed through native public APIs.
// Reference: QwenLM/Qwen3-ASR 7c6daf77a2421100f5fb066495372c00129d39ff (Apache-2.0).
import Foundation
import MLX
import MLXAudioSTT

extension QwenNativeProbe {
    struct OfficialPass: Sendable {
        let index: Int
        let audioSamples: Int
        let finalTail: Bool
        let prefix: String
        let generated: String
        let rawText: String
        let generationTokens: Int
        let seconds: Double
        let completedSeconds: Double
        let displayText: String
        let termination: String
    }

    struct OfficialMeasurement: Sendable {
        let measurement: StreamMeasurement
        let language: String?
        let passes: [OfficialPass]
    }

    nonisolated static func officialStream(model: Qwen3ASRModel, samples: [Float], chunkSamples: Int = 32_000) async throws -> OfficialMeasurement {
        guard let tokenizer = model.tokenizer else { throw NSError(domain: "QwenOfficialControl", code: 1) }
        var policy = QwenOfficialStreamingPolicy(chunkSamples: chunkSamples)
        var passes: [OfficialPass] = []
        var displayTimes: [Double] = []
        let begin = ProcessInfo.processInfo.systemUptime
        let release = begin + Double(samples.count) / 16_000

        func decode(_ audio: [Float], finalTail: Bool) throws {
            try Task.checkCancellation()
            let prefix = policy.prefix(finalTail: finalTail,
                encode: { tokenizer.encode(text: $0) }, decode: { tokenizer.decode(tokens: $0) })
            let start = ProcessInfo.processInfo.systemUptime
            let result = try officialDecode(model: model, samples: audio, prefix: prefix)
            let index = policy.passIndex
            policy.accept(prefix: prefix, generated: result.text)
            passes.append(OfficialPass(index: index, audioSamples: audio.count, finalTail: finalTail,
                prefix: prefix, generated: result.text, rawText: policy.rawDecoded,
                generationTokens: result.tokens, seconds: ProcessInfo.processInfo.systemUptime - start,
                completedSeconds: ProcessInfo.processInfo.systemUptime - begin,
                displayText: QwenOfficialStreamingPolicy.output(policy.rawDecoded).text, termination: result.termination))
            if !QwenOfficialStreamingPolicy.output(policy.rawDecoded).text.isEmpty {
                displayTimes.append(ProcessInfo.processInfo.systemUptime)
            }
        }

        for offset in stride(from: 0, to: samples.count, by: 1280) {
            let end = min(offset + 1280, samples.count)
            let wait = begin + Double(end) / 16_000 - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            policy.append(Array(samples[offset..<end]))
            while let audio = policy.takeAudio() { try decode(audio, finalTail: false) }
        }
        let stop = ProcessInfo.processInfo.systemUptime
        if let audio = policy.takeAudio(finalTail: true) { try decode(audio, finalTail: true) }
        let end = ProcessInfo.processInfo.systemUptime
        let output = QwenOfficialStreamingPolicy.output(policy.rawDecoded)
        let liveTimes = displayTimes.filter { $0 < release }
        return OfficialMeasurement(measurement: StreamMeasurement(text: output.text,
            finalization: end - release, stopFinalization: end - stop,
            firstPartial: liveTimes.first.map { $0 - begin }, partialCount: liveTimes.count,
            feedOverrun: max(0, stop - release)), language: output.language, passes: passes)
    }

    nonisolated static func officialDecode(model: Qwen3ASRModel, samples: [Float], prefix: String) throws -> (text: String, tokens: Int, termination: String) {
        guard let tokenizer = model.tokenizer else { throw NSError(domain: "QwenOfficialControl", code: 1) }
        let (features, mask, count) = model.preprocessAudio(MLXArray(samples))
        let base = model.buildPrompt(numAudioTokens: count, language: nil).asArray(Int32.self).map(Int.init)
        let prompt = tokenizer.decode(tokens: base, skipSpecialTokens: false)
        guard tokenizer.encode(text: prompt) == base else {
            throw NSError(domain: "QwenOfficialControl", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Tokenizer prompt round-trip mismatch; cannot claim faithful prefix composition."])
        }
        // Re-tokenize the complete prompt plus prefix, preserving possible BPE boundary merges.
        let ids = MLXArray(tokenizer.encode(text: prompt + prefix).map(Int32.init)).expandedDimensions(axis: 0)
        let cache = model.makeCache()
        var logits = model(inputIds: ids, inputFeatures: features, featureAttentionMask: mask, cache: cache)
        eval(logits)
        var generated: [Int] = []
        var termination = "max_tokens"
        for _ in 0..<256 {
            try Task.checkCancellation()
            let token = logits[0..., -1, 0...].argMax(axis: -1).item(Int.self)
            if token == 151645 || token == 151643 { termination = "eos_\(token)"; break }
            generated.append(token)
            if generated.count == 256 { break }
            logits = model(inputIds: MLXArray([Int32(token)]).expandedDimensions(axis: 0), cache: cache)
            eval(logits)
        }
        let text = tokenizer.decode(tokens: generated)
        Memory.clearCache()
        return (text, generated.count, termination)
    }
}
