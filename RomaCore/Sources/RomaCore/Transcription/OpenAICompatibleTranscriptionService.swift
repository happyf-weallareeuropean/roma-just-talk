import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAICompatibleTranscriptionConfiguration: Sendable {
    public var endpointURL: URL
    public var apiKey: String

    public init(endpointURL: URL, apiKey: String) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
    }
}

public enum OpenAICompatibleTranscriptionError: Error, LocalizedError {
    case audioFileNotFound(String)
    case invalidResponse
    case apiRequestFailed(statusCode: Int, message: String)
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidResponse:
            return "The transcription endpoint returned an invalid response."
        case .apiRequestFailed(let statusCode, let message):
            return "The transcription endpoint failed with status \(statusCode): \(message)"
        case .noTranscriptionReturned:
            return "The transcription endpoint returned no text."
        }
    }
}

public struct OpenAICompatibleMultipartBody: Sendable {
    public var boundary: String
    public var contentType: String
    public var data: Data

    public init(boundary: String, data: Data) {
        self.boundary = boundary
        self.contentType = "multipart/form-data; boundary=\(boundary)"
        self.data = data
    }
}

public enum OpenAICompatibleMultipartRequestBuilder {
    public static func makeBody(
        audioData: Data,
        fileName: String,
        modelName: String,
        language: String? = nil,
        prompt: String? = nil,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) -> OpenAICompatibleMultipartBody {
        let crlf = "\r\n"
        var body = Data()

        func append(_ string: String) {
            body.append(contentsOf: string.utf8)
        }

        func field(_ name: String, _ value: String) {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(escapeHeaderValue(name))\"\(crlf)\(crlf)")
            append(value)
            append(crlf)
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(escapeHeaderValue(fileName))\"\(crlf)")
        append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        append(crlf)

        field("model", modelName)
        field("response_format", "json")
        field("temperature", "0")

        if let language = trimmedNonEmpty(language), language != "auto" {
            field("language", language)
        }
        if let prompt = trimmedNonEmpty(prompt) {
            field("prompt", prompt)
        }

        append("--\(boundary)--\(crlf)")
        return OpenAICompatibleMultipartBody(boundary: boundary, data: body)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func escapeHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public final class OpenAICompatibleTranscriptionService: TranscriptionService, @unchecked Sendable {
    private let configuration: OpenAICompatibleTranscriptionConfiguration
    private let session: URLSession

    public init(
        configuration: OpenAICompatibleTranscriptionConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: request.audioURL.path) else {
            throw OpenAICompatibleTranscriptionError.audioFileNotFound(request.audioURL.path)
        }

        let audioData = try Data(contentsOf: request.audioURL)
        let multipart = OpenAICompatibleMultipartRequestBuilder.makeBody(
            audioData: audioData,
            fileName: request.audioURL.lastPathComponent,
            modelName: request.model.name,
            language: request.language,
            prompt: request.prompt
        )

        var urlRequest = URLRequest(url: configuration.endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = multipart.data

        let (data, response) = try await data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleTranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No response body"
            throw OpenAICompatibleTranscriptionError.apiRequestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAICompatibleTranscriptionError.noTranscriptionReturned
        }

        return TranscriptionResult(
            text: text,
            language: decoded.language,
            durationSeconds: decoded.duration
        )
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: OpenAICompatibleTranscriptionError.invalidResponse)
                    return
                }

                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private struct Response: Decodable {
        var text: String
        var language: String?
        var duration: Double?
    }
}
