import ApplicationServices
import Foundation
import RomaCore

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
    typealias TextInsertionContext = RomaTranscriptionOutputFilter.TextInsertionContext

    private static let maxInsertionContextCharacters = 512
    private static let lowercaseTranscriptionKey = "LowercaseTranscription"

    static func filter(_ text: String) -> String {
        RomaTranscriptionOutputFilter.filter(
            text,
            removesFillerWords: FillerWordManager.shared.isEnabled,
            fillerWords: FillerWordManager.shared.fillerWords
        )
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

    static func applyInsertionPolish(_ text: String, context: TextInsertionContext?) -> String {
        RomaTranscriptionOutputFilter.applyInsertionPolish(text, context: context)
    }

    static func applyInsertionSpacing(_ text: String, context: TextInsertionContext?) -> String {
        RomaTranscriptionOutputFilter.applyInsertionSpacing(text, context: context)
    }

    static func applyUserCleanupPreferences(_ text: String) -> String {
        let punctuationMode = PunctuationCleanupMode.current()
        let shouldLowercase = UserDefaults.standard.bool(forKey: lowercaseTranscriptionKey)

        return applyCleanupPreferences(text, punctuationMode: punctuationMode, shouldLowercase: shouldLowercase)
    }

    static func applyCleanupPreferences(
        _ text: String,
        punctuationMode: PunctuationCleanupMode,
        shouldLowercase: Bool
    ) -> String {
        RomaTranscriptionOutputFilter.applyCleanupPreferences(
            text,
            punctuationMode: romaMode(for: punctuationMode),
            shouldLowercase: shouldLowercase
        )
    }

    static func removeTrailingPeriod(from text: String) -> String {
        RomaTranscriptionOutputFilter.removeTrailingPeriod(from: text)
    }

    static func removePunctuation(from text: String) -> String {
        RomaTranscriptionOutputFilter.removePunctuation(from: text)
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

    private static func romaMode(for mode: PunctuationCleanupMode) -> RomaPunctuationCleanupMode {
        switch mode {
        case .keep:
            return .keep
        case .removeAll:
            return .removeAll
        case .removeTrailingPeriod:
            return .removeTrailingPeriod
        }
    }
}
