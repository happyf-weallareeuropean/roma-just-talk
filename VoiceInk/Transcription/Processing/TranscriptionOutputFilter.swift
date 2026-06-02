import Foundation
import ApplicationServices

enum PunctuationCleanupMode: String, Codable, CaseIterable, Identifiable {
    case keep = "keep"
    case removeAll = "removeAll"
    case removeTrailingPeriod = "removeTrailingPeriod"

    static let userDefaultsKey = "PunctuationCleanupMode"
    static let legacyRemovePunctuationKey = "RemovePunctuation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keep:
            return "Keep"
        case .removeAll:
            return "Remove all"
        case .removeTrailingPeriod:
            return "Remove trailing period"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> PunctuationCleanupMode {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           let mode = PunctuationCleanupMode(rawValue: rawValue) {
            return mode
        }

        return defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep
    }

    static func setCurrent(_ mode: PunctuationCleanupMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
        defaults.set(mode == .removeAll, forKey: legacyRemovePunctuationKey)
    }

    static func migrateLegacyUserDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        if let rawValue = defaults.string(forKey: userDefaultsKey),
           PunctuationCleanupMode(rawValue: rawValue) != nil {
            return
        }

        setCurrent(defaults.bool(forKey: legacyRemovePunctuationKey) ? .removeAll : .keep, in: defaults)
    }
}

struct TranscriptionOutputFilter {
    struct TextInsertionContext {
        let precedingText: String
        let selectedText: String?

        init(precedingText: String, selectedText: String? = nil) {
            self.precedingText = precedingText
            self.selectedText = selectedText
        }
    }

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

    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
    private static let maxInsertionContextCharacters = 512
    private static let apostropheLikeCharacters = CharacterSet(charactersIn: "'’‘ʼ＇")
    private static let removableTrailingFragmentPunctuation = CharacterSet(charactersIn: ".,;:…")
    private static let nonSpeechBracketContents: Set<String> = [
        "applause", "background noise", "inaudible", "laughter", "laughs",
        "music", "noise", "silence", "sound", "static"
    ]
    private static let preservedRepeatedWords: Set<String> = [
        "ha", "haha", "no", "ok", "okay", "really", "so", "very", "yes"
    ]
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
    
