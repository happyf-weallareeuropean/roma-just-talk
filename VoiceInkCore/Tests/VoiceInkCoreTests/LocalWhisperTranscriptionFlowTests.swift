import Foundation
import VoiceInkCore

final class LocalWhisperTranscriptionFlowTests: XCTestCase {

    func testRequestBuildersPreservePlatformDefaults() {
        let suiteName = "LocalWhisperTranscriptionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
        VoiceInkTranscriptionPromptPreference.savePrompt("custom local prompt", to: defaults)

        let audioURL = URL(fileURLWithPath: "/tmp/input.wav")
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, defaults: defaults),
            VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "fr",
                prompt: "custom local prompt",
                failurePlatform: .macOS,
                mapsThrownAudioSampleErrors: false
            )
        )
        let englishOnlyRequest = VoiceInkLocalWhisperTranscriptionRequest.macOS(
            audioURL: audioURL, isMultilingual: false, defaults: defaults
        )
        XCTAssertEqual(englishOnlyRequest.language, "en")
        XCTAssertEqual(englishOnlyRequest.prompt, VoiceInkLocalWhisperPromptCatalog.prompt(for: "en"))
        XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "fr")
        XCTAssertEqual(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults), "custom local prompt")
        XCTAssertEqual(VoiceInkLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, defaults: defaults).language, "fr")
        VoiceInkTranscriptionPromptPreference.saveLocalWhisperCustomPrompt("English prompt edit", for: "en", to: defaults)
        XCTAssertEqual(VoiceInkLocalWhisperTranscriptionRequest.macOS(
            audioURL: audioURL, isMultilingual: false, defaults: defaults
        ).prompt, "English prompt edit")
        XCTAssertEqual(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults), "custom local prompt")
        VoiceInkTranscriptionPromptPreference.saveLocalWhisperCustomPrompt("French prompt edit", for: "fr", to: defaults)
        XCTAssertEqual(VoiceInkLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, defaults: defaults).prompt, "French prompt edit")
        XCTAssertEqual(
            VoiceInkLocalWhisperTranscriptionRequest.iOS(audioURL: audioURL, language: "de", prompt: nil),
            VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "de",
                prompt: "",
                failurePlatform: .iOS
            )
        )
    }

    func testFlowRunsTranscriptionAndReleasesOwnedContext() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/input.wav")
        let context = StubLocalWhisperContext(text: "hello")

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: "en",
                prompt: "names: Roma",
                failurePlatform: .iOS
            ),
            actions: actions(
                context: context,
                shouldReleaseContext: true,
                samples: [0.1, 0.2],
                expectedAudioURL: audioURL
            )
        )

        XCTAssertEqual(text, "hello")
        XCTAssertEqual(context.samples, [0.1, 0.2])
        XCTAssertEqual(context.language, "en")
        XCTAssertEqual(context.prompt, "names: Roma")
        XCTAssertEqual(context.releaseCount, 1)
    }

    func testFlowLeavesBorrowedContextLoaded() async throws {
        let context = StubLocalWhisperContext(text: "shared model")

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
                failurePlatform: .macOS
            ),
            actions: actions(context: context, shouldReleaseContext: false)
        )

        XCTAssertEqual(text, "shared model")
        XCTAssertEqual(context.releaseCount, 0)
    }

    func testFlowMapsMissingSamplesToPlatformAudioFailureAndReleasesContext() async throws {
        let context = StubLocalWhisperContext()

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/bad.wav"),
                    failurePlatform: .iOS
                ),
                actions: actions(context: context, shouldReleaseContext: true, samples: nil)
            )
            XCTFail("Expected audio processing failure")
        } catch {
            XCTAssertEqual(errorName(error), "audioProcessingFailed")
            XCTAssertEqual(context.releaseCount, 1)
        }
    }

    func testFlowMapsFailedTranscriptionToPlatformFailureAndReleasesContext() async throws {
        let context = StubLocalWhisperContext(shouldSucceed: false)

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/input.wav"),
                    failurePlatform: .macOS
                ),
                actions: actions(context: context, shouldReleaseContext: true)
            )
            XCTFail("Expected transcription failure")
        } catch {
            XCTAssertEqual(errorName(error), "whisperCoreFailed")
            XCTAssertEqual(context.releaseCount, 1)
        }
    }

    func testFlowCanPreserveShellThrownSampleErrorsAndFailureLifetime() async throws {
        let context = StubLocalWhisperContext()

        do {
            _ = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
                request: VoiceInkLocalWhisperTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/missing.wav"),
                    failurePlatform: .macOS,
                    mapsThrownAudioSampleErrors: false
                ),
                actions: actions(
                    context: context,
                    shouldReleaseContext: true,
                    shouldReleaseContextOnFailure: false,
                    readError: StubAudioReadError.readFailed
                )
            )
            XCTFail("Expected shell audio read error")
        } catch StubAudioReadError.readFailed {
            XCTAssertEqual(context.releaseCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThreadCountKeepsExistingBounds() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 1), 1)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 4), 2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.threadCount(processorCount: 12), 8)
    }

    func testRuntimeConstantsMatchExistingWhisperWrappers() {
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.printRealtime)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.printProgress)
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.printTimestamps)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.printSpecial)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.translate)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.offsetMilliseconds, 0)
        XCTAssertTrue(VoiceInkWhisperRuntimeDefaults.noContext)
        XCTAssertFalse(VoiceInkWhisperRuntimeDefaults.singleSegment)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.transcriptionTemperature, 0.2)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingTargetPeak, 12_000)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingNoiseFloorPeak, 32)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.audioLevelingMaxGain, 16)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadThreshold, 0.50)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs, 250)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs, 100)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs, 30)
        XCTAssertEqual(VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap, 0.1)
    }

    func testRuntimeDiagnosticsPreserveExistingWhisperWrapperLogText() {
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.logCategory, "WhisperContext")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.simulatorCPUModeMessage, "Running on the simulator, using CPU")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.metalFlashAttentionMessage, "Flash attention enabled for Metal")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.vadBundleModelLoadedMessage, "VAD model loaded from bundle resources")
        XCTAssertEqual(VoiceInkWhisperRuntimeDiagnostics.vadModelPathMissingWarningMessage, "VAD model path not found, VAD will be disabled.")
        XCTAssertEqual(
            VoiceInkWhisperRuntimeDiagnostics.transcriptionFailedMessage(
                isVADEnabled: true,
                platform: .macOS
            ),
            "❌ Failed to run whisper_full. VAD enabled: true"
        )
        XCTAssertEqual(
            VoiceInkWhisperRuntimeDiagnostics.transcriptionFailedMessage(
                isVADEnabled: false,
                platform: .iOS
            ),
            "Failed to run whisper_full. VAD enabled: false"
        )
        XCTAssertEqual(
            VoiceInkWhisperRuntimeDiagnostics.modelLoadFailedMessagePrefix(platform: .macOS),
            "❌ Couldn't load model at"
        )
        XCTAssertEqual(
            VoiceInkWhisperRuntimeDiagnostics.modelLoadFailedMessagePrefix(platform: .iOS),
            "Couldn't load model at"
        )
    }

    func testContextRuntimePlanPreservesSimulatorAndDeviceInitializationPolicy() {
        XCTAssertEqual(
            VoiceInkWhisperContextRuntimePlan.current(environment: .simulator),
            VoiceInkWhisperContextRuntimePlan(
                useGPU: false,
                flashAttention: nil,
                diagnosticMessage: VoiceInkWhisperRuntimeDiagnostics.simulatorCPUModeMessage
            )
        )
        XCTAssertEqual(
            VoiceInkWhisperContextRuntimePlan.current(environment: .device),
            VoiceInkWhisperContextRuntimePlan(
                useGPU: nil,
                flashAttention: true,
                diagnosticMessage: VoiceInkWhisperRuntimeDiagnostics.metalFlashAttentionMessage
            )
        )
    }

    func testContextRuntimePlanAppliesSimulatorParametersWithoutOverwritingFlashAttention() {
        var params = StubWhisperContextParameters(use_gpu: true, flash_attn: true)

        VoiceInkWhisperContextRuntimePlan.current(environment: .simulator).apply(to: &params)

        XCTAssertFalse(params.use_gpu)
        XCTAssertTrue(params.flash_attn)
    }

    func testContextRuntimePlanAppliesDeviceParametersWithoutOverwritingGPUDefault() {
        var params = StubWhisperContextParameters(use_gpu: false, flash_attn: false)

        VoiceInkWhisperContextRuntimePlan.current(environment: .device).apply(to: &params)

        XCTAssertFalse(params.use_gpu)
        XCTAssertTrue(params.flash_attn)
    }

    func testVADRuntimeConfigurationRequiresEnabledPreferenceAndModelPath() {
        XCTAssertEqual(
            VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "/tmp/vad.bin", isEnabled: true),
            VoiceInkWhisperVADRuntimeConfiguration(modelPath: "/tmp/vad.bin")
        )
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "/tmp/vad.bin", isEnabled: false))
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: nil, isEnabled: true))
        XCTAssertNil(VoiceInkWhisperVADRuntimeConfiguration.current(modelPath: "", isEnabled: true))
    }

    func testRuntimeOptionsPreserveExistingWhisperCppFlags() {
        XCTAssertEqual(
            VoiceInkWhisperRuntimeOptions(),
            VoiceInkWhisperRuntimeOptions(
                printRealtime: true,
                printProgress: false,
                printTimestamps: true,
                printSpecial: false,
                translate: false,
                offsetMilliseconds: 0,
                noContext: true,
                singleSegment: false
            )
        )
    }

    func testRuntimeConfigurationBuildsSharedWhisperInputs() {
        withTemporaryDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(true, to: defaults)

            let configuration = VoiceInkWhisperRuntimeConfiguration.current(
                language: "ja",
                prompt: "Use Japanese punctuation.",
                vadModelPath: "/tmp/vad.bin",
                defaults: defaults,
                processorCount: 6
            )

            XCTAssertEqual(configuration.language, "ja")
            XCTAssertEqual(configuration.prompt, "Use Japanese punctuation.")
            XCTAssertEqual(configuration.options, VoiceInkWhisperRuntimeOptions())
            XCTAssertEqual(configuration.threadCount, 4)
            XCTAssertEqual(configuration.temperature, VoiceInkWhisperRuntimeDefaults.transcriptionTemperature)
            XCTAssertEqual(configuration.vad?.modelPath, "/tmp/vad.bin")
            XCTAssertEqual(configuration.vad?.threshold, VoiceInkWhisperRuntimeDefaults.vadThreshold)
            XCTAssertEqual(configuration.vad?.minSpeechDurationMs, VoiceInkWhisperRuntimeDefaults.vadMinSpeechDurationMs)
            XCTAssertEqual(configuration.vad?.minSilenceDurationMs, VoiceInkWhisperRuntimeDefaults.vadMinSilenceDurationMs)
            XCTAssertEqual(configuration.vad?.maxSpeechDurationSeconds, VoiceInkWhisperRuntimeDefaults.vadMaxSpeechDurationSeconds)
            XCTAssertEqual(configuration.vad?.speechPadMs, VoiceInkWhisperRuntimeDefaults.vadSpeechPadMs)
            XCTAssertEqual(configuration.vad?.samplesOverlap, VoiceInkWhisperRuntimeDefaults.vadSamplesOverlap)
        }
    }

    func testRuntimeConfigurationAppliesSharedWhisperFullParameterSink() {
        var params = StubWhisperFullParameters()
        var madeVADParameters = false
        let configuration = VoiceInkWhisperRuntimeConfiguration(
            options: VoiceInkWhisperRuntimeOptions(
                printRealtime: false,
                printProgress: true,
                printTimestamps: false,
                printSpecial: true,
                translate: true,
                offsetMilliseconds: 42,
                noContext: false,
                singleSegment: true
            ),
            threadCount: 3,
            temperature: 0.7,
            vad: nil
        )

        configuration.apply(to: &params) {
            madeVADParameters = true
            return StubWhisperVADParameters()
        }

        XCTAssertFalse(params.print_realtime)
        XCTAssertTrue(params.print_progress)
        XCTAssertFalse(params.print_timestamps)
        XCTAssertTrue(params.print_special)
        XCTAssertTrue(params.translate)
        XCTAssertEqual(params.n_threads, 3)
        XCTAssertEqual(params.offset_ms, 42)
        XCTAssertFalse(params.no_context)
        XCTAssertTrue(params.single_segment)
        XCTAssertEqual(params.temperature, 0.7, accuracy: 0.0001)
        XCTAssertFalse(params.vad)
        XCTAssertNil(params.vad_model_path)
        XCTAssertFalse(madeVADParameters)
    }

    func testRuntimeConfigurationAppliesSharedWhisperVADParameterSink() {
        var params = StubWhisperFullParameters()
        let configuration = VoiceInkWhisperRuntimeConfiguration(
            vad: VoiceInkWhisperVADRuntimeConfiguration(
                modelPath: "/tmp/vad.bin",
                threshold: 0.65,
                minSpeechDurationMs: 120,
                minSilenceDurationMs: 230,
                maxSpeechDurationSeconds: 45,
                speechPadMs: 34,
                samplesOverlap: 0.25
            )
        )

        configuration.apply(to: &params) {
            StubWhisperVADParameters()
        }

        XCTAssertTrue(params.vad)
        XCTAssertNil(params.vad_model_path)
        XCTAssertEqual(params.vad_params.threshold, 0.65, accuracy: 0.0001)
        XCTAssertEqual(params.vad_params.min_speech_duration_ms, 120)
        XCTAssertEqual(params.vad_params.min_silence_duration_ms, 230)
        XCTAssertEqual(params.vad_params.max_speech_duration_s, 45, accuracy: 0.0001)
        XCTAssertEqual(params.vad_params.speech_pad_ms, 34)
        XCTAssertEqual(params.vad_params.samples_overlap, 0.25, accuracy: 0.0001)
    }

    func testRuntimeConfigurationNormalizesWhisperRequestLanguage() {
        XCTAssertEqual(
            VoiceInkWhisperRuntimeConfiguration.current(language: " fr ").language,
            "fr"
        )
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: "auto").language)
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: "  ").language)
        XCTAssertNil(VoiceInkWhisperRuntimeConfiguration.current(language: nil).language)
    }

    func testRuntimeConfigurationDisablesVADWhenPreferenceIsOff() {
        withTemporaryDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)

            let configuration = VoiceInkWhisperRuntimeConfiguration.current(
                vadModelPath: "/tmp/vad.bin",
                defaults: defaults
            )

            XCTAssertNil(configuration.vad)
        }
    }

    func testRuntimeInvocationPlanKeepsWhisperCStringInputsAlive() {
        let plan = VoiceInkWhisperRuntimeInvocationPlan(
            configuration: VoiceInkWhisperRuntimeConfiguration(
                language: "ja",
                prompt: "Use Japanese punctuation.",
                vad: VoiceInkWhisperVADRuntimeConfiguration(modelPath: "/tmp/vad.bin")
            )
        )

        let strings = plan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            [
                languagePointer.map { String(cString: $0) },
                promptPointer.map { String(cString: $0) },
                vadModelPathPointer.map { String(cString: $0) }
            ]
        }

        let expectedStrings: [String?] = ["ja", "Use Japanese punctuation.", "/tmp/vad.bin"]
        XCTAssertEqual(strings, expectedStrings)
    }

    func testRuntimeInvocationPlanOmitsDisabledWhisperInputs() {
        let plan = VoiceInkWhisperRuntimeInvocationPlan(
            configuration: VoiceInkWhisperRuntimeConfiguration(
                language: nil,
                prompt: nil,
                vad: nil
            )
        )

        let hasPointers = plan.withUnsafeCStringPointers { languagePointer, promptPointer, vadModelPathPointer in
            [
                languagePointer != nil,
                promptPointer != nil,
                vadModelPathPointer != nil
            ]
        }

        XCTAssertEqual(hasPointers, [false, false, false])
    }

    func testLocalWhisperFailurePolicyPreservesMacOSMapping() {
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: .macOS)),
            "modelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: .macOS)),
            "modelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: .macOS)),
            "audioProcessingFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: .macOS)),
            "whisperCoreFailed"
        )
    }

    func testLocalWhisperFailurePolicyPreservesIOSMapping() {
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: .iOS)),
            "localModelUnavailable"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: .iOS)),
            "localModelLoadFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: .iOS)),
            "audioProcessingFailed"
        )
        XCTAssertEqual(
            errorName(VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: .iOS)),
            "whisperTranscriptionFailed"
        )
    }

    func testJoinedTextConcatenatesSegmentsWithoutSeparator() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText([" hello", " world", "."]),
            " hello world."
        )
    }

    func testJoinedTextPreservesMacOSRawWhitespacePolicy() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(["  hello", "\nworld  "]),
            "  hello\nworld  "
        )
    }

    func testJoinedTextReturnsEmptyForNoSegments() {
        XCTAssertEqual(VoiceInkWhisperTranscriptSegments.joinedText([]), "")
    }

    func testJoinedTextFromSegmentLookupPreservesRawOrderAndSkipsMissingSegments() {
        let segments: [Int32: String] = [
            0: " hello",
            2: " world"
        ]

        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: 3) { segments[$0] },
            " hello world"
        )
    }

    func testJoinedTextFromSegmentLookupReturnsEmptyForNonPositiveCounts() {
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: 0) { _ in "ignored" },
            ""
        )
        XCTAssertEqual(
            VoiceInkWhisperTranscriptSegments.joinedText(segmentCount: -1) { _ in "ignored" },
            ""
        )
    }

    private func withTemporaryDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LocalWhisperTranscriptionFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        test(defaults)
    }

    private func actions(
        context: StubLocalWhisperContext,
        shouldReleaseContext: Bool,
        shouldReleaseContextOnFailure: Bool? = nil,
        samples: [Float]? = [0.3],
        expectedAudioURL: URL? = nil,
        readError: Error? = nil
    ) -> VoiceInkLocalWhisperTranscriptionActions<StubLocalWhisperContext> {
        VoiceInkLocalWhisperTranscriptionActions(
            resolveContext: {
                VoiceInkLocalWhisperContextPlan(
                    context: context,
                    shouldReleaseContext: shouldReleaseContext,
                    shouldReleaseContextOnFailure: shouldReleaseContextOnFailure
                )
            },
            readAudioSamples: { audioURL in
                if let expectedAudioURL {
                    XCTAssertEqual(audioURL, expectedAudioURL)
                }
                if let readError {
                    throw readError
                }
                return samples
            },
            runTranscription: { context, samples, language, prompt in
                context.samples = samples
                context.language = language
                context.prompt = prompt
                return context.shouldSucceed
            },
            transcriptionText: { context in
                context.text
            },
            releaseContext: { context in
                context.releaseCount += 1
            }
        )
    }

    private func errorName(_ error: Error) -> String {
        String(describing: error)
    }
}

