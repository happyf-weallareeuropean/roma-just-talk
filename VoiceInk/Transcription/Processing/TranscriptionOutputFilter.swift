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

    private static let lowercaseTranscriptionKey = "LowercaseTranscription"
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

        // Remove filler words (if enabled)
        if FillerWordManager.shared.isEnabled {
            filteredText = removeFillerWords(from: filteredText)
        }

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

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let fullText = value as? String else {
            return nil
        }

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

        let cursorOffset = max(0, min(selectedRange.location, fullText.count))
        let cursorIndex = fullText.index(fullText.startIndex, offsetBy: cursorOffset)
        return TextInsertionContext(
            precedingText: String(fullText[..<cursorIndex]),
            selectedText: selectedText
        )
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
        let trimmedText = precedingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastCharacter = trimmedText.last else { return false }

        if ".!?。！？".contains(lastCharacter) {
            return false
        }

        return true
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
