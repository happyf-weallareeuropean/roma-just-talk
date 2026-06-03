import Foundation

public enum RomaPunctuationCleanupMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case keep = "keep"
    case removeAll = "removeAll"
    case removeTrailingPeriod = "removeTrailingPeriod"

    static let userDefaultsKey = "PunctuationCleanupMode"
    static let legacyRemovePunctuationKey = "RemovePunctuation"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keep:
            return "Keep"
        case .removeAll:
            return "Remove all"
        case .removeTrailingPeriod:
            return "Remove trailing period"
        }
    }

    public static func current(in defaults: UserDefaults = .standard) -> RomaPunctuationCleanupMode {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let mode = RomaPunctuationCleanupMode(rawValue: rawValue) {
            return mode
        }

        return defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep
    }

    public static func setCurrent(_ mode: RomaPunctuationCleanupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
        defaults.set(mode == .removeAll, forKey: legacyRemovePunctuationKey)
    }

    public static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           RomaPunctuationCleanupMode(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep, in: defaults)
    }
}

public enum RomaTranscriptionCleanupLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case raw = "raw"
    case light = "light"
    case polished = "polished"

    public var id: String { rawValue }
}

public struct RomaTranscriptionOutputFilter {
    public struct TextInsertionContext: Equatable, Hashable, Sendable {
        public let precedingText: String
        public let selectedText: String?

        public init(precedingText: String, selectedText: String? = nil) {
            self.precedingText = precedingText
            self.selectedText = selectedText
        }
    }

    public static let defaultFillerWords = [
        "uh", "um", "uhm", "umm", "uhh", "uhhh",
        "hmm", "hmmm", "hmmmm", "hm", "mmm", "mm", "mh",
        "eh", "ehh", "er", "erm", "ah", "ahh", "huh"
    ]

    private struct SpokenPunctuationCommand {
        let pattern: String
        let output: String
        let blockedPreviousWords: Set<String>
        let blockedNextWords: Set<String>

        init(
            pattern: String,
            output: String,
            blockedPreviousWords: Set<String> = [],
            blockedNextWords: Set<String> = []
        ) {
            self.pattern = pattern
            self.output = output
            self.blockedPreviousWords = blockedPreviousWords
            self.blockedNextWords = blockedNextWords
        }
    }

    private struct SpokenSymbolCommand {
        let pattern: String
        let output: String
        let blockedPreviousWords: Set<String>
        let blockedNextWords: Set<String>
        let requiresCompactContext: Bool

        init(
            pattern: String,
            output: String,
            blockedPreviousWords: Set<String> = [],
            blockedNextWords: Set<String> = [],
            requiresCompactContext: Bool = false
        ) {
            self.pattern = pattern
            self.output = output
            self.blockedPreviousWords = blockedPreviousWords
            self.blockedNextWords = blockedNextWords
            self.requiresCompactContext = requiresCompactContext
        }
    }

    private struct SpokenContractionCommand {
        let pattern: String
        let replacement: String
    }

    private enum SpokenCodeCaseStyle {
        case camel
        case snake
        case kebab
        case pascal
    }

    private struct SpokenCodeCaseCommand {
        let pattern: String
        let style: SpokenCodeCaseStyle
    }

    private enum SpokenMarkdownTaskState {
        case unchecked
        case checked
    }

    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
    private static let maxInsertionContextCharacters = 512
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")
    private static let removableTrailingFragmentPunctuation = CharacterSet(charactersIn: ".,;:…-–—")
    private static let removableTrailingSentenceFragmentPunctuation = CharacterSet(charactersIn: "!?")
    private static let removableTrailingSpacedFragmentSymbols = "/\\|"
    private static let nonSpeechBracketContents: Set<String> = [
        "applause", "background noise", "inaudible", "laughter", "laughs",
        "music", "noise", "silence", "sound", "static"
    ]
    private static let preservedRepeatedWords: Set<String> = [
        "ha", "haha", "no", "ok", "okay", "really", "so", "very", "yes"
    ]
    private static let preservedRepeatedClauses: Set<String> = [
        "i know", "new york", "you know"
    ]
    private static let allowedPreviousWordsForSpokenCodeCase: Set<String> = [
        "argument", "branch", "call", "called", "class", "constant", "enum",
        "field", "file", "folder", "function", "identifier", "key", "method",
        "named", "parameter", "property", "set", "struct", "to", "use",
        "using", "variable"
    ]
    private static let blockedFirstWordsForSpokenCodeCase: Set<String> = [
        "a", "an", "as", "for", "in", "is", "means", "style", "the", "with"
    ]
    private static let dateContextWords: Set<String> = [
        "after", "before", "by", "due", "from", "on", "since", "through", "until"
    ]
    private static let poundWeightContextWords: Set<String> = [
        "dropped", "gain", "gained", "lose", "losing", "lost", "shed", "weigh", "weighed", "weighs"
    ]
    private static let blockedNextWordsForSpokenPossessive: Set<String> = [
        "character", "characters", "is", "mark", "marks", "means", "meaning", "suffix", "symbol", "symbols"
    ]
    private static let spokenPossessivePattern = #"(?i)(?<![\p{L}\p{N}])([\p{L}\p{N}][\p{L}\p{N}'’ʼ-]{0,63})\s+apostrophe\s+s(?=\s+[\p{L}\p{N}])"#
    private static let likelyLowercaseFragments: Set<String> = [
        "a", "about", "after", "again", "all", "also", "an", "and", "any", "are",
        "as", "at", "back", "be", "because", "but", "by", "can", "case", "code",
        "could", "data", "did", "do", "does", "done", "for", "from", "get", "go",
        "got", "had", "has", "have", "here", "how", "if", "in", "is", "it", "just",
        "like", "make", "maybe", "mean", "model", "models", "need", "not", "now",
        "of", "on", "one", "or", "out", "put", "really", "right", "see", "should",
        "so", "some", "that", "the", "then", "there", "this", "to", "use", "was",
        "we", "what", "when", "where", "which", "will", "with", "work", "would",
        "yeah", "you"
    ]
    private static let preservedSingleWordQuestionFragments: Set<String> = [
        "how", "what", "when", "where", "which", "who", "why"
    ]
    
