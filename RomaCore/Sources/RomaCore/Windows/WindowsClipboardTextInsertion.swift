#if os(Windows)
import Foundation

public struct WindowsClipboardTextInsertion: TextInsertion {
    private let restoreConfiguration: WindowsClipboardRestoreConfiguration

    public init(
        restoreConfiguration: WindowsClipboardRestoreConfiguration = WindowsClipboardRestoreConfiguration()
    ) {
        self.restoreConfiguration = restoreConfiguration
    }

    public func pasteAtCursor(_ text: String) async throws {
        try WindowsPasteProof.pasteText(
            text,
            options: WindowsPasteOptions(
                restoreClipboard: restoreConfiguration.restoreClipboard,
                restoreDelaySeconds: restoreConfiguration.restoreDelaySeconds
            )
        )
    }
}
#endif
