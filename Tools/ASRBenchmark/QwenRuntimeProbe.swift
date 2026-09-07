import CryptoKit
import Foundation
import VoiceInkCore
import VoiceInkQwen

/// Exercises production queueing, presentation, event delivery and finish; never calls the decoder directly.
@main
struct QwenRuntimeProbe {
    struct Input: Codable, Sendable { let file: String; let sha256: String }
    enum PreRoll: String, Codable, Sendable { case none, silence, speechPrefix }
    struct Case: Codable, Sendable {
        let id: String
        let inputs: [Input]
        let preRoll: PreRoll
        let gapMilliseconds: Int
        let trailingSilenceMilliseconds: Int
        let packetSamples: [Int]
        let deliveryHoldMilliseconds: Int
        let tailHoldMilliseconds: Int
        let unloadBefore: Bool
        let prewarmBefore: Bool
    }
    struct Packet: Codable, Sendable {
        let startSample: Int
        let endSample: Int
        let availabilitySeconds: Double
        let appendStartedSeconds: Double
        let appendReturnedSeconds: Double
    }
    struct Event: Codable, Sendable {
        let kind: String
        let text: String
        let receivedSeconds: Double
    }
    struct Result: Encodable, Sendable {
        let event = "runtime_result"
        let specification: Case
        let referenceAudioSamples: Int
        let preRollSamples: Int
        let capturedSamples: Int
        let prewarmSeconds: Double
        let sessionReadySeconds: Double
        let nominalReleaseSeconds: Double
        let finishStartedSeconds: Double
        let finishReturnedSeconds: Double
        let finalEventSeconds: Double
        let packets: [Packet]
        let events: [Event]
        let text: String
    }
    enum ProbeError: Error { case usage, invalidCase, badAudio(String), badChecksum(String), noFinal, outputExists }

    nonisolated static func now() -> Double { ProcessInfo.processInfo.systemUptime }
    nonisolated static func samples(milliseconds: Int) -> Int { milliseconds * 16 }
    nonisolated static func wait(until deadline: Double) async throws {
        let remaining = deadline - now()
        if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
    }

