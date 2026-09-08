import Foundation

public struct VoiceInkLanguageOption: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum VoiceInkTranscriptionLanguagePresentation {
    public static let sectionTitle = "Transcription Language"
    public static let pickerTitle = "Language"
    public static let menuPickerTitle = "Select Language"
    public static let autoDetectedLabel = "Language: Autodetected"
    public static let autoDetectedDescription = "The transcription language is automatically detected by the model."
    public static let multilingualDescription = "This model supports multiple languages. Select a specific language or auto-detect(if available)"
    public static let englishOnlyLabel = "Language: English"
    public static let englishOnlyDescription = "This is an English-optimized model and only supports English transcription."
    public static let englishOnlyMenuLabel = "Language: English (only)"

    public static func menuLabel(
        selectedLanguage: String,
        languages: [String: String]
    ) -> String {
        "\(pickerTitle): \(VoiceInkLanguageCatalog.displayName(for: selectedLanguage, in: languages))"
    }
}

public enum VoiceInkTranscriptionLanguageSource: Equatable, Sendable {
    case whisper
    case nativeApple
    case fluidAudio
    case qwen
    case provider(VoiceInkTranscriptionModelProvider)
    case all
}

enum VoiceInkTranscriptionLanguageSelectionControl: Equatable, Sendable {
    case disabledAutodetect
    case picker
    case hiddenDefault
}

public struct VoiceInkTranscriptionLanguageSelectionFacts: Equatable, Sendable {
    public var source: VoiceInkTranscriptionLanguageSource
    public var isMultilingual: Bool
    public var languageOptions: [String: String]

    var control: VoiceInkTranscriptionLanguageSelectionControl {
        if source.disablesTranscriptionLanguageSelection {
            return .disabledAutodetect
        }

        return isMultilingual ? .picker : .hiddenDefault
    }

    public var shouldShowDisabledAutodetectControl: Bool {
        control == .disabledAutodetect
    }

    public var shouldShowPicker: Bool {
        control == .picker
    }

    public var shouldShowDefaultLanguageOnly: Bool {
        control == .hiddenDefault
    }

    public var showsNativeAppleAssetControl: Bool {
        source.showsNativeAppleAssetControl
    }

    public init(
        source: VoiceInkTranscriptionLanguageSource,
        isMultilingual: Bool,
        languageOptions: [String: String]
    ) {
        self.source = source
        self.isMultilingual = isMultilingual
        self.languageOptions = languageOptions
    }

    public func compatibleLanguage(_ language: String?) -> String {
        VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            languages: languageOptions,
            prefersNativeAppleEnglish: source.prefersNativeAppleEnglishFallback
        )
    }

}

public enum VoiceInkNativeAppleLanguageAssetState: Equatable, Sendable {
    case checking
    case downloaded
    case needsDownload
    case downloading
    case notSupported
    case assetManagementUnavailable
    case failed(String)
}

public enum VoiceInkNativeAppleLanguageAssetDisplay: Equatable, Sendable {
    case hidden
    case progress
    case actionButton(systemImageName: String)
    case statusIcon(systemImageName: String)
}

public struct VoiceInkNativeAppleLanguageAssetPresentation: Equatable, Sendable {
    public let display: VoiceInkNativeAppleLanguageAssetDisplay
    public let helpText: String?
    public let accessibilityLabel: String?

    public init(
        display: VoiceInkNativeAppleLanguageAssetDisplay,
        helpText: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.display = display
        self.helpText = helpText
        self.accessibilityLabel = accessibilityLabel
    }

    public static func presentation(for state: VoiceInkNativeAppleLanguageAssetState) -> Self {
        switch state {
        case .checking:
            return Self(
                display: .progress,
                helpText: "Checking Apple Speech language download status."
            )
        case .downloaded:
            return Self(display: .hidden)
        case .needsDownload:
            return Self(
                display: .actionButton(systemImageName: "arrow.down.circle.fill"),
                helpText: "Download this Apple Speech language before transcribing.",
                accessibilityLabel: "Download Apple Speech language"
            )
        case .downloading:
            return Self(
                display: .progress,
                helpText: "Downloading Apple Speech language."
            )
        case .notSupported:
            return Self(
                display: .statusIcon(systemImageName: "exclamationmark.triangle"),
                helpText: "This language is not supported by Apple Speech."
            )
        case .assetManagementUnavailable:
            return Self(
                display: .statusIcon(systemImageName: "exclamationmark.triangle"),
                helpText: "Apple Speech asset management is not available on this system."
            )
        case .failed(let message):
            return Self(
                display: .actionButton(systemImageName: "arrow.clockwise.circle.fill"),
                helpText: "Retry downloading this Apple Speech language. \(message)",
                accessibilityLabel: "Retry Apple Speech language download"
            )
        }
    }
}

