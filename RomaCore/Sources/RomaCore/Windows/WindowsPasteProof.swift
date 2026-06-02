#if os(Windows)
import Foundation
import WinSDK

public enum WindowsPasteProofError: Error, Equatable, CustomStringConvertible {
    case noConsoleWindow
    case globalAllocFailed(errorCode: UInt32)
    case globalLockFailed(errorCode: UInt32)
    case openClipboardFailed(errorCode: UInt32)
    case emptyClipboardFailed(errorCode: UInt32)
    case setClipboardDataFailed(errorCode: UInt32)
    case sendInputFailed(sent: UInt32, expected: UInt32, errorCode: UInt32)

    public var description: String {
        switch self {
        case .noConsoleWindow:
            return "GetConsoleWindow returned nil; run the proof from a normal console"
        case .globalAllocFailed(let errorCode):
            return "GlobalAlloc failed with GetLastError=\(errorCode)"
        case .globalLockFailed(let errorCode):
            return "GlobalLock failed with GetLastError=\(errorCode)"
        case .openClipboardFailed(let errorCode):
            return "OpenClipboard failed with GetLastError=\(errorCode)"
        case .emptyClipboardFailed(let errorCode):
            return "EmptyClipboard failed with GetLastError=\(errorCode)"
        case .setClipboardDataFailed(let errorCode):
            return "SetClipboardData failed with GetLastError=\(errorCode)"
        case .sendInputFailed(let sent, let expected, let errorCode):
            return "SendInput sent \(sent)/\(expected) events with GetLastError=\(errorCode)"
        }
    }
}

public enum WindowsPasteProof {
    public static func pasteText(_ text: String) throws {
        try setClipboardText(text)
        try sendControlV()
    }

    public static func setClipboardText(_ text: String) throws {
        let payload = WindowsClipboardPayload.cfUnicodeTextData(for: text)
        guard let memory = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(payload.count)) else {
            throw WindowsPasteProofError.globalAllocFailed(errorCode: GetLastError())
        }

        var memoryTransferredToClipboard = false
        defer {
            if !memoryTransferredToClipboard {
                _ = GlobalFree(memory)
            }
        }

        guard let lockedMemory = GlobalLock(memory) else {
            throw WindowsPasteProofError.globalLockFailed(errorCode: GetLastError())
        }

        payload.copyBytes(
            to: UnsafeMutableRawBufferPointer(start: lockedMemory, count: payload.count)
        )
        GlobalUnlock(memory)

        guard let ownerWindow = GetConsoleWindow() else {
            throw WindowsPasteProofError.noConsoleWindow
        }
        guard OpenClipboard(ownerWindow) else {
            throw WindowsPasteProofError.openClipboardFailed(errorCode: GetLastError())
        }
        defer { CloseClipboard() }

        guard EmptyClipboard() else {
            throw WindowsPasteProofError.emptyClipboardFailed(errorCode: GetLastError())
        }
        guard SetClipboardData(UINT(CF_UNICODETEXT), memory) != nil else {
            throw WindowsPasteProofError.setClipboardDataFailed(errorCode: GetLastError())
        }
        memoryTransferredToClipboard = true
    }

    public static func sendControlV() throws {
        var inputs = Array(repeating: INPUT(), count: 4)

        inputs[0].type = DWORD(INPUT_KEYBOARD)
        inputs[0].ki.wVk = WORD(VK_CONTROL)

        inputs[1].type = DWORD(INPUT_KEYBOARD)
        inputs[1].ki.wVk = WORD(0x56)

        inputs[2].type = DWORD(INPUT_KEYBOARD)
        inputs[2].ki.wVk = WORD(0x56)
        inputs[2].ki.dwFlags = DWORD(KEYEVENTF_KEYUP)

        inputs[3].type = DWORD(INPUT_KEYBOARD)
        inputs[3].ki.wVk = WORD(VK_CONTROL)
        inputs[3].ki.dwFlags = DWORD(KEYEVENTF_KEYUP)

        let expected = UINT(inputs.count)
        let sent = inputs.withUnsafeMutableBufferPointer { buffer in
            SendInput(expected, buffer.baseAddress, Int32(MemoryLayout<INPUT>.size))
        }

        guard sent == expected else {
            throw WindowsPasteProofError.sendInputFailed(
                sent: UInt32(sent),
                expected: UInt32(expected),
                errorCode: GetLastError()
            )
        }
    }
}
#endif