    nonisolated static func run(_ specification: Case, relativeTo directory: URL, runtime: QwenRuntime) async throws -> Result {
        guard !specification.inputs.isEmpty, !specification.packetSamples.isEmpty,
              specification.packetSamples.allSatisfy({ (1...16_000).contains($0) }),
              [specification.gapMilliseconds, specification.trailingSilenceMilliseconds,
               specification.deliveryHoldMilliseconds, specification.tailHoldMilliseconds].allSatisfy({ (0...60_000).contains($0) }) else {
            throw ProbeError.invalidCase
        }
        var referenceAudio: [Float] = []
        for (index, input) in specification.inputs.enumerated() {
            let data = try Data(contentsOf: directory.appendingPathComponent(input.file))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == input.sha256 else { throw ProbeError.badChecksum(input.file) }
            guard let decoded = VoiceInkPCM16Audio.floatSamples(fromWAVData: data), !decoded.isEmpty else {
                throw ProbeError.badAudio(input.file)
            }
            if index > 0 { referenceAudio += [Float](repeating: 0, count: samples(milliseconds: specification.gapMilliseconds)) }
            referenceAudio += decoded
        }
        let preRollCapacity = VoiceInkPCM16Audio.sampleCount(forMono16kDuration: VoiceInkAudioPreRollPolicy.durationSeconds)
        let preRoll: [Float]
        var live: [Float]
        switch specification.preRoll {
        case .none: preRoll = []; live = referenceAudio
        case .silence: preRoll = [Float](repeating: 0, count: preRollCapacity); live = referenceAudio
        case .speechPrefix:
            let count = min(preRollCapacity, referenceAudio.count)
            preRoll = [Float](repeating: 0, count: preRollCapacity - count) + referenceAudio.prefix(count)
            live = Array(referenceAudio.dropFirst(count))
        }
        live += [Float](repeating: 0, count: samples(milliseconds: specification.trailingSilenceMilliseconds))
        if specification.unloadBefore { try await runtime.unload() }
        let preparation = now()
        if specification.prewarmBefore { try await runtime.prewarm() }
        let prewarmSeconds = now() - preparation
        let begin = now()
        let release = Double(live.count) / 16_000
        let session = try await runtime.startStreaming(language: nil)
        let ready = now() - begin
        let receiver = Task.detached { () throws -> [Event] in
            var events: [Event] = []
            for try await event in session.events {
                try Task.checkCancellation()
                let received = now() - begin
                switch event {
                case .partial(let text): events.append(Event(kind: "partial", text: text, receivedSeconds: received))
                case .final(let text): events.append(Event(kind: "final", text: text, receivedSeconds: received))
                }
            }
            return events
        }
        var packets: [Packet] = []
        do {
            // Pre-roll was already captured before key-down. Startup delay can also queue live packets.
            try await wait(until: begin + Double(specification.deliveryHoldMilliseconds) / 1000)
            let preRollPacket = VoiceInkPCM16Audio.sampleCount(forMono16kDuration: VoiceInkAudioPreRollPolicy.streamingChunkDurationSeconds)
            for offset in stride(from: 0, to: preRoll.count, by: preRollPacket) {
                let end = min(offset + preRollPacket, preRoll.count)
                let started = now() - begin
                try await runtime.appendAudio(Array(preRoll[offset..<end]), sessionID: session.id)
                packets.append(Packet(startSample: offset, endSample: end,
                    availabilitySeconds: Double(end - preRoll.count) / 16_000,
                    appendStartedSeconds: started, appendReturnedSeconds: now() - begin))
            }
            var offset = 0
            var packetIndex = 0
            while offset < live.count {
                let end = min(offset + specification.packetSamples[packetIndex % specification.packetSamples.count], live.count)
                let available = Double(end) / 16_000
                let tailBoundary = release - Double(specification.tailHoldMilliseconds) / 1000
                let delivery = specification.tailHoldMilliseconds > 0 && available > tailBoundary ? release : available
                try await wait(until: begin + delivery)
                let started = now() - begin
                try await runtime.appendAudio(Array(live[offset..<end]), sessionID: session.id)
                packets.append(Packet(startSample: preRoll.count + offset, endSample: preRoll.count + end,
                    availabilitySeconds: available, appendStartedSeconds: started, appendReturnedSeconds: now() - begin))
                offset = end
                packetIndex += 1
            }
            let finishStarted = now() - begin
            try await runtime.finishStreaming(sessionID: session.id)
            let finishReturned = now() - begin
            let events = try await receiver.value
            let finals = events.filter { $0.kind == "final" }
            guard finals.count == 1, let final = finals.first else { throw ProbeError.noFinal }
            return Result(specification: specification, referenceAudioSamples: referenceAudio.count,
                preRollSamples: preRoll.count, capturedSamples: preRoll.count + live.count,
                prewarmSeconds: prewarmSeconds, sessionReadySeconds: ready, nominalReleaseSeconds: release,
                finishStartedSeconds: finishStarted, finishReturnedSeconds: finishReturned,
                finalEventSeconds: final.receivedSeconds, packets: packets, events: events, text: final.text)
        } catch {
            try? await runtime.cancelStreaming(sessionID: session.id)
            receiver.cancel()
            _ = await receiver.result
            throw error
        }
    }

    nonisolated static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 else { throw ProbeError.usage }
        let matrixURL = URL(fileURLWithPath: args[1])
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: matrixURL))
        guard !cases.isEmpty, Set(cases.map(\.id)).count == cases.count else { throw ProbeError.invalidCase }
        let outputURL = URL(fileURLWithPath: args[2])
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw ProbeError.outputExists }
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else { throw ProbeError.usage }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let runtime = try QwenRuntime(cacheDirectory: URL(fileURLWithPath: args[0]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var failures = 0
        for specification in cases {
            do {
                let result = try await run(specification, relativeTo: matrixURL.deletingLastPathComponent(), runtime: runtime)
                var data = try encoder.encode(result); data.append(0x0a)
                try output.write(contentsOf: data); try output.synchronize()
            } catch {
                failures += 1
                var data = try JSONSerialization.data(withJSONObject: ["event": "runtime_error", "case": specification.id,
                    "error": String(describing: error)], options: [.sortedKeys]); data.append(0x0a)
                try output.write(contentsOf: data); try output.synchronize()
                try? await runtime.unload()
            }
        }
        try await runtime.unload()
        if failures > 0 { throw NSError(domain: "QwenRuntimeProbe", code: failures) }
    }
}
