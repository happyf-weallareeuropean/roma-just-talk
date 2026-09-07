// Adapted from QwenLM/Qwen3-ASR streaming state; Copyright 2026 The Alibaba Qwen team.
// SPDX-License-Identifier: Apache-2.0. Full license: Resources/Apache-2.0-LICENSE.txt.
// Source revision: 7c6daf77a2421100f5fb066495372c00129d39ff.
import Foundation

/// Cumulative audio and raw suffix replacement. Display parsing never mutates this state.
public struct QwenStreamingPolicy {
    public static let sourceRevision = "7c6daf77a2421100f5fb066495372c00129d39ff"
    public let chunkSamples: Int
    public private(set) var accumulatedAudio: [Float] = []
    private var pendingAudio: [Float] = []
    public private(set) var passIndex = 0
    public private(set) var rawDecoded = ""

    public init(chunkSamples: Int = 32_000) {
        precondition(chunkSamples > 0)
        self.chunkSamples = chunkSamples
    }

    public mutating func append(_ packet: [Float]) { pendingAudio.append(contentsOf: packet) }

    public mutating func takeAudio(finalTail: Bool = false) -> [Float]? {
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

    public func prefix(
        finalTail: Bool,
        encode: (String) -> [Int],
        decode: ([Int]) -> String
    ) -> String {
        guard passIndex >= 2 else { return "" }
        let ids = encode(rawDecoded)
        if finalTail {
            // Preserve the official tail rule, including its incomplete-Unicode limitation.
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

    public mutating func accept(prefix: String, generated: String) {
        rawDecoded = prefix + generated
        passIndex += 1
    }
}
