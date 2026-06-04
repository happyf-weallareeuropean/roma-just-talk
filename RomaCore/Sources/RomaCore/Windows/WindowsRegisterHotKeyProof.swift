#if os(Windows)
import Foundation
import WinSDK

public enum WindowsRegisterHotKeyError: Error, Equatable, CustomStringConvertible {
    case registrationFailed(errorCode: UInt32)
    case messageLoopFailed
    case unregisterFailed(errorCode: UInt32)

    public var description: String {
        switch self {
        case .registrationFailed(let errorCode):
            return "RegisterHotKey failed with GetLastError=\(errorCode)"
        case .messageLoopFailed:
            return "GetMessageW failed while waiting for WM_HOTKEY"
        case .unregisterFailed(let errorCode):
            return "UnregisterHotKey failed with GetLastError=\(errorCode)"
        }
    }
}

public enum WindowsRegisterHotKeyProof {
    public static func assertRegistrationAvailable(
        hotKey: WindowsHotKey = .proofToggle
    ) throws {
        guard RegisterHotKey(nil, hotKey.id, hotKey.modifiers.rawValue, hotKey.virtualKeyCode) else {
            throw WindowsRegisterHotKeyError.registrationFailed(errorCode: GetLastError())
        }

        guard UnregisterHotKey(nil, hotKey.id) else {
            throw WindowsRegisterHotKeyError.unregisterFailed(errorCode: GetLastError())
        }
    }

    @discardableResult
    public static func waitForSingleTrigger(
        hotKey: WindowsHotKey = .proofToggle
    ) throws -> WindowsHotKey {
        guard RegisterHotKey(nil, hotKey.id, hotKey.modifiers.rawValue, hotKey.virtualKeyCode) else {
            throw WindowsRegisterHotKeyError.registrationFailed(errorCode: GetLastError())
        }

        defer {
            _ = UnregisterHotKey(nil, hotKey.id)
        }

        var message = MSG()
        while try GetMessageW(&message, nil, 0, 0) {
            if message.message == WM_HOTKEY,
               Int(message.wParam) == Int(hotKey.id) {
                return hotKey
            }
        }

        throw WindowsRegisterHotKeyError.messageLoopFailed
    }

    public static func unregister(hotKey: WindowsHotKey = .proofToggle) throws {
        guard UnregisterHotKey(nil, hotKey.id) else {
            throw WindowsRegisterHotKeyError.unregisterFailed(errorCode: GetLastError())
        }
    }
}
#endif
