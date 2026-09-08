import Foundation
@testable import VoiceInkCore

final class UserDefaultsPreferencesTests: XCTestCase {

    func testMacOSEnhancementSettingsPresentationPreservesOptions() {
        let presentation = VoiceInkEnhancementSettingsPresentation.macOS

        XCTAssertEqual(
            presentation.shortEnhancementWordOptions,
            (1...15).map {
                VoiceInkEnhancementIntegerOption(title: "\($0) \($0 == 1 ? "word" : "words")", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutOptions,
            [3, 5, 7, 10, 15, 20, 30, 40, 50, 60].map {
                VoiceInkEnhancementIntegerOption(title: "\($0) seconds", value: $0)
            }
        )
        XCTAssertEqual(
            presentation.timeoutRetryOptions,
            [
                VoiceInkEnhancementRetryOption(title: "Fail immediately", value: false),
                VoiceInkEnhancementRetryOption(title: "Retry", value: true)
            ]
        )
    }

    func testSharedPreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.hasCompletedOnboarding, "hasCompletedOnboarding")
        XCTAssertEqual(VoiceInkUserDefaultsKey.lowercaseTranscription, "LowercaseTranscription")
        XCTAssertEqual(VoiceInkUserDefaultsKey.removeFillerWords, "RemoveFillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.fillerWords, "FillerWords")
        XCTAssertEqual(VoiceInkUserDefaultsKey.wordReplacements, "voiceInkIOSWordReplacements")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customVocabularyTerms, "voiceInkIOSCustomVocabularyTerms")
        XCTAssertEqual(VoiceInkUserDefaultsKey.modes, "modes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedModeId, "selectedModeId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedTranscriptionLanguage, "SelectedLanguage")
        XCTAssertEqual(VoiceInkUserDefaultsKey.currentTranscriptionModel, "CurrentTranscriptionModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionPrompt, "TranscriptionPrompt")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTextFormattingEnabled, "IsTextFormattingEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isVADEnabled, "IsVADEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled, "IsTranscriptionCleanupEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.transcriptionRetentionMinutes, "TranscriptionRetentionMinutes")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isAudioCleanupEnabled, "IsAudioCleanupEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.audioRetentionPeriodDays, "AudioRetentionPeriod")
        XCTAssertEqual(VoiceInkUserDefaultsKey.appendTrailingSpace, "AppendTrailingSpace")
        XCTAssertEqual(VoiceInkUserDefaultsKey.skipShortEnhancement, "SkipShortEnhancement")
        XCTAssertEqual(VoiceInkUserDefaultsKey.shortEnhancementWordThreshold, "ShortEnhancementWordThreshold")
        XCTAssertEqual(VoiceInkUserDefaultsKey.enhancementTimeoutSeconds, "EnhancementTimeoutSeconds")
        XCTAssertEqual(VoiceInkUserDefaultsKey.enhancementRetryOnTimeout, "EnhancementRetryOnTimeout")
        XCTAssertEqual(VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds, "audioSessionTimeoutSeconds")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isAIEnhancementEnabled, "isAIEnhancementEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.useClipboardContext, "useClipboardContext")
        XCTAssertEqual(VoiceInkUserDefaultsKey.useScreenCaptureContext, "useScreenCaptureContext")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customPrompts, "customPrompts")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedPromptId, "selectedPromptId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeUIFlag, "powerModeUIFlag")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModePersistConfig, "powerModePersistConfig")
        XCTAssertEqual(VoiceInkUserDefaultsKey.powerModeConfigurations, "powerModeConfigurationsV2")
        XCTAssertEqual(VoiceInkUserDefaultsKey.activePowerModeConfigurationId, "activeConfigurationId")
        XCTAssertEqual(VoiceInkUserDefaultsKey.activePowerModeSession, "powerModeActiveSession.v1")
        XCTAssertEqual(VoiceInkUserDefaultsKey.prewarmModelOnWake, "PrewarmModelOnWake")
        XCTAssertEqual(VoiceInkUserDefaultsKey.showLiveTextPreview, "showLiveTextPreview")
        XCTAssertEqual(VoiceInkUserDefaultsKey.primaryRecordingShortcut, "primaryRecordingShortcut")
        XCTAssertEqual(VoiceInkUserDefaultsKey.secondaryRecordingShortcut, "secondaryRecordingShortcut")
        XCTAssertEqual(VoiceInkUserDefaultsKey.primaryRecordingShortcutMode, "primaryRecordingShortcutMode")
        XCTAssertEqual(VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode, "secondaryRecordingShortcutMode")
        XCTAssertEqual(VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled, "isMiddleClickToggleEnabled")
        XCTAssertEqual(VoiceInkUserDefaultsKey.middleClickActivationDelay, "middleClickActivationDelay")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProvider, "selectedAIProvider")
        XCTAssertEqual(VoiceInkUserDefaultsKey.openRouterModels, "openRouterModels")
        XCTAssertEqual(VoiceInkUserDefaultsKey.ollamaBaseURL, "ollamaBaseURL")
        XCTAssertEqual(VoiceInkUserDefaultsKey.ollamaSelectedModel, "ollamaSelectedModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customProviderBaseURL, "customProviderBaseURL")
        XCTAssertEqual(VoiceInkUserDefaultsKey.customProviderModel, "customProviderModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.showMenuBarIcon, "ShowMenuBarIcon")
        XCTAssertEqual(VoiceInkUserDefaultsKey.legacyIsMenuBarOnly, "IsMenuBarOnly")
        XCTAssertEqual(VoiceInkUserDefaultsKey.didApplyLaunchAtLoginDefault, "DidApplyLaunchAtLoginDefault")
    }

    func testPreferenceListRemovingAtOffsetsPreservesRemainingOrder() {
        XCTAssertEqual(
            VoiceInkPreferenceList.removing(at: IndexSet([1, 3]), from: ["zero", "one", "two", "three"]),
            ["zero", "two"]
        )
    }

    func testPreferenceListRemovingAtOffsetsIgnoresOutOfRangeIndexes() {
        XCTAssertEqual(
            VoiceInkPreferenceList.removing(at: IndexSet([1, 9]), from: ["zero", "one", "two"]),
            ["zero", "two"]
        )
    }

    func testAIProviderModelSelectionKeyPreservesExistingProviderRawValuePattern() {
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProviderModel("Groq"), "GroqSelectedModel")
        XCTAssertEqual(VoiceInkUserDefaultsKey.selectedAIProviderModel("Local CLI"), "Local CLISelectedModel")
    }

    func testSharedPreferenceDefaultsPreserveExistingIOSAudioSessionTimeout() {
        XCTAssertEqual(VoiceInkPreferenceDefault.audioSessionTimeoutSeconds, 90)
    }

    func testSharedPreferenceDefaultsPreserveExistingTextFormattingPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.isTextFormattingEnabled, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingVADPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.isVADEnabled, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingTranscriptionCleanupPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.lowercaseTranscription, false)
        XCTAssertEqual(VoiceInkPreferenceDefault.removeFillerWords, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingCleanupRetention() {
        XCTAssertEqual(VoiceInkPreferenceDefault.transcriptionRetentionMinutes, 24 * 60)
        XCTAssertEqual(VoiceInkPreferenceDefault.audioRetentionDays, 7)
    }

    func testSharedPreferenceDefaultsPreserveMacOSTrailingSpacePolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.appendTrailingSpace, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingShortEnhancementPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.skipShortEnhancement, true)
        XCTAssertEqual(VoiceInkPreferenceDefault.shortEnhancementWordThreshold, 3)
    }

    func testSharedPreferenceDefaultsPreserveExistingEnhancementTimeoutPolicy() {
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementTimeoutSeconds, 7)
        XCTAssertEqual(VoiceInkPreferenceDefault.enhancementRetryOnTimeout, true)
    }

    func testSharedPreferenceDefaultsPreserveExistingPowerModeFlags() {
        XCTAssertFalse(VoiceInkPreferenceDefault.powerModeUIEnabled)
        XCTAssertFalse(VoiceInkPreferenceDefault.powerModePersistConfiguredPreferences)
    }

    func testSharedPreferenceDefaultsPreserveExistingMacOSRuntimeFlags() {
        XCTAssertTrue(VoiceInkPreferenceDefault.prewarmModelOnWake)
        XCTAssertFalse(VoiceInkPreferenceDefault.showLiveTextPreview)
    }

    func testSharedPreferenceDefaultsPreserveExistingMacOSMenuBarPolicy() {
        XCTAssertFalse(VoiceInkPreferenceDefault.showMenuBarIcon)
        XCTAssertFalse(VoiceInkPreferenceDefault.showDockIcon)
        XCTAssertFalse(VoiceInkPreferenceDefault.didApplyLaunchAtLoginDefault)
    }

    func testSharedPreferenceDefaultsPreserveExistingRecordingShortcutFlags() {
        XCTAssertFalse(VoiceInkPreferenceDefault.isMiddleClickToggleEnabled)
        XCTAssertEqual(VoiceInkPreferenceDefault.middleClickActivationDelay, 200)
    }

    func testSharedPreferenceDefaultsPreserveExistingOllamaBaseURL() {
        XCTAssertEqual(VoiceInkPreferenceDefault.ollamaBaseURL, "http://localhost:11434")
    }

    func testDefaultSettingsPreserveIOSResetState() {
        let defaults = VoiceInkDefaultSettings.iOS

        XCTAssertEqual(defaults.audioSessionTimeoutSeconds, VoiceInkPreferenceDefault.audioSessionTimeoutSeconds)
        XCTAssertEqual(defaults.punctuationCleanupMode, .keep)
        XCTAssertEqual(defaults.isTextFormattingEnabled, VoiceInkPreferenceDefault.isTextFormattingEnabled)
        XCTAssertEqual(defaults.isVADEnabled, VoiceInkPreferenceDefault.isVADEnabled)
        XCTAssertEqual(defaults.lowercaseTranscription, VoiceInkPreferenceDefault.lowercaseTranscription)
        XCTAssertEqual(defaults.removeFillerWords, VoiceInkPreferenceDefault.removeFillerWords)
        XCTAssertEqual(defaults.fillerWords, VoiceInkFillerWords.defaultWords)
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, VoiceInkLanguageCatalog.autoDetectCode)
    }

    func testDefaultSettingsBuildSharedAppSettingsResetState() {
        let defaults = VoiceInkDefaultSettings(
            audioSessionTimeoutSeconds: 12,
            punctuationCleanupMode: .removeTrailingPeriod,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false,
            fillerWords: ["um"],
            selectedTranscriptionLanguage: "de"
        )

        let resetState = defaults.appSettingsResetState

        XCTAssertTrue(resetState.modes.isEmpty)
        XCTAssertNil(resetState.selectedModeId)
        XCTAssertEqual(resetState.apiKeyState, VoiceInkProviderAPIKeyState())
        XCTAssertEqual(resetState.audioSessionTimeoutSeconds, 12)
        XCTAssertEqual(
            resetState.transcriptionCleanupSettings,
            VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
        XCTAssertEqual(resetState.fillerWords, ["um"])
        XCTAssertEqual(resetState.wordReplacements, [])
        XCTAssertEqual(resetState.customVocabularyTerms, [])
        XCTAssertEqual(resetState.selectedTranscriptionLanguage, "de")
        XCTAssertEqual(resetState.apiKeyProvidersToDelete, VoiceInkProviderKind.userAPIKeyProviders)
    }

    func testAppSettingsResetStateAppliesDefaultRuntimeStateInOrder() {
        let resetState = VoiceInkDefaultSettings.iOS.appSettingsResetState

        XCTAssertEqual(appSettingsResetActionEvents(for: resetState), [
            "applyResetState",
            "clearCoreUserSettings",
            "deleteProviderAPIKeys:\(VoiceInkProviderKind.userAPIKeyProviders.map(\.rawValue).joined(separator: ","))"
        ])
    }

    func testAppSettingsResetStateAppliesRuntimeStateInOrder() {
        let mode = Mode(name: "Focus")
        let resetState = VoiceInkAppSettingsResetState(
            modes: [mode],
            selectedModeId: mode.id,
            apiKeyState: VoiceInkProviderAPIKeyState(storedKeysByProvider: [.groq: "groq-key"]),
            audioSessionTimeoutSeconds: 90,
            transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            ),
            fillerWords: ["uh"],
            wordReplacements: [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ],
            customVocabularyTerms: ["Whisper"],
            selectedTranscriptionLanguage: "fr",
            apiKeyProvidersToDelete: [.groq, .openAI]
        )
        var events: [String] = []

        resetState.applyRuntimeState(
            setModes: { modes in events.append("modes:\(modes.count)") },
            setSelectedModeId: { selectedModeId in events.append("selectedMode:\(selectedModeId == mode.id)") },
            setAPIKeyState: { state in events.append("apiKey:\(state.storedAPIKey(for: .groq))") },
            setAudioSessionTimeoutSeconds: { timeout in events.append("timeout:\(timeout)") },
            setTranscriptionCleanupSettings: { settings in events.append("cleanup:\(settings.punctuationMode.rawValue)") },
            setFillerWords: { words in events.append("filler:\(words.joined(separator: ","))") },
            setWordReplacements: { rules in events.append("rules:\(rules.count)") },
            setCustomVocabularyTerms: { terms in events.append("vocabulary:\(terms.joined(separator: ","))") },
            setSelectedTranscriptionLanguage: { language in events.append("language:\(language)") },
            clearCoreUserSettings: { events.append("clear") },
            deleteProviderAPIKeys: { providers in events.append("delete:\(providers.map(\.rawValue).joined(separator: ","))") }
        )

        XCTAssertEqual(events, [
            "modes:1",
            "selectedMode:true",
            "apiKey:groq-key",
            "timeout:90",
            "cleanup:removeTrailingPeriod",
            "filler:uh",
            "rules:1",
            "vocabulary:Whisper",
            "language:fr",
            "clear",
            "delete:groq,openAI"
        ])
    }

    func testAppSettingsResetStateSkipsProviderDeletionRuntimeActionWhenNoProviders() {
        let resetState = VoiceInkAppSettingsResetState(
            modes: [],
            selectedModeId: nil,
            apiKeyState: VoiceInkProviderAPIKeyState(),
            audioSessionTimeoutSeconds: 30,
            transcriptionCleanupSettings: VoiceInkDefaultSettings.iOS.transcriptionCleanupSettings,
            fillerWords: [],
            wordReplacements: [],
            customVocabularyTerms: [],
            selectedTranscriptionLanguage: VoiceInkLanguageCatalog.autoDetectCode,
            apiKeyProvidersToDelete: []
        )

        XCTAssertEqual(appSettingsResetActionEvents(for: resetState), [
            "applyResetState",
            "clearCoreUserSettings"
        ])
    }

    private func appSettingsResetActionEvents(
        for resetState: VoiceInkAppSettingsResetState
    ) -> [String] {
        var events: [String] = []
        resetState.applyRuntimeState(
            setModes: { _ in events.append("applyResetState") },
            setSelectedModeId: { _ in },
            setAPIKeyState: { _ in },
            setAudioSessionTimeoutSeconds: { _ in },
            setTranscriptionCleanupSettings: { _ in },
            setFillerWords: { _ in },
            setWordReplacements: { _ in },
            setCustomVocabularyTerms: { _ in },
            setSelectedTranscriptionLanguage: { _ in },
            clearCoreUserSettings: {
                events.append("clearCoreUserSettings")
            },
            deleteProviderAPIKeys: { providers in
                events.append("deleteProviderAPIKeys:\(providers.map(\.rawValue).joined(separator: ","))")
            }
        )
        return events
    }

    func testIOSAppSettingsStartupPolicyLoadsPersistedStateThroughAdapters() {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = Mode(
            name: "Meeting",
            transcriptionProvider: .groq,
            transcriptionModel: "whisper-large-v3",
            isPostProcessingEnabled: true,
            postProcessingProvider: .openAI,
            postProcessingModel: "gpt-4o-mini"
        )
        VoiceInkModeStorage.saveModes([mode], to: defaults)
        VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)
        VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
        PunctuationCleanupMode.setCurrent(.removeTrailingPeriod, in: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)
        VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)
        VoiceInkWordReplacementPreference.saveRules([
            VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
        ], to: defaults)
        VoiceInkCustomVocabularyPreference.saveTerms([" Felix ", "roma", " "], to: defaults)
        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
        VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)

        let startupState = VoiceInkIOSAppSettingsStartupPolicy.state(
            from: defaults,
            verifiedProviders: VoiceInkProviderAPIKeyVerificationState.verifiedProviders(in: defaults),
            loadStoredAPIKey: { provider in
                provider == .groq ? "groq-key" : ""
            }
        )

        XCTAssertEqual(startupState.modes.count, 1)
        XCTAssertEqual(startupState.modes.first?.id, mode.id)
        XCTAssertEqual(startupState.modes.first?.transcriptionProvider, .groq)
        XCTAssertEqual(startupState.selectedModeId, mode.id)
        XCTAssertEqual(startupState.apiKeyState.storedAPIKey(for: .groq), "groq-key")
        XCTAssertEqual(startupState.audioSessionTimeoutSeconds, 120)
        XCTAssertEqual(
            startupState.transcriptionCleanupSettings,
            VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
        XCTAssertEqual(startupState.fillerWords, ["um", "like"])
        XCTAssertEqual(
            startupState.wordReplacements,
            [VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")]
        )
        XCTAssertEqual(startupState.customVocabularyTerms, ["Felix", "roma"])
        XCTAssertEqual(startupState.selectedTranscriptionLanguage, "fr")
    }

    func testIOSFirstTimeSetupPolicySeedsDefaultModeAndCompletionIntent() {
        let plan = VoiceInkIOSFirstTimeSetupPolicy.plan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )
        var didSaveHasCompletedOnboarding = false
        var appliedModeSettingsRepairPlan: VoiceInkModeSettingsRepairPlan?

        plan.applyRuntimeState(
            applyModeSettingsRepair: { repairPlan in
                appliedModeSettingsRepairPlan = repairPlan
            },
            saveHasCompletedOnboarding: {
                didSaveHasCompletedOnboarding = true
            }
        )

        XCTAssertTrue(didSaveHasCompletedOnboarding)
        guard let modeSettingsRepairPlan = appliedModeSettingsRepairPlan else {
            return XCTFail("Expected first-time setup to apply mode repair")
        }
        XCTAssertTrue(modeSettingsRepairPlan.shouldReplaceModes)
        XCTAssertEqual(modeSettingsRepairPlan.modes.count, 1)
        XCTAssertEqual(modeSettingsRepairPlan.modes.first?.id, modeSettingsRepairPlan.selectedModeId)
        XCTAssertEqual(modeSettingsRepairPlan.modes.first?.transcriptionProvider, .localWhisper)
        XCTAssertEqual(
            modeSettingsRepairPlan.selectedTranscriptionLanguage,
            VoiceInkLanguageCatalog.autoDetectCode
        )
    }

    func testIOSFirstTimeSetupPlanSkipsOnboardingRuntimeActionWhenDisabled() {
        let plan = VoiceInkIOSFirstTimeSetupPlan(
            modeSettingsRepairPlan: VoiceInkModeSettingsPolicy.defaultModeRepairPlan(
                modes: [],
                selectedModeId: nil,
                selectedTranscriptionLanguage: "not-a-language"
            ),
            shouldSaveHasCompletedOnboarding: false
        )

        XCTAssertEqual(iOSFirstTimeSetupEvents(for: plan), ["repair:1"])
    }

    func testIOSFirstTimeSetupPlanAppliesRuntimeStateInOrder() {
        let plan = VoiceInkIOSFirstTimeSetupPolicy.plan(
            modes: [],
            selectedModeId: nil,
            selectedTranscriptionLanguage: "not-a-language"
        )
        XCTAssertEqual(iOSFirstTimeSetupEvents(for: plan), [
            "repair:1",
            "saveOnboarding"
        ])
    }

    private func iOSFirstTimeSetupEvents(
        for plan: VoiceInkIOSFirstTimeSetupPlan
    ) -> [String] {
        var events: [String] = []
        plan.applyRuntimeState(
            applyModeSettingsRepair: { repairPlan in
                events.append("repair:\(repairPlan.modes.count)")
            },
            saveHasCompletedOnboarding: {
                events.append("saveOnboarding")
            }
        )
        return events
    }

    func testDefaultSettingsPreserveMacOSSelectedLanguageDefault() {
        let defaults = VoiceInkDefaultSettings.macOS
        let registeredDefaults = defaults.registeredUserDefaults()

        XCTAssertEqual(
            defaults.selectedTranscriptionLanguage,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(defaults.selectedTranscriptionLanguage, "en")
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
    }

    func testDefaultSettingsExposeTranscriptionCleanupSettings() {
        let defaults = VoiceInkDefaultSettings(
            punctuationCleanupMode: .removeTrailingPeriod,
            isTextFormattingEnabled: false,
            lowercaseTranscription: true,
            removeFillerWords: false
        )

        XCTAssertEqual(
            defaults.transcriptionCleanupSettings,
            VoiceInkTranscriptionCleanupSettings(
                punctuationMode: .removeTrailingPeriod,
                isTextFormattingEnabled: false,
                lowercaseTranscription: true,
                removeFillerWords: false
            )
        )
    }

    func testDefaultSettingsBuildRegisteredUserDefaultsForPlatformSelections() {
        let registeredDefaults = VoiceInkDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )

        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.hasCompletedOnboarding] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.isTextFormattingEnabled] as? Bool,
            VoiceInkPreferenceDefault.isTextFormattingEnabled
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.isVADEnabled] as? Bool,
            VoiceInkPreferenceDefault.isVADEnabled
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.removeFillerWords] as? Bool,
            VoiceInkPreferenceDefault.removeFillerWords
        )
        XCTAssertEqual(registeredDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.lowercaseTranscription] as? Bool,
            VoiceInkPreferenceDefault.lowercaseTranscription
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkPreferenceDefault.macOSSelectedTranscriptionLanguage
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.currentTranscriptionModel] as? String,
            VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )
        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.transcriptionRetentionMinutes] as? Int,
            VoiceInkPreferenceDefault.transcriptionRetentionMinutes
        )
        XCTAssertEqual(registeredDefaults[VoiceInkUserDefaultsKey.isAudioCleanupEnabled] as? Bool, false)
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.audioRetentionPeriodDays] as? Int,
            VoiceInkPreferenceDefault.audioRetentionDays
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.skipShortEnhancement] as? Bool,
            VoiceInkPreferenceDefault.skipShortEnhancement
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.shortEnhancementWordThreshold] as? Int,
            VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.enhancementTimeoutSeconds] as? Int,
            VoiceInkPreferenceDefault.enhancementTimeoutSeconds
        )
        XCTAssertEqual(
            registeredDefaults[VoiceInkUserDefaultsKey.enhancementRetryOnTimeout] as? Bool,
            VoiceInkPreferenceDefault.enhancementRetryOnTimeout
        )

        let iOSRegisteredDefaults = VoiceInkDefaultSettings.iOS.registeredUserDefaults()
        XCTAssertNil(iOSRegisteredDefaults[VoiceInkUserDefaultsKey.currentTranscriptionModel])
        XCTAssertEqual(
            iOSRegisteredDefaults[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String,
            VoiceInkLanguageCatalog.autoDetectCode
        )

        let completedRemovePunctuationDefaults = VoiceInkDefaultSettings(
            punctuationCleanupMode: .removeAll
        ).registeredUserDefaults(
            hasCompletedOnboarding: true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[VoiceInkUserDefaultsKey.hasCompletedOnboarding] as? Bool,
            true
        )
        XCTAssertEqual(
            completedRemovePunctuationDefaults[PunctuationCleanupMode.legacyRemovePunctuationKey] as? Bool,
            true
        )
    }

    func testMenuBarPreferencePreservesRegisteredDefaultsAndStorage() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkMacOSSettingsPresentation.macOS.menuBarTitle, "Menu Bar")
            XCTAssertEqual(VoiceInkMacOSSettingsPresentation.macOS.dockIconTitle, "Dock Icon")
            XCTAssertEqual(
                VoiceInkMenuBarPreference.showMenuBarIconKey,
                VoiceInkUserDefaultsKey.showMenuBarIcon
            )
            XCTAssertEqual(
                VoiceInkMenuBarPreference.legacyIsMenuBarOnlyKey,
                VoiceInkUserDefaultsKey.legacyIsMenuBarOnly
            )
            XCTAssertEqual(
                VoiceInkMenuBarPreference.registeredDefaults[VoiceInkUserDefaultsKey.showMenuBarIcon] as? Bool,
                VoiceInkPreferenceDefault.showMenuBarIcon
            )
            XCTAssertEqual(
                VoiceInkMenuBarPreference.registeredDefaults[VoiceInkUserDefaultsKey.legacyIsMenuBarOnly] as? Bool,
                !VoiceInkPreferenceDefault.showDockIcon
            )

            XCTAssertFalse(VoiceInkMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertFalse(VoiceInkMenuBarPreference.shouldShowDockIcon(from: defaults))

            defaults.register(defaults: VoiceInkMenuBarPreference.registeredDefaults)

            XCTAssertFalse(VoiceInkMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertFalse(VoiceInkMenuBarPreference.shouldShowDockIcon(from: defaults))

            VoiceInkMenuBarPreference.saveShowMenuBarIcon(true, to: defaults)
            VoiceInkMenuBarPreference.saveShowDockIcon(true, to: defaults)

            XCTAssertTrue(VoiceInkMenuBarPreference.shouldShowMenuBarIcon(from: defaults))
            XCTAssertTrue(VoiceInkMenuBarPreference.shouldShowDockIcon(from: defaults))
            XCTAssertFalse(defaults.bool(forKey: VoiceInkMenuBarPreference.legacyIsMenuBarOnlyKey))
            XCTAssertEqual(
                VoiceInkMacOSMenuBarPresentation.dockIconTitle(showDockIcon: true),
                "Hide Dock Icon"
            )
            XCTAssertEqual(
                VoiceInkMacOSMenuBarPresentation.dockIconTitle(showDockIcon: false),
                "Show Dock Icon"
            )
        }
    }

    func testMacOSLaunchAtLoginDefaultPolicyPreservesExistingStorageAndRegisteredDefault() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey,
                VoiceInkUserDefaultsKey.didApplyLaunchAtLoginDefault
            )
            XCTAssertEqual(
                VoiceInkMacOSLaunchAtLoginDefaultPolicy.registeredDefaults[
                    VoiceInkMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey
                ] as? Bool,
                false
            )
            XCTAssertTrue(VoiceInkMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))

            VoiceInkMacOSLaunchAtLoginDefaultPolicy.markDefaultApplied(to: defaults)

            XCTAssertFalse(VoiceInkMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
            XCTAssertEqual(
                defaults.bool(forKey: VoiceInkMacOSLaunchAtLoginDefaultPolicy.didApplyDefaultKey),
                true
            )
        }
    }

    func testMacOSLaunchAtLoginDefaultPolicySkipsExistingOnboardingOrRegisteredState() {
        withIsolatedDefaults { defaults in
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(false, to: defaults)

            XCTAssertFalse(VoiceInkMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
        }

        withIsolatedDefaults { defaults in
            defaults.register(defaults: VoiceInkMacOSLaunchAtLoginDefaultPolicy.registeredDefaults)

            XCTAssertFalse(VoiceInkMacOSLaunchAtLoginDefaultPolicy.shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults))
        }
    }

    func testMacOSShellBackupPreferencesPreserveExportShape() {
        XCTAssertEqual(
            VoiceInkMacOSShellBackupPreference.backupPreferences(
                launchAtLoginEnabled: true,
                showDockIcon: true,
                recorderType: "mini"
            ),
            VoiceInkMacOSShellBackupPreferences(
                launchAtLoginEnabled: true,
                showDockIcon: true,
                recorderType: "mini"
            )
        )
    }

    func testMacOSShellBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            VoiceInkMacOSShellBackupPreference.backupImportPlan(
                from: VoiceInkMacOSShellBackupPreferences(
                    launchAtLoginEnabled: nil,
                    showDockIcon: false,
                    recorderType: nil
                )
            ),
            VoiceInkMacOSShellBackupImportPlan(
                launchAtLoginEnabled: nil,
                showDockIcon: false,
                recorderType: nil
            )
        )
    }

    func testDefaultSettingsRegisterUserDefaultsForPlatformSelections() {
        let previousRegistrationDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(
                previousRegistrationDomain,
                forName: UserDefaults.registrationDomain
            )
        }

        withIsolatedDefaults { defaults in
            defaults.set("fr", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            VoiceInkDefaultSettings.macOS.registerUserDefaults(
                to: defaults,
                currentTranscriptionModel: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )

            XCTAssertEqual(
                defaults.object(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding) as? Bool,
                false
            )
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage),
                "fr"
            )
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel),
                VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )
            XCTAssertEqual(
                defaults.object(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) as? Int,
                VoiceInkPreferenceDefault.transcriptionRetentionMinutes
            )
        }
    }

    func testStartupPreferenceMigrationUsesIOSMigrationSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            VoiceInkStartupPreferenceMigration.migrateLegacyPreferences(for: .iOS, in: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertNil(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey))
        }
    }

    func testStartupPreferenceMigrationUsesMacOSMigrationSet() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
            defaults.set(true, forKey: VoiceInkPasteMethod.legacyAppleScriptPasteKey)

            VoiceInkStartupPreferenceMigration.migrateLegacyPreferences(for: .macOS, in: defaults)

            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .removeAll)
            XCTAssertEqual(VoiceInkPasteMethod.current(in: defaults), .appleScript)
            XCTAssertEqual(defaults.string(forKey: VoiceInkPasteMethod.userDefaultsKey), "appleScript")
        }
    }

    func testOnboardingPreferenceUsesFalseWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testOnboardingPreferenceSavesAndClearsCompletionState() {
        withIsolatedDefaults { defaults in
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(true, to: defaults)
            XCTAssertTrue(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertTrue(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))

            VoiceInkOnboardingPreference.clear(from: defaults)
            XCTAssertFalse(VoiceInkOnboardingPreference.hasStoredCompletionState(from: defaults))
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
        }
    }

    func testAudioSessionTimeoutPreferenceUsesExistingDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testAudioSessionTimeoutPreferenceSavesAndClearsTimeout() {
        withIsolatedDefaults { defaults in
            VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults), 120)

            VoiceInkAudioSessionTimeoutPreference.clear(from: defaults)
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
        }
    }

    func testAudioSessionTimeoutPreferenceOwnsIOSRuntimePolicy() {
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.minimumSeconds, 0)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.maximumSeconds, 300)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.stepSeconds, 15)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.countdownUpdateInterval, 1.0)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.displayText(for: 90), "90s")
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: 0), .immediate)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: -1), .immediate)
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.deactivationPlan(for: 90), .delayed(90))
        XCTAssertEqual(VoiceInkAudioSessionTimeoutPreference.remainingTimeAfterCountdownTick(90), 89)
    }

    func testAudioSessionDeactivationPlanOwnsShellExecutionIntent() {
        assertAudioSessionDeactivationExecution(
            VoiceInkAudioSessionDeactivationPlan.immediate.executionPlan,
            expectedEvents: ["deactivate"]
        )
        assertAudioSessionDeactivationExecution(
            VoiceInkAudioSessionDeactivationPlan.delayed(90).executionPlan,
            expectedEvents: ["timer", "scheduled"]
        )
    }

    func testAudioSessionDeactivationExecutionPlanAppliesRuntimeState() {
        assertAudioSessionDeactivationExecution(
            VoiceInkAudioSessionDeactivationPlan.immediate.executionPlan,
            expectedEvents: ["deactivate"]
        )
        assertAudioSessionDeactivationExecution(
            VoiceInkAudioSessionDeactivationPlan.delayed(90).executionPlan,
            expectedEvents: ["timer", "scheduled"]
        )
    }

    private func assertAudioSessionDeactivationExecution(
        _ plan: VoiceInkAudioSessionDeactivationExecutionPlan,
        expectedEvents: [String]
    ) {
        var events: [String] = []

        plan.applyRuntimeState(
            deactivateSession: { events.append("deactivate") },
            runCountdownTimer: { events.append("timer") },
            countdownTimerDidStart: { events.append("scheduled") }
        )

        XCTAssertEqual(events, expectedEvents)
    }

    func testVADPreferenceUsesSharedDefaultWhenMissing() {
        XCTAssertEqual(VoiceInkVADPreference.userDefaultsKey, "IsVADEnabled")
        XCTAssertTrue(VoiceInkVADPreference.defaultIsEnabled)

        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
        }
    }

    func testVADPreferenceSavesAndClearsEnabledState() {
        withIsolatedDefaults { defaults in
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)
            XCTAssertFalse(VoiceInkVADPreference.isEnabled(from: defaults))

            VoiceInkVADPreference.clear(from: defaults)
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
        }
    }

    func testCustomLanguagePromptsKeyPreservesExistingMacOSStorageName() {
        XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.customLanguagePromptsKey, "CustomLanguagePrompts")
    }

    func testPromptDraftStateOwnsMacOSEditSaveAndLanguageRefresh() {
        let draftState = VoiceInkLocalWhisperPromptDraftState()

        XCTAssertEqual(draftState, VoiceInkLocalWhisperPromptDraftState(text: "", isEditing: false))

        let editingState = draftState.editing(prompt: "Use sentence case.")
        XCTAssertEqual(
            editingState,
            VoiceInkLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: true)
        )

        XCTAssertEqual(
            editingState.refreshingForSelectedLanguage(prompt: "Use French punctuation."),
            VoiceInkLocalWhisperPromptDraftState(text: "Use French punctuation.", isEditing: true)
        )

        let savedState = editingState.saved()
        XCTAssertEqual(
            savedState,
            VoiceInkLocalWhisperPromptDraftState(text: "Use sentence case.", isEditing: false)
        )

        XCTAssertEqual(
            savedState.refreshingForSelectedLanguage(prompt: "Use German punctuation."),
            savedState
        )
    }

    func testDefaultPromptsPreserveExistingMacOSLanguageSeeds() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "en"),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja"),
            "こんにちは、お元気ですか？お会いできて嬉しいです。"
        )
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "he"),
            ",שלום, מה שלומך? נעים להכיר"
        )
    }

    func testPromptUsesCustomPromptWhenAvailable() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.prompt(
                for: "en",
                customPrompts: ["en": "Spell Roma Just Talk exactly."]
            ),
            "Spell Roma Just Talk exactly."
        )
    }

    func testPromptFallsBackToDefaultWhenCustomPromptIsEmptyOrLanguageIsMissing() {
        XCTAssertEqual(
            VoiceInkLocalWhisperPromptCatalog.prompt(for: "en", customPrompts: ["en": ""]),
            "Hello, how are you doing? Nice to meet you."
        )
        XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.prompt(for: "xx"), "")
    }

    func testPromptForSelectedLanguageUsesSharedLanguageKeyAndFallbackLanguage() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Hello, how are you doing? Nice to meet you."
            )

            defaults.set("fr", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Bonjour, comment allez-vous? Ravi de vous rencontrer."
            )
        }
    }

    func testStoredCustomPromptsRoundTrip() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults), [:])

            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                ["en": "Spell Roma Just Talk exactly."]
            )
        }
    }

    func testSaveCustomPromptUpdatesOneLanguageAndPreservesOthers() {
        withIsolatedDefaults { defaults in
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["fr": "Use French punctuation."],
                to: defaults
            )

            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.storedCustomPrompts(from: defaults),
                [
                    "en": "Spell Roma Just Talk exactly.",
                    "fr": "Use French punctuation."
                ]
            )
        }
    }

    func testPromptForSelectedLanguageUsesStoredCustomPromptsByDefault() {
        withIsolatedDefaults { defaults in
            defaults.set("en", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(
                ["en": "Spell Roma Just Talk exactly."],
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults),
                "Spell Roma Just Talk exactly."
            )

            XCTAssertEqual(
                VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults, customPrompts: [:]),
                "Hello, how are you doing? Nice to meet you."
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesFallbackOnlyWhenLocalWhisperPromptIsMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                "Language prompt"
            )

            VoiceInkTranscriptionPromptPreference.savePrompt("", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                ""
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" spell Roma correctly ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPrompt(from: defaults, fallback: "Language prompt"),
                " spell Roma correctly "
            )
        }
    }

    func testTranscriptionPromptPreferenceUsesSelectedLanguagePromptFallback() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" custom prompt ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(from: defaults),
                " custom prompt "
            )
        }
    }

    func testTranscriptionPromptPreferenceSavesSelectedLanguagePrompt() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("ja", to: defaults)

            let prompt = VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja"))
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                VoiceInkLocalWhisperPromptCatalog.defaultPrompt(for: "ja")
            )
        }
    }

    func testTranscriptionPromptPreferenceSavesCustomPromptForSelectedLanguage() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt(
                "Spell Roma Just Talk exactly.",
                for: "en",
                to: defaults
            )

            let prompt = VoiceInkTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage(
                from: defaults
            )

            XCTAssertEqual(prompt, "Spell Roma Just Talk exactly.")
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                "Spell Roma Just Talk exactly."
            )
        }
    }

    func testTranscriptionPromptPreferenceDropsBlankRequestPrompts() {
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(nil))
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(""))
        XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(" \n\t "))
    }

    func testTranscriptionPromptPreferenceReadsRequestPromptFromSharedKey() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults))

            VoiceInkTranscriptionPromptPreference.savePrompt(" keep product names ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults),
                " keep product names "
            )

            VoiceInkTranscriptionPromptPreference.savePrompt(" \n ", to: defaults)
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.requestPrompt(from: defaults))
        }
    }

    func testTranscriptionPromptPreferenceRoundTripsStoredPrompt() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults))

            VoiceInkTranscriptionPromptPreference.savePrompt("keep Roma spelling", to: defaults)

            XCTAssertEqual(
                VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults),
                "keep Roma spelling"
            )
        }
    }

    func testTranscriptionLanguagePreferenceUsesAutoDetectFallbackWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                VoiceInkLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults))
        }
    }

    func testTranscriptionLanguagePreferenceUsesMacOSFallbackWhenRequested() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                VoiceInkDefaultSettings.macOS.selectedTranscriptionLanguage
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage(from: defaults),
                "fr"
            )
        }
    }

    func testTranscriptionLanguagePreferenceSelectsCompatibleLanguageForSource() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "en-US"
            )

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr-FR", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(
                    source: .nativeApple,
                    from: defaults
                ),
                "fr-FR"
            )
        }
    }

    func testTranscriptionLanguagePreferencePreservesRawSelectedLanguage() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                "auto"
            )
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults))

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(" fr ", to: defaults)
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                " fr "
            )
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(from: defaults), "fr")
        }
    }

    func testTranscriptionLanguagePreferenceExposesStoredLanguageWhenPresent() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults))

            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("de", to: defaults)

            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "de")
        }
    }

    func testTranscriptionLanguagePreferenceClearsSelection() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            VoiceInkTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)

            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults))
        }
    }

    func testCurrentTranscriptionModelPreferenceRoundTripsModelName() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))

            VoiceInkCurrentTranscriptionModelPreference.saveModelName(
                VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName,
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
                VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
            )
        }
    }

    func testCurrentTranscriptionModelPreferenceClearsModelName() {
        withIsolatedDefaults { defaults in
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))
        }
    }

    func testCurrentTranscriptionModelPreferenceClearsLegacyModelName() {
        withIsolatedDefaults { defaults in
            defaults.set("legacy-base", forKey: VoiceInkCurrentTranscriptionModelPreference.legacyModelNameKey)

            VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)

            XCTAssertNil(defaults.string(forKey: VoiceInkCurrentTranscriptionModelPreference.legacyModelNameKey))
        }
    }

    func testCurrentTranscriptionModelLoadPlanNoOpsWhenNoModelIsSaved() {
        let plan = VoiceInkCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: nil,
            candidateModelExists: false,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, [])
    }

    func testCurrentTranscriptionModelLoadPlanNoOpsWhenSavedModelIsMissingFromRegistry() {
        let plan = VoiceInkCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "missing-model",
            candidateModelExists: false,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, [])
    }

    func testCurrentTranscriptionModelLoadPlanRestoresAvailableSavedModel() {
        let plan = VoiceInkCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "nova-3",
            candidateModelExists: true,
            isCandidateAvailableOnCurrentOS: true
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, ["restore"])
    }

    func testCurrentTranscriptionModelLoadPlanClearsUnavailableSavedModel() {
        let plan = VoiceInkCurrentTranscriptionModelPreference.loadPlan(
            savedModelName: "apple-speech",
            candidateModelExists: true,
            isCandidateAvailableOnCurrentOS: false
        )
        var events: [String] = []

        plan.applyRuntimeState(
            clearStoredModelName: {
                events.append("clear")
            },
            restoreSavedModel: {
                events.append("restore")
            }
        )

        XCTAssertEqual(events, ["clear"])
    }

    func testAIEnhancementProviderPreferenceUsesDefaultWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.defaultSelectedProvider, .gemini)
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults),
                .gemini
            )
        }
    }

    func testAIEnhancementProviderPreferenceRepairsLegacyStoredProvider() {
        withIsolatedDefaults { defaults in
            defaults.set("GROQ", forKey: VoiceInkUserDefaultsKey.selectedAIProvider)

            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .groq)
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                VoiceInkAIEnhancementProviderKind.groq.rawValue
            )
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsRawProvider() {
        withIsolatedDefaults { defaults in
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                "OpenRouter"
            )
            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceSavesEnumProvider() {
        withIsolatedDefaults { defaults in
            VoiceInkAIEnhancementProviderPreference.saveSelectedProvider(.openRouter, to: defaults)

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                VoiceInkAIEnhancementProviderKind.openRouter.rawValue
            )
            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceAppliesProviderSelectionPlan() {
        withIsolatedDefaults { defaults in
            let appliedProvider = VoiceInkAIEnhancementProviderPreference.applyProviderSelectionPlan(
                VoiceInkAIEnhancementProviderSelectionPlan.selecting(.openRouter),
                to: defaults
            )

            XCTAssertEqual(appliedProvider, .openRouter)
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults),
                VoiceInkAIEnhancementProviderKind.openRouter.rawValue
            )
            XCTAssertEqual(VoiceInkAIEnhancementProviderPreference.selectedProvider(from: defaults), .openRouter)
        }
    }

    func testAIEnhancementProviderPreferenceRoundTripsSelectedModel() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults)
            )

            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "Groq",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testAIEnhancementProviderPreferenceAppliesModelSelectionPlan() throws {
        let plan = try XCTUnwrap(
            VoiceInkAIEnhancementModelSelectionPlan.selecting(
                "openai/gpt-oss-120b",
                provider: .groq,
                selectedModels: [:]
            )
        )

        withIsolatedDefaults { defaults in
            let appliedModel = VoiceInkAIEnhancementProviderPreference.applyModelSelectionPlan(
                plan,
                to: defaults
            )

            XCTAssertEqual(appliedModel, "openai/gpt-oss-120b")
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "Groq", from: defaults),
                "openai/gpt-oss-120b"
            )
        }
    }

    func testAIEnhancementProviderPreferenceAppliesModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = VoiceInkAIEnhancementProviderPreference.applyModelRefreshPlan(
                VoiceInkAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["anthropic/claude-3.5-sonnet"],
                    selectedModelToSave: "anthropic/claude-3.5-sonnet"
                ),
                for: .openRouter,
                to: defaults
            )

            XCTAssertEqual(appliedModel, "anthropic/claude-3.5-sonnet")
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )

            let ignoredModel = VoiceInkAIEnhancementProviderPreference.applyModelRefreshPlan(
                VoiceInkAIEnhancementModelRefreshPlan(
                    refreshedModelNames: [],
                    selectedModelToSave: nil
                ),
                for: .openRouter,
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )
        }
    }

    func testAIEnhancementProviderPreferenceLoadsSelectedModelsByProvider() {
        withIsolatedDefaults { defaults in
            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: .groq,
                to: defaults
            )
            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "openai/gpt-4o",
                for: .openAI,
                to: defaults
            )
            defaults.set("", forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel("OpenRouter"))

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModels(
                    for: [.groq, .openRouter, .openAI],
                    from: defaults
                ),
                [
                    .groq: "llama-3.3-70b-versatile",
                    .openAI: "openai/gpt-4o"
                ]
            )
        }
    }

    func testAIEnhancementProviderPreferenceBuildsDiagnosticDescriptions() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Disabled"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "None selected"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "None selected"
            )

            VoiceInkAIEnhancementPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("GROQ", to: defaults)

            XCTAssertTrue(VoiceInkAIEnhancementPreference.isEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkAIEnhancementPreference.statusDiagnosticDescription(from: defaults),
                "Enabled"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedProviderDiagnosticDescription(from: defaults),
                "GROQ"
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "Default (GROQ)"
            )

            VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
                "llama-3.3-70b-versatile",
                for: "GROQ",
                to: defaults
            )

            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModelDiagnosticDescription(from: defaults),
                "llama-3.3-70b-versatile"
            )
        }
    }

    func testAIEnhancementContextPreferenceRoundTripsAndClearsToggles() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)

            XCTAssertTrue(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertTrue(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))

            VoiceInkAIEnhancementContextPreference.clear(from: defaults)

            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
        }
    }

    func testDynamicAIProviderPreferenceReadsOllamaFallbacksAndSavedValues() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.defaultOllamaBaseURL,
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.defaultOllamaRuntimeSelectedModel,
                VoiceInkAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel(from: defaults),
                VoiceInkAIEnhancementProviderKind.legacyOllamaServiceSelectedModelFallback
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )

            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                "http://example.local:11434"
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "mistral"
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel(from: defaults),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferencePreservesCallerSpecificOllamaModelFallbacks() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "mistral"
            )
        }
    }

    func testDynamicAIProviderPreferenceAppliesOllamaModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = VoiceInkDynamicAIProviderPreference.applyOllamaModelRefreshPlan(
                VoiceInkAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["llama3", "mistral"],
                    selectedModelToSave: "llama3"
                ),
                to: defaults
            )

            XCTAssertEqual(appliedModel, "llama3")
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "llama3"
            )

            let ignoredModel = VoiceInkDynamicAIProviderPreference.applyOllamaModelRefreshPlan(
                VoiceInkAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["mistral"],
                    selectedModelToSave: nil
                ),
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "mistral"),
                "llama3"
            )
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsCustomProviderSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "")

            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults),
                "https://api.example.com/v1"
            )
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "custom-model")
        }
    }

    func testDynamicAIProviderPreferenceRoundTripsOpenRouterModels() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults), [])

            VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b", "z-ai/glm-4.5"], to: defaults)

            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults),
                ["openai/gpt-oss-120b", "z-ai/glm-4.5"]
            )
        }
    }

    func testDynamicAIProviderPreferenceAppliesOpenRouterModelRefreshPlan() {
        withIsolatedDefaults { defaults in
            let appliedModel = VoiceInkDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
                VoiceInkAIEnhancementModelRefreshPlan(
                    refreshedModelNames: ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"],
                    selectedModelToSave: "anthropic/claude-3.5-sonnet"
                ),
                to: defaults
            )

            XCTAssertEqual(appliedModel, "anthropic/claude-3.5-sonnet")
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults),
                ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"]
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )

            let ignoredModel = VoiceInkDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
                .failed,
                to: defaults
            )

            XCTAssertNil(ignoredModel)
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults), [])
            XCTAssertEqual(
                VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults),
                "anthropic/claude-3.5-sonnet"
            )
        }
    }

    func testFillerWordPreferenceUsesDefaultWordsWhenMissing() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                VoiceInkFillerWords.defaultWords
            )
        }
    }

    func testFillerWordPreferenceRoundTripsSavedWords() {
        withIsolatedDefaults { defaults in
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)

            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                ["um", "like"]
            )
        }
    }

    func testFillerWordPreferenceClearsSavedWords() {
        withIsolatedDefaults { defaults in
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)
            VoiceInkFillerWordPreference.clearWords(from: defaults)

            XCTAssertEqual(
                VoiceInkFillerWordPreference.words(from: defaults),
                VoiceInkFillerWords.defaultWords
            )
        }
    }

    func testWordReplacementPreferenceRoundTripsSharedRules() {
        withIsolatedDefaults { defaults in
            let rules = [
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ]

            VoiceInkWordReplacementPreference.saveRules(rules, to: defaults)

            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), rules)

            VoiceInkWordReplacementPreference.clearRules(from: defaults)
            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testWordReplacementPreferenceIgnoresInvalidStoredData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data([0]), forKey: VoiceInkUserDefaultsKey.wordReplacements)

            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
        }
    }

    func testCustomVocabularyPreferenceNormalizesTerms() {
        withIsolatedDefaults { defaults in
            VoiceInkCustomVocabularyPreference.saveTerms([" Roma ", "Felix", "roma", ""], to: defaults)

            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), ["Roma", "Felix"])

            VoiceInkCustomVocabularyPreference.clearTerms(from: defaults)
            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), [])
        }
    }

    func testAIEnhancementRequestPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults),
                VoiceInkPreferenceDefault.enhancementRetryOnTimeout
            )
        }
    }

    func testAIEnhancementRequestPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            defaults.set(15, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)

            XCTAssertEqual(VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults), 15)
            XCTAssertFalse(VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
        }
    }

    func testAIEnhancementRequestPreferenceFallsBackForNonPositiveTimeout() {
        withIsolatedDefaults { defaults in
            defaults.set(0, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)

            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
        }
    }

    func testTranscriptionAutoCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, VoiceInkPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, VoiceInkPreferenceDefault.transcriptionRetentionMinutes)
            XCTAssertFalse(configuration.shouldDeleteCompletedTranscriptionImmediately)
        }
    }

    func testTranscriptionAutoCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)

            let configuration = VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionMinutes, 15)
            XCTAssertEqual(configuration.effectiveRetentionMinutes, 15)
        }
    }

    func testTranscriptionAutoCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: -5
        )
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionMinutes, 0)
        XCTAssertTrue(configuration.shouldDeleteCompletedTranscriptionImmediately)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testTranscriptionAutoCleanupConfigurationBuildsCutoffDate() {
        let configuration = VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: true,
            retentionMinutes: 30
        )
        let referenceDate = Date(timeIntervalSince1970: 3_600)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 1_800))
    }

    func testTranscriptionAutoCleanupConfigurationAppliesCompletedTranscriptionRuntimeState() {
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: false,
                retentionMinutes: 0
            ),
            ["ignore"]
        )
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: true,
                retentionMinutes: 30
            ),
            ["sweep"]
        )
        XCTAssertEqual(
            transcriptionAutoCleanupCompletionEvents(
                isEnabled: true,
                retentionMinutes: 0
            ),
            ["delete"]
        )
    }

    private func transcriptionAutoCleanupCompletionEvents(
        isEnabled: Bool,
        retentionMinutes: Int
    ) -> [String] {
        var events: [String] = []
        VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled,
            retentionMinutes: retentionMinutes
        ).applyCompletionRuntimeState(
            ignore: {
                events.append("ignore")
            },
            sweepOldTranscriptions: {
                events.append("sweep")
            },
            deleteCompletedTranscription: {
                events.append("delete")
            }
        )
        return events
    }

    func testTranscriptionAutoCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupPreferences(
                from: VoiceInkTranscriptionAutoCleanupConfiguration(
                    isEnabled: true,
                    retentionMinutes: 15
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupPreferences(
                isEnabled: true,
                retentionMinutes: 15
            )
        )
    }

    func testTranscriptionAutoCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: false,
                    retentionMinutes: 0
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: false,
                retentionMinutes: 0
            )
        )

        XCTAssertEqual(
            VoiceInkTranscriptionAutoCleanupPreference.backupImportPlan(
                from: VoiceInkTranscriptionAutoCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionMinutes: nil
                )
            ),
            VoiceInkTranscriptionAutoCleanupBackupImportPlan(
                isEnabled: nil,
                retentionMinutes: nil
            )
        )
    }

    func testAudioCleanupPreferenceUsesSharedDefaultsWhenUnset() {
        withIsolatedDefaults { defaults in
            let configuration = VoiceInkAudioCleanupPreference.current(from: defaults)

            XCTAssertFalse(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, VoiceInkPreferenceDefault.audioRetentionDays)
            XCTAssertEqual(configuration.effectiveRetentionDays, VoiceInkPreferenceDefault.audioRetentionDays)
        }
    }

    func testAudioCleanupPreferencePreservesDailyCleanupCheckInterval() {
        XCTAssertEqual(VoiceInkAudioCleanupPreference.cleanupCheckInterval, 86_400)
    }

    func testAudioCleanupPreferenceReadsStoredValues() {
        withIsolatedDefaults { defaults in
            VoiceInkAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(14, to: defaults)

            let configuration = VoiceInkAudioCleanupPreference.current(from: defaults)

            XCTAssertTrue(configuration.isEnabled)
            XCTAssertEqual(configuration.retentionDays, 14)
            XCTAssertEqual(configuration.effectiveRetentionDays, 14)
        }
    }

    func testAudioCleanupConfigurationBuildsDayCutoffDate() {
        let configuration = VoiceInkAudioCleanupConfiguration(isEnabled: true, retentionDays: 7)
        let referenceDate = Date(timeIntervalSince1970: 7 * 86_400)

        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), Date(timeIntervalSince1970: 0))
    }

    func testAudioCleanupConfigurationClampsNegativeRetentionForCutoff() {
        let configuration = VoiceInkAudioCleanupConfiguration(isEnabled: true, retentionDays: -1)
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(configuration.effectiveRetentionDays, 0)
        XCTAssertEqual(configuration.cutoffDate(from: referenceDate), referenceDate)
    }

    func testAudioCleanupBackupPreferencesPreserveMacOSExportShape() {
        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupPreferences(
                from: VoiceInkAudioCleanupConfiguration(
                    isEnabled: true,
                    retentionDays: 14
                )
            ),
            VoiceInkAudioCleanupBackupPreferences(
                isEnabled: true,
                retentionDays: 14
            )
        )
    }

    func testAudioCleanupBackupImportPlanPreservesOptionalFields() {
        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupImportPlan(
                from: VoiceInkAudioCleanupBackupPreferences(
                    isEnabled: false,
                    retentionDays: 0
                )
            ),
            VoiceInkAudioCleanupBackupImportPlan(
                isEnabled: false,
                retentionDays: 0
            )
        )

        XCTAssertEqual(
            VoiceInkAudioCleanupPreference.backupImportPlan(
                from: VoiceInkAudioCleanupBackupPreferences(
                    isEnabled: nil,
                    retentionDays: nil
                )
            ),
            VoiceInkAudioCleanupBackupImportPlan(
                isEnabled: nil,
                retentionDays: nil
            )
        )
    }

    func testModelRuntimePreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(VoiceInkModelRuntimePreference.userDefaultsKey, "PrewarmModelOnWake")
        XCTAssertTrue(VoiceInkModelRuntimePreference.defaultShouldPrewarmModelOnWake)
        XCTAssertEqual(VoiceInkModelRuntimePreference.prewarmScheduleDelay, .seconds(3))
        XCTAssertEqual(
            VoiceInkModelRuntimePreference.registeredDefaults[VoiceInkModelRuntimePreference.userDefaultsKey] as? Bool,
            true
        )
    }

    func testModelRuntimePreferenceReadsSavesAndClearsPrewarmFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            XCTAssertFalse(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))

            VoiceInkModelRuntimePreference.clear(from: defaults)
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
        }
    }

    func testRecorderPreviewPreferenceRegisteredDefaultsPreserveMacOSPolicy() {
        XCTAssertEqual(VoiceInkRecorderPreviewPreference.userDefaultsKey, "showLiveTextPreview")
        XCTAssertFalse(VoiceInkRecorderPreviewPreference.defaultIsLiveTextPreviewEnabled)
        XCTAssertEqual(
            VoiceInkRecorderPreviewPreference.registeredDefaults[VoiceInkRecorderPreviewPreference.userDefaultsKey] as? Bool,
            false
        )
    }

    func testRecorderPreviewPreferenceReadsSavesAndClearsPreviewFlag() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            VoiceInkRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            XCTAssertTrue(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))

            VoiceInkRecorderPreviewPreference.clear(from: defaults)
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
        }
    }

    func testRecordingShortcutSelectionPreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.none.rawValue, "none")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.none.displayName, "None")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.custom.rawValue, "custom")
        XCTAssertEqual(VoiceInkRecordingShortcutSelection.custom.displayName, "Custom")
    }

    func testRecordingShortcutModePreservesRawValuesAndDisplayNames() {
        XCTAssertEqual(VoiceInkRecordingShortcutMode.special.rawValue, "special")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.special.displayName, "Special")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.toggle.rawValue, "toggle")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.toggle.displayName, "Toggle")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.pushToTalk.displayName, "Push to Talk")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.hybrid.rawValue, "hybrid")
        XCTAssertEqual(VoiceInkRecordingShortcutMode.hybrid.displayName, "Hybrid")
    }

    func testRecordingShortcutModePreservesMonitorPolicy() {
        XCTAssertTrue(VoiceInkRecordingShortcutMode.special.tracksKeyUpEvidence)
        XCTAssertFalse(VoiceInkRecordingShortcutMode.special.allowsShortcutInterruption)

        for mode in [
            VoiceInkRecordingShortcutMode.toggle,
            .pushToTalk,
            .hybrid
        ] {
            XCTAssertFalse(mode.tracksKeyUpEvidence)
            XCTAssertTrue(mode.allowsShortcutInterruption)
        }
    }

    func testReliablePressContextAllowsSpecialShortcutCommit() {
        XCTAssertFalse(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext()
            )
        )
    }

    func testTypingEvidenceDiscardsSpecialShortcut() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(didPressOtherKeyDuringPress: true)
            )
        )
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(didReleaseOtherKeyDuringPress: true)
            )
        )
    }

    func testUnreliableKeyEvidenceFailsClosed() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutKeyEvidencePolicy.shouldDiscardShortcut(
                for: VoiceInkShortcutPressContext(hasReliableKeyEvidence: false)
            )
        )
    }

    func testShortcutInterruptionPolicyPreservesMacOSWindow() {
        XCTAssertEqual(VoiceInkShortcutInterruptionPolicy.interruptionWindow, 1.0)
        XCTAssertTrue(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 10.5))
        XCTAssertTrue(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.0))
        XCTAssertFalse(VoiceInkShortcutInterruptionPolicy.isWithinInterruptionWindow(pressedAt: 10.0, eventTime: 11.1))
    }

    func testRecordingShortcutTimingPolicyPreservesMacOSThresholds() {
        XCTAssertEqual(VoiceInkRecordingShortcutTimingPolicy.pressCooldown, 0.08)
        XCTAssertEqual(VoiceInkRecordingShortcutTimingPolicy.hybridPushToTalkThreshold, 0.5)
    }

    func testRecordingShortcutTimingPolicyDetectsPressCooldown() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: nil,
                now: now
            )
        )
        XCTAssertTrue(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.079),
                now: now
            )
        )
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.isPressWithinCooldown(
                lastPressTime: now.addingTimeInterval(-0.08),
                now: now
            )
        )
    }

    func testRecordingShortcutTimingPolicyHybridStopRequiresThresholdAndRecordingState() {
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.499,
                recordingState: .recording
            )
        )
        XCTAssertTrue(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .recording
            )
        )
        XCTAssertFalse(
            VoiceInkRecordingShortcutTimingPolicy.shouldStopHybridRecording(
                pressDuration: 0.5,
                recordingState: .idle
            )
        )
    }

    func testRecordingShortcutTimingPolicyConvertsSleepDelaySafely() {
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: 0.25),
            250_000_000
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: -1),
            0
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .infinity),
            0
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutTimingPolicy.sleepNanoseconds(delaySeconds: .greatestFiniteMagnitude),
            UInt64.max
        )
    }

    func testShortPressSchedulesEmptyTapFallbackOnlyBelowThreshold() {
        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.319)
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.32)
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldScheduleFallback(pressDuration: 0.5)
        )
    }

    func testConsumeFallbackRequiresFreshCompletedEmptyTranscription() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = createdAt.addingTimeInterval(29.9)

        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: " \n ",
                enhancedText: nil
            )
        )
        XCTAssertTrue(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: now,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "  "
            )
        )
    }

    func testConsumeFallbackRejectsStalePendingOrNonEmptyTranscriptions() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt.addingTimeInterval(30.1),
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .pending,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: nil,
                rawText: "",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "hello",
                enhancedText: nil
            )
        )
        XCTAssertFalse(
            VoiceInkSpecialShortcutEmptyFallbackPolicy.shouldConsumeFallback(
                createdAt: createdAt,
                now: createdAt,
                transcriptionStatus: .completed,
                rawText: "",
                enhancedText: "hello"
            )
        )
    }

    func testRecordingShortcutPreferencePreservesMacOSSettingsPresentation() {
        let presentation = VoiceInkRecordingShortcutPreference.macOSSettingsPresentation

        XCTAssertEqual(presentation.sectionTitle, "Shortcuts")
        XCTAssertEqual(presentation.primaryShortcutLabel, "Primary Shortcut")
        XCTAssertEqual(presentation.secondaryShortcutLabel, "Secondary Shortcut")
        XCTAssertEqual(presentation.addSecondaryShortcutButtonTitle, "Add Second Shortcut")
        XCTAssertEqual(presentation.emptyTapPasteLastTranscriptLabel, "Empty Tap Pastes Last")
        XCTAssertEqual(presentation.additionalSectionTitle, "Additional Shortcuts")
        XCTAssertEqual(presentation.pasteLastTranscriptionOriginalLabel, "Paste Last Transcription (Original)")
        XCTAssertEqual(presentation.pasteLastTranscriptionEnhancedLabel, "Paste Last Transcription (Enhanced)")
        XCTAssertEqual(presentation.retryLastTranscriptionLabel, "Retry Last Transcription")
        XCTAssertEqual(presentation.cancelRecordingLabel, "Cancel Recording")
        XCTAssertEqual(presentation.resetToDefaultHelp, "Reset to default")
        XCTAssertEqual(presentation.middleClickRecordingLabel, "Middle-Click Recording")
        XCTAssertEqual(presentation.activationDelayLabel, "Activation Delay")
        XCTAssertEqual(presentation.activationDelayUnitLabel, "ms")
    }

    func testRecordingShortcutPreferenceBuildsMiddleClickActivationDelayFormatter() {
        let formatter = VoiceInkRecordingShortcutPreference.middleClickActivationDelayFormatter()

        XCTAssertEqual(formatter.minimum, NSNumber(value: VoiceInkRecordingShortcutPreference.minimumMiddleClickActivationDelay))
        XCTAssertNil(formatter.maximum)
    }

    func testRecordingShortcutPreferencePreservesMacOSRecorderPresentation() {
        let presentation = VoiceInkRecordingShortcutPreference.macOSRecorderPresentation

        XCTAssertEqual(presentation.recordingPlaceholderText, "Press shortcut")
        XCTAssertEqual(presentation.idleAccessibilityLabel, "Record shortcut")
        XCTAssertEqual(presentation.idleButtonText, "Record")
    }

    func testRecordingShortcutPreferencePreservesMacOSNotificationNames() {
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.shortcutDidChangeNotificationName.rawValue,
            "ShortcutStoreShortcutDidChange"
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.shortcutRecordingDidStartNotificationName.rawValue,
            "ShortcutRecorderRecordingDidStart"
        )
    }

    func testRecordingShortcutPreferenceKeysDefaultsAndRegisteredDefaults() {
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.selectionKey(for: .primary),
            VoiceInkUserDefaultsKey.primaryRecordingShortcut
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.selectionKey(for: .secondary),
            VoiceInkUserDefaultsKey.secondaryRecordingShortcut
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.modeKey(for: .primary),
            VoiceInkUserDefaultsKey.primaryRecordingShortcutMode
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.modeKey(for: .secondary),
            VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode
        )
        XCTAssertEqual(
            VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap,
            "specialShortcutPasteLastTranscriptOnEmptyTap"
        )
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultSelection(for: .primary), .custom)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultSelection(for: .secondary), .none)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultMode(for: .primary), .special)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.defaultMode(for: .secondary), .hybrid)
        XCTAssertEqual(VoiceInkRecordingShortcutPreference.minimumMiddleClickActivationDelay, 0)
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.isMiddleClickToggleEnabled] as? Bool,
            VoiceInkPreferenceDefault.isMiddleClickToggleEnabled
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.middleClickActivationDelay] as? Int,
            VoiceInkPreferenceDefault.middleClickActivationDelay
        )
        XCTAssertEqual(
            VoiceInkRecordingShortcutPreference.registeredDefaults[VoiceInkUserDefaultsKey.specialShortcutPasteLastTranscriptOnEmptyTap] as? Bool,
            VoiceInkPreferenceDefault.specialShortcutPasteLastTranscriptOnEmptyTap
        )
    }

    func testShortcutActionIdentifierPreservesStorageAndLegacyKeys() {
        let powerModeId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.storageName, "primaryRecording")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.shortcutStorageKey, "Shortcut_primaryRecording")
        XCTAssertTrue(VoiceInkShortcutActionIdentifier.primaryRecording.isStoredShortcut)
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.recordingShortcutSlot, .primary)
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.selectionKey, VoiceInkUserDefaultsKey.primaryRecordingShortcut)
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.legacySelectionKey, "selectedHotkey1")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.modeKey, VoiceInkUserDefaultsKey.primaryRecordingShortcutMode)
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.legacyModeKey, "hotkeyMode1")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.legacyCustomRecordingShortcutKey, "CustomRecordingShortcut_primary")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.primaryRecording.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_toggleMiniRecorder")

        XCTAssertEqual(VoiceInkShortcutActionIdentifier.secondaryRecording.legacySelectionKey, "selectedHotkey2")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.secondaryRecording.legacyModeKey, "hotkeyMode2")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.secondaryRecording.legacyCustomRecordingShortcutKey, "CustomRecordingShortcut_secondary")
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.secondaryRecording.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_toggleMiniRecorder2")

        let powerMode = VoiceInkShortcutActionIdentifier.powerMode(powerModeId)
        XCTAssertEqual(powerMode.storageName, "powerMode_11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(powerMode.shortcutStorageKey, "Shortcut_powerMode_11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(powerMode.legacyKeyboardShortcutStorageKey, "KeyboardShortcuts_powerMode_11111111-2222-3333-4444-555555555555")

        XCTAssertFalse(VoiceInkShortcutActionIdentifier.miniRecorderPrompt(2).isStoredShortcut)
        XCTAssertNil(VoiceInkShortcutActionIdentifier.miniRecorderPrompt(2).legacyKeyboardShortcutStorageKey)
        XCTAssertEqual(
            VoiceInkShortcutActionIdentifier.legacyKeyboardShortcutActions,
            [
                .primaryRecording,
                .secondaryRecording,
                .pasteLastTranscription,
                .pasteLastEnhancement,
                .retryLastTranscription,
                .cancelRecorder,
                .openHistoryWindow,
                .quickAddToDictionary,
                .toggleEnhancement
            ]
        )
        XCTAssertEqual(VoiceInkShortcutActionIdentifier.legacyCustomRecordingShortcutActions, [.primaryRecording, .secondaryRecording])
    }

    func testShortcutActionPresentationPreservesMacOSDisplayNames() {
        let powerModeId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .primaryRecording),
            "Primary Shortcut"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .secondaryRecording),
            "Secondary Shortcut"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .pasteLastTranscription),
            "Paste Last Transcription"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .pasteLastEnhancement),
            "Paste Last Enhanced Transcription"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .retryLastTranscription),
            "Retry Last Transcription"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .cancelRecorder),
            "Cancel Recording"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .openHistoryWindow),
            "Open History Window"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .quickAddToDictionary),
            "Quick Add to Dictionary"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .toggleEnhancement),
            "Toggle Enhancement"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .powerMode(powerModeId)),
            "Power Mode"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .powerMode(powerModeId), powerModeName: "Writing"),
            "Writing Power Mode"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .miniRecorderEscape),
            "Mini Recorder Cancel"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .miniRecorderPrompt(0)),
            "Select Prompt 1"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .miniRecorderPrompt(9)),
            "Select Prompt 10"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .miniRecorderPowerMode(0)),
            "Select Power Mode 1"
        )
        XCTAssertEqual(
            VoiceInkShortcutActionPresentation.displayName(for: .miniRecorderPowerMode(9)),
            "Select Power Mode 10"
        )
    }

    func testMacOSShortcutNotificationPresentationPreservesShellCopy() {
        XCTAssertEqual(
            VoiceInkMacOSShortcutNotificationPresentation.inputMonitoringPermissionRequired,
            VoiceInkMacOSShortcutNotificationPresentation(
                title: "Enable Input Monitoring for shortcuts",
                duration: 6,
                actionButtonLabel: "Open Settings"
            )
        )
        XCTAssertEqual(
            VoiceInkMacOSShortcutNotificationPresentation.accessibilityPermissionRequired,
            VoiceInkMacOSShortcutNotificationPresentation(
                title: "Enable Accessibility for shortcuts",
                duration: 6,
                actionButtonLabel: "Open Settings"
            )
        )
        XCTAssertEqual(
            VoiceInkMacOSShortcutNotificationPresentation.monitorStartFailed,
            VoiceInkMacOSShortcutNotificationPresentation(
                title: "Keyboard shortcut monitor could not start",
                duration: 6
            )
        )
        XCTAssertEqual(
            VoiceInkMacOSShortcutNotificationPresentation.miniRecorderEscapeConfirmation(duration: 1.5),
            VoiceInkMacOSShortcutNotificationPresentation(
                title: "Press ESC again to cancel recording",
                duration: 1.5
            )
        )
    }

    func testMiniRecorderEscapeShortcutPolicyPreservesMacOSTiming() {
        XCTAssertEqual(VoiceInkMiniRecorderEscapeShortcutPolicy.doublePressThreshold, 1.5)
        XCTAssertEqual(
            VoiceInkMiniRecorderEscapeShortcutPolicy.confirmationPresentation,
            VoiceInkMacOSShortcutNotificationPresentation(
                title: "Press ESC again to cancel recording",
                duration: 1.5
            )
        )
        XCTAssertEqual(VoiceInkMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(), 1_500_000_000)
        XCTAssertEqual(
            VoiceInkMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: -1),
            0
        )
        XCTAssertEqual(
            VoiceInkMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: .infinity),
            0
        )
        XCTAssertEqual(
            VoiceInkMiniRecorderEscapeShortcutPolicy.timeoutNanoseconds(threshold: .greatestFiniteMagnitude),
            UInt64.max
        )

        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            VoiceInkMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: nil,
                now: now
            )
        )
        XCTAssertTrue(
            VoiceInkMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: now.addingTimeInterval(-1.5),
                now: now
            )
        )
        XCTAssertFalse(
            VoiceInkMiniRecorderEscapeShortcutPolicy.isSecondPress(
                firstPressTime: now.addingTimeInterval(-1.51),
                now: now
            )
        )
    }

    func testRecordingShortcutSelectionMigrationPlanMigratesCurrentPresetAndRemovesLegacyKey() {
        withIsolatedDefaults { defaults in
            defaults.set("rightOption", forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcut)
            defaults.set("leftShift", forKey: "selectedHotkey1")

            let plan = VoiceInkRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .primaryRecording,
                allowsNone: false,
                from: defaults
            )

            XCTAssertEqual(plan.selection, .custom)
            XCTAssertEqual(plan.destinationKey, VoiceInkUserDefaultsKey.primaryRecordingShortcut)
            XCTAssertEqual(plan.legacyKeyToRemove, "selectedHotkey1")
            XCTAssertEqual(plan.presetToStore, .rightOption)
            XCTAssertNil(plan.defaultPresetToStore)

            VoiceInkRecordingShortcutPreference.applyShortcutSelectionMigrationPlan(plan, to: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcut), "custom")
            XCTAssertNil(defaults.object(forKey: "selectedHotkey1"))
        }
    }

    func testRecordingShortcutSelectionMigrationPlanHandlesLegacyNoneAndAbsentDefaults() {
        withIsolatedDefaults { defaults in
            defaults.set("none", forKey: "selectedHotkey2")

            let secondaryPlan = VoiceInkRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .secondaryRecording,
                allowsNone: true,
                from: defaults
            )

            XCTAssertEqual(secondaryPlan.selection, .none)
            XCTAssertEqual(secondaryPlan.destinationKey, VoiceInkUserDefaultsKey.secondaryRecordingShortcut)
            XCTAssertEqual(secondaryPlan.legacyKeyToRemove, "selectedHotkey2")
            XCTAssertNil(secondaryPlan.presetToStore)
            XCTAssertNil(secondaryPlan.defaultPresetToStore)

            VoiceInkRecordingShortcutPreference.applyShortcutSelectionMigrationPlan(secondaryPlan, to: defaults)

            XCTAssertEqual(defaults.string(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcut), "none")
            XCTAssertNil(defaults.object(forKey: "selectedHotkey2"))
        }

        withIsolatedDefaults { defaults in
            let primaryPlan = VoiceInkRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .primaryRecording,
                allowsNone: false,
                from: defaults
            )

            XCTAssertEqual(primaryPlan.selection, .custom)
            XCTAssertEqual(primaryPlan.destinationKey, VoiceInkUserDefaultsKey.primaryRecordingShortcut)
            XCTAssertNil(primaryPlan.legacyKeyToRemove)
            XCTAssertNil(primaryPlan.presetToStore)
            XCTAssertEqual(primaryPlan.defaultPresetToStore, .leftShift)

            let absentSecondaryPlan = VoiceInkRecordingShortcutPreference.shortcutSelectionMigrationPlan(
                for: .secondaryRecording,
                allowsNone: true,
                from: defaults
            )

            XCTAssertEqual(absentSecondaryPlan.selection, .none)
            XCTAssertNil(absentSecondaryPlan.destinationKey)
            XCTAssertNil(absentSecondaryPlan.legacyKeyToRemove)
            XCTAssertNil(absentSecondaryPlan.presetToStore)
            XCTAssertNil(absentSecondaryPlan.defaultPresetToStore)
        }
    }

    func testRecordingShortcutModeMigrationMovesLegacyValuesAndMarksCompletion() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isLegacyKeyboardShortcutsMigrationComplete(in: defaults))
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isLegacyCustomRecordingShortcutsMigrationComplete(in: defaults))

            VoiceInkRecordingShortcutPreference.markLegacyKeyboardShortcutsMigrationComplete(in: defaults)
            VoiceInkRecordingShortcutPreference.markLegacyCustomRecordingShortcutsMigrationComplete(in: defaults)

            XCTAssertTrue(VoiceInkRecordingShortcutPreference.isLegacyKeyboardShortcutsMigrationComplete(in: defaults))
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.isLegacyCustomRecordingShortcutsMigrationComplete(in: defaults))

            defaults.set("pushToTalk", forKey: "hotkeyMode2")

            let mode = VoiceInkRecordingShortcutPreference.migrateShortcutMode(
                for: .secondaryRecording,
                in: defaults
            )

            XCTAssertEqual(mode, .pushToTalk)
            XCTAssertEqual(defaults.string(forKey: VoiceInkUserDefaultsKey.secondaryRecordingShortcutMode), "pushToTalk")
            XCTAssertNil(defaults.object(forKey: "hotkeyMode2"))
        }

        withIsolatedDefaults { defaults in
            defaults.set("toggle", forKey: VoiceInkUserDefaultsKey.primaryRecordingShortcutMode)
            defaults.set("hybrid", forKey: "hotkeyMode1")

            let mode = VoiceInkRecordingShortcutPreference.migrateShortcutMode(
                for: .primaryRecording,
                in: defaults
            )

            XCTAssertEqual(mode, .toggle)
            XCTAssertNil(defaults.object(forKey: "hotkeyMode1"))
        }
    }

    func testRecordingShortcutPreferenceReadsSavesAndClearsSettings() {
        withIsolatedDefaults { defaults in
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .secondary, from: defaults), .hybrid)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            VoiceInkRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            VoiceInkRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)

            XCTAssertEqual(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults), .custom)
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.selection(for: .secondary, from: defaults),
                VoiceInkRecordingShortcutSelection.none
            )
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .toggle)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .secondary, from: defaults), .pushToTalk)
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 350)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))

            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(-1, to: defaults)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 0)
            defaults.set(-50, forKey: VoiceInkUserDefaultsKey.middleClickActivationDelay)
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults), 0)

            VoiceInkRecordingShortcutPreference.clear(from: defaults)

            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
        }
    }

    func testShortcutStoragePreferenceStoresDataAndClearedState() {
        withIsolatedDefaults { defaults in
            let shortcutKey = "Shortcut_primaryRecording"
            let clearedKey = VoiceInkShortcutStoragePreference.clearedKey(for: shortcutKey)
            let shortcutData = Data([1, 2, 3])

            XCTAssertEqual(clearedKey, "Shortcut_primaryRecording_cleared")
            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertFalse(VoiceInkShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            VoiceInkShortcutStoragePreference.markShortcutCleared(for: shortcutKey, to: defaults)

            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertTrue(VoiceInkShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            VoiceInkShortcutStoragePreference.saveShortcutData(shortcutData, for: shortcutKey, to: defaults)

            XCTAssertEqual(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults), shortcutData)
            XCTAssertNil(defaults.object(forKey: clearedKey))

            VoiceInkShortcutStoragePreference.removeShortcutStorage(for: shortcutKey, from: defaults)

            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertNil(defaults.object(forKey: clearedKey))
        }
    }

    func testShortcutStoragePreferenceCapturesAndRestoresStoredState() {
        withIsolatedDefaults { defaults in
            let shortcutKey = "Shortcut_secondaryRecording"
            let originalData = Data([9, 8, 7])
            let replacementData = Data([1, 2, 3])

            VoiceInkShortcutStoragePreference.saveShortcutData(originalData, for: shortcutKey, to: defaults)
            let dataState = VoiceInkShortcutStoragePreference.storedState(for: shortcutKey, from: defaults)

            XCTAssertEqual(dataState, VoiceInkShortcutStorageState(shortcutData: originalData, clearedValue: nil))

            VoiceInkShortcutStoragePreference.markShortcutCleared(for: shortcutKey, to: defaults)
            let clearedState = VoiceInkShortcutStoragePreference.storedState(for: shortcutKey, from: defaults)

            XCTAssertEqual(clearedState, VoiceInkShortcutStorageState(shortcutData: nil, clearedValue: true))

            VoiceInkShortcutStoragePreference.saveShortcutData(replacementData, for: shortcutKey, to: defaults)
            VoiceInkShortcutStoragePreference.restoreStoredState(clearedState, for: shortcutKey, to: defaults)

            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults))
            XCTAssertTrue(VoiceInkShortcutStoragePreference.isShortcutCleared(for: shortcutKey, from: defaults))

            VoiceInkShortcutStoragePreference.restoreStoredState(dataState, for: shortcutKey, to: defaults)

            XCTAssertEqual(VoiceInkShortcutStoragePreference.shortcutData(for: shortcutKey, from: defaults), originalData)
            XCTAssertNil(defaults.object(forKey: VoiceInkShortcutStoragePreference.clearedKey(for: shortcutKey)))
        }
    }

    func testRecordingShortcutPreferenceBuildsBackupPreferences() throws {
        let backup = VoiceInkRecordingShortcutPreference.backupPreferences(
            primaryRecordingShortcut: .custom,
            secondaryRecordingShortcut: .none,
            primaryRecordingShortcutMode: .toggle,
            secondaryRecordingShortcutMode: .pushToTalk,
            specialShortcutPasteLastTranscriptOnEmptyTap: false,
            isMiddleClickToggleEnabled: true,
            middleClickActivationDelay: 350
        )

        XCTAssertEqual(backup.primaryRecordingShortcutRawValue, "custom")
        XCTAssertEqual(backup.secondaryRecordingShortcutRawValue, "none")
        XCTAssertEqual(backup.primaryRecordingShortcutModeRawValue, "toggle")
        XCTAssertEqual(backup.secondaryRecordingShortcutModeRawValue, "pushToTalk")
        XCTAssertEqual(backup.specialShortcutPasteLastTranscriptOnEmptyTap, false)
        XCTAssertEqual(backup.isMiddleClickToggleEnabled, true)
        XCTAssertEqual(backup.middleClickActivationDelay, 350)

        let data = try JSONEncoder().encode(backup)
        XCTAssertEqual(
            try JSONDecoder().decode(VoiceInkRecordingShortcutBackupPreferences.self, from: data),
            backup
        )
    }

    func testRecordingShortcutPreferenceBackupImportPlanSkipsInvalidRawValues() {
        let plan = VoiceInkRecordingShortcutPreference.backupImportPlan(
            from: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: "custom",
                secondaryRecordingShortcutRawValue: "invalid-selection",
                primaryRecordingShortcutModeRawValue: "toggle",
                secondaryRecordingShortcutModeRawValue: "invalid-mode",
                specialShortcutPasteLastTranscriptOnEmptyTap: false,
                isMiddleClickToggleEnabled: true,
                middleClickActivationDelay: 350
            )
        )

        var appliedEvents = [String]()
        plan.applyRuntimeState(
            setPrimaryRecordingShortcut: { appliedEvents.append("primary:\($0.rawValue)") },
            setSecondaryRecordingShortcut: { appliedEvents.append("secondary:\($0.rawValue)") },
            setPrimaryRecordingShortcutMode: { appliedEvents.append("primaryMode:\($0.rawValue)") },
            setSecondaryRecordingShortcutMode: { appliedEvents.append("secondaryMode:\($0.rawValue)") },
            setSpecialShortcutPasteLastTranscriptOnEmptyTap: { appliedEvents.append("paste:\($0)") },
            setMiddleClickToggleEnabled: { appliedEvents.append("middleClick:\($0)") },
            setMiddleClickActivationDelay: { appliedEvents.append("middleClickDelay:\($0)") }
        )

        XCTAssertEqual(
            appliedEvents,
            [
                "primary:custom",
                "primaryMode:toggle",
                "paste:false",
                "middleClick:true",
                "middleClickDelay:350"
            ]
        )

        let negativeDelayPlan = VoiceInkRecordingShortcutPreference.backupImportPlan(
            from: VoiceInkRecordingShortcutBackupPreferences(
                primaryRecordingShortcutRawValue: nil,
                secondaryRecordingShortcutRawValue: nil,
                primaryRecordingShortcutModeRawValue: nil,
                secondaryRecordingShortcutModeRawValue: nil,
                specialShortcutPasteLastTranscriptOnEmptyTap: nil,
                isMiddleClickToggleEnabled: nil,
                middleClickActivationDelay: -1
            )
        )

        var negativeDelayEvents = [String]()
        negativeDelayPlan.applyRuntimeState(
            setPrimaryRecordingShortcut: { negativeDelayEvents.append("primary:\($0.rawValue)") },
            setSecondaryRecordingShortcut: { negativeDelayEvents.append("secondary:\($0.rawValue)") },
            setPrimaryRecordingShortcutMode: { negativeDelayEvents.append("primaryMode:\($0.rawValue)") },
            setSecondaryRecordingShortcutMode: { negativeDelayEvents.append("secondaryMode:\($0.rawValue)") },
            setSpecialShortcutPasteLastTranscriptOnEmptyTap: { negativeDelayEvents.append("paste:\($0)") },
            setMiddleClickToggleEnabled: { negativeDelayEvents.append("middleClick:\($0)") },
            setMiddleClickActivationDelay: { negativeDelayEvents.append("middleClickDelay:\($0)") }
        )

        XCTAssertEqual(negativeDelayEvents, ["middleClickDelay:0"])
    }

    func testShortcutBackupPolicyExportsGeneralShortcutsInStableOrder() {
        XCTAssertEqual(
            VoiceInkShortcutBackupPolicy.generalBackupShortcutExportPlan(
                availableActionIdentifiers: [
                    .toggleEnhancement,
                    .miniRecorderEscape,
                    .primaryRecording,
                    .retryLastTranscription,
                    .quickAddToDictionary
                ]
            ),
            [
                .primaryRecording,
                .retryLastTranscription,
                .quickAddToDictionary,
                .toggleEnhancement
            ]
        )
    }

    func testShortcutBackupPolicyBuildsGeneralShortcutRecordsThroughAdapter() {
        var requestedActionIdentifiers = [VoiceInkShortcutActionIdentifier]()
        let records = VoiceInkShortcutBackupPolicy.generalBackupShortcutRecords { actionIdentifier in
            requestedActionIdentifiers.append(actionIdentifier)
            switch actionIdentifier {
            case .primaryRecording:
                return "primary"
            case .retryLastTranscription:
                return "retry"
            case .toggleEnhancement:
                return "toggle"
            default:
                return nil
            }
        }

        XCTAssertEqual(
            requestedActionIdentifiers,
            VoiceInkShortcutBackupPolicy.generalBackupShortcutActionIdentifiers
        )
        XCTAssertEqual(
            records,
            [
                .primaryRecording: "primary",
                .retryLastTranscription: "retry",
                .toggleEnhancement: "toggle"
            ]
        )
    }

    func testShortcutBackupPolicyImportsGeneralShortcutsWithRecordingSelections() {
        XCTAssertEqual(
            VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(
                importedActionIdentifiers: [
                    .secondaryRecording,
                    .miniRecorderEscape,
                    .pasteLastTranscription,
                    .primaryRecording
                ]
            ),
            [
                VoiceInkShortcutBackupImport(
                    actionIdentifier: .primaryRecording,
                    recordingShortcutSlot: .primary,
                    recordingShortcutSelection: .custom
                ),
                VoiceInkShortcutBackupImport(
                    actionIdentifier: .secondaryRecording,
                    recordingShortcutSlot: .secondary,
                    recordingShortcutSelection: .custom
                ),
                VoiceInkShortcutBackupImport(
                    actionIdentifier: .pasteLastTranscription,
                    recordingShortcutSlot: nil,
                    recordingShortcutSelection: nil
                )
            ]
        )
    }

    func testSharedPreferenceResetClearsCoreUserSettings() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            VoiceInkModeStorage.saveModes([mode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)
            VoiceInkOnboardingPreference.saveHasCompletedOnboarding(to: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(120, to: defaults)
            VoiceInkVADPreference.saveIsEnabled(false, to: defaults)
            PunctuationCleanupMode.setCurrent(.removeAll, in: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(false, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(true, to: defaults)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(false, to: defaults)
            VoiceInkFillerWordPreference.saveWords(["um", "like"], to: defaults)
            VoiceInkWordReplacementPreference.saveRules([
                VoiceInkWordReplacementRule(originalText: "roma", replacementText: "Roma Just Talk")
            ], to: defaults)
            VoiceInkCustomVocabularyPreference.saveTerms(["Roma", "Felix"], to: defaults)
            VoiceInkDictionaryListSortPreference.saveVocabularySortMode(.wordDescending, to: defaults)
            VoiceInkDictionaryListSortPreference.saveWordReplacementSortMode(.replacementDescending, to: defaults)
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr", to: defaults)
            VoiceInkTranscriptionPromptPreference.savePrompt("custom prompt", to: defaults)
            VoiceInkCurrentTranscriptionModelPreference.saveModelName("nova-3", to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue("OpenRouter", to: defaults)
            VoiceInkAIEnhancementProviderPreference.saveSelectedModel("openai/gpt-oss-120b", for: "OpenRouter", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL("http://example.local:11434", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel("mistral", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL("https://api.example.com/v1", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel("custom-model", to: defaults)
            VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(["openai/gpt-oss-120b"], to: defaults)
            VoiceInkLocalCLIPreference.saveCommandTemplate("codex exec \"$VOICEINK_FULL_PROMPT\"", to: defaults)
            VoiceInkLocalCLIPreference.saveSelectedTemplate(.codex, to: defaults)
            VoiceInkLocalCLIPreference.saveTimeoutSeconds(90, to: defaults)
            defaults.set(15, forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
            defaults.set(false, forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
            VoiceInkTranscriptionAutoCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkTranscriptionAutoCleanupPreference.saveRetentionMinutes(15, to: defaults)
            VoiceInkAudioCleanupPreference.saveIsEnabled(true, to: defaults)
            VoiceInkAudioCleanupPreference.saveRetentionDays(30, to: defaults)
            let customPrompt = VoiceInkCustomPrompt(title: "Custom", promptText: "Clean this")
            VoiceInkCustomPromptStorage.savePrompts([customPrompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(customPrompt.id, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseClipboardContext(true, to: defaults)
            VoiceInkAIEnhancementContextPreference.saveUseScreenCaptureContext(true, to: defaults)
            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)
            VoiceInkPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)
            VoiceInkModelRuntimePreference.saveShouldPrewarmModelOnWake(false, to: defaults)
            VoiceInkRecorderPreviewPreference.saveIsLiveTextPreviewEnabled(true, to: defaults)
            VoiceInkAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.custom, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveSelection(.none, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.toggle, for: .primary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMode(.pushToTalk, for: .secondary, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickToggleEnabled(true, to: defaults)
            VoiceInkRecordingShortcutPreference.saveMiddleClickActivationDelay(350, to: defaults)
            VoiceInkRecordingShortcutPreference.saveShouldPasteLastTranscriptOnEmptyTap(false, to: defaults)
            let powerModeConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            VoiceInkPowerModeConfigurationPreference.saveConfigurations([powerModeConfig], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(powerModeConfig.id, to: defaults)
            try? VoiceInkPowerModeSessionPreference.saveActiveSession(
                VoiceInkPowerModeSession(
                    id: UUID(),
                    startTime: Date(timeIntervalSince1970: 1_700_000_000),
                    originalState: VoiceInkPowerModeApplicationState(
                        isEnhancementEnabled: true,
                        useScreenCaptureContext: false
                    )
                ),
                to: defaults
            )

            VoiceInkSharedPreferenceReset.clearCoreUserSettings(from: defaults, providers: [.groq])

            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkModeStorage.loadSelectedModeId(from: defaults))
            XCTAssertFalse(VoiceInkOnboardingPreference.hasCompletedOnboarding(from: defaults))
            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(
                VoiceInkAudioSessionTimeoutPreference.timeoutSeconds(from: defaults),
                VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
            )
            XCTAssertEqual(
                VoiceInkVADPreference.isEnabled(from: defaults),
                VoiceInkPreferenceDefault.isVADEnabled
            )
            XCTAssertEqual(PunctuationCleanupMode.current(in: defaults), .keep)
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.isTextFormattingEnabled(from: defaults),
                VoiceInkPreferenceDefault.isTextFormattingEnabled
            )
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.shouldLowercase(from: defaults),
                VoiceInkPreferenceDefault.lowercaseTranscription
            )
            XCTAssertEqual(
                VoiceInkTranscriptionCleanupPreferenceStorage.shouldRemoveFillerWords(from: defaults),
                VoiceInkPreferenceDefault.removeFillerWords
            )
            XCTAssertEqual(VoiceInkFillerWordPreference.words(from: defaults), VoiceInkFillerWords.defaultWords)
            XCTAssertEqual(VoiceInkWordReplacementPreference.rules(from: defaults), [])
            XCTAssertEqual(VoiceInkCustomVocabularyPreference.terms(from: defaults), [])
            XCTAssertEqual(VoiceInkDictionaryListSortPreference.vocabularySortMode(from: defaults), .wordAscending)
            XCTAssertEqual(
                VoiceInkDictionaryListSortPreference.wordReplacementSortMode(from: defaults),
                .originalAscending
            )
            XCTAssertEqual(
                VoiceInkTranscriptionLanguagePreference.selectedLanguage(from: defaults),
                VoiceInkLanguageCatalog.autoDetectCode
            )
            XCTAssertNil(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults))
            XCTAssertNil(VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults))
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue(from: defaults))
            XCTAssertNil(VoiceInkAIEnhancementProviderPreference.selectedModel(for: "OpenRouter", from: defaults))
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults),
                VoiceInkPreferenceDefault.ollamaBaseURL
            )
            XCTAssertEqual(
                VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(from: defaults, fallback: "llama2"),
                "llama2"
            )
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults), "")
            XCTAssertEqual(VoiceInkDynamicAIProviderPreference.openRouterModels(from: defaults), [])
            XCTAssertEqual(VoiceInkLocalCLIPreference.commandTemplate(from: defaults), "")
            XCTAssertEqual(VoiceInkLocalCLIPreference.selectedTemplate(from: defaults), .pi)
            XCTAssertEqual(VoiceInkLocalCLIPreference.timeoutSeconds(from: defaults), 45)
            XCTAssertEqual(
                VoiceInkAIEnhancementRequestPreference.timeoutSeconds(from: defaults),
                TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
            )
            XCTAssertTrue(VoiceInkAIEnhancementRequestPreference.shouldRetryOnTimeout(from: defaults))
            XCTAssertEqual(
                VoiceInkTranscriptionAutoCleanupPreference.current(from: defaults),
                VoiceInkTranscriptionAutoCleanupConfiguration(
                    isEnabled: false,
                    retentionMinutes: VoiceInkPreferenceDefault.transcriptionRetentionMinutes
                )
            )
            XCTAssertEqual(
                VoiceInkAudioCleanupPreference.current(from: defaults),
                VoiceInkAudioCleanupConfiguration(
                    isEnabled: false,
                    retentionDays: VoiceInkPreferenceDefault.audioRetentionDays
                )
            )
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useClipboardContext(from: defaults))
            XCTAssertFalse(VoiceInkAIEnhancementContextPreference.useScreenCaptureContext(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(try? VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertTrue(VoiceInkModelRuntimePreference.shouldPrewarmModelOnWake(from: defaults))
            XCTAssertFalse(VoiceInkRecorderPreviewPreference.isLiveTextPreviewEnabled(from: defaults))
            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertEqual(VoiceInkRecordingShortcutPreference.mode(for: .primary, from: defaults), .special)
            XCTAssertFalse(VoiceInkRecordingShortcutPreference.isMiddleClickToggleEnabled(from: defaults))
            XCTAssertEqual(
                VoiceInkRecordingShortcutPreference.middleClickActivationDelay(from: defaults),
                VoiceInkPreferenceDefault.middleClickActivationDelay
            )
            XCTAssertTrue(VoiceInkRecordingShortcutPreference.shouldPasteLastTranscriptOnEmptyTap(from: defaults))
        }
    }

    func testModeStorageRoundTripsModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let localMode = Mode.defaultLocalWhisper(name: "Local")
            let cloudMode = Mode(
                name: "Cloud",
                transcriptionProvider: .deepgram,
                transcriptionModel: "nova-3-medical"
            )

            VoiceInkModeStorage.saveModes([localMode, cloudMode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(cloudMode.id, to: defaults)

            let loadedModes = VoiceInkModeStorage.loadModes(from: defaults)
            XCTAssertEqual(loadedModes.map(\.name), ["Local", "Cloud"])
            XCTAssertEqual(loadedModes.map(\.id), [localMode.id, cloudMode.id])
            XCTAssertEqual(VoiceInkModeStorage.loadSelectedModeId(from: defaults), cloudMode.id)
        }
    }

    func testModeStorageRepairsStaleModelSelectionsOnLoad() {
        withIsolatedDefaults { defaults in
            let staleMode = Mode(
                name: "Cloud",
                transcriptionProvider: .deepgram,
                transcriptionModel: "stale-transcription-model",
                isPostProcessingEnabled: true,
                postProcessingProvider: .gemini,
                postProcessingModel: "stale-post-processing-model"
            )

            VoiceInkModeStorage.saveModes([staleMode], to: defaults)

            let loadedMode = VoiceInkModeStorage.loadModes(from: defaults).first

            XCTAssertEqual(loadedMode?.id, staleMode.id)
            XCTAssertEqual(loadedMode?.transcriptionModel, VoiceInkProviderKind.deepgram.defaultModel(for: .transcription))
            XCTAssertEqual(loadedMode?.postProcessingModel, VoiceInkProviderKind.gemini.defaultModel(for: .postProcessing))
        }
    }

    func testModeStorageMigratesLegacyVoiceInkProvidersWithoutDroppingModeList() {
        withIsolatedDefaults { defaults in
            let legacyModeId = UUID(uuidString: "E9A2F4E2-6B2F-4E9D-A631-0D4640D74F3A")!
            let cloudModeId = UUID(uuidString: "C3E1F5D0-539B-4D1B-9F7F-48989AF59056")!
            let groqDefaultModel = VoiceInkAIModelCatalog.defaultModel(for: .groq)
            let json = """
            [
              {
                "id": "\(legacyModeId.uuidString)",
                "name": "Legacy VoiceInk",
                "transcriptionProvider": "VoiceInk",
                "transcriptionModel": "whisper-large-v3",
                "isPostProcessingEnabled": true,
                "postProcessingProvider": "voiceInk",
                "postProcessingModel": "llama-3.1-8b-instant",
                "promptTemplate": {
                  "type": "Summary",
                  "customPrompt": ""
                }
              },
              {
                "id": "\(cloudModeId.uuidString)",
                "name": "Cloud",
                "transcriptionProvider": "Deepgram",
                "transcriptionModel": "nova-3",
                "isPostProcessingEnabled": false,
                "postProcessingProvider": "Groq",
                "postProcessingModel": "\(groqDefaultModel)",
                "promptTemplate": {
                  "type": "Summary",
                  "customPrompt": ""
                }
              }
            ]
            """

            defaults.set(Data(json.utf8), forKey: VoiceInkUserDefaultsKey.modes)

            let modes = VoiceInkModeStorage.loadModes(from: defaults)

            XCTAssertEqual(modes.map(\.id), [legacyModeId, cloudModeId])
            XCTAssertEqual(modes.first?.name, "Legacy VoiceInk")
            XCTAssertEqual(modes.first?.transcriptionProvider, .localWhisper)
            XCTAssertEqual(modes.first?.transcriptionModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
            XCTAssertEqual(modes.first?.isPostProcessingEnabled, false)
            XCTAssertEqual(modes.first?.postProcessingProvider, .groq)
            XCTAssertEqual(modes.first?.postProcessingModel, groqDefaultModel)
            XCTAssertEqual(modes.last?.transcriptionProvider, .deepgram)
            XCTAssertEqual(modes.last?.postProcessingProvider, .groq)
        }
    }

    func testModeStorageFallsBackToEmptyModesForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.modes)
            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
        }
    }

    func testModeStorageClearRemovesModesAndSelectedModeId() {
        withIsolatedDefaults { defaults in
            let mode = Mode.defaultLocalWhisper()
            VoiceInkModeStorage.saveModes([mode], to: defaults)
            VoiceInkModeStorage.saveSelectedModeId(mode.id, to: defaults)

            VoiceInkModeStorage.clear(from: defaults)

            XCTAssertTrue(VoiceInkModeStorage.loadModes(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkModeStorage.loadSelectedModeId(from: defaults))
        }
    }

    func testPowerModeConfigurationPreferenceRoundTripsConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let firstConfig = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                appConfigs: [
                    VoiceInkPowerModeAppConfig(bundleIdentifier: "com.example.App", appName: "Example")
                ],
                urlConfigs: [
                    VoiceInkPowerModeURLConfig(url: "example.com")
                ],
                isAIEnhancementEnabled: true,
                selectedPrompt: "prompt-id",
                selectedTranscriptionModelName: "ggml-base",
                selectedLanguage: "en",
                useScreenCapture: true,
                isTextFormattingEnabled: true,
                punctuationCleanupMode: .removeTrailingPeriod,
                lowercaseTranscription: true,
                selectedAIProvider: "openai",
                selectedAIModel: "gpt-4o",
                autoSendKey: .commandEnter,
                isDefault: true
            )
            let secondConfig = PowerModeConfig(
                name: "Notes",
                emoji: "N",
                isAIEnhancementEnabled: false
            )

            VoiceInkPowerModeConfigurationPreference.saveConfigurations([firstConfig, secondConfig], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(secondConfig.id, to: defaults)

            let loadedConfigs = VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults)
            XCTAssertEqual(loadedConfigs.map(\.id), [firstConfig.id, secondConfig.id])
            XCTAssertEqual(loadedConfigs.map(\.name), ["Writing", "Notes"])
            XCTAssertEqual(loadedConfigs.first?.appConfigs?.first?.bundleIdentifier, "com.example.App")
            XCTAssertEqual(loadedConfigs.first?.urlConfigs?.first?.url, "example.com")
            XCTAssertEqual(loadedConfigs.first?.autoSendKey, .commandEnter)
            XCTAssertEqual(
                VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults),
                secondConfig.id
            )
            XCTAssertTrue(defaults.data(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations) != nil)
            XCTAssertEqual(
                defaults.string(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId),
                secondConfig.id.uuidString
            )
        }
    }

    func testPowerModeConfigurationPreferenceFallsBackForMissingInvalidAndBlankActiveId() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.powerModeConfigurations)
            defaults.set("not-a-uuid", forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)

            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))

            defaults.set("", forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
        }
    }

    func testPowerModeConfigurationPreferenceClearRemovesConfigurationsAndActiveConfigurationId() {
        withIsolatedDefaults { defaults in
            let config = PowerModeConfig(
                name: "Writing",
                emoji: "W",
                isAIEnhancementEnabled: false
            )
            VoiceInkPowerModeConfigurationPreference.saveConfigurations([config], to: defaults)
            VoiceInkPowerModeConfigurationPreference.saveActiveConfigurationId(config.id, to: defaults)

            VoiceInkPowerModeConfigurationPreference.clear(from: defaults)

            XCTAssertTrue(VoiceInkPowerModeConfigurationPreference.loadConfigurations(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkPowerModeConfigurationPreference.loadActiveConfigurationId(from: defaults))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.powerModeConfigurations))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.activePowerModeConfigurationId))
        }
    }

    func testPowerModePreferenceRegisteredDefaultsPreserveUIFlagInitializationPolicy() {
        XCTAssertNil(VoiceInkPowerModePreference.registeredDefaults[VoiceInkUserDefaultsKey.powerModeUIFlag])
        XCTAssertEqual(
            VoiceInkPowerModePreference.registeredDefaults[VoiceInkUserDefaultsKey.powerModePersistConfig] as? Bool,
            false
        )
    }

    func testPowerModePreferenceReadsAndSavesFlags() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertFalse(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))

            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)
            VoiceInkPowerModePreference.saveShouldPersistConfiguredPreferences(true, to: defaults)

            XCTAssertTrue(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
            XCTAssertTrue(VoiceInkPowerModePreference.shouldPersistConfiguredPreferences(from: defaults))
        }
    }

    func testPowerModePreferenceInitializesUIFlagFromEnabledConfigurationsWhenMissing() {
        withIsolatedDefaults { defaults in
            VoiceInkPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertTrue(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceInitializeUIFlagDoesNotOverwriteStoredValue() {
        withIsolatedDefaults { defaults in
            VoiceInkPowerModePreference.saveIsUIEnabled(false, to: defaults)

            VoiceInkPowerModePreference.initializeUIFlagIfNeeded(
                hasEnabledConfigurations: true,
                in: defaults
            )

            XCTAssertFalse(VoiceInkPowerModePreference.isUIEnabled(from: defaults))
        }
    }

    func testPowerModePreferenceShortcutEligibilityRequiresUIAndEnabledConfigurations() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))

            VoiceInkPowerModePreference.saveIsUIEnabled(true, to: defaults)

            XCTAssertFalse(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: false, from: defaults))
            XCTAssertTrue(VoiceInkPowerModePreference.canUseShortcuts(hasEnabledConfigurations: true, from: defaults))
        }
    }

    func testPowerModeSessionPreferenceRoundTripsActiveSession() throws {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let originalState = VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: true,
            useScreenCaptureContext: false,
            selectedPromptId: "prompt-id",
            selectedAIProvider: "openai",
            selectedAIModel: "gpt-4o",
            selectedLanguage: "en",
            transcriptionModelName: "ggml-base",
            isTextFormattingEnabled: true,
            punctuationCleanupMode: .removeAll,
            removePunctuation: true,
            lowercaseTranscription: false
        )
        let session = VoiceInkPowerModeSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            originalState: originalState
        )

        try VoiceInkPowerModeSessionPreference.saveActiveSession(session, to: defaults)

        let loadedSession = try VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults)
        XCTAssertEqual(loadedSession?.id, session.id)
        XCTAssertEqual(loadedSession?.startTime, session.startTime)
        XCTAssertEqual(loadedSession?.originalState, originalState)
        XCTAssertTrue(defaults.data(forKey: VoiceInkUserDefaultsKey.activePowerModeSession) != nil)
    }

    func testPowerModeSessionPreferenceThrowsForInvalidActiveSessionData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.activePowerModeSession)

            var didThrow = false
            do {
                _ = try VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults)
            } catch {
                didThrow = true
            }

            XCTAssertTrue(didThrow)
        }
    }

    func testPowerModeSessionPreferenceClearRemovesActiveSession() {
        withIsolatedDefaults { defaults in
            let session = VoiceInkPowerModeSession(
                id: UUID(),
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                originalState: VoiceInkPowerModeApplicationState(
                    isEnhancementEnabled: false,
                    useScreenCaptureContext: true
                )
            )
            try? VoiceInkPowerModeSessionPreference.saveActiveSession(session, to: defaults)

            VoiceInkPowerModeSessionPreference.clear(from: defaults)

            XCTAssertNil(try? VoiceInkPowerModeSessionPreference.loadActiveSession(from: defaults))
            XCTAssertNil(defaults.object(forKey: VoiceInkUserDefaultsKey.activePowerModeSession))
        }
    }

    func testCustomPromptStorageRoundTripsPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let customPrompt = VoiceInkCustomPrompt(
                title: "Custom",
                promptText: "Keep terms exact.",
                triggerWords: ["terms"]
            )
            let assistantPrompt = VoiceInkCustomPrompt(predefinedPrompt: VoiceInkPredefinedPrompts.all[1])

            VoiceInkCustomPromptStorage.savePrompts([customPrompt, assistantPrompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(assistantPrompt.id, to: defaults)

            let loadedPrompts = VoiceInkCustomPromptStorage.loadPrompts(from: defaults)
            XCTAssertEqual(loadedPrompts.map(\.id), [customPrompt.id, assistantPrompt.id])
            XCTAssertEqual(loadedPrompts.map(\.title), ["Custom", "Assistant"])
            XCTAssertEqual(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults), assistantPrompt.id)
        }
    }

    func testCustomPromptStorageFallsBackToEmptyPromptsForMissingOrInvalidData() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)

            defaults.set(Data("bad".utf8), forKey: VoiceInkUserDefaultsKey.customPrompts)
            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
        }
    }

    func testCustomPromptStorageClearRemovesPromptsAndSelectedPromptId() {
        withIsolatedDefaults { defaults in
            let prompt = VoiceInkCustomPrompt(title: "Prompt", promptText: "Text")
            VoiceInkCustomPromptStorage.savePrompts([prompt], to: defaults)
            VoiceInkCustomPromptStorage.saveSelectedPromptId(prompt.id, to: defaults)

            VoiceInkCustomPromptStorage.clear(from: defaults)

            XCTAssertTrue(VoiceInkCustomPromptStorage.loadPrompts(from: defaults).isEmpty)
            XCTAssertNil(VoiceInkCustomPromptStorage.loadSelectedPromptId(from: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateUsesProviderKeys() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)

            XCTAssertTrue(VoiceInkProviderAPIKeyVerificationState.isVerified(.groq, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "groqKeyVerified") as? Bool, true)
        }
    }

    func testProviderAPIKeyVerificationStatePersistsFalseFlag() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(false, for: .deepgram, in: defaults)

            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))
            XCTAssertEqual(defaults.object(forKey: "deepgramKeyVerified") as? Bool, false)
        }
    }

    func testProviderAPIKeyVerificationStateFiltersVerifiedUserKeyProviders() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .localWhisper, in: defaults)

            XCTAssertEqual(
                VoiceInkProviderAPIKeyVerificationState.verifiedProviders(from: [.groq, .deepgram, .localWhisper], in: defaults),
                [.groq]
            )
            XCTAssertFalse(VoiceInkProviderAPIKeyVerificationState.isVerified(.localWhisper, in: defaults))
        }
    }

    func testProviderAPIKeyVerificationStateClearsSingleAndAllProviders() {
        withIsolatedDefaults { defaults in
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .groq, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.setVerified(true, for: .deepgram, in: defaults)
            VoiceInkProviderAPIKeyVerificationState.clear(for: .groq, in: defaults)

            XCTAssertNil(defaults.object(forKey: "groqKeyVerified"))
            XCTAssertTrue(VoiceInkProviderAPIKeyVerificationState.isVerified(.deepgram, in: defaults))

            VoiceInkProviderAPIKeyVerificationState.clearAll(from: [.groq, .deepgram], in: defaults)

            XCTAssertNil(defaults.object(forKey: "deepgramKeyVerified"))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.UserDefaultsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
