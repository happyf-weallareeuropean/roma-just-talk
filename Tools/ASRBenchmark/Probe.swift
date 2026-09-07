import FluidAudio
import Foundation
import Darwin

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func samples(_ url: URL) throws -> [Float] {
    let converter = AudioConverter(sampleRate: 16000)
    return try converter.resampleAudioFile(url)
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}

@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, ["sensevoice", "parakeet"].contains(args[1]) else {
            fatalError("Usage: RomaASRBenchmark sensevoice|parakeet model-directory audio-directory")
        }
        let model = args[1]
        let directory = URL(fileURLWithPath: args[2])
        let audio = URL(fileURLWithPath: args[3])
        let files = try FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { fatalError("No WAV inputs") }
        emit(["event": "baseline", "pid": getpid(), "model": model])
        try await Task.sleep(for: .seconds(3))
        let started = Date()
        let transcribe: ([Float]) async throws -> String
        if model == "sensevoice" {
            let models = try SenseVoiceModels.load(from: directory, precision: .int8)
            let manager = SenseVoiceManager(models: models)
            transcribe = { try await manager.transcribe(audio: $0) }
        } else {
            let models = try await AsrModels.load(from: directory, version: .v2)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            transcribe = { audio in
                var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                return try await manager.transcribe(audio, decoderState: &state).text
            }
        }
        emit(["event": "loaded", "pid": getpid(), "model": model, "load_seconds": Date().timeIntervalSince(started)])
        try await Task.sleep(for: .seconds(5))
        var failed = false
        for repetition in 0..<3 {
            for file in files {
                let audioSamples = try samples(file)
                let cpuStart = cpuSeconds()
                let start = Date()
                do {
                    let text = try await transcribe(audioSamples)
                    emit(["event": "clip", "clip": file.lastPathComponent, "repetition": repetition,
                          "duration_seconds": Double(audioSamples.count) / 16000,
                          "text": text, "elapsed_seconds": Date().timeIntervalSince(start),
                          "cpu_seconds": cpuSeconds() - cpuStart, "accuracy_scored": false])
                } catch {
                    failed = true
                    emit(["event": "clip_error", "clip": file.lastPathComponent, "error": String(describing: error)])
                }
            }
        }
        emit(["event": "idle_start", "pid": getpid()])
        try await Task.sleep(for: .seconds(10))
        emit(["event": "finished"])
        if failed { exit(1) }
    }
}
