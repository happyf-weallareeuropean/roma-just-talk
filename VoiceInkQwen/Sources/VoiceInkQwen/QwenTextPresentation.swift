import Foundation

enum QwenTextPresentation {
    /// Converts the complete display hypothesis; raw decoder text/prefix tokens stay untouched.
    static func traditional(_ text: String) throws -> String {
        guard let converted = text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) else {
            throw QwenRuntimeError.textConversionUnavailable
        }
        return converted
    }
}
