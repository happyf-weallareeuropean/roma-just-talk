import Foundation
import CoreAudio

enum SystemMuteMode: String, CaseIterable, Identifiable {
    case automatic = "auto"
    case always = "always"
    case never = "never"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .always: return "On"
        case .never: return "Off"
        }
    }
}

final class MediaController: ObservableObject {

    static let shared = MediaController()

    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var unmuteTask: Task<Void, Never>?
    private var muteGeneration: Int = 0

    @Published var systemMuteMode: SystemMuteMode = {
        guard let rawValue = UserDefaults.standard.string(forKey: "systemMuteMode"),
              let mode = SystemMuteMode(rawValue: rawValue) else {
            return .automatic
        }
        return mode
    }() {
        didSet {
            UserDefaults.standard.set(systemMuteMode.rawValue, forKey: "systemMuteMode")
            UserDefaults.standard.set(systemMuteMode != .never, forKey: "isSystemMuteEnabled")
        }
    }

    var isSystemMuteEnabled: Bool {
        get { systemMuteMode != .never }
        set { systemMuteMode = newValue ? .always : .never }
    }

    @Published var audioResumptionDelay: Double = UserDefaults.standard.double(forKey: "audioResumptionDelay") {
        didSet { UserDefaults.standard.set(audioResumptionDelay, forKey: "audioResumptionDelay") }
    }

    private init() {}

    func muteSystemAudio(forInputDevice deviceID: AudioDeviceID) async -> Bool {
        guard shouldMuteAudio(forInputDevice: deviceID) else { return false }

        unmuteTask?.cancel()
        unmuteTask = nil
        muteGeneration += 1

        let currentlyMuted = isSystemAudioMuted()

        if currentlyMuted {
            if didMuteAudio {
                // We muted it previously, stay responsible for unmuting
                wasAudioMutedBeforeRecording = false
            } else {
                // User muted it, don't unmute when done
                wasAudioMutedBeforeRecording = true
                didMuteAudio = false
            }
            return true
        }

        wasAudioMutedBeforeRecording = false
        let success = setSystemMuted(true)
        didMuteAudio = success
        return success
    }

    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled else { return }

        let delay = audioResumptionDelay
        let shouldUnmute = didMuteAudio && !wasAudioMutedBeforeRecording
        let myGeneration = muteGeneration

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            guard self.muteGeneration == myGeneration else { return }

            if shouldUnmute {
                _ = self.setSystemMuted(false)
            }

            self.didMuteAudio = false
        }

        unmuteTask = task
        await task.value
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func isSystemAudioMuted() -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &muted)
        return status == noErr && muted != 0
    }

    private func setSystemMuted(_ muted: Bool) -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

        var muteValue: UInt32 = muted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }

        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if status != noErr || !isSettable.boolValue { return false }

        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &muteValue)
        return status == noErr
    }

    private func shouldMuteAudio(forInputDevice deviceID: AudioDeviceID) -> Bool {
        switch systemMuteMode {
        case .always:
            return true
        case .never:
            return false
        case .automatic:
            // Simplified fast-dev policy: built-in mic gets output mute, external mics do not.
            // Future expansion can add explicit external-mic noise/isolation rules here.
            return AudioDeviceManager.shared.isBuiltInDevice(deviceID)
        }
    }
}
