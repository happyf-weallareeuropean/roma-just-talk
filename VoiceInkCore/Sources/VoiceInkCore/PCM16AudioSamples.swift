import Foundation

public enum VoiceInkAudioProcessingError: LocalizedError, Equatable, Sendable {
    case invalidAudioFile
    case conversionFailed
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return "The audio file is invalid or corrupted"
        case .conversionFailed:
            return "Failed to convert the audio format"
        case .unsupportedFormat:
            return "The audio format is not supported"
        }
    }
}

public enum VoiceInkWhisperAudioSamples {
    public static func floatSamples(fromWAVData data: Data) -> [Float]? {
        VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: data,
            targetPeak: VoiceInkWhisperRuntimeDefaults.audioLevelingTargetPeak,
            noiseFloorPeak: VoiceInkWhisperRuntimeDefaults.audioLevelingNoiseFloorPeak,
            maxGain: VoiceInkWhisperRuntimeDefaults.audioLevelingMaxGain
        )
    }

    public static func floatSamples(fromWAVFileAt url: URL) throws -> [Float]? {
        try floatSamples(fromWAVData: Data(contentsOf: url))
    }
}

public enum VoiceInkPCM16Audio {
    public static let mono16kSampleRateHz = 16_000
    public static let mono16kSampleRate = Double(mono16kSampleRateHz)
    public static let monoChannelCount = 1
    public static let bitsPerSample = 16
    public static let bytesPerSample = MemoryLayout<Int16>.size
    public static let isBigEndian = false
    public static let isFloatingPoint = false
    public static let wavHeaderByteCount = 44
    private static let minimumSpeechLikeCrestFactor: Float = 6.0
    private static let minimumSpeechLikeActiveSampleCount = 3
    private static let minimumSpeechLikeActiveSampleDivisor = 100
    private static let minimumSpeechLikeActiveRunSampleCount = 4

    public static func floatSamples(fromLittleEndianData data: Data, startingAt startByteOffset: Int = 0) -> [Float] {
        guard startByteOffset >= 0 else { return [] }
        let readableByteCount = data.count - startByteOffset
        guard readableByteCount >= bytesPerSample else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return [] }

            let sampleCount = readableByteCount / bytesPerSample
            var samples: [Float] = []
            samples.reserveCapacity(sampleCount)

            for sampleIndex in 0..<sampleCount {
                let byteIndex = startByteOffset + sampleIndex * bytesPerSample
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                let sample = Int16(bitPattern: rawValue)
                samples.append(max(-1.0, min(Float(sample) / 32767.0, 1.0)))
            }