private enum StubAudioReadError: Error {
    case readFailed
}

private final class StubLocalWhisperContext {
    var text: String
    var shouldSucceed: Bool
    var samples: [Float] = []
    var language: String?
    var prompt: String?
    var releaseCount = 0

    init(text: String = "", shouldSucceed: Bool = true) {
        self.text = text
        self.shouldSucceed = shouldSucceed
    }
}

private struct StubWhisperContextParameters: VoiceInkWhisperContextParameterSink {
    var use_gpu: Bool
    var flash_attn: Bool
}

private struct StubWhisperFullParameters: VoiceInkWhisperRuntimeFullParameterSink {
    var print_realtime = true
    var print_progress = false
    var print_timestamps = true
    var print_special = false
    var translate = false
    var n_threads: Int32 = 0
    var offset_ms: Int32 = 0
    var no_context = true
    var single_segment = false
    var temperature: Float = 0
    var vad = true
    var vad_model_path: UnsafePointer<CChar>?
    var vad_params = StubWhisperVADParameters()
}

private struct StubWhisperVADParameters: VoiceInkWhisperRuntimeVADParameterSink {
    var threshold: Float = 0
    var min_speech_duration_ms: Int32 = 0
    var min_silence_duration_ms: Int32 = 0
    var max_speech_duration_s: Float = 0
    var speech_pad_ms: Int32 = 0
    var samples_overlap: Float = 0
}
