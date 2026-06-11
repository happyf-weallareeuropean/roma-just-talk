import Foundation

enum ContextualCapitalizationFormatter {
    static func format(_ text: String, beforeCursor: String?) -> String {
        guard let beforeCursor,
              let firstCasedRange = firstCasedCharacterRange(in: text) else {
            return text
        }

        let firstWord = word(in: text, startingAt: firstCasedRange.lowerBound)
        guard !firstWord.isEmpty else { return text }

        switch boundary(beforeCursor) {
        case .sentenceStart:
            guard shouldUppercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).uppercased())
        case .midSentence:
            guard shouldLowercaseFirstCasedCharacter(in: firstWord) else { return text }
            return replacing(text, range: firstCasedRange, with: String(text[firstCasedRange]).lowercased())
        }
    }

    private enum Boundary {
        case sentenceStart
        case midSentence
    }

    private static let sentenceTerminators = Set<Character>([".", "!", "?", "。", "！", "？"])
    private static let wordInternalCharacters = Set<Character>(["'", "’", "‘", "ʼ", "＇", "-"])

    private static func boundary(_ beforeCursor: String) -> Boundary {
        var index = beforeCursor.endIndex
        var sawTrailingNewline = false

        while index > beforeCursor.startIndex {
            let previousIndex = beforeCursor.index(before: index)
            let character = beforeCursor[previousIndex]

            if isWhitespace(character) {
                if containsNewline(character) {
                    sawTrailingNewline = true
                }
                index = previousIndex
                continue
            }

            if sawTrailingNewline || sentenceTerminators.contains(character) {
                return .sentenceStart
            }

            return .midSentence
        }

        return .sentenceStart
    }

    private static func firstCasedCharacterRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if isCasedLetter(text[index]) {
                return index..<nextIndex
            }
            index = nextIndex
        }
        return nil
    }

    private static func word(in text: String, startingAt startIndex: String.Index) -> String {
        var index = startIndex
        var result = ""

        while index < text.endIndex {
            let character = text[index]
            guard isWordCharacter(character) else { break }
            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private static func shouldUppercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard let first = letters.first,
              isLowercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func shouldLowercaseFirstCasedCharacter(in word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard letters.count > 1,
              let first = letters.first,
              isUppercase(first) else {
            return false
        }

        return letters.dropFirst().allSatisfy { isLowercase($0) }
    }

    private static func casedLetters(in word: String) -> [Character] {
        word.filter { isCasedLetter($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        isCasedLetter(character) ||
            wordInternalCharacters.contains(character) ||
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isCasedLetter(_ character: Character) -> Bool {
        let value = String(character)
        return value.lowercased() != value.uppercased()
    }

    private static func isLowercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.lowercased() && value != value.uppercased()
    }

    private static func isUppercase(_ character: Character) -> Bool {
        let value = String(character)
        return value == value.uppercased() && value != value.lowercased()
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func containsNewline(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }

    private static func replacing(_ text: String, range: Range<String.Index>, with replacement: String) -> String {
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
    }
}