            return samples
        }
    }

    public static func floatSamples(fromWAVData data: Data) -> [Float]? {
        guard let pcmData = littleEndianPCM16Data(fromWAVData: data) else { return nil }
        return floatSamples(fromLittleEndianData: pcmData)
    }

    public static func floatSamples(fromWAVFileAt url: URL) throws -> [Float]? {
        try floatSamples(fromWAVData: Data(contentsOf: url))
    }

    static func leveledFloatSamples(
        fromWAVData data: Data,
        targetPeak: Int16,
        noiseFloorPeak: Int16,
        maxGain: Float
    ) -> [Float]? {
        guard let pcmData = littleEndianPCM16Data(fromWAVData: data) else { return nil }
        let leveledData = leveledLittleEndianData(
            pcmData,
            targetPeak: targetPeak,
            noiseFloorPeak: noiseFloorPeak,
            maxGain: maxGain
        )
        return floatSamples(fromLittleEndianData: leveledData)
    }

    static func leveledFloatSamples(
        fromWAVFileAt url: URL,
        targetPeak: Int16,
        noiseFloorPeak: Int16,
        maxGain: Float
    ) throws -> [Float]? {
        try leveledFloatSamples(
            fromWAVData: Data(contentsOf: url),
            targetPeak: targetPeak,
            noiseFloorPeak: noiseFloorPeak,
            maxGain: maxGain
        )
    }

    public static func normalizedMonoFloatSamples(
        channelCount: Int,
        frameLength: Int,
        sampleAt: (_ channel: Int, _ frame: Int) -> Float
    ) -> [Float] {
        guard channelCount > 0, frameLength > 0 else { return [] }

        var samples = Array(repeating: Float(0), count: frameLength)

        if channelCount == 1 {
            for frame in 0..<frameLength {
                samples[frame] = sampleAt(0, frame)
            }
        } else {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += sampleAt(channel, frame)
                }
                samples[frame] = sum / Float(channelCount)
            }
        }

        let maxSample = samples.map(abs).max() ?? 1
        if maxSample > 0 {
            samples = samples.map { $0 / maxSample }
        }

        return samples
    }

    public static func pcm16Samples(fromFloatSamples samples: [Float]) -> [Int16] {
        samples.map { sample in
            let clipped = max(-1.0, min(1.0, sample))
            return Int16(clipped * Float(Int16.max))
        }
    }

    public static func leveledLittleEndianData(
        _ data: Data,
        targetPeak: Int16,
        noiseFloorPeak: Int16,
        maxGain: Float
    ) -> Data {
        let sampleByteCount = data.count - (data.count % bytesPerSample)
        guard sampleByteCount >= bytesPerSample,
              targetPeak > 0,
              noiseFloorPeak >= 0,
              maxGain > 1 else {
            return data
        }

        let metrics = pcm16Metrics(
            inLittleEndianData: data,
            byteCount: sampleByteCount,
            activeThreshold: Int(noiseFloorPeak)
        )
        let peak = metrics.peak
        guard peak > 0, peak >= Int(noiseFloorPeak), peak < Int(targetPeak) else { return data }
        let minimumActiveSampleCount = max(
            minimumSpeechLikeActiveSampleCount,
            metrics.sampleCount / minimumSpeechLikeActiveSampleDivisor
        )
        guard metrics.activeSampleCount >= minimumActiveSampleCount else { return data }
        guard metrics.longestActiveSampleRun >= minimumSpeechLikeActiveRunSampleCount else { return data }
        guard metrics.rms > 0,
              Float(peak) / metrics.rms >= minimumSpeechLikeCrestFactor else {
            return data
        }

        let gain = min(Float(targetPeak) / Float(peak), maxGain)
        guard gain > 1 else { return data }

        var output = Data()
        output.reserveCapacity(data.count)
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }

            for byteIndex in stride(from: 0, to: sampleByteCount, by: bytesPerSample) {
                let sample = littleEndianPCM16Sample(bytes: bytes, byteIndex: byteIndex)
                let leveledSample = pcm16SampleFromScaledInt16(sample, gain: gain)
                let littleEndian = leveledSample.littleEndian
                output.append(UInt8(truncatingIfNeeded: littleEndian))
                output.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
            }
        }

        if sampleByteCount < data.count {
            output.append(data.subdata(in: sampleByteCount..<data.count))
        }

        return output
    }

    public static func convertedMonoPCM16SampleCount(
        frameCount: Int,
        inputSampleRate: Double,
        outputSampleRate: Double = mono16kSampleRate
    ) -> Int {
        guard frameCount > 0, inputSampleRate > 0, outputSampleRate > 0 else { return 0 }
        let ratio = outputSampleRate / inputSampleRate
        guard ratio.isFinite, ratio > 0 else { return 0 }
        return Int(Double(frameCount) * ratio)
    }

    /// `inputSamples` must contain at least `frameCount * channelCount` interleaved samples.
    public static func writeMonoPCM16Samples(
        fromInterleavedFloat32Samples inputSamples: UnsafePointer<Float32>,
        frameCount: Int,
        channelCount: Int,
        inputSampleRate: Double,
        outputSampleRate: Double = mono16kSampleRate,
        to outputSamples: UnsafeMutablePointer<Int16>,
        outputCapacity: Int
    ) -> Int {
        guard frameCount > 0, channelCount > 0, inputSampleRate > 0, outputSampleRate > 0 else {
            return 0
        }

        let ratio = outputSampleRate / inputSampleRate
        guard ratio.isFinite, ratio > 0 else { return 0 }

        let outputFrameCount = convertedMonoPCM16SampleCount(
            frameCount: frameCount,
            inputSampleRate: inputSampleRate,
            outputSampleRate: outputSampleRate
        )
        guard outputFrameCount > 0, outputFrameCount <= outputCapacity else { return 0 }

        if inputSampleRate == outputSampleRate {
            for frame in 0..<frameCount {
                let sample = averagedInterleavedSample(
                    inputSamples,
                    frame: frame,
                    channelCount: channelCount
                )
                outputSamples[frame] = pcm16SampleFromScaledFloat(sample)
            }
        } else {
            for outputFrame in 0..<outputFrameCount {
                let inputIndex = Double(outputFrame) / ratio
                let inputIndexInt = Int(inputIndex)
                let fraction = Float32(inputIndex - Double(inputIndexInt))
                let firstFrame = min(inputIndexInt, frameCount - 1)
                let secondFrame = min(inputIndexInt + 1, frameCount - 1)
                var sample: Float32 = 0

                for channel in 0..<channelCount {
                    let firstSample = inputSamples[firstFrame * channelCount + channel]
                    let secondSample = inputSamples[secondFrame * channelCount + channel]
                    sample += firstSample + fraction * (secondSample - firstSample)
                }
                sample /= Float32(channelCount)

                outputSamples[outputFrame] = pcm16SampleFromScaledFloat(sample)
            }
        }

        return outputFrameCount
    }

    public static func sampleCount(inData data: Data) -> Int {
        data.count / bytesPerSample
    }

    public static func sampleCount(forMono16kDuration seconds: Double) -> Int {
        Int((seconds * Double(mono16kSampleRateHz)).rounded())
    }

    public static func byteCount(forMono16kDuration seconds: Double) -> Int {
        Int((seconds * Double(mono16kSampleRateHz) * Double(bytesPerSample)).rounded())
    }

    public static func duration(forMono16kData data: Data) -> TimeInterval {
        TimeInterval(sampleCount(inData: data)) / Double(mono16kSampleRateHz)
    }

    public static func monoPCM16Chunks(from data: Data, maxByteCount: Int) -> [Data] {
        guard !data.isEmpty, maxByteCount >= bytesPerSample else { return [] }

        let chunkByteCount = maxByteCount - (maxByteCount % bytesPerSample)
        guard chunkByteCount > 0 else { return [] }

        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let remainingByteCount = data.count - offset
            let length = min(chunkByteCount, remainingByteCount)
            guard length >= bytesPerSample else { break }

            chunks.append(data.subdata(in: offset..<(offset + length)))
            offset += length
        }

        return chunks
    }

    private static func averagedInterleavedSample(
        _ inputSamples: UnsafePointer<Float32>,
        frame: Int,
        channelCount: Int
    ) -> Float32 {
        var sample: Float32 = 0
        for channel in 0..<channelCount {
            sample += inputSamples[frame * channelCount + channel]
        }
        return sample / Float32(channelCount)
    }

    public static func littleEndianPCM16Data(fromWAVData data: Data) -> Data? {
        guard let dataChunkRange = wavDataChunkRange(in: data) else { return nil }
        return data.subdata(in: dataChunkRange)
    }

    public static func wavData(fromLittleEndianPCM16Data pcmData: Data) -> Data {
        let sampleByteCount = pcmData.count - (pcmData.count % bytesPerSample)
        let sampleData = pcmData.prefix(sampleByteCount)

        var wavData = Data()
        appendASCII("RIFF", to: &wavData)
        appendUInt32LE(UInt32(36 + sampleData.count), to: &wavData)
        appendASCII("WAVE", to: &wavData)
        appendASCII("fmt ", to: &wavData)
        appendUInt32LE(16, to: &wavData)
        appendUInt16LE(1, to: &wavData)
        appendUInt16LE(UInt16(monoChannelCount), to: &wavData)
        appendUInt32LE(UInt32(mono16kSampleRateHz), to: &wavData)
        appendUInt32LE(UInt32(mono16kSampleRateHz * monoChannelCount * bytesPerSample), to: &wavData)
        appendUInt16LE(UInt16(monoChannelCount * bytesPerSample), to: &wavData)
        appendUInt16LE(UInt16(bitsPerSample), to: &wavData)
        appendASCII("data", to: &wavData)
        appendUInt32LE(UInt32(sampleData.count), to: &wavData)
        wavData.append(sampleData)
        return wavData
    }

    private static func wavDataChunkRange(in data: Data) -> Range<Int>? {
        guard data.count >= 12 else { return nil }

        return data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                  matchesASCII("RIFF", bytes: bytes, at: 0),
                  matchesASCII("WAVE", bytes: bytes, at: 8) else {
                return nil
            }

            var isValidPCMFormat = false
            var dataChunkRange: Range<Int>?
            var offset = 12
            while offset + 8 <= data.count {
                let chunkSize = Int(littleEndianUInt32(bytes: bytes, at: offset + 4))
                let chunkDataStart = offset + 8
                let chunkDataEnd = chunkDataStart + chunkSize
                guard chunkDataEnd <= data.count else { return nil }

                if matchesASCII("fmt ", bytes: bytes, at: offset) {
                    guard chunkSize >= 16 else { return nil }
                    isValidPCMFormat = isMono16kPCM16Format(bytes: bytes, at: chunkDataStart)
                } else if matchesASCII("data", bytes: bytes, at: offset) {
                    dataChunkRange = chunkDataStart..<chunkDataEnd
                }

                let nextOffset = chunkDataEnd + (chunkSize.isMultiple(of: 2) ? 0 : 1)
                guard nextOffset <= data.count else { return nil }
                offset = nextOffset
            }

            guard isValidPCMFormat,
                  let dataChunkRange,
                  dataChunkRange.count.isMultiple(of: bytesPerSample) else {
                return nil
            }
            return dataChunkRange
        }
    }

    private static func isMono16kPCM16Format(bytes: UnsafePointer<UInt8>, at offset: Int) -> Bool {
        let audioFormat = littleEndianUInt16(bytes: bytes, at: offset)
        let channelCount = littleEndianUInt16(bytes: bytes, at: offset + 2)
        let sampleRate = littleEndianUInt32(bytes: bytes, at: offset + 4)
        let byteRate = littleEndianUInt32(bytes: bytes, at: offset + 8)
        let blockAlign = littleEndianUInt16(bytes: bytes, at: offset + 12)
        let bits = littleEndianUInt16(bytes: bytes, at: offset + 14)
        return audioFormat == 1
            && channelCount == UInt16(monoChannelCount)
            && sampleRate == UInt32(mono16kSampleRateHz)
            && byteRate == UInt32(mono16kSampleRateHz * monoChannelCount * bytesPerSample)
            && blockAlign == UInt16(monoChannelCount * bytesPerSample)
            && bits == UInt16(bitsPerSample)
    }

    private static func matchesASCII(
        _ value: StaticString,
        bytes: UnsafePointer<UInt8>,
        at offset: Int
    ) -> Bool {
        let expected = value.utf8Start
        for index in 0..<value.utf8CodeUnitCount {
            guard bytes[offset + index] == expected[index] else { return false }
        }
        return true
    }

    private static func littleEndianUInt32(bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func littleEndianUInt16(bytes: UnsafePointer<UInt8>, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 16))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 24))
    }

    fileprivate static func pcm16SampleFromScaledFloat(_ sample: Float32) -> Int16 {
        let scaled = sample * 32767.0
        let clipped = max(-32768.0, min(32767.0, scaled))
        return Int16(clipped)
    }

    private static func pcm16Metrics(
        inLittleEndianData data: Data,
        byteCount: Int,
        activeThreshold: Int
    ) -> (peak: Int, rms: Float, activeSampleCount: Int, sampleCount: Int, longestActiveSampleRun: Int) {
        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return (0, 0, 0, 0, 0) }

            var peak = 0
            var sumSquares = Double(0)
            var sampleCount = 0
            var activeSampleCount = 0
            var currentActiveSampleRun = 0
            var longestActiveSampleRun = 0
            for byteIndex in stride(from: 0, to: byteCount, by: bytesPerSample) {
                let sample = littleEndianPCM16Sample(bytes: bytes, byteIndex: byteIndex)
                let magnitude = pcm16Magnitude(sample)
                peak = max(peak, magnitude)
                if magnitude >= activeThreshold {
                    activeSampleCount += 1
                    currentActiveSampleRun += 1
                    longestActiveSampleRun = max(longestActiveSampleRun, currentActiveSampleRun)
                } else {
                    currentActiveSampleRun = 0
                }
                sumSquares += Double(sample) * Double(sample)
                sampleCount += 1
            }
            guard sampleCount > 0 else { return (0, 0, 0, 0, 0) }
            return (
                peak,
                Float(sqrt(sumSquares / Double(sampleCount))),
                activeSampleCount,
                sampleCount,
                longestActiveSampleRun
            )
        }
    }

    private static func littleEndianPCM16Sample(bytes: UnsafePointer<UInt8>, byteIndex: Int) -> Int16 {
        let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
        return Int16(bitPattern: rawValue)
    }

    private static func pcm16Magnitude(_ sample: Int16) -> Int {
        sample == Int16.min ? Int(Int16.max) + 1 : abs(Int(sample))
    }

    private static func pcm16SampleFromScaledInt16(_ sample: Int16, gain: Float) -> Int16 {
        let scaled = (Float(sample) * gain).rounded()
        let clipped = max(-32768.0, min(32767.0, scaled))
        return Int16(clipped)
    }

}

