#if os(Windows)
import Foundation
import WinSDK

public enum WindowsPasteProofError: Error, Equatable, CustomStringConvertible {
    case noConsoleWindow
    case globalAllocFailed(errorCode: UInt32)
    case globalLockFailed(errorCode: UInt32)
    case globalSizeFailed(errorCode: UInt32)
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
        case .globalSizeFailed(let errorCode):
            return "GlobalSize failed with GetLastError=\(errorCode)"
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

public struct WindowsPasteOptions: Equatable, Hashable, Sendable {
    public var restoreClipboard: Bool
    public var restoreDelaySeconds: TimeInterval

    public init(
        restoreClipboard: Bool = true,
        restoreDelaySeconds: TimeInterval = 2
    ) {
        self.restoreClipboard = restoreClipboard
        self.restoreDelaySeconds = restoreDelaySeconds
    }
}

public struct WindowsPasteResult: Equatable, Hashable, Sendable {
    public var restoreStatus: WindowsClipboardRestoreStatus

    public init(restoreStatus: WindowsClipboardRestoreStatus) {
        self.restoreStatus = restoreStatus
    }
}

public enum WindowsClipboardRestoreStatus: String, Equatable, Hashable, Sendable {
    case disabled
    case restoredText = "restored_text"
    case clearedInsertedText = "cleared_inserted_text"
    case skippedBecauseClipboardChanged = "skipped_clipboard_changed"
}

public enum WindowsPasteProof {
    @discardableResult
    public static func pasteText(
        _ text: String,
        options: WindowsPasteOptions = WindowsPasteOptions()
    ) throws -> WindowsPasteResult {
        let previousText = options.restoreClipboard ? try currentClipboardText() : nil
        try setClipboardText(text)
        try sendControlV()
        let restoreStatus = options.restoreClipboard
            ? try restoreClipboardText(previousText, insertedText: text, delaySeconds: options.restoreDelaySeconds)
            : .disabled
        return WindowsPasteResult(restoreStatus: restoreStatus)
    }

    public static func setClipboardText(_ text: String) throws {
        let payload = WindowsClipboardPayload.cfUnicodeTextData(for: text)
        try setClipboardPayload(payload)
    }

    private static func setClipboardPayload(_ payload: Data) throws {
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

    private static func currentClipboardText() throws -> String? {
        guard let ownerWindow = GetConsoleWindow() else {
            throw WindowsPasteProofError.noConsoleWindow
        }
        guard OpenClipboard(ownerWindow) else {
            throw WindowsPasteProofError.openClipboardFailed(errorCode: GetLastError())
        }
        defer { CloseClipboard() }

        guard IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)) else {
            return nil
        }
        guard let memory = GetClipboardData(UINT(CF_UNICODETEXT)) else {
            return nil
        }

        let byteCount = Int(GlobalSize(memory))
        guard byteCount > 0 else {
            throw WindowsPasteProofError.globalSizeFailed(errorCode: GetLastError())
        }
        guard let lockedMemory = GlobalLock(memory) else {
            throw WindowsPasteProofError.globalLockFailed(errorCode: GetLastError())
        }
        defer { GlobalUnlock(memory) }

        let data = Data(bytes: lockedMemory, count: byteCount)
        return WindowsClipboardPayload.text(fromCFUnicodeTextData: data)
    }

    private static func restoreClipboardText(
        _ previousText: String?,
        insertedText: String,
        delaySeconds: TimeInterval
    ) throws -> WindowsClipboardRestoreStatus {
        let delayMilliseconds = min(max(delaySeconds, 0) * 1_000, Double(UInt32.max))
        let milliseconds = DWORD(delayMilliseconds)
        if milliseconds > 0 {
            Sleep(milliseconds)
        }

        guard try currentClipboardText() == insertedText else {
            return .skippedBecauseClipboardChanged
        }

        if let previousText {
            try setClipboardText(previousText)
            return .restoredText
        }

        try clearClipboard()
        return .clearedInsertedText
    }

    private static func clearClipboard() throws {
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
