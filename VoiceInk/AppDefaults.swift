import Foundation
import LaunchAtLogin
import VoiceInkCore

enum AppDefaults {
    static var registeredDefaults: [String: Any] {
        var defaults = VoiceInkDefaultSettings.macOS.registeredUserDefaults(
            currentTranscriptionModel: VoiceInkTranscriptionModelCatalog.defaultMacOSFluidAudioModelName
        )

        var platformDefaults: [String: Any] = [
            // Onboarding & General

            // Recording & Transcription
            VoiceInkRecorderStylePreference.userDefaultsKey: VoiceInkRecorderStylePreference.defaultRawValue,

            // UI & Behavior
        ]

        platformDefaults.merge(VoiceInkMacOSLaunchAtLoginDefaultPolicy.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkMenuBarPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkAppendTrailingSpacePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkModelRuntimePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecorderPreviewPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecordingShortcutPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkRecordingFeedbackPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkCustomSoundPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkAudioInputPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkPastePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkPowerModePreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkAnnouncementPreference.registeredDefaults) { _, sharedValue in sharedValue }
        platformDefaults.merge(VoiceInkUpdatePreference.registeredDefaults) { _, sharedValue in sharedValue }
        defaults.merge(platformDefaults, uniquingKeysWith: { _, platformValue in platformValue })

        return defaults
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let shouldEnableLaunchAtLoginByDefault = VoiceInkMacOSLaunchAtLoginDefaultPolicy
            .shouldEnableByDefaultBeforeRegisteringDefaults(in: defaults)

        defaults.register(defaults: registeredDefaults)

        if shouldEnableLaunchAtLoginByDefault {
            LaunchAtLogin.isEnabled = true
            VoiceInkMacOSLaunchAtLoginDefaultPolicy.markDefaultApplied(to: defaults)
        }

        VoiceInkStartupPreferenceMigration.migrateLegacyPreferences(for: .macOS)
    }
}
