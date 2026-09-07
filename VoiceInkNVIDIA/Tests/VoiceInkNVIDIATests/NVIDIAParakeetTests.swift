import XCTest
import GRPCCore
@testable import VoiceInkNVIDIA

@available(macOS 15, iOS 18, *)
final class NVIDIAParakeetTests: XCTestCase {
    func testRequestMatchesRivaWireContractAndKeepsPCMUnchanged() throws {
        let request = try NVIDIAParakeetClient.recognitionRequest(
            pcm16Data: Data([0, 0, 1, 0]), apiKey: " test-key "
        )
        // Official Riva field numbers: config=1, audio=2; LINEAR_PCM=1, 16kHz, zh-TW.
        let expected = Data([
            0x0a, 0x12, 0x08, 0x01, 0x10, 0x80, 0x7d,
            0x1a, 0x05, 0x7a, 0x68, 0x2d, 0x54, 0x57,
            0x20, 0x01, 0x38, 0x01, 0x58, 0x01,
            0x12, 0x04, 0x00, 0x00, 0x01, 0x00
        ])
        XCTAssertEqual(try request.message.serializedData(), expected)
        XCTAssertEqual(Array(request.metadata[stringValues: "authorization"]), ["Bearer test-key"])
        XCTAssertEqual(Array(request.metadata[stringValues: "function-id"]), ["8473f56d-51ef-473c-bb26-efd4f5def2bf"])
        XCTAssertEqual(Nvidia_Riva_Asr_RivaSpeechRecognition.Method.Recognize.descriptor.fullyQualifiedMethod, "nvidia.riva.asr.RivaSpeechRecognition/Recognize")
    }

    func testEmptyAndTruncatedPCMAndHeaderInjectionAreRejectedBeforeNetwork() throws {
        for data in [Data(), Data([1])] {
            XCTAssertThrowsError(try NVIDIAParakeetClient.recognitionRequest(pcm16Data: data, apiKey: "key"))
        }
        for key in ["", "  ", "key\r\ninjected: header"] {
            XCTAssertThrowsError(try NVIDIAParakeetClient.recognitionRequest(pcm16Data: Data([0, 0]), apiKey: key))
        }
    }

    func testResultsKeepTraditionalChineseAndEnglishAndOnlyUseBestAlternative() throws {
        var response = Nvidia_Riva_Asr_RecognizeResponse()
        response.results = [
            .with { $0.alternatives = [.with { $0.transcript = "  臺灣 API " }, .with { $0.transcript = "wrong" }] },
            .with { $0.alternatives = [.with { $0.transcript = "server 測試。\n" }] }
        ]
        XCTAssertEqual(try NVIDIAParakeetClient.transcript(from: response), "臺灣 API server 測試。")
        XCTAssertThrowsError(try NVIDIAParakeetClient.transcript(from: .init()))
        response.results = [.with { $0.alternatives = [.with { $0.transcript = " \n" }] }]
        XCTAssertThrowsError(try NVIDIAParakeetClient.transcript(from: response))
    }
}
