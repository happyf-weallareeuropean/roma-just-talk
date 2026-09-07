import Foundation

public enum VoiceInkLocalOnboardingModelChoice: String, CaseIterable, Sendable {
    case chineseAndEnglish
    case englishOnly

    public var title: String {
        switch self {
        case .chineseAndEnglish: return "Chinese + English"
        case .englishOnly: return "English only"
        }
    }

    public static func suggested(forCountryCode countryCode: String?) -> Self {
        let country = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["TW", "CN", "HK", "MO", "SG"].contains(country ?? "")
            ? .chineseAndEnglish : .englishOnly
    }
}

/// Region is a suggestion only. User interaction and an existing model take precedence.
public struct VoiceInkLocalOnboardingModelSelection: Equatable, Sendable {
    public private(set) var choice: VoiceInkLocalOnboardingModelChoice
    public private(set) var acceptsRegionSuggestion: Bool

    public init(
        explicitChoice: VoiceInkLocalOnboardingModelChoice? = nil,
        existingModelChoice: VoiceInkLocalOnboardingModelChoice? = nil,
        hasExistingModel: Bool = false
    ) {
        choice = existingModelChoice ?? explicitChoice ?? .englishOnly
        acceptsRegionSuggestion = explicitChoice == nil && !hasExistingModel && existingModelChoice == nil
    }

    public mutating func choose(_ choice: VoiceInkLocalOnboardingModelChoice) {
        self.choice = choice
        acceptsRegionSuggestion = false
    }

    public mutating func preserveCurrentChoice() {
        acceptsRegionSuggestion = false
    }

    public mutating func applyRegionSuggestion(countryCode: String?) {
        guard acceptsRegionSuggestion else { return }
        choice = .suggested(forCountryCode: countryCode)
        acceptsRegionSuggestion = false
    }
}

public enum VoiceInkLocalOnboardingModelPreference {
    private static let key = "macOSOnboardingLocalModelChoice"

    public static func choice(in defaults: UserDefaults = .standard) -> VoiceInkLocalOnboardingModelChoice? {
        defaults.string(forKey: key).flatMap(VoiceInkLocalOnboardingModelChoice.init(rawValue:))
    }

    public static func save(_ choice: VoiceInkLocalOnboardingModelChoice, in defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: key)
    }

    public static func persistedModelName(
        in defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        guard let domainName else { return nil }
        return defaults.persistentDomain(forName: domainName)?[VoiceInkUserDefaultsKey.currentTranscriptionModel] as? String
    }

    public static func persistedLanguage(
        in defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        guard let domainName else { return nil }
        return defaults.persistentDomain(forName: domainName)?[VoiceInkUserDefaultsKey.selectedTranscriptionLanguage] as? String
    }

    public static func shouldDownloadModelAtStartup(
        hasCompletedOnboarding: Bool,
        persistedModelName: String?
    ) -> Bool {
        hasCompletedOnboarding || persistedModelName != nil
    }
}

public enum VoiceInkOnboardingRegionLookup {
    public static let endpoint = URL(string: "https://roma-just-talk.com/api/region")!

    public static func countryCode() async -> String? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await countryCode(session: session)
    }

    static func countryCode(session: URLSession) async -> String? {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  data.count <= 1_024 else { return nil }
            return countryCode(from: data)
        } catch {
            return nil
        }
    }

    static func countryCode(from data: Data) -> String? {
        struct Region: Decodable { let countryCode: String? }
        guard let region = try? JSONDecoder().decode(Region.self, from: data),
              let country = region.countryCode,
              country.utf8.count == 2,
              country.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return country
    }
}
