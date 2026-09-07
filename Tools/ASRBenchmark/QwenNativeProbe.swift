import Foundation
import Darwin
import Metal
import MLX
import MLXNN
import MLXAudioCore
import MLXAudioSTT

/// Isolated native batch parity probe; model files must already be pinned locally.
@main
struct QwenNativeProbe {
    nonisolated static func main() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let cpuOnly = args.contains("--cpu")
        let streaming = args.contains("--streaming")
        let official = args.contains("--official-streaming")
        let tokenStream = args.contains("--token-stream")
        let encoderFP32 = args.contains("--encoder-fp32")
        args.removeAll { ["--cpu", "--streaming", "--official-streaming", "--token-stream", "--encoder-fp32"].contains($0) }
        guard [streaming, official, tokenStream].filter({ $0 }).count <= 1 else { throw NSError(domain: "QwenNativeProbe", code: 7) }
        try await Device.withDefaultDevice(cpuOnly ? .cpu : .gpu) { @Sendable [args, cpuOnly, streaming, official, tokenStream, encoderFP32] in
            try await run(args, cpuOnly: cpuOnly, streaming: streaming, official: official, tokenStream: tokenStream, encoderFP32: encoderFP32)
        }
    }

    nonisolated static func run(_ args: [String], cpuOnly: Bool, streaming: Bool, official: Bool, tokenStream: Bool, encoderFP32: Bool) async throws {
        if args == ["--frontend-proof"] {
            try frontendProof(cpuOnly: cpuOnly)
            return
        }
        guard args.count == 4 else {
            throw NSError(domain: "QwenNativeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: QwenNativeProbe MODEL_DIRECTORY AUDIO_DIRECTORY OUTPUT_JSONL MODEL_REVISION"])
        }
        let device = MTLCreateSystemDefaultDevice()
        guard cpuOnly || device != nil else {
            throw NSError(domain: "QwenNativeProbe", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "No Metal device: MLX inference unavailable; no native accuracy or latency verdict."])
        }
        let outputURL = URL(fileURLWithPath: args[2])
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw NSError(domain: "QwenNativeProbe", code: 3)
        }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        func emit(_ row: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0a)
            try output.write(contentsOf: data)
            try output.synchronize()
        }
        let start = ProcessInfo.processInfo.systemUptime
        let model = try await Qwen3ASRModel.fromModelDirectory(URL(fileURLWithPath: args[0]))
        if encoderFP32 {
            let parameters = model.parameters().flattened()
                .filter { $0.0.hasPrefix("audio_tower.") }
                .map { ($0.0, $0.1.asType(.float32)) }
            try model.update(parameters: ModuleParameters.unflattened(parameters), verify: [.noUnusedKeys, .shapeMismatch])
            eval(model)
        }
        var streamingConfiguration: [String: Any] = [:]
        if official {
            streamingConfiguration = ["reference_revision": QwenOfficialStreamingPolicy.sourceRevision,
                "chunk_seconds": 2.0, "unfixed_chunk_num": 2, "unfixed_token_num": 5,
                "audio_context": "cumulative from utterance start", "global_repetition_filter": false,
                "packet_samples": 1280, "packet_availability": "last sample received",
                "final_tail_policy": "official max(1, tokens-5), without Unicode repair"]
        } else if streaming {
            streamingConfiguration = ["packet_samples": 1280, "packet_availability": "last sample received",
                "delay_preset": "realtime", "decode_interval_seconds": 0.35,
                "max_cached_windows": 2, "encoder_window_overlap_seconds": 1.0]
        }
        try emit([
            "event": "loaded", "model_revision": args[3],
            "package_revision": "aee9bd1dffcf786f544d6562d971b3e25221e261",
            "metal_device": device?.name ?? "none", "compute_device": cpuOnly ? "cpu" : "gpu",
            "load_seconds": ProcessInfo.processInfo.systemUptime - start,
            "mlx_active_bytes": Memory.activeMemory,
            "mlx_peak_bytes": Memory.peakMemory,
            "mode": official ? "official_cumulative_streaming_control" : streaming ? "paced_streaming" : tokenStream ? "full_audio_token_stream" : "batch",
            "encoder_fp32": encoderFP32, "language": "auto", "max_tokens": 256,
            "streaming_configuration": streamingConfiguration
        ])
        let files = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: args[1]), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw NSError(domain: "QwenNativeProbe", code: 4) }
        for file in files {
            let (rate, audio) = try loadAudioArray(from: file, sampleRate: 16_000)
            eval(audio)
            let duration = Double(audio.size) / Double(rate)
            let begin = ProcessInfo.processInfo.systemUptime
            let text: String
            let language: String?
            var streamingMetrics: [String: Any] = [:]
            if streaming || official {
                let measured: StreamMeasurement
                if official {
                    let result = try await officialStream(model: model, samples: audio.asArray(Float.self))
                    measured = result.measurement
                    language = result.language
                    streamingMetrics["official_passes"] = result.passes.map { pass -> [String: Any] in
                        ["index": pass.index, "audio_samples": pass.audioSamples, "final_tail": pass.finalTail,
                         "prefix": pass.prefix, "generated": pass.generated, "raw_text": pass.rawText,
                         "generation_tokens": pass.generationTokens, "seconds": pass.seconds]
                    }
                } else {
                    measured = try await stream(model: model, samples: audio.asArray(Float.self))
                    language = nil
                }
                text = measured.text
                streamingMetrics.merge(["release_to_final_seconds": measured.finalization,
                    "stop_to_final_seconds": measured.stopFinalization,
                    "first_partial_seconds": measured.firstPartial.map { $0 as Any } ?? NSNull(),
                    "partial_count": measured.partialCount, "feed_overrun_seconds": measured.feedOverrun]) { _, new in new }
            } else {
                let result: STTOutput
                if tokenStream {
                    result = try await tokenStreamResult(model: model, audio: audio)
                } else {
                    result = model.generate(audio: audio, maxTokens: 256, language: nil)
                }
                text = result.text
                language = result.language
                streamingMetrics = ["generation_tokens": result.generationTokens,
                    "prompt_tokens": result.promptTokens]
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - begin
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            var row: [String: Any] = [
                "event": "result", "file": file.lastPathComponent,
                "text": text, "detected_language": language.map { $0 as Any } ?? NSNull(),
                "audio_seconds": duration,
                "inference_seconds": elapsed, "rtf": elapsed / duration,
                "timing_semantics": (streaming || official) ? "paced wall time including playback" : "batch inference",
                "process_peak_rss_bytes": usage.ru_maxrss,
                "mlx_active_bytes": Memory.activeMemory,
                "mlx_peak_bytes": Memory.peakMemory
            ]
            row.merge(streamingMetrics) { _, new in new }
            try emit(row)
        }
    }

    nonisolated static func tokenStreamResult(model: Qwen3ASRModel, audio: MLXArray) async throws -> STTOutput {
        for try await event in model.generateStream(audio: audio, maxTokens: 256, language: nil) {
            if case .result(let output) = event { return output }
        }
        throw NSError(domain: "QwenNativeProbe", code: 8)
    }

    struct StreamMeasurement: Sendable {
        var text: String
        var finalization: Double
        var stopFinalization: Double
        var firstPartial: Double?
        var partialCount: Int
        var feedOverrun: Double
    }

    nonisolated static func stream(model: Qwen3ASRModel, samples: [Float]) async throws -> StreamMeasurement {
        let session = StreamingInferenceSession(model: model, config: StreamingConfig(
            decodeIntervalSeconds: 0.35, encoderWindowOverlapSeconds: 1.0,
            maxCachedWindows: 2, delayPreset: .realtime,
            language: nil, maxTokensPerPass: 256))
        let begin = ProcessInfo.processInfo.systemUptime
        let collected = Task { @Sendable in
            var displayTimes: [Double] = []
            for await event in session.events {
                switch event {
                case .displayUpdate(let confirmed, let provisional):
                    if !(confirmed + provisional).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        displayTimes.append(ProcessInfo.processInfo.systemUptime)
                    }
                case .ended(let text):
                    return (text, ProcessInfo.processInfo.systemUptime, displayTimes, true)
                default: break
                }
            }
            return ("", ProcessInfo.processInfo.systemUptime, displayTimes, false)
        }
        for offset in stride(from: 0, to: samples.count, by: 1280) {
            let end = min(offset + 1280, samples.count)
            // A microphone packet becomes available after its last sample, not its first.
            let wait = begin + Double(end) / 16_000 - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            session.feedAudio(samples: Array(samples[offset..<end]))
        }
        let wait = begin + Double(samples.count) / 16_000 - ProcessInfo.processInfo.systemUptime
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        let release = begin + Double(samples.count) / 16_000
        let stop = ProcessInfo.processInfo.systemUptime
        session.stop()
        let watchdog = Task { @Sendable in
            try await Task.sleep(for: .seconds(30))
            session.cancel()
        }
        let (text, finalTime, displayTimes, ended) = await collected.value
        watchdog.cancel()
        guard ended else { throw NSError(domain: "QwenNativeProbe", code: 6) }
        let liveTimes = displayTimes.filter { $0 < release }
        return StreamMeasurement(text: text, finalization: finalTime - release,
            stopFinalization: finalTime - stop,
            firstPartial: liveTimes.first.map { $0 - begin }, partialCount: liveTimes.count,
            feedOverrun: max(0, stop - release))
    }

    /// Compare interior frames, excluding end padding, against the trained batch frontend.
    nonisolated static func frontendProof(cpuOnly: Bool) throws {
        guard cpuOnly || MTLCreateSystemDefaultDevice() != nil else {
            throw NSError(domain: "QwenNativeProbe", code: 2)
        }
        let samples: [Float] = (0..<32_000).map { index in
            let t = Double(index) / 16_000
            return Float(0.2 * sin(2 * .pi * 440 * t) + 0.1 * sin(2 * .pi * 1733 * t))
        }
        let batch = computeMelSpectrogram(audio: MLXArray(samples), sampleRate: 16_000,
            nFft: 400, hopLength: 160, nMels: 128, melScale: .slaney, hannPeriodic: true)
        let incremental = IncrementalMelSpectrogram()
        guard let streaming = incremental.process(samples: samples) else {
            throw NSError(domain: "QwenNativeProbe", code: 5)
        }
        let end = min(batch.dim(0), streaming.dim(0)) - 2
        let maxError = MLX.abs(batch[2..<end] - streaming[2..<end]).max().item(Float.self)
        let row: [String: Any] = ["event": "frontend_proof", "max_absolute_error": maxError,
            "tolerance": 0.0001, "passed": maxError < 0.0001]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if maxError >= 0.0001 { exit(1) }
    }
}
