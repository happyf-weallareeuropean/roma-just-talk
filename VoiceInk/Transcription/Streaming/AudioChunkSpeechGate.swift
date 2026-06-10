import Foundation

protocol SpeechActivityDetecting: Sendable {
    func containsSpeech(inPCM16LEData data: Data) -> Bool
}

final class AudioChunkSpeechGate: @unchecked Sendable {
    private let detector: any SpeechActivityDetecting
    private let leadInChunkCount: Int
    private let trailingSilenceChunkCount: Int
    private var leadInBuffer: [Data] = []
    private var trailingSilenceBudget = 0

    init(
        detector: any SpeechActivityDetecting,
        leadInChunkCount: Int = 5,
        trailingSilenceChunkCount: Int = 3
    ) {
        self.detector = detector
        self.leadInChunkCount = max(0, leadInChunkCount)
        self.trailingSilenceChunkCount = max(0, trailingSilenceChunkCount)
    }

    func accept(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else { return [] }

        if detector.containsSpeech(inPCM16LEData: chunk) {
            let buffered = leadInBuffer
            leadInBuffer.removeAll(keepingCapacity: true)
            trailingSilenceBudget = trailingSilenceChunkCount
            return buffered + [chunk]
        }

        if trailingSilenceBudget > 0 {
            trailingSilenceBudget -= 1
            return [chunk]
        }

        guard leadInChunkCount > 0 else { return [] }

        leadInBuffer.append(chunk)
        if leadInBuffer.count > leadInChunkCount {
            leadInBuffer.removeFirst(leadInBuffer.count - leadInChunkCount)
        }
        return []
    }
}
