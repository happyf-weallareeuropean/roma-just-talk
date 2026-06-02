import Foundation

public enum PCM16WAVFile {
    public enum WriteError: Error, Equatable {
        case unsupportedFormat(AudioChunkFormat)
        case invalidFormat(AudioChunkFormat)
        case pcmDataNotInt16Aligned(byteCount: Int)
        case dataTooLarge(byteCount: Int)
    }

    public static func makeData(
        samples: [Int16],
        format: AudioChunkFormat = .speechPCM16kMono
    ) throws -> Data {
        try makeData(pcmData: pcmData(from: samples), format: format)
    }

    public static func makeData(
        pcmData: Data,
        format: AudioChunkFormat = .speechPCM16kMono
    ) throws -> Data {
        try validate(format: format, pcmByteCount: pcmData.count)

        var data = Data()
        data.reserveCapacity(44 + pcmData.count)

        appendASCII("RIFF", to: &data)
        appendUInt32LittleEndian(UInt32(36 + pcmData.count), to: &data)
        appendASCII("WAVE", to: &data)

        appendASCII("fmt ", to: &data)
        appendUInt32LittleEndian(16, to: &data)
        appendUInt16LittleEndian(1, to: &data)
        appendUInt16LittleEndian(UInt16(format.channelCount), to: &data)
        appendUInt32LittleEndian(UInt32(format.sampleRate), to: &data)
        appendUInt32LittleEndian(UInt32(format.sampleRate * format.channelCount * 2), to: &data)
        appendUInt16LittleEndian(UInt16(format.channelCount * 2), to: &data)
        appendUInt16LittleEndian(16, to: &data)

        appendASCII("data", to: &data)
        appendUInt32LittleEndian(UInt32(pcmData.count), to: &data)
        data.append(pcmData)
        return data
    }

    public static func write(
        samples: [Int16],
        to url: URL,
        format: AudioChunkFormat = .speechPCM16kMono
    ) throws {
        try makeData(samples: samples, format: format).write(to: url, options: [.atomic])
    }

    public static func write(
        pcmData: Data,
        to url: URL,
        format: AudioChunkFormat = .speechPCM16kMono
    ) throws {
        try makeData(pcmData: pcmData, format: format).write(to: url, options: [.atomic])
    }

    private static func validate(format: AudioChunkFormat, pcmByteCount: Int) throws {
        guard format.sampleFormat == .signedInteger16 else {
            throw WriteError.unsupportedFormat(format)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw WriteError.invalidFormat(format)
        }
        guard pcmByteCount.isMultiple(of: MemoryLayout<Int16>.size) else {
            throw WriteError.pcmDataNotInt16Aligned(byteCount: pcmByteCount)
        }
        guard pcmByteCount <= Int(UInt32.max) - 36 else {
            throw WriteError.dataTooLarge(byteCount: pcmByteCount)
        }
    }

    private static func pcmData(from samples: [Int16]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<Int16>.size)

        for sample in samples {
            appendUInt16LittleEndian(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func appendUInt16LittleEndian(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x00FF),
            UInt8((value & 0xFF00) >> 8)
        ])
    }

    private static func appendUInt32LittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x000000FF),
            UInt8((value & 0x0000FF00) >> 8),
            UInt8((value & 0x00FF0000) >> 16),
            UInt8((value & 0xFF000000) >> 24)
        ])
    }
}
