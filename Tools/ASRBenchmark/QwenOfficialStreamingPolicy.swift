// Swift benchmark adaptation of QwenLM/Qwen3-ASR streaming state.
// Copyright 2026 The Alibaba Qwen team. SPDX-License-Identifier: Apache-2.0
// Source: 7c6daf77a2421100f5fb066495372c00129d39ff, qwen_asr/inference/qwen3_asr.py.
// Licensed under https://www.apache.org/licenses/LICENSE-2.0 (AS IS, no warranties).
import Foundation

struct QwenOfficialStreamingPolicy {
    static let sourceRevision = "7c6daf77a2421100f5fb066495372c00129d39ff"
    let chunkSamples: Int
    private(set) var accumulatedAudio: [Float] = []
    private var pendingAudio: [Float] = []
    private(set) var passIndex = 0
    private(set) var rawDecoded = ""

    init(chunkSamples: Int = 32_000) {
        precondition(chunkSamples > 0)
        self.chunkSamples = chunkSamples
    }

    mutating func append(_ packet: [Float]) { pendingAudio.append(contentsOf: packet) }

    /// Every pass owns the same utterance start; no independently appended windows.
    mutating func takeAudio(finalTail: Bool = false) -> [Float]? {
        let count: Int
        if finalTail {
            guard !pendingAudio.isEmpty else { return nil }
            count = pendingAudio.count
        } else {
            guard pendingAudio.count >= chunkSamples else { return nil }
            count = chunkSamples
        }
        accumulatedAudio.append(contentsOf: pendingAudio.prefix(count))
        pendingAudio.removeFirst(count)
        return accumulatedAudio
    }

    func prefix(
        finalTail: Bool,
        encode: (String) -> [Int],
        decode: ([Int]) -> String
    ) -> String {
        guard passIndex >= 2 else { return "" }
        let ids = encode(rawDecoded)
        if finalTail {
            // Preserve the official final-tail difference, including its Unicode limitation.
            return decode(Array(ids.prefix(max(1, ids.count - 5))))
        }
        var rollback = 5
        while true {
            let count = max(0, ids.count - rollback)
            let prefix = count > 0 ? decode(Array(ids.prefix(count))) : ""
            if !prefix.contains("\u{fffd}") || count == 0 { return prefix }
            rollback += 1
        }
    }

    mutating func accept(prefix: String, generated: String) {
        rawDecoded = prefix + generated
        passIndex += 1
    }

    /// Official display grammar, deliberately without its global repetition cleaner.
    static func output(_ raw: String) -> (language: String?, text: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = text.range(of: "<asr_text>") else { return (nil, text) }
        let metadata = String(text[..<marker.lowerBound])
        let body = text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if metadata.lowercased().contains("language none") { return (nil, body) }
        for line in metadata.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("language ") {
                let name = line.dropFirst("language ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = name.prefix(1).uppercased() + name.dropFirst().lowercased()
                return (normalized.isEmpty ? nil : normalized, body)
            }
        }
        return (nil, body)
    }
}
