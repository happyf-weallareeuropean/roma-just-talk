import Foundation

public enum AudioSampleFormat: String, Codable, Hashable, Sendable {
    case signedInteger16
    case float32
}

public struct AudioChunkFormat: Codable, Equatable, Hashable, Sendable {
    public var sampleRate: Int
    public var channelCount: Int
    public var sampleFormat: AudioSampleFormat

    public init(
        sampleRate: Int,
        channelCount: Int,
        sampleFormat: AudioSampleFormat
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleFormat = sampleFormat
    }

    public static let speechPCM16kMono = AudioChunkFormat(
        sampleRate: 16_000,
        channelCount: 1,
        sampleFormat: .signedInteger16
    )
}

public struct PreRollConfiguration: Codable, Equatable, Hashable, Sendable {
    public var durationSeconds: TimeInterval
    public var outputFormat: AudioChunkFormat

    public init(
        durationSeconds: TimeInterval = 3,
        outputFormat: AudioChunkFormat = .speechPCM16kMono
    ) {
        self.durationSeconds = durationSeconds
        self.outputFormat = outputFormat
    }
}

public struct RecordedAudio: Codable, Equatable, Hashable, Sendable {
    public var fileURL: URL
    public var format: AudioChunkFormat
    public var durationSeconds: TimeInterval?
    public var includedPreRollSeconds: TimeInterval?

    public init(
        fileURL: URL,
        format: AudioChunkFormat = .speechPCM16kMono,
        durationSeconds: TimeInterval? = nil,
        includedPreRollSeconds: TimeInterval? = nil
    ) {
        self.fileURL = fileURL
        self.format = format
        self.durationSeconds = durationSeconds
        self.includedPreRollSeconds = includedPreRollSeconds
    }
}
