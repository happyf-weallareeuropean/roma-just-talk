import Foundation
import RomaCore
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text // No replacements to apply
        }

        let rules = replacements.map {
            RomaWordReplacementRule(
                originalText: $0.originalText,
                replacementText: $0.replacementText,
                isEnabled: $0.isEnabled
            )
        }
        return RomaWordReplacementProcessor.apply(rules, to: text)
    }
}
