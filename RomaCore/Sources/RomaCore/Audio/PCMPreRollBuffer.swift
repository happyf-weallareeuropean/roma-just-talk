import Foundation

public final class PCMPreRollBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int16]
    private var writeIndex = 0
    private var availableSamples = 0

    public let format: AudioChunkFormat
    public let capacitySamples: Int

    public var availableSampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return availableSamples
    }

    public init(configuration: PreRollConfiguration = PreRollConfiguration()) {
        format = configuration.outputFormat
        capacitySamples = max(Int(Double(configuration.outputFormat.sampleRate) * configuration.durationSeconds), 1)
        samples = Array(repeating: 0, count: capacitySamples)
    }

    public convenience init(sampleRate: Int, seconds: TimeInterval, channelCount: Int = 1) {
        self.init(
            configuration: PreRollConfiguration(
                durationSeconds: seconds,
                outputFormat: AudioChunkFormat(
                    sampleRate: sampleRate,
                    channelCount: channelCount,
                    sampleFormat: .signedInteger16
                )
            )
        )
    }

    public func append(samples input: [Int16]) {
        input.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            append(baseAddress, sampleCount: buffer.count)
        }
    }

    public func append(_ input: UnsafePointer<Int16>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        if sampleCount >= capacitySamples {
            let start = sampleCount - capacitySamples
            for offset in 0..<capacitySamples {
                samples[offset] = input[start + offset]
            }
            writeIndex = 0
            availableSamples = capacitySamples
            return
        }

        let firstCopyCount = min(sampleCount, capacitySamples - writeIndex)
        for offset in 0..<firstCopyCount {
            samples[writeIndex + offset] = input[offset]
        }

        let remaining = sampleCount - firstCopyCount
        if remaining > 0 {
            for offset in 0..<remaining {
                samples[offset] = input[firstCopyCount + offset]
            }
        }

        writeIndex = (writeIndex + sampleCount) % capacitySamples
        availableSamples = min(capacitySamples, availableSamples + sampleCount)
    }

    public func snapshotSamples() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        guard availableSamples > 0 else { return [] }

        let start = (writeIndex - availableSamples + capacitySamples) % capacitySamples
        let firstSampleCount = min(availableSamples, capacitySamples - start)
        let secondSampleCount = availableSamples - firstSampleCount

        var result = Array(samples[start..<(start + firstSampleCount)])
        if secondSampleCount > 0 {
            result.append(contentsOf: samples[0..<secondSampleCount])
        }
        return result
    }

    public func snapshotData() -> Data {
        let snapshot = snapshotSamples()
        var data = Data()
        data.reserveCapacity(snapshot.count * MemoryLayout<Int16>.size)

        for sample in snapshot {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    public func clear() {
        lock.lock()
        writeIndex = 0
        availableSamples = 0
        lock.unlock()
    }
}
