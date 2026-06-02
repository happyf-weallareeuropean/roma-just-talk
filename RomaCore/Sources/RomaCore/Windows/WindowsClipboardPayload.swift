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

    public static func text(fromCFUnicodeTextData data: Data) -> String? {
        guard data.count.isMultiple(of: MemoryLayout<UInt16>.size) else {
            return nil
        }

        var codeUnits: [UInt16] = []
        codeUnits.reserveCapacity(data.count / MemoryLayout<UInt16>.size)

        for offset in stride(from: 0, to: data.count, by: MemoryLayout<UInt16>.size) {
            let codeUnit = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if codeUnit == 0 {
                return String(decoding: codeUnits, as: UTF16.self)
            }
            codeUnits.append(codeUnit)
        }

        return String(decoding: codeUnits, as: UTF16.self)
    }

    private static func appendUInt16LittleEndian(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0x00FF),
            UInt8((value & 0xFF00) >> 8)
        ])
    }
}
