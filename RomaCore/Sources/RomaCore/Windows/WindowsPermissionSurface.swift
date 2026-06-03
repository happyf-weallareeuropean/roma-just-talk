import Foundation

public struct WindowsPermissionSurface: Equatable, Hashable, Sendable {
    public var minimumPermissions: [String]
    public var microphoneSettingsPath: String
    public var requiresDesktopAppMicrophoneAccess: Bool
    public var hotKeyPermissionPrompt: Bool
    public var pastePermissionPrompt: Bool
    public var pasteIntegrityLimit: String
    public var screenCaptureRequired: Bool

    public init(
        minimumPermissions: [String],
        microphoneSettingsPath: String,
        requiresDesktopAppMicrophoneAccess: Bool,
        hotKeyPermissionPrompt: Bool,
        pastePermissionPrompt: Bool,
        pasteIntegrityLimit: String,
        screenCaptureRequired: Bool
    ) {
        self.minimumPermissions = minimumPermissions
        self.microphoneSettingsPath = microphoneSettingsPath
        self.requiresDesktopAppMicrophoneAccess = requiresDesktopAppMicrophoneAccess
        self.hotKeyPermissionPrompt = hotKeyPermissionPrompt
        self.pastePermissionPrompt = pastePermissionPrompt
        self.pasteIntegrityLimit = pasteIntegrityLimit
        self.screenCaptureRequired = screenCaptureRequired
    }

    public static let minimumMVP = WindowsPermissionSurface(
        minimumPermissions: ["microphone", "hotkey", "clipboard"],
        microphoneSettingsPath: "Settings > Privacy & security > Microphone",
        requiresDesktopAppMicrophoneAccess: true,
        hotKeyPermissionPrompt: false,
        pastePermissionPrompt: false,
        pasteIntegrityLimit: "equal_or_lower",
        screenCaptureRequired: false
    )
}
