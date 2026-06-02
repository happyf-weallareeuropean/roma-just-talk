import Foundation

public enum WindowsClipboardPayload {
    public static func cfUnicodeTextData(for text: String) -> Data {
        var data = Data()
        data.reserveCapacity((text.utf16.count + 1) * MemoryLayout<UInt16>.size)

        for codeUnit in text.utf16 {
            appendUInt16LittleEndian(codeUnit, to: &data)
        }
        appendUInt16LittleEndian(0, to: &data)
        return data
    }

    private static func appendUInt16LittleEndian(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x00FF),
            UInt8((value & 0xFF00) >> 8)
        ])
    }
}