/// One source clock across microphone callbacks. The owner serializes conversion, cuts and reset.
public final class VoiceInkPCM16StreamConverter {
    public let maximumOutputFrameCount: Int
    private let ratio: Double
    private let channelCount: Int
    private let maximumInputFrameCount: Int
    private let historyCapacity: Int
    private var history: [Float32]
    private var historyCount = 0
    private var inputFrameCount = 0
    private var outputFrameIndex = 0

    public init?(
        inputSampleRate: Double,
        channelCount: Int,
        maximumInputFrameCount: Int = 4096,
        outputSampleRate: Double = VoiceInkPCM16Audio.mono16kSampleRate
    ) {
        guard inputSampleRate.isFinite, inputSampleRate > 0,
              outputSampleRate.isFinite, outputSampleRate > 0,
              channelCount > 0, maximumInputFrameCount > 0 else { return nil }
        let ratio = outputSampleRate / inputSampleRate
        let historyFrames = max(2, ceil(1 / ratio) + 1)
        let outputFrames = ceil(Double(maximumInputFrameCount) * ratio) + ceil(ratio) + 1
        guard historyFrames.isFinite, historyFrames < Double(Int.max / channelCount),
              outputFrames.isFinite, outputFrames < Double(Int.max) else { return nil }
        self.ratio = ratio
        self.channelCount = channelCount
        self.maximumInputFrameCount = maximumInputFrameCount
        historyCapacity = Int(historyFrames)
        history = Array(repeating: 0, count: Int(historyFrames) * channelCount)
        maximumOutputFrameCount = Int(outputFrames)
    }

