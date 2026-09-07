import Foundation
import VoiceInkCore

final class TranscriptionModelCatalogTests: XCTestCase {
    func testAvailabilityRequirementPredicatesIdentifyShellFactsNeeded() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.configuredAPIKey.requiresCurrentOSSupport)
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresCurrentOSSupport)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.currentOSSupport.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.downloadedLocalWhisperModel.requiresCurrentOSSupport)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.alwaysAvailable.requiresConfiguredAPIKey)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityRequirement.unavailable.requiresCurrentOSSupport)
    }

    func testConfiguredAPIKeyRequirementUsesConfiguredKeyFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .configuredAPIKey,
            hasConfiguredAPIKey: false
        ).isUsable)
    }

    func testCurrentOSRequirementUsesCurrentOSFact() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: true
        ).isUsable)

        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .currentOSSupport,
            isAvailableOnCurrentOS: false
        ).isUsable)
    }

    func testLocalModelRequirementsUseDownloadedFacts() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalWhisperModel,
            isLocalWhisperModelDownloaded: false
        ).isUsable)

        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: true
        ).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(
            requirement: .downloadedLocalFluidAudioModel,
            isLocalFluidAudioModelDownloaded: false
        ).isUsable)
    }

    func testAlwaysAvailableAndUnavailableRequirementsStayExplicit() {
        XCTAssertTrue(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .alwaysAvailable).isUsable)
        XCTAssertFalse(VoiceInkTranscriptionModelAvailabilityFacts(requirement: .unavailable).isUsable)
    }

    func testLocalWhisperRoutePrewarmsAndLoadsWhisperAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["whisper"])
    }

    func testLocalFluidAudioRoutePrewarmsAndLoadsFluidAudioAtRecordingStartup() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertTrue(plan.shouldPrewarmModel)
        XCTAssertEqual(events, ["fluid"])
    }

    func testCloudRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testNativeAppleRouteSkipsLocalRuntimeWork() async {
        let plan = VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
        var events: [String] = []

        await plan.applyRecordingStartupRuntimeState(
            loadLocalWhisperModel: {
                events.append("whisper")
            },
            loadLocalFluidAudioModel: {
                events.append("fluid")
            }
        )

        XCTAssertFalse(plan.shouldPrewarmModel)
        XCTAssertEqual(events, [])
    }

    func testModelSelectionResourcePlanOwnsLocalWhisperRuntimeUpdate() {
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localWhisper)
                .modelSelectionLocalWhisperRuntimeUpdate),
            []
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .localFluidAudio)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
        XCTAssertEqual(
            localWhisperRuntimeUpdateEvents(for: VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .nativeApple)
                .modelSelectionLocalWhisperRuntimeUpdate),
            ["clearLoadedModel", "isModelLoaded:true"]
        )
    }

    func testDeletedCurrentModelPlanClearsSelectionAndMarksLocalWhisperUnloaded() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "ggml-base.en"
        )

        XCTAssertEqual(
            transcriptionModelDeletionEvents(for: plan),
            ["clearCurrentModel", "clearLoadedModel", "isModelLoaded:false"]
        )
    }

    func testDeletedNonCurrentModelPlanPreservesSelectionAndLocalWhisperRuntime() {
        let plan = VoiceInkTranscriptionModelDeletionPlan(
            currentModelName: "ggml-base.en",
            deletedModelName: "parakeet-tdt-0.6b-v2"
        )

        XCTAssertEqual(transcriptionModelDeletionEvents(for: plan), [])
    }

    private func localWhisperRuntimeUpdateEvents(for update: VoiceInkLocalWhisperRuntimeUpdate) -> [String] {
        var events: [String] = []

        update.applyRuntimeState(
            clearLoadedModel: { events.append("clearLoadedModel") },
            setIsModelLoaded: { events.append("isModelLoaded:\($0)") }
        )

        return events
    }

    private func transcriptionModelDeletionEvents(for plan: VoiceInkTranscriptionModelDeletionPlan) -> [String] {
        var events: [String] = []

        plan.applyRuntimeState(
            clearCurrentModel: { events.append("clearCurrentModel") },
            applyLocalWhisperRuntimeUpdate: {
                events.append(contentsOf: localWhisperRuntimeUpdateEvents(for: $0))
            }
        )

        return events
    }

    func testModelPrewarmUsesOneSecondMono16kSilence() {
        XCTAssertEqual(
            VoiceInkModelPrewarmSamplePolicy.generatedSilenceSampleCount,
            VoiceInkPCM16Audio.mono16kSampleRateHz
        )
    }

    func testWhisperModelPrewarmOnlyReusesMatchingLoadedContext() {
        XCTAssertTrue(
            VoiceInkWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: true,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-base.en.bin"
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: false,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-base.en.bin"
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelLoadPolicy.shouldReuseLoadedContext(
                hasContext: true,
                loadedModelName: "ggml-base.en.bin",
                requestedModelName: "ggml-small.en.bin"
            )
        )
    }

    func testModelPrewarmPlanUsesRuntimeAvailabilityWithoutAudioFixture() {
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: false,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).skipReason,
            .disabledByUser
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).skipReason,
            .missingCurrentModel
        )
        XCTAssertNil(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: false,
                shouldPrewarmModel: false
            ).diagnosticMessage
        )
        XCTAssertEqual(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: false
            ).diagnosticMessage,
            "Skipping prewarm - cloud models don't need it"
        )

        XCTAssertTrue(
            VoiceInkModelPrewarmPlan.plan(
                isEnabled: true,
                hasCurrentModel: true,
                shouldPrewarmModel: true
            ).shouldRun
        )
    }

    func testWhisperModelWarmupPolicySchedulesOnlyCoreMLModelsNotAlreadyWarming() {
        XCTAssertTrue(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: false,
                isAlreadyWarming: false
            )
        )
        XCTAssertFalse(
            VoiceInkWhisperModelWarmupPolicy.shouldScheduleWarmup(
                supportsCoreML: true,
                isAlreadyWarming: true
            )
        )
    }

    func testModelManagementFiltersApplySharedModelFacts() {
        let models = [
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "custom-api", category: .custom)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testModelManagementFiltersOwnListFilteringAndRecommendedOrder() {
        let models = [
            model(name: "custom-api", category: .custom),
            model(name: "whisper-large-v3-turbo", category: .cloud),
            model(name: "ggml-base.en", category: .local),
            model(name: "ggml-large-v3-turbo-q5_0", category: .local, isAvailableOnCurrentOS: false),
            model(name: "parakeet-tdt-0.6b-v2", category: .local)
        ]

        XCTAssertEqual(
            VoiceInkModelManagementFilter.recommended.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2", "ggml-large-v3-turbo-q5_0", "whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.local.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["ggml-base.en", "parakeet-tdt-0.6b-v2"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.cloud.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["whisper-large-v3-turbo"]
        )
        XCTAssertEqual(
            VoiceInkModelManagementFilter.custom.filteredModels(models, facts: \.facts).map(\.facts.name),
            ["custom-api"]
        )
    }

    func testMistralLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.mistral.languageCodes,
            ["ar", "de", "en", "es", "fr", "hi", "it", "ja", "ko", "nl", "pt", "ru", "zh"]
        )
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.mistral.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .mistral)
        XCTAssertEqual(models.map(\.name), ["voxtral-mini-latest"])
        XCTAssertEqual(models.first?.displayName, "Voxtral (Mistral)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSonioxLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.last, "cy")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.soniox.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.soniox.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .soniox)
        XCTAssertEqual(models.map(\.name), ["stt-async-v4"])
        XCTAssertEqual(models.first?.displayName, "Soniox V4")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testSpeechmaticsLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.first, "ar")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.last, "zh")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.speechmatics.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.speechmatics.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .speechmatics)
        XCTAssertEqual(models.map(\.name), ["speechmatics-enhanced"])
        XCTAssertEqual(models.first?.displayName, "Speechmatics")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testElevenLabsLanguageCapabilityAndModelsAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.last, "zu")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.elevenLabs.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.elevenLabs.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .elevenLabs)
        XCTAssertEqual(models.map(\.name), ["scribe_v1", "scribe_v2"])
        XCTAssertEqual(models.map(\.displayName), ["Scribe v1 (ElevenLabs)", "Scribe V2 (ElevenLabs)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [false, true])
    }

    func testStreamingConnectionModelNamesAreSharedProviderPolicy() {
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.deepgram.streamingConnectionModelName(for: "nova-3"),
            "nova-3"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.assemblyAI.streamingConnectionModelName(for: "universal-3-pro"),
            "universal-3-pro"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.cartesia.streamingConnectionModelName(for: "ink-whisper"),
            "ink-whisper"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.mistral.streamingConnectionModelName(for: "voxtral-mini-latest"),
            "voxtral-mini-transcribe-realtime-2602"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.elevenLabs.streamingConnectionModelName(for: "scribe_v2"),
            "scribe_v2_realtime"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.xai.streamingConnectionModelName(for: "grok-stt"),
            "grok-stt"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.soniox.streamingConnectionModelName(for: "stt-async-v4"),
            "stt-rt-v4"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-enhanced"),
            "enhanced"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProvider.speechmatics.streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
    }

    func testXAILanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.languageCodes?.first, "ar")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.languageCodes?.last, "vi")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.xai.languageCodes?.contains("en") == true)
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.xai.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .xai)
        XCTAssertEqual(models.map(\.name), ["grok-stt"])
        XCTAssertEqual(models.first?.displayName, "Grok (xAI)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testCartesiaLanguageCapabilityAndModelAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.first, "af")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.last, "zu")
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.cartesia.languageCodes?.contains("en") == true)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.cartesia.includesAutoDetect)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.cartesia.supportsRecordedFileTranscription)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .cartesia)
        XCTAssertEqual(models.map(\.name), ["ink-whisper"])
        XCTAssertEqual(models.first?.displayName, "Ink Whisper (Cartesia)")
        XCTAssertTrue(models.first?.supportsStreaming == true)
    }

    func testProviderRoleOwnsModelCategoryRouteAvailabilityAndLanguageSource() {
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionServiceRoute, .localWhisper)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionModelAvailabilityRequirement, .downloadedLocalWhisperModel)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localWhisper.transcriptionLanguageSource, .whisper)
        XCTAssertNil(VoiceInkTranscriptionModelProviderRole.localWhisper.coreTranscriptionModelProvider)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionServiceRoute, .localFluidAudio)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionModelAvailabilityRequirement, .downloadedLocalFluidAudioModel)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.localFluidAudio.transcriptionLanguageSource, .fluidAudio)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.modelManagementCategory, .local)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionServiceRoute, .nativeApple)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionModelAvailabilityRequirement, .currentOSSupport)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.nativeApple.transcriptionLanguageSource, .nativeApple)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.modelManagementCategory, .custom)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionServiceRoute, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionModelAvailabilityRequirement, .alwaysAvailable)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionLanguageSource, .all)

        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).modelManagementCategory, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionServiceRoute, .cloud)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionModelAvailabilityRequirement, .configuredAPIKey)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).transcriptionLanguageSource, .provider(.groq))
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).coreTranscriptionModelProvider, .groq)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(nil).transcriptionModelAvailabilityRequirement, .unavailable)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(nil).transcriptionLanguageSource, .all)
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.groq).apiKeyProviderName(defaultName: "Groq"), "Groq")
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.customCloud.apiKeyProviderName(defaultName: "Custom"), "Custom")
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.localWhisper.supportsRecordedFileTranscription)
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.customCloud.supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.cloud(.cartesia).supportsRecordedFileTranscription)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.localWhisper.isStreamingOnly)
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.cloud(.cartesia).isStreamingOnly)
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.cloud(.speechmatics).streamingConnectionModelName(for: "speechmatics-standard"),
            "standard"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.customCloud.streamingConnectionModelName(for: "custom-model"),
            "custom-model"
        )
        XCTAssertTrue(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertFalse(VoiceInkTranscriptionModelProviderRole.cloud(.deepgram).mapsStreamingTransportTimeoutToFinalTimeout)

        let customLanguages = ["zz": "Customish"]
        XCTAssertEqual(
            VoiceInkTranscriptionModelProviderRole.customCloud.transcriptionLanguageOptions(
                defaultLanguages: customLanguages,
                isMultilingual: true,
                usesRealtimeProviderLanguages: true
            ),
            customLanguages
        )
        XCTAssertNil(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: true
        )["en_uk"])
        XCTAssertEqual(VoiceInkTranscriptionModelProviderRole.cloud(.assemblyAI).transcriptionLanguageOptions(
            defaultLanguages: [:],
            isMultilingual: true,
            usesRealtimeProviderLanguages: false
        )["en_uk"], "British English")
    }

    func testMacOSTranscriptionModelProviderPreservesRawValuesAndLegacyLocalDecode() throws {
        XCTAssertEqual(
            VoiceInkMacOSTranscriptionModelProvider.allCases.map(\.rawValue),
            [
                "Whisper",
                "Parakeet",
                "Groq",
                "ElevenLabs",
                "Deepgram",
                "Mistral",
                "Gemini",
                "Soniox",
                "Speechmatics",
                "AssemblyAI",
                "xAI",
                "Cartesia",
                "NVIDIA",
                "Custom",
                "Native Apple"
            ]
        )

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Local""#.utf8)),
            .whisper
        )
        XCTAssertEqual(
            try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Parakeet""#.utf8)),
            .fluidAudio
        )

        do {
            _ = try decoder.decode(VoiceInkMacOSTranscriptionModelProvider.self, from: Data(#""Unknown""#.utf8))
            XCTFail("Unknown macOS transcription model provider raw value should throw")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMacOSTranscriptionModelFactsDeriveSharedModelPolicy() {
        let streamingFacts = VoiceInkMacOSTranscriptionModelFacts(
            name: "scribe_v1",
            provider: .elevenLabs,
            isMultilingual: true,
            supportedLanguages: ["fallback": "Fallback"],
            supportsStreaming: true
        )
        let streamingSnapshot = VoiceInkTranscriptionStreamingModelSnapshot(
            name: "scribe_v1",
            supportsStreaming: true
        )

        XCTAssertTrue(streamingFacts.supportsRecordedFileTranscription)
        XCTAssertEqual(streamingFacts.streamingPreferenceSnapshot, streamingSnapshot)
        XCTAssertEqual(
            streamingFacts.transcriptionSessionRouteFacts,
            VoiceInkTranscriptionSessionRouteFacts(
                serviceRoute: .cloud,
                streamingSnapshot: streamingSnapshot
            )
        )
        XCTAssertEqual(streamingFacts.streamingConnectionModelName, "scribe_v2_realtime")
        XCTAssertFalse(streamingFacts.mapsStreamingTransportTimeoutToFinalTimeout)
        XCTAssertEqual(
            streamingFacts.transcriptionRuntimeResourcePlan,
            VoiceInkTranscriptionRuntimeResourcePlan(serviceRoute: .cloud)
        )
        XCTAssertEqual(
            streamingFacts.transcriptionModelAvailabilityFacts(hasConfiguredAPIKey: true),
            VoiceInkTranscriptionModelAvailabilityFacts(
                requirement: .configuredAPIKey,
                hasConfiguredAPIKey: true
            )
        )

        let customLanguages = ["custom": "Custom"]
        let customFacts = VoiceInkMacOSTranscriptionModelFacts(
            name: "custom-model",
            provider: .custom,
            isMultilingual: false,
            supportedLanguages: customLanguages,
            supportsStreaming: false
        )

        XCTAssertEqual(customFacts.transcriptionLanguageOptions, customLanguages)
        XCTAssertEqual(
            customFacts.transcriptionLanguageSelectionFacts,
            VoiceInkTranscriptionLanguageSelectionFacts(
                source: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelFacts,
            VoiceInkPowerModeTranscriptionModelFacts(
                name: "custom-model",
                languageSource: .all,
                isMultilingual: false,
                languageOptions: customLanguages
            )
        )
        XCTAssertEqual(
            customFacts.powerModeTranscriptionModelResourceFacts,
            VoiceInkPowerModeTranscriptionModelResourceFacts(name: "custom-model", languageSource: .all)
        )
        XCTAssertEqual(
            customFacts.modelManagementFacts(isAvailableOnCurrentOS: false),
            VoiceInkModelManagementModelFacts(
                name: "custom-model",
                category: .custom,
                isAvailableOnCurrentOS: false
            )
        )
    }

    func testProviderAPIErrorDomainsPreserveMacOSBatchMapping() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.groq.apiErrorDomain, "GroqAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.deepgram.apiErrorDomain, "DeepgramAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.gemini.apiErrorDomain, "GeminiAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.mistral.apiErrorDomain, "MistralAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.elevenLabs.apiErrorDomain, "ElevenLabsAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.soniox.apiErrorDomain, "SonioxAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.speechmatics.apiErrorDomain, "SpeechmaticsAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.assemblyAI.apiErrorDomain, "AssemblyAIAPI")
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.xai.apiErrorDomain, "XAIAPI")
        XCTAssertNil(VoiceInkTranscriptionModelProvider.cartesia.apiErrorDomain)
        XCTAssertNil(VoiceInkTranscriptionModelProvider.local.apiErrorDomain)
    }

    func testRequiredProviderAPIErrorDomainsMatchSharedMapping() {
        let providers: [VoiceInkTranscriptionModelProvider] = [
            .groq,
            .deepgram,
            .gemini,
            .mistral,
            .elevenLabs,
            .soniox,
            .speechmatics,
            .assemblyAI,
            .xai
        ]

        for provider in providers {
            XCTAssertEqual(provider.requiredAPIErrorDomain, provider.apiErrorDomain)
        }
    }

    func testAssemblyAILanguageCapabilityAndModelsAreSharedProviderMetadata() {
        XCTAssertEqual(VoiceInkTranscriptionModelProvider.assemblyAI.languageCodes, ["en", "es", "de", "fr", "pt", "it"])
        XCTAssertTrue(VoiceInkTranscriptionModelProvider.assemblyAI.includesAutoDetect)

        let models = VoiceInkTranscriptionModelCatalog.cloudModels(for: .assemblyAI)
        XCTAssertEqual(models.map(\.name), ["universal-3-pro", "universal-streaming"])
        XCTAssertEqual(models.map(\.displayName), ["Universal-3 Pro (AssemblyAI)", "Universal-2 (AssemblyAI)"])
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
    }

    func testOpenAICompatibleProvidersUseAllLanguagesWithoutAutoDetectFlag() {
        XCTAssertNil(VoiceInkTranscriptionModelProvider.groq.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.groq.includesAutoDetect)
        XCTAssertNil(VoiceInkTranscriptionModelProvider.gemini.languageCodes)
        XCTAssertFalse(VoiceInkTranscriptionModelProvider.gemini.includesAutoDetect)
    }

    func testProviderKindExposesTranscriptionLanguageCapabilityMetadata() {
        let expected: [VoiceInkProviderKind: VoiceInkTranscriptionModelProvider] = [
            .deepgram: .deepgram,
            .mistral: .mistral,
            .elevenLabs: .elevenLabs,
            .soniox: .soniox,
            .speechmatics: .speechmatics,
            .assemblyAI: .assemblyAI,
            .xai: .xai
        ]

        for (provider, modelProvider) in expected {
            XCTAssertEqual(provider.transcriptionModelProvider?.languageCodes, modelProvider.languageCodes)
            XCTAssertEqual(provider.transcriptionModelProvider?.includesAutoDetect, modelProvider.includesAutoDetect)
        }
    }

    private func model(
        name: String,
        category: VoiceInkModelManagementModelCategory,
        isAvailableOnCurrentOS: Bool = true
    ) -> ModelManagementFilterFixture {
        ModelManagementFilterFixture(
            facts: VoiceInkModelManagementModelFacts(
                name: name,
                category: category,
                isAvailableOnCurrentOS: isAvailableOnCurrentOS
            )
        )
    }

    func testFluidAudioModelMetadataIsShared() {
        let models = VoiceInkTranscriptionModelCatalog.fluidAudioModels

        XCTAssertEqual(models.map(\.name), ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(models.map(\.displayName), ["Parakeet V2", "Parakeet V3"])
        XCTAssertEqual(models.map(\.size), ["474 MB", "494 MB"])
        XCTAssertEqual(models.map(\.modelVersion), [.v2, .v3])
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
            "parakeet-tdt-0.6b-v2"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel.name,
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )
        XCTAssertEqual(VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModel.modelVersion, .v2)
        XCTAssertEqual(models.map(\.supportsStreaming), [true, true])
        XCTAssertEqual(models.map(\.isMultilingual), [false, true])
        XCTAssertEqual(models.first?.supportedLanguages, ["en": "English"])
        XCTAssertEqual(models.last?.supportedLanguages["fr"], "French")
    }
}

private struct ModelManagementFilterFixture {
    let facts: VoiceInkModelManagementModelFacts

}