    private static let hallucinationPatterns = [
        #"\[.*?\]"#,     // []
        #"\(.*?\)"#,     // ()
        #"\{.*?\}"#      // {}
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
    private static let backtrackingMarkerPattern = #"""
        (?ix)
        \s*
        (?:
            (?:[,;:…]|\.\.\.)\s*actually |
            sorry\s+not\s+that\s*[,;:]?\s+actually |
            scratch\s+that |
            wait\s+no |
            sorry\s+not\s+that |
            sorry\s+no |
            i\s+mean
        )
        \s*[,;:]?\s+
        """#
    private static let phraseBoundaryPunctuation = CharacterSet(charactersIn: ".,!?;:…")
    private static let softPhrasePunctuation = CharacterSet(charactersIn: ",;:…")
    private static let wordConnectorCharacters = CharacterSet(charactersIn: "'’ʼ-")
    private static let maxBacktrackingCorrectionWords = 4
    private static let spokenFormattingCommands: [(pattern: String, replacement: String)] = [
        (#"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+paragraph(?![\p{L}\p{N}])"#, "\n\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new|next)\s+line(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])line\s+break(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])newline(?![\p{L}\p{N}])"#, "\n"),
        (#"(?i)(?<![\p{L}\p{N}])(?:new\s+bullet|bullet\s+point|bullet)(?![\p{L}\p{N}])"#, "\n- ")
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
            output: ":"
        )
    ]

    static func filter(_ text: String) -> String {
        var filteredText = unwrapBracketedWholeOutput(text)

        // Remove <TAG>...</TAG> blocks
        let tagBlockPattern = #"<([A-Za-z][A-Za-z0-9:_-]*)[^>]*>[\s\S]*?</\1>"#
        if let regex = try? NSRegularExpression(pattern: tagBlockPattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        // Remove bracketed hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }

        filteredText = removeASRBoilerplate(from: filteredText)

        // Remove filler words (if enabled)
        if FillerWordManager.shared.isEnabled {
            filteredText = removeFillerWords(from: filteredText)
        }

        filteredText = applyBacktrackingCorrections(in: filteredText)
        filteredText = applySpokenFormattingCommands(in: filteredText)
        filteredText = applySpokenPunctuationCommands(in: filteredText)
        filteredText = collapseAdjacentRepeatedWords(in: filteredText)

        // Clean whitespace
        filteredText = normalizeWhitespace(filteredText)

        return filteredText
    }

    static func currentInsertionContext() -> TextInsertionContext? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
              let focusedElement else {
            return nil
        }

        let element = focusedElement as! AXUIElement

        var selectedText: String?
        var selectedTextValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        ) == .success {
            selectedText = selectedTextValue as? String
        }

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
              let selectedRangeValue,
              CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &selectedRange) else {
            return nil
        }

        if let precedingText = precedingTextFromParameterizedRange(
            in: element,
            cursorOffset: selectedRange.location
        ) {
            return TextInsertionContext(precedingText: precedingText, selectedText: selectedText)
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let fullText = value as? String else {
            return nil
        }

        return insertionContext(fromFullText: fullText, selectedRange: selectedRange, selectedText: selectedText)
    }

    private static func precedingTextFromParameterizedRange(in element: AXUIElement, cursorOffset: Int) -> String? {
        guard cursorOffset > 0 else { return "" }

        let prefixStart = max(0, cursorOffset - maxInsertionContextCharacters)
        var prefixRange = CFRange(location: prefixStart, length: cursorOffset - prefixStart)
        guard let axRange = AXValueCreate(.cfRange, &prefixRange) else {
            return nil
        }

        var prefixValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &prefixValue
        ) == .success else {
            return nil
        }

        return prefixValue as? String
    }

    private static func insertionContext(
        fromFullText fullText: String,
        selectedRange: CFRange,
        selectedText: String?
    ) -> TextInsertionContext {
        let cursorOffset = max(0, min(selectedRange.location, fullText.count))
        let cursorIndex = fullText.index(fullText.startIndex, offsetBy: cursorOffset)
        return TextInsertionContext(
            precedingText: String(fullText[..<cursorIndex]),
            selectedText: selectedText
        )
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

    static func applyInsertionPolish(_ text: String, context: TextInsertionContext?) -> String {
        var polishedText = stripBoundaryNoise(from: normalizeWhitespace(text))
        guard !polishedText.isEmpty else { return polishedText }

        let shouldTreatAsFragment = isShortFragment(polishedText)
        if shouldTreatAsFragment {
            polishedText = removeTrailingFragmentPunctuation(from: polishedText)
        }

        if let context {
            guard isContinuingSentence(after: context.precedingText) else {
                return polishedText
            }
            return lowercaseInitialWordIfSafe(in: polishedText, force: true)
        }

        return lowercaseInitialWordIfSafe(in: polishedText, force: false)
    }

    static func applyInsertionSpacing(_ text: String, context: TextInsertionContext?) -> String {
        guard let context else { return text }
        guard needsLeadingSpace(before: text, context: context) else { return text }
        return " \(text)"
    }

    private static func removeFillerWords(from text: String) -> String {
        var filteredText = text

        let spokenPausePattern = #"(?i)(?<![\p{L}\p{N}])(?:u+h+|u+m+|h+m+|m+h+|m{2,}|e+h+|e+r+|a+h+|h+uh+)(?:[.,;:!?…]+)?(?![\p{L}\p{N}])"#
        if let regex = try? NSRegularExpression(pattern: spokenPausePattern) {
            let range = NSRange(filteredText.startIndex..., in: filteredText)
            filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
        }

        let fillerWords = Set(FillerWordManager.shared.fillerWords + FillerWordManager.defaultFillerWords)
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

        guard previousWord(in: beforeCommand) != nil else { return false }

        if let previousWord = previousWord(in: beforeCommand),
           command.blockedPreviousWords.contains(previousWord) {
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

        if let firstSuffixCharacter = suffix.first,
           firstSuffixCharacter.isPunctuation || firstSuffixCharacter.isNewline {
            return prefix + command.output + suffix
        }

        return "\(prefix)\(command.output) \(suffix)"
    }

    private static func normalizePunctuationSpacing(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,.;:!?])([^\s,.;:!?\]\)}])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([)\]\}])"#, with: "$1", options: .regularExpression)
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

        return correctedText
    }

    private static func rewriteBacktrackingMatch(in text: String, markerRange: Range<String.Index>) -> String? {
        let beforeMarker = String(text[..<markerRange.lowerBound])
        let afterMarker = String(text[markerRange.upperBound...])

        guard let correction = leadingCorrectionPhrase(in: afterMarker),
              let prefix = removeTrailingWords(correction.wordCount, from: beforeMarker) else {
            return nil
        }

        let correctionText = String(afterMarker[correction.range])
        let suffix = String(afterMarker[correction.range.upperBound...])
        return normalizeBacktrackingWhitespace(join(prefix, correctionText, suffix))
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

    private static func unwrapBracketedWholeOutput(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmedText.first,
              let last = trimmedText.last,
              let expectedClosing = matchingClosingBracket(for: first),
              expectedClosing == last else {
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

    private static func matchingClosingBracket(for opening: Character) -> Character? {
        switch opening {
        case "[": return "]"
        case "(": return ")"
        case "{": return "}"
        default: return nil
        }
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

    private static func stripBoundaryNoise(from text: String) -> String {
        var strippedText = unwrapBracketedWholeOutput(text)
        guard isShortFragment(strippedText) else { return strippedText }

        let boundaryCharacters = CharacterSet(charactersIn: #"[]{}()"“”‘’'"`"#)
        strippedText = strippedText.trimmingCharacters(in: boundaryCharacters.union(.whitespacesAndNewlines))
        return normalizeWhitespace(strippedText)
    }

    private static func removeTrailingFragmentPunctuation(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastScalar = result.unicodeScalars.last,
              removableTrailingFragmentPunctuation.contains(lastScalar) {
            result.removeLast()
        }
        return result
    }

    private static func isShortFragment(_ text: String) -> Bool {
        let sentencePunctuation = CharacterSet(charactersIn: "!?")
        if text.unicodeScalars.contains(where: { sentencePunctuation.contains($0) }) {
            return false
        }

        return wordCount(in: text) <= 3
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

        if firstCharacter.isPunctuation {
            return false
        }

        let noLeadingSpaceAfter = CharacterSet(charactersIn: "([{`'\"“‘/")
        if previousCharacter.unicodeScalars.allSatisfy({ noLeadingSpaceAfter.contains($0) }) {
            return false
        }

        return previousCharacter.isLetter || previousCharacter.isNumber || previousCharacter == "." || previousCharacter == "," || previousCharacter == ")" || previousCharacter == "]"
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\r\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = PunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        return applyCleanupPreferences(text, punctuationMode: punctuationMode, shouldLowercase: shouldLowercase)
    }

    static func applyCleanupPreferences(_ text: String, punctuationMode: PunctuationCleanupMode, shouldLowercase: Bool) -> String {
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

    static func removeTrailingPeriod(from text: String) -> String {
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

    static func removePunctuation(from text: String) -> String {
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
