import Foundation
import IOKit.ps

enum LiveTranscriptionMode: String, CaseIterable, Identifiable {
    case on
    case off
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .on:
            return "On"
        case .off:
            return "Off"
        case .auto:
            return "Auto"
        }
    }
}

struct LiveTranscriptionConfiguration: Equatable {
    let mode: LiveTranscriptionMode
    let autoDisablesCloudModels: Bool
    let autoDisablesLowBatteryLocalModels: Bool
    let lowBatteryThresholdPercent: Int
}

enum LiveTranscriptionSettings {
    static let modeKey = "LiveTranscriptionMode"
    static let autoDisableCloudModelsKey = "LiveTranscriptionAutoDisableCloudModels"
    static let autoDisableLowBatteryLocalModelsKey = "LiveTranscriptionAutoDisableLowBatteryLocalModels"
    static let lowBatteryThresholdPercentKey = "LiveTranscriptionLowBatteryThresholdPercent"

    static let defaultMode: LiveTranscriptionMode = .auto
    static let defaultAutoDisablesCloudModels = false
    static let defaultAutoDisablesLowBatteryLocalModels = true
    static let defaultLowBatteryThresholdPercent = 40

    static func configuration(in defaults: UserDefaults = .standard) -> LiveTranscriptionConfiguration {
        let mode = defaults.string(forKey: modeKey)
            .flatMap(LiveTranscriptionMode.init(rawValue:))
            ?? defaultMode
        let cloudGuard = defaults.object(forKey: autoDisableCloudModelsKey) as? Bool
            ?? defaultAutoDisablesCloudModels
        let lowBatteryGuard = defaults.object(forKey: autoDisableLowBatteryLocalModelsKey) as? Bool
            ?? defaultAutoDisablesLowBatteryLocalModels
        let storedThreshold = defaults.object(forKey: lowBatteryThresholdPercentKey) as? Int
            ?? defaultLowBatteryThresholdPercent

        return LiveTranscriptionConfiguration(
            mode: mode,
            autoDisablesCloudModels: cloudGuard,
            autoDisablesLowBatteryLocalModels: lowBatteryGuard,
            lowBatteryThresholdPercent: min(max(storedThreshold, 1), 100)
        )
    }

    static func perModelStreamingEnabled(for model: any TranscriptionModel, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "streaming-enabled-\(model.name)") as? Bool ?? true
    }
}

struct LiveTranscriptionPowerState: Equatable, Sendable {
    let isOnBattery: Bool
    let batteryLevelPercent: Int?
}

protocol LiveTranscriptionPowerStateProviding {
    func currentPowerState() -> LiveTranscriptionPowerState
}

struct IOKitLiveTranscriptionPowerStateProvider: LiveTranscriptionPowerStateProviding {
    func currentPowerState() -> LiveTranscriptionPowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return LiveTranscriptionPowerState(isOnBattery: false, batteryLevelPercent: nil)
        }

        var hasBattery = false
        var isOnBattery = false
        var levels: [Int] = []

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description[kIOPSTypeKey as String] as? String
            let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int
            let looksLikeBattery = type == (kIOPSInternalBatteryType as String) || currentCapacity != nil
            guard looksLikeBattery else { continue }

            hasBattery = true

            if description[kIOPSPowerSourceStateKey as String] as? String == (kIOPSBatteryPowerValue as String) {
                isOnBattery = true
            }

            if let currentCapacity, let maxCapacity, maxCapacity > 0 {
                levels.append(Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded()))
            }
        }

        return LiveTranscriptionPowerState(
            isOnBattery: hasBattery && isOnBattery,
            batteryLevelPercent: levels.min()
        )
    }
}

struct LiveTranscriptionPolicy {
    let configuration: LiveTranscriptionConfiguration
    let powerState: LiveTranscriptionPowerState

    init(
        configuration: LiveTranscriptionConfiguration,
        powerState: LiveTranscriptionPowerState
    ) {
        self.configuration = configuration
        self.powerState = powerState
    }

    init(defaults: UserDefaults = .standard, powerState: LiveTranscriptionPowerState) {
        self.init(
            configuration: LiveTranscriptionSettings.configuration(in: defaults),
            powerState: powerState
        )
    }

    func allowsStreaming(
        for model: any TranscriptionModel,
        isStreamingOnly: Bool,
        perModelEnabled: Bool
    ) -> Bool {
        guard model.supportsStreaming else { return false }

        // Some providers have no batch endpoint. Keep those usable even when the global
        // preference would otherwise choose file-based transcription.
        if isStreamingOnly { return true }

        guard perModelEnabled else { return false }

        switch configuration.mode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            if configuration.autoDisablesCloudModels, model.provider.isCloudTranscriptionProvider {
                return false
            }

            if configuration.autoDisablesLowBatteryLocalModels,
               model.provider.isLocalTranscriptionProvider,
               powerState.isOnBattery,
               let batteryLevel = powerState.batteryLevelPercent,
               batteryLevel < configuration.lowBatteryThresholdPercent {
                return false
            }

            return true
        }
    }
}

extension ModelProvider {
    var isCloudTranscriptionProvider: Bool {
        switch self {
        case .groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .custom:
            return true
        case .whisper, .fluidAudio, .nativeApple:
            return false
        }
    }

    var isLocalTranscriptionProvider: Bool {
        !isCloudTranscriptionProvider
    }
}
