#if os(Windows)
import Foundation

public struct WindowsClipboardTextInsertion: TextInsertion {
    public init() {}

    public func pasteAtCursor(_ text: String) async throws {
        try WindowsPasteProof.pasteText(text)
    }
}
#endif
