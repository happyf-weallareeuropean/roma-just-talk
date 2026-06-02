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
        case "windows-hotkey-doctor":
            printWindowsHotKeyDoctor()
        case "windows-hotkey-proof":
            try runWindowsHotKeyProof()
        case "windows-paste-doctor":
            printWindowsPasteDoctor()
        case "windows-paste-proof":
            try runWindowsPasteProof(arguments: Array(arguments.dropFirst()))
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
        print("windows_register_hotkey_adapter_source=true")
        print("windows_paste_adapter_source=true")
    }

    private static func printWindowsHotKeyDoctor() {
        let hotKey = WindowsHotKey.proofToggle
        print("platform=\(platformName)")
        print("hotkey=\(hotKey.displayName)")
        print("hotkey_id=\(hotKey.id)")
        print("modifiers_raw=0x\(String(hotKey.modifiers.rawValue, radix: 16, uppercase: true))")
        print("virtual_key=0x\(String(hotKey.virtualKeyCode, radix: 16, uppercase: true))")
        print("api=RegisterHotKey")
        print("mode=toggle")
        print("permission_prompt=false")
        #if os(Windows)
        print("windows_hotkey_runtime=true")
        #else
        print("windows_hotkey_runtime=false")
        #endif
    }

    private static func runWindowsHotKeyProof() throws {
        let hotKey = WindowsHotKey.proofToggle

        #if os(Windows)
        print("waiting_for=\(hotKey.displayName)")
        try WindowsRegisterHotKeyProof.waitForSingleTrigger(hotKey: hotKey)
        print("hotkey_received=true")
        #else
        throw AgentError.unsupportedPlatform("windows-hotkey-proof requires Windows")
        #endif
    }

    private static func printWindowsPasteDoctor() {
        let proofText = "roma just talk proof"
        let payload = WindowsClipboardPayload.cfUnicodeTextData(for: proofText)
        print("platform=\(platformName)")
        print("clipboard_format=CF_UNICODETEXT")
        print("clipboard_payload_bytes=\(payload.count)")
        print("input_api=SendInput")
        print("paste_chord=Ctrl+V")
        print("permission_prompt=false")
        print("integrity_limit=equal_or_lower")
        #if os(Windows)
        print("windows_paste_runtime=true")
        #else
        print("windows_paste_runtime=false")
        #endif
    }

    private static func runWindowsPasteProof(arguments: [String]) throws {
        let text = try value(after: "--text", in: arguments)

        #if os(Windows)
        try WindowsPasteProof.pasteText(text)
        print("paste_sent=true")
        print("text_utf16_bytes=\(WindowsClipboardPayload.cfUnicodeTextData(for: text).count)")
        #else
        throw AgentError.unsupportedPlatform("windows-paste-proof requires Windows")
        #endif
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
        print("  RomaProofAgent windows-hotkey-doctor")
        print("  RomaProofAgent windows-hotkey-proof")
        print("  RomaProofAgent windows-paste-doctor")
        print("  RomaProofAgent windows-paste-proof --text \"roma just talk proof\"")
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
    case unsupportedPlatform(String)

    var description: String {
        switch self {
        case .missingOption(let option):
            return "missing required option \(option)"
        case .unsupportedPlatform(let message):
            return message
        }
    }
}
