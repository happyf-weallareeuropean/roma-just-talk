import Foundation

public enum VoiceInkUpdateTrack: String, CaseIterable, Identifiable, Sendable {
    case stable
    case prerelease

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .prerelease:
            return "Prerelease"
        }
    }

    public var feedURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://github.com/negentropi/roma-just-talk/releases/latest/download/appcast.xml")!
        case .prerelease:
            return URL(string: "https://github.com/negentropi/roma-just-talk/releases/latest/download/appcast-prerelease.xml")!
        }
    }
}

public enum VoiceInkUpdatePreference {
    public static let automaticUpdatesEnabledKey = "automaticUpdatesEnabled"
    public static let trackKey = "updateTrack"
    public static let defaultAutomaticUpdatesEnabled = true
    public static let defaultTrack = VoiceInkUpdateTrack.stable
    public static let releaseHistoryURL = URL(string: "https://github.com/negentropi/roma-just-talk/releases")!

    public static let registeredDefaults: [String: Any] = [
        trackKey: defaultTrack.rawValue
    ]

    private static let legacyAutomaticUpdateKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate"
    ]

    public static func automaticUpdatesEnabled(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: automaticUpdatesEnabledKey) != nil {
            return defaults.bool(forKey: automaticUpdatesEnabledKey)
        }

        let hasLegacyOptOut = legacyAutomaticUpdateKeys.contains {
            defaults.object(forKey: $0) != nil && !defaults.bool(forKey: $0)
        }
        return hasLegacyOptOut ? false : defaultAutomaticUpdatesEnabled
    }

    public static func migrateAutomaticUpdatesEnabled(
        from defaults: UserDefaults = .standard
    ) -> Bool {
        let isEnabled = automaticUpdatesEnabled(from: defaults)
        saveAutomaticUpdatesEnabled(isEnabled, to: defaults)
        return isEnabled
    }

    public static func saveAutomaticUpdatesEnabled(
        _ isEnabled: Bool,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: automaticUpdatesEnabledKey)
    }

    public static func track(from defaults: UserDefaults = .standard) -> VoiceInkUpdateTrack {
        guard let rawValue = defaults.string(forKey: trackKey),
              let track = VoiceInkUpdateTrack(rawValue: rawValue) else {
            return defaultTrack
        }
        return track
    }

    public static func saveTrack(_ track: VoiceInkUpdateTrack, to defaults: UserDefaults = .standard) {
        defaults.set(track.rawValue, forKey: trackKey)
    }
}

public enum VoiceInkUpdatePolicy {
    public static func shouldHandleFoundUpdate(
        automaticUpdatesEnabled: Bool,
        userInitiated: Bool
    ) -> Bool {
        automaticUpdatesEnabled || userInitiated
    }
}

public enum VoiceInkUpdatePresentation {
    public static let automaticUpdatesTitle = "Automatically download updates"
    public static let trackTitle = "Update track"
    public static let checkNowTitle = "Check Now"
    public static let releaseHistoryTitle = "Release History"
    public static let releaseNotesTitle = "Release Notes"
    public static let cancelTitle = "Cancel"
    public static let relaunchTitle = "Relaunch"
    public static let dismissAccessibilityLabel = "Dismiss update status"
}

public enum VoiceInkUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case downloading
    case preparing
    case ready
    case installing
    case upToDate
    case failed
}

public struct VoiceInkUpdateStatus: Equatable, Sendable {
    public let phase: VoiceInkUpdatePhase
    public let version: String?
    public let progress: Double?
    public let detail: String?

    public init(
        phase: VoiceInkUpdatePhase,
        version: String? = nil,
        progress: Double? = nil,
        detail: String? = nil
    ) {
        self.phase = phase
        self.version = version
        self.progress = progress.map { min(max($0, 0), 1) }
        self.detail = detail
    }

    public static let idle = VoiceInkUpdateStatus(phase: .idle)

    public var isVisible: Bool {
        phase != .idle
    }

    public var title: String {
        switch phase {
        case .idle:
            return ""
        case .checking:
            return "Checking for updates…"
        case .downloading:
            return version.map { "Downloading \($0)…" } ?? "Downloading update…"
        case .preparing:
            return version.map { "Preparing \($0)…" } ?? "Preparing update…"
        case .ready:
            return version.map { "\($0) is ready" } ?? "Update is ready"
        case .installing:
            return "Installing update…"
        case .upToDate:
            return "You’re up to date"
        case .failed:
            return "Update failed"
        }
    }

    public var canCancel: Bool {
        switch phase {
        case .checking, .downloading, .ready:
            return true
        default:
            return false
        }
    }

    public var canRelaunch: Bool {
        phase == .ready
    }
}