public enum VoiceInkNativeAppleLanguageAssetDiagnostics {
    public static func downloadUnavailableRequiresMacOS26Message(localeIdentifier: String) -> String {
        "Apple Speech asset download unavailable for '\(localeIdentifier)': requires macOS 26 or later."
    }

    public static func reservationReturnedFalseMessage(normalizedIdentifier: String) -> String {
        "Apple Speech asset reservation returned false for '\(normalizedIdentifier)'. Continuing to request installation after confirming the asset still needs download."
    }

    public static func downloadFailedMessage(localeIdentifier: String, errorDescription: String) -> String {
        "Apple Speech asset download failed for '\(localeIdentifier)': \(errorDescription)."
    }

    public static func downloadUnavailableFeatureFlagMessage(localeIdentifier: String) -> String {
        "Apple Speech asset download unavailable for '\(localeIdentifier)': ENABLE_NATIVE_SPEECH_ANALYZER is not active."
    }
}

extension VoiceInkTranscriptionLanguageSource {
    var disablesTranscriptionLanguageSelection: Bool {
        self == .provider(.gemini)
    }

    var prefersNativeAppleEnglishFallback: Bool {
        self == .nativeApple
    }

    var loadsLocalWhisperModelResource: Bool {
        self == .whisper
    }

    var showsNativeAppleAssetControl: Bool {
        self == .nativeApple
    }
}

public enum VoiceInkLanguageCatalog {
    public static let autoDetectCode = "auto"
    public static let autoDetectName = "Auto-detect"

    private static let whisperLanguageCodes: Set<String> = [
        "auto",
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
        "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
        "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
        "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
        "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
        "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh"
    ]

