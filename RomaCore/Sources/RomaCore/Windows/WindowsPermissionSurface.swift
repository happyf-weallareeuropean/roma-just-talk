import Foundation

public struct WindowsPermissionSurface: Equatable, Hashable, Sendable {
    public var minimumPermissions: [String]
    public var osPermissionGrants: [String]
    public var nativeCapabilities: [String]
    public var microphoneSettingsPath: String
    public var requiresDesktopAppMicrophoneAccess: Bool
    public var hotKeyPermissionPrompt: Bool
    public var pastePermissionPrompt: Bool
    public var pasteIntegrityLimit: String
    public var adminRequired: Bool
    public var startupMechanism: String
    public var startupLauncher: String
    public var startupLaunchMode: String
    public var startupPermissionPrompt: Bool
    public var screenCaptureRequired: Bool

    public init(
        minimumPermissions: [String],
        osPermissionGrants: [String],
        nativeCapabilities: [String],
        microphoneSettingsPath: String,
        requiresDesktopAppMicrophoneAccess: Bool,
        hotKeyPermissionPrompt: Bool,
        pastePermissionPrompt: Bool,
        pasteIntegrityLimit: String,
        adminRequired: Bool,
        startupMechanism: String,
        startupLauncher: String,
        startupLaunchMode: String,
        startupPermissionPrompt: Bool,
        screenCaptureRequired: Bool
    ) {
        self.minimumPermissions = minimumPermissions
        self.osPermissionGrants = osPermissionGrants
        self.nativeCapabilities = nativeCapabilities
        self.microphoneSettingsPath = microphoneSettingsPath
        self.requiresDesktopAppMicrophoneAccess = requiresDesktopAppMicrophoneAccess
        self.hotKeyPermissionPrompt = hotKeyPermissionPrompt
        self.pastePermissionPrompt = pastePermissionPrompt
        self.pasteIntegrityLimit = pasteIntegrityLimit
        self.adminRequired = adminRequired
        self.startupMechanism = startupMechanism
        self.startupLauncher = startupLauncher
        self.startupLaunchMode = startupLaunchMode
        self.startupPermissionPrompt = startupPermissionPrompt
        self.screenCaptureRequired = screenCaptureRequired
    }

    public static let minimumMVP = WindowsPermissionSurface(
        minimumPermissions: ["microphone", "hotkey", "clipboard"],
        osPermissionGrants: ["microphone"],
        nativeCapabilities: [
            "RegisterHotKey",
            "WH_KEYBOARD_LL",
            "Win32 clipboard",
            "SendInput",
            "DPAPI",
            "user Startup folder shortcut"
        ],
        microphoneSettingsPath: "Settings > Privacy & security > Microphone",
        requiresDesktopAppMicrophoneAccess: true,
        hotKeyPermissionPrompt: false,
        pastePermissionPrompt: false,
        pasteIntegrityLimit: "equal_or_lower",
        adminRequired: false,
        startupMechanism: "user_startup_folder_shortcut",
        startupLauncher: "run-windows-agent.ps1",
        startupLaunchMode: "listen",
        startupPermissionPrompt: false,
        screenCaptureRequired: false
    )
}
