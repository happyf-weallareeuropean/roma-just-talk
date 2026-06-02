import Foundation
import RomaCore

@main
struct RomaProofAgent {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        switch arguments.first {
        case "doctor":
            printDoctor()
        case "pre-roll-proof":
            try writePreRollProof(arguments: Array(arguments.dropFirst()))
        default:
            printUsage()
        }
    }

    private static func printDoctor() {
        print("platform=\(platformName)")
        print("swift_core=true")
        print("pre_roll_seconds=\(PreRollConfiguration().durationSeconds)")
        print("audio_format=pcm16_16000_mono")
        print("wav_writer=true")
        print("native_windows_adapters=false")
    }

    private static func writePreRollProof(arguments: [String]) throws {
        let outputURL = URL(fileURLWithPath: try value(after: "--out", in: arguments))
        let format = AudioChunkFormat.speechPCM16kMono
        let sampleRate = format.sampleRate
        let buffer = PCMPreRollBuffer(configuration: PreRollConfiguration(durationSeconds: 3, outputFormat: format))

        let beforeHotkeySamples = tone(frequency: 440, seconds: 2, sampleRate: sampleRate)
        let afterHotkeySamples = tone(frequency: 880, seconds: 1, sampleRate: sampleRate)

        buffer.append(samples: beforeHotkeySamples)
        let capturedPreRoll = buffer.snapshotSamples()
        let proofSamples = capturedPreRoll + afterHotkeySamples

        try PCM16WAVFile.write(samples: proofSamples, to: outputURL, format: format)

        print("wrote=\(outputURL.path)")
        print("pre_roll_samples=\(capturedPreRoll.count)")
        print("after_hotkey_samples=\(afterHotkeySamples.count)")
        print("sample_rate=\(sampleRate)")
        print("channels=\(format.channelCount)")
    }

    private static func value(after option: String, in arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            throw AgentError.missingOption(option)
        }
        return arguments[index + 1]
    }

    private static func tone(frequency: Double, seconds: Double, sampleRate: Int) -> [Int16] {
        let sampleCount = Int(Double(sampleRate) * seconds)
        return (0..<sampleCount).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
            let amplitude = sin(phase) * 12_000
            return Int16(amplitude)
        }
    }

    private static func printUsage() {
        print("usage:")
        print("  RomaProofAgent doctor")
        print("  RomaProofAgent pre-roll-proof --out proof.wav")
    }

    private static var platformName: String {
        #if os(Windows)
        return "windows"
        #elseif os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #else
        return "unknown"
        #endif
    }
}

private enum AgentError: Error, CustomStringConvertible {
    case missingOption(String)

    var description: String {
        switch self {
        case .missingOption(let option):
            return "missing required option \(option)"
        }
    }
}
