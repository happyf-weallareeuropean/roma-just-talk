import Foundation
import RomaCore

@main
struct RomaCoreChecks {
    static func main() async throws {
        try checkDefaultPreRollContract()
        try checkPreRollBufferKeepsChronologicalSamples()
        try checkPCM16WAVFileWritesCanonicalHeader()
        try checkTranscriptionRequestMetadata()
        try await checkFakeAdaptersSatisfyCorePorts()
        try checkSourcesDoNotImportApplePlatformFrameworks()
    }

    private static func checkDefaultPreRollContract() throws {
        let configuration = PreRollConfiguration()

        try require(configuration.durationSeconds == 3, "default pre-roll should stay at 3 seconds")
        try require(configuration.outputFormat == .speechPCM16kMono, "default format should be speechPCM16kMono")
        try require(configuration.outputFormat.sampleRate == 16_000, "sample rate should be 16 kHz")
        try require(configuration.outputFormat.channelCount == 1, "channel count should be mono")
        try require(configuration.outputFormat.sampleFormat == .signedInteger16, "sample format should be Int16")
    }

    private static func checkPreRollBufferKeepsChronologicalSamples() throws {
        let buffer = PCMPreRollBuffer(sampleRate: 5, seconds: 1)

        try require(buffer.capacitySamples == 5, "pre-roll capacity should derive from sample rate and seconds")
        try require(buffer.snapshotSamples().isEmpty, "empty pre-roll buffer should snapshot empty")

        buffer.append(samples: [1, 2, 3])
        try require(buffer.snapshotSamples() == [1, 2, 3], "pre-roll should preserve initial order")

        buffer.append(samples: [4, 5, 6])
        try require(
            buffer.snapshotSamples() == [2, 3, 4, 5, 6],
            "pre-roll should keep newest samples in chronological order after wrap"
        )
        try require(buffer.availableSampleCount == 5, "pre-roll should report capacity when full")

        let data = buffer.snapshotData()
        try require(data.count == 10, "pre-roll snapshot data should be Int16 PCM")
        let decodedData = try decodeInt16LittleEndian(data)
        try require(
            decodedData == [2, 3, 4, 5, 6],
            "pre-roll data should round-trip as little-endian Int16"
        )

        buffer.append(samples: [10, 11, 12, 13, 14, 15, 16])
        try require(
            buffer.snapshotSamples() == [12, 13, 14, 15, 16],
            "oversized append should keep last capacity samples"
        )

        buffer.clear()
        try require(buffer.availableSampleCount == 0, "clear should reset available samples")
        try require(buffer.snapshotSamples().isEmpty, "clear should reset snapshot")
    }

    private static func checkPCM16WAVFileWritesCanonicalHeader() throws {
        let samples: [Int16] = [0, 32_767, -32_768, 42]
        let format = AudioChunkFormat(sampleRate: 8_000, channelCount: 1, sampleFormat: .signedInteger16)
        let wavData = try PCM16WAVFile.makeData(samples: samples, format: format)

        try require(wavData.count == 52, "WAV data should include 44 byte header plus sample bytes")
        try require(try asciiString(wavData, offset: 0, count: 4) == "RIFF", "WAV should start with RIFF")
        try require(try readUInt32LittleEndian(wavData, offset: 4) == 44, "RIFF chunk size should include payload")
        try require(try asciiString(wavData, offset: 8, count: 4) == "WAVE", "WAV should identify WAVE format")
        try require(try asciiString(wavData, offset: 12, count: 4) == "fmt ", "WAV should include fmt chunk")
        try require(try readUInt32LittleEndian(wavData, offset: 16) == 16, "fmt chunk should be PCM size")
        try require(try readUInt16LittleEndian(wavData, offset: 20) == 1, "audio format should be PCM")
        try require(try readUInt16LittleEndian(wavData, offset: 22) == 1, "channel count should be mono")
        try require(try readUInt32LittleEndian(wavData, offset: 24) == 8_000, "sample rate should be encoded")
        try require(try readUInt32LittleEndian(wavData, offset: 28) == 16_000, "byte rate should be encoded")
        try require(try readUInt16LittleEndian(wavData, offset: 32) == 2, "block align should be encoded")
        try require(try readUInt16LittleEndian(wavData, offset: 34) == 16, "bits per sample should be Int16")
        try require(try asciiString(wavData, offset: 36, count: 4) == "data", "WAV should include data chunk")
        try require(try readUInt32LittleEndian(wavData, offset: 40) == 8, "data chunk size should match PCM bytes")
        try require(
            try decodeInt16LittleEndian(wavData.subdata(in: 44..<wavData.count)) == samples,
            "WAV payload should be little-endian Int16 PCM"
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-core-wav-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try PCM16WAVFile.write(samples: samples, to: outputURL, format: format)
        try require(try Data(contentsOf: outputURL) == wavData, "WAV file write should round-trip bytes")

        do {
            _ = try PCM16WAVFile.makeData(pcmData: Data([0]), format: format)
            throw CheckFailure("unaligned PCM should be rejected")
        } catch PCM16WAVFile.WriteError.pcmDataNotInt16Aligned(let byteCount) {
            try require(byteCount == 1, "unaligned PCM error should report byte count")
        }
    }

    private static func checkTranscriptionRequestMetadata() throws {
        let model = TranscriptionModelDescriptor(
            name: "ggml-base.en",
            displayName: "Whisper Base English",
            provider: .whisper,
            supportedLanguages: ["en": "English"]
        )
        let request = TranscriptionRequest(
            audioURL: URL(fileURLWithPath: "/tmp/proof.wav"),
            model: model,
            language: "en",
            prompt: "short dictation",
            customVocabulary: ["roma"]
        )

        try require(request.model.provider == .whisper, "request should carry provider")
        try require(request.language == "en", "request should carry language")
        try require(request.customVocabulary == ["roma"], "request should carry vocabulary")
    }

    private static func checkFakeAdaptersSatisfyCorePorts() async throws {
        let recorder = FakeRecorder()
        let inserter = FakeTextInsertion()
        let transcriber = FakeTranscriptionService()

        try await recorder.startPreRollBuffering()
        try await recorder.startRecording(toOutputFile: URL(fileURLWithPath: "/tmp/proof.wav"))
        let recordedAudio = try await recorder.finishRecording()

        let model = TranscriptionModelDescriptor(
            name: "cloud-proof",
            displayName: "Cloud Proof",
            provider: .custom
        )
        let result = try await transcriber.transcribe(
            TranscriptionRequest(audioURL: recordedAudio.fileURL, model: model)
        )
        try await inserter.pasteAtCursor(result.text)

        try require(recordedAudio.includedPreRollSeconds == 3, "recorded audio should report pre-roll")
        try require(result.text == "roma just talk proof", "transcription should return proof text")
        let pastedText = await inserter.pastedText
        try require(pastedText == "roma just talk proof", "text insertion should receive proof text")
    }

    private static func checkSourcesDoNotImportApplePlatformFrameworks() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot.appendingPathComponent("Sources/RomaCore")
        let bannedImports = [
            "AppKit",
            "ApplicationServices",
            "AudioToolbox",
            "AVFoundation",
            "Carbon",
            "Charts",
            "Cocoa",
            "CoreAudio",
            "CoreGraphics",
            "CoreML",
            "FluidAudio",
            "IOKit",
            "LaunchAtLogin",
            "MediaRemoteAdapter",
            "NaturalLanguage",
            "PermissionFlow",
            "ScreenCaptureKit",
            "Security",
            "SelectedTextKit",
            "Sparkle",
            "Speech",
            "SwiftData",
            "SwiftUI",
            "UniformTypeIdentifiers",
            "Vision",
            "whisper"
        ]

        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            throw CheckFailure("could not enumerate \(sourcesRoot.path)")
        }

