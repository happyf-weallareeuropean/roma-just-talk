import Foundation

public enum PermissionStatus: Equatable, Hashable, Sendable {
    case granted
    case denied
    case notDetermined
    case unavailable
    case restartRequired
}

public protocol RollingRecorder: AnyObject, Sendable {
    var onAudioChunk: (@Sendable (Data) -> Void)? { get set }
    var preRollConfiguration: PreRollConfiguration { get }

    func startPreRollBuffering() async throws
    func startRecording(toOutputFile url: URL) async throws
    func finishRecording() async throws -> RecordedAudio
    func stopCapture() async
}

public protocol ShortcutListening: AnyObject, Sendable {
    func start(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) throws
    func stop()
}

public protocol TextInsertion: Sendable {
    func pasteAtCursor(_ text: String) async throws
}

public protocol PermissionStatusProviding: Sendable {
    func microphoneStatus() -> PermissionStatus
    func shortcutStatus() -> PermissionStatus
    func pasteStatus() -> PermissionStatus
}

public protocol SecretStoring: Sendable {
    func save(_ value: String, forKey key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

public protocol SettingsStoring: Sendable {
    func bool(forKey key: String) -> Bool?
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double?
    func set(_ value: Bool, forKey key: String) throws
    func set(_ value: String, forKey key: String) throws
    func set(_ value: Double, forKey key: String) throws
}