    private static let fluidAudioLanguageCodes: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr",
        "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro",
        "ru", "sk", "sl", "sv", "uk"
    ]

    // Apple Native Speech languages in BCP-47 format.
    // Queried from SpeechTranscriber.supportedLocales on macOS 26.4.
    public static let nativeApple: [String: String] = [
        "de-DE": "German (Germany)",
        "de-AT": "German (Austria)",
        "de-CH": "German (Switzerland)",
        "en-AU": "English (Australia)",
        "en-CA": "English (Canada)",
        "en-GB": "English (United Kingdom)",
        "en-IE": "English (Ireland)",
        "en-IN": "English (India)",
        "en-NZ": "English (New Zealand)",
        "en-SG": "English (Singapore)",
        "en-US": "English (United States)",
        "en-ZA": "English (South Africa)",
        "es-CL": "Spanish (Chile)",
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "es-US": "Spanish (United States)",
        "fr-BE": "French (Belgium)",
        "fr-CA": "French (Canada)",
        "fr-CH": "French (Switzerland)",
        "fr-FR": "French (France)",
        "it-CH": "Italian (Switzerland)",
        "it-IT": "Italian (Italy)",
        "ja-JP": "Japanese (Japan)",
        "ko-KR": "Korean (South Korea)",
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        "yue-CN": "Cantonese (China mainland)",
        "zh-CN": "Chinese (China mainland)",
        "zh-HK": "Chinese (Hong Kong)",
        "zh-TW": "Chinese (Taiwan)"
    ]

    public static func nativeAppleDisplayName(
        for localeIdentifier: String,
        locale: Locale = .current
    ) -> String {
        nativeApple[localeIdentifier]
            ?? locale.localizedString(forIdentifier: localeIdentifier)
            ?? localeIdentifier
    }

    public static let all: [String: String] = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "am": "Amharic",
        "ar": "Arabic",
        "as": "Assamese",
        "az": "Azerbaijani",
        "ba": "Bashkir",
        "be": "Belarusian",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "bo": "Tibetan",
        "br": "Breton",
        "bs": "Bosnian",
        "ca": "Catalan",
        "cs": "Czech",
        "cy": "Welsh",
        "da": "Danish",
        "de": "German",
        "de_ch": "Swiss German",
        "el": "Greek",
        "en": "English",
        "en_au": "Australian English",
        "en_uk": "British English",
        "en_us": "US English",
        "es": "Spanish",
        "et": "Estonian",
        "eu": "Basque",
        "fa": "Persian",
        "fi": "Finnish",
        "fil": "Filipino",
        "fo": "Faroese",
        "fr": "French",
        "ga": "Irish",
        "gl": "Galician",
        "gu": "Gujarati",
        "ha": "Hausa",
        "haw": "Hawaiian",
        "he": "Hebrew",
        "hi": "Hindi",
        "hr": "Croatian",
        "ht": "Haitian Creole",
        "hu": "Hungarian",
        "hy": "Armenian",
        "id": "Indonesian",
        "ig": "Igbo",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "jw": "Javanese",
        "ka": "Georgian",
        "kk": "Kazakh",
        "km": "Khmer",
        "kn": "Kannada",
        "ko": "Korean",
        "ku": "Kurdish",
        "ky": "Kyrgyz",
        "la": "Latin",
        "lb": "Luxembourgish",
        "ln": "Lingala",
        "lo": "Lao",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "mg": "Malagasy",
        "mi": "Maori",
        "mk": "Macedonian",
        "ml": "Malayalam",
        "mn": "Mongolian",
        "mr": "Marathi",
        "ms": "Malay",
        "mt": "Maltese",
        "my": "Myanmar",
        "ne": "Nepali",
        "nl": "Dutch",
        "nn": "Norwegian Nynorsk",
        "no": "Norwegian",
        "oc": "Occitan",
        "or": "Odia",
        "pa": "Punjabi",
        "pl": "Polish",
        "ps": "Pashto",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sa": "Sanskrit",
        "sd": "Sindhi",
        "si": "Sinhala",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sn": "Shona",
        "so": "Somali",
        "sq": "Albanian",
        "sr": "Serbian",
        "su": "Sundanese",
        "sv": "Swedish",
        "sw": "Swahili",
        "ta": "Tamil",
        "te": "Telugu",
        "tg": "Tajik",
        "th": "Thai",
        "tk": "Turkmen",
        "tl": "Tagalog",
        "tr": "Turkish",
        "tt": "Tatar",
        "uk": "Ukrainian",
        "ur": "Urdu",
        "uz": "Uzbek",
        "vi": "Vietnamese",
        "wo": "Wolof",
        "xh": "Xhosa",
        "yi": "Yiddish",
        "yo": "Yoruba",
        "yue": "Cantonese",
        "zh": "Chinese",
        "zu": "Zulu"
    ]

    public static let englishOnly = ["en": "English"]

    static func languages<S: Sequence>(matching codes: S) -> [String: String] where S.Element == String {
        let codeSet = Set(codes)
        return all.filter { codeSet.contains($0.key) }
    }

    public static func whisperLanguages(isMultilingual: Bool = true) -> [String: String] {
        isMultilingual ? languages(matching: whisperLanguageCodes) : englishOnly
    }

    public static func fluidAudioLanguages(isMultilingual: Bool = true) -> [String: String] {
        guard isMultilingual else {
            return englishOnly
        }

        var filtered = languages(matching: fluidAudioLanguageCodes)
        filtered[autoDetectCode] = autoDetectName
        return filtered
    }

    public static func languages(
        for provider: VoiceInkTranscriptionModelProvider,
        isMultilingual: Bool = true
    ) -> [String: String] {
        guard isMultilingual else {
            return englishOnly
        }

        if provider == .local {
            return whisperLanguages()
        }

        if provider == .nativeApple {
            return nativeApple
        }

        guard let codes = provider.languageCodes else {
            return all
        }

        var filtered = languages(matching: codes)
        if provider.includesAutoDetect {
            filtered[autoDetectCode] = autoDetectName
        }
        return filtered
    }

    public static func languages(
        for provider: VoiceInkProviderKind,
        isMultilingual: Bool = true
    ) -> [String: String] {
        guard isMultilingual else {
            return englishOnly
        }

        if provider == .localFluidAudio {
            return fluidAudioLanguages()
        }

        guard let modelProvider = provider.transcriptionModelProvider else {
            return all
        }
        return languages(for: modelProvider)
    }

    public static func sortedOptions(_ languages: [String: String]) -> [VoiceInkLanguageOption] {
        languages
            .map { VoiceInkLanguageOption(code: $0.key, name: $0.value) }
            .sorted { lhs, rhs in
                if lhs.code == autoDetectCode { return true }
                if rhs.code == autoDetectCode { return false }

                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }

                return lhs.code.localizedCaseInsensitiveCompare(rhs.code) == .orderedAscending
            }
    }

    public static func displayName(
        for languageCode: String,
        in languages: [String: String],
        fallback: String = "Unknown"
    ) -> String {
        languages[languageCode] ?? fallback
    }
}

