import Foundation
import VoiceInkCore

final class NVIDIACloudModelTests: XCTestCase {
    func testNVIDIAIsOptionalCloudAndRequiresBothKeyAndSupportedOS() {
        let provider = VoiceInkMacOSTranscriptionModelProvider.nvidia
        XCTAssertEqual(provider.transcriptionServiceRoute, .cloud)
        XCTAssertEqual(provider.transcriptionModelAvailabilityRequirement, .configuredAPIKeyAndCurrentOSSupport)
        XCTAssertEqual(provider.cloudModelSpecs.map(\.name), ["parakeet-ctc-0.6b-zh-tw"])
        XCTAssertFalse(provider.cloudModelSpecs[0].supportsStreaming)
        XCTAssertEqual(VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel.name, "parakeet-tdt-0.6b-v2")
        for key in [false, true] {
            for os in [false, true] {
                XCTAssertEqual(VoiceInkTranscriptionModelAvailabilityFacts(
                    requirement: provider.transcriptionModelAvailabilityRequirement,
                    hasConfiguredAPIKey: key, isAvailableOnCurrentOS: os
                ).isUsable, key && os)
            }
        }
        XCTAssertEqual(VoiceInkProviderAPIKeyAccount.accountIdentifier(forProviderName: "NVIDIA"), "nvidiaAPIKey")
        XCTAssertEqual(VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: nil, provider: .nvidia, environment: ["NVIDIA_API_KEY": "test-key"]
        ), "test-key")
        XCTAssertFalse(VoiceInkProviderKind.nvidia.supportsModelUse(.postProcessing))
    }

    func testProviderRepairNeverSilentlyRoutesAudioIntoOrOutOfNVIDIA() {
        var mode = Mode.defaultLocalWhisper()
        mode.repairProviderSelection(availableTranscriptionProviders: [.nvidia], availablePostProcessingProviders: [])
        XCTAssertEqual(mode.transcriptionProvider, .localWhisper)
        mode.selectTranscriptionProvider(.nvidia)
        XCTAssertEqual(mode.transcriptionProvider, .nvidia)
        mode.repairProviderSelection(availableTranscriptionProviders: [.groq], availablePostProcessingProviders: [])
        XCTAssertEqual(mode.transcriptionProvider, .nvidia)
    }

    func testCloudEntryPointRejectsMissingKeyAndMalformedAudioBeforeNetwork() async {
        for (key, audio) in [(Optional<String>.none, Data()), ("test-key", Data("not WAV".utf8))] {
            do {
                _ = try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                    modelProvider: .nvidia, apiKey: key, modelName: "parakeet-ctc-0.6b-zh-tw",
                    audioData: audio, fileName: "audio.wav", language: "en", prompt: nil, customVocabulary: []
                )
                XCTFail("Invalid local request must not reach NVIDIA.")
            } catch VoiceInkCloudTranscriptionError.missingAPIKey {
                XCTAssertNil(key)
            } catch VoiceInkCloudTranscriptionError.invalidAudioFormat {
                XCTAssertTrue(key != nil)
            } catch VoiceInkCloudTranscriptionError.unsupportedOperatingSystem {
                if #available(macOS 15, iOS 18, *) { XCTFail("Supported OS was rejected.") }
            } catch {
                XCTFail("Expected local validation error, received: \(error)")
            }
        }
    }
}
