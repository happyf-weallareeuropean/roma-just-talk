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

    private struct WordToken {
        let text: String
        let range: Range<String.Index>
    }

    private struct SpokenDateCandidate {
        let wordCount: Int
        let dayWordCount: Int
        let yearWord: String?
    }

    private enum SpokenAmountUnitPlacement {
        case prefix
        case suffix
    }

    private struct SpokenAmountCandidate {
        let wordCount: Int
        let unitText: String
        let unitPlacement: SpokenAmountUnitPlacement
    }

    private struct SpokenCompactConnector {
        let wordCount: Int
        let output: String
    }

    private struct SpokenCompactConnectorSuffix {
        let wordCount: Int
        let previousWord: String
    }

    private struct SpokenCodeCaseTail {
        let argumentWordCount: Int
    }

    private struct SpokenTextCaseTail {
        let wordCount: Int
        let style: SpokenTextCaseStyle
    }

    private enum SpokenMarkdownCommandKind {
        case line
        case inlineCode
    }

    private struct SpokenMarkdownCommand {
        let wordCount: Int
        let maxArgumentWordCount: Int
        let kind: SpokenMarkdownCommandKind
    }

    private struct SpokenMarkdownTail {
        let argumentWordCount: Int
        let maxCorrectionWordCount: Int
        let kind: SpokenMarkdownCommandKind
    }

    private struct SpokenMarkdownTaskCommandMatch {
        let range: Range<String.Index>
        let state: SpokenMarkdownTaskState
    }

    private struct SpokenMarkdownLinkTail {
        let wordCount: Int
        let commandText: String
        let labelText: String
        let targetText: String
    }

    private enum SpokenCodeCaseStyle {
        case camel
        case snake
        case kebab
        case pascal
    }

    private enum SpokenTextCaseStyle {
        case allCaps
        case lowercase
        case capitalize
        case title
    }

    private struct SpokenCodeCaseCommand {
        let pattern: String
        let style: SpokenCodeCaseStyle
    }

    private struct SpokenTextCaseCommand {
        let pattern: String
        let style: SpokenTextCaseStyle
    }

    private struct GuardedSpokenFormattingCommand {
        let pattern: String
        let replacement: String
        let blockedPreviousWords: Set<String>
        let blockedNextWords: Set<String>

        init(
            pattern: String,
            replacement: String,
            blockedPreviousWords: Set<String> = [],
            blockedNextWords: Set<String> = []
        ) {
            self.pattern = pattern
            self.replacement = replacement
            self.blockedPreviousWords = blockedPreviousWords
            self.blockedNextWords = blockedNextWords
        }
    }

    private struct SpokenSequenceListMarker {
        let range: Range<String.Index>
        let value: Int
    }

    private enum SpokenMarkdownTaskState {
        case unchecked
        case checked
    }

    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
    private static let maxInsertionContextCharacters = 512
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")
    private static let removableLeadingPausePunctuation = CharacterSet(charactersIn: ".…")
    private static let removableLeadingFragmentPunctuation = CharacterSet(charactersIn: ".,;:…-–—。．，、；：")
    private static let removableTrailingFragmentPunctuation = CharacterSet(charactersIn: ".,;:…-–—。．，、；：")
    private static let removableTrailingSentenceFragmentPunctuation = CharacterSet(charactersIn: "!?！？")
    private static let removableLeadingSpacedFragmentSymbols = "/\\|•‣◦"
    private static let removableTrailingSpacedFragmentSymbols = "/\\|"
    private static let removableOpeningNonASCIIBoundaryWrappers = CharacterSet(charactersIn: "【《〈（｛［「『〔")
    private static let nonSpeechBracketContents: Set<String> = [
        "ambient noise", "applause", "background music", "background noise",
        "background sound", "background sounds", "beep", "beeping",
        "blank audio", "breath", "breathing", "clapping", "cough", "coughing",
        "crosstalk", "foreign language", "inaudible", "indistinct", "keyboard typing",
        "empty audio", "hum", "humming", "laughter", "laughing", "laughs",
        "mumble", "mumbling", "music", "noise",
        "no audio", "no sound", "no speech", "overlap", "overlapping",
        "phone ringing", "ringing", "sigh", "sighing", "silence", "silent",
        "sneeze", "sneezing", "sound", "speaking foreign language", "static",
        "typing", "unclear", "unintelligible"
    ]
    private static let unbracketedNonSpeechDescriptorPattern = #"""
        (?ix)
        (?:^|(?<=[.!?]\s))
        \s*
        (?:
            ambient\s+noise |
            applause | background\s+(?:chatter|conversation|music|noise|sounds?|speech|voices) |
            beep(?:ing)? | breath(?:ing|es)? | clapping |
            clears?\s+(?:his\s+|her\s+|their\s+)?throat | clearing\s+throat |
            coughs? | coughing | crowd\s+(?:applause|chatter|noise|talking) |
            foreign\s+language |
            keyboard\s+typing |
            hum(?:ming)? | inaudible | indistinct | laugh(?:s|ing)? | laughter |
            mumbles? | mumbling | music\s+playing | no\s+(?:audio|sound|speech) |
            phone\s+ringing |
            sighs? | sighing | silence | silent | sneezes? | sneezing |
            speaking\s+foreign\s+language |
            static(?:\s+noise)? | typing | unclear | unintelligible
        )
        (?:\s+(?:continues?|indistinctly|loudly|quietly|softly|sounds?)){0,3}
        \s*(?:[.!?,;:…]+|\.\.\.)(?=\s|$)
        """#
    private static let preservedRepeatedWords: Set<String> = [
        "dash", "ha", "haha", "hyphen", "no", "ok", "okay", "really", "so", "very", "yes"
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
    private static let allowedPreviousWordsForSpokenTextCase: Set<String> = [
        "call", "called", "enter", "label", "make", "mark", "named", "paste",
        "please", "say", "set", "title", "to", "type", "use", "write"
    ]
    private static let blockedFirstWordsForSpokenTextCase: Set<String> = [
        "a", "an", "as", "command", "commands", "for", "in", "is", "means",
        "phrase", "phrases", "style", "the", "with", "word", "words"
    ]
    private static let dateContextWords: Set<String> = [
        "after", "before", "by", "due", "from", "on", "since", "through", "until"
    ]
    private static let monthWords: Set<String> = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]
    private static let ordinalDayValues: [String: Int] = [
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
    private static let poundWeightContextWords: Set<String> = [
        "dropped", "gain", "gained", "lose", "losing", "lost", "shed", "weigh", "weighed", "weighs"
    ]
    private static let trailingAmountUnitWords: Set<String> = [
        "buck", "bucks", "dollar", "dollars", "eur", "euro", "euros",
        "gbp", "percent", "pound", "pounds", "usd"
    ]
    private static let leadingCurrencySignWords: Set<String> = [
        "dollar", "euro", "pound"
    ]
    private static let compactConnectorWords: Set<String> = [
        "at", "back", "backslash", "dash", "dot", "forward", "hyphen", "sign", "slash", "underscore"
    ]
    private static let commonTechnicalAcronyms = [
        "ai": "AI",
        "api": "API",
        "asr": "ASR",
        "cli": "CLI",
        "cpu": "CPU",
        "css": "CSS",
        "csv": "CSV",
        "gpu": "GPU",
        "html": "HTML",
        "http": "HTTP",
        "https": "HTTPS",
        "json": "JSON",
        "llm": "LLM",
        "ml": "ML",
        "nlp": "NLP",
        "pdf": "PDF",
        "sdk": "SDK",
        "sql": "SQL",
        "stt": "STT",
        "tts": "TTS",
        "ui": "UI",
        "url": "URL",
        "ux": "UX",
        "xml": "XML"
    ]
    private static let blockedNextWordsForSpokenPossessive: Set<String> = [
        "character", "characters", "is", "mark", "marks", "means", "meaning", "suffix", "symbol", "symbols"
    ]
    private static let blockedPreviousWordsForSpokenPunctuationName: Set<String> = [
        "a", "an", "command", "commands", "how", "phrase", "phrases", "say", "saying",
        "symbol", "symbols", "the", "to", "word", "words"
    ]
    private static let blockedNextWordsForSpokenPunctuationName: Set<String> = [
        "character", "characters", "command", "commands", "from", "in", "is", "means",
        "of", "operator", "phrase", "phrases", "separated", "shortcut", "shortcuts",
        "symbol", "symbols"
    ]
    private static let spokenPossessivePattern = #"(?i)(?<![\p{L}\p{N}])([\p{L}\p{N}][\p{L}\p{N}'’ʼ-]{0,63})\s+apostrophe\s+s(?=\s+[\p{L}\p{N}])"#
    private static let spokenNoSpaceCommandPattern = #"(?i)(?<![\p{L}\p{N}])([\p{L}\p{N}][\p{L}\p{N}'’ʼ-]{0,63})[ \t]+no[ \t]+spaces?[ \t]+([\p{L}\p{N}][\p{L}\p{N}'’ʼ-]{0,63})(?![\p{L}\p{N}])"#
    private static let blockedPreviousWordsForSpokenNoSpace: Set<String> = [
        "a", "an", "are", "be", "has", "have", "is", "need", "needs", "should",
        "that", "the", "there", "want", "wants", "was", "were"
    ]
    private static let blockedNextWordsForSpokenNoSpace: Set<String> = [
        "available", "before", "between", "command", "commands", "from", "here",
        "in", "is", "left", "needed", "of", "shortcut", "shortcuts", "there", "to"
    ]
    private static let likelyLowercaseFragments: Set<String> = [
        "a", "about", "after", "again", "all", "also", "an", "and", "any", "app", "are",
        "as", "at", "back", "be", "because", "but", "by", "can", "case", "client", "code", "config",
        "could", "data", "did", "do", "does", "done", "final", "first", "for", "from",
        "get", "go", "got", "had", "has", "have", "here", "how", "if", "in",
        "is", "it", "just", "last", "like", "make", "maybe", "mean", "model",
        "models", "need", "next", "not", "now", "of", "on", "one", "or", "out",
        "page", "parser", "phrase", "phrases", "prompt", "put", "really", "request", "response", "right",
        "router", "screen", "second", "see", "server", "service", "setting", "should", "single", "so", "some",
        "that", "the", "then", "there", "third", "this", "to", "token", "tool", "use", "view", "was",
        "we", "what", "when", "where", "which", "will", "window", "with", "word", "words", "work",
        "would", "yeah", "you"
    ]
    private static let preservedSingleWordQuestionFragments: Set<String> = [
        "how", "what", "when", "where", "which", "who", "why"
    ]
    private static let preservedTerminalPeriodAbbreviations: Set<String> = [
        "d.phil.", "dr.", "e.g.", "ed.d.", "etc.", "i.e.", "jr.", "ll.m.",
        "m.phil.", "mr.", "mrs.", "ms.", "ph.d.", "prof.", "sc.d.", "sr.",
        "st.", "u.k.", "u.n.", "u.s.", "vs."
    ]
    
    private static let nonSpeechBracketPatterns = [
        #"\[\s*([^\[\]]{1,80})\s*\]"#,
        #"\(\s*([^\(\)]{1,80})\s*\)"#,
        #"\{\s*([^\{\}]{1,80})\s*\}"#
    ]
    private static let asrBoilerplatePatterns: [(pattern: String, replacement: String)] = [
        (
            #"(?im)(^|(?<=[.!?])\s+|\n)\s*(?:thank\s+you(?:\s+(?:all|everyone|so\s+much))?\s+for\s+(?:watching|listening)|thanks(?:\s+(?:all|everyone|so\s+much))?\s+for\s+(?:watching|listening)|please\s+(?:like\s+and\s+)?subscribe|like\s+and\s+subscribe|(?:don't\s+forget|be\s+sure)\s+to\s+(?:like\s+and\s+)?subscribe)(?:[.!?]+)?(?=\s*$|\n)"#,
            "$1"
        ),
        (
            #"(?im)^\s*(?:subtitles?|captions?|captioned|transcribed)\s+by\b[^\n]*$"#,
            ""
        )
    ]
    private static let asrSpecialTokenPattern = #"(?i)<\|\s*(?:no[\s_-]*speech|nospeech|empty[\s_-]*audio|blank[\s_-]*audio|no[\s_-]*audio|silence|silent|end[\s_-]*of[\s_-]*text|endoftext|start[\s_-]*of[\s_-]*transcript|startoftranscript|no[\s_-]*timestamps|notimestamps|transcribe|translate|af|am|ar|as|az|ba|be|bg|bn|bo|br|bs|ca|cs|cy|da|de|el|en|es|et|eu|fa|fi|fo|fr|gl|gu|ha|haw|he|hi|hr|ht|hu|hy|id|is|it|ja|jw|ka|kk|km|kn|ko|la|lb|ln|lo|lt|lv|mg|mi|mk|ml|mn|mr|ms|mt|my|ne|nl|nn|no|oc|pa|pl|ps|pt|ro|ru|sa|sd|si|sk|sl|sn|so|sq|sr|su|sv|sw|ta|te|tg|th|tk|tl|tr|tt|uk|ur|uz|vi|yi|yo|zh|\d{1,2}(?:\.\d{1,2})?)\s*\|>"#
    private static let punctuatedDiscourseFillerPatterns: [(pattern: String, replacement: String)] = [
        (#"(?i)[,;:…]\s+(?:you\s+know|like)[,;:…]*([.!?])\s*$"#, "$1"),
        (#"(?i)[,;:…]\s+(?:you\s+know|like)[,;:…]+(?=\s)"#, " ")
    ]
    private static let leadingDiscourseFillerPatterns: [(pattern: String, replacement: String)] = [
        (#"(?i)^\s*(?:ok(?:ay)?|all\s+right|alright|right|yeah)(?:[ \t]*[,;:…]+[ \t]*(?:you\s+know(?:[ \t]+what[ \t]+i[ \t]+mean)?|i\s+mean|like)[ \t]*[,;:…]+)+[ \t]+"#, ""),
        (#"(?i)^\s*(?:ok(?:ay)?|all\s+right|alright|right|yeah)[,;:…]*[ \t]+so[,;:…]*[ \t]+"#, ""),
        (#"(?i)^\s*(?:ok(?:ay)?|all\s+right|alright|right|yeah)(?:[ \t]*[,;:…]+[ \t]*)+so[,;:…]*[ \t]+"#, ""),
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
    private static let allowedNextWordsForUnpunctuatedHedgeFiller: Set<String> = [
        "actually", "almost", "basically", "close", "done", "fine", "going",
        "good", "just", "maybe", "not", "probably", "ready", "really",
        "thinking", "trying", "waiting", "working"
    ]
    private static let leadingLikeClauseStarterVerbs: Set<String> = [
        "am", "are", "can", "could", "did", "do", "does", "had", "has",
        "have", "is", "might", "must", "need", "needs", "should", "think",
        "thinks", "was", "were", "will", "work", "works", "would"
    ]
    private static let leadingLikeClauseStarterPronouns: Set<String> = [
        "he", "i", "it", "she", "that", "they", "this", "we", "you"
    ]
    private static let inlineNumberedListMarkerPattern = #"(?<![\p{L}\p{N}])\d{1,2}\.\s+(?=\S)"#
    private static let spokenSequenceListMarkerPattern = #"(?i)(?<![\p{L}\p{N}])(?:number[ \t]+)?(one|two|three|four|five|six|seven|eight|nine|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)(?:[.)])?[ \t]+(?=\S)"#
    private static let spokenSequenceListMarkerValues: [String: Int] = [
        "one": 1, "first": 1,
        "two": 2, "second": 2,
        "three": 3, "third": 3,
        "four": 4, "fourth": 4,
        "five": 5, "fifth": 5,
        "six": 6, "sixth": 6,
        "seven": 7, "seventh": 7,
        "eight": 8, "eighth": 8,
        "nine": 9, "ninth": 9
    ]
    private static let blockedPreviousWordsForSpokenSequenceListMarkers: Set<String> = [
        "a", "an", "chapter", "her", "his", "its", "line", "my", "our", "page",
        "section", "that", "the", "their", "these", "this", "those", "version", "your"
    ]
    private static let blockedNextWordsForSpokenSequenceListMarkers: Set<String> = [
        "and", "billion", "cent", "cents", "dollar", "dollars", "grade", "grades", "hundred",
        "item", "items", "line", "lines", "million", "percent", "place", "places",
        "point", "or", "second", "seconds", "thing", "things", "thousand", "time", "times"
    ]
    private static let markdownHeadingPattern = #"(?im)(^|\n)[ \t]*(?:heading|header)[ \t]+(one|two|three|1|2|3)[ \t]+([^\n]+)"#
    private static let uncheckedMarkdownTaskPattern = #"(?im)(^|\n)[ \t]*(?:todo|to[ \t]+do|checkbox|check[ \t]+box|unchecked[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+([^\n]+)"#
    private static let checkedMarkdownTaskPattern = #"(?im)(^|\n)[ \t]*(?:(?:checked|done|completed)[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+([^\n]+)"#
    private static let nestedUncheckedMarkdownTaskCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:todo|to[ \t]+do|checkbox|check[ \t]+box|unchecked[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+"#
    private static let nestedCheckedMarkdownTaskCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:(?:checked|done|completed)[ \t]+(?:task|checkbox|check[ \t]+box))[ \t]+"#
    private static let blockedNextWordsForNestedMarkdownTaskCommand: Set<String> = [
        "command", "commands", "from", "in", "is", "means", "of", "phrase",
        "phrases", "shortcut", "shortcuts"
    ]
    private static let markdownTablePattern = #"(?im)(^|\n)[ \t]*(?:markdown[ \t]+)?table[ \t]+([^\n]+)"#
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
            (?:[,;:…]|\.\.\.)?\s*actually\s+wait\s*[,;:]?\s+no\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*actually\s+wait\s*[,;:]?\s+never\s*mind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*actually\s+wait\s*[,;:]?\s+nevermind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*actually\s+never\s*mind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*actually\s+nevermind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*actually\s+no\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*actually\s+make\s+it\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*better\s+make\s+it\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*actually |
            (?:[,;:…]|\.\.\.)\s*no\s*[,;:]?\s+actually\s*[,;:]? |
            sorry\s+not\s+that\s*[,;:]?\s+actually |
            (?:[,;:…]|\.\.\.)\s*(?:oops|whoops|woops)\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*my\s+bad\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*correction\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*on\s+second\s+thought\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*let\s+me\s+rephrase\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*back\s*track\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*(?:just\s+)?to\s+clarify\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*(?:just\s+)?to\s+be\s+clear\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*for\s+clarity\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*sorry\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*sorry\s*[,;:]?\s+i\s+meant\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*what\s+i\s+mean\s+is\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*i\s+mean\s+to\s+say\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*i\s+meant\s+to\s+say\s*[,;:]? |
            sorry\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*i\s+meant\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*i\s+should\s+say\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*make\s+that\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*make\s+it\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*call\s+it\s*[,;:]? |
            replace\s+(?:that|it)\s+with |
            change\s+(?:that|it)\s+to |
            (?:(?:scratch|strike|delete|remove|erase|undo|cancel|disregard|ignore|forget|cut|drop)\s+(?:that|this)\s+out|cross\s+(?:that|this)\s+out|(?:scratch|strike|delete|remove|erase|undo|cancel|disregard|ignore|forget|cut|drop)\s+(?:that|this)(?!\s+(?:out|words?|lines?|sentences?|paragraphs?)\b)) |
            (?:[,;:…]|\.\.\.)\s*hold\s+on\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*hang\s+on\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*wait\s*[,;:]?\s+never\s*mind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*wait\s*[,;:]?\s+nevermind\s*[,;:]? |
            (?:[,;:…]|\.\.\.)?\s*wait\s*[,;:]?\s+no\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*wait\s*[,;:]?\s+actually\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*wait\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*wait\s*[,;:]?\s+i\s+meant\s*[,;:]? |
            (?:[,;:…]|\.\.\.)\s*wait\s*[,;:]?(?!\s+(?:no|actually|i\s+mean|i\s+meant|never\s*mind|nevermind)\b) |
            (?:[,;:…]|\.\.\.)\s*no\s*[,;:]?\s+wait\s*[,;:]? |
            no\s*[,;:]?\s+i\s+mean\s*[,;:]? |
            no\s*[,;:]?\s+i\s+meant\s*[,;:]? |
            no\s*[,;:]?\s+actually\s*[,;:]? |
            never\s*mind |
            nevermind |
            sorry\s+not\s+that |
            sorry\s+no |
            (?:[,;:…]|\.\.\.)\s*sorry\s*[,;:]? |
            no\s*[,;:]?\s+sorry |
            sorry |
            (?:[,;:…]|\.\.\.)\s*rather\s*[,;:]? |
            or\s+rather |
            or\s+actually |
            or\s+wait\s*[,;:]?\s+no |
            (?:[,;:…]|\.\.\.)\s*instead(?!\s+of\b)\s*[,;:]? |
            i\s+mean
        )
        \s*[,;:]?\s+
        """#
    private static let scratchThatCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:(?:scratch|strike|delete|remove|erase|undo|cancel|disregard|ignore|forget|cut|drop)\s+(?:that|this)(?:\s+out)?|cross\s+(?:that|this)\s+out)(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n))"#
    private static let deletePreviousWordCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:delete|remove|erase|undo|scratch|strike|cancel|drop)\s+(?:(?:the\s+)?(?:last|previous)(?:\s+(\d|one|two|three|four|five))?|that|this)\s+words?(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n)|\s+)"#
    private static let deletePreviousLineCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:delete|remove|erase|undo|scratch|strike|cancel|drop)\s+(?:(?:the\s+)?(?:last|previous)|that|this)\s+line(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n)|\s+)"#
    private static let deletePreviousParagraphCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:delete|remove|erase|undo|scratch|strike|cancel|drop)\s+(?:(?:the\s+)?(?:last|previous)|that|this)\s+paragraph(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n)|\s+)"#
    private static let deletePreviousSentenceCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:delete|remove|erase|undo|scratch|strike|cancel|drop)\s+(?:(?:the\s+)?(?:last|previous)|that|this)\s+sentence(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n)|\s+)"#
    private static let phraseBoundaryPunctuation = CharacterSet(charactersIn: ".,!?;:…")
    private static let softPhrasePunctuation = CharacterSet(charactersIn: ",;:…")
    private static let wordConnectorCharacters = CharacterSet(charactersIn: "'’ʼ-")
    private static let compactTokenConnectors = CharacterSet(charactersIn: "@._-/\\")
    private static let maxBacktrackingCorrectionWords = 4
    private static let maxScratchThatWords = 12
    private static let blockedPreviousWordsForReplaceThat: Set<String> = [
        "command", "commands", "phrase", "phrases", "say", "saying", "word", "words"
    ]
    private static let blockedPreviousWordsForEraseThat: Set<String> = [
        "can", "could", "command", "commands", "did", "do", "does", "he", "i", "it", "may", "might",
        "must", "never", "not", "said", "say", "saying", "says", "shall", "she", "should", "they",
        "to", "we", "will", "word", "words", "would", "you"
    ]
    private static let blockedFirstCorrectionWordsForReplaceThat: Set<String> = [
        "is", "means"
    ]
    private static let blockedPreviousWordsForBareSorryCorrection: Set<String> = [
        "am", "are", "felt", "feel", "feeling", "is", "really", "said", "say", "saying", "says", "so",
        "truly", "very", "was", "were"
    ]
    private static let blockedFirstCorrectionWordsForBareSorryCorrection: Set<String> = [
        "about", "for", "that", "this", "to"
    ]
    private static let blockedSingleWordPrefixesForMakeCallCorrection: Set<String> = [
        "please"
    ]
    private static let blockedPrefixesForPlainIMeanCorrection: Set<String> = [
        "all right", "alright", "ok", "okay", "right", "well", "yeah"
    ]
    private static let blockedPreviousWordsForDeleteCommand: Set<String> = [
        "a", "an", "command", "commands", "shortcut", "shortcuts", "the"
    ]
    private static let blockedNextWordsForDeleteCommand: Set<String> = [
        "command", "commands", "from", "in", "is", "means", "of", "shortcut", "shortcuts"
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
        (#"(?i)(?<![\p{L}\p{N}])(?<!start[ \t]a[ \t])(?:new|next)\s+paragraph(?![\p{L}\p{N}])"#, "\n\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+line(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])line\s+break(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])newline(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new\s+bullet|bullet\s+point|bullet)(?![\p{L}\p{N}])"#, "\n- ")
    ]
    private static let spokenSentenceBoundaryCommandPattern = #"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+sentence(?:\s*[.!?,;:…]+|(?=\s*$|\s*\n)|\s+)"#
    private static let blockedPreviousWordsForSpokenSentenceBoundary: Set<String> = [
        "a", "an", "command", "commands", "how", "phrase", "phrases", "say",
        "saying", "start", "the", "to", "word", "words"
    ]
    private static let blockedNextWordsForSpokenSentenceBoundary: Set<String> = [
        "command", "commands", "from", "in", "is", "means", "of", "phrase",
        "phrases", "shortcut", "shortcuts"
    ]
    private static let guardedSpokenFormattingCommands = [
        GuardedSpokenFormattingCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:skip\s+a\s+line|blank\s+line|paragraph\s+break|start\s+a\s+new\s+paragraph|break\s+here|split\s+here)(?![\p{L}\p{N}])"#,
            replacement: "\n\n",
            blockedPreviousWords: ["command", "commands", "how", "phrase", "phrases", "say", "saying", "the", "to", "word", "words"],
            blockedNextWords: ["command", "commands", "from", "in", "is", "means", "of", "phrase", "phrases", "shortcut", "shortcuts"]
        ),
        GuardedSpokenFormattingCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:press|hit|tap)\s+(?:the\s+)?(?:enter|return)(?:\s+key)?(?![\p{L}\p{N}])"#,
            replacement: "\n",
            blockedPreviousWords: ["command", "commands", "how", "phrase", "phrases", "say", "saying", "the", "to", "word", "words"],
            blockedNextWords: ["command", "commands", "from", "in", "is", "means", "of", "phrase", "phrases", "shortcut", "shortcuts"]
        ),
        GuardedSpokenFormattingCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:press|hit|tap)\s+(?:the\s+)?tab(?:\s+key)?(?![\p{L}\p{N}])"#,
            replacement: "\t",
            blockedPreviousWords: ["command", "commands", "how", "phrase", "phrases", "say", "saying", "the", "to", "word", "words"],
            blockedNextWords: ["command", "commands", "from", "in", "is", "means", "of", "phrase", "phrases", "shortcut", "shortcuts"]
        )
    ]
    private static let spokenEnclosureCommands: [(pattern: String, replacement: String)] = [
        (#"(?i)(?<![\p{L}\p{N}])(?:open|start)\s+(?:quote|quotation\s+marks?)(?![\p{L}\p{N}])"#, openQuotePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|end)\s+(?:quote|quotation\s+marks?)(?![\p{L}\p{N}])"#, closeQuotePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:paren|parenthesis|parentheses)(?![\p{L}\p{N}])"#, openParenthesisPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right|end)\s+(?:paren|parenthesis|parentheses)(?![\p{L}\p{N}])"#, closeParenthesisPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:square\s+)?bracket(?![\p{L}\p{N}])"#, openBracketPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right|end)\s+(?:square\s+)?bracket(?![\p{L}\p{N}])"#, closeBracketPlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:open|left)\s+(?:curly\s+)?brace(?![\p{L}\p{N}])"#, openBracePlaceholder),
        (#"(?i)(?<![\p{L}\p{N}])(?:close|right|end)\s+(?:curly\s+)?brace(?![\p{L}\p{N}])"#, closeBracePlaceholder)
    ]
    private static let spokenDoubleQuotePairPattern = #"(?i)(?<![\p{L}\p{N}])quote[ \t]+([^.!?\n]{1,160}?)[ \t]+unquote([.!?])?(?![\p{L}\p{N}])"#
    private static let spokenSingleQuotePairPattern = #"(?i)(?<![\p{L}\p{N}])single[ \t]+quote[ \t]+([^.!?\n]{1,160}?)[ \t]+single[ \t]+quote([.!?])?(?![\p{L}\p{N}])"#
    private static let spokenPutEnclosurePattern = #"(?i)(?<![\p{L}\p{N}])(?:put|wrap|enclose)[ \t]+([^.!?\n]{1,120}?)[ \t]+(?:in|inside)[ \t]+(single[ \t]+quotes?|quotes?|quotation[ \t]+marks?|parentheses|parenthesis|parens?|brackets?|square[ \t]+brackets?|braces?|curly[ \t]+braces?)([.!?])?(?![\p{L}\p{N}])"#
    private static let spokenLongCLIFlagPattern = #"(?i)(?<![\p{L}\p{N}])(?:dash|hyphen)[ \t]+(?:dash|hyphen)[ \t]+([A-Za-z][A-Za-z0-9]*(?:[ \t]+(?:dash|hyphen)[ \t]+[A-Za-z0-9]+){0,4})(?=[.!?,;:]|\s+(?:and|or|then|with|without)\b|$)"#
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
    private static let spokenTextCaseCommands = [
        SpokenTextCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:all[ \t]+caps|uppercase|upper[ \t]+case)[ \t]+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b|is\b|means\b)[\p{L}\p{N}_./@:+#'-]+[ \t]*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .allCaps
        ),
        SpokenTextCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:lowercase|lower[ \t]+case)[ \t]+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b|is\b|means\b)[\p{L}\p{N}_./@:+#'-]+[ \t]*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .lowercase
        ),
        SpokenTextCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:capitalize|capitalise)[ \t]+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b|is\b|means\b)[\p{L}\p{N}_./@:+#'-]+[ \t]*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .capitalize
        ),
        SpokenTextCaseCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])title[ \t]+case[ \t]+((?:(?!for\b|from\b|in\b|into\b|on\b|to\b|with\b|is\b|means\b)[\p{L}\p{N}_./@:+#'-]+[ \t]*){1,5})(?=\s+(?:for|from|in|into|on|to|with)\b|[.!?,;:]|$)"#,
            style: .title
        )
    ]
    private static let spokenPunctuationCommands = [
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:ellipsis|dot\s+dot\s+dot|period\s+period\s+period|full\s+stop\s+full\s+stop\s+full\s+stop)(?![\p{L}\p{N}])"#,
            output: "...",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:em\s+dash|m\s+dash)(?![\p{L}\p{N}])"#,
            output: " —",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])question\s+(?:mark|point|sign)(?![\p{L}\p{N}])"#,
            output: "?",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])exclamation\s+(?:mark|point|sign)(?![\p{L}\p{N}])"#,
            output: "!",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])full\s+stop(?![\p{L}\p{N}])"#,
            output: ".",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])period(?![\p{L}\p{N}])"#,
            output: ".",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName.union([
                "billing", "class", "current", "grace", "historical",
                "pay", "payback", "reporting", "retention", "school",
                "time", "trial"
            ]),
            blockedNextWords: blockedNextWordsForSpokenPunctuationName.union(["drama", "of", "piece"])
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])comma(?![\p{L}\p{N}])"#,
            output: ",",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName.union(["oxford", "serial"]),
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])semicolon(?![\p{L}\p{N}])"#,
            output: ";",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName,
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        ),
        SpokenPunctuationCommand(
            pattern: #"(?i)(?<![\p{L}\p{N}])colon(?![\p{L}\p{N}])"#,
            output: ":",
            blockedPreviousWords: blockedPreviousWordsForSpokenPunctuationName.union(["http", "https"]),
            blockedNextWords: blockedNextWordsForSpokenPunctuationName
        )
    ]
    private static let standaloneSpokenPunctuationOutputs = [
        "ellipsis": "...",
        "dot dot dot": "...",
        "period period period": "...",
        "full stop full stop full stop": "...",
        "em dash": " —",
        "em-dash": " —",
        "emdash": " —",
        "m dash": " —",
        "m-dash": " —",
        "mdash": " —",
        "slash": "/",
        "forward slash": "/",
        "backslash": "\\",
        "back slash": "\\",
        "dot": ".",
        "underscore": "_",
        "at sign": "@",
        "dash": "-",
        "hyphen": "-",
        "comma": ",",
        "period": ".",
        "full stop": ".",
        "question mark": "?",
        "question point": "?",
        "question sign": "?",
        "exclamation mark": "!",
        "exclamation point": "!",
        "exclamation sign": "!",
        "semicolon": ";",
        "colon": ":"
    ]
    private static let standaloneSpokenEnclosureOutputs = [
        "open quote": "\"",
        "start quote": "\"",
        "open quotation mark": "\"",
        "open quotation marks": "\"",
        "start quotation mark": "\"",
        "start quotation marks": "\"",
        "close quote": "\"",
        "end quote": "\"",
        "close quotation mark": "\"",
        "close quotation marks": "\"",
        "end quotation mark": "\"",
        "end quotation marks": "\"",
        "open paren": "(",
        "open parenthesis": "(",
        "open parentheses": "(",
        "left paren": "(",
        "left parenthesis": "(",
        "left parentheses": "(",
        "close paren": ")",
        "close parenthesis": ")",
        "close parentheses": ")",
        "right paren": ")",
        "right parenthesis": ")",
        "right parentheses": ")",
        "end paren": ")",
        "end parenthesis": ")",
        "end parentheses": ")",
        "open bracket": "[",
        "open square bracket": "[",
        "left bracket": "[",
        "left square bracket": "[",
        "close bracket": "]",
        "close square bracket": "]",
        "right bracket": "]",
        "right square bracket": "]",
        "end bracket": "]",
        "end square bracket": "]",
        "open brace": "{",
        "open curly brace": "{",
        "left brace": "{",
        "left curly brace": "{",
        "close brace": "}",
        "close curly brace": "}",
        "right brace": "}",
        "right curly brace": "}",
        "end brace": "}",
        "end curly brace": "}"
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

        filteredText = removeASRSpecialTokens(from: filteredText)

        filteredText = removeNonSpeechBracketedContent(from: filteredText)
        filteredText = removeUnbracketedNonSpeechDescriptors(from: filteredText)

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
        let leadingFormattingNewlineCount = leadingSpokenFormattingNewlineCount(in: filteredText)
        filteredText = applySpokenFormattingCommands(in: filteredText)
        if cleanupLevel == .polished {
            filteredText = applyDeletePreviousLineCommands(in: filteredText)
            filteredText = applyDeletePreviousParagraphCommands(in: filteredText)
        }
        filteredText = applySpokenEnclosureCommands(in: filteredText)
        filteredText = applySpokenURLCommands(in: filteredText)
        filteredText = applySpokenValueFormattingCommands(in: filteredText)
        filteredText = applySpokenPunctuationCommands(in: filteredText)
        filteredText = applySpokenNumberedOutlineCommands(in: filteredText)
        filteredText = replaceSpokenSequenceListMarkers(in: filteredText)
        filteredText = formatInlineNumberedLists(in: filteredText)
        filteredText = applySpokenCLIFlagCommands(in: filteredText)
        filteredText = applySpokenSymbolCommands(in: filteredText)
        filteredText = applySpokenContractionCommands(in: filteredText)
        filteredText = applySpokenPossessiveCommands(in: filteredText)
        filteredText = applySpokenNoSpaceCommands(in: filteredText)
        filteredText = applyCommonTechnicalAcronymCasing(in: filteredText)
        filteredText = applySpokenTextCaseCommands(in: filteredText)
        filteredText = applySpokenCodeCaseCommands(in: filteredText)
        filteredText = applySpokenMarkdownCommands(in: filteredText)
        if cleanupLevel == .polished {
            filteredText = collapseAdjacentRepeatedWords(in: filteredText)
            filteredText = collapseSeparatorRepeatedWords(in: filteredText)
            filteredText = collapseRepeatedShortPhrases(in: filteredText)
            filteredText = collapseRepeatedShortClauses(in: filteredText)
            filteredText = collapseRepeatedShortSentences(in: filteredText)
            filteredText = collapseMismatchedRepeatedShortSentences(in: filteredText)
        }

        // Clean whitespace
        filteredText = normalizeWhitespace(filteredText)
        filteredText = applyNestedBulletCommands(in: filteredText)
        filteredText = restoreLeadingNewlines(leadingFormattingNewlineCount, to: filteredText)

        return filteredText
    }

    private static func removeUnbracketedNonSpeechDescriptors(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: unbracketedNonSpeechDescriptorPattern) else {
            return text
        }

        var filteredText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            guard let match = regex.firstMatch(in: filteredText, range: range),
                  let matchRange = Range(match.range, in: filteredText) else {
                break
            }

            filteredText.replaceSubrange(matchRange, with: "")
            rewriteCount += 1
        }

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

    private static func removeASRSpecialTokens(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: asrSpecialTokenPattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
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
        let normalizedText = normalizedBracketContent(text)
        return nonSpeechBracketContents.contains(normalizedText) ||
            isExtendedNonSpeechBracketContent(normalizedText) ||
            isTranscriptTimestampLabel(normalizedText) ||
            isTranscriptSpeakerLabel(normalizedText)
    }

    private static func normalizedBracketContent(_ text: String) -> String {
        text
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;:… ").union(.whitespacesAndNewlines))
            .lowercased()
            .replacingOccurrences(of: #"[\s_-]+"#, with: " ", options: .regularExpression)
    }

    private static func isExtendedNonSpeechBracketContent(_ text: String) -> Bool {
        let patterns = [
            #"^(?:applause|beep|beeping|breathing|coughing|humming|laughing|mumbling|music|noise|ringing|sighing|silence|sneeze|sneezing|static|typing)(?:\s+(?:continues?|indistinctly|loudly|noise|playing|quietly|softly|sounds?)){1,3}$"#,
            #"^background\s+(?:chatter|conversation|music|noise|speech|voices)$"#,
            #"^crowd\s+(?:applause|chatter|noise|talking)$"#,
            #"^(?:keyboard\s+typing|phone\s+ringing)(?:\s+(?:continues?|loudly|quietly|softly|sounds?)){1,3}$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return true
            }
        }

        return false
    }

    private static func isTranscriptTimestampLabel(_ text: String) -> Bool {
        let patterns = [
            #"^(?:0{1,2}:\d{2}(?::\d{2})?(?:\.\d{1,3})?|\d{1,2}:\d{2}\s*(?:timestamp|timestamps))$"#,
            #"^(?:\d{1,2}:)?\d{2}:\d{2}\s*(?:-|–|—)?\s+(?:\d{1,2}:)?\d{2}:\d{2}(?:\s*(?:timestamp|timestamps))?$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return true
            }
        }

        return false
    }

    private static func isTranscriptSpeakerLabel(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"^speaker(?:[\s_-]*(?:\d{1,3}|[a-z]))?$"#
        ) else {
            return false
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    public static func applyInsertionPolish(_ text: String, context: TextInsertionContext?) -> String {
        let leadingNewlineCount = leadingNewlineCount(in: text)
        let activeContext = leadingNewlineCount > 0 ? nil : context
        let polishInput = text.dropFirst(leadingNewlineCount)
        let normalizedText = normalizeWhitespace(String(polishInput))

        if activeContext != nil,
           let enclosure = standaloneSpokenEnclosureOutput(in: normalizedText) {
            return restoreLeadingNewlines(leadingNewlineCount, to: enclosure)
        }

        let wasWholeSquareBracketedOutput = isWholeSquareBracketedOutput(normalizedText)
        var polishedText = stripBoundaryNoise(from: normalizedText)
        polishedText = removeRedundantOuterPunctuationAfterPreservedBoundary(from: polishedText)
        polishedText = removeLeadingPausePunctuation(from: polishedText)
        guard !polishedText.isEmpty else {
            return restoreLeadingNewlines(leadingNewlineCount, to: polishedText)
        }

        let shouldTreatAsFragment = isShortFragment(polishedText) ||
            (wasWholeSquareBracketedOutput &&
                isShortFragment(removeTrailingNoisyFragmentPunctuation(from: polishedText)))
        let shouldUseFragmentPolish: Bool
        if let activeContext, isContinuingSentence(after: activeContext.precedingText) {
            shouldUseFragmentPolish = shouldTreatAsFragment
        } else {
            shouldUseFragmentPolish = shouldTreatAsFragment &&
                (wasWholeSquareBracketedOutput ||
                    isSingleWordFinalFragment(polishedText) ||
                    isShortNoisyBoundaryFinalFragment(polishedText))
        }

        if shouldUseFragmentPolish {
            if let activeContext,
               shouldRemoveLeadingGeneratedFragmentMarker(after: activeContext.precedingText) {
                polishedText = removeLeadingGeneratedFragmentMarker(from: polishedText)
            }
            polishedText = removeLeadingFragmentPunctuation(from: polishedText)
            if wasWholeSquareBracketedOutput {
                polishedText = removeTrailingNoisyFragmentPunctuation(from: polishedText)
            } else {
                polishedText = removeTrailingShortFragmentPunctuation(from: polishedText)
            }
        }

        if let activeContext,
           let punctuation = standaloneSpokenPunctuationOutput(in: polishedText),
           canAttachStandalonePunctuation(after: activeContext.precedingText) {
            return restoreLeadingNewlines(leadingNewlineCount, to: punctuation)
        }

        if let activeContext {
            guard isContinuingSentence(after: activeContext.precedingText) else {
                return restoreLeadingNewlines(leadingNewlineCount, to: polishedText)
            }
            polishedText = removeTrailingContinuationPeriod(from: polishedText)
            let lowercasedText = lowercaseInitialWordIfSafe(in: polishedText)
            let adjustedText = shouldLowercaseLikelyTitleCasedFragmentWords(in: lowercasedText)
                ? lowercaseLikelyTitleCasedWordsIfSafe(in: lowercasedText)
                : lowercasedText
            return restoreLeadingNewlines(leadingNewlineCount, to: adjustedText)
        }

        guard shouldUseFragmentPolish else {
            return restoreLeadingNewlines(leadingNewlineCount, to: polishedText)
        }
        return restoreLeadingNewlines(leadingNewlineCount, to: lowercaseFragmentWordsIfSafe(in: polishedText))
    }

    private static func standaloneSpokenPunctuationOutput(in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return standaloneSpokenPunctuationOutputs[normalizedText]
    }

    private static func standaloneSpokenEnclosureOutput(in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if let output = standaloneSpokenEnclosureOutputs[normalizedText] {
            return output
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count == 2,
              trimmedText.last == ".",
              let firstCharacter = trimmedText.first,
              "()[]{}\"".contains(firstCharacter) else {
            return nil
        }

        return String(firstCharacter)
    }

    private static func canAttachStandalonePunctuation(after precedingText: String) -> Bool {
        let trimmedText = currentLinePrefix(in: precedingText).trimmingCharacters(in: .whitespaces)
        guard let previousCharacter = trimmedText.last else { return false }

        if previousCharacter.isLetter || previousCharacter.isNumber {
            return true
        }

        return ")]}\"'”’".contains(previousCharacter)
    }

    public static func applyInsertionSpacing(_ text: String, context: TextInsertionContext?) -> String {
        guard let context else { return text }
        if needsLeadingListBoundary(before: text, context: context) {
            return "\n\(text)"
        }
        guard needsLeadingSpace(before: text, context: context) else { return text }
        return " \(text)"
    }

    private static func removeFillerWords(from text: String, fillerWords configuredFillerWords: [String]) -> String {
        var filteredText = text
        let hadLeadingFillerNoise = startsWithRemovableLeadingFillerNoise(
            filteredText,
            fillerWords: configuredFillerWords
        )
        let hadLeadingPauseFillerNoise = startsWithRemovableLeadingPauseFillerNoise(
            filteredText,
            fillerWords: configuredFillerWords
        )

        filteredText = removeStandaloneDiscourseFillers(from: filteredText)
        filteredText = removeLeadingDiscourseFillers(from: filteredText)
        filteredText = removeLeadingAcknowledgementFillerChain(from: filteredText)
        filteredText = removeLeadingWellFiller(from: filteredText)
        filteredText = removeLeadingUnpunctuatedDiscourseFiller(from: filteredText)
        filteredText = removeLeadingUnpunctuatedLikeFiller(from: filteredText)
        filteredText = removeLeadingBasicallyFiller(from: filteredText)
        filteredText = removeLeadingSoFiller(from: filteredText)
        filteredText = removePunctuatedDiscourseFillers(from: filteredText)
        filteredText = removeTerminalDiscourseFillers(from: filteredText)
        filteredText = removeTerminalAcknowledgementFillers(from: filteredText)
        filteredText = removeUnpunctuatedLikeFillers(from: filteredText)
        filteredText = removeUnpunctuatedHedgeFillers(from: filteredText)
        filteredText = preserveBacktrackingMarkersAfterPauseFillers(in: filteredText)

        let embeddedPausePattern = #"(?i)(?<=[\p{L}\p{N}])[,;:…][ \t]+(?:u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+)(?:[.,;:!?…]+)?(?=[ \t]+[\p{L}\p{N}])"#
        if let regex = try? NSRegularExpression(pattern: embeddedPausePattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        let joinedPausePattern = #"(?i)(?<![\p{L}\p{N}])(?:m+h+m+|m+[\s-]+h+m+|u+h+[\s-]+h*u+h+|u+h+[\s-]+u+h+|u+m+[\s-]+h+m+)(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
        if let regex = try? NSRegularExpression(pattern: joinedPausePattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        let spokenPausePattern = #"(?i)(?<![\p{L}\p{N}])(?:u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+)(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
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

        filteredText = removeLeadingDiscourseFillers(from: filteredText)
        if hadLeadingPauseFillerNoise {
            filteredText = removeStandaloneAcknowledgementAfterPauseFiller(from: filteredText)
            filteredText = removeLeadingAcknowledgementFillerChain(from: filteredText)
            filteredText = removeLeadingSingleAcknowledgementFiller(from: filteredText)
        }
        if hadLeadingFillerNoise {
            filteredText = removeLeadingFragmentPunctuation(from: filteredText)
        }

        return filteredText
    }

    private static func preserveBacktrackingMarkersAfterPauseFillers(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)([,;:…]|\.\.\.)[ \t]+(?:u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+)(?:[.,;:!?…]+)?[ \t]+(actually(?:[ \t]+no|[ \t]+make[ \t]+it)?|better[ \t]+make[ \t]+it|sorry[ \t]+i[ \t]+mean|sorry[ \t]+i[ \t]+meant|what[ \t]+i[ \t]+mean[ \t]+is|i[ \t]+mean[ \t]+to[ \t]+say|i[ \t]+meant[ \t]+to[ \t]+say|i[ \t]+mean|i[ \t]+meant|i[ \t]+should[ \t]+say|make[ \t]+that|make[ \t]+it|call[ \t]+it|wait[ \t]+no|no[ \t]+wait|no[ \t]+actually|on[ \t]+second[ \t]+thought|let[ \t]+me[ \t]+rephrase|(?:just[ \t]+)?to[ \t]+clarify|(?:just[ \t]+)?to[ \t]+be[ \t]+clear|for[ \t]+clarity|rather|instead|oops|whoops|woops|my[ \t]+bad|correction)(?=\s)"#
        ) else {
            return text
        }

        var preservedText = text
        let matches = regex.matches(in: preservedText, range: NSRange(preservedText.startIndex..., in: preservedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: preservedText),
                  let punctuationRange = Range(match.range(at: 1), in: preservedText),
                  let markerRange = Range(match.range(at: 2), in: preservedText) else {
                continue
            }

            let prefix = String(preservedText[..<fullRange.lowerBound])
            guard shouldPreserveBacktrackingMarkerAfterPauseFiller(beforeMarker: prefix) else {
                continue
            }

            preservedText.replaceSubrange(
                fullRange,
                with: "\(preservedText[punctuationRange]) \(preservedText[markerRange])"
            )
        }

        return preservedText
    }

    private static func shouldPreserveBacktrackingMarkerAfterPauseFiller(beforeMarker text: String) -> Bool {
        guard wordCount(in: text) >= 2,
              let previousWord = previousWord(in: text) else {
            return false
        }

        return !["am", "are", "be", "been", "being", "is", "was", "were"].contains(previousWord)
    }

    private static func startsWithRemovableLeadingFillerNoise(_ text: String, fillerWords configuredFillerWords: [String]) -> Bool {
        let fillerWords = Set(configuredFillerWords + defaultFillerWords)
            .map { NSRegularExpression.escapedPattern(for: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        let pauseNoise = #"m+h+m+|m+[\s-]+h+m+|u+h+[\s-]+h*u+h+|u+h+[\s-]+u+h+|u+m+[\s-]+h+m+|u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+"#
        let discourseNoise = #"you[ \t]+know|i[ \t]+mean|like|ok(?:ay)?|all[ \t]+right|alright|right|yeah"#
        let pattern = #"(?i)^\s*(?:"# + [pauseNoise, discourseNoise, fillerWords]
            .filter { !$0.isEmpty }
            .joined(separator: "|") + #")(?:[.,;:!?…–—-]|\s)+"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func startsWithRemovableLeadingPauseFillerNoise(_ text: String, fillerWords configuredFillerWords: [String]) -> Bool {
        let fillerWords = Set(configuredFillerWords + defaultFillerWords)
            .map { NSRegularExpression.escapedPattern(for: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        let pauseNoise = #"m+h+m+|m+[\s-]+h+m+|u+h+[\s-]+h*u+h+|u+h+[\s-]+u+h+|u+m+[\s-]+h+m+|u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+"#
        let pattern = #"(?i)^\s*(?:"# + [pauseNoise, fillerWords]
            .filter { !$0.isEmpty }
            .joined(separator: "|") + #")(?:[.,;:!?…–—-]|\s)+"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
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

    private static func removeStandaloneAcknowledgementAfterPauseFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:(?:ok(?:ay)?|all[ \t]+right|alright|right|yeah)(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]*)+(?:[.!?]+)?$"#
        ) else {
            return text
        }

        let range = NSRange(trimmedText.startIndex..., in: trimmedText)
        guard regex.firstMatch(in: trimmedText, range: range) != nil,
              !isLiteralYeahRightAcknowledgementChain(trimmedText) else {
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

    private static func removeLeadingSingleAcknowledgementFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:ok(?:ay)?|all[ \t]+right|alright|right|yeah)(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]+"#
        ),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingFillerFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func removeLeadingAcknowledgementFillerChain(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:(?:ok(?:ay)?|all[ \t]+right|alright|right|yeah)(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]+){2,}"#
        ),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let chain = String(trimmedText[..<matchRange.upperBound])
        guard !isLiteralYeahRightAcknowledgementChain(chain) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingFillerFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func isLiteralYeahRightAcknowledgementChain(_ text: String) -> Bool {
        let tokens = wordTokens(in: text)
        guard tokens.count >= 2 else { return false }
        return tokens[0].text == "yeah" && tokens[1].text == "right"
    }

    private static func removeLeadingWellFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:(?:ok(?:ay)?|all[ \t]+right|alright|right|yeah)(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]+)?well(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]+"#
        ),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if isLeadingFillerFollowedByClauseStarter(suffix) {
            return suffix
        }

        var nestedSuffix = removeLeadingDiscourseFillers(from: suffix)
        nestedSuffix = removeLeadingUnpunctuatedDiscourseFiller(from: nestedSuffix)
        guard nestedSuffix != suffix,
              isLeadingFillerFollowedByClauseStarter(nestedSuffix) else {
            return text
        }

        return nestedSuffix
    }

    private static func removeLeadingUnpunctuatedDiscourseFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^(?:you[ \t]+know(?:[ \t]+what[ \t]+i[ \t]+mean)?|i[ \t]+mean)[ \t]+"#),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingFillerFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func removeLeadingUnpunctuatedLikeFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^like[ \t]+"#),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingLikeFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func isLeadingLikeFollowedByClauseStarter(_ text: String) -> Bool {
        isLeadingFillerFollowedByClauseStarter(text)
    }

    private static func removeLeadingBasicallyFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^basically(?:[ \t]*[,;:…]+)?[ \t]+"#),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingFillerFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func removeLeadingSoFiller(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^so(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]+"#),
              let match = regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
              let matchRange = Range(match.range, in: trimmedText) else {
            return text
        }

        let suffix = String(trimmedText[matchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLeadingFillerFollowedByClauseStarter(suffix) else {
            return text
        }

        return suffix
    }

    private static func isLeadingFillerFollowedByClauseStarter(_ text: String) -> Bool {
        let tokens = wordTokens(in: text)
        guard tokens.count >= 2 else { return false }

        let firstWord = tokens[0].text
        let secondWord = tokens[1].text
        guard leadingLikeClauseStarterPronouns.contains(firstWord) else {
            return false
        }

        if leadingLikeClauseStarterVerbs.contains(secondWord) {
            return true
        }

        guard tokens.count >= 3 else { return false }
        let thirdWord = tokens[2].text
        return secondWord == "really" && leadingLikeClauseStarterVerbs.contains(thirdWord)
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

    private static func removeTerminalAcknowledgementFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^([\s\S]*?)(?:[,;:…]|\.\.\.)[ \t]+(?:m+h+m+|m+[\s-]+h+m+|u+h+[\s-]+h*u+h+|u+h+[\s-]+u+h+|u+m+[\s-]+h+m+|u+h+|u+m+|h+m+|m+h+|m{2,}|(?-i:[aA]h+[eE][mM]+|[eE]h+[mM]+|[eE][hH]+m+)|e+h+|e+r+|a+h+|h+uh+)?(?:[.,;:!?…]+)?[ \t]*((?:(?:ok(?:ay)?|all[ \t]+right|alright|right|yeah)(?:[ \t]*(?:[,;:…]+|\.\.\.))?[ \t]*)+)([.!])\s*$"#
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 4,
              let prefixRange = Range(match.range(at: 1), in: text),
              let acknowledgementRange = Range(match.range(at: 2), in: text),
              let punctuationRange = Range(match.range(at: 3), in: text) else {
            return text
        }

        let trimmedPrefix = String(text[prefixRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: softPhrasePunctuation)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmedPrefix) >= 2,
              !isLiteralYeahRightAcknowledgementChain(String(text[acknowledgementRange])) else {
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

    private static func removeUnpunctuatedHedgeFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}])(?:kind[ \t]+of|sort[ \t]+of|kinda|sorta)(?:[ \t]*[,;:…]+)?(?![\p{L}\p{N}])"#
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
                  allowedNextWordsForUnpunctuatedHedgeFiller.contains(nextWord) else {
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

        formattedText = applyGuardedSpokenFormattingCommands(in: formattedText)
        formattedText = applySpokenSentenceBoundaryCommands(in: formattedText)
        return normalizeSpokenFormattingSpacing(formattedText)
    }

    private static func applyGuardedSpokenFormattingCommands(in text: String) -> String {
        var formattedText = text

        for command in guardedSpokenFormattingCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: formattedText) else {
                    continue
                }

                let prefix = String(formattedText[..<matchRange.lowerBound])
                if let previousWord = previousWord(in: prefix),
                   command.blockedPreviousWords.contains(previousWord) {
                    continue
                }

                let suffix = String(formattedText[matchRange.upperBound...])
                if let nextWord = nextWord(in: suffix),
                   command.blockedNextWords.contains(nextWord) {
                    continue
                }

                formattedText.replaceSubrange(matchRange, with: command.replacement)
            }
        }

        return formattedText
    }

    private static func applySpokenSentenceBoundaryCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenSentenceBoundaryCommandPattern) else {
            return text
        }

        var formattedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))
            var nextText: String?

            for match in matches {
                guard let matchRange = Range(match.range, in: formattedText),
                      let rewrittenText = rewriteSpokenSentenceBoundaryCommand(
                        in: formattedText,
                        commandRange: matchRange
                      ),
                      rewrittenText != formattedText else {
                    continue
                }

                nextText = rewrittenText
                break
            }

            guard let nextText else {
                break
            }

            formattedText = nextText
            rewriteCount += 1
        }

        return formattedText
    }

    private static func rewriteSpokenSentenceBoundaryCommand(
        in text: String,
        commandRange: Range<String.Index>
    ) -> String? {
        let beforeCommand = String(text[..<commandRange.lowerBound])
        let afterCommand = String(text[commandRange.upperBound...])

        guard let previousWord = previousWord(in: beforeCommand),
              !blockedPreviousWordsForSpokenSentenceBoundary.contains(previousWord),
              let nextWord = nextWord(in: afterCommand),
              !blockedNextWordsForSpokenSentenceBoundary.contains(nextWord) else {
            return nil
        }

        var prefix = beforeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        prefix = prefix.trimmingCharacters(in: softPhrasePunctuation)
        var suffix = afterCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        suffix = suffix.trimmingCharacters(in: softPhrasePunctuation)

        guard !prefix.isEmpty, !suffix.isEmpty else {
            return nil
        }

        if let lastCharacter = prefix.last, !".!?".contains(lastCharacter) {
            prefix += "."
        }

        return "\(prefix) \(uppercaseFirstLetterPreservingRest(in: suffix))"
    }

    private static func applySpokenEnclosureCommands(in text: String) -> String {
        var enclosedText = applySpokenQuotePairCommands(in: text)

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

    private static func applySpokenQuotePairCommands(in text: String) -> String {
        var quotedText = replaceSpokenQuotePairs(in: text, pattern: spokenDoubleQuotePairPattern, opening: "\"", closing: "\"")
        quotedText = replaceSpokenQuotePairs(in: quotedText, pattern: spokenSingleQuotePairPattern, opening: "'", closing: "'")
        quotedText = replaceSpokenPutEnclosures(in: quotedText)
        return quotedText
    }

    private static func replaceSpokenQuotePairs(
        in text: String,
        pattern: String,
        opening: String,
        closing: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        var quotedText = text
        let matches = regex.matches(in: quotedText, range: NSRange(quotedText.startIndex..., in: quotedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: quotedText),
                  let contentRange = Range(match.range(at: 1), in: quotedText) else {
                continue
            }

            let content = String(quotedText[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            let punctuation = optionalMatchText(in: quotedText, match: match, rangeIndex: 2) ?? ""
            quotedText.replaceSubrange(fullRange, with: "\(opening)\(content)\(closing)\(punctuation)")
        }

        return quotedText
    }

    private static func replaceSpokenPutEnclosures(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenPutEnclosurePattern) else {
            return text
        }

        var enclosedText = text
        let matches = regex.matches(in: enclosedText, range: NSRange(enclosedText.startIndex..., in: enclosedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range(at: 0), in: enclosedText),
                  let contentRange = Range(match.range(at: 1), in: enclosedText),
                  let targetRange = Range(match.range(at: 2), in: enclosedText),
                  let boundary = spokenEnclosureBoundary(for: String(enclosedText[targetRange])) else {
                continue
            }

            let content = String(enclosedText[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            let punctuation = optionalMatchText(in: enclosedText, match: match, rangeIndex: 3) ?? ""
            enclosedText.replaceSubrange(fullRange, with: "\(boundary.opening)\(content)\(boundary.closing)\(punctuation)")
        }

        return enclosedText
    }

    private static func spokenEnclosureBoundary(for text: String) -> (opening: String, closing: String)? {
        let normalizedText = normalizeWhitespace(text).lowercased()
        switch normalizedText {
        case "single quote", "single quotes":
            return ("'", "'")
        case "quote", "quotes", "quotation mark", "quotation marks":
            return ("\"", "\"")
        case "parenthesis", "parentheses", "paren", "parens":
            return ("(", ")")
        case "bracket", "brackets", "square bracket", "square brackets":
            return ("[", "]")
        case "brace", "braces", "curly brace", "curly braces":
            return ("{", "}")
        default:
            return nil
        }
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

    private static func applySpokenCLIFlagCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenLongCLIFlagPattern) else {
            return text
        }

        var flagText = text
        let matches = regex.matches(in: flagText, range: NSRange(flagText.startIndex..., in: flagText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: flagText),
                  let flagRange = Range(match.range(at: 1), in: flagText),
                  shouldApplySpokenCLIFlag(in: flagText, commandRange: fullRange) else {
                continue
            }

            let flagName = spokenCLIFlagName(from: String(flagText[flagRange]))
            guard !flagName.isEmpty else { continue }

            let prefix = String(flagText[..<fullRange.lowerBound])
            let separator = prefix.last.map { $0.isWhitespace || $0.isNewline ? "" : " " } ?? ""
            flagText.replaceSubrange(fullRange, with: "\(separator)--\(flagName)")
        }

        return flagText
    }

    private static func shouldApplySpokenCLIFlag(
        in text: String,
        commandRange: Range<String.Index>
    ) -> Bool {
        let beforeCommand = String(text[..<commandRange.lowerBound])
        let trimmedBefore = beforeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBefore.isEmpty else { return true }

        guard let previousWord = previousWord(in: beforeCommand),
              !["a", "an", "the"].contains(previousWord) else {
            return false
        }

        let allowedPreviousWords = [
            "add", "and", "argument", "arguments", "args", "command", "enter", "flag", "option",
            "or", "pass", "run", "then", "type", "use", "using", "with", "without"
        ]
        if allowedPreviousWords.contains(previousWord) {
            return true
        }

        let lowercasedLine = currentLinePrefix(in: beforeCommand).lowercased()
        let cliContextPattern = #"(?i)(?:^|\s)(?:run|execute|terminal|shell|command|git|gh|npm|pnpm|yarn|node|python|swift|cargo|docker|brew|curl)\b"#
        guard let regex = try? NSRegularExpression(pattern: cliContextPattern) else {
            return false
        }

        return regex.firstMatch(in: lowercasedLine, range: NSRange(lowercasedLine.startIndex..., in: lowercasedLine)) != nil
    }

    private static func spokenCLIFlagName(from text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"(?i)[ \t]+(?:dash|hyphen)[ \t]+"#,
                with: "-",
                options: .regularExpression
            )
            .lowercased()
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

        if command.output == "-",
           hasAdjacentSpokenDashWord(before: beforeCommand, after: afterCommand) {
            return false
        }

        if command.requiresCompactContext,
           !hasCompactSymbolContext(command: command, before: beforeCommand, after: afterCommand) {
            return false
        }

        return true
    }

    private static func hasAdjacentSpokenDashWord(before: String, after: String) -> Bool {
        let dashWords = Set(["dash", "hyphen"])
        return previousWord(in: before).map { dashWords.contains($0) } == true ||
            nextWord(in: after).map { dashWords.contains($0) } == true
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

        return ordinalDayValues[normalizedText]
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

    private static func applySpokenNoSpaceCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenNoSpaceCommandPattern) else {
            return text
        }

        var compactText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(compactText.startIndex..., in: compactText)
            let matches = regex.matches(in: compactText, range: fullRange)
            var didRewrite = false

            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let fullRange = Range(match.range(at: 0), in: compactText),
                      let previousRange = Range(match.range(at: 1), in: compactText),
                      let nextRange = Range(match.range(at: 2), in: compactText) else {
                    continue
                }

                let previousWord = String(compactText[previousRange]).lowercased()
                let nextWord = String(compactText[nextRange]).lowercased()
                guard !blockedPreviousWordsForSpokenNoSpace.contains(previousWord),
                      !blockedNextWordsForSpokenNoSpace.contains(nextWord) else {
                    continue
                }

                compactText.replaceSubrange(fullRange, with: "\(compactText[previousRange])\(compactText[nextRange])")
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return compactText
    }

    private static func applyCommonTechnicalAcronymCasing(in text: String) -> String {
        let acronymPattern = commonTechnicalAcronyms.keys
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_./@:+#'-])(\#(acronymPattern))(?![\p{L}\p{N}_/@:+#'-]|\.[\p{L}\p{N}])"#
        ) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let acronymRange = Range(match.range(at: 1), in: formattedText),
                  shouldApplyCommonTechnicalAcronymCasing(in: formattedText, acronymRange: fullRange) else {
                continue
            }

            let key = String(formattedText[acronymRange]).lowercased()
            guard let replacement = commonTechnicalAcronyms[key] else { continue }
            formattedText.replaceSubrange(fullRange, with: replacement)
        }

        return formattedText
    }

    private static func shouldApplyCommonTechnicalAcronymCasing(
        in text: String,
        acronymRange: Range<String.Index>
    ) -> Bool {
        let beforeAcronym = String(text[..<acronymRange.lowerBound])
        let afterAcronym = String(text[acronymRange.upperBound...])

        if let previousWord = previousWord(in: beforeAcronym),
           ["lowercase", "literal", "phrase", "word"].contains(previousWord) {
            return false
        }

        if let nextWord = nextWord(in: afterAcronym),
           ["lowercase", "phrase", "word"].contains(nextWord) {
            return false
        }

        return !hasCompactAcronymDotContext(in: text, acronymRange: acronymRange)
    }

    private static func hasCompactAcronymDotContext(
        in text: String,
        acronymRange: Range<String.Index>
    ) -> Bool {
        if acronymRange.lowerBound > text.startIndex {
            let previousIndex = text.index(before: acronymRange.lowerBound)
            if text[previousIndex] == "." {
                return true
            }
        }

        guard acronymRange.upperBound < text.endIndex,
              text[acronymRange.upperBound] == "." else {
            return false
        }

        let afterDotIndex = text.index(after: acronymRange.upperBound)
        return afterDotIndex < text.endIndex &&
            (text[afterDotIndex].isLetter || text[afterDotIndex].isNumber)
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

    private static func applySpokenTextCaseCommands(in text: String) -> String {
        var formattedText = text

        for command in spokenTextCaseCommands {
            guard let regex = try? NSRegularExpression(pattern: command.pattern) else {
                continue
            }

            let fullRange = NSRange(formattedText.startIndex..., in: formattedText)
            let matches = regex.matches(in: formattedText, range: fullRange).reversed()

            for match in matches {
                guard match.numberOfRanges >= 2,
                      let commandRange = Range(match.range(at: 0), in: formattedText),
                      let phraseRange = Range(match.range(at: 1), in: formattedText),
                      shouldApplySpokenTextCaseCommand(in: formattedText, commandRange: commandRange, phraseRange: phraseRange) else {
                    continue
                }

                let phrase = String(formattedText[phraseRange])
                let replacement = formatSpokenTextCasePhrase(phrase, style: command.style)
                formattedText.replaceSubrange(commandRange.lowerBound..<phraseRange.upperBound, with: replacement)
            }
        }

        return formattedText
    }

    private static func shouldApplySpokenTextCaseCommand(
        in text: String,
        commandRange: Range<String.Index>,
        phraseRange: Range<String.Index>
    ) -> Bool {
        let phraseWords = textCaseWords(in: String(text[phraseRange]))
        guard let firstWord = phraseWords.first,
              !blockedFirstWordsForSpokenTextCase.contains(firstWord),
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
        return allowedPreviousWordsForSpokenTextCase.contains(previousWord)
    }

    private static func formatSpokenTextCasePhrase(_ phrase: String, style: SpokenTextCaseStyle) -> String {
        let normalizedPhrase = normalizeWhitespace(phrase)
        guard !normalizedPhrase.isEmpty else { return normalizedPhrase }

        switch style {
        case .allCaps:
            return normalizedPhrase.uppercased()
        case .lowercase:
            return normalizedPhrase.lowercased()
        case .capitalize:
            return capitalizeFirstTextCaseWord(normalizedPhrase)
        case .title:
            return titleCasedTextCasePhrase(normalizedPhrase)
        }
    }

    private static func textCaseWords(in phrase: String) -> [String] {
        phrase
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
    }

    private static func capitalizeFirstTextCaseWord(_ phrase: String) -> String {
        var result = phrase.lowercased()
        guard let firstLetterRange = result.rangeOfCharacter(from: .letters) else {
            return result
        }

        result.replaceSubrange(firstLetterRange, with: String(result[firstLetterRange]).uppercased())
        return result
    }

    private static func uppercaseFirstLetterPreservingRest(in text: String) -> String {
        var result = text
        guard let firstLetterRange = result.rangeOfCharacter(from: .letters) else {
            return result
        }

        result.replaceSubrange(firstLetterRange, with: String(result[firstLetterRange]).uppercased())
        return result
    }

    private static func titleCasedTextCasePhrase(_ phrase: String) -> String {
        phrase
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token -> String in
                let lowercasedToken = String(token).lowercased()
                guard let firstLetterRange = lowercasedToken.rangeOfCharacter(from: .letters) else {
                    return lowercasedToken
                }

                var titleToken = lowercasedToken
                titleToken.replaceSubrange(firstLetterRange, with: String(titleToken[firstLetterRange]).uppercased())
                return titleToken
            }
            .joined(separator: " ")
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
        formattedText = applySpokenMarkdownTables(in: formattedText)
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
        let taskText = applySpokenMarkdownTaskCommand(
            in: checkedText,
            pattern: uncheckedMarkdownTaskPattern,
            state: .unchecked
        )
        return splitNestedSpokenMarkdownTasks(in: taskText)
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

    private static func splitNestedSpokenMarkdownTasks(in text: String) -> String {
        var formattedText = text

        for _ in 0..<8 {
            guard let splitText = splitFirstNestedSpokenMarkdownTask(in: formattedText) else {
                break
            }

            formattedText = splitText
        }

        return formattedText
    }

    private static func splitFirstNestedSpokenMarkdownTask(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^- \[(?: |x)\] [^\n]+$"#) else {
            return nil
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let lineRange = Range(match.range, in: text) else {
                continue
            }

            let line = String(text[lineRange])
            guard let splitLine = splitNestedSpokenMarkdownTaskLine(line) else {
                continue
            }

            var splitText = text
            splitText.replaceSubrange(lineRange, with: splitLine)
            return splitText
        }

        return nil
    }

    private static func splitNestedSpokenMarkdownTaskLine(_ line: String) -> String? {
        let prefixes = ["- [ ] ", "- [x] "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else {
            return nil
        }

        let contentStart = line.index(line.startIndex, offsetBy: prefix.count)
        let content = String(line[contentStart...])
        guard let command = firstNestedSpokenMarkdownTaskCommand(in: content),
              command.range.lowerBound > content.startIndex else {
            return nil
        }

        let beforeContent = markdownLineContent(String(content[..<command.range.lowerBound]))
        let afterContent = markdownLineContent(String(content[command.range.upperBound...]))
        guard !beforeContent.isEmpty,
              !afterContent.isEmpty,
              shouldApplySpokenMarkdownLineCommand(to: afterContent) else {
            return nil
        }

        let checkbox = command.state == .checked ? "[x]" : "[ ]"
        return "\(prefix)\(beforeContent)\n- \(checkbox) \(afterContent)"
    }

    private static func firstNestedSpokenMarkdownTaskCommand(in content: String) -> SpokenMarkdownTaskCommandMatch? {
        let uncheckedCommand = firstNestedSpokenMarkdownTaskCommand(
            in: content,
            pattern: nestedUncheckedMarkdownTaskCommandPattern,
            state: .unchecked
        )
        let checkedCommand = firstNestedSpokenMarkdownTaskCommand(
            in: content,
            pattern: nestedCheckedMarkdownTaskCommandPattern,
            state: .checked
        )

        return [uncheckedCommand, checkedCommand]
            .compactMap { $0 }
            .min { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func firstNestedSpokenMarkdownTaskCommand(
        in content: String,
        pattern: String,
        state: SpokenMarkdownTaskState
    ) -> SpokenMarkdownTaskCommandMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        for match in matches {
            guard let range = Range(match.range, in: content) else {
                continue
            }

            let suffix = String(content[range.upperBound...])
            if let nextWord = nextWord(in: suffix),
               blockedNextWordsForNestedMarkdownTaskCommand.contains(nextWord) {
                continue
            }

            return SpokenMarkdownTaskCommandMatch(range: range, state: state)
        }

        return nil
    }

    private static func applySpokenMarkdownTables(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: markdownTablePattern) else {
            return text
        }

        var formattedText = text
        let matches = regex.matches(in: formattedText, range: NSRange(formattedText.startIndex..., in: formattedText))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: formattedText),
                  let prefixRange = Range(match.range(at: 1), in: formattedText),
                  let bodyRange = Range(match.range(at: 2), in: formattedText),
                  let table = markdownTable(from: String(formattedText[bodyRange])) else {
                continue
            }

            let prefix = String(formattedText[prefixRange])
            formattedText.replaceSubrange(fullRange, with: "\(prefix)\(table)")
        }

        return formattedText
    }

    private static func markdownTable(from spokenBody: String) -> String? {
        let rows = splitSpokenMarkdownTableRows(spokenBody).map { markdownTableCells(from: $0) }
        guard rows.count >= 2,
              let columnCount = rows.first?.count,
              (2...4).contains(columnCount),
              rows.allSatisfy({ $0.count == columnCount }),
              rows.flatMap({ $0 }).allSatisfy({ shouldApplySpokenMarkdownLineCommand(to: $0) }) else {
            return nil
        }

        let header = markdownTableRow(rows[0])
        let separator = markdownTableRow(Array(repeating: "---", count: columnCount))
        let bodyRows = rows.dropFirst().map(markdownTableRow)
        return ([header, separator] + bodyRows).joined(separator: "\n")
    }

    private static func splitSpokenMarkdownTableRows(_ text: String) -> [String] {
        splitSpokenMarkdownTableComponents(text, separatorPattern: #"(?i)(?<![\p{L}\p{N}])row(?![\p{L}\p{N}])"#)
    }

    private static func markdownTableCells(from row: String) -> [String] {
        let normalizedRow = markdownLineContent(row)
        guard !normalizedRow.isEmpty else { return [] }

        let explicitCells = splitSpokenMarkdownTableComponents(
            normalizedRow,
            separatorPattern: #"(?i)(?<![\p{L}\p{N}])(?:column|pipe)(?![\p{L}\p{N}])"#
        )
        if explicitCells.count > 1 {
            return explicitCells.map(markdownTableCell).filter { !$0.isEmpty }
        }

        return normalizedRow
            .split(whereSeparator: \.isWhitespace)
            .map { markdownTableCell(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func splitSpokenMarkdownTableComponents(_ text: String, separatorPattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else {
            return [text]
        }

        var components: [String] = []
        var currentIndex = text.startIndex
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let component = String(text[currentIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !component.isEmpty {
                components.append(component)
            }
            currentIndex = range.upperBound
        }

        let finalComponent = String(text[currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalComponent.isEmpty {
            components.append(finalComponent)
        }

        return components
    }

    private static func markdownTableRow(_ cells: [String]) -> String {
        "| \(cells.joined(separator: " | ")) |"
    }

    private static func markdownTableCell(_ text: String) -> String {
        markdownLineContent(text).replacingOccurrences(of: "|", with: "\\|")
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

            if isAtMarkdownLineStart(in: text, markerStart: markerRange.lowerBound) {
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

    private static func isAtMarkdownLineStart(in text: String, markerStart: String.Index) -> Bool {
        let lineStart = text[..<markerStart].lastIndex(of: "\n")
            .map { text.index(after: $0) } ?? text.startIndex

        return text[lineStart..<markerStart].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func applySpokenNumberedOutlineCommands(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var didRewrite = false

        let rewrittenLines = lines.map { line -> String in
            guard let outline = spokenNumberedOutline(from: line) else {
                return line
            }

            didRewrite = true
            return outline
        }

        return didRewrite ? rewrittenLines.joined(separator: "\n") : text
    }

    private static func spokenNumberedOutline(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: spokenSequenceListMarkerPattern) else {
            return nil
        }

        let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        guard matches.count >= 2,
              let firstMatch = matches.first,
              let firstRange = Range(firstMatch.range(at: 0), in: line),
              line[..<firstRange.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        var items: [(value: Int, content: String, levelDelta: Int?)] = []
        var sawNestingCommand = false

        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: line),
                  let markerRange = Range(match.range(at: 1), in: line),
                  let value = spokenSequenceListMarkerValues[String(line[markerRange]).lowercased()] else {
                return nil
            }

            let nextStart = index + 1 < matches.count
                ? Range(matches[index + 1].range(at: 0), in: line)?.lowerBound
                : line.endIndex
            guard let contentEnd = nextStart else { return nil }

            let rawContent = markdownLineContent(String(line[fullRange.upperBound..<contentEnd]))
            let command = trailingNestedBulletCommand(in: rawContent)
            let visibleContent = command?.content ?? rawContent
            guard !visibleContent.isEmpty else { return nil }

            if command != nil { sawNestingCommand = true }
            items.append((value: value, content: visibleContent, levelDelta: command?.levelDelta))
        }

        guard sawNestingCommand,
              items.first?.value == 1 else {
            return nil
        }

        var nestingLevel = 0
        return items.map { item in
            let indentation = String(repeating: "  ", count: nestingLevel)
            let line = "\(indentation)\(item.value). \(item.content)"
            if let levelDelta = item.levelDelta {
                nestingLevel = max(0, nestingLevel + levelDelta)
            }
            return line
        }.joined(separator: "\n")
    }

    private static func replaceSpokenSequenceListMarkers(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: spokenSequenceListMarkerPattern) else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let markers = matches.compactMap { match -> SpokenSequenceListMarker? in
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: text),
                  let markerRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            let markerText = String(text[markerRange]).lowercased()
            guard let value = spokenSequenceListMarkerValues[markerText] else { return nil }

            let beforeMarker = String(text[..<fullRange.lowerBound])
            if let previousWord = previousWord(in: beforeMarker),
               blockedPreviousWordsForSpokenSequenceListMarkers.contains(previousWord) {
                return nil
            }

            let afterMarker = String(text[fullRange.upperBound...])
            if let nextWord = nextWord(in: afterMarker),
               blockedNextWordsForSpokenSequenceListMarkers.contains(nextWord) {
                return nil
            }

            return SpokenSequenceListMarker(range: fullRange, value: value)
        }

        let replacementIndices = spokenSequenceListRunIndices(in: markers)
        guard !replacementIndices.isEmpty else { return text }

        var listText = text
        for index in replacementIndices.sorted(by: >) {
            let marker = markers[index]
            listText.replaceSubrange(marker.range, with: "\(marker.value). ")
        }

        return listText
    }

    private static func spokenSequenceListRunIndices(in markers: [SpokenSequenceListMarker]) -> Set<Int> {
        var replacementIndices: Set<Int> = []
        var runStart = 0

        while runStart < markers.count {
            guard markers[runStart].value == 1 else {
                runStart += 1
                continue
            }

            var run = [runStart]
            var nextExpectedValue = 2
            var cursor = runStart + 1

            while cursor < markers.count, markers[cursor].value == nextExpectedValue {
                run.append(cursor)
                nextExpectedValue += 1
                cursor += 1
            }

            if run.count >= 2 {
                replacementIndices.formUnion(run)
                runStart = cursor
            } else {
                runStart += 1
            }
        }

        return replacementIndices
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
        let protectedText = protectPunctuationSpacingSpans(in: text)
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
                of: #"\.\s+\.\s+\."#,
                with: "...",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\.{4,}"#,
                with: "...",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(\b\d{1,2}):\s+(\d{2}\s+(?:AM|PM)\b)"#,
                with: "$1:$2",
                options: .regularExpression
            )

        return restoreProtectedPunctuationSpacingSpans(in: normalizedText, spans: protectedText.spans)
    }

    private static func normalizeDuplicatePhrasePunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"([,;:!?])\1+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[,;:]+([.!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([.!?])[,;:]+"#, with: "$1", options: .regularExpression)
    }

    private static func protectPunctuationSpacingSpans(in text: String) -> (text: String, spans: [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b\d{1,2}:\d{2}(?::\d{2})?(?:\.\d{1,3})?\b|\b(?:https?://|www\.)[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+|\b[A-Za-z][A-Za-z0-9_-]{1,63}\.[A-Za-z][A-Za-z0-9_-]{1,63}(?:\.[A-Za-z][A-Za-z0-9_-]{1,63})*\b|(?<![\p{L}\p{N}])(?:[A-Za-z]{1,4}\.){2,}(?![\p{L}\p{N}])|(?<![\p{L}\p{N}])\.[A-Za-z][A-Za-z0-9._-]{0,63}"#
        ) else {
            return (text, [])
        }

        var protectedText = text
        var spans: [String] = []
        let matches = regex.matches(in: protectedText, range: NSRange(protectedText.startIndex..., in: protectedText))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: protectedText) else {
                continue
            }

            spans.append(String(protectedText[range]))
            protectedText.replaceSubrange(range, with: "__VOICEINK_PUNCT_SPAN_\(spans.count - 1)__")
        }

        return (protectedText, spans)
    }

    private static func restoreProtectedPunctuationSpacingSpans(in text: String, spans: [String]) -> String {
        var restoredText = text
        for (index, span) in spans.enumerated() {
            restoredText = restoredText.replacingOccurrences(of: "__VOICEINK_PUNCT_SPAN_\(index)__", with: span)
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
            .replacingOccurrences(of: #"[ \t]*\t[ \t]*"#, with: "\t", options: .regularExpression)
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

    private static func applyNestedBulletCommands(in text: String) -> String {
        var nestingLevel = 0
        var didRewrite = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let rewrittenLines = lines.map { line -> String in
            guard let content = bulletLineContent(in: line) else {
                nestingLevel = 0
                return line
            }

            var visibleContent = content
            if let command = trailingNestedBulletCommand(in: visibleContent) {
                visibleContent = command.content
                didRewrite = true
            }

            let indentation = String(repeating: "  ", count: nestingLevel)
            let rewrittenLine = "\(indentation)- \(visibleContent)"

            if let command = trailingNestedBulletCommand(in: content) {
                nestingLevel = max(0, nestingLevel + command.levelDelta)
            }

            return rewrittenLine
        }

        return didRewrite ? rewrittenLines.joined(separator: "\n") : text
    }

    private static func bulletLineContent(in line: String) -> String? {
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix("- ") else {
            return nil
        }

        return String(trimmedLeading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func trailingNestedBulletCommand(in content: String) -> (content: String, levelDelta: Int)? {
        let commandPatterns: [(pattern: String, levelDelta: Int)] = [
            (#"(?i)(?:^|[ \t]+)(?:indent|increase[ \t]+indent|sub)(?:[.!?])?[ \t]*$"#, 1),
            (#"(?i)(?:^|[ \t]+)(?:outdent|dedent|decrease[ \t]+indent)(?:[.!?])?[ \t]*$"#, -1)
        ]

        for commandPattern in commandPatterns {
            guard let regex = try? NSRegularExpression(pattern: commandPattern.pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let commandRange = Range(match.range, in: content) else {
                continue
            }

            let visibleContent = String(content[..<commandRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            return (visibleContent, commandPattern.levelDelta)
        }

        return nil
    }

    private static func leadingSpokenFormattingNewlineCount(in text: String) -> Int {
        for command in spokenFormattingCommands where command.replacement == "\n" || command.replacement == "\n\n" {
            if let count = leadingSpokenFormattingNewlineCount(
                in: text,
                pattern: command.pattern,
                replacement: command.replacement,
                blockedNextWords: []
            ) {
                return count
            }
        }

        for command in guardedSpokenFormattingCommands where command.replacement == "\n" || command.replacement == "\n\n" {
            if let count = leadingSpokenFormattingNewlineCount(
                in: text,
                pattern: command.pattern,
                replacement: command.replacement,
                blockedNextWords: command.blockedNextWords
            ) {
                return count
            }
        }

        return 0
    }

    private static func leadingSpokenFormattingNewlineCount(
        in text: String,
        pattern: String,
        replacement: String,
        blockedNextWords: Set<String>
    ) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        let prefix = text[..<matchRange.lowerBound]
        guard prefix.allSatisfy(\.isWhitespace) else { return nil }

        let suffix = String(text[matchRange.upperBound...])
        if let nextWord = nextWord(in: suffix),
           blockedNextWords.contains(nextWord) {
            return nil
        }

        return replacement.filter(\.isNewline).count
    }

    private static func restoreLeadingNewlines(_ count: Int, to text: String) -> String {
        guard count > 0,
              text.first?.isNewline != true else {
            return text
        }

        return String(repeating: "\n", count: count) + text
    }

    private static func leadingNewlineCount(in text: String) -> Int {
        var count = 0
        for character in text {
            guard character.isNewline else { break }
            count += 1
        }
        return count
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

        correctedText = applyDeletePreviousWordCommands(in: correctedText)
        correctedText = applyDeletePreviousSentenceCommands(in: correctedText)
        return applyScratchThatCommands(in: correctedText)
    }

    private static func rewriteBacktrackingMatch(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let markerText = String(text[markerRange])
        let afterMarker = correctionSourceAfterNestedIntro(
            String(text[markerRange.upperBound...]),
            markerText: markerText
        )

        guard let correction = leadingCorrectionPhrase(in: afterMarker) else {
            return nil
        }

        let boundedCorrection = boundedLeadingCorrection(
            correction,
            markerText: markerText,
            in: afterMarker,
            beforeMarker: beforeMarker
        )
        let correctionText = boundedCorrection.replacementText ?? String(afterMarker[boundedCorrection.range])
        guard shouldApplyBacktrackingMarker(
            markerText,
            beforeMarker: beforeMarker,
            correctionText: correctionText
        ),
              let prefix = removeTrailingWords(
                removalWordCount(for: correctionText, fallback: boundedCorrection.removalWordCount, beforeMarker: beforeMarker),
                from: beforeMarker
              ) else {
            return nil
        }

        let suffix = String(afterMarker[boundedCorrection.range.upperBound...])
        return normalizeBacktrackingWhitespace(join(prefix, correctionText, suffix))
    }

    private static func boundedLeadingCorrection(
        _ correction: (range: Range<String.Index>, wordCount: Int),
        markerText: String,
        in text: String,
        beforeMarker: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    ) {
        let defaultCorrection = (
            range: correction.range,
            wordCount: correction.wordCount,
            removalWordCount: correction.wordCount,
            replacementText: Optional<String>.none
        )
        guard isSingleWordReplacementBacktrackingMarker(markerText) else {
            return defaultCorrection
        }

        let correctionTokens = wordTokens(in: text, range: correction.range)
        guard let firstToken = correctionTokens.first else {
            return defaultCorrection
        }

        if let sourceTimeWordCount = trailingSpokenTimeWordCount(in: beforeMarker),
           let correctionTimeWordCount = leadingSpokenTimeWordCount(in: correctionTokens.map { $0.text }) ??
            (spokenHourValue(firstToken.text) == nil ? nil : 1) {
            let timeRange = firstToken.range.lowerBound..<correctionTokens[correctionTimeWordCount - 1].range.upperBound
            return (timeRange, correctionTimeWordCount, sourceTimeWordCount, nil)
        }

        if let dateCorrection = boundedSpokenDateCorrection(
            beforeMarker: beforeMarker,
            correctionTokens: correctionTokens,
            in: text
        ) {
            return dateCorrection
        }

        if let amountCorrection = boundedSpokenAmountCorrection(
            beforeMarker: beforeMarker,
            correctionTokens: correctionTokens,
            in: text
        ) {
            return amountCorrection
        }

        if let textCaseCorrection = boundedSpokenTextCaseCorrection(
            beforeMarker: beforeMarker,
            correctionTokens: correctionTokens,
            in: text
        ) {
            return textCaseCorrection
        }

        if let codeCaseCorrection = boundedSpokenCodeCaseCorrection(
            beforeMarker: beforeMarker,
            correctionTokens: correctionTokens
        ) {
            return codeCaseCorrection
        }

        if let markdownCorrection = boundedSpokenMarkdownCorrection(
            beforeMarker: beforeMarker,
            correctionTokens: correctionTokens
        ) {
            return markdownCorrection
        }

        if let markdownLinkCorrection = boundedSpokenMarkdownLinkCorrection(
            beforeMarker: beforeMarker,
            in: text
        ) {
            return markdownLinkCorrection
        }

        if let compactTokenCorrection = boundedSpokenCompactTokenCorrection(
            beforeMarker: beforeMarker,
            in: text
        ) {
            return compactTokenCorrection
        }

        guard correction.wordCount > 1 else {
            return defaultCorrection
        }

        return (firstToken.range, 1, 1, nil)
    }

    private static func correctionSourceAfterNestedIntro(_ text: String, markerText: String) -> String {
        switch normalizedBacktrackingMarker(markerText) {
        case "oops", "whoops", "woops", "my bad", "correction", "sorry", "no sorry":
            break
        default:
            return text
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^\s*(?:actually|i\s+mean|i\s+meant)\s*[,;:]?\s+"#
        ) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return text
        }

        let suffix = String(text[matchRange.upperBound...])
        guard firstWord(in: suffix) != nil else {
            return text
        }

        return suffix
    }

    private static func removalWordCount(for correctionText: String, fallback wordCount: Int, beforeMarker: String) -> Int {
        guard wordCount > 1,
              let firstCorrectionWord = firstWord(in: correctionText),
              ["a", "an", "the"].contains(firstCorrectionWord) else {
            return wordCount
        }

        let contentWordCount = wordCount - 1
        guard trailingWords(contentWordCount + 1, in: beforeMarker).first.map({ ["a", "an", "the"].contains($0) }) == true else {
            return contentWordCount
        }

        return wordCount
    }

    private static func trailingWords(_ count: Int, in text: String) -> [String] {
        guard count > 0 else { return [] }

        var words: [String] = []
        var wordEnd = text.endIndex

        while words.count < count {
            wordEnd = indexBeforeTrailingNoise(in: text, from: wordEnd)
            guard wordEnd > text.startIndex else { break }

            var wordStart = wordEnd
            while wordStart > text.startIndex {
                let previousIndex = text.index(before: wordStart)
                guard isWordCharacter(text[previousIndex]) else { break }
                wordStart = previousIndex
            }

            guard wordStart < wordEnd else { break }
            words.append(String(text[wordStart..<wordEnd]).lowercased())
            wordEnd = wordStart
        }

        return words.reversed()
    }

    private static func boundedSpokenTextCaseCorrection(
        beforeMarker: String,
        correctionTokens: [WordToken],
        in text: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceTail = trailingSpokenTextCaseTail(in: beforeMarker),
              let correctionWordCount = leadingTextCaseArgumentWordCount(in: correctionTokens.map { $0.text }) else {
            return nil
        }

        let correctionRange = correctionTokens[0].range.lowerBound..<correctionTokens[correctionWordCount - 1].range.upperBound
        let replacement = formatSpokenTextCasePhrase(String(text[correctionRange]), style: sourceTail.style)
        return (correctionRange, correctionWordCount, sourceTail.wordCount, replacement)
    }

    private static func trailingSpokenTextCaseTail(in text: String) -> SpokenTextCaseTail? {
        let tokens = wordTokens(in: text)
        guard tokens.count >= 2 else { return nil }

        let maxCandidateCount = min(7, tokens.count)
        for wordCount in stride(from: maxCandidateCount, through: 2, by: -1) {
            let candidateTokens = Array(tokens.suffix(wordCount))
            let candidateWords = candidateTokens.map { $0.text }
            guard let style = leadingTextCaseStyle(in: candidateWords),
                  candidateWords.count > style.wordCount,
                  shouldUseSpokenTextCaseCommandTail(
                    in: text,
                    commandStart: candidateTokens[0].range.lowerBound
                  ) else {
                continue
            }

            let argumentWords = Array(candidateWords.dropFirst(style.wordCount))
            guard isTextCaseArgumentWords(argumentWords) else {
                continue
            }

            return SpokenTextCaseTail(wordCount: wordCount, style: style.style)
        }

        return nil
    }

    private static func leadingTextCaseArgumentWordCount(in words: [String]) -> Int? {
        var maxArgumentWordCount = min(5, words.count)
        while maxArgumentWordCount > 1,
              isCommandArgumentContinuationWord(words[maxArgumentWordCount - 1]) {
            maxArgumentWordCount -= 1
        }

        for wordCount in stride(from: maxArgumentWordCount, through: 1, by: -1) {
            let candidate = Array(words.prefix(wordCount))
            guard isTextCaseArgumentWords(candidate) else { continue }
            return wordCount
        }

        return nil
    }

    private static func leadingTextCaseStyle(in words: [String]) -> (wordCount: Int, style: SpokenTextCaseStyle)? {
        guard let firstWord = words.first else { return nil }

        switch firstWord {
        case "uppercase":
            return (1, .allCaps)
        case "upper" where words.count >= 2 && words[1] == "case":
            return (2, .allCaps)
        case "all" where words.count >= 2 && words[1] == "caps":
            return (2, .allCaps)
        case "lowercase":
            return (1, .lowercase)
        case "lower" where words.count >= 2 && words[1] == "case":
            return (2, .lowercase)
        case "capitalize", "capitalise":
            return (1, .capitalize)
        case "title" where words.count >= 2 && words[1] == "case":
            return (2, .title)
        default:
            return nil
        }
    }

    private static func shouldUseSpokenTextCaseCommandTail(
        in text: String,
        commandStart: String.Index
    ) -> Bool {
        let beforeCommand = String(text[..<commandStart])
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

        return allowedPreviousWordsForSpokenTextCase.contains(previousWord)
    }

    private static func isTextCaseArgumentWords(_ words: [String]) -> Bool {
        guard let firstWord = words.first,
              !blockedFirstWordsForSpokenTextCase.contains(firstWord),
              words.count <= 5 else {
            return false
        }

        return words.allSatisfy { word in
            !["for", "from", "in", "into", "is", "means", "on", "to", "with"].contains(word)
        }
    }

    private static func isCommandArgumentContinuationWord(_ word: String) -> Bool {
        ["again", "later", "now", "please", "today", "tomorrow"].contains(word)
    }

    private static func boundedSpokenCodeCaseCorrection(
        beforeMarker: String,
        correctionTokens: [WordToken]
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceTail = trailingSpokenCodeCaseTail(in: beforeMarker),
              let correctionWordCount = leadingCodeCaseArgumentWordCount(in: correctionTokens.map { $0.text }) else {
            return nil
        }

        let correctionRange = correctionTokens[0].range.lowerBound..<correctionTokens[correctionWordCount - 1].range.upperBound
        return (correctionRange, correctionWordCount, sourceTail.argumentWordCount, nil)
    }

    private static func trailingSpokenCodeCaseTail(in text: String) -> SpokenCodeCaseTail? {
        let words = wordTokens(in: text).map { $0.text }
        guard words.count >= 3 else { return nil }

        let maxCandidateCount = min(7, words.count)
        for wordCount in stride(from: maxCandidateCount, through: 3, by: -1) {
            let candidate = Array(words.suffix(wordCount))
            guard let styleWordCount = leadingCodeCaseStyleWordCount(in: candidate),
                  candidate.count > styleWordCount else {
                continue
            }

            let argumentWords = Array(candidate.dropFirst(styleWordCount))
            guard isCodeCaseArgumentWords(argumentWords) else {
                continue
            }

            return SpokenCodeCaseTail(argumentWordCount: argumentWords.count)
        }

        return nil
    }

    private static func leadingCodeCaseArgumentWordCount(in words: [String]) -> Int? {
        let maxArgumentWordCount = min(5, words.count)
        for wordCount in stride(from: maxArgumentWordCount, through: 1, by: -1) {
            let candidate = Array(words.prefix(wordCount))
            guard isCodeCaseArgumentWords(candidate) else { continue }
            return wordCount
        }

        return nil
    }

    private static func leadingCodeCaseStyleWordCount(in words: [String]) -> Int? {
        guard words.count >= 2,
              words[1] == "case" else {
            return nil
        }

        if ["camel", "snake", "pascal"].contains(words[0]) {
            return 2
        }

        if ["kebab", "dash", "hyphen"].contains(words[0]) {
            return 2
        }

        return nil
    }

    private static func isCodeCaseArgumentWords(_ words: [String]) -> Bool {
        guard let firstWord = words.first,
              !blockedFirstWordsForSpokenCodeCase.contains(firstWord),
              words.count <= 5 else {
            return false
        }

        return words.allSatisfy { word in
            !["for", "from", "in", "into", "on", "to", "with"].contains(word)
        }
    }

    private static func boundedSpokenMarkdownCorrection(
        beforeMarker: String,
        correctionTokens: [WordToken]
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceTail = trailingSpokenMarkdownTail(in: beforeMarker),
              let correctionWordCount = leadingMarkdownArgumentWordCount(
                in: correctionTokens.map { $0.text },
                maxWordCount: sourceTail.maxCorrectionWordCount,
                kind: sourceTail.kind
              ) else {
            return nil
        }

        let correctionRange = correctionTokens[0].range.lowerBound..<correctionTokens[correctionWordCount - 1].range.upperBound
        return (correctionRange, correctionWordCount, sourceTail.argumentWordCount, nil)
    }

    private static func trailingSpokenMarkdownTail(in text: String) -> SpokenMarkdownTail? {
        let tokens = wordTokens(in: text)
        let words = tokens.map { $0.text }
        guard tokens.count >= 2 else { return nil }

        let maxCandidateCount = min(10, tokens.count)
        for wordCount in stride(from: maxCandidateCount, through: 2, by: -1) {
            let candidateTokens = Array(tokens.suffix(wordCount))
            let candidateWords = Array(words.suffix(wordCount))
            guard let command = leadingMarkdownCommand(in: candidateWords),
                  candidateWords.count > command.wordCount,
                  shouldUseSpokenMarkdownCommandTail(
                    command,
                    in: text,
                    commandStart: candidateTokens[0].range.lowerBound
                  ) else {
                continue
            }

            let argumentWords = Array(candidateWords.dropFirst(command.wordCount))
            guard isMarkdownArgumentWords(
                argumentWords,
                maxWordCount: command.maxArgumentWordCount,
                kind: command.kind
            ) else {
                continue
            }

            return SpokenMarkdownTail(
                argumentWordCount: argumentWords.count,
                maxCorrectionWordCount: command.maxArgumentWordCount,
                kind: command.kind
            )
        }

        return nil
    }

    private static func leadingMarkdownArgumentWordCount(
        in words: [String],
        maxWordCount: Int,
        kind: SpokenMarkdownCommandKind
    ) -> Int? {
        let maxArgumentWordCount = min(maxWordCount, words.count)
        for wordCount in stride(from: maxArgumentWordCount, through: 1, by: -1) {
            let candidate = Array(words.prefix(wordCount))
            guard isMarkdownArgumentWords(candidate, maxWordCount: maxWordCount, kind: kind) else {
                continue
            }

            return wordCount
        }

        return nil
    }

    private static func leadingMarkdownCommand(in words: [String]) -> SpokenMarkdownCommand? {
        guard let firstWord = words.first else { return nil }

        if ["heading", "header"].contains(firstWord),
           words.count >= 2,
           ["one", "two", "three", "1", "2", "3"].contains(words[1]) {
            return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 8, kind: .line)
        }

        if ["todo", "checkbox"].contains(firstWord) {
            return SpokenMarkdownCommand(wordCount: 1, maxArgumentWordCount: 8, kind: .line)
        }

        if words.count >= 2,
           firstWord == "to",
           words[1] == "do" {
            return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 8, kind: .line)
        }

        if words.count >= 2,
           firstWord == "check",
           words[1] == "box" {
            return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 8, kind: .line)
        }

        if firstWord == "unchecked" {
            if words.count >= 3,
               words[1] == "check",
               words[2] == "box" {
                return SpokenMarkdownCommand(wordCount: 3, maxArgumentWordCount: 8, kind: .line)
            }

            if words.count >= 2,
               ["task", "checkbox"].contains(words[1]) {
                return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 8, kind: .line)
            }
        }

        if ["checked", "done", "completed"].contains(firstWord) {
            if words.count >= 3,
               words[1] == "check",
               words[2] == "box" {
                return SpokenMarkdownCommand(wordCount: 3, maxArgumentWordCount: 8, kind: .line)
            }

            if words.count >= 2,
               ["task", "checkbox"].contains(words[1]) {
                return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 8, kind: .line)
            }
        }

        if words.count >= 2,
           firstWord == "inline",
           words[1] == "code" {
            return SpokenMarkdownCommand(wordCount: 2, maxArgumentWordCount: 4, kind: .inlineCode)
        }

        return nil
    }

    private static func shouldUseSpokenMarkdownCommandTail(
        _ command: SpokenMarkdownCommand,
        in text: String,
        commandStart: String.Index
    ) -> Bool {
        switch command.kind {
        case .line:
            return isAtMarkdownLineCommandStart(in: text, commandStart: commandStart)
        case .inlineCode:
            return hasInlineCodeCommandContext(in: text, commandStart: commandStart)
        }
    }

    private static func isAtMarkdownLineCommandStart(in text: String, commandStart: String.Index) -> Bool {
        let prefix = String(text[..<commandStart])
        guard let lastNewline = prefix.lastIndex(where: { $0.isNewline }) else {
            return prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let afterNewline = prefix[prefix.index(after: lastNewline)...]
        return afterNewline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasInlineCodeCommandContext(in text: String, commandStart: String.Index) -> Bool {
        let beforeCommand = String(text[..<commandStart])
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

        return allowedPreviousWordsForSpokenCodeCase.contains(previousWord) || previousWord == "write"
    }

    private static func isMarkdownArgumentWords(
        _ words: [String],
        maxWordCount: Int,
        kind: SpokenMarkdownCommandKind
    ) -> Bool {
        guard let firstWord = words.first,
              !blockedFirstWordsForSpokenCodeCase.contains(firstWord),
              words.count <= maxWordCount else {
            return false
        }

        switch kind {
        case .line:
            return true
        case .inlineCode:
            return !words.contains(where: isBlockedInlineCodeWord)
        }
    }

    private static func boundedSpokenMarkdownLinkCorrection(
        beforeMarker: String,
        in text: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceTail = trailingSpokenMarkdownLinkTail(in: beforeMarker) else {
            return nil
        }

        let correctionTokens = wordTokens(in: text)
        let correctionWords = correctionTokens.map { $0.text }
        if let targetWordCount = leadingMarkdownLinkTargetCorrectionWordCount(in: correctionWords) {
            let targetRange = correctionTokens[0].range.lowerBound..<correctionTokens[targetWordCount - 1].range.upperBound
            let targetTextStart = correctionWords.first == "to" && targetWordCount > 1
                ? correctionTokens[1].range.lowerBound
                : targetRange.lowerBound
            let targetText = String(text[targetTextStart..<targetRange.upperBound])
            return (
                targetRange,
                targetWordCount,
                sourceTail.wordCount,
                "\(sourceTail.commandText) \(sourceTail.labelText) to \(targetText)"
            )
        }

        guard let labelWordCount = leadingMarkdownLinkLabelWordCount(in: correctionWords) else {
            return nil
        }

        let labelRange = correctionTokens[0].range.lowerBound..<correctionTokens[labelWordCount - 1].range.upperBound
        let labelText = String(text[labelRange])
        return (
            labelRange,
            labelWordCount,
            sourceTail.wordCount,
            "\(sourceTail.commandText) \(labelText) to \(sourceTail.targetText)"
        )
    }

    private static func trailingSpokenMarkdownLinkTail(in text: String) -> SpokenMarkdownLinkTail? {
        let tokens = wordTokens(in: text)
        guard tokens.count >= 4 else { return nil }

        let maxCandidateCount = min(12, tokens.count)
        for wordCount in stride(from: maxCandidateCount, through: 4, by: -1) {
            let candidateTokens = Array(tokens.suffix(wordCount))
            let candidate = candidateTokens.map { $0.text }
            guard let linkIndex = leadingMarkdownLinkCommandWordCount(in: candidate),
                  let toIndex = candidate[linkIndex...].firstIndex(of: "to"),
                  toIndex > linkIndex,
                  toIndex < candidate.endIndex - 1 else {
                continue
            }

            let labelWords = Array(candidate[linkIndex..<toIndex])
            let targetWords = Array(candidate[candidate.index(after: toIndex)..<candidate.endIndex])
            guard isMarkdownLinkLabelWords(labelWords),
                  isMarkdownLinkTargetWords(targetWords) else {
                continue
            }

            let commandText = String(text[candidateTokens[0].range.lowerBound..<candidateTokens[linkIndex - 1].range.upperBound])
            let labelText = String(text[candidateTokens[linkIndex].range.lowerBound..<candidateTokens[toIndex - 1].range.upperBound])
            let targetText = String(text[candidateTokens[toIndex + 1].range.lowerBound..<candidateTokens[wordCount - 1].range.upperBound])
            return SpokenMarkdownLinkTail(
                wordCount: wordCount,
                commandText: commandText,
                labelText: labelText,
                targetText: targetText
            )
        }

        return nil
    }

    private static func leadingMarkdownLinkCommandWordCount(in words: [String]) -> Int? {
        if words.count >= 2, words[0] == "markdown", words[1] == "link" {
            return 2
        }
        guard words.first == "link" else { return nil }
        return 1
    }

    private static func leadingMarkdownLinkLabelWordCount(in words: [String]) -> Int? {
        let maxWordCount = min(6, words.count)
        for wordCount in stride(from: maxWordCount, through: 1, by: -1) {
            let candidate = Array(words.prefix(wordCount))
            guard isMarkdownLinkLabelWords(candidate) else { continue }
            return wordCount
        }

        return nil
    }

    private static func leadingMarkdownLinkTargetCorrectionWordCount(in words: [String]) -> Int? {
        if words.first == "to",
           let targetWordCount = leadingMarkdownLinkTargetWordCount(in: Array(words.dropFirst())) {
            return 1 + targetWordCount
        }

        return leadingMarkdownLinkTargetWordCount(in: words)
    }

    private static func leadingMarkdownLinkTargetWordCount(in words: [String]) -> Int? {
        let maxWordCount = min(8, words.count)
        for wordCount in stride(from: maxWordCount, through: 1, by: -1) {
            let candidate = Array(words.prefix(wordCount))
            guard isMarkdownLinkTargetWords(candidate) else { continue }
            return wordCount
        }

        return nil
    }

    private static func isMarkdownLinkLabelWords(_ words: [String]) -> Bool {
        guard let firstWord = words.first,
              !blockedFirstWordsForSpokenCodeCase.contains(firstWord),
              words.count <= 6 else {
            return false
        }

        return !words.contains("to")
    }

    private static func isMarkdownLinkTargetWords(_ words: [String]) -> Bool {
        guard !words.isEmpty,
              words.count <= 8 else {
            return false
        }

        let target = words.joined(separator: " ")
        if isMarkdownLinkTarget(target) {
            return true
        }

        return spokenURLTarget(target, allowLocalhost: true) != nil
    }

    private static func wordTokens(in text: String, range searchRange: Range<String.Index>? = nil) -> [WordToken] {
        let searchRange = searchRange ?? text.startIndex..<text.endIndex
        var tokens: [WordToken] = []
        var index = searchRange.lowerBound

        while index < searchRange.upperBound {
            while index < searchRange.upperBound, !isWordCharacter(text[index]) {
                index = text.index(after: index)
            }

            guard index < searchRange.upperBound else { break }

            let wordStart = index
            while index < searchRange.upperBound, isWordCharacter(text[index]) {
                index = text.index(after: index)
            }

            tokens.append(
                WordToken(
                    text: String(text[wordStart..<index]).lowercased(),
                    range: wordStart..<index
                )
            )
        }

        return tokens
    }

    private static func boundedSpokenDateCorrection(
        beforeMarker: String,
        correctionTokens: [WordToken],
        in text: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceDate = trailingSpokenDate(in: beforeMarker) else {
            return nil
        }

        let correctionWords = correctionTokens.map { $0.text }
        if let correctionDate = leadingSpokenDate(in: correctionWords) {
            let dateRange = correctionTokens[0].range.lowerBound..<correctionTokens[correctionDate.wordCount - 1].range.upperBound
            return (dateRange, correctionDate.wordCount, sourceDate.wordCount, nil)
        }

        guard let correctionDayWordCount = leadingSpokenDayWordCount(in: correctionWords) else {
            return nil
        }

        let dayRange = correctionTokens[0].range.lowerBound..<correctionTokens[correctionDayWordCount - 1].range.upperBound
        if let sourceYear = sourceDate.yearWord {
            let dayText = String(text[dayRange])
            return (
                dayRange,
                correctionDayWordCount,
                sourceDate.dayWordCount + 1,
                "\(dayText) \(sourceYear)"
            )
        }

        return (dayRange, correctionDayWordCount, sourceDate.dayWordCount, nil)
    }

    private static func trailingSpokenDate(in text: String) -> SpokenDateCandidate? {
        let tokens = wordTokens(in: text)
        let words = tokens.map { $0.text }
        guard tokens.count >= 2 else { return nil }

        let maxCandidateCount = min(4, words.count)
        for wordCount in stride(from: maxCandidateCount, through: 2, by: -1) {
            let candidateTokens = Array(tokens.suffix(wordCount))
            let candidate = candidateTokens.map { $0.text }
            if let date = leadingSpokenDate(in: candidate),
               date.wordCount == wordCount,
               let monthToken = candidateTokens.first,
               shouldFormatSpokenMonth(
                String(text[monthToken.range]),
                precedingText: String(text[..<monthToken.range.lowerBound])
               ) {
                return date
            }
        }

        return nil
    }

    private static func leadingSpokenDate(in words: [String]) -> SpokenDateCandidate? {
        guard words.count >= 2,
              monthWords.contains(words[0]) else {
            return nil
        }

        for dayWordCount in [2, 1] where words.count >= 1 + dayWordCount {
            let dayWords = Array(words[1..<(1 + dayWordCount)])
            guard spokenDayValue(dayWords) != nil else { continue }

            let yearIndex = 1 + dayWordCount
            let yearWord = words.indices.contains(yearIndex) && isFourDigitYearWord(words[yearIndex]) ? words[yearIndex] : nil
            return SpokenDateCandidate(
                wordCount: yearIndex + (yearWord == nil ? 0 : 1),
                dayWordCount: dayWordCount,
                yearWord: yearWord
            )
        }

        return nil
    }

    private static func leadingSpokenDayWordCount(in words: [String]) -> Int? {
        for wordCount in [2, 1] where words.count >= wordCount {
            let dayWords = Array(words[0..<wordCount])
            guard spokenDayValue(dayWords) != nil else { continue }
            return wordCount
        }

        return nil
    }

    private static func spokenDayValue(_ words: [String]) -> Int? {
        guard !words.isEmpty, words.count <= 2 else { return nil }

        if words.count == 1,
           let numericDay = numericDayValue(words[0]) {
            return numericDay
        }

        let dayText = words.joined(separator: " ")
        return ordinalDayValues[dayText]
    }

    private static func numericDayValue(_ word: String) -> Int? {
        let normalizedWord = word
            .lowercased()
            .replacingOccurrences(of: #"(?:st|nd|rd|th)$"#, with: "", options: .regularExpression)
        guard let value = Int(normalizedWord),
              (1...31).contains(value) else {
            return nil
        }

        return value
    }

    private static func isFourDigitYearWord(_ word: String) -> Bool {
        guard word.count == 4,
              let value = Int(word) else {
            return false
        }

        return (1000...9999).contains(value)
    }

    private static func boundedSpokenAmountCorrection(
        beforeMarker: String,
        correctionTokens: [WordToken],
        in text: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceAmount = trailingSpokenAmount(in: beforeMarker),
              !correctionTokens.isEmpty else {
            return nil
        }

        let amountTokens = wordTokens(in: text)
        let amountWords = amountTokens.map { $0.text }
        if let correctionAmount = leadingSpokenAmount(in: amountWords) {
            let amountRange = amountTokens[0].range.lowerBound..<amountTokens[correctionAmount.wordCount - 1].range.upperBound
            return (amountRange, correctionAmount.wordCount, sourceAmount.wordCount, nil)
        }

        guard let valueWordCount = leadingAmountValueWordCount(in: amountWords) else {
            return nil
        }

        let valueRange = amountTokens[0].range.lowerBound..<amountTokens[valueWordCount - 1].range.upperBound
        let valueText = String(text[valueRange])
        let replacementText: String
        switch sourceAmount.unitPlacement {
        case .prefix:
            replacementText = "\(sourceAmount.unitText) \(valueText)"
        case .suffix:
            replacementText = "\(valueText) \(sourceAmount.unitText)"
        }

        return (valueRange, valueWordCount, sourceAmount.wordCount, replacementText)
    }

    private static func trailingSpokenAmount(in text: String) -> SpokenAmountCandidate? {
        let words = wordTokens(in: text).map { $0.text }
        guard words.count >= 2 else { return nil }

        let maxCandidateCount = min(8, words.count)
        for wordCount in stride(from: maxCandidateCount, through: 2, by: -1) {
            let candidate = Array(words.suffix(wordCount))
            if let amount = leadingSpokenAmount(in: candidate),
               amount.wordCount == wordCount {
                return amount
            }
        }

        return nil
    }

    private static func leadingSpokenAmount(in words: [String]) -> SpokenAmountCandidate? {
        if words.count >= 3,
           leadingCurrencySignWords.contains(words[0]),
           words[1] == "sign",
           let valueWordCount = leadingAmountValueWordCount(in: Array(words.dropFirst(2))) {
            return SpokenAmountCandidate(
                wordCount: 2 + valueWordCount,
                unitText: "\(words[0]) sign",
                unitPlacement: .prefix
            )
        }

        guard let valueWordCount = leadingAmountValueWordCount(in: words),
              words.count > valueWordCount else {
            return nil
        }

        if trailingAmountUnitWords.contains(words[valueWordCount]) {
            return SpokenAmountCandidate(
                wordCount: valueWordCount + 1,
                unitText: words[valueWordCount],
                unitPlacement: .suffix
            )
        }

        if words.count > valueWordCount + 1,
           words[valueWordCount] == "per",
           words[valueWordCount + 1] == "cent" {
            return SpokenAmountCandidate(
                wordCount: valueWordCount + 2,
                unitText: "per cent",
                unitPlacement: .suffix
            )
        }

        return nil
    }

    private static func leadingAmountValueWordCount(in words: [String]) -> Int? {
        if let decimalWordCount = leadingDecimalAmountValueWordCount(in: words) {
            return decimalWordCount
        }

        for wordCount in [2, 1] where words.count >= wordCount {
            let valueWords = Array(words[0..<wordCount])
            guard spokenNumberValue(valueWords.joined(separator: " ")) != nil else {
                continue
            }

            return wordCount
        }

        return nil
    }

    private static func leadingDecimalAmountValueWordCount(in words: [String]) -> Int? {
        for integerWordCount in [2, 1] where words.count > integerWordCount + 1 {
            let integerWords = Array(words[0..<integerWordCount])
            guard spokenNumberValue(integerWords.joined(separator: " ")) != nil,
                  words[integerWordCount] == "point" else {
                continue
            }

            var fractionalWordCount = 0
            var index = integerWordCount + 1
            while index < words.count,
                  fractionalWordCount < 6,
                  spokenDecimalDigits(words[index]) != nil {
                fractionalWordCount += 1
                index += 1
            }

            guard fractionalWordCount > 0 else { continue }
            return integerWordCount + 1 + fractionalWordCount
        }

        return nil
    }

    private static func boundedSpokenCompactTokenCorrection(
        beforeMarker: String,
        in text: String
    ) -> (
        range: Range<String.Index>,
        wordCount: Int,
        removalWordCount: Int,
        replacementText: String?
    )? {
        guard let sourceWordCount = trailingSpokenCompactTokenWordCount(in: beforeMarker) else {
            return nil
        }

        let compactTokens = wordTokens(in: text)
        let compactWords = compactTokens.map { $0.text }
        guard let correctionWordCount = leadingSpokenCompactTokenWordCount(in: compactWords) else {
            if let connectorCorrection = leadingSpokenCompactConnectorCorrection(in: compactWords),
               let leadingConnector = spokenCompactConnector(in: compactWords, startingAt: 0),
               let sourceSuffix = trailingSpokenCompactConnectorSuffix(
                in: beforeMarker,
                matching: connectorCorrection.output
               ),
               shouldUseSpokenCompactConnector(
                connectorCorrection.output,
                previousWord: sourceSuffix.previousWord,
                nextWord: compactWords[leadingConnector.wordCount]
               ) {
                let compactRange = compactTokens[0].range.lowerBound..<compactTokens[connectorCorrection.wordCount - 1].range.upperBound
                return (compactRange, connectorCorrection.wordCount, sourceSuffix.wordCount, nil)
            }

            return nil
        }

        let compactRange = compactTokens[0].range.lowerBound..<compactTokens[correctionWordCount - 1].range.upperBound
        return (compactRange, correctionWordCount, sourceWordCount, nil)
    }

    private static func trailingSpokenCompactTokenWordCount(in text: String) -> Int? {
        let words = wordTokens(in: text).map { $0.text }
        guard words.count >= 3 else { return nil }

        let maxCandidateCount = min(16, words.count)
        for wordCount in stride(from: maxCandidateCount, through: 3, by: -1) {
            let candidate = Array(words.suffix(wordCount))
            if leadingSpokenCompactTokenWordCount(in: candidate) == wordCount {
                return wordCount
            }
        }

        return nil
    }

    private static func leadingSpokenCompactTokenWordCount(in words: [String]) -> Int? {
        guard isCompactTokenSegment(words.first) else {
            return nil
        }

        var index = 1
        var connectorCount = 0
        while index < words.count {
            guard let connector = spokenCompactConnector(in: words, startingAt: index) else {
                break
            }

            let nextSegmentIndex = index + connector.wordCount
            guard nextSegmentIndex < words.count,
                  isCompactTokenSegment(words[nextSegmentIndex]),
                  shouldUseSpokenCompactConnector(
                    connector.output,
                    previousWord: words[index - 1],
                    nextWord: words[nextSegmentIndex]
                  ) else {
                break
            }

            connectorCount += 1
            index = nextSegmentIndex + 1
        }

        guard connectorCount > 0 else { return nil }
        return index
    }

    private static func leadingSpokenCompactConnectorCorrection(in words: [String]) -> SpokenCompactConnector? {
        guard let connector = spokenCompactConnector(in: words, startingAt: 0) else {
            return nil
        }

        let nextSegmentIndex = connector.wordCount
        guard nextSegmentIndex < words.count,
              isCompactTokenSegment(words[nextSegmentIndex]) else {
            return nil
        }

        var index = nextSegmentIndex + 1
        while index < words.count {
            guard let nextConnector = spokenCompactConnector(in: words, startingAt: index) else {
                break
            }

            let nextIndex = index + nextConnector.wordCount
            guard nextIndex < words.count,
                  isCompactTokenSegment(words[nextIndex]),
                  shouldUseSpokenCompactConnector(
                    nextConnector.output,
                    previousWord: words[index - 1],
                    nextWord: words[nextIndex]
                  ) else {
                break
            }

            index = nextIndex + 1
        }

        return SpokenCompactConnector(wordCount: index, output: connector.output)
    }

    private static func trailingSpokenCompactConnectorSuffix(
        in text: String,
        matching connectorOutput: String
    ) -> SpokenCompactConnectorSuffix? {
        let words = wordTokens(in: text).map { $0.text }
        guard let tokenWordCount = trailingSpokenCompactTokenWordCount(in: text) else {
            return nil
        }

        let compactWords = Array(words.suffix(tokenWordCount))
        var index = 1
        var suffix: SpokenCompactConnectorSuffix?
        while index < compactWords.count {
            guard let connector = spokenCompactConnector(in: compactWords, startingAt: index) else {
                break
            }

            let nextSegmentIndex = index + connector.wordCount
            guard nextSegmentIndex < compactWords.count,
                  isCompactTokenSegment(compactWords[nextSegmentIndex]),
                  shouldUseSpokenCompactConnector(
                    connector.output,
                    previousWord: compactWords[index - 1],
                    nextWord: compactWords[nextSegmentIndex]
                  ) else {
                break
            }

            if connector.output == connectorOutput {
                suffix = SpokenCompactConnectorSuffix(
                    wordCount: compactWords.count - index,
                    previousWord: compactWords[index - 1]
                )
            }

            index = nextSegmentIndex + 1
        }

        return suffix
    }

    private static func spokenCompactConnector(
        in words: [String],
        startingAt index: Int
    ) -> SpokenCompactConnector? {
        guard index < words.count else { return nil }

        switch words[index] {
        case "dot":
            return SpokenCompactConnector(wordCount: 1, output: ".")
        case "slash":
            return SpokenCompactConnector(wordCount: 1, output: "/")
        case "backslash":
            return SpokenCompactConnector(wordCount: 1, output: "\\")
        case "underscore":
            return SpokenCompactConnector(wordCount: 1, output: "_")
        case "dash", "hyphen":
            return SpokenCompactConnector(wordCount: 1, output: "-")
        case "forward" where index + 1 < words.count && words[index + 1] == "slash":
            return SpokenCompactConnector(wordCount: 2, output: "/")
        case "back" where index + 1 < words.count && words[index + 1] == "slash":
            return SpokenCompactConnector(wordCount: 2, output: "\\")
        case "at" where index + 1 < words.count && words[index + 1] == "sign":
            return SpokenCompactConnector(wordCount: 2, output: "@")
        default:
            return nil
        }
    }

    private static func shouldUseSpokenCompactConnector(
        _ connector: String,
        previousWord: String,
        nextWord: String
    ) -> Bool {
        switch connector {
        case ".":
            return !["a", "an", "the"].contains(previousWord) &&
                !["matrix", "notation", "plot", "product"].contains(nextWord)
        case "@":
            return !["a", "an", "the"].contains(previousWord) && nextWord != "symbol"
        case "_":
            return !["a", "an", "the"].contains(previousWord) &&
                !["command", "commands", "symbol"].contains(nextWord)
        case "/":
            return !["command", "commands"].contains(nextWord)
        case "-":
            return previousWord != "a" && nextWord != "of"
        default:
            return true
        }
    }

    private static func isCompactTokenSegment(_ word: String?) -> Bool {
        guard let word,
              !compactConnectorWords.contains(word) else {
            return false
        }

        return isURLWordToken(word)
    }

    private static func trailingSpokenTimeWordCount(in text: String) -> Int? {
        let words = wordTokens(in: text).map { $0.text }
        guard words.count >= 2 else { return nil }

        let maxCandidateCount = min(5, words.count)
        for wordCount in stride(from: maxCandidateCount, through: 2, by: -1) {
            let candidate = Array(words.suffix(wordCount))
            if leadingSpokenTimeWordCount(in: candidate) == wordCount {
                return wordCount
            }
        }

        return nil
    }

    private static func leadingSpokenTimeWordCount(in words: [String]) -> Int? {
        guard !words.isEmpty,
              spokenHourValue(words[0]) != nil else {
            return nil
        }

        if words.count >= 3,
           isOClockPhrase(Array(words[1...2])) {
            return 3
        }

        if let meridiemWordCount = meridiemWordCount(in: words, startingAt: 1) {
            return 1 + meridiemWordCount
        }

        for minuteWordCount in [2, 1] where words.count >= 1 + minuteWordCount {
            let minuteWords = Array(words[1..<(1 + minuteWordCount)])
            guard spokenMinuteValue(minuteWords) != nil else { continue }

            let nextIndex = 1 + minuteWordCount
            if let meridiemWordCount = meridiemWordCount(in: words, startingAt: nextIndex) {
                return nextIndex + meridiemWordCount
            }

            return nextIndex
        }

        return nil
    }

    private static func isOClockPhrase(_ words: [String]) -> Bool {
        guard words.count == 2 else { return false }
        return ["o", "oh"].contains(words[0]) && words[1] == "clock"
    }

    private static func meridiemWordCount(in words: [String], startingAt startIndex: Int) -> Int? {
        guard startIndex < words.count else { return nil }

        if ["am", "pm"].contains(words[startIndex]) {
            return 1
        }

        guard startIndex + 1 < words.count,
              ["a", "p"].contains(words[startIndex]),
              words[startIndex + 1] == "m" else {
            return nil
        }

        return 2
    }

    private static func spokenHourValue(_ word: String) -> Int? {
        guard let value = spokenNumberValue(word),
              (1...12).contains(value) else {
            return nil
        }

        return value
    }

    private static func spokenMinuteValue(_ words: [String]) -> Int? {
        guard !words.isEmpty, words.count <= 2 else { return nil }

        if words.count == 2,
           ["o", "oh", "zero"].contains(words[0]),
           let value = spokenNumberValue(words[1]),
           (0...9).contains(value) {
            return value
        }

        let minuteText = words.joined(separator: " ")
        guard let value = spokenNumberValue(minuteText),
              (0...59).contains(value) else {
            return nil
        }

        if words.count == 1,
           value < 10,
           words[0].count != 2 {
            return nil
        }

        return value
    }

    private static func shouldApplyBacktrackingMarker(
        _ markerText: String,
        beforeMarker: String,
        correctionText: String
    ) -> Bool {
        if isMakeOrCallBacktrackingMarker(markerText),
           wordCount(in: beforeMarker) == 1,
           let previousWord = previousWord(in: beforeMarker),
           blockedSingleWordPrefixesForMakeCallCorrection.contains(previousWord) {
            return false
        }

        if isPlainIMeanBacktrackingMarker(markerText),
           blockedPrefixesForPlainIMeanCorrection.contains(normalizedRepeatedClause(beforeMarker)) {
            return false
        }

        if isPlainIMeanBacktrackingMarker(markerText),
           previousWord(in: beforeMarker) == "what" {
            return false
        }

        if isOrAlternativeBacktrackingMarker(markerText),
           wordCount(in: correctionText) != 1 {
            return false
        }

        if isBareSorryBacktrackingMarker(markerText),
           !shouldApplyBareSorryBacktrackingMarker(beforeMarker: beforeMarker, correctionText: correctionText) {
            return false
        }

        if isEraseBacktrackingMarker(markerText) {
            guard wordCount(in: beforeMarker) >= 2 else {
                return false
            }

            if let previousWord = previousWord(in: beforeMarker),
               blockedPreviousWordsForEraseThat.contains(previousWord) {
                return false
            }

            if let firstCorrectionWord = firstWord(in: correctionText),
               blockedFirstCorrectionWordsForReplaceThat.contains(firstCorrectionWord) {
                return false
            }

            return true
        }

        guard isReplaceOrChangeBacktrackingMarker(markerText) ||
                isGuardedNaturalBacktrackingMarker(markerText) ||
                isBareSorryBacktrackingMarker(markerText) ||
                isOrAlternativeBacktrackingMarker(markerText) else {
            return true
        }

        guard wordCount(in: beforeMarker) >= 2 else {
            return false
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

    private static func isReplaceOrChangeBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "replace that with",
            "replace it with",
            "change that to",
            "change it to"
        ].contains(normalizedMarker)
    }

    private static func isMakeOrCallBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "make that",
            "make it",
            "call it"
        ].contains(normalizedMarker)
    }

    private static func isGuardedNaturalBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "actually wait no",
            "actually wait never mind",
            "actually wait nevermind",
            "actually never mind",
            "actually nevermind",
            "no i mean",
            "no i meant",
            "no actually",
            "what i mean is",
            "i mean to say",
            "i meant to say",
            "on second thought",
            "let me rephrase",
            "backtrack",
            "back track",
            "just to clarify",
            "to clarify",
            "just to be clear",
            "to be clear",
            "for clarity",
            "hold on",
            "hang on",
            "scratch that",
            "scratch that out",
            "scratch this",
            "scratch this out",
            "cross that out",
            "cross this out",
            "strike that",
            "strike that out",
            "strike this",
            "strike this out",
            "delete that",
            "delete that out",
            "delete this",
            "delete this out",
            "remove that",
            "remove that out",
            "remove this",
            "remove this out",
            "erase that",
            "erase that out",
            "erase this",
            "erase this out",
            "undo that",
            "undo that out",
            "undo this",
            "undo this out",
            "cancel that",
            "cancel that out",
            "cancel this",
            "cancel this out",
            "disregard that",
            "disregard that out",
            "disregard this",
            "disregard this out",
            "ignore that",
            "ignore that out",
            "ignore this",
            "ignore this out",
            "forget that",
            "forget that out",
            "forget this",
            "forget this out",
            "cut that",
            "cut that out",
            "cut this",
            "cut this out",
            "drop that",
            "drop that out",
            "drop this",
            "drop this out",
            "wait actually",
            "wait i mean",
            "wait i meant",
            "wait",
            "wait never mind",
            "wait nevermind",
            "never mind",
            "nevermind"
        ].contains(normalizedMarker)
    }

    private static func isEraseBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "scratch that",
            "scratch that out",
            "scratch this",
            "scratch this out",
            "cross that out",
            "cross this out",
            "strike that",
            "strike that out",
            "strike this",
            "strike this out",
            "delete that",
            "delete that out",
            "delete this",
            "delete this out",
            "remove that",
            "remove that out",
            "remove this",
            "remove this out",
            "erase that",
            "erase that out",
            "erase this",
            "erase this out",
            "undo that",
            "undo that out",
            "undo this",
            "undo this out",
            "cancel that",
            "cancel that out",
            "cancel this",
            "cancel this out",
            "disregard that",
            "disregard that out",
            "disregard this",
            "disregard this out",
            "ignore that",
            "ignore that out",
            "ignore this",
            "ignore this out",
            "forget that",
            "forget that out",
            "forget this",
            "forget this out",
            "cut that",
            "cut that out",
            "cut this",
            "cut this out",
            "drop that",
            "drop that out",
            "drop this",
            "drop this out"
        ].contains(normalizedMarker)
    }

    private static func isOrAlternativeBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "or actually",
            "or wait no"
        ].contains(normalizedMarker)
    }

    private static func isBareSorryBacktrackingMarker(_ markerText: String) -> Bool {
        normalizedBacktrackingMarker(markerText) == "sorry"
    }

    private static func shouldApplyBareSorryBacktrackingMarker(beforeMarker: String, correctionText: String) -> Bool {
        if let previousWord = previousWord(in: beforeMarker),
           blockedPreviousWordsForBareSorryCorrection.contains(previousWord) {
            return false
        }

        if let firstCorrectionWord = firstWord(in: correctionText),
           blockedFirstCorrectionWordsForBareSorryCorrection.contains(firstCorrectionWord) {
            return false
        }

        return true
    }

    private static func isSingleWordReplacementBacktrackingMarker(_ markerText: String) -> Bool {
        let normalizedMarker = normalizedBacktrackingMarker(markerText)
        return [
            "actually no",
            "actually wait no",
            "actually wait never mind",
            "actually wait nevermind",
            "actually never mind",
            "actually nevermind",
            "never mind",
            "nevermind",
            "no actually",
            "no wait",
            "what i mean is",
            "i mean to say",
            "i meant to say",
            "on second thought",
            "let me rephrase",
            "backtrack",
            "back track",
            "just to clarify",
            "to clarify",
            "just to be clear",
            "to be clear",
            "for clarity",
            "hold on",
            "hang on",
            "wait",
            "wait never mind",
            "wait nevermind",
            "wait no"
        ].contains(normalizedMarker)
    }

    private static func isPlainIMeanBacktrackingMarker(_ markerText: String) -> Bool {
        normalizedBacktrackingMarker(markerText) == "i mean"
    }

    private static func normalizedBacktrackingMarker(_ markerText: String) -> String {
        normalizeWhitespace(markerText)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:… "))
            .replacingOccurrences(of: #"\.+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[,;:]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private static func applyDeletePreviousWordCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: deletePreviousWordCommandPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            guard let match = regex.firstMatch(in: correctedText, range: fullRange),
                  let markerRange = Range(match.range, in: correctedText),
                  let rewrittenText = rewriteDeletePreviousWordCommand(in: correctedText, match: match, markerRange: markerRange),
                  rewrittenText != correctedText else {
                break
            }

            correctedText = rewrittenText
            rewriteCount += 1
        }

        return correctedText
    }

    private static func rewriteDeletePreviousWordCommand(
        in text: String,
        match: NSTextCheckingResult,
        markerRange: Range<String.Index>
    ) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])
        let deletedWordCount = deletePreviousWordCount(in: text, match: match)

        guard shouldApplyDeleteCommand(beforeMarker: beforeMarker, afterMarker: afterMarker),
              let prefix = removeTrailingWords(deletedWordCount, from: beforeMarker) else {
            return nil
        }

        return normalizeBacktrackingWhitespace(join(prefix, "", afterMarker))
    }

    private static func deletePreviousWordCount(in text: String, match: NSTextCheckingResult) -> Int {
        guard let countText = optionalMatchText(in: text, match: match, rangeIndex: 1),
              let count = spokenNumberValue(countText),
              (1...5).contains(count) else {
            return 1
        }

        return count
    }

    private static func applyDeletePreviousLineCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: deletePreviousLineCommandPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            guard let match = regex.firstMatch(in: correctedText, range: fullRange),
                  let markerRange = Range(match.range, in: correctedText),
                  let rewrittenText = rewriteDeletePreviousLineCommand(in: correctedText, markerRange: markerRange),
                  rewrittenText != correctedText else {
                break
            }

            correctedText = rewrittenText
            rewriteCount += 1
        }

        return correctedText
    }

    private static func rewriteDeletePreviousLineCommand(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard shouldApplyDeleteCommand(beforeMarker: beforeMarker, afterMarker: afterMarker),
              let prefix = removeTrailingLine(from: beforeMarker) else {
            return nil
        }

        return joinLineDeletion(prefix: prefix, suffix: afterMarker)
    }

    private static func applyDeletePreviousParagraphCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: deletePreviousParagraphCommandPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            guard let match = regex.firstMatch(in: correctedText, range: fullRange),
                  let markerRange = Range(match.range, in: correctedText),
                  let rewrittenText = rewriteDeletePreviousParagraphCommand(in: correctedText, markerRange: markerRange),
                  rewrittenText != correctedText else {
                break
            }

            correctedText = rewrittenText
            rewriteCount += 1
        }

        return correctedText
    }

    private static func rewriteDeletePreviousParagraphCommand(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard shouldApplyDeleteCommand(beforeMarker: beforeMarker, afterMarker: afterMarker),
              let prefix = removeTrailingParagraph(from: beforeMarker) else {
            return nil
        }

        return joinLineDeletion(prefix: prefix, suffix: afterMarker)
    }

    private static func applyDeletePreviousSentenceCommands(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: deletePreviousSentenceCommandPattern) else {
            return text
        }

        var correctedText = text
        var rewriteCount = 0

        while rewriteCount < 8 {
            let fullRange = NSRange(correctedText.startIndex..., in: correctedText)
            guard let match = regex.firstMatch(in: correctedText, range: fullRange),
                  let markerRange = Range(match.range, in: correctedText),
                  let rewrittenText = rewriteDeletePreviousSentenceCommand(in: correctedText, markerRange: markerRange),
                  rewrittenText != correctedText else {
                break
            }

            correctedText = rewrittenText
            rewriteCount += 1
        }

        return correctedText
    }

    private static func rewriteDeletePreviousSentenceCommand(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard shouldApplyDeleteCommand(beforeMarker: beforeMarker, afterMarker: afterMarker),
              let prefix = removeTrailingSentence(from: beforeMarker) else {
            return nil
        }

        return normalizeBacktrackingWhitespace(join(prefix, "", afterMarker))
    }

    private static func shouldApplyDeleteCommand(beforeMarker: String, afterMarker: String) -> Bool {
        guard wordCount(in: beforeMarker) >= 1,
              let previousWord = previousWordBeforeSpokenPunctuationCommand(in: beforeMarker),
              !blockedPreviousWordsForDeleteCommand.contains(previousWord) else {
            return false
        }

        if let nextWord = nextWord(in: afterMarker),
           blockedNextWordsForDeleteCommand.contains(nextWord) {
            return false
        }

        return true
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

    private static func removeTrailingLine(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmedText) > 0 else { return nil }

        guard let lastNewlineIndex = trimmedText.lastIndex(where: { $0.isNewline }) else {
            return ""
        }

        let lineStart = trimmedText.index(after: lastNewlineIndex)
        let removedLine = String(trimmedText[lineStart...])
        guard wordCount(in: removedLine) > 0 else { return nil }

        return String(trimmedText[...lastNewlineIndex])
    }

    private static func removeTrailingParagraph(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmedText) > 0 else { return nil }

        guard let separatorRange = trimmedText.range(
            of: #"\n{2,}"#,
            options: [.regularExpression, .backwards]
        ) else {
            return ""
        }

        let removedParagraph = String(trimmedText[separatorRange.upperBound...])
        guard wordCount(in: removedParagraph) > 0 else { return nil }

        return String(trimmedText[..<separatorRange.upperBound])
    }

    private static func removeTrailingSentence(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(in: trimmedText) > 0 else { return nil }

        var scanIndex = trimmedText.endIndex
        while scanIndex > trimmedText.startIndex {
            let previousIndex = trimmedText.index(before: scanIndex)
            let previousCharacter = trimmedText[previousIndex]
            guard previousCharacter.isWhitespace || ".!?。！？".contains(previousCharacter) else {
                break
            }
            scanIndex = previousIndex
        }

        while scanIndex > trimmedText.startIndex {
            let previousIndex = trimmedText.index(before: scanIndex)
            let previousCharacter = trimmedText[previousIndex]
            if previousCharacter == "\n" || ".!?。！？".contains(previousCharacter) {
                return String(trimmedText[..<trimmedText.index(after: previousIndex)])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            scanIndex = previousIndex
        }

        return ""
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

    private static func joinLineDeletion(prefix: String, suffix: String) -> String {
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespaces)

        guard !normalizedPrefix.isEmpty else {
            return normalizeWhitespace(trimmedSuffix)
        }

        guard !trimmedSuffix.isEmpty else {
            return normalizeWhitespace(normalizedPrefix)
        }

        return normalizeWhitespace(normalizedPrefix + trimmedSuffix)
    }

    private static func normalizeBacktrackingWhitespace(_ text: String) -> String {
        normalizeWhitespace(text)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([([{])\s+"#, with: "$1", options: .regularExpression)
    }

    private static func unwrapSquareBracketedWholeOutput(_ text: String) -> String {
        guard let innerText = wholeSquareBracketedOutputInnerText(in: text) else {
            return text
        }

        guard !innerText.isEmpty else { return "" }

        if isNonSpeechBracketContent(innerText) {
            return ""
        }

        return innerText
    }

    private static func isWholeSquareBracketedOutput(_ text: String) -> Bool {
        wholeSquareBracketedOutputInnerText(in: text) != nil
    }

    private static func wholeSquareBracketedOutputInnerText(in text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.first == "[" else { return nil }

        var closingIndex = trimmedText.index(before: trimmedText.endIndex)
        while closingIndex > trimmedText.startIndex {
            let character = trimmedText[closingIndex]
            if character == "]" {
                break
            }

            guard character.unicodeScalars.allSatisfy({
                removableTrailingFragmentPunctuation.contains($0) ||
                    removableTrailingSentenceFragmentPunctuation.contains($0)
            }) else {
                return nil
            }
            closingIndex = trimmedText.index(before: closingIndex)
        }

        guard closingIndex > trimmedText.startIndex,
              trimmedText[closingIndex] == "]" else {
            return nil
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        return String(trimmedText[innerStart..<closingIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                if let previousPart = result.popLast() {
                    result.append(mergedRepeatedWordToken(previousPart, part))
                }
                continue
            }

            result.append(part)
            previousNormalizedWord = normalizedWord
        }

        return result.joined(separator: " ")
    }

    private static func mergedRepeatedWordToken(_ previousToken: String, _ duplicateToken: String) -> String {
        if hasTrailingSentencePunctuation(duplicateToken) {
            if hasTrailingSentencePunctuation(previousToken) {
                return previousToken
            }
            return appendingTrailingSentencePunctuation(from: duplicateToken, to: previousToken)
        }

        if hasTrailingSentencePunctuation(previousToken) {
            return previousToken
        }

        let cleanedDuplicateToken = removingTrailingRepeatSeparator(from: duplicateToken)
        if cleanedDuplicateToken != duplicateToken {
            return cleanedDuplicateToken
        }

        return removingTrailingRepeatSeparator(from: previousToken)
    }

    private static func collapseSeparatorRepeatedWords(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}])([\p{L}\p{N}][\p{L}\p{N}'’ʼ]{0,63})[ \t]*(?:[,;:…–—-]|\.\.\.)+[ \t]*\1(?=[ \t]+[\p{L}\p{N}]|[.!?,;:…]|\s*$)"#
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
                guard match.numberOfRanges >= 2,
                      let fullRange = Range(match.range(at: 0), in: collapsedText),
                      let wordRange = Range(match.range(at: 1), in: collapsedText) else {
                    continue
                }

                let word = String(collapsedText[wordRange])
                let normalizedWord = word.lowercased()
                guard (normalizedWord.count > 1 || normalizedWord == "i"),
                      word.rangeOfCharacter(from: .letters) != nil,
                      !preservedRepeatedWords.contains(normalizedWord) else {
                    continue
                }

                collapsedText.replaceSubrange(fullRange, with: word)
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return collapsedText
    }

    private static func hasTrailingSentencePunctuation(_ token: String) -> Bool {
        token.last.map { ".!?".contains($0) } == true && !token.hasSuffix("...")
    }

    private static func appendingTrailingSentencePunctuation(from duplicateToken: String, to previousToken: String) -> String {
        guard let punctuation = duplicateToken.last, ".!?".contains(punctuation) else {
            return duplicateToken
        }

        let baseToken = removingTrailingRepeatSeparator(from: previousToken)
        guard !baseToken.isEmpty else {
            return duplicateToken
        }

        return "\(baseToken)\(punctuation)"
    }

    private static func removingTrailingRepeatSeparator(from token: String) -> String {
        var cleanedToken = token

        while cleanedToken.hasSuffix("...") {
            cleanedToken.removeLast(3)
        }

        while let lastCharacter = cleanedToken.last,
              character(lastCharacter, isIn: softPhrasePunctuation) {
            cleanedToken.removeLast()
        }

        return cleanedToken.isEmpty ? token : cleanedToken
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

    private static func collapseMismatchedRepeatedShortSentences(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(^|(?<=[.!?])\s+)([^.!?\n]{3,120})([.!?])\s+\2([.!?])(?=\s|$)"#
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
                guard match.numberOfRanges >= 5,
                      let fullRange = Range(match.range, in: collapsedText),
                      let prefixRange = Range(match.range(at: 1), in: collapsedText),
                      let sentenceBodyRange = Range(match.range(at: 2), in: collapsedText),
                      let firstPunctuationRange = Range(match.range(at: 3), in: collapsedText),
                      let secondPunctuationRange = Range(match.range(at: 4), in: collapsedText) else {
                    continue
                }

                let sentenceBody = String(collapsedText[sentenceBodyRange])
                let sentenceWordCount = wordCount(in: sentenceBody)
                guard sentenceWordCount >= 2 && sentenceWordCount <= 12,
                      !preservedRepeatedClauses.contains(normalizedRepeatedClause(sentenceBody)) else {
                    continue
                }

                let firstPunctuation = String(collapsedText[firstPunctuationRange])
                let secondPunctuation = String(collapsedText[secondPunctuationRange])
                let punctuation = repeatedSentencePunctuation(firstPunctuation, secondPunctuation)
                collapsedText.replaceSubrange(
                    fullRange,
                    with: String(collapsedText[prefixRange]) + sentenceBody + punctuation
                )
                didRewrite = true
            }

            guard didRewrite else { break }
            rewriteCount += 1
        }

        return collapsedText
    }

    private static func repeatedSentencePunctuation(_ first: String, _ second: String) -> String {
        if first == "." || second == "." { return "." }
        return second
    }

    private static func collapseRepeatedShortPhrases(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(^|(?<=[.!?])\s+|\n|(?<=[ \t]))((?:[^\s,;:.!?\n]+[ \t]+){1,4}[^\s,;:.!?\n]+)[ \t]+\2(?=[ \t]+[^\s,;:.!?\n]+|[.!?]|\s*$)"#
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
            pattern: #"(?i)(^|(?<=[.!?])\s+|\n|(?<=[ \t]))([^,;:.!?\n]{5,120}?)[ \t]*[,;:][ \t]+\2(?=[.!?]|\s|$)"#
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
        if strippedText == text {
            let withoutLeadingNoise = removeLeadingFragmentPunctuation(from: removeLeadingPausePunctuation(from: text))
            let unwrappedLeadingFragment = unwrapSquareBracketedWholeOutput(withoutLeadingNoise)
            if unwrappedLeadingFragment != withoutLeadingNoise {
                strippedText = unwrappedLeadingFragment
            } else if withoutLeadingNoise != text,
                      startsWithRemovableNonASCIIBoundaryWrapper(withoutLeadingNoise) {
                strippedText = withoutLeadingNoise
            }
        }
        strippedText = unwrapNestedSquareBracketedBoundaryOutput(strippedText)
        strippedText = unwrapNoisyAngleBracketedBoundaryOutput(strippedText)
        strippedText = unwrapNoisyMarkdownBoundaryOutput(strippedText)
        guard isShortFragment(strippedText) else { return strippedText }

        if hasPreservedBalancedBoundary(strippedText) ||
            hasPreservedBalancedBoundary(removeTrailingFragmentPunctuation(from: strippedText)) {
            return normalizeWhitespace(strippedText)
        }

        let boundaryCharacters = CharacterSet(charactersIn: #"[]{}()"“”‘’'"`【】《》〈〉（）｛｝［］「」『』〔〕"#)
        strippedText = strippedText.trimmingCharacters(in: boundaryCharacters.union(.whitespacesAndNewlines))
        return normalizeWhitespace(strippedText)
    }

    private static func unwrapNestedSquareBracketedBoundaryOutput(_ text: String) -> String {
        guard let innerText = preservedBoundaryInnerText(in: text) else {
            return text
        }

        let unwrappedInnerText = unwrapSquareBracketedWholeOutput(innerText)
        guard unwrappedInnerText != innerText else {
            return text
        }

        return unwrappedInnerText
    }

    private static func unwrapNoisyAngleBracketedBoundaryOutput(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.first == "<",
              trimmedText.last == ">" else {
            return text
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        let innerText = String(trimmedText[innerStart..<innerEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !innerText.isEmpty else { return text }

        let pipeUnwrappedText = unwrapPipeWrappedFragment(innerText)
        let nestedUnwrappedText = unwrapNoisyNestedBoundaryFragment(pipeUnwrappedText)
        let candidateText = nestedUnwrappedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidateText.isEmpty else { return text }
        guard isShortFragment(candidateText) else { return text }

        let didUnwrapNestedBoundary = candidateText != innerText
        let didRemoveNoisyPunctuation = removeTrailingNoisyFragmentPunctuation(from: candidateText) != candidateText
        guard didUnwrapNestedBoundary || didRemoveNoisyPunctuation else {
            return text
        }

        return candidateText
    }

    private static func unwrapNoisyNestedBoundaryFragment(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let squareUnwrappedText = unwrapSquareBracketedWholeOutput(trimmedText)
        if squareUnwrappedText != trimmedText {
            return squareUnwrappedText
        }

        guard let nonASCIIUnwrappedText = nonASCIIBoundaryInnerText(in: trimmedText),
              isShortFragment(nonASCIIUnwrappedText),
              removeTrailingNoisyFragmentPunctuation(from: nonASCIIUnwrappedText) != nonASCIIUnwrappedText else {
            return text
        }

        return nonASCIIUnwrappedText
    }

    private static func nonASCIIBoundaryInnerText(in text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let closing = nonASCIIClosingBoundary(for: first),
              trimmedText.last == closing else {
            return nil
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        let innerText = String(trimmedText[innerStart..<innerEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return innerText.isEmpty ? nil : innerText
    }

    private static func nonASCIIClosingBoundary(for opening: Character) -> Character? {
        switch opening {
        case "【": return "】"
        case "《": return "》"
        case "〈": return "〉"
        case "（": return "）"
        case "｛": return "｝"
        case "［": return "］"
        case "「": return "」"
        case "『": return "』"
        case "〔": return "〕"
        default: return nil
        }
    }

    private static func unwrapPipeWrappedFragment(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.first == "|",
              trimmedText.last == "|",
              trimmedText.count >= 3 else {
            return text
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        return String(trimmedText[innerStart..<innerEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapNoisyMarkdownBoundaryOutput(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = trimmedText.first,
              marker == "*" || marker == "_" else {
            return text
        }

        var markerCount = 0
        var prefixEnd = trimmedText.startIndex
        while prefixEnd < trimmedText.endIndex,
              trimmedText[prefixEnd] == marker,
              markerCount < 3 {
            markerCount += 1
            prefixEnd = trimmedText.index(after: prefixEnd)
        }
        guard markerCount > 0,
              prefixEnd < trimmedText.endIndex else {
            return text
        }

        var suffixStart = trimmedText.endIndex
        for _ in 0..<markerCount {
            guard suffixStart > prefixEnd else { return text }
            suffixStart = trimmedText.index(before: suffixStart)
            guard trimmedText[suffixStart] == marker else { return text }
        }

        let innerText = String(trimmedText[prefixEnd..<suffixStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !innerText.isEmpty,
              isShortFragment(innerText),
              removeTrailingNoisyFragmentPunctuation(from: innerText) != innerText else {
            return text
        }

        return innerText
    }

    private static func startsWithRemovableNonASCIIBoundaryWrapper(_ text: String) -> Bool {
        guard let firstScalar = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else {
            return false
        }

        return removableOpeningNonASCIIBoundaryWrappers.contains(firstScalar)
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
        let innerText = trimmedText[innerStart..<innerEnd]
        guard !innerText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            return false
        }

        if first == "[" {
            guard let lastInnerScalar = innerText.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last else {
                return false
            }
            return !removableTrailingFragmentPunctuation.contains(lastInnerScalar) &&
                !removableTrailingSentenceFragmentPunctuation.contains(lastInnerScalar)
        }

        return true
    }

    private static func preservedClosingBoundary(for opening: Character) -> Character? {
        switch opening {
        case "\"": return "\""
        case "'": return "'"
        case "“": return "”"
        case "‘": return "’"
        case "(": return ")"
        case "[": return "]"
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

    private static func removeLeadingPausePunctuation(from text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = result.startIndex
        var punctuationCount = 0
        var didSeeEllipsisCharacter = false

        while index < result.endIndex {
            let character = result[index]
            guard character.unicodeScalars.allSatisfy({ removableLeadingPausePunctuation.contains($0) }) else {
                break
            }
            punctuationCount += 1
            if character == "…" {
                didSeeEllipsisCharacter = true
            }
            index = result.index(after: index)
        }

        guard punctuationCount >= 2 || didSeeEllipsisCharacter else { return result }

        let remainder = String(result[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.rangeOfCharacter(from: .alphanumerics) != nil else { return result }
        return remainder
    }

    private static func removeLeadingFragmentPunctuation(from text: String) -> String {
        var result = removeLeadingSpacedFragmentSymbols(from: text)
        while let firstScalar = result.unicodeScalars.first,
              removableLeadingFragmentPunctuation.contains(firstScalar) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func removeLeadingSpacedFragmentSymbols(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let firstCharacter = result.first,
              removableLeadingSpacedFragmentSymbols.contains(firstCharacter) {
            let symbolEndIndex = result.index(after: result.startIndex)
            guard symbolEndIndex < result.endIndex,
                  result[symbolEndIndex].isWhitespace else {
                return result
            }
            result = String(result[symbolEndIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func shouldRemoveLeadingGeneratedFragmentMarker(after precedingText: String) -> Bool {
        guard isContinuingSentence(after: precedingText) else { return false }

        let linePrefix = currentLinePrefix(in: precedingText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastCharacter = linePrefix.last else { return false }
        return lastCharacter != ":" && lastCharacter != "："
    }

    private static func removeLeadingGeneratedFragmentMarker(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hashUnwrappedText = removeLeadingHashFragmentMarker(from: trimmedText) {
            return hashUnwrappedText
        }

        if let numberedUnwrappedText = removeLeadingNumberedFragmentMarker(from: trimmedText) {
            return numberedUnwrappedText
        }

        return text
    }

    private static func removeLeadingHashFragmentMarker(from text: String) -> String? {
        var markerEnd = text.startIndex
        var markerCount = 0
        while markerEnd < text.endIndex,
              text[markerEnd] == "#",
              markerCount < 6 {
            markerCount += 1
            markerEnd = text.index(after: markerEnd)
        }

        guard markerCount > 0,
              markerEnd < text.endIndex,
              text[markerEnd].isWhitespace else {
            return nil
        }

        let candidateText = String(text[markerEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNoisyMarkedShortFragment(candidateText) else { return nil }
        return candidateText
    }

    private static func removeLeadingNumberedFragmentMarker(from text: String) -> String? {
        var markerEnd = text.startIndex
        var digitCount = 0
        while markerEnd < text.endIndex,
              text[markerEnd].isNumber,
              digitCount < 3 {
            digitCount += 1
            markerEnd = text.index(after: markerEnd)
        }

        guard digitCount > 0,
              markerEnd < text.endIndex,
              text[markerEnd] == "." || text[markerEnd] == ")" else {
            return nil
        }

        let whitespaceStart = text.index(after: markerEnd)
        guard whitespaceStart < text.endIndex,
              text[whitespaceStart].isWhitespace else {
            return nil
        }

        let candidateText = String(text[whitespaceStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNoisyMarkedShortFragment(candidateText) else { return nil }
        return candidateText
    }

    private static func isNoisyMarkedShortFragment(_ text: String) -> Bool {
        guard !text.isEmpty,
              isShortFragment(text),
              removeTrailingNoisyFragmentPunctuation(from: text) != text else {
            return false
        }
        return true
    }

    private static func removeTrailingShortFragmentPunctuation(from text: String) -> String {
        var result = removeTrailingPunctuationAfterPreservedBoundary(from: text)
        result = removeTrailingFragmentPunctuationPreservingAbbreviation(from: result)
        result = removeTrailingSpacedFragmentSymbols(from: result)
        result = removeTrailingSentenceFragmentPunctuationInsidePreservedBoundary(from: result)
        result = unwrapNoisyNestedBoundaryInsidePreservedBoundary(from: result)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingSentenceFragmentPunctuation.contains(lastScalar),
              isLikelyPunctuatedShortFragment(result) {
            result.removeLast()
        }
        return result
    }

    private static func removeTrailingNoisyFragmentPunctuation(from text: String) -> String {
        var result = removeTrailingFragmentPunctuationPreservingAbbreviation(from: text)
        result = removeTrailingSpacedFragmentSymbols(from: result)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingSentenceFragmentPunctuation.contains(lastScalar) {
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeTrailingFragmentPunctuationPreservingAbbreviation(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingFragmentPunctuation.contains(lastScalar) {
            if lastScalar == ".", isTerminalPeriodAbbreviation(result) {
                break
            }
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func removeTrailingPunctuationAfterPreservedBoundary(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmedText
        var didRemovePunctuation = false

        while let lastScalar = candidate.unicodeScalars.last,
              removableTrailingFragmentPunctuation.contains(lastScalar) ||
                removableTrailingSentenceFragmentPunctuation.contains(lastScalar) {
            candidate.removeLast()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            didRemovePunctuation = true
        }

        guard didRemovePunctuation,
              hasPreservedBalancedBoundary(candidate) else {
            return text
        }

        return candidate
    }

    private static func removeRedundantOuterPunctuationAfterPreservedBoundary(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = removeTrailingPunctuationAfterPreservedBoundary(from: trimmedText)
        guard candidate != trimmedText,
              let innerText = preservedBoundaryInnerText(in: candidate),
              let lastInnerScalar = innerText.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last,
              removableTrailingFragmentPunctuation.contains(lastInnerScalar) ||
                removableTrailingSentenceFragmentPunctuation.contains(lastInnerScalar) ||
                unwrapNoisyNestedBoundaryFragment(innerText) != innerText else {
            return text
        }

        return candidate
    }

    private static func removeTrailingContinuationPeriod(from text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.last == ".",
              !result.hasSuffix("..."),
              !isTerminalPeriodAbbreviation(result) else {
            return text
        }

        let withoutFinalPeriod = String(result.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutFinalPeriod.isEmpty,
              !hasInternalSentenceBoundary(withoutFinalPeriod) else {
            return text
        }

        return withoutFinalPeriod
    }

    private static func hasInternalSentenceBoundary(_ text: String) -> Bool {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            guard nextIndex < text.endIndex,
                  text[nextIndex].isWhitespace,
                  ".!?".contains(character) else {
                index = nextIndex
                continue
            }

            if character == "." {
                let tokenThroughPeriod = terminalToken(endingAt: index, in: text)
                if isTerminalPeriodAbbreviation(tokenThroughPeriod) {
                    index = nextIndex
                    continue
                }
            }

            return true
        }

        return false
    }

    private static func terminalToken(endingAt endIndex: String.Index, in text: String) -> String {
        var startIndex = endIndex
        while startIndex > text.startIndex {
            let previousIndex = text.index(before: startIndex)
            guard !text[previousIndex].isWhitespace else {
                break
            }
            startIndex = previousIndex
        }

        return String(text[startIndex...endIndex])
    }

    private static func removeTrailingSpacedFragmentSymbols(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastCharacter = result.last,
              removableTrailingSpacedFragmentSymbols.contains(lastCharacter) {
            var symbolRunStart = result.index(before: result.endIndex)
            while symbolRunStart > result.startIndex {
                let previousIndex = result.index(before: symbolRunStart)
                guard removableTrailingSpacedFragmentSymbols.contains(result[previousIndex]) else { break }
                symbolRunStart = previousIndex
            }

            let prefix = result[..<symbolRunStart]
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
        guard shouldRemoveNoisySentencePunctuationInsideBoundary(innerText) else {
            return text
        }

        let cleanedInnerText = removeTrailingShortFragmentPunctuation(from: innerText)
        return "\(first)\(cleanedInnerText)\(closing)"
    }

    private static func unwrapNoisyNestedBoundaryInsidePreservedBoundary(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let closing = preservedClosingBoundary(for: first),
              trimmedText.last == closing,
              let innerText = preservedBoundaryInnerText(in: trimmedText) else {
            return text
        }

        let unwrappedInnerText = unwrapNoisyNestedBoundaryFragment(innerText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard unwrappedInnerText != innerText.trimmingCharacters(in: .whitespacesAndNewlines),
              !unwrappedInnerText.isEmpty,
              isShortFragment(unwrappedInnerText) else {
            return text
        }

        let cleanedInnerText = removeTrailingNoisyFragmentPunctuation(from: unwrappedInnerText)
        return "\(first)\(cleanedInnerText)\(closing)"
    }

    private static func isShortNoisyBoundaryFinalFragment(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isShortNoisyBoundaryFinalFragmentWithoutOuterPunctuation(trimmedText) {
            return true
        }

        let withoutOuterPunctuation = removeTrailingPunctuationAfterPreservedBoundary(from: trimmedText)
        guard withoutOuterPunctuation != trimmedText else { return false }
        return isShortNoisyBoundaryFinalFragmentWithoutOuterPunctuation(withoutOuterPunctuation)
    }

    private static func isShortNoisyBoundaryFinalFragmentWithoutOuterPunctuation(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let innerText = preservedBoundaryInnerText(in: trimmedText) else {
            return false
        }

        return shouldRemoveNoisySentencePunctuationInsideBoundary(innerText)
    }

    private static func preservedBoundaryInnerText(in text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let closing = preservedClosingBoundary(for: first),
              trimmedText.last == closing else {
            return nil
        }

        let innerStart = trimmedText.index(after: trimmedText.startIndex)
        let innerEnd = trimmedText.index(before: trimmedText.endIndex)
        let innerText = String(trimmedText[innerStart..<innerEnd])
        guard !innerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return innerText
    }

    private static func shouldRemoveNoisySentencePunctuationInsideBoundary(_ text: String) -> Bool {
        if isLikelyPunctuatedShortFragment(text) {
            return true
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.last == ".",
              !trimmedText.hasSuffix("...") else {
            return false
        }

        let baseText = String(trimmedText.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseText.isEmpty,
              !baseText.contains(".") else {
            return false
        }

        let baseWordCount = wordCount(in: baseText)
        return baseWordCount >= 1 && baseWordCount <= 3
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

    private static func isTerminalPeriodAbbreviation(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.last == "." else { return false }

        if preservedTerminalPeriodAbbreviations.contains(trimmedText.lowercased()) {
            return true
        }

        guard let regex = try? NSRegularExpression(pattern: #"(?i)^(?:[a-z]\.){2,}$"#) else {
            return false
        }
        return regex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)) != nil
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

    private static func lowercaseInitialWordIfSafe(in text: String) -> String {
        guard let firstLetterRange = text.rangeOfCharacter(from: .letters) else {
            return text
        }

        let suffixFromFirstLetter = text[firstLetterRange.lowerBound...]
        guard let firstWordEnd = suffixFromFirstLetter.firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }) else {
            return lowercaseInitialWordIfSafe(in: text, firstLetterRange: firstLetterRange, firstWordEnd: text.endIndex)
        }

        return lowercaseInitialWordIfSafe(in: text, firstLetterRange: firstLetterRange, firstWordEnd: firstWordEnd)
    }

    private static func lowercaseFragmentWordsIfSafe(in text: String) -> String {
        lowercaseLikelyTitleCasedWordsIfSafe(in: lowercaseInitialWordIfSafe(in: text))
    }

    private static func shouldLowercaseLikelyTitleCasedFragmentWords(in text: String) -> Bool {
        !text.contains { ".!?。！？".contains($0) }
    }

    private static func lowercaseLikelyTitleCasedWordsIfSafe(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}'’ʼ-])[\p{L}][\p{L}\p{N}'’ʼ-]*(?![\p{L}\p{N}'’ʼ-])"#
        ) else {
            return text
        }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let wordRange = Range(match.range, in: result) else {
                continue
            }

            let word = String(result[wordRange])
            guard shouldLowercaseLikelyFragmentWord(word) else {
                continue
            }

            result.replaceSubrange(wordRange, with: String(word.prefix(1)).lowercased() + word.dropFirst())
        }

        return result
    }

    private static func lowercaseInitialWordIfSafe(
        in text: String,
        firstLetterRange: Range<String.Index>,
        firstWordEnd: String.Index
    ) -> String {
        let firstWordRange = firstLetterRange.lowerBound..<firstWordEnd
        let firstWord = String(text[firstWordRange])
        guard shouldLowercaseLikelyFragmentWord(firstWord) else {
            return text
        }

        var result = text
        result.replaceSubrange(firstLetterRange, with: String(text[firstLetterRange]).lowercased())
        return result
    }

    private static func shouldLowercaseLikelyFragmentWord(_ word: String) -> Bool {
        let comparisonWord = word.trimmingCharacters(in: apostropheLikeCharacters)
        guard let firstCharacter = comparisonWord.first, firstCharacter.isUppercase else {
            return false
        }

        if comparisonWord == "I" { return false }
        if comparisonWord.count > 1 && comparisonWord.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return false }
        if comparisonWord.dropFirst().contains(where: { $0.isUppercase }) { return false }

        return likelyLowercaseFragments.contains(comparisonWord.lowercased())
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

        if text == "\"",
           hasUnclosedStraightDoubleQuote(in: context.precedingText) {
            return false
        }

        let noLeadingSpaceBefore = CharacterSet(charactersIn: ".,;:!?)]}”’/\\-@_")
        if firstCharacter.unicodeScalars.allSatisfy({ noLeadingSpaceBefore.contains($0) }) {
            return false
        }

        let noLeadingSpaceAfter = CharacterSet(charactersIn: "([{`'\"“‘/")
        if previousCharacter.unicodeScalars.allSatisfy({ noLeadingSpaceAfter.contains($0) }) {
            return false
        }

        let leadingSpaceAfter = CharacterSet(charactersIn: ".,;:!?)]}”’")
        return previousCharacter.isLetter ||
            previousCharacter.isNumber ||
            previousCharacter.unicodeScalars.allSatisfy { leadingSpaceAfter.contains($0) }
    }

    private static func needsLeadingListBoundary(before text: String, context: TextInsertionContext) -> Bool {
        guard context.selectedText?.isEmpty != false,
              let previousCharacter = context.precedingText.last,
              let firstCharacter = text.first,
              !previousCharacter.isWhitespace,
              !firstCharacter.isWhitespace,
              startsWithListMarker(text) else {
            return false
        }

        let linePrefix = currentLinePrefix(in: context.precedingText)
            .trimmingCharacters(in: .whitespaces)
        guard !linePrefix.isEmpty else { return false }

        let allowedListBoundaryBefore = CharacterSet(charactersIn: ".,;:!?)]}”’")
        return previousCharacter.isLetter ||
            previousCharacter.isNumber ||
            previousCharacter.unicodeScalars.allSatisfy { allowedListBoundaryBefore.contains($0) }
    }

    private static func startsWithListMarker(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:-\s+\S|\d{1,2}\.\s+\S)"#) else {
            return false
        }

        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func hasUnclosedStraightDoubleQuote(in precedingText: String) -> Bool {
        let linePrefix = currentLinePrefix(in: precedingText)
        let quoteCount = linePrefix.reduce(0) { count, character in
            character == "\"" ? count + 1 : count
        }

        return quoteCount % 2 == 1
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let protectedText = protectMarkdownListIndentation(in: text)
        let normalizedText = protectedText.text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}(?![-*][ \t]|\d{1,2}\.[ \t])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+(?![-*][ \t]|\d{1,2}\.[ \t])"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return restoreMarkdownListIndentation(in: normalizedText, spans: protectedText.spans)
    }

    private static func protectMarkdownListIndentation(in text: String) -> (text: String, spans: [String]) {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^[ \t]+(?=(?:[-*][ \t]|\d{1,2}\.[ \t]))"#) else {
            return (text, [])
        }

        var protectedText = text
        var spans: [String] = []
        let matches = regex.matches(in: protectedText, range: NSRange(protectedText.startIndex..., in: protectedText))

        for match in matches.reversed() {
            guard let range = Range(match.range, in: protectedText) else {
                continue
            }

            spans.append(String(protectedText[range]))
            protectedText.replaceSubrange(range, with: "__VOICEINK_LIST_INDENT_\(spans.count - 1)__")
        }

        return (protectedText, spans)
    }

    private static func restoreMarkdownListIndentation(in text: String, spans: [String]) -> String {
        var restoredText = text

        for index in spans.indices {
            restoredText = restoredText.replacingOccurrences(
                of: "__VOICEINK_LIST_INDENT_\(index)__",
                with: spans[index]
            )
        }

        return restoredText
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
