import Foundation

public struct RomaWordReplacementRule: Codable, Equatable, Hashable, Sendable {
    public var originalText: String
    public var replacementText: String
    public var isEnabled: Bool

    public init(
        originalText: String,
        replacementText: String,
        isEnabled: Bool = true
    ) {
        self.originalText = originalText
        self.replacementText = replacementText
        self.isEnabled = isEnabled
    }
}

public enum RomaWordReplacementProcessor {
    public static func apply(
        _ rules: [RomaWordReplacementRule],
        to text: String
    ) -> String {
        let enabledRules = rules.filter(\.isEnabled)
        guard !enabledRules.isEmpty else { return text }

        var modifiedText = text
        let sortedRules = enabledRules.sorted {
            $0.originalText.count > $1.originalText.count
        }

        for rule in sortedRules {
            let variants = rule.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            let boundaryVariants = variants.filter(usesWordBoundaries)
            let substringVariants = variants.filter { !usesWordBoundaries(for: $0) }

            modifiedText = replace(
                boundaryVariants,
                in: modifiedText,
                with: rule.replacementText,
                usesBoundaries: true
            )
            modifiedText = replace(
                substringVariants,
                in: modifiedText,
                with: rule.replacementText,
                usesBoundaries: false
            )
        }

        return modifiedText
    }

    private static func replace(
        _ variants: [String],
        in text: String,
        with replacementText: String,
        usesBoundaries: Bool
    ) -> String {
        guard !variants.isEmpty else { return text }

        let alternatives = variants
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        let pattern = usesBoundaries
            ? "(?<![a-zA-Z0-9])(?:\(alternatives))(?![a-zA-Z0-9])"
            : "(?:\(alternatives))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacementText)
        )
    }

    private static func usesWordBoundaries(for text: String) -> Bool {
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,
            0x30A0...0x30FF,
            0x4E00...0x9FFF,
            0xAC00...0xD7AF,
            0x0E00...0x0E7F
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts where range.contains(scalar.value) {
                return false
            }
        }

        return true
    }
}