    public func reset() {
        historyCount = 0
        inputFrameCount = 0
        outputFrameIndex = 0
    }

    /// Returns nil without consuming input if the caller's buffers cannot hold this conversion.
    public func convert(
        _ input: UnsafePointer<Float32>,
        frameCount: Int,
        to output: UnsafeMutablePointer<Int16>,
        outputCapacity: Int
    ) -> Int? {
        guard frameCount >= 0, frameCount <= maximumInputFrameCount,
              frameCount <= Int.max - inputFrameCount else { return nil }
        let total = inputFrameCount + frameCount
        guard let target = targetOutputCount(total),
              outputCapacity >= target - outputFrameIndex else { return nil }
        guard frameCount > 0 else { return 0 }

        var written = 0
        while outputFrameIndex < target {
            let position = Double(outputFrameIndex) / ratio
            let first = Int(position)
            let fraction = Float32(position - Double(first))
            let second = fraction == 0 ? first : first + 1
            // Upsampling needs the next callback's first frame, not a clamped packet endpoint.
            guard second < total else { break }
            output[written] = sample(first: first, second: second, fraction: fraction, input: input)
            written += 1
            outputFrameIndex += 1
        }

        // A pending grid point can lie several frames before the last frame (512 at48k).
        let retained = min(total, historyCapacity)
        let start = total - retained
        for frame in 0..<retained {
            for channel in 0..<channelCount {
                history[frame * channelCount + channel] = source(start + frame, channel: channel, input: input)
            }
        }
        historyCount = retained
        inputFrameCount = total
        return written
    }

