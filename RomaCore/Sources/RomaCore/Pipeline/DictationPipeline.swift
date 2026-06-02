import Foundation

public struct DictationPipelineRequest: Equatable, Hashable, Sendable {
    public var outputURL: URL
    public var model: TranscriptionModelDescriptor
    public var language: String?
    public var prompt: String?
    public var shouldInsertTranscription: Bool
    public var textProcessing: DictationTextProcessingConfiguration

    public init(
        outputURL: URL,
        model: TranscriptionModelDescriptor,
        language: String? = nil,
        prompt: String? = nil,
        shouldInsertTranscription: Bool = false,
        textProcessing: DictationTextProcessingConfiguration = .standard
    ) {
        self.outputURL = outputURL
        self.model = model
        self.language = language
        self.prompt = prompt
        self.shouldInsertTranscription = shouldInsertTranscription
        self.textProcessing = textProcessing
    }
}

public struct DictationPipelineResult: Equatable, Hashable, Sendable {
    public var session: DictationSession
    public var transcription: TranscriptionResult
    public var processedText: String

    public init(
        session: DictationSession,
        transcription: TranscriptionResult,
        processedText: String
    ) {
        self.session = session
        self.transcription = transcription
        self.processedText = processedText
    }
}

public struct DictationTextProcessingConfiguration: Equatable, Hashable, Sendable {
    public var removesFillerWords: Bool
    public var fillerWords: [String]
    public var wordReplacements: [RomaWordReplacementRule]
    public var punctuationMode: RomaPunctuationCleanupMode
    public var shouldLowercase: Bool
    public var insertionContext: TextInsertionContext?

    public init(
        removesFillerWords: Bool = true,
        fillerWords: [String] = RomaTranscriptionOutputFilter.defaultFillerWords,
        wordReplacements: [RomaWordReplacementRule] = [],
        punctuationMode: RomaPunctuationCleanupMode = .keep,
        shouldLowercase: Bool = false,
        insertionContext: TextInsertionContext? = nil
    ) {
        self.removesFillerWords = removesFillerWords
        self.fillerWords = fillerWords
        self.wordReplacements = wordReplacements
        self.punctuationMode = punctuationMode
        self.shouldLowercase = shouldLowercase
        self.insertionContext = insertionContext
    }

    public static let standard = DictationTextProcessingConfiguration()
}

public enum DictationPipelineError: Error, LocalizedError, Equatable {
    case missingTextInsertion

    public var errorDescription: String? {
        switch self {
        case .missingTextInsertion:
            return "Text insertion was requested, but no TextInsertion adapter was provided."
        }
    }
}

public final class DictationPipeline: @unchecked Sendable {
    private let recorder: RollingRecorder
    private let transcriptionService: TranscriptionService
    private let textInsertion: TextInsertion?

    public init(
        recorder: RollingRecorder,
        transcriptionService: TranscriptionService,
        textInsertion: TextInsertion? = nil
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textInsertion = textInsertion
    }

    public func runRecordingWindow(
        _ request: DictationPipelineRequest,
        recordingWindow: @escaping @Sendable () async throws -> Void
    ) async throws -> DictationPipelineResult {
        if request.shouldInsertTranscription, textInsertion == nil {
            throw DictationPipelineError.missingTextInsertion
        }

        do {
            try await recorder.startRecording(toOutputFile: request.outputURL)
            try await recordingWindow()
            let recordedAudio = try await recorder.finishRecording()

            let transcription = try await transcriptionService.transcribe(
                TranscriptionRequest(
                    audioURL: recordedAudio.fileURL,
                    model: request.model,
                    language: request.language,
                    prompt: request.prompt
                )
            )
            let processedText = processText(transcription.text, using: request.textProcessing)

            var insertedText: String?
            if request.shouldInsertTranscription {
                try await textInsertion?.pasteAtCursor(processedText)
                insertedText = processedText
            }

            await recorder.stopCapture()
            let session = DictationSession(
                recordedAudio: recordedAudio,
                model: request.model,
                status: .completed,
                rawText: transcription.text,
                insertedText: insertedText
            )
            return DictationPipelineResult(
                session: session,
                transcription: transcription,
                processedText: processedText
            )
        } catch {
            await recorder.stopCapture()
            throw error
        }
    }

    private func processText(
        _ text: String,
        using configuration: DictationTextProcessingConfiguration
    ) -> String {
        let filteredText = RomaTranscriptionOutputFilter.filter(
            text,
            removesFillerWords: configuration.removesFillerWords,
            fillerWords: configuration.fillerWords
        )
        let replacedText = RomaWordReplacementProcessor.apply(
            configuration.wordReplacements,
            to: filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let cleanedText = RomaTranscriptionOutputFilter.applyCleanupPreferences(
            replacedText,
            punctuationMode: configuration.punctuationMode,
            shouldLowercase: configuration.shouldLowercase
        )
        let context = configuration.insertionContext.map {
            RomaTranscriptionOutputFilter.TextInsertionContext(
                precedingText: $0.precedingText,
                selectedText: $0.selectedText
            )
        }
        let polishedText = RomaTranscriptionOutputFilter.applyInsertionPolish(cleanedText, context: context)
        return RomaTranscriptionOutputFilter.applyInsertionSpacing(polishedText, context: context)
    }
}
