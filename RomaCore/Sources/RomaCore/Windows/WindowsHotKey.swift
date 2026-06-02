import Foundation

public struct WindowsHotKey: Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let alt = Modifiers(rawValue: 0x0001)
        public static let control = Modifiers(rawValue: 0x0002)
        public static let shift = Modifiers(rawValue: 0x0004)
        public static let win = Modifiers(rawValue: 0x0008)
        public static let noRepeat = Modifiers(rawValue: 0x4000)
    }

    public var id: Int32
    public var modifiers: Modifiers
    public var virtualKeyCode: UInt32

    public init(id: Int32, modifiers: Modifiers, virtualKeyCode: UInt32) {
        self.id = id
        self.modifiers = modifiers
        self.virtualKeyCode = virtualKeyCode
    }

    public static let proofToggle = WindowsHotKey(
        id: 1,
        modifiers: [.control, .shift, .noRepeat],
        virtualKeyCode: 0x52
    )

    public var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.alt) { parts.append("Alt") }
        if modifiers.contains(.win) { parts.append("Win") }
        parts.append(virtualKeyName)
        return parts.joined(separator: "+")
    }

    private var virtualKeyName: String {
        if let scalar = UnicodeScalar(virtualKeyCode),
           CharacterSet.uppercaseLetters.contains(scalar) {
            return String(scalar)
        }

        let hex = String(virtualKeyCode, radix: 16, uppercase: true)
        return "VK_0x\(hex)"
    }
}