        let swiftFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }

        try require(!swiftFiles.isEmpty, "RomaCore should contain Swift sources")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for bannedImport in bannedImports {
                try require(
                    !source.contains("import \(bannedImport)"),
                    "\(file.path) imports \(bannedImport), which blocks Windows portability"
                )
            }
        }
    }

    private static func asciiString(_ data: Data, offset: Int, count: Int) throws -> String {
        try require(offset >= 0, "offset should be nonnegative")
        try require(count >= 0, "count should be nonnegative")
        try require(offset + count <= data.count, "ASCII read should stay inside data")

        return String(decoding: data[offset..<(offset + count)], as: UTF8.self)
    }

    private static func readUInt16LittleEndian(_ data: Data, offset: Int) throws -> UInt16 {
        try require(offset >= 0, "offset should be nonnegative")
        try require(offset + 2 <= data.count, "UInt16 read should stay inside data")

        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LittleEndian(_ data: Data, offset: Int) throws -> UInt32 {
        try require(offset >= 0, "offset should be nonnegative")
        try require(offset + 4 <= data.count, "UInt32 read should stay inside data")

        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func decodeInt16LittleEndian(_ data: Data) throws -> [Int16] {
        try require(data.count.isMultiple(of: MemoryLayout<Int16>.size), "PCM data should be Int16-aligned")

        return stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size).map { offset in
            let low = UInt16(data[offset])
            let high = UInt16(data[offset + 1]) << 8
            return Int16(bitPattern: low | high)
        }
    }

    fileprivate static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private enum FakeRecorderError: Error {
    case missingOutputFile
}

private final class FakeRecorder: RollingRecorder, @unchecked Sendable {
    var onAudioChunk: (@Sendable (Data) -> Void)?
    let preRollConfiguration = PreRollConfiguration()
    private var outputFile: URL?

    func startPreRollBuffering() async throws {}

    func startRecording(toOutputFile url: URL) async throws {
        outputFile = url
    }

    func finishRecording() async throws -> RecordedAudio {
        guard let outputFile else { throw FakeRecorderError.missingOutputFile }
        return RecordedAudio(
            fileURL: outputFile,
            durationSeconds: 5,
            includedPreRollSeconds: preRollConfiguration.durationSeconds
        )
    }

    func stopCapture() async {}
}

private actor FakeTextInsertion: TextInsertion {
    private(set) var pastedText: String?

    func pasteAtCursor(_ text: String) async throws {
        pastedText = text
    }
}

private struct FakeTranscriptionService: TranscriptionService {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try RomaCoreChecks.require(request.audioURL.lastPathComponent == "proof.wav", "request should carry proof.wav")
        return TranscriptionResult(text: "roma just talk proof")
    }
}