    /// Ends a recording segment without restarting the source clock. Repeated cuts emit no data.
    public func finishSegment(to output: UnsafeMutablePointer<Int16>, outputCapacity: Int) -> Int? {
        guard let target = targetOutputCount(inputFrameCount),
              outputCapacity >= target - outputFrameIndex else { return nil }
        var written = 0
        while outputFrameIndex < target {
            let position = Double(outputFrameIndex) / ratio
            let first = min(Int(position), inputFrameCount - 1)
            let fraction = Float32(position - Double(Int(position)))
            output[written] = sample(
                first: first, second: min(first + 1, inputFrameCount - 1),
                fraction: fraction, input: nil
            )
            written += 1
            outputFrameIndex += 1
        }
        return written
    }

    private func targetOutputCount(_ frames: Int) -> Int? {
        let count = Double(frames) * ratio
        guard count.isFinite, count < Double(Int.max) else { return nil }
        return Int(count)
    }

    private func source(_ frame: Int, channel: Int, input: UnsafePointer<Float32>?) -> Float32 {
        if frame >= inputFrameCount, let input {
            return input[(frame - inputFrameCount) * channelCount + channel]
        }
        return history[(frame - (inputFrameCount - historyCount)) * channelCount + channel]
    }

    private func sample(
        first: Int, second: Int, fraction: Float32, input: UnsafePointer<Float32>?
    ) -> Int16 {
        var value: Float32 = 0
        for channel in 0..<channelCount {
            let a = source(first, channel: channel, input: input)
            if first == second {
                value += a
            } else {
                value += a + fraction * (source(second, channel: channel, input: input) - a)
            }
        }
        return VoiceInkPCM16Audio.pcm16SampleFromScaledFloat(value / Float32(channelCount))
    }
}
