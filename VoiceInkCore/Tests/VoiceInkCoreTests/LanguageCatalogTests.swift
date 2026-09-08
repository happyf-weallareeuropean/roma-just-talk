import Foundation
@testable import VoiceInkCore

final class LanguageCatalogTests: XCTestCase {
    func testLanguageCatalogPreservesSharedNames() {
        XCTAssertEqual(VoiceInkLanguageCatalog.all["auto"], "Auto-detect")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["en_uk"], "British English")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["de_ch"], "Swiss German")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["yue"], "Cantonese")
        XCTAssertEqual(VoiceInkLanguageCatalog.all["zu"], "Zulu")
    }

    func testWhisperLanguagesPreserveMacOSWhisperSet() {
        let languages = VoiceInkLanguageCatalog.whisperLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["yue"], "Cantonese")
        XCTAssertEqual(languages["zh"], "Chinese")
        XCTAssertNil(languages["zu"])
        XCTAssertEqual(VoiceInkLanguageCatalog.whisperLanguages(isMultilingual: false), ["en": "English"])
    }

    func testNativeAppleLanguagesUseBCP47Identifiers() {
        XCTAssertEqual(VoiceInkLanguageCatalog.nativeApple["en-US"], "English (United States)")
        XCTAssertEqual(VoiceInkLanguageCatalog.nativeApple["zh-TW"], "Chinese (Taiwan)")
        XCTAssertNil(VoiceInkLanguageCatalog.nativeApple["en"])
    }

    func testNativeAppleDisplayNameUsesCatalogThenLocalizedFallback() {
        let locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(
            VoiceInkLanguageCatalog.nativeAppleDisplayName(for: "en-US", locale: locale),
            "English (United States)"
        )
        XCTAssertEqual(
            VoiceInkLanguageCatalog.nativeAppleDisplayName(for: "es-AR", locale: locale),
            "Spanish (Argentina)"
        )
        XCTAssertEqual(
            VoiceInkLanguageCatalog.nativeAppleDisplayName(for: "zz-ZZ", locale: locale),
            "zz-ZZ"
        )
    }

    func testFluidAudioLanguagesPreserveParakeetPolicies() {
        let languages = VoiceInkLanguageCatalog.fluidAudioLanguages()

        XCTAssertEqual(languages["auto"], "Auto-detect")
        XCTAssertEqual(languages["bg"], "Bulgarian")
        XCTAssertEqual(languages["uk"], "Ukrainian")
        XCTAssertNil(languages["ja"])
        XCTAssertEqual(VoiceInkLanguageCatalog.fluidAudioLanguages(isMultilingual: false), ["en": "English"])
    }

    func testProviderLanguagesPreserveCloudProviderPolicies() {
        let groq = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.groq)
        XCTAssertEqual(groq["auto"], "Auto-detect")
        XCTAssertEqual(groq["zu"], "Zulu")

        let deepgram = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.deepgram)
        XCTAssertEqual(deepgram["auto"], "Auto-detect")
        XCTAssertEqual(deepgram["ar"], "Arabic")
        XCTAssertNil(deepgram["zu"])

        let cartesia = VoiceInkLanguageCatalog.languages(for: VoiceInkTranscriptionModelProvider.cartesia)
        XCTAssertNil(cartesia["auto"])
        XCTAssertEqual(cartesia["zu"], "Zulu")
    }

    func testProviderKindLanguagesExposeLocalWhisperPolicy() {
        let local = VoiceInkLanguageCatalog.languages(for: VoiceInkProviderKind.localWhisper)

        XCTAssertEqual(local["auto"], "Auto-detect")
        XCTAssertEqual(local["yue"], "Cantonese")
        XCTAssertNil(local["zu"])
    }

    func testAssemblyAILanguagesPreserveRealtimeAndBatchPolicies() {
        let realtime = VoiceInkTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: true)
        XCTAssertEqual(realtime["auto"], "Auto-detect")
        XCTAssertEqual(realtime["en"], "English")
        XCTAssertNil(realtime["en_uk"])

        let batch = VoiceInkTranscriptionLanguageSupport.assemblyAILanguages(usesRealtime: false)
        XCTAssertEqual(batch["auto"], "Auto-detect")
        XCTAssertEqual(batch["en_uk"], "British English")
        XCTAssertEqual(batch["de_ch"], "Swiss German")
    }

    func testTranscriptionLanguageSourceRoutesMacOSModelProviderPolicies() {
        let whisper = VoiceInkTranscriptionLanguageSupport.languages(for: .whisper)
        XCTAssertEqual(whisper["auto"], "Auto-detect")
        XCTAssertEqual(whisper["yue"], "Cantonese")
        XCTAssertNil(whisper["zu"])

        let nativeApple = VoiceInkTranscriptionLanguageSupport.languages(for: .nativeApple)
        XCTAssertEqual(nativeApple["en-US"], "English (United States)")
        XCTAssertNil(nativeApple["auto"])

        let fluidAudio = VoiceInkTranscriptionLanguageSupport.languages(for: .fluidAudio)
        XCTAssertEqual(fluidAudio["auto"], "Auto-detect")
        XCTAssertEqual(fluidAudio["bg"], "Bulgarian")
        XCTAssertNil(fluidAudio["ja"])

        let deepgram = VoiceInkTranscriptionLanguageSupport.languages(for: .provider(.deepgram))
        XCTAssertEqual(deepgram["auto"], "Auto-detect")
        XCTAssertEqual(deepgram["ar"], "Arabic")
        XCTAssertNil(deepgram["zu"])

        let all = VoiceInkTranscriptionLanguageSupport.languages(for: .all)
        XCTAssertEqual(all["auto"], "Auto-detect")
        XCTAssertEqual(all["zu"], "Zulu")

        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.languages(for: .nativeApple, isMultilingual: false),
            ["en": "English"]
        )
    }

    func testTranscriptionLanguageSourceRoutesAssemblyAIRealtimePolicy() {
        let realtime = VoiceInkTranscriptionLanguageSupport.languages(
            for: .provider(.assemblyAI),
            assemblyAIUsesRealtime: true
        )
        XCTAssertEqual(realtime["auto"], "Auto-detect")
        XCTAssertNil(realtime["en_uk"])

        let batch = VoiceInkTranscriptionLanguageSupport.languages(
            for: .provider(.assemblyAI),
            assemblyAIUsesRealtime: false
        )
        XCTAssertEqual(batch["auto"], "Auto-detect")
        XCTAssertEqual(batch["en_uk"], "British English")
    }

    func testValidLanguageOrFallbackPreservesMacOSFallbackOrder() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "es",
                languages: ["auto": "Auto-detect", "es": "Spanish"]
            ),
            "es"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: VoiceInkLanguageCatalog.nativeApple,
                prefersNativeAppleEnglish: true
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["auto": "Auto-detect", "en": "English"]
            ),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                languages: ["aa": "Aardvark", "zz": "Zed"]
            ),
            "aa"
        )
    }

    func testValidLanguageOrFallbackSupportsProviderKindLanguages() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .localWhisper
            ),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "zu",
                provider: .elevenLabs
            ),
            "zu"
        )
    }

    func testValidLanguageOrFallbackSupportsLanguageSourcePolicy() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "bad",
                source: .nativeApple
            ),
            "en-US"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "en_uk",
                source: .provider(.assemblyAI),
                assemblyAIUsesRealtime: true
            ),
            "auto"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                "en_uk",
                source: .provider(.assemblyAI),
                assemblyAIUsesRealtime: false
            ),
            "en_uk"
        )
    }

    func testTranscriptionLanguageSelectionFactsDeriveControlFromSource() {
        let geminiFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .provider(.gemini),
            isMultilingual: true,
            languageOptions: VoiceInkLanguageCatalog.all
        )
        let whisperFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .whisper,
            isMultilingual: true,
            languageOptions: VoiceInkLanguageCatalog.whisperLanguages()
        )
        let nativeAppleFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .nativeApple,
            isMultilingual: true,
            languageOptions: VoiceInkLanguageCatalog.nativeApple
        )
        let englishOnlyFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .provider(.groq),
            isMultilingual: false,
            languageOptions: VoiceInkLanguageCatalog.englishOnly
        )

        XCTAssertEqual(geminiFacts.control, .disabledAutodetect)
        XCTAssertTrue(geminiFacts.shouldShowDisabledAutodetectControl)
        XCTAssertFalse(geminiFacts.shouldShowPicker)
        XCTAssertFalse(geminiFacts.shouldShowDefaultLanguageOnly)
        XCTAssertFalse(geminiFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(whisperFacts.control, .picker)
        XCTAssertFalse(whisperFacts.shouldShowDisabledAutodetectControl)
        XCTAssertTrue(whisperFacts.shouldShowPicker)
        XCTAssertFalse(whisperFacts.shouldShowDefaultLanguageOnly)
        XCTAssertFalse(whisperFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(nativeAppleFacts.control, .picker)
        XCTAssertFalse(nativeAppleFacts.shouldShowDisabledAutodetectControl)
        XCTAssertTrue(nativeAppleFacts.shouldShowPicker)
        XCTAssertFalse(nativeAppleFacts.shouldShowDefaultLanguageOnly)
        XCTAssertTrue(nativeAppleFacts.showsNativeAppleAssetControl)
        XCTAssertEqual(englishOnlyFacts.control, .hiddenDefault)
        XCTAssertFalse(englishOnlyFacts.shouldShowDisabledAutodetectControl)
        XCTAssertFalse(englishOnlyFacts.shouldShowPicker)
        XCTAssertTrue(englishOnlyFacts.shouldShowDefaultLanguageOnly)
    }

    func testTranscriptionLanguageSelectionFactsUseSharedCompatibleFallback() {
        let nativeAppleFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .nativeApple,
            isMultilingual: true,
            languageOptions: VoiceInkLanguageCatalog.nativeApple
        )
        let whisperFacts = VoiceInkTranscriptionLanguageSelectionFacts(
            source: .whisper,
            isMultilingual: true,
            languageOptions: VoiceInkLanguageCatalog.whisperLanguages()
        )

        XCTAssertEqual(nativeAppleFacts.compatibleLanguage("bad"), "en-US")
        XCTAssertEqual(whisperFacts.compatibleLanguage("bad"), VoiceInkLanguageCatalog.autoDetectCode)
        XCTAssertEqual(whisperFacts.compatibleLanguage("fr"), "fr")
    }

    func testModelEffectiveLanguagePreservesAutoAcrossEnglishOnlyAndBilingualModels() {
        withLanguageDefaults { defaults in
            let english = languageFacts(.fluidAudio, multilingual: false)
            let bilingual = languageFacts(.qwen)
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.effectiveLanguage(for: english, from: defaults), "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: english, from: defaults), "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.effectiveLanguage(for: bilingual, from: defaults), "auto")
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults))
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "auto")
        }
    }

    func testModelEffectiveLanguagePreservesExplicitEnglishAndLaterUserChoices() {
        withLanguageDefaults { defaults in
            let bilingual = languageFacts(.qwen)
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("en", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults), "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "en")
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("zh", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.whisper, multilingual: false), from: defaults), "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults), "zh")
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: bilingual, from: defaults))
        }
    }

    func testModelEffectiveLanguageResolvesUnsupportedPreferencesWithoutPersistingFallbacks() {
        withLanguageDefaults { defaults in
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.qwen), from: defaults))
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults))
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("fr-FR", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.nativeApple), from: defaults), "fr-FR")
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.qwen), from: defaults))
            XCTAssertNil(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.provider(.groq)), from: defaults))
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "fr-FR")
            VoiceInkTranscriptionPromptPreference.savePrompt("Saved French prompt", to: defaults)
            VoiceInkLocalWhisperPromptCatalog.saveCustomPrompt("Edited auto prompt", for: "auto", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionPromptPreference.requestPrompt(
                forEffectiveLanguage: "auto", from: defaults
            ), "Edited auto prompt")
            XCTAssertEqual(VoiceInkTranscriptionPromptPreference.requestPrompt(
                forEffectiveLanguage: "fr-FR", from: defaults
            ), "Saved French prompt")
            XCTAssertEqual(VoiceInkTranscriptionPromptPreference.storedPrompt(from: defaults), "Saved French prompt")
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage("auto", to: defaults)
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.nativeApple), from: defaults), "en-US")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.requestLanguage(for: languageFacts(.provider(.cartesia)), from: defaults), "en")
            XCTAssertEqual(VoiceInkTranscriptionLanguagePreference.storedLanguage(from: defaults), "auto")
        }
    }

    private func languageFacts(_ source: VoiceInkTranscriptionLanguageSource, multilingual: Bool = true) -> VoiceInkTranscriptionLanguageSelectionFacts {
        VoiceInkTranscriptionLanguageSelectionFacts(source: source, isMultilingual: multilingual,
            languageOptions: VoiceInkTranscriptionLanguageSupport.languages(for: source, isMultilingual: multilingual))
    }

    private func withLanguageDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "LanguageCatalogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testNativeAppleLanguageAssetPresentationPreservesProgressAndIconStates() {
        let checking = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .checking)
        XCTAssertEqual(checking.display, .progress)
        XCTAssertEqual(checking.helpText, "Checking Apple Speech language download status.")
        XCTAssertNil(checking.accessibilityLabel)

        let downloaded = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .downloaded)
        XCTAssertEqual(downloaded.display, .hidden)
        XCTAssertNil(downloaded.helpText)
        XCTAssertNil(downloaded.accessibilityLabel)

        let downloading = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .downloading)
        XCTAssertEqual(downloading.display, .progress)
        XCTAssertEqual(downloading.helpText, "Downloading Apple Speech language.")
        XCTAssertNil(downloading.accessibilityLabel)

        let unsupported = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .notSupported)
        XCTAssertEqual(unsupported.display, .statusIcon(systemImageName: "exclamationmark.triangle"))
        XCTAssertEqual(unsupported.helpText, "This language is not supported by Apple Speech.")
        XCTAssertNil(unsupported.accessibilityLabel)

        let unavailable = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .assetManagementUnavailable)
        XCTAssertEqual(unavailable.display, .statusIcon(systemImageName: "exclamationmark.triangle"))
        XCTAssertEqual(unavailable.helpText, "Apple Speech asset management is not available on this system.")
        XCTAssertNil(unavailable.accessibilityLabel)
    }

    func testNativeAppleLanguageAssetPresentationPreservesActionStates() {
        let needsDownload = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .needsDownload)
        XCTAssertEqual(needsDownload.display, .actionButton(systemImageName: "arrow.down.circle.fill"))
        XCTAssertEqual(needsDownload.helpText, "Download this Apple Speech language before transcribing.")
        XCTAssertEqual(needsDownload.accessibilityLabel, "Download Apple Speech language")

        let failed = VoiceInkNativeAppleLanguageAssetPresentation.presentation(for: .failed("Network unavailable"))
        XCTAssertEqual(failed.display, .actionButton(systemImageName: "arrow.clockwise.circle.fill"))
        XCTAssertEqual(
            failed.helpText,
            "Retry downloading this Apple Speech language. Network unavailable"
        )
        XCTAssertEqual(failed.accessibilityLabel, "Retry Apple Speech language download")
    }

    func testSortedLanguageOptionsPutAutoDetectFirstThenSortByDisplayName() {
        XCTAssertEqual(
            VoiceInkLanguageCatalog.sortedOptions([
                "es": "Spanish",
                "auto": "Auto-detect",
                "de": "German",
                "en": "English"
            ]),
            [
                VoiceInkLanguageOption(code: "auto", name: "Auto-detect"),
                VoiceInkLanguageOption(code: "en", name: "English"),
                VoiceInkLanguageOption(code: "de", name: "German"),
                VoiceInkLanguageOption(code: "es", name: "Spanish")
            ]
        )
    }

    func testSortedLanguageOptionsUseCodeForStableTies() {
        XCTAssertEqual(
            VoiceInkLanguageCatalog.sortedOptions([
                "en_us": "English",
                "en": "English"
            ]),
            [
                VoiceInkLanguageOption(code: "en", name: "English"),
                VoiceInkLanguageOption(code: "en_us", name: "English")
            ]
        )
    }

    func testDisplayNameUsesLanguageMapThenFallback() {
        XCTAssertEqual(
            VoiceInkLanguageCatalog.displayName(
                for: "es",
                in: ["es": "Spanish", "en": "English"]
            ),
            "Spanish"
        )
        XCTAssertEqual(
            VoiceInkLanguageCatalog.displayName(
                for: "bad",
                in: ["es": "Spanish", "en": "English"]
            ),
            "Unknown"
        )
        XCTAssertEqual(
            VoiceInkLanguageCatalog.displayName(
                for: "bad",
                in: ["es": "Spanish"],
                fallback: "Unavailable"
            ),
            "Unavailable"
        )
    }

    func testTranscriptionLanguagePresentationBuildsMenuLabelWithSharedDisplayName() {
        XCTAssertEqual(
            VoiceInkTranscriptionLanguagePresentation.menuLabel(
                selectedLanguage: "es",
                languages: ["es": "Spanish", "en": "English"]
            ),
            "Language: Spanish"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionLanguagePresentation.menuLabel(
                selectedLanguage: "bad",
                languages: ["es": "Spanish", "en": "English"]
            ),
            "Language: Unknown"
        )
    }

    func testRequestLanguageStripsAutoAndBlankValues() {
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage(nil))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage(""))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage("  "))
        XCTAssertNil(VoiceInkTranscriptionLanguageSupport.requestLanguage("auto"))
        XCTAssertEqual(VoiceInkTranscriptionLanguageSupport.requestLanguage(" fr "), "fr")
    }
}