    private static let nonSpeechBracketPatterns = [
        #"\[\s*([^\[\]]{1,80})\s*\]"#,
        #"\(\s*([^\(\)]{1,80})\s*\)"#,
        #"\{\s*([^\{\}]{1,80})\s*\}"#
    ]
    private static let asrBoilerplatePatterns: [(pattern: String, replacement: String)] = [
        (
            #"(?im)(^|(?<=[.!?])\s+|\n)\s*(?:thank\s+you\s+for\s+watching|thanks\s+for\s+watching|please\s+subscribe|like\s+and\s+subscribe|don't\s+forget\s+to\s+subscribe)(?:[.!?]+)?(?=\s*$|\s+[A-Z]|\n)"#,
            "$1"
        ),
        (
            #"(?im)^\s*(?:subtitles?|captions?|captioned|transcribed)\s+by\b[^\n]*$"#,
            ""
        )
    ]
    private static let punctuatedDiscourseFillerPatterns: [(pattern: String, replacement: String)] = [
        (#"(?i)[,;:…]\s+(?:you\s+know|like)[,;:…]*([.!?])\s*$"#, "$1"),
        (#"(?i)[,;:…]\s+(?:you\s+know|like)[,;:…]+(?=\s)"#, " ")
    ]
    private static let leadingDiscourseFillerPatterns: [(pattern: String, replacement: String)] = [
        (#"(?i)^\s*(?:you\s+know|i\s+mean|like)[,;:…]+[ \t]*"#, "")
    ]
    private static let standaloneDiscourseFillerPattern = #"(?i)^\s*you[ \t]+know(?:[ \t]+what[ \t]+i[ \t]+mean)?[ \t]*[.,;:…]*\s*$"#
    private static let blockedPreviousWordsForTerminalYouKnow: Set<String> = [
        "do", "does", "did", "don't", "if", "know", "let", "should", "to", "whether", "will", "would"
    ]
    private static let allowedPreviousWordsForUnpunctuatedLikeFiller: Set<String> = [
        "am", "are", "be", "been", "being", "i'm", "im", "is", "it's", "its",
        "that's", "thats", "they're", "theyre", "was", "we're", "were", "you're", "youre"
    ]
    private static let allowedNextWordsForUnpunctuatedLikeFiller: Set<String> = [
        "actually", "almost", "basically", "doing", "going", "just", "kind", "kinda",
        "looking", "maybe", "not", "probably", "really", "saying", "so", "sort",
        "sorta", "thinking", "trying", "using", "waiting", "working"
    ]
    private static let inlineNumberedListMarkerPattern = #"(?<![\p{L}\p{N}])\d{1,2}\.\s+(?=\S)"#
    private static let markdownHeadingPattern = #"(?im)(^|\n)[ \t]*(?:heading|header)[ \t]+(one|two|three|1|2|3)[ \t]+([^\n]+)"#
    private static let uncheckedMarkdownTaskPattern = #"(?im)(^|\n)[ \t]*(?:todo|to[ \t]+do|checkbox|check[ \t]+box|unchecked[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+([^\n]+)"#
    private static let checkedMarkdownTaskPattern = #"(?im)(^|\n)[ \t]*(?:(?:checked|done|completed)[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+([^\n]+)"#
    private static let inlineCodePattern = #"(?i)(?<![\p{L}\p{N}])inline[ \t]+code[ \t]+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b)[\p{L}\p{N}_./@:+#-]+[ \t]*){1,4})([.!?])?(?=\s+(?:for|from|in|into|on|to|with)\b|\s|$)"#
    private static let markdownLinkPattern = #"(?im)(^|\n)[ \t]*(?:markdown[ \t]+)?link[ \t]+([^\n]{1,80}?)[ \t]+to[ \t]+([^ \t\n]+)([ \t]+(?:for|from|in|into|on|to|with)\b[^\n.!?]*)?[ \t]*([.!?])?(?=\n|$)"#
    private static let openCodeBlockPattern = #"(?im)(^|\n)[ \t]*(?:open|start)[ \t]+code[ \t]+block(?:[ \t]+([A-Za-z0-9_+#.-]+))?[ \t]*(?=\n|$)"#
    private static let closeCodeBlockPattern = #"(?im)(^|\n)[ \t]*(?:close|end)[ \t]+code[ \t]+block[ \t]*(?=\n|$)"#
    private static let spokenSchemeURLPattern = #"(?i)(?<![\p{L}\p{N}])((?:h[ \t]+t[ \t]+t[ \t]+p[ \t]+s?)|https?)[ \t]*(?:colon|:)[ \t]+(?:slash[ \t]+slash|forward[ \t]+slash[ \t]+forward[ \t]+slash)[ \t]+((?:(?:[A-Za-z0-9-]+[ \t]+dot[ \t]+)+(?:ai|app|co|com|dev|edu|gov|io|net|org)(?:(?:[ \t]+(?:slash|forward[ \t]+slash)[ \t]+[A-Za-z0-9_-]+)+)?)|(?:localhost(?:[ \t]+colon[ \t]+\d{1,5})?(?:(?:[ \t]+(?:slash|forward[ \t]+slash)[ \t]+[A-Za-z0-9_-]+)+)?))([.!?])?(?=\s|$|\n)"#
    private static let spokenWWWURLPattern = #"(?i)(?<![\p{L}\p{N}])www[ \t]+dot[ \t]+((?:[A-Za-z0-9-]+[ \t]+dot[ \t]+)*(?:ai|app|co|com|dev|edu|gov|io|net|org)(?:(?:[ \t]+(?:slash|forward[ \t]+slash)[ \t]+[A-Za-z0-9_-]+)+)?)([.!?])?(?=\s|$|\n)"#
    private static let monthOrdinalDatePattern = #"(?i)(?<![\p{L}\p{N}])(january|february|march|april|may|june|july|august|september|october|november|december)[ \t]+(thirty[ \t]+first|thirtieth|twenty[ \t]+ninth|twenty[ \t]+eighth|twenty[ \t]+seventh|twenty[ \t]+sixth|twenty[ \t]+fifth|twenty[ \t]+fourth|twenty[ \t]+third|twenty[ \t]+second|twenty[ \t]+first|twentieth|nineteenth|eighteenth|seventeenth|sixteenth|fifteenth|fourteenth|thirteenth|twelfth|eleventh|tenth|ninth|eighth|seventh|sixth|fifth|fourth|third|second|first)(?:[ \t]+(\d{4}))?(?![\p{L}\p{N}])"#
    private static let monthNumberDatePattern = #"(?i)(?<![\p{L}\p{N}])(january|february|march|april|may|june|july|august|september|october|november|december)[ \t]+(\d{1,2})(?:st|nd|rd|th)?(?:[ \t]+(\d{4}))?(?![\p{L}\p{N}])"#
    private static let spokenTimePattern = #"(?i)(?<![\p{L}\p{N}])(\d{1,2})(?:[ \t]+(?:(?:colon|:)[ \t]*)?(\d{2}))?[ \t]*(a[ \t]*m|p[ \t]*m|am|pm)(?![\p{L}\p{N}])"#
    private static let leadingCurrencySignPattern = #"(?i)(?<![\p{L}\p{N}])(dollar|euro|pound)[ \t]+sign[ \t]+(\d+(?:\.\d{1,2})?)(?![\p{L}\p{N}])"#
    private static let trailingCurrencyPattern = #"(?i)(?<![\p{L}\p{N}])(\d+(?:\.\d{1,2})?)[ \t]+(dollars?|bucks|usd|euros?|eur|pounds?|gbp)(?![\p{L}\p{N}])"#
    private static let spokenPercentPattern = #"(?i)(?<![\p{L}\p{N}])(\d+(?:\.\d+)?)[ \t]+(?:percent|per[ \t]+cent)(?![\p{L}\p{N}])"#
    private static let simpleNumberWordsPattern = #"(?:zero|oh|o|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ \t]+(?:one|two|three|four|five|six|seven|eight|nine))?"#
    private static let decimalDigitWordsPattern = #"(?:zero|oh|o|one|two|three|four|five|six|seven|eight|nine|\d)"#
    private static let spokenDecimalValuePattern = #"(?i)(?<![\p{L}\p{N}])(\#(simpleNumberWordsPattern)|\d{1,3})[ \t]+point[ \t]+(\#(decimalDigitWordsPattern)(?:[ \t]+\#(decimalDigitWordsPattern)){0,5})(?![\p{L}\p{N}])"#
    private static let leadingWordCurrencySignPattern = #"(?i)(?<![\p{L}\p{N}])(dollar|euro|pound)[ \t]+sign[ \t]+(\#(simpleNumberWordsPattern))(?![\p{L}\p{N}])"#
    private static let trailingWordCurrencyPattern = #"(?i)(?<![\p{L}\p{N}])(\#(simpleNumberWordsPattern))[ \t]+(dollars?|bucks|usd|euros?|eur|pounds?|gbp)(?![\p{L}\p{N}])"#
    private static let spokenWordPercentPattern = #"(?i)(?<![\p{L}\p{N}])(\#(simpleNumberWordsPattern))[ \t]+(?:percent|per[ \t]+cent)(?![\p{L}\p{N}])"#
    private static let backtrackingMarkerPattern = #"""
        (?ix)
        \s*
        (?:
            (?:[,;:…]|\.\.\.)\s*actually\s+no\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*actually |
            (?:[,;:…]|\.\.\.)\s*no\s*[,;:]?\s+actually\s*[,;:]? |
            sorry\s+not\s+that\s*[,;:]?\s+actually |
            (?:[,;:…]|\.\.\.)\s*sorry\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            sorry\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            replace\s+that\s+with |
            change\s+that\s+to |
            scratch\s+that |
            wait\s+no |
            never\s*mind |
            nevermind |
            sorry\s+not\s+that |
            sorry\s+no |
            (?:[,;:…]|\.\.\.)\s*sorry\s*[,;:]? |
            no\s*[,;:]?\s+sorry |
            or\s+rather |
            i\s+mean
        )
        \s*[,;:]?\s+
        """#
    private static let scratchThatCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:scratch|strike|delete|remove|erase|undo)\s+that(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n))"#
    private static let phraseBoundaryPunctuation = CharacterSet(charactersIn: ".,!?;:…")
    private static let softPhrasePunctuation = CharacterSet(charactersIn: ",;:…")
    private static let wordConnectorCharacters = CharacterSet(charactersIn: "'’ʼ-")
    private static let compactTokenConnectors = CharacterSet(charactersIn: "@._-/\\")
    private static let maxBacktrackingCorrectionWords = 4
    private static let maxScratchThatWords = 12
    private static let blockedPreviousWordsForReplaceThat: Set<String> = [
        "command", "commands", "phrase", "phrases", "say", "saying", "word", "words"
    ]
    private static let blockedFirstCorrectionWordsForReplaceThat: Set<String> = [
        "is", "means"
    ]
    private static let openQuotePlaceholder = "__VOICEINK_OPEN_QUOTE__"
    private static let closeQuotePlaceholder = "__VOICEINK_CLOSE_QUOTE__"
    private static let openParenthesisPlaceholder = "__VOICEINK_OPEN_PAREN__"
    private static let closeParenthesisPlaceholder = "__VOICEINK_CLOSE_PAREN__"
    private static let openBracketPlaceholder = "__VOICEINK_OPEN_BRACKET__"
    private static let closeBracketPlaceholder = "__VOICEINK_CLOSE_BRACKET__"
    private static let openBracePlaceholder = "__VOICEINK_OPEN_BRACE__"
    private static let closeBracePlaceholder = "__VOICEINK_CLOSE_BRACE__"
    private static let spokenFormattingCommands: [(pattern: String, replacement: String)] = [
        (#"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+paragraph(?![\p{L}\p{N}])"#, "\n\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+line(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])line\s+break(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])newline(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new\s+bullet|bullet\s+point|bullet)(?![\p{L}\p{N}])"#, "\n- ")
    ]
    private static let spokenEnclosureCommands: [(pattern: String, replacement: String)] = [
        (#"(?i)(?<![\p{L}\p{N}])(?:open|start)\s+(?:quote|quotation\s+marks?)(?![\p{L}\p{N}])"#, openQuotePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|end)\s+(?:quote|quotation\s+marks?)(?![\p{L}\p{N}])"#, closeQuotePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:paren|parenthesis|parentheses)(?![\p{L}\p{N}])"#, openParenthesisPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right)\s+(?:paren|parenthesis|parentheses)(?![\p{L}\p{N}])"#, closeParenthesisPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:square\s+)?bracket(?![\p{L}\p{N}])"#, openBracketPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right)\s+(?:square\s+)?bracket(?![\p{L}\p{N}])"#, closeBracketPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:curly\s+)?brace(?![\p{L}\p{N}])"#, openBracePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right)\s+(?:curly\s+)?brace(?![\p{L}\p{N}])"#, closeBracePlaceholder)
    ]
    private static let spokenSymbolCommands = [
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:forward\s+slash|slash)(?![\p{L}\p{N}])"#,
            output: "/",
            blockedNextWords: ["command", "commands"]
        ),
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:back\s+slash|backslash)(?![\p{L}\p{N}])"#,
            output: "\\"
        ),
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])at\s+sign(?![\p{L}\p{N}])"#,
            output: "@",
            blockedPreviousWords: ["a", "an", "the"],
            blockedNextWords: ["symbol"],
            requiresCompactContext: true
        ),
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])dot(?![\p{L}\p{N}])"#,
            output: ".",
            blockedPreviousWords: ["a", "an", "the"],
            blockedNextWords: ["matrix", "notation", "plot", "product"],
            requiresCompactContext: true
        ),
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])underscore(?![\p{L}\p{N}])"#,
            output: "_",
            blockedPreviousWords: ["a", "an", "the"],
            blockedNextWords: ["command", "commands", "symbol"],
            requiresCompactContext: true
        ),
        SpokenSymbolCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:dash|hyphen)(?![\p{L}\p{N}])"#,
            output: "-",
            blockedPreviousWords: ["a"],
            blockedNextWords: ["of"]
        )
    ]
    private static let spokenContractionCommands = [
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])can\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "can't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])don\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "don't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])won\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "won't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])doesn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "doesn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])didn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "didn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])isn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "isn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])aren\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "aren't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])wasn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "wasn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])weren\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "weren't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])hasn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "hasn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])haven\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "haven't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])hadn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "hadn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])shouldn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "shouldn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])wouldn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "wouldn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])couldn\s+apostrophe\s+t(?![\p{L}\p{N}])"#, replacement: "couldn't"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])I\s+apostrophe\s+m(?![\p{L}\p{N}])"#, replacement: "I'm"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])I\s+apostrophe\s+ve(?![\p{L}\p{N}])"#, replacement: "I've"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])I\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "I'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])I\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "I'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])we\s+apostrophe\s+re(?![\p{L}\p{N}])"#, replacement: "we're"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])you\s+apostrophe\s+re(?![\p{L}\p{N}])"#, replacement: "you're"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])they\s+apostrophe\s+re(?![\p{L}\p{N}])"#, replacement: "they're"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])we\s+apostrophe\s+ve(?![\p{L}\p{N}])"#, replacement: "we've"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])you\s+apostrophe\s+ve(?![\p{L}\p{N}])"#, replacement: "you've"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])they\s+apostrophe\s+ve(?![\p{L}\p{N}])"#, replacement: "they've"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])we\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "we'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])you\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "you'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])they\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "they'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])we\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "we'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])you\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "you'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])they\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "they'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])he\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "he's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])he\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "he'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])he\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "he'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])she\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "she's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])she\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "she'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])she\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "she'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])it\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "it's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])it\s+apostrophe\s+ll(?![\p{L}\p{N}])"#, replacement: "it'll"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])it\s+apostrophe\s+d(?![\p{L}\p{N}])"#, replacement: "it'd"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])that\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "that's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])what\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "what's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])who\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "who's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])where\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "where's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])when\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "when's"),
        SpokenContractionCommand(pattern: #"(?i)(?<![\p{L}\p{N}])let\s+apostrophe\s+s(?![\p{L}\p{N}])"#, replacement: "let's")
    ]
    private static let spokenCodeCaseCommands = [
        SpokenCodeCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])camel\s*case\s+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b)[\p{L}\p{N}]+\s*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .camel
        ),
        SpokenCodeCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])snake\s*case\s+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b)[\p{L}\p{N}]+\s*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .snake
        ),
        SpokenCodeCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:kebab|dash|hyphen)\s*case\s+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b)[\p{L}\p{N}]+\s*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .kebab
        ),
        SpokenCodeCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])pascal\s*case\s+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b)[\p{L}\p{N}]+\s*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .pascal
        )
    ]
    private static let spokenPunctuationCommands = [
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])question\s+mark(?![\p{L}\p{N}])"#,
            output: "?"
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])exclamation\s+(?:mark|point)(?![\p{L}\p{N}])"#,
            output: "!"
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])full\s+stop(?![\p{L}\p{N}])"#,
            output: "."
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])period(?![\p{L}\p{N}])"#,
            output: ".",
            blockedPreviousWords: [
                "billing", "class", "current", "grace", "historical",
                "pay", "payback", "reporting", "retention", "school",
                "time", "trial"
            ],
            blockedNextWords: ["drama", "of", "piece"]
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])comma(?![\p{L}\p{N}])"#,
            output: ",",
            blockedPreviousWords: ["oxford", "serial"],
            blockedNextWords: ["operator", "separated"]
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])semicolon(?![\p{L}\p{N}])"#,
            output: ";"
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])colon(?![\p{L}\p{N}])"#,
            output: ":",
            blockedPreviousWords: ["http", "https"]
        )
    ]
    private static let standaloneSpokenPunctuationOutputs = [
        "comma": ",",
        "period": ".",
        "full stop": ".",
        "question mark": "?",
        "exclamation mark": "!",
        "exclamation point": "!",
        "semicolon": ";",
        "colon": ":"
    ]

    public static func filter(
        _ text: String,
        cleanupLevel: RomaTranscriptionCleanupLevel = .polished,
        removesFillerWords: Bool = false,
        fillerWords: [String] = Self.defaultFillerWords
    ) -> String {
        var filteredText = unwrapSquareBracketedWholeOutput(text)

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        filteredText = removeNonSpeechBracketedContent(from: filteredText)

        filteredText = removeASRBoilerplate(from: filteredText)

        guard cleanupLevel != .raw else {
            return normalizeWhitespace(filteredText)
        }

        if cleanupLevel == .polished && removesFillerWords {
            filteredText = removeFillerWords(from: filteredText, fillerWords: fillerWords)
        }

        if cleanupLevel == .polished {
            filteredText = applyBacktrackingCorrections(in: filteredText)
        }
        filteredText = applySpokenFormattingCommands(in: filteredText)
        filteredText = applySpokenEnclosureCommands(in: filteredText)
        filteredText = applySpokenURLCommands(in: filteredText)
        filteredText = applySpokenValueFormattingCommands(in: filteredText)
        filteredText = applySpokenPunctuationCommands(in: filteredText)
        filteredText = formatInlineNumberedLists(in: filteredText)
        filteredText = applySpokenSymbolCommands(in: filteredText)
        filteredText = applySpokenContractionCommands(in: filteredText)
        filteredText = applySpokenPossessiveCommands(in: filteredText)
        filteredText = applySpokenCodeCaseCommands(in: filteredText)
        filteredText = applySpokenMarkdownCommands(in: filteredText)
        if cleanupLevel == .polished {
            filteredText = collapseAdjacentRepeatedWords(in: filteredText)
            filteredText = collapseRepeatedShortPhrases(in: filteredText)
            filteredText = collapseRepeatedShortClauses(in: filteredText)
            filteredText = collapseRepeatedShortSentences(in: filteredText)
        }

        // Clean whitespace
        filteredText = normalizeWhitespace(filteredText)

        return filteredText
    }

    private static func removeASRBoilerplate(from text: String) -> String {
        var filteredText = text
        for pattern in asrBoilerplatePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else {
                continue
            }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(
                in: filteredText,
                options: [],
                range: range,
                withTemplate: pattern.replacement
            )
        }

        return filteredText
    }

    private static func removeNonSpeechBracketedContent(from text: String) -> String {
        var filteredText = text

        for pattern in nonSpeechBracketPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let matches = regex
                .matches(in: filteredText, range: NSRange(filteredText.startIndex..., in: filteredText))
                .reversed()

            for match in matches {
                guard match.numberOfRanges >= 2,
                      let fullRange = Range(match.range(at: 0), in: filteredText),
                      let innerRange = Range(match.range(at: 1), in: filteredText),
                      isNonSpeechBracketContent(String(filteredText[innerRange])) else {
                    continue
                }

                filteredText.replaceSubrange(fullRange, with: "")
            }
        }

        return filteredText
    }

    private static func isNonSpeechBracketContent(_ text: String) -> Bool {
        let normalizedText = text
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;:… ").union(.whitespacesAndNewlines))
            .lowercased()
        return nonSpeechBracketContents.contains(normalizedText)
    }

    public static func applyInsertionPolish(_ text: String, context: TextInsertionContext?) -> String {
        var polishedText = stripBoundaryNoise(from: normalizeWhitespace(text))
        guard !polishedText.isEmpty else { return polishedText }

        let shouldTreatAsFragment = isShortFragment(polishedText)
        let shouldUseFragmentPolish: Bool
        if let context, isContinuingSentence(after: context.precedingText) {
            shouldUseFragmentPolish = shouldTreatAsFragment
        } else {
            shouldUseFragmentPolish = shouldTreatAsFragment && isSingleWordFinalFragment(polishedText)
        }

        if shouldUseFragmentPolish {
            polishedText = removeTrailingShortFragmentPunctuation(from: polishedText)
        }

        if let context,
           let punctuation = standaloneSpokenPunctuationOutput(in: polishedText),
           canAttachStandalonePunctuation(after: context.precedingText) {
            return punctuation
        }

        if let context {
            guard isContinuingSentence(after: context.precedingText) else {
                return polishedText
            }
            return lowercaseInitialWordIfSafe(in: polishedText, force: true)
        }

        guard shouldUseFragmentPolish else { return polishedText }
        return lowercaseInitialWordIfSafe(in: polishedText, force: false)
    }

    private static func standaloneSpokenPunctuationOutput(in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return standaloneSpokenPunctuationOutputs[normalizedText]
    }

    private static func canAttachStandalonePunctuation(after precedingText: String) -> Bool {
        let trimmedText = currentLinePrefix(in: precedingText).trimmingCharacters(in: .whitespaces)
        guard let previousCharacter = trimmedText.last else { return false }

        if previousCharacter.isLetter || previousCharacter.isNumber {
            return true
        }

        return ")]}\"'".contains(previousCharacter)
    }

    public static func applyInsertionSpacing(_ text: String, context: TextInsertionContext?) -> String {
        guard let context else { return text }
        guard needsLeadingSpace(before: text, context: context) else { return text }
        return " \(text)"
    }

    private static func removeFillerWords(from text: String, fillerWords configuredFillerWords: [String]) -> String {
        var filteredText = text

        filteredText = removeStandaloneDiscourseFillers(from: filteredText)
        filteredText = removeLeadingDiscourseFillers(from: filteredText)
        filteredText = removePunctuatedDiscourseFillers(from: filteredText)
        filteredText = removeTerminalDiscourseFillers(from: filteredText)
        filteredText = removeUnpunctuatedLikeFillers(from: filteredText)

        let joinedPausePattern = #"(?i)(?<![\p{L}\p{N}])(?:m+h+m+|m+[\s-]+h+m+|u+h+[\s-]+h*u+h+|u+h+[\s-]+u+h+|u+m+[\s-]+h+m+)(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
        if let regex = try? NSRegularExpression(pattern: joinedPausePattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        let spokenPausePattern = #"(?i)(?<![\p{L}\p{N}])(?:u+h+|u+m+|h+m+|m+h+|m{2,}|e+h+|e+r+|a+h+|h+uh+)(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
        if let regex = try? NSRegularExpression(pattern: spokenPausePattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        let fillerWords = Set(configuredFillerWords + defaultFillerWords)
        for fillerWord in fillerWords {
            let normalizedFillerWord = fillerWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedFillerWord.isEmpty else { continue }

            let pattern = #"(?i)(?<![\p{L}\p{N}])"# +
                NSRegularExpression.escapedPattern(for: normalizedFillerWord) +
                #"(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        return filteredText
    }

    private static func removeStandaloneDiscourseFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: standaloneDiscourseFillerPattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        guard regex.firstMatch(in: text, range: range) != nil else {
            return text
        }
        return ""
    }

    private static func removeLeadingDiscourseFillers(from text: String) -> String {
        var filteredText = text

        for pattern in leadingDiscourseFillerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else {
                continue
            }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(
                in: filteredText,
                options: [],
                range: range,
                withTemplate: pattern.replacement
            )
        }

        return filteredText
    }

    private static func removeTerminalDiscourseFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^([\s\S]*?)[ \t]+you[ \t]+know(?:[ \t]+what[ \t]+i[ \t]+mean)?[ \t]*([.!?])\s*$"#
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let prefixRange = Range(match.range(at: 1), in: text),
              let punctuationRange = Range(match.range(at: 2), in: text) else {
            return text
        }

        let prefix = String(text[prefixRange])
        let trimmedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: softPhrasePunctuation)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmedPrefix) >= 2,
              let previousWord = previousWord(in: trimmedPrefix),
              !blockedPreviousWordsForTerminalYouKnow.contains(previousWord) else {
            return text
        }

        return "\(trimmedPrefix)\(String(text[punctuationRange]))"
    }

    private static func removeUnpunctuatedLikeFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}])like(?:[ \t]*[,;:…]+)?(?![\p{L}\p{N}])"#
        ) else {
            return text
        }

        var filteredText = text
        let range = NSRange(filteredText.startIndex..., in: filteredText)
        let matches = regex.matches(in: filteredText, range: range).reversed()

        for match in matches {
            guard let matchRange = Range(match.range, in: filteredText) else {
                continue
            }

            let prefix = String(filteredText[..<matchRange.lowerBound])
            let suffix = String(filteredText[matchRange.upperBound...])
            guard let previousWord = previousWord(in: prefix),
                  let nextWord = nextWord(in: suffix),
                  allowedPreviousWordsForUnpunctuatedLikeFiller.contains(previousWord),
                  allowedNextWordsForUnpunctuatedLikeFiller.contains(nextWord) else {
                continue
            }

            filteredText.replaceSubrange(matchRange, with: "")
        }

        return filteredText
    }

    private static func removePunctuatedDiscourseFillers(from text: String) -> String {
        var filteredText = text

        for pattern in punctuatedDiscourseFillerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else {
                continue
            }

            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(
                in: filteredText,
                options: [],
                range: range,
                withTemplate: pattern.replacement
            )
        }

        return filteredText
    }

    private static func applySpokenFormattingCommands(in text: String) -> String {
        var formattedText = text

        for command in spokenFormattingCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let range = NSRange(formattedText.startIndex..., in: formattedText)
            formattedText = regex.stringByReplacingMatches(
                in: formattedText,
                options: [],
                range: range,
                withTemplate: command.replacement
            )
        }

        return normalizeSpokenFormattingSpacing(formattedText)
    }

    private static func applySpokenEnclosureCommands(in text: String) -> String {
        var enclosedText = text

        for command in spokenEnclosureCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let range = NSRange(enclosedText.startIndex..., in: enclosedText)
            enclosedText = regex.stringByReplacingMatches(
                in: enclosedText,
                options: [],
                range: range,
                withTemplate: command.replacement
            )
        }

        return normalizeSpokenEnclosureSpacing(enclosedText)
    }

    private static func normalizeSpokenEnclosureSpacing(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\(openQuotePlaceholder)\\s+", with: openQuotePlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\\s+\(closeQuotePlaceholder)", with: closeQuotePlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\(openParenthesisPlaceholder)\\s+", with: openParenthesisPlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\\s+\(closeParenthesisPlaceholder)", with: closeParenthesisPlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\(openBracketPlaceholder)\\s+", with: openBracketPlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\\s+\(closeBracketPlaceholder)", with: closeBracketPlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\(openBracePlaceholder)\\s+", with: openBracePlaceholder, options: .regularExpression)
            .replacingOccurrences(of: "\\s+\(closeBracePlaceholder)", with: closeBracePlaceholder, options: .regularExpression)
            .replacingOccurrences(of: openQuotePlaceholder, with: "\"")
            .replacingOccurrences(of: closeQuotePlaceholder, with: "\"")
            .replacingOccurrences(of: openParenthesisPlaceholder, with: "(")
            .replacingOccurrences(of: closeParenthesisPlaceholder, with: ")")
            .replacingOccurrences(of: openBracketPlaceholder, with: "[")
            .replacingOccurrences(of: closeBracketPlaceholder, with: "]")
            .replacingOccurrences(of: openBracePlaceholder, with: "{")
            .replacingOccurrences(of: closeBracePlaceholder, with: "}")
    }

    private static func applySpokenSymbolCommands(in text: String) -> String {
        var symbolizedText = text

        for command in spokenSymbolCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let fullRange = NSRange(symbolizedText.startIndex..., in: symbolizedText)
            let matches = regex.matches(in: symbolizedText, range: fullRange).reversed()

            for match in matches {
                guard let range = Range(match.range, in: symbolizedText),
                      shouldApplySpokenSymbolCommand(command, in: symbolizedText, commandRange: range) else {
                    continue
                }

                symbolizedText = replaceSpokenSymbolCommand(command, in: symbolizedText, commandRange: range)
            }
        }

        return symbolizedText
    }

    private static func applySpokenContractionCommands(in text: String) -> String {
        var contractedText = text

        for command in spokenContractionCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let fullRange = NSRange(contractedText.startIndex..., in: contractedText)
            let matches = regex.matches(in: contractedText, range: fullRange).reversed()

            for match in matches {
                guard let range = Range(match.range, in: contractedText) else {
                    continue
                }

                let matchedText = String(contractedText[range])
                let replacement = spokenContractionReplacement(command.replacement, matchedText: matchedText)
                contractedText.replaceSubrange(range, with: replacement)
            }
        }

        return contractedText
    }

    private static func spokenContractionReplacement(_ replacement: String, matchedText: String) -> String {
        if replacement.first == "I" {
            return replacement
        }

        guard matchedText.first?.isUppercase == true else {
            return replacement
        }

        return replacement.prefix(1).uppercased() + String(replacement.dropFirst())
    }

    private static func applySpokenPossessiveCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenPossessivePattern) else {
            return text
        }

        var possessiveText = text
        let fullRange = NSRange(possessiveText.startIndex..., in: possessiveText)
        let matches = regex.matches(in: possessiveText, range: fullRange).reversed()

        for match in matches {
            guard let range = Range(match.range, in: possessiveText),
                  let ownerRange = Range(match.range(at: 1), in: possessiveText),
                  shouldApplySpokenPossessive(in: possessiveText, commandRange: range) else {
                continue
            }

            possessiveText.replaceSubrange(range, with: "\(possessiveText[ownerRange])'s")
        }

        return possessiveText
    }

    private static func shouldApplySpokenPossessive(in text: String, commandRange: Range<String.Index>) -> Bool {
        let afterCommand = String(text[commandRange.upperBound...])

        guard let nextWord = nextWord(in: afterCommand) else {
            return false
        }

        return !blockedNextWordsForSpokenPossessive.contains(nextWord)
    }

    private static func shouldApplySpokenSymbolCommand(
        _ command: SpokenSymbolCommand,
        in text: String,
        commandRange: Range<String.Index>
    ) -> Bool {
        let beforeCommand = String(text[..<commandRange.lowerBound])
        let afterCommand = String(text[commandRange.upperBound...])

        guard let previousWord = previousWord(in: beforeCommand),
              let nextWord = nextWord(in: afterCommand) else {
            return false
        }

        if command.blockedPreviousWords.contains(previousWord) {
            return false
        }

        if command.blockedNextWords.contains(nextWord) {
            return false
        }

        if command.requiresCompactContext,
           !hasCompactSymbolContext(command: command, before: beforeCommand, after: afterCommand) {
            return false
        }

        return true
    }

    private static func hasCompactSymbolContext(
        command: SpokenSymbolCommand,
        before: String,
        after: String
    ) -> Bool {
        switch command.output {
        case "@":
            return hasAtSignSymbolContext(before: before, after: after)
        case ".":
            return hasDotSymbolContext(before: before, after: after)
        case "_":
            return hasUnderscoreSymbolContext(before: before, after: after)
        default:
            return hasGenericCompactSymbolContext(before: before, after: after)
        }
    }

    private static func hasAtSignSymbolContext(before: String, after: String) -> Bool {
        guard let previousToken = trailingToken(in: before),
              let nextToken = leadingToken(in: after) else {
            return false
        }

        return previousToken.count <= 64 && (3...63).contains(nextToken.count)
    }

    private static func hasDotSymbolContext(before: String, after: String) -> Bool {
        guard let previousToken = trailingToken(in: before),
              let nextToken = leadingToken(in: after) else {
            return false
        }

        if isCommonTopLevelDomain(nextToken) || containsSpokenDomainSuffix(after) {
            return true
        }

        if previousToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) ||
            nextToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) {
            return true
        }

        return previousToken.contains(where: \.isNumber) || nextToken.contains(where: \.isNumber)
    }

    private static func hasUnderscoreSymbolContext(before: String, after: String) -> Bool {
        guard let previousToken = trailingToken(in: before),
              let nextToken = leadingToken(in: after) else {
            return false
        }

        if previousToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) ||
            nextToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) {
            return true
        }

        if previousToken.contains(where: \.isNumber) || nextToken.contains(where: \.isNumber) {
            return true
        }

        return previousToken.count <= 32 && nextToken.count <= 4
    }

    private static func hasGenericCompactSymbolContext(before: String, after: String) -> Bool {
        guard let previousToken = trailingToken(in: before),
              let nextToken = leadingToken(in: after) else {
            return false
        }

        if isCommonTopLevelDomain(nextToken) {
            return true
        }

        if previousToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) ||
            nextToken.unicodeScalars.contains(where: { compactTokenConnectors.contains($0) }) {
            return true
        }

        if previousToken.contains(where: \.isNumber) || nextToken.contains(where: \.isNumber) {
            return true
        }

        return previousToken.count <= 12 && nextToken.count <= 4
    }

    private static func applySpokenURLCommands(in text: String) -> String {
        var urlText = replaceSpokenSchemeURLs(in: text)
        urlText = replaceSpokenWWWURLs(in: urlText)
        return urlText
    }

    private static func replaceSpokenSchemeURLs(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenSchemeURLPattern) else {
            return text
        }

        var urlText = text
        let matches = regex.matches(in: urlText, range: NSRange(urlText.startIndex..., in: urlText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: urlText),
                  let schemeRange = Range(match.range(at: 1), in: urlText),
                  let targetRange = Range(match.range(at: 2), in: urlText) else {
                continue
            }

            let scheme = spokenURLScheme(String(urlText[schemeRange]))
            guard let target = spokenURLTarget(String(urlText[targetRange]), allowLocalhost: true) else {
                continue
            }

            urlText.replaceSubrange(fullRange, with: "\(scheme)://\(target)")
        }

        return urlText
    }

    private static func replaceSpokenWWWURLs(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenWWWURLPattern) else {
            return text
        }

        var urlText = text
        let matches = regex.matches(in: urlText, range: NSRange(urlText.startIndex..., in: urlText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: urlText),
                  let targetRange = Range(match.range(at: 1), in: urlText),
                  let target = spokenURLTarget(String(urlText[targetRange]), allowLocalhost: false) else {
                continue
            }

            urlText.replaceSubrange(fullRange, with: "www.\(target)")
        }

        return urlText
    }

    private static func spokenURLScheme(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func spokenURLTarget(_ text: String, allowLocalhost: Bool) -> String? {
        let tokens = spokenURLTokens(in: text)
        guard !tokens.isEmpty else { return nil }

        var target = ""
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]

            switch token {
            case "dot":
                target += "."
            case "slash":
                target += "/"
            case "forward" where tokens.index(after: index) < tokens.endIndex && tokens[tokens.index(after: index)] == "slash":
                target += "/"
                index = tokens.index(after: index)
            case "dash", "hyphen":
                target += "-"
            case "underscore":
                target += "_"
            case "colon":
                target += ":"
            default:
                guard isURLWordToken(token) else { return nil }
                target += token
            }

            index = tokens.index(after: index)
        }

        let normalizedTarget = target.trimmingCharacters(in: CharacterSet(charactersIn: "/._-:"))
        guard isLikelyURLTarget(normalizedTarget, allowLocalhost: allowLocalhost) else {
            return nil
        }
        return normalizedTarget
    }

    private static func spokenURLTokens(in text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
    }

    private static func isURLWordToken(_ token: String) -> Bool {
        token.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil
    }

    private static func isLikelyURLTarget(_ text: String, allowLocalhost: Bool) -> Bool {
        let host = text.split(separator: "/", maxSplits: 1).first?
            .split(separator: ":", maxSplits: 1).first
            .map(String.init) ?? ""
        guard !host.isEmpty else { return false }

        if allowLocalhost && host == "localhost" {
            return true
        }

        let hostParts = host.split(separator: ".").map(String.init)
        guard hostParts.count >= 2,
              let topLevelDomain = hostParts.last else {
            return false
        }

        return isCommonTopLevelDomain(topLevelDomain)
    }

    private static func applySpokenValueFormattingCommands(in text: String) -> String {
        var formattedText = replaceSpokenMonthOrdinalDates(in: text)
        formattedText = replaceSpokenMonthNumberDates(in: formattedText)
        formattedText = replaceSpokenTimes(in: formattedText)
        formattedText = replaceSpokenDecimalValues(in: formattedText)
        formattedText = replaceLeadingCurrencySigns(in: formattedText)
        formattedText = replaceTrailingCurrencyWords(in: formattedText)
        formattedText = replaceSpokenWordCurrencyAmounts(in: formattedText)
        formattedText = replaceSpokenPercents(in: formattedText)
        formattedText = replaceSpokenWordPercents(in: formattedText)
        return formattedText
    }

    private static func replaceSpokenMonthOrdinalDates(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: monthOrdinalDatePattern) else {
            return text
        }

        var dateText = text
        let matches = regex.matches(in: dateText, range: NSRange(dateText.startIndex..., in: dateText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: dateText),
                  let monthRange = Range(match.range(at: 1), in: dateText),
                  let ordinalRange = Range(match.range(at: 2), in: dateText),
                  let day = ordinalDayNumber(String(dateText[ordinalRange])) else {
                continue
            }

            let rawMonth = String(dateText[monthRange])
            let beforeDate = String(dateText[..<fullRange.lowerBound])
            guard shouldFormatSpokenMonth(rawMonth, precedingText: beforeDate) else { continue }

            let month = normalizedMonthName(rawMonth)
            let year = optionalMatchText(in: dateText, match: match, rangeIndex: 3)
            let replacement = year.map { "\(month) \(day), \($0)" } ?? "\(month) \(day)"
            dateText.replaceSubrange(fullRange, with: replacement)
        }

        return dateText
    }

    private static func replaceSpokenMonthNumberDates(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: monthNumberDatePattern) else {
            return text
        }

        var dateText = text
        let matches = regex.matches(in: dateText, range: NSRange(dateText.startIndex..., in: dateText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: dateText),
                  let monthRange = Range(match.range(at: 1), in: dateText),
                  let dayRange = Range(match.range(at: 2), in: dateText),
                  let day = Int(dateText[dayRange]),
                  (1...31).contains(day) else {
                continue
            }

            let rawMonth = String(dateText[monthRange])
            let beforeDate = String(dateText[..<fullRange.lowerBound])
            guard shouldFormatSpokenMonth(rawMonth, precedingText: beforeDate) else { continue }

            let month = normalizedMonthName(rawMonth)
            let year = optionalMatchText(in: dateText, match: match, rangeIndex: 3)
            let replacement = year.map { "\(month) \(day), \($0)" } ?? "\(month) \(day)"
            dateText.replaceSubrange(fullRange, with: replacement)
        }

        return dateText
    }

    private static func replaceSpokenTimes(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenTimePattern) else {
            return text
        }

        var timeText = text
        let matches = regex.matches(in: timeText, range: NSRange(timeText.startIndex..., in: timeText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range(at: 0), in: timeText),
                  let hourRange = Range(match.range(at: 1), in: timeText),
                  let hour = Int(timeText[hourRange]),
                  (1...12).contains(hour),
                  let meridiemRange = Range(match.range(at: 3), in: timeText) else {
                continue
            }

            let minuteText = optionalMatchText(in: timeText, match: match, rangeIndex: 2)
            if let minuteText,
               let minute = Int(minuteText),
               !(0...59).contains(minute) {
                continue
            }

            let meridiem = normalizedMeridiem(String(timeText[meridiemRange]))
            let replacement = minuteText.map { "\(hour):\($0) \(meridiem)" } ?? "\(hour) \(meridiem)"
            timeText.replaceSubrange(fullRange, with: replacement)
        }

        return timeText
    }

    private static func replaceSpokenDecimalValues(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenDecimalValuePattern) else {
            return text
        }

        var decimalText = text
        let matches = regex.matches(in: decimalText, range: NSRange(decimalText.startIndex..., in: decimalText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: decimalText),
                  let integerRange = Range(match.range(at: 1), in: decimalText),
                  let fractionalRange = Range(match.range(at: 2), in: decimalText),
                  let integerPart = spokenNumberValue(String(decimalText[integerRange])),
                  let fractionalDigits = spokenDecimalDigits(String(decimalText[fractionalRange])) else {
                continue
            }

            decimalText.replaceSubrange(fullRange, with: "\(integerPart).\(fractionalDigits)")
        }

        return decimalText
    }

    private static func replaceLeadingCurrencySigns(in text: String) -> String {
        replaceCurrency(in: text, pattern: leadingCurrencySignPattern, amountRangeIndex: 2, currencyRangeIndex: 1)
    }

    private static func replaceTrailingCurrencyWords(in text: String) -> String {
        replaceCurrency(in: text, pattern: trailingCurrencyPattern, amountRangeIndex: 1, currencyRangeIndex: 2)
    }

    private static func replaceCurrency(
        in text: String,
        pattern: String,
        amountRangeIndex: Int,
        currencyRangeIndex: Int
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var currencyText = text
        let matches = regex.matches(in: currencyText, range: NSRange(currencyText.startIndex..., in: currencyText))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: currencyText),
                  let amountRange = Range(match.range(at: amountRangeIndex), in: currencyText),
                  let currencyRange = Range(match.range(at: currencyRangeIndex), in: currencyText),
                  let symbol = currencySymbol(for: String(currencyText[currencyRange])) else {
                continue
            }

            guard shouldFormatCurrencyAmount(
                currencyWord: String(currencyText[currencyRange]),
                beforeAmount: String(currencyText[..<fullRange.lowerBound]),
                afterAmount: String(currencyText[fullRange.upperBound...])
            ) else {
                continue
            }

            currencyText.replaceSubrange(fullRange, with: "\(symbol)\(currencyText[amountRange])")
        }

        return currencyText
    }

    private static func replaceSpokenWordCurrencyAmounts(in text: String) -> String {
        var currencyText = replaceWordCurrency(
            in: text,
            pattern: leadingWordCurrencySignPattern,
            amountRangeIndex: 2,
            currencyRangeIndex: 1
        )
        currencyText = replaceWordCurrency(
            in: currencyText,
            pattern: trailingWordCurrencyPattern,
            amountRangeIndex: 1,
            currencyRangeIndex: 2
        )
        return currencyText
    }

    private static func replaceWordCurrency(
        in text: String,
        pattern: String,
        amountRangeIndex: Int,
        currencyRangeIndex: Int
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var currencyText = text
        let matches = regex.matches(in: currencyText, range: NSRange(currencyText.startIndex..., in: currencyText))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: currencyText),
                  let amountRange = Range(match.range(at: amountRangeIndex), in: currencyText),
                  let amount = spokenNumberValue(String(currencyText[amountRange])),
                  let currencyRange = Range(match.range(at: currencyRangeIndex), in: currencyText),
                  let symbol = currencySymbol(for: String(currencyText[currencyRange])) else {
                continue
            }

            guard shouldFormatCurrencyAmount(
                currencyWord: String(currencyText[currencyRange]),
                beforeAmount: String(currencyText[..<fullRange.lowerBound]),
                afterAmount: String(currencyText[fullRange.upperBound...])
            ) else {
                continue
            }

            currencyText.replaceSubrange(fullRange, with: "\(symbol)\(amount)")
        }

        return currencyText
    }

    private static func replaceSpokenPercents(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenPercentPattern) else {
            return text
        }

        var percentText = text
        let matches = regex.matches(in: percentText, range: NSRange(percentText.startIndex..., in: percentText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: percentText),
                  let amountRange = Range(match.range(at: 1), in: percentText) else {
                continue
            }

            percentText.replaceSubrange(fullRange, with: "\(percentText[amountRange])%")
        }

        return percentText
    }

    private static func replaceSpokenWordPercents(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenWordPercentPattern) else {
            return text
        }

        var percentText = text
        let matches = regex.matches(in: percentText, range: NSRange(percentText.startIndex..., in: percentText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: percentText),
                  let amountRange = Range(match.range(at: 1), in: percentText),
                  let amount = spokenNumberValue(String(percentText[amountRange])) else {
                continue
            }

            percentText.replaceSubrange(fullRange, with: "\(amount)%")
        }

        return percentText
    }

    private static func optionalMatchText(in text: String, match: NSTextCheckingResult, rangeIndex: Int) -> String? {
        guard match.numberOfRanges > rangeIndex,
              let range = Range(match.range(at: rangeIndex), in: text) else {
            return nil
        }

        return String(text[range])
    }

    private static func spokenNumberValue(_ text: String) -> Int? {
        let normalizedText = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let value = Int(normalizedText) {
            return value
        }

        let ones = [
            "zero": 0, "oh": 0, "o": 0, "one": 1, "two": 2, "three": 3,
            "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
        ]
        if let value = ones[normalizedText] {
            return value
        }

        let tens = [
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        if let value = tens[normalizedText] {
            return value
        }

        let parts = normalizedText.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let tensValue = tens[parts[0]],
              let onesValue = ones[parts[1]],
              (1...9).contains(onesValue) else {
            return nil
        }

        return tensValue + onesValue
    }

    private static func spokenDecimalDigits(_ text: String) -> String? {
        let parts = text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !parts.isEmpty else { return nil }

        var digits: [String] = []
        for part in parts {
            if let value = Int(part),
               (0...9).contains(value) {
                digits.append(String(value))
                continue
            }

            guard let value = spokenNumberValue(part),
                  (0...9).contains(value) else {
                return nil
            }
            digits.append(String(value))
        }

        return digits.joined()
    }

    private static func normalizedMonthName(_ text: String) -> String {
        let lowercasedText = text.lowercased()
        guard let firstCharacter = lowercasedText.first else { return lowercasedText }
        return String(firstCharacter).uppercased() + lowercasedText.dropFirst()
    }

    private static func shouldFormatSpokenMonth(_ text: String, precedingText: String) -> Bool {
        if text.first?.isUppercase == true {
            return true
        }

        guard let previousWord = previousWord(in: precedingText) else {
            return false
        }

        return dateContextWords.contains(previousWord)
    }

    private static func ordinalDayNumber(_ text: String) -> Int? {
        let normalizedText = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let ordinals = [
            "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
            "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
            "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
            "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
            "nineteenth": 19, "twentieth": 20, "twenty first": 21,
            "twenty second": 22, "twenty third": 23, "twenty fourth": 24,
            "twenty fifth": 25, "twenty sixth": 26, "twenty seventh": 27,
            "twenty eighth": 28, "twenty ninth": 29, "thirtieth": 30,
            "thirty first": 31
        ]

        return ordinals[normalizedText]
    }

    private static func normalizedMeridiem(_ text: String) -> String {
        text.lowercased().contains("p") ? "PM" : "AM"
    }

    private static func currencySymbol(for text: String) -> String? {
        switch text.lowercased() {
        case "dollar", "dollars", "bucks", "usd":
            return "$"
        case "euro", "euros", "eur":
            return "€"
        case "pound", "pounds", "gbp":
            return "£"
        default:
            return nil
        }
    }

    private static func shouldFormatCurrencyAmount(
        currencyWord: String,
        beforeAmount: String,
        afterAmount: String
    ) -> Bool {
        guard ["pound", "pounds"].contains(currencyWord.lowercased()) else {
            return true
        }

        if let previousWord = previousWord(in: beforeAmount),
           poundWeightContextWords.contains(previousWord) {
            return false
        }

        if nextWord(in: afterAmount) == "of" {
            return false
        }

        return true
    }

    private static func containsSpokenDomainSuffix(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^\s+[\p{L}\p{N}-]+\s+dot\s+(ai|app|co|com|dev|edu|gov|io|net|org)(?:[^\p{L}\p{N}]|$)"#
        ) else {
            return false
        }

        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func isCommonTopLevelDomain(_ text: String) -> Bool {
        let commonTopLevelDomains: Set<String> = [
            "ai", "app", "co", "com", "dev", "edu", "gov", "io", "net", "org"
        ]
        return commonTopLevelDomains.contains(text.lowercased())
    }

    private static func trailingToken(in text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        var tokenStart = trimmedText.endIndex
        while tokenStart > trimmedText.startIndex {
            let previousIndex = trimmedText.index(before: tokenStart)
            let character = trimmedText[previousIndex]
            guard isCompactTokenCharacter(character) else { break }
            tokenStart = previousIndex
        }

        guard tokenStart < trimmedText.endIndex else { return nil }
        return String(trimmedText[tokenStart...])
    }

    private static func leadingToken(in text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        var tokenEnd = trimmedText.startIndex
        while tokenEnd < trimmedText.endIndex,
              isCompactTokenCharacter(trimmedText[tokenEnd]) {
            tokenEnd = trimmedText.index(after: tokenEnd)
        }

        guard trimmedText.startIndex < tokenEnd else { return nil }
        return String(trimmedText[..<tokenEnd])
    }

    private static func isCompactTokenCharacter(_ character: Character) -> Bool {
        character.isLetter ||
            character.isNumber ||
            character.unicodeScalars.allSatisfy { compactTokenConnectors.contains($0) }
    }

    private static func replaceSpokenSymbolCommand(
        _ command: SpokenSymbolCommand,
        in text: String,
        commandRange: Range<String.Index>
    ) -> String {
        let prefix = String(text[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(text[commandRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty && !suffix.isEmpty else {
            return text
        }

        return "\(prefix)\(command.output)\(suffix)"
    }

    private static func applySpokenCodeCaseCommands(in text: String) -> String {
        var formattedText = text

        for command in spokenCodeCaseCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let fullRange = NSRange(formattedText.startIndex..., in: formattedText)
            let matches = regex.matches(in: formattedText, range: fullRange).reversed()

            for match in matches {
                guard match.numberOfRanges >= 2,
                      let commandRange = Range(match.range(at: 0), in: formattedText),
                      let phraseRange = Range(match.range(at: 1), in: formattedText),
                      shouldApplySpokenCodeCaseCommand(in: formattedText, commandRange: commandRange, phraseRange: phraseRange) else {
                    continue
                }

                let phrase = String(formattedText[phraseRange])
                let replacement = formatSpokenCodeCasePhrase(phrase, style: command.style)
                formattedText.replaceSubrange(commandRange.lowerBound..<phraseRange.upperBound, with: replacement)
            }
        }

        return formattedText
    }

    private static func shouldApplySpokenCodeCaseCommand(
        in text: String,
        commandRange: Range<String.Index>,
        phraseRange: Range<String.Index>
    ) -> Bool {
        let phraseWords = codeCaseWords(in: String(text[phraseRange]))
        guard let firstWord = phraseWords.first,
              !blockedFirstWordsForSpokenCodeCase.contains(firstWord),
              phraseWords.count <= 5 else {
            return false
        }

        let beforeCommand = String(text[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforeCommand.isEmpty else {
            return true
        }

        if let previousCharacter = beforeCommand.last,
           ".!?([{:\n".contains(previousCharacter) {
            return true
        }

        guard let previousWord = previousWord(in: beforeCommand) else {
            return false
        }
        return allowedPreviousWordsForSpokenCodeCase.contains(previousWord)
    }

    private static func formatSpokenCodeCasePhrase(_ phrase: String, style: SpokenCodeCaseStyle) -> String {
        let words = codeCaseWords(in: phrase)
        guard !words.isEmpty else { return normalizeWhitespace(phrase) }

        switch style {
        case .camel:
            return words.enumerated()
                .map { index, word in
                    index == 0 ? word : capitalizedCodeCaseWord(word)
                }
                .joined()
        case .snake:
            return words.joined(separator: "_")
        case .kebab:
            return words.joined(separator: "-")
        case .pascal:
            return words.map(capitalizedCodeCaseWord).joined()
        }
    }

    private static func codeCaseWords(in phrase: String) -> [String] {
        phrase
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
    }

    private static func capitalizedCodeCaseWord(_ word: String) -> String {
        guard let firstCharacter = word.first else { return word }
        return String(firstCharacter).uppercased() + word.dropFirst()
    }

    private static func applySpokenMarkdownCommands(in text: String) -> String {
        var formattedText = applySpokenMarkdownHeadings(in: text)
        formattedText = applySpokenMarkdownTasks(in: formattedText)
        formattedText = applySpokenMarkdownInlineCode(in: formattedText)
        formattedText = applySpokenMarkdownLinks(in: formattedText)
        formattedText = applySpokenMarkdownCodeBlocks(in: formattedText)
        return formattedText
    }

    private static func applySpokenMarkdownHeadings(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: markdownHeadingPattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let prefixRange = Range(match.range(at: 1), in: formattedText),
                  let levelRange = Range(match.range(at: 2), in: formattedText),
                  let titleRange = Range(match.range(at: 3), in: formattedText) else {
                continue
            }

            let prefix = String(formattedText[prefixRange])
            let marker = String(repeating: "#", count: markdownHeadingLevel(from: String(formattedText[levelRange])))
            let title = markdownLineContent(String(formattedText[titleRange]))
            guard !title.isEmpty,
                  shouldApplySpokenMarkdownLineCommand(to: title) else {
                continue
            }

            formattedText.replaceSubrange(fullRange, with: "\(prefix)\(marker) \(title)")
        }

        return formattedText
    }

    private static func markdownHeadingLevel(from text: String) -> Int {
        switch text.lowercased() {
        case "one", "1": return 1
        case "two", "2": return 2
        default: return 3
        }
    }

    private static func applySpokenMarkdownTasks(in text: String) -> String {
        let checkedText = applySpokenMarkdownTaskCommand(
            in: text,
            pattern: checkedMarkdownTaskPattern,
            state: .checked
        )
        return applySpokenMarkdownTaskCommand(
            in: checkedText,
            pattern: uncheckedMarkdownTaskPattern,
            state: .unchecked
        )
    }

    private static func applySpokenMarkdownTaskCommand(
        in text: String,
        pattern: String,
        state: SpokenMarkdownTaskState
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let prefixRange = Range(match.range(at: 1), in: formattedText),
                  let contentRange = Range(match.range(at: 2), in: formattedText) else {
                continue
            }

            let prefix = String(formattedText[prefixRange])
            let checkbox = state == .checked ? "[x]" : "[ ]"
            let content = markdownLineContent(String(formattedText[contentRange]))
            guard !content.isEmpty,
                  shouldApplySpokenMarkdownLineCommand(to: content) else {
                continue
            }

            formattedText.replaceSubrange(fullRange, with: "\(prefix)- \(checkbox) \(content)")
        }

        return formattedText
    }

    private static func applySpokenMarkdownInlineCode(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: inlineCodePattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let phraseRange = Range(match.range(at: 1), in: formattedText),
                  shouldApplySpokenInlineCodeCommand(in: formattedText, commandRange: fullRange, phraseRange: phraseRange) else {
                continue
            }

            let rawContent = String(formattedText[phraseRange])
            let content = inlineCodeContent(rawContent)
            guard !content.isEmpty else { continue }

            let terminalPunctuation = inlineCodeTerminalPunctuation(in: rawContent, fullText: formattedText, match: match)
            let beforeCommand = String(formattedText[..<fullRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldKeepTerminalPunctuation = !beforeCommand.isEmpty
            let replacement = shouldKeepTerminalPunctuation ? "`\(content)`\(terminalPunctuation)" : "`\(content)`"
            formattedText.replaceSubrange(fullRange, with: replacement)
        }

        return formattedText
    }

    private static func shouldApplySpokenInlineCodeCommand(
        in text: String,
        commandRange: Range<String.Index>,
        phraseRange: Range<String.Index>
    ) -> Bool {
        let words = codeCaseWords(in: String(text[phraseRange]))
        guard !words.isEmpty,
              words.count <= 4,
              !words.contains(where: isBlockedInlineCodeWord) else {
            return false
        }

        let beforeCommand = String(text[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforeCommand.isEmpty else {
            return words.count <= 3
        }

        if let previousCharacter = beforeCommand.last,
           ".!?([{:\n".contains(previousCharacter) {
            return true
        }

        guard let previousWord = previousWord(in: beforeCommand) else {
            return false
        }
        return allowedPreviousWordsForSpokenCodeCase.contains(previousWord) || previousWord == "write"
    }

    private static func isBlockedInlineCodeWord(_ word: String) -> Bool {
        blockedFirstWordsForSpokenCodeCase.contains(word) ||
            ["are", "example", "examples", "from", "into", "on"].contains(word)
    }

    private static func inlineCodeContent(_ text: String) -> String {
        let normalizedText = normalizeWhitespace(text)
        return removeTrailingFragmentPunctuation(from: normalizedText)
    }

    private static func inlineCodeTerminalPunctuation(
        in rawContent: String,
        fullText: String,
        match: NSTextCheckingResult
    ) -> String {
        guard match.numberOfRanges >= 3,
              let punctuationRange = Range(match.range(at: 2), in: fullText) else {
            return terminalPhrasePunctuation(in: rawContent)
        }

        let explicitPunctuation = String(fullText[punctuationRange])
        return explicitPunctuation.isEmpty ? terminalPhrasePunctuation(in: rawContent) : explicitPunctuation
    }

    private static func terminalPhrasePunctuation(in text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastCharacter = trimmedText.last,
              ".!?".contains(lastCharacter) else {
            return ""
        }
        return String(lastCharacter)
    }

    private static func applySpokenMarkdownLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: markdownLinkPattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 6,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let prefixRange = Range(match.range(at: 1), in: formattedText),
                  let labelRange = Range(match.range(at: 2), in: formattedText),
                  let targetRange = Range(match.range(at: 3), in: formattedText) else {
                continue
            }

            let label = markdownLinkLabel(String(formattedText[labelRange]))
            let target = markdownLinkTarget(String(formattedText[targetRange]))
            guard !label.isEmpty,
                  isMarkdownLinkTarget(target),
                  shouldApplySpokenMarkdownLineCommand(to: label) else {
                continue
            }

            let prefix = String(formattedText[prefixRange])
            let suffix = optionalMatchText(in: formattedText, match: match, rangeIndex: 4) ?? ""
            let terminalPunctuation = optionalMatchText(in: formattedText, match: match, rangeIndex: 5) ?? ""
            let trailingText = suffix.isEmpty ? "" : "\(suffix)\(terminalPunctuation)"
            formattedText.replaceSubrange(fullRange, with: "\(prefix)[\(label)](\(target))\(trailingText)")
        }

        return formattedText
    }

    private static func markdownLinkLabel(_ text: String) -> String {
        markdownLineContent(text)
    }

    private static func markdownLinkTarget(_ text: String) -> String {
        text.trimmingCharacters(
            in: CharacterSet(charactersIn: ".!?,;:… ")
                .union(.whitespacesAndNewlines)
        )
    }

    private static func isMarkdownLinkTarget(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        return lowercasedText.hasPrefix("http://") ||
            lowercasedText.hasPrefix("https://") ||
            lowercasedText.hasPrefix("www.") ||
            lowercasedText.hasPrefix("#") ||
            text.contains(".") ||
            text.contains("/")
    }

    private static func applySpokenMarkdownCodeBlocks(in text: String) -> String {
        var formattedText = replaceCodeBlockCommand(
            in: text,
            pattern: openCodeBlockPattern,
            isOpeningFence: true
        )
        formattedText = replaceCodeBlockCommand(
            in: formattedText,
            pattern: closeCodeBlockPattern,
            isOpeningFence: false
        )
        return formattedText
    }

    private static func replaceCodeBlockCommand(
        in text: String,
        pattern: String,
        isOpeningFence: Bool
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let prefixRange = Range(match.range(at: 1), in: formattedText) else {
                continue
            }

            let prefix = String(formattedText[prefixRange])
            let language = codeBlockLanguage(in: formattedText, match: match)
            let fence = isOpeningFence ? "```\(language)" : "```"
            formattedText.replaceSubrange(fullRange, with: "\(prefix)\(fence)")
        }

        return formattedText
    }

    private static func codeBlockLanguage(in text: String, match: NSTextCheckingResult) -> String {
        guard match.numberOfRanges >= 3,
              let languageRange = Range(match.range(at: 2), in: text) else {
            return ""
        }

        let language = String(text[languageRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return language.isEmpty ? "" : language
    }

    private static func markdownLineContent(_ text: String) -> String {
        let normalizedText = normalizeWhitespace(text)
        return removeTrailingFragmentPunctuation(from: normalizedText)
    }

    private static func shouldApplySpokenMarkdownLineCommand(to content: String) -> Bool {
        guard let firstWord = codeCaseWords(in: content).first else {
            return false
        }

        return !blockedFirstWordsForSpokenCodeCase.contains(firstWord)
    }

    private static func applySpokenPunctuationCommands(in text: String) -> String {
        var punctuatedText = text

        for command in spokenPunctuationCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let fullRange = NSRange(punctuatedText.startIndex..., in: punctuatedText)
            let matches = regex.matches(in: punctuatedText, range: fullRange).reversed()

            for match in matches {
                guard let range = Range(match.range, in: punctuatedText),
                      shouldApplySpokenPunctuationCommand(command, in: punctuatedText, commandRange: range) else {
                    continue
                }

                punctuatedText = replaceSpokenPunctuationCommand(command, in: punctuatedText, commandRange: range)
            }
        }

        return normalizePunctuationSpacing(punctuatedText)
    }

    private static func shouldApplySpokenPunctuationCommand(
        _ command: SpokenPunctuationCommand,
        in text: String,
        commandRange: Range<String.Index>
    ) -> Bool {
        let beforeCommand = String(text[..<commandRange.lowerBound])
        let afterCommand = String(text[commandRange.upperBound...])

        guard let previousWord = previousWordBeforeSpokenPunctuationCommand(in: beforeCommand) else { return false }

        if command.blockedPreviousWords.contains(previousWord) {
            return false
        }

        if let nextWord = nextWord(in: afterCommand),
           command.blockedNextWords.contains(nextWord) {
            return false
        }

        return true
    }

    private static func replaceSpokenPunctuationCommand(
        _ command: SpokenPunctuationCommand,
        in text: String,
        commandRange: Range<String.Index>
    ) -> String {
        let prefix = String(text[..<commandRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(text[commandRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !suffix.isEmpty else {
            return prefix + command.output
        }

        if let suffixWithoutAutoPunctuation = suffixDroppingLeadingPhrasePunctuation(from: suffix) {
            guard !suffixWithoutAutoPunctuation.isEmpty else {
                return prefix + command.output
            }
            if let firstSuffixCharacter = suffixWithoutAutoPunctuation.first,
               firstSuffixCharacter.isWhitespace || firstSuffixCharacter.isNewline {
                return prefix + command.output + suffixWithoutAutoPunctuation
            }
            return "\(prefix)\(command.output) \(suffixWithoutAutoPunctuation)"
        }

        if let firstSuffixCharacter = suffix.first,
           firstSuffixCharacter.isPunctuation || firstSuffixCharacter.isNewline {
            return prefix + command.output + suffix
        }

        return "\(prefix)\(command.output) \(suffix)"
    }

    private static func suffixDroppingLeadingPhrasePunctuation(from text: String) -> String? {
        var suffixStart = text.startIndex
        var didDropPunctuation = false

        while suffixStart < text.endIndex,
              character(text[suffixStart], isIn: phraseBoundaryPunctuation) {
            didDropPunctuation = true
            suffixStart = text.index(after: suffixStart)
        }

        guard didDropPunctuation else { return nil }
        return String(text[suffixStart...])
    }

    private static func formatInlineNumberedLists(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: inlineNumberedListMarkerPattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count >= 2 else { return text }

        var formattedText = ""
        var currentIndex = text.startIndex

        for match in matches {
            guard let markerRange = Range(match.range, in: text),
                  markerRange.lowerBound > currentIndex else {
                continue
            }

            let previousIndex = text.index(before: markerRange.lowerBound)
            if text[previousIndex].isNewline { continue }

            let whitespaceStart = precedingWhitespaceStart(in: text, before: markerRange.lowerBound)
            formattedText += String(text[currentIndex..<whitespaceStart])
            formattedText += "\n"
            currentIndex = markerRange.lowerBound
        }

        guard currentIndex > text.startIndex else { return text }
        formattedText += String(text[currentIndex...])
        return formattedText
    }

    private static func precedingWhitespaceStart(in text: String, before index: String.Index) -> String.Index {
        var whitespaceStart = index
        while whitespaceStart > text.startIndex {
            let previousIndex = text.index(before: whitespaceStart)
            guard text[previousIndex].isWhitespace, !text[previousIndex].isNewline else {
                break
            }
            whitespaceStart = previousIndex
        }
        return whitespaceStart
    }

    private static func normalizePunctuationSpacing(_ text: String) -> String {
        let protectedText = protectURLSpans(in: text)
        let punctuatedText = normalizeDuplicatePhrasePunctuation(protectedText.text)
        let spacedText = punctuatedText
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,.;:!?])([^\s,.;:!?\]\)}"”’])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([)\]\}])"#, with: "$1", options: .regularExpression)

        let normalizedText = spacedText
            .replacingOccurrences(
            of: #"(\d)\.\s+(?=\d)"#,
            with: "$1.",
            options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(\b\d{1,2}):\s+(\d{2}\s+(?:AM|PM)\b)"#,
                with: "$1:$2",
                options: .regularExpression
            )

        return restoreProtectedURLSpans(in: normalizedText, urls: protectedText.urls)
    }

    private static func normalizeDuplicatePhrasePunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"([,;:!?])\1+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[,;:]+([.!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([.!?])[,;:]+"#, with: "$1", options: .regularExpression)
    }

    private static func protectURLSpans(in text: String) -> (text: String, urls: [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:https?://|www\.)[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"#
        ) else {
            return (text, [])
        }

        var protectedText = text
        var urls: [String] = []
        let matches = regex.matches(in: protectedText, range: NSRange(protectedText.startIndex..., in: protectedText))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: protectedText) else {
                continue
            }

            urls.append(String(protectedText[range]))
            protectedText.replaceSubrange(range, with: "__VOICEINK_URL_\(urls.count - 1)__")
        }

        return (protectedText, urls)
    }

    private static func restoreProtectedURLSpans(in text: String, urls: [String]) -> String {
        var restoredText = text
        for (index, url) in urls.enumerated() {
            restoredText = restoredText.replacingOccurrences(of: "__VOICEINK_URL_\(index)__", with: url)
        }
        return restoredText
    }

    private static func previousWord(in text: String) -> String? {
        let endIndex = indexBeforeTrailingNoise(in: text, from: text.endIndex)
        guard endIndex > text.startIndex else { return nil }

        var wordStart = endIndex
        while wordStart > text.startIndex {
            let previousIndex = text.index(before: wordStart)
            guard isWordCharacter(text[previousIndex]) else { break }
            wordStart = previousIndex
        }

        guard wordStart < endIndex else { return nil }
        return String(text[wordStart..<endIndex]).lowercased()
    }

    private static func previousWordBeforeSpokenPunctuationCommand(in text: String) -> String? {
        let endIndex = indexBeforeTrailingPhraseNoise(in: text, from: text.endIndex)
        guard endIndex > text.startIndex else { return nil }

        var wordStart = endIndex
        while wordStart > text.startIndex {
            let previousIndex = text.index(before: wordStart)
            guard isWordCharacter(text[previousIndex]) else { break }
            wordStart = previousIndex
        }

        guard wordStart < endIndex else { return nil }
        return String(text[wordStart..<endIndex]).lowercased()
    }

    private static func firstWord(in text: String) -> String? {
        var index = text.startIndex
        while index < text.endIndex, !isWordCharacter(text[index]) {
            index = text.index(after: index)
        }

        guard index < text.endIndex else { return nil }

        let wordStart = index
        while index < text.endIndex, isWordCharacter(text[index]) {
            index = text.index(after: index)
        }

        return String(text[wordStart..<index]).lowercased()
    }

    private static func nextWord(in text: String) -> String? {
        var index = text.startIndex
        while index < text.endIndex {
            let currentCharacter = text[index]
            if currentCharacter.isWhitespace || character(currentCharacter, isIn: softPhrasePunctuation) {
                index = text.index(after: index)
                continue
            }
            break
        }

        guard index < text.endIndex else { return nil }
        let wordStart = index
        while index < text.endIndex, isWordCharacter(text[index]) {
            index = text.index(after: index)
        }

        guard wordStart < index else { return nil }
        return String(text[wordStart..<index]).lowercased()
    }

    private static func normalizeSpokenFormattingSpacing(_ text: String) -> String {
        let formattedText = text
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}(?=- )"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n-\s*"#, with: "\n- ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*-\s*"#, with: "- ", options: .regularExpression)

        return formattedText.replacingOccurrences(
            of: #"(?m)^(-\s+\S+(?:\s+\S+){0,2})\.$"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private static func applyBacktrackingCorrections(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: backtrackingMarkerPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            let matches = regex.matches(in: correctedText, range: fullRange)
            var nextText: String?

            for match in matches {
                guard let matchRange = Range(match.range, in: correctedText),
                      let rewrittenText = rewriteBacktrackingMatch(in: correctedText, markerRange: matchRange),
                      rewrittenText != correctedText else {
                    continue
                }

                nextText = rewrittenText
                break
            }

            guard let nextText else {
                break
            }

            correctedText = nextText
            rewriteCount += 1
        }

        return applyScratchThatCommands(in: correctedText)
    }

    private static func rewriteBacktrackingMatch(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard let correction = leadingCorrectionPhrase(in: afterMarker) else {
            return nil
        }

        let correctionText = String(afterMarker[correction.range])
        guard shouldApplyBacktrackingMarker(
            String(text[markerRange]),
            beforeMarker: beforeMarker,
            correctionText: correctionText
        ),
              let prefix = removeTrailingWords(correction.wordCount, from: beforeMarker) else {
            return nil
        }

        let suffix = String(afterMarker[correction.range.upperBound...])
        return normalizeBacktrackingWhitespace(join(prefix, correctionText, suffix))
    }

    private static func shouldApplyBacktrackingMarker(
        _ markerText: String,
        beforeMarker: String,
        correctionText: String
    ) -> Bool {
        guard isReplaceThatBacktrackingMarker(markerText) else {
            return true
        }

        if let previousWord = previousWord(in: beforeMarker),
           blockedPreviousWordsForReplaceThat.contains(previousWord) {
            return false
        }

        if let firstCorrectionWord = firstWord(in: correctionText),
           blockedFirstCorrectionWordsForReplaceThat.contains(firstCorrectionWord) {
            return false
        }

        return true
    }

    private static func isReplaceThatBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizeWhitespace(markerText)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))
            .lowercased()
        return normalizedMarker == "replace that with" || normalizedMarker == "change that to"
    }

    private static func applyScratchThatCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: scratchThatCommandPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            guard let match = regex.firstMatch(in: correctedText, range: fullRange),
                  let markerRange = Range(match.range, in: correctedText),
                  let rewrittenText = rewriteScratchThatCommand(in: correctedText, markerRange: markerRange),
                  rewrittenText != correctedText else {
                break
            }

            correctedText = rewrittenText
            rewriteCount += 1
        }

        return correctedText
    }

    private static func rewriteScratchThatCommand(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard let prefix = removeTrailingScratchPhrase(from: beforeMarker) else {
            return nil
        }

        return normalizeBacktrackingWhitespace(join(prefix, "", afterMarker))
    }

    private static func removeTrailingScratchPhrase(from text: String) -> String? {
        let endIndex = indexBeforeTrailingNoise(in: text, from: text.endIndex)
        guard endIndex > text.startIndex else { return nil }

        var phraseStart = endIndex
        while phraseStart > text.startIndex {
            let previousIndex = text.index(before: phraseStart)
            let previousCharacter = text[previousIndex]
            if previousCharacter == "\n" || character(previousCharacter, isIn: phraseBoundaryPunctuation) {
                break
            }
            phraseStart = previousIndex
        }

        let phrase = String(text[phraseStart..<endIndex])
        let removedWordCount = wordCount(in: phrase)
        guard removedWordCount > 0,
              removedWordCount <= maxScratchThatWords else {
            return nil
        }

        var prefix = String(text[..<phraseStart])
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        prefix = prefix.trimmingCharacters(in: softPhrasePunctuation)
        return prefix
    }

    private static func leadingCorrectionPhrase(in text: String) -> (range: Range<String.Index>, wordCount: Int)? {
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        let start = index
        var end = index
        var wordCount = 0

        while index < text.endIndex, wordCount < maxBacktrackingCorrectionWords {
            if character(text[index], isIn: phraseBoundaryPunctuation) {
                break
            }

            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }

            guard index < text.endIndex,
                  isWordCharacter(text[index]) else {
                break
            }

            while index < text.endIndex, isWordCharacter(text[index]) {
                index = text.index(after: index)
            }

            end = index
            wordCount += 1

            let lookahead = text[index...].drop(while: \.isWhitespace)
            guard let nextCharacter = lookahead.first,
                  !character(nextCharacter, isIn: phraseBoundaryPunctuation) else {
                break
            }
        }

        guard wordCount > 0 else { return nil }
        return (start..<end, wordCount)
    }

    private static func removeTrailingWords(_ wordCount: Int, from text: String) -> String? {
        guard wordCount > 0 else { return text }

        var startOfRemovedWords = text.endIndex
        var wordsRemoved = 0

        while wordsRemoved < wordCount {
            startOfRemovedWords = indexBeforeTrailingNoise(in: text, from: startOfRemovedWords)
            guard startOfRemovedWords > text.startIndex else { return nil }

            var wordStart = startOfRemovedWords
            while wordStart > text.startIndex {
                let previousIndex = text.index(before: wordStart)
                guard isWordCharacter(text[previousIndex]) else { break }
                wordStart = previousIndex
            }

            guard wordStart < startOfRemovedWords else { return nil }
            startOfRemovedWords = wordStart
            wordsRemoved += 1
        }

        var prefix = String(text[..<startOfRemovedWords])
        prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        prefix = prefix.trimmingCharacters(in: softPhrasePunctuation)
        return prefix
    }

    private static func indexBeforeTrailingNoise(in text: String, from endIndex: String.Index) -> String.Index {
        var index = endIndex
        while index > text.startIndex {
            let previousIndex = text.index(before: index)
            let previousCharacter = text[previousIndex]
            if previousCharacter.isWhitespace || character(previousCharacter, isIn: softPhrasePunctuation) {
                index = previousIndex
                continue
            }
            break
        }

        return index
    }

    private static func indexBeforeTrailingPhraseNoise(in text: String, from endIndex: String.Index) -> String.Index {
        var index = endIndex
        while index > text.startIndex {
            let previousIndex = text.index(before: index)
            let previousCharacter = text[previousIndex]
            if previousCharacter.isWhitespace || character(previousCharacter, isIn: phraseBoundaryPunctuation) {
                index = previousIndex
                continue
            }
            break
        }

        return index
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter ||
            character.isNumber ||
            character.unicodeScalars.allSatisfy { wordConnectorCharacters.contains($0) }
    }

    private static func character(_ character: Character, isIn characterSet: CharacterSet) -> Bool {
        character.unicodeScalars.allSatisfy { characterSet.contains($0) }
    }

    private static func join(_ prefix: String, _ correction: String, _ suffix: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrection = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)

        var pieces: [String] = []
        if !trimmedPrefix.isEmpty { pieces.append(trimmedPrefix) }
        if !trimmedCorrection.isEmpty { pieces.append(trimmedCorrection) }

        let base = pieces.joined(separator: " ")
        guard !trimmedSuffix.isEmpty else { return base }
        if let firstSuffixCharacter = trimmedSuffix.first,
           firstSuffixCharacter.isPunctuation {
            return base + trimmedSuffix
        }
        return base.isEmpty ? trimmedSuffix : "\(base) \(trimmedSuffix)"
    }

    private static func normalizeBacktrackingWhitespace(_ text: String) -> String {
        normalizeWhitespace(text)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([([{])\s+"#, with: "$1", options: .regularExpression)
    }

    private static func unwrapSquareBracketedWholeOutput(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let last = trimmedText.last,
              first == "[",
              last == "]" else {
            return text
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        let innerText = String(trimmedText[innerStart..<innerEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !innerText.isEmpty else { return "" }

        let normalizedInner = innerText
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;:… ").union(.whitespacesAndNewlines))
            .lowercased()
        if nonSpeechBracketContents.contains(normalizedInner) {
            return ""
        }

        return innerText
    }

    private static func collapseAdjacentRepeatedWords(in text: String) -> String {
        let parts = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var previousNormalizedWord: String?

        for part in parts {
            guard let normalizedWord = normalizedRepeatWord(part) else {
                result.append(part)
                previousNormalizedWord = nil
                continue
            }

            if normalizedWord == previousNormalizedWord,
               !preservedRepeatedWords.contains(normalizedWord) {
                continue
            }

            result.append(part)
            previousNormalizedWord = normalizedWord
        }

        return result.joined(separator: " ")
    }

    private static func collapseRepeatedShortSentences(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(^|(?<=[.!?])\s+)([^.!?\n]{3,120}[.!?])\s+\2(?=\s|$)"#
        ) else {
            return text
        }

        var collapsedText = text
        var rewriteCount = 0

        while rewriteCount < 4 {
            let range = NSRange(collapsedText.startIndex..., in: collapsedText)
            let matches = regex.matches(in: collapsedText, range: range).reversed()
            var didRewrite = false

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let fullRange = Range(match.range, in: collapsedText),
                      let prefixRange = Range(match.range(at: 1), in: collapsedText),
                      let sentenceRange = Range(match.range(at: 2), in: collapsedText) else {
                    continue
                }

                let sentence = String(collapsedText[sentenceRange])
                let sentenceWordCount = wordCount(in: sentence)
                guard sentenceWordCount >= 2 && sentenceWordCount <= 12 else {
                    continue
                }

                collapsedText.replaceSubrange(
                    fullRange,
                    with: String(collapsedText[prefixRange]) + sentence
                )
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return collapsedText
    }

    private static func collapseRepeatedShortPhrases(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(^|(?<=[.!?])\s+|\n)((?:[^\s,;:.!?\n]+[ \t]+){1,4}[^\s,;:.!?\n]+)[ \t]+\2(?=[ \t]+[^\s,;:.!?\n]+|[.!?]|\s*$)"#
        ) else {
            return text
        }

        var collapsedText = text
        var rewriteCount = 0

        while rewriteCount < 4 {
            let range = NSRange(collapsedText.startIndex..., in: collapsedText)
            let matches = regex.matches(in: collapsedText, range: range).reversed()
            var didRewrite = false

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let fullRange = Range(match.range, in: collapsedText),
                      let prefixRange = Range(match.range(at: 1), in: collapsedText),
                      let phraseRange = Range(match.range(at: 2), in: collapsedText) else {
                    continue
                }

                let phrase = String(collapsedText[phraseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let phraseWordCount = wordCount(in: phrase)
                guard phraseWordCount >= 2 && phraseWordCount <= 5,
                      !preservedRepeatedClauses.contains(normalizedRepeatedClause(phrase)) else {
                    continue
                }

                collapsedText.replaceSubrange(
                    fullRange,
                    with: String(collapsedText[prefixRange]) + phrase
                )
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return collapsedText
    }

    private static func collapseRepeatedShortClauses(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(^|(?<=[.!?])\s+|\n)([^,;:.!?\n]{5,120}?)[ \t]*[,;:][ \t]+\2(?=[.!?]|\s|$)"#
        ) else {
            return text
        }

        var collapsedText = text
        var rewriteCount = 0

        while rewriteCount < 4 {
            let range = NSRange(collapsedText.startIndex..., in: collapsedText)
            let matches = regex.matches(in: collapsedText, range: range).reversed()
            var didRewrite = false

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let fullRange = Range(match.range, in: collapsedText),
                      let prefixRange = Range(match.range(at: 1), in: collapsedText),
                      let clauseRange = Range(match.range(at: 2), in: collapsedText) else {
                    continue
                }

                let clause = String(collapsedText[clauseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let clauseWordCount = wordCount(in: clause)
                guard clauseWordCount >= 2 && clauseWordCount <= 12,
                      !preservedRepeatedClauses.contains(normalizedRepeatedClause(clause)) else {
                    continue
                }

                collapsedText.replaceSubrange(
                    fullRange,
                    with: String(collapsedText[prefixRange]) + clause
                )
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return collapsedText
    }

    private static func normalizedRepeatWord(_ token: String) -> String? {
        let trimmedToken = token.trimmingCharacters(
            in: CharacterSet.punctuationCharacters
                .union(.symbols)
                .union(.whitespacesAndNewlines)
        )
        guard !trimmedToken.isEmpty,
              trimmedToken.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }

        return trimmedToken.lowercased()
    }

    private static func normalizedRepeatedClause(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func stripBoundaryNoise(from text: String) -> String {
        var strippedText = unwrapSquareBracketedWholeOutput(text)
        guard isShortFragment(strippedText) else { return strippedText }

        if hasPreservedBalancedBoundary(strippedText) ||
            hasPreservedBalancedBoundary(removeTrailingFragmentPunctuation(from: strippedText)) {
            return normalizeWhitespace(strippedText)
        }

        let boundaryCharacters = CharacterSet(charactersIn: #"[]{}()"“”‘’'"`"#)
        strippedText = strippedText.trimmingCharacters(in: boundaryCharacters.union(.whitespacesAndNewlines))
        return normalizeWhitespace(strippedText)
    }

    private static func hasPreservedBalancedBoundary(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let last = trimmedText.last,
              let expectedClosing = preservedClosingBoundary(for: first),
              expectedClosing == last else {
            return false
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        return !trimmedText[innerStart..<innerEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private static func preservedClosingBoundary(for opening: Character) -> Character? {
        switch opening {
        case "\"": return "\""
        case "'": return "'"
        case "“": return "”"
        case "‘": return "’"
        case "(": return ")"
        case "{": return "}"
        default: return nil
        }
    }

    private static func removeTrailingFragmentPunctuation(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingFragmentPunctuation.contains(lastScalar) {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeTrailingShortFragmentPunctuation(from text: String) -> String {
        var result = removeTrailingFragmentPunctuation(from: text)
        result = removeTrailingSpacedFragmentSymbols(from: result)
        result = removeTrailingSentenceFragmentPunctuationInsidePreservedBoundary(from: result)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingSentenceFragmentPunctuation.contains(lastScalar),
              isLikelyPunctuatedShortFragment(result) {
            result.removeLast()
        }
        return result
    }

    private static func removeTrailingSpacedFragmentSymbols(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastCharacter = result.last,
              removableTrailingSpacedFragmentSymbols.contains(lastCharacter) {
            let symbolIndex = result.index(before: result.endIndex)
            let prefix = result[..<symbolIndex]
            guard prefix.last?.isWhitespace == true else {
                return result
            }
            result = String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func removeTrailingSentenceFragmentPunctuationInsidePreservedBoundary(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let closing = preservedClosingBoundary(for: first),
              trimmedText.last == closing else {
            return text
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        let innerText = String(trimmedText[innerStart..<innerEnd])
        guard isLikelyPunctuatedShortFragment(innerText) else {
            return text
        }

        let cleanedInnerText = removeTrailingShortFragmentPunctuation(from: innerText)
        return "\(first)\(cleanedInnerText)\(closing)"
    }

    private static func isShortFragment(_ text: String) -> Bool {
        let textWithoutTrailingFragmentPunctuation = removeTrailingFragmentPunctuation(from: text)
        if isShortPreservedBoundaryFragment(textWithoutTrailingFragmentPunctuation) {
            return true
        }

        let sentencePunctuation = CharacterSet(charactersIn: "!?")
        if textWithoutTrailingFragmentPunctuation.unicodeScalars.contains(where: { sentencePunctuation.contains($0) }) {
            return isLikelyPunctuatedShortFragment(textWithoutTrailingFragmentPunctuation) ||
                isLikelyPunctuatedShortFragmentInsidePreservedBoundary(textWithoutTrailingFragmentPunctuation)
        }

        return wordCount(in: textWithoutTrailingFragmentPunctuation) <= 3
    }

    private static func isShortPreservedBoundaryFragment(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasPreservedBalancedBoundary(trimmedText) else { return false }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        return wordCount(in: String(trimmedText[innerStart..<innerEnd])) <= 3
    }

    private static func isSingleWordFinalFragment(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(
            in: removableTrailingFragmentPunctuation
                .union(removableTrailingSentenceFragmentPunctuation)
                .union(.whitespacesAndNewlines)
        )
        guard !trimmedText.isEmpty else { return false }

        if hasPreservedBalancedBoundary(trimmedText) {
            let innerStart = trimmedText.index(after: trimmedText.startIndex)
            let innerEnd = trimmedText.index(before: trimmedText.endIndex)
            return wordCount(in: String(trimmedText[innerStart..<innerEnd])) == 1
        }

        return wordCount(in: trimmedText) == 1
    }

    private static func isLikelyPunctuatedShortFragmentInsidePreservedBoundary(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let closing = preservedClosingBoundary(for: first),
              trimmedText.last == closing else {
            return false
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        return isLikelyPunctuatedShortFragment(String(trimmedText[innerStart..<innerEnd]))
    }

    private static func isLikelyPunctuatedShortFragment(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastScalar = trimmedText.unicodeScalars.last,
              removableTrailingSentenceFragmentPunctuation.contains(lastScalar) else {
            return false
        }

        let baseText = trimmedText.trimmingCharacters(
            in: removableTrailingSentenceFragmentPunctuation.union(.whitespacesAndNewlines)
        )
        guard wordCount(in: baseText) == 1 else { return false }

        let normalizedText = normalizedRepeatedClause(baseText)
        guard !preservedSingleWordQuestionFragments.contains(normalizedText) else {
            return false
        }
        return likelyLowercaseFragments.contains(normalizedText)
    }

    private static func wordCount(in text: String) -> Int {
        let words = text.split { character in
            character.isWhitespace || character.isPunctuation
        }
        return words.count
    }

    private static func isContinuingSentence(after precedingText: String) -> Bool {
        let linePrefix = currentLinePrefix(in: precedingText)
        let trimmedText = linePrefix.trimmingCharacters(in: .whitespaces)
        guard let lastCharacter = trimmedText.last else { return false }

        if ".!?。！？".contains(lastCharacter) {
            return false
        }

        return true
    }

    private static func currentLinePrefix(in text: String) -> String {
        guard let lastNewlineIndex = text.lastIndex(where: \.isNewline) else {
            return text
        }

        return String(text[text.index(after: lastNewlineIndex)...])
    }

    private static func lowercaseInitialWordIfSafe(in text: String, force: Bool) -> String {
        guard let firstLetterRange = text.rangeOfCharacter(from: .letters) else {
            return text
        }

        let suffixFromFirstLetter = text[firstLetterRange.lowerBound...]
        guard let firstWordEnd = suffixFromFirstLetter.firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }) else {
            return lowercaseInitialWordIfSafe(in: text, firstLetterRange: firstLetterRange, firstWordEnd: text.endIndex, force: force)
        }

        return lowercaseInitialWordIfSafe(in: text, firstLetterRange: firstLetterRange, firstWordEnd: firstWordEnd, force: force)
    }

    private static func lowercaseInitialWordIfSafe(
        in text: String,
        firstLetterRange: Range<String.Index>,
        firstWordEnd: String.Index,
        force: Bool
    ) -> String {
        let firstWordRange = firstLetterRange.lowerBound..<firstWordEnd
        let firstWord = String(text[firstWordRange])
        guard shouldLowercaseInitialWord(firstWord, force: force) else {
            return text
        }

        var result = text
        result.replaceSubrange(firstLetterRange, with: String(text[firstLetterRange]).lowercased())
        return result
    }

    private static func shouldLowercaseInitialWord(_ word: String, force: Bool) -> Bool {
        guard let firstCharacter = word.first, firstCharacter.isUppercase else {
            return false
        }

        if word == "I" { return false }
        if word.count > 1 && word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return false }
        if word.dropFirst().contains(where: { $0.isUppercase }) { return false }

        if force { return true }
        return likelyLowercaseFragments.contains(word.lowercased())
    }

    private static func needsLeadingSpace(before text: String, context: TextInsertionContext) -> Bool {
        guard context.selectedText?.isEmpty != false,
              let previousCharacter = context.precedingText.last,
              let firstCharacter = text.first else {
            return false
        }

        if previousCharacter.isWhitespace || firstCharacter.isWhitespace {
            return false
        }

        let noLeadingSpaceBefore = CharacterSet(charactersIn: ".,;:!?)]}/\\-")
        if firstCharacter.unicodeScalars.allSatisfy({ noLeadingSpaceBefore.contains($0) }) {
            return false
        }

        let noLeadingSpaceAfter = CharacterSet(charactersIn: "([{`'\"“‘/")
        if previousCharacter.unicodeScalars.allSatisfy({ noLeadingSpaceAfter.contains($0) }) {
            return false
        }

        let leadingSpaceAfter = CharacterSet(charactersIn: ".,;:!?)]}")
        return previousCharacter.isLetter ||
            previousCharacter.isNumber ||
            previousCharacter.unicodeScalars.allSatisfy { leadingSpaceAfter.contains($0) }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = RomaPunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        return applyCleanupPreferences(text, punctuationMode: punctuationMode, shouldLowercase: shouldLowercase)
    }

    public static func applyCleanupPreferences(
        _ text: String,
        punctuationMode: RomaPunctuationCleanupMode,
        shouldLowercase: Bool
    ) -> String {
        guard punctuationMode != .keep || shouldLowercase else {
            return text
        }

        var cleanedText = text
        switch punctuationMode {
        case .keep:
            break
        case .removeAll:
            cleanedText = removePunctuation(from: cleanedText)
        case .removeTrailingPeriod:
            cleanedText = removeTrailingPeriod(from: cleanedText)
        }

        if shouldLowercase {
            cleanedText = cleanedText.lowercased()
        }

        return cleanedText
    }

    public static func removeTrailingPeriod(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let trailingWhitespace = text.reversed().prefix { $0.isWhitespace }
        let trimmedEndIndex = text.index(text.endIndex, offsetBy: -trailingWhitespace.count)
        guard trimmedEndIndex > text.startIndex else { return text }

        let lastCharIndex = text.index(before: trimmedEndIndex)
        guard text[lastCharIndex] == "." else { return text }

        if lastCharIndex > text.startIndex {
            let previousCharIndex = text.index(before: lastCharIndex)
            guard text[previousCharIndex] != "." else { return text }
        }

        var result = text
        result.remove(at: lastCharIndex)
        return result
    }

    public static func removePunctuation(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let punctuationSeparators = CharacterSet.punctuationCharacters.subtracting(apostropheLikeCharacters)
        let cleanedScalars = text.unicodeScalars.map { scalar -> String in
            if apostropheLikeCharacters.contains(scalar) {
                return ""
            }

            if punctuationSeparators.contains(scalar) {
                return " "
            }

            return String(scalar)
        }

        return normalizeWhitespace(cleanedScalars.joined())
    }
}
