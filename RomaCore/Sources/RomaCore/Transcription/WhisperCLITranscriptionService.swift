import Foundation

public struct WhisperCLITranscriptionConfiguration: Equatable, Sendable {
    public var executableURL: URL
    public var modelURL: URL
    public var outputDirectoryURL: URL
    public var extraArguments: [String]
    public var timeoutSeconds: TimeInterval

    public init(
        executableURL: URL,
        modelURL: URL,
        outputDirectoryURL: URL = FileManager.default.temporaryDirectory,
        extraArguments: [String] = [],
        timeoutSeconds: TimeInterval = 120
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.outputDirectoryURL = outputDirectoryURL
        self.extraArguments = extraArguments
        self.timeoutSeconds = timeoutSeconds
    }

    public func makeInvocation(
        for request: TranscriptionRequest,
        outputBaseName: String = "roma-whisper-\(UUID().uuidString)"
    ) -> WhisperCLITranscriptionInvocation {
        let outputBaseURL = outputDirectoryURL.appendingPathComponent(outputBaseName)
        var arguments = [
            "-m", modelURL.path,
            "-f", request.audioURL.path,
            "-nt",
            "-np",
            "-oj",
            "-of", outputBaseURL.path
        ]

        if let language = trimmedNonEmpty(request.language) {
            arguments.append(contentsOf: ["-l", language])
        }
        if let prompt = trimmedNonEmpty(request.prompt) {
            arguments.append(contentsOf: ["--prompt", prompt])
        }

        arguments.append(contentsOf: extraArguments)

        return WhisperCLITranscriptionInvocation(
            executableURL: executableURL,
            arguments: arguments,
            jsonOutputURL: outputBaseURL.appendingPathExtension("json")
        )
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct WhisperCLITranscriptionInvocation: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var jsonOutputURL: URL

    public init(executableURL: URL, arguments: [String], jsonOutputURL: URL) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.jsonOutputURL = jsonOutputURL
    }
}

public enum WhisperCLITranscriptionError: Error, LocalizedError, Equatable {
    case audioFileNotFound(String)
    case modelFileNotFound(String)
    case executableFileNotFound(String)
    case launchFailed(String)
    case timedOut(TimeInterval)
    case processFailed(status: Int32, stderr: String)
    case outputJSONMissing(String)
    case invalidJSONOutput
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .modelFileNotFound(let path):
            return "Whisper model file not found: \(path)"
        case .executableFileNotFound(let path):
            return "whisper.cpp CLI executable not found: \(path)"
        case .launchFailed(let message):
            return "Failed to launch whisper.cpp CLI: \(message)"
        case .timedOut(let seconds):
            return "whisper.cpp CLI timed out after \(Int(seconds)) seconds."
        case .processFailed(let status, let stderr):
            if stderr.isEmpty {
                return "whisper.cpp CLI failed with exit code \(status)."
            }
            return "whisper.cpp CLI failed with exit code \(status): \(stderr)"
        case .outputJSONMissing(let path):
            return "whisper.cpp CLI did not write JSON output: \(path)"
        case .invalidJSONOutput:
            return "whisper.cpp CLI returned invalid JSON output."
        case .noTranscriptionReturned:
            return "whisper.cpp CLI returned no transcription text."
        }
    }
}

public final class WhisperCLITranscriptionService: TranscriptionService, @unchecked Sendable {
    private let configuration: WhisperCLITranscriptionConfiguration
    private let fileManager: FileManager

    public init(
        configuration: WhisperCLITranscriptionConfiguration,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard fileManager.fileExists(atPath: request.audioURL.path) else {
            throw WhisperCLITranscriptionError.audioFileNotFound(request.audioURL.path)
        }
        guard fileManager.fileExists(atPath: configuration.modelURL.path) else {
            throw WhisperCLITranscriptionError.modelFileNotFound(configuration.modelURL.path)
        }
        guard fileManager.fileExists(atPath: configuration.executableURL.path) else {
            throw WhisperCLITranscriptionError.executableFileNotFound(configuration.executableURL.path)
        }

        try fileManager.createDirectory(
            at: configuration.outputDirectoryURL,
            withIntermediateDirectories: true
        )

        let invocation = configuration.makeInvocation(for: request)
        return try await run(invocation)
    }

    public static func decodeJSONResult(from data: Data) throws -> TranscriptionResult {
        guard let decoded = try? JSONDecoder().decode(WhisperCLIJSONOutput.self, from: data) else {
            throw WhisperCLITranscriptionError.invalidJSONOutput
        }

        let text = decoded.transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw WhisperCLITranscriptionError.noTranscriptionReturned
        }

        return TranscriptionResult(
            text: text,
            language: decoded.languageCode,
            durationSeconds: decoded.durationSeconds
        )
    }

    private func run(_ invocation: WhisperCLITranscriptionInvocation) async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let completion = ProcessCompletion(continuation: continuation)

            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.standardOutput = standardOutput
            process.standardError = standardError

            process.terminationHandler = { process in
                let stderr = Self.string(from: standardError.fileHandleForReading.readDataToEndOfFile())
                _ = standardOutput.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    completion.resume(
                        throwing: WhisperCLITranscriptionError.processFailed(
                            status: process.terminationStatus,
                            stderr: stderr
                        )
                    )
                    return
                }

                guard self.fileManager.fileExists(atPath: invocation.jsonOutputURL.path) else {
                    completion.resume(
                        throwing: WhisperCLITranscriptionError.outputJSONMissing(invocation.jsonOutputURL.path)
                    )
                    return
                }

                do {
                    let data = try Data(contentsOf: invocation.jsonOutputURL)
                    completion.resume(returning: try Self.decodeJSONResult(from: data))
                } catch {
                    completion.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                completion.resume(
                    throwing: WhisperCLITranscriptionError.launchFailed(error.localizedDescription)
                )
                return
            }

            let timeoutSeconds = configuration.timeoutSeconds
            guard timeoutSeconds > 0 else { return }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                guard process.isRunning else { return }
                process.terminate()
                completion.resume(throwing: WhisperCLITranscriptionError.timedOut(timeoutSeconds))
            }
        }
    }

    private static func string(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct WhisperCLIJSONOutput: Decodable {
    var text: String?
    var language: String?
    var duration: Double?
    var result: ResultMetadata?
    var transcription: [Segment]?

    var transcriptionText: String {
        if let text {
            return text
        }
        return transcription?
            .compactMap { segment in
                guard let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return nil
                }
                return text
            }
            .joined(separator: " ") ?? ""
    }

    var languageCode: String? {
        language ?? result?.language
    }

    var durationSeconds: Double? {
        duration ?? result?.duration
    }

    struct ResultMetadata: Decodable {
        var language: String?
        var duration: Double?
    }

    struct Segment: Decodable {
        var text: String?
    }
}

private final class ProcessCompletion<Value>: @unchecked Sendable {
    private let continuation: CheckedContinuation<Value, Error>
    private let lock = NSLock()
    private var didResume = false

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        resume(.success(value))
    }

    func resume(throwing error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else { return }
        didResume = true

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
