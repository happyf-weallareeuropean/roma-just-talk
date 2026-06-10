import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os

final class WhisperVADSpeechDetector: SpeechActivityDetecting, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperVADSpeechDetector")
    private let lock = NSLock()
    private let threshold: Float
    private var context: OpaquePointer?

    static func makeDefault() async -> WhisperVADSpeechDetector? {
        guard UserDefaults.standard.bool(forKey: "IsVADEnabled"),
              let modelPath = await VADModelManager.shared.getModelPath() else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            WhisperVADSpeechDetector(modelPath: modelPath)
        }.value
    }

    init?(modelPath: String, threshold: Float = 0.5) {
        self.threshold = threshold

        var params = whisper_vad_default_context_params()
        params.n_threads = Int32(max(1, min(2, ProcessInfo.processInfo.processorCount - 1)))
        params.use_gpu = false

        guard let context = whisper_vad_init_from_file_with_params(modelPath, params) else {
            logger.error("Failed to load streaming VAD model at \(modelPath, privacy: .public)")
            return nil
        }

        self.context = context
    }

    deinit {
        if let context {
            whisper_vad_free(context)
        }
    }

    func containsSpeech(inPCM16LEData data: Data) -> Bool {
        let samples = Self.floatSamples(fromPCM16LEData: data)
        guard !samples.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        guard let context else { return true }

        let didRun = samples.withUnsafeBufferPointer { buffer in
            whisper_vad_detect_speech_no_reset(context, buffer.baseAddress, Int32(buffer.count))
        }

        guard didRun else {
            logger.notice("Streaming VAD detection failed; passing audio through")
            return true
        }

        let probabilityCount = whisper_vad_n_probs(context)
        guard probabilityCount > 0, let probabilities = whisper_vad_probs(context) else {
            return false
        }

        for index in 0..<Int(probabilityCount) {
            if probabilities[index] >= threshold {
                return true
            }
        }

        return false
    }

    private static func floatSamples(fromPCM16LEData data: Data) -> [Float] {
        guard data.count >= MemoryLayout<Int16>.size else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return [] }

            let sampleCount = data.count / MemoryLayout<Int16>.size
            var samples: [Float] = []
            samples.reserveCapacity(sampleCount)

            for sampleIndex in 0..<sampleCount {
                let byteIndex = sampleIndex * MemoryLayout<Int16>.size
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                let sample = Int16(bitPattern: rawValue)
                samples.append(max(-1.0, min(Float(sample) / 32767.0, 1.0)))
            }

            return samples
        }
    }
}