public enum VoiceInkTranscriptionLanguageSupport {
    private static let assemblyAIRealtimeLanguageCodes = ["en", "es", "de", "fr", "pt", "it"]

    private static let assemblyAIBatchLanguageCodes = [
        "en", "en_au", "en_uk", "en_us", "es", "fr", "de", "it", "pt", "nl",
        "hi", "ja", "zh", "fi", "ko", "pl", "ru", "tr", "uk", "vi", "af",
        "sq", "am", "ar", "hy", "as", "az", "ba", "eu", "be", "bn", "bs",
        "br", "bg", "my", "ca", "hr", "cs", "da", "et", "fo", "gl", "ka",
        "el", "gu", "ht", "ha", "haw", "he", "hu", "is", "id", "jw", "kn",
        "kk", "km", "lo", "la", "lv", "ln", "lt", "lb", "mk", "mg", "ms",
        "ml", "mt", "mi", "mr", "mn", "ne", "no", "nn", "oc", "pa", "ps",
        "fa", "ro", "sa", "sr", "sn", "sd", "si", "sk", "sl", "so", "su",
        "sw", "sv", "de_ch", "tl", "tg", "ta", "tt", "te", "th", "bo",
        "tk", "ur", "uz", "cy", "yi", "yo"
    ]

    public static func assemblyAILanguages(usesRealtime: Bool) -> [String: String] {
        let codes = usesRealtime ? assemblyAIRealtimeLanguageCodes : assemblyAIBatchLanguageCodes
        var filtered = VoiceInkLanguageCatalog.languages(matching: codes)
        filtered[VoiceInkLanguageCatalog.autoDetectCode] = VoiceInkLanguageCatalog.autoDetectName
        return filtered
    }

    public static func languages(
        for source: VoiceInkTranscriptionLanguageSource,
        isMultilingual: Bool = true,
        assemblyAIUsesRealtime: Bool = false
    ) -> [String: String] {
        guard isMultilingual else {
            return VoiceInkLanguageCatalog.englishOnly
        }

        switch source {
        case .whisper:
            return VoiceInkLanguageCatalog.whisperLanguages()
        case .nativeApple:
            return VoiceInkLanguageCatalog.nativeApple
        case .fluidAudio:
            return VoiceInkLanguageCatalog.fluidAudioLanguages()
        case .qwen:
            return ["auto": "Auto-detect", "en": "English", "zh": "Chinese (Traditional output)"]
        case .provider(.assemblyAI):
            return assemblyAILanguages(usesRealtime: assemblyAIUsesRealtime)
        case .provider(let provider):
            return VoiceInkLanguageCatalog.languages(for: provider)
        case .all:
            return VoiceInkLanguageCatalog.all
        }
    }

    public static func validLanguageOrFallback(
        _ language: String?,
        languages: [String: String],
        prefersNativeAppleEnglish: Bool = false
    ) -> String {
        if let language, languages[language] != nil {
            return language
        }

        if prefersNativeAppleEnglish, languages["en-US"] != nil {
            return "en-US"
        }

        if languages[VoiceInkLanguageCatalog.autoDetectCode] != nil {
            return VoiceInkLanguageCatalog.autoDetectCode
        }

        if languages["en"] != nil {
            return "en"
        }

        return VoiceInkLanguageCatalog.sortedOptions(languages).first?.code ?? "en"
    }

    public static func validLanguageOrFallback(
        _ language: String?,
        source: VoiceInkTranscriptionLanguageSource,
        isMultilingual: Bool = true,
        assemblyAIUsesRealtime: Bool = false
    ) -> String {
        validLanguageOrFallback(
            language,
            languages: languages(
                for: source,
                isMultilingual: isMultilingual,
                assemblyAIUsesRealtime: assemblyAIUsesRealtime
            ),
            prefersNativeAppleEnglish: source == .nativeApple
        )
    }

    public static func validLanguageOrFallback(
        _ language: String?,
        provider: VoiceInkProviderKind,
        isMultilingual: Bool = true
    ) -> String {
        validLanguageOrFallback(
            language,
            languages: VoiceInkLanguageCatalog.languages(
                for: provider,
                isMultilingual: isMultilingual
            )
        )
    }

    public static func requestLanguage(_ language: String?) -> String? {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty,
              language != VoiceInkLanguageCatalog.autoDetectCode else {
            return nil
        }

        return language
    }
}
