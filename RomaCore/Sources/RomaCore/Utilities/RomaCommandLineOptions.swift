import Foundation

public enum RomaCommandLineOptionsError: Error, LocalizedError, Equatable {
    case missingOption(String)
    case invalidOptionValue(String)
    case conflictingOptions(String)

    public var errorDescription: String? {
        switch self {
        case .missingOption(let option):
            return "missing required option \(option)"
        case .invalidOptionValue(let option):
            return "invalid value for option \(option)"
        case .conflictingOptions(let message):
            return "conflicting options: \(message)"
        }
    }
}

public struct RomaCommandLineOptions: Sendable {
    public var arguments: [String]

    public init(_ arguments: [String]) {
        self.arguments = arguments
    }

    public func contains(_ option: String) -> Bool {
        arguments.contains(option)
    }

    public func value(after option: String) throws -> String {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            throw RomaCommandLineOptionsError.missingOption(option)
        }
        return arguments[index + 1]
    }

    public func optionalValue(after option: String) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        let trimmed = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func values(after option: String) throws -> [String] {
        var values: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            defer { index = arguments.index(after: index) }
            guard arguments[index] == option else { continue }

            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw RomaCommandLineOptionsError.missingOption(option)
            }

            values.append(arguments[valueIndex])
            index = valueIndex
        }
        return values
    }

    public func doubleValue(after option: String, default defaultValue: Double) throws -> Double {
        guard let index = arguments.firstIndex(of: option) else {
            return defaultValue
        }
        guard arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]) else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }
        return value
    }
}

public enum RomaCommandLineText {
    public static func oneLine(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
    }

    public static func isValidEnvironmentName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }

        return value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    public static func wordReplacementRules(
        from options: RomaCommandLineOptions,
        option: String = "--replace"
    ) throws -> [RomaWordReplacementRule] {
        try options.values(after: option).map { value in
            try wordReplacementRule(from: value, option: option)
        }
    }

    public static func wordReplacementRule(
        from value: String,
        option: String = "--replace"
    ) throws -> RomaWordReplacementRule {
        let pieces = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }

        let original = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else {
            throw RomaCommandLineOptionsError.invalidOptionValue(option)
        }

        return RomaWordReplacementRule(
            originalText: original,
            replacementText: replacement
        )
    }
}
