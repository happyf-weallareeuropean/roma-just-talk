import Foundation

public enum WindowsDictationTrigger: Equatable, Hashable, Sendable {
    case toggle(recordSeconds: TimeInterval)
    case hold(timeoutMilliseconds: UInt32)
}

public enum WindowsDictationRuntimeEvent: Equatable, Hashable, Sendable {
    case preRollBuffering
    case waitingForToggle(displayName: String)
    case toggleReceived
    case waitingForHoldKeyDown(displayName: String)
    case holdKeyDown
    case holdKeyUp
}

public struct WindowsDictationRuntimeRequest: Sendable {
    public var outputURL: URL
    public var model: TranscriptionModelDescriptor
    public var language: String?
    public var prompt: String?
    public var shouldPaste: Bool
    public var clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration
    public var textProcessing: DictationTextProcessingConfiguration
    public var trigger: WindowsDictationTrigger

    public init(
        outputURL: URL,
        model: TranscriptionModelDescriptor,
        language: String? = nil,
        prompt: String? = nil,
        shouldPaste: Bool = false,
        clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration = WindowsClipboardRestoreConfiguration(),
        textProcessing: DictationTextProcessingConfiguration = .standard,
        trigger: WindowsDictationTrigger
    ) {
        self.outputURL = outputURL
        self.model = model
        self.language = language
        self.prompt = prompt
        self.shouldPaste = shouldPaste
        self.clipboardRestoreConfiguration = clipboardRestoreConfiguration
        self.textProcessing = textProcessing
        self.trigger = trigger
    }
}

public enum WindowsDictationRuntimeError: Error, LocalizedError, Equatable {
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Windows dictation runtime is only available on Windows."
        }
    }
}

public enum WindowsDictationRuntime {
    public static var isRuntimeAvailable: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    public static func run(
        _ request: WindowsDictationRuntimeRequest,
        transcriptionService: TranscriptionService,
        onEvent: @escaping @Sendable (WindowsDictationRuntimeEvent) -> Void = { _ in }
    ) async throws -> DictationPipelineResult {
        #if os(Windows)
        let recorder = MiniaudioCaptureRecorder()
        let pipeline = DictationPipeline(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textInsertion: request.shouldPaste
                ? WindowsClipboardTextInsertion(
                    restoreConfiguration: request.clipboardRestoreConfiguration
                )
                : nil
        )
        let pipelineRequest = DictationPipelineRequest(
            outputURL: request.outputURL,
            model: request.model,
            language: request.language,
            prompt: request.prompt,
            shouldInsertTranscription: request.shouldPaste,
            textProcessing: request.textProcessing
        )

        do {
            try await recorder.startPreRollBuffering()
            onEvent(.preRollBuffering)

            switch request.trigger {
            case .toggle(let recordSeconds):
                let hotKey = WindowsHotKey.proofToggle
                onEvent(.waitingForToggle(displayName: hotKey.displayName))
                try WindowsRegisterHotKeyProof.waitForSingleTrigger(hotKey: hotKey)
                onEvent(.toggleReceived)

                return try await pipeline.runRecordingWindow(pipelineRequest) {
                    try await sleep(seconds: recordSeconds)
                }
            case .hold(let timeoutMilliseconds):
                let chord = WindowsLowLevelKeyboardHookChord.proofHold
                onEvent(.waitingForHoldKeyDown(displayName: chord.displayName))
                _ = try WindowsLowLevelKeyboardHookProof.waitForKeyDown(
                    chord: chord,
                    timeoutMilliseconds: timeoutMilliseconds
                )
                onEvent(.holdKeyDown)

                return try await pipeline.runRecordingWindow(pipelineRequest) {
                    _ = try WindowsLowLevelKeyboardHookProof.waitForKeyUp(
                        chord: chord,
                        timeoutMilliseconds: timeoutMilliseconds
                    )
                    onEvent(.holdKeyUp)
                }
            }
        } catch {
            await recorder.stopCapture()
            throw error
        }
        #else
        throw WindowsDictationRuntimeError.unsupported
        #endif
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
