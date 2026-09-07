import Foundation
import VoiceInkNVIDIA

public protocol VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String
}

public struct VoiceInkUnsupportedAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    public init() {}

    public func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        throw VoiceInkCloudTranscriptionError.unsupportedProvider
    }
}

public enum VoiceInkCloudTranscriptionError: Error, LocalizedError {
    public static let apiStatusCodeRange: ClosedRange<Int> = 100...599

    case unsupportedProvider
    case missingAPIKey
    case audioFileNotFound
    case invalidAudioFormat(String)
    case unsupportedOperatingSystem(String)
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .invalidAudioFormat(let message), .unsupportedOperatingSystem(let message):
            return message
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        }
    }

    public static func apiRequestFailure(
        from error: NSError,
        matchingErrorDomain errorDomain: String?
    ) -> VoiceInkCloudTranscriptionError? {
        guard let errorDomain,
              error.domain == errorDomain,
              apiStatusCodeRange.contains(error.code) else {
            return nil
        }

        return .apiRequestFailed(
            statusCode: error.code,
            message: apiRequestFailureMessage(from: error)
        )
    }

    public static func apiRequestFailureMessage(from error: NSError) -> String {
        error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
    }

    public static func remoteExecutionFailure(
        from error: Error,
        matchingErrorDomain errorDomain: String?
    ) -> VoiceInkCloudTranscriptionError {
        if let cloudError = error as? VoiceInkCloudTranscriptionError {
            return cloudError
        }

        if let apiError = apiRequestFailure(
            from: error as NSError,
            matchingErrorDomain: errorDomain
        ) {
            return apiError
        }

        return .networkError(error)
    }
}

public struct VoiceInkCloudTranscriptionAudioFile: Equatable, Sendable {
    public let data: Data
    public let fileName: String

    public init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
    }

    public static func load(from url: URL) throws -> VoiceInkCloudTranscriptionAudioFile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceInkCloudTranscriptionError.audioFileNotFound
        }

        return VoiceInkCloudTranscriptionAudioFile(
            data: try Data(contentsOf: url),
            fileName: url.lastPathComponent
        )
    }
}

public struct VoiceInkAudioTranscriptionServiceFactory {
    public typealias RemoteServiceFactory = (VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService
    public typealias LocalWhisperServiceFactory = () -> any VoiceInkAudioTranscriptionService
    public typealias LocalFluidAudioServiceFactory = () -> any VoiceInkAudioTranscriptionService
    public typealias NativeAppleServiceFactory = () -> any VoiceInkAudioTranscriptionService
    public typealias CustomCloudServiceFactory = () -> any VoiceInkAudioTranscriptionService

    private let remoteServiceFactory: RemoteServiceFactory
    private let localWhisperServiceFactory: LocalWhisperServiceFactory
    private let localFluidAudioServiceFactory: LocalFluidAudioServiceFactory
    private let nativeAppleServiceFactory: NativeAppleServiceFactory
    private let customCloudServiceFactory: CustomCloudServiceFactory

    public init(
        localWhisperServiceFactory: @escaping LocalWhisperServiceFactory,
        localFluidAudioServiceFactory: @escaping LocalFluidAudioServiceFactory = {
            VoiceInkUnsupportedAudioTranscriptionService()
        },
        nativeAppleServiceFactory: @escaping NativeAppleServiceFactory = {
            VoiceInkUnsupportedAudioTranscriptionService()
        },
        customCloudServiceFactory: @escaping CustomCloudServiceFactory = {
            VoiceInkUnsupportedAudioTranscriptionService()
        },
        remoteServiceFactory: @escaping RemoteServiceFactory = { VoiceInkRemoteTranscriptionService(provider: $0) }
    ) {
        self.localWhisperServiceFactory = localWhisperServiceFactory
        self.localFluidAudioServiceFactory = localFluidAudioServiceFactory
        self.nativeAppleServiceFactory = nativeAppleServiceFactory
        self.customCloudServiceFactory = customCloudServiceFactory
        self.remoteServiceFactory = remoteServiceFactory
    }

    public func service(for provider: VoiceInkProviderKind) -> any VoiceInkAudioTranscriptionService {
        switch provider.transcriptionServiceKind {
        case .remote:
            return remoteServiceFactory(provider)
        case .streamingOnly:
            return VoiceInkUnsupportedAudioTranscriptionService()
        case .customCloud:
            return customCloudServiceFactory()
        case .localWhisper:
            return localWhisperServiceFactory()
        case .localFluidAudio:
            return localFluidAudioServiceFactory()
        case .nativeApple:
            return nativeAppleServiceFactory()
        }
    }
}

public struct VoiceInkRemoteTranscriptionOptions: Equatable, Sendable {
    public static var defaultOpenAICompatibleErrorDomain: String {
        guard let apiErrorDomain = VoiceInkTranscriptionModelProvider.groq.apiErrorDomain else {
            preconditionFailure("Groq provider metadata must define an API error domain")
        }
        return apiErrorDomain
    }

    public let prompt: String?
    public let customVocabulary: [String]
    public let openAICompatibleResponseFormat: String?
    public let openAICompatibleTemperature: String?
    public let openAICompatibleErrorDomain: String
    public let openAICompatibleTimeout: TimeInterval?
    public let openAICompatibleMaxRetries: Int
    public let openAICompatibleAllowsPlainTextFallback: Bool
    public let deepgramParagraphs: Bool?
    public let deepgramDiarize: Bool?
    public let deepgramTimeout: TimeInterval?

    public init(
        prompt: String? = nil,
        customVocabulary: [String] = [],
        openAICompatibleResponseFormat: String? = nil,
        openAICompatibleTemperature: String? = nil,
        openAICompatibleErrorDomain: String = VoiceInkRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain,
        openAICompatibleTimeout: TimeInterval? = nil,
        openAICompatibleMaxRetries: Int = 0,
        openAICompatibleAllowsPlainTextFallback: Bool = true,
        deepgramParagraphs: Bool? = nil,
        deepgramDiarize: Bool? = false,
        deepgramTimeout: TimeInterval? = nil
    ) {
        self.prompt = prompt
        self.customVocabulary = customVocabulary
        self.openAICompatibleResponseFormat = openAICompatibleResponseFormat
        self.openAICompatibleTemperature = openAICompatibleTemperature
        self.openAICompatibleErrorDomain = openAICompatibleErrorDomain
        self.openAICompatibleTimeout = openAICompatibleTimeout
        self.openAICompatibleMaxRetries = openAICompatibleMaxRetries
        self.openAICompatibleAllowsPlainTextFallback = openAICompatibleAllowsPlainTextFallback
        self.deepgramParagraphs = deepgramParagraphs
        self.deepgramDiarize = deepgramDiarize
        self.deepgramTimeout = deepgramTimeout
    }

    public static func batchDefaults(
        for provider: VoiceInkTranscriptionModelProvider,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = provider.providerKind.map {
            VoiceInkTranscriptionPromptUse.recordedFileTranscription($0).requestPrompt(prompt)
        } ?? nil
        let normalizedCustomVocabulary = provider.providerKind.map {
            VoiceInkCustomVocabularyTerms.normalized(customVocabulary, for: .batchTranscription($0))
        } ?? []

        switch provider {
        case .groq:
            return Self(
                prompt: requestPrompt,
                openAICompatibleResponseFormat: "json",
                openAICompatibleTemperature: "0",
                openAICompatibleErrorDomain: Self.defaultOpenAICompatibleErrorDomain,
                openAICompatibleTimeout: 60,
                openAICompatibleMaxRetries: 2
            )
        case .openAI:
            return Self(prompt: requestPrompt)
        case .deepgram:
            return Self(
                deepgramParagraphs: true,
                deepgramDiarize: nil,
                deepgramTimeout: 30
            )
        case .soniox, .speechmatics:
            return Self(customVocabulary: normalizedCustomVocabulary)
        case .assemblyAI:
            return Self(
                prompt: requestPrompt,
                customVocabulary: normalizedCustomVocabulary
            )
        case .cartesia, .elevenLabs, .gemini, .mistral, .xai, .nvidia, .local, .nativeApple:
            return Self()
        }
    }

    public static func batchDefaults(
        forProviderKind provider: VoiceInkProviderKind,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) -> Self {
        let requestPrompt = VoiceInkTranscriptionPromptUse.recordedFileTranscription(provider).requestPrompt(prompt)
        guard let modelProvider = provider.transcriptionModelProvider else {
            return requestPrompt.map { Self(prompt: $0) } ?? Self()
        }

        return batchDefaults(
            for: modelProvider,
            prompt: requestPrompt,
            customVocabulary: customVocabulary
        )
    }
}

public enum VoiceInkMacOSCloudTranscriptionPolicy {
    typealias TranscriptionTransport = @Sendable (VoiceInkMacOSCloudTranscriptionRequest) async throws -> String

    public static func transcribeAudioData(
        modelProvider: VoiceInkMacOSTranscriptionModelProvider,
        apiKey: String?,
        modelName: String,
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        try await transcribeAudioData(
            modelProvider: modelProvider,
            apiKey: apiKey,
            modelName: modelName,
            audioData: audioData,
            fileName: fileName,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary
        ) { request in
            try await VoiceInkRemoteTranscriptionService(provider: request.provider).transcribeAudioData(
                apiKey: request.apiKey,
                model: request.modelName,
                audioData: request.audioData,
                fileName: request.fileName,
                language: request.language,
                options: request.options
            )
        }
    }

    static func transcribeAudioData(
        modelProvider: VoiceInkMacOSTranscriptionModelProvider,
        apiKey: String?,
        modelName: String,
        audioData: Data,
        fileName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        transport: TranscriptionTransport
    ) async throws -> String {
        guard let usableAPIKey = VoiceInkProviderCredential.nonBlank(apiKey) else {
            throw VoiceInkCloudTranscriptionError.missingAPIKey
        }

        guard let provider = modelProvider.remoteTranscriptionProviderKind else {
            throw VoiceInkCloudTranscriptionError.unsupportedProvider
        }

        let request = VoiceInkMacOSCloudTranscriptionRequest(
            provider: provider,
            apiKey: usableAPIKey,
            modelName: modelName,
            audioData: audioData,
            fileName: fileName,
            language: language,
            options: modelProvider.remoteTranscriptionOptions(
                prompt: prompt,
                customVocabulary: customVocabulary
            )
        )

        do {
            let text = try await transport(request)
            guard modelProvider.acceptsRemoteTranscriptionText(text) else {
                throw VoiceInkCloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch {
            throw VoiceInkCloudTranscriptionError.remoteExecutionFailure(
                from: error,
                matchingErrorDomain: modelProvider.apiErrorDomain
            )
        }
    }
}

struct VoiceInkMacOSCloudTranscriptionRequest: Equatable, Sendable {
    let provider: VoiceInkProviderKind
    let apiKey: String
    let modelName: String
    let audioData: Data
    let fileName: String
    let language: String?
    let options: VoiceInkRemoteTranscriptionOptions
}

public struct VoiceInkOpenAICompatibleTranscriptionResponse: Decodable, Equatable, Sendable {
    public let text: String?
    public let language: String?
    public let duration: Double?

    public init(text: String?, language: String? = nil, duration: Double? = nil) {
        self.text = text
        self.language = language
        self.duration = duration
    }
}

public enum VoiceInkOpenAICompatibleTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> Data {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model", value: model)
        if let responseFormat, !responseFormat.isEmpty {
            form.addField(name: "response_format", value: responseFormat)
        }
        if let temperature, !temperature.isEmpty {
            form.addField(name: "temperature", value: temperature)
        }
        if let language, !language.isEmpty {
            form.addField(name: "language", value: language)
        }
        if let prompt, !prompt.isEmpty {
            form.addField(name: "prompt", value: prompt)
        }

        return form.data
    }

    public static func textIfPresent(from data: Data) throws -> String? {
        try JSONDecoder()
            .decode(VoiceInkOpenAICompatibleTranscriptionResponse.self, from: data)
            .text
    }

    static func transcriptionText(from data: Data, allowPlainTextFallback: Bool) -> String {
        if let text = try? textIfPresent(from: data) {
            return text
        }
        guard allowPlainTextFallback else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct VoiceInkOpenAICompatibleTranscriptionClient: Sendable {
    private let modelsClient: VoiceInkOpenAICompatibleClient

    public init(modelsClient: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient()) {
        self.modelsClient = modelsClient
    }

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        return try await transcribeAudioData(
            url: VoiceInkProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature,
            errorDomain: errorDomain,
            timeout: timeout,
            maxRetries: maxRetries,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func transcribeAudioData(
        url: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil,
        errorDomain: String = "OpenAICompatibleTranscriptionAPI",
        timeout: TimeInterval? = nil,
        maxRetries: Int = 0,
        allowPlainTextFallback: Bool = true
    ) async throws -> String {
        let preparedRequest = VoiceInkOpenAICompatibleTranscriptionRequestBuilder.make(
            url: url,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: preparedRequest.requestWithHTTPBody(),
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return VoiceInkOpenAICompatibleTranscriptionCodec.transcriptionText(
            from: data,
            allowPlainTextFallback: allowPlainTextFallback
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await modelsClient.verifyAPIKey(baseURL: baseURL, apiKey: apiKey)
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await modelsClient.verifyAPIKeyDetailed(
            baseURL: baseURL,
            apiKey: apiKey,
            timeout: timeout
        )
    }
}

public struct VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }

    public func requestWithHTTPBody() -> URLRequest {
        var copy = request
        copy.httpBody = body
        return copy
    }
}

public enum VoiceInkOpenAICompatibleTranscriptionRequestBuilder {
    public static func make(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
        make(
            url: VoiceInkProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: baseURL),
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }

    public static func make(
        url: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: String? = nil,
        temperature: String? = nil
    ) -> VoiceInkPreparedOpenAICompatibleTranscriptionRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            VoiceInkOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = VoiceInkOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary,
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )

        return VoiceInkPreparedOpenAICompatibleTranscriptionRequest(request: request, body: body)
    }
}

public enum VoiceInkDeepgramTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(DeepgramTranscriptionResponse.self, from: data)
        return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
    }
}

public enum VoiceInkDeepgramRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        smartFormat: Bool = true,
        punctuate: Bool = true,
        paragraphs: Bool? = nil,
        diarize: Bool? = false,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: smartFormat ? "true" : "false"),
            URLQueryItem(name: "punctuate", value: punctuate ? "true" : "false")
        ]

        if let paragraphs {
            queryItems.append(URLQueryItem(name: "paragraphs", value: paragraphs ? "true" : "false"))
        }

        if let diarize {
            queryItems.append(URLQueryItem(name: "diarize", value: diarize ? "true" : "false"))
        }

        if let language, !language.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }

        for term in customVocabulary where !term.isEmpty {
            queryItems.append(URLQueryItem(name: "keyterm", value: term))
        }

        var components = URLComponents(
            url: VoiceInkProviderEndpoint.deepgramListenURL(from: baseURL),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems

        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeProjectsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.deepgramProjectsURL(from: baseURL))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkDeepgramTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        smartFormat: Bool = true,
        punctuate: Bool = true,
        paragraphs: Bool? = nil,
        diarize: Bool? = false,
        customVocabulary: [String] = [],
        errorDomain: String = VoiceInkTranscriptionModelProvider.deepgram.requiredAPIErrorDomain,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            language: language,
            smartFormat: smartFormat,
            punctuate: punctuate,
            paragraphs: paragraphs,
            diarize: diarize,
            customVocabulary: customVocabulary,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: errorDomain
        )

        return try VoiceInkDeepgramTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkDeepgramRequestBuilder.makeProjectsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct DeepgramTranscriptionResponse: Decodable {
    let results: DeepgramResults
}

private struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

private struct DeepgramAlternative: Decodable {
    let transcript: String
}

public enum VoiceInkGeminiTranscriptionCodec {
    public static let defaultPrompt = "Please transcribe this audio file. Provide only the transcribed text."

    public static func requestBody(
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = defaultPrompt
    ) throws -> Data {
        try JSONEncoder().encode(
            VoiceInkGeminiTranscriptionRequest(
                contents: [
                    VoiceInkGeminiContent(parts: [
                        VoiceInkGeminiPart(text: prompt, inlineData: nil),
                        VoiceInkGeminiPart(
                            text: nil,
                            inlineData: VoiceInkGeminiInlineData(
                                mimeType: mimeType,
                                data: audioData.base64EncodedString()
                            )
                        )
                    ])
                ]
            )
        )
    }

    public static func transcript(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(VoiceInkGeminiTranscriptionResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public enum VoiceInkGeminiRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = VoiceInkGeminiTranscriptionCodec.defaultPrompt,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.geminiGenerateContentURL(from: baseURL, model: model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try VoiceInkGeminiTranscriptionCodec.requestBody(
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt
        )
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.geminiModelsURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkGeminiTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        mimeType: String = "audio/wav",
        prompt: String = VoiceInkGeminiTranscriptionCodec.defaultPrompt,
        errorDomain: String = VoiceInkTranscriptionModelProvider.gemini.requiredAPIErrorDomain,
        timeout: TimeInterval? = 60
    ) async throws -> String {
        let request = try VoiceInkGeminiRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            mimeType: mimeType,
            prompt: prompt,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: nil,
            maxRetries: 0,
            errorDomain: errorDomain
        )

        return try VoiceInkGeminiTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkGeminiRequestBuilder.makeModelsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkGeminiTranscriptionRequest: Encodable {
    let contents: [VoiceInkGeminiContent]
}

private struct VoiceInkGeminiContent: Encodable {
    let parts: [VoiceInkGeminiPart]
}

private struct VoiceInkGeminiPart: Encodable {
    let text: String?
    let inlineData: VoiceInkGeminiInlineData?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let inlineData {
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }
}

private struct VoiceInkGeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct VoiceInkGeminiTranscriptionResponse: Decodable {
    let candidates: [VoiceInkGeminiCandidate]
}

private struct VoiceInkGeminiCandidate: Decodable {
    let content: VoiceInkGeminiResponseContent
}

private struct VoiceInkGeminiResponseContent: Decodable {
    let parts: [VoiceInkGeminiResponsePart]
}

private struct VoiceInkGeminiResponsePart: Decodable {
    let text: String
}

public struct VoiceInkPreparedMistralTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkMistralTranscriptionCodec {
    public static func multipartContentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public static func requestBody(
        audioData: Data,
        fileName: String,
        model: String,
        boundary: String
    ) -> Data {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addField(name: "model", value: model)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        return form.data
    }

    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkMistralTranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkMistralRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedMistralTranscriptionRequest {
        let body = VoiceInkMistralTranscriptionCodec.requestBody(
            audioData: audioData,
            fileName: fileName,
            model: model,
            boundary: boundary
        )

        var request = URLRequest(url: VoiceInkProviderEndpoint.mistralAudioTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(
            VoiceInkMistralTranscriptionCodec.multipartContentType(boundary: boundary),
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedMistralTranscriptionRequest(request: request, body: body)
    }

    public static func makeModelsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.mistralModelsURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkMistralTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        errorDomain: String = VoiceInkTranscriptionModelProvider.mistral.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkMistralRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkMistralTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkMistralRequestBuilder.makeModelsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkMistralTranscriptionResponse: Decodable {
    let text: String
}

public struct VoiceInkPreparedElevenLabsTranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkElevenLabsTranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkElevenLabsTranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkElevenLabsRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedElevenLabsTranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)
        form.addField(name: "model_id", value: model)
        form.addField(name: "temperature", value: "0.0")
        form.addField(name: "tag_audio_events", value: "false")
        if let language, !language.isEmpty {
            form.addField(name: "language_code", value: language)
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedElevenLabsTranscriptionRequest(request: request, body: form.data)
    }

    public static func makeUserRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.elevenLabsUserURL(from: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkElevenLabsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        errorDomain: String = VoiceInkTranscriptionModelProvider.elevenLabs.requiredAPIErrorDomain,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkElevenLabsRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            fileName: fileName,
            language: language,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkElevenLabsTranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkElevenLabsRequestBuilder.makeUserRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkElevenLabsTranscriptionResponse: Decodable {
    let text: String
}

public struct VoiceInkPreparedXAITranscriptionRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkXAITranscriptionCodec {
    public static func transcript(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkXAITranscriptionResponse.self, from: data).text
    }
}

public enum VoiceInkXAIRequestBuilder {
    public static func makeTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        format: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedXAITranscriptionRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        if let language, !language.isEmpty, language != "auto" {
            form.addField(name: "language", value: language)
            if format {
                form.addField(name: "format", value: "true")
            }
        }
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiSpeechToTextURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedXAITranscriptionRequest(request: request, body: form.data)
    }

    public static func makeAPIKeyRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.xaiAPIKeyURL(from: baseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

public struct VoiceInkXAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        format: Bool = false,
        errorDomain: String = VoiceInkTranscriptionModelProvider.xai.requiredAPIErrorDomain,
        timeout: TimeInterval = 60,
        maxRetries: Int = 2
    ) async throws -> String {
        let preparedRequest = VoiceInkXAIRequestBuilder.makeTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            format: format,
            timeout: timeout
        )

        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )

        return try VoiceInkXAITranscriptionCodec.transcript(from: data)
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkXAIRequestBuilder.makeAPIKeyRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }
}

private struct VoiceInkXAITranscriptionResponse: Decodable {
    let text: String
}

public struct VoiceInkSonioxTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        errorDomain: String = VoiceInkTranscriptionModelProvider.soniox.requiredAPIErrorDomain
    ) async throws -> String {
        let fileID = try await uploadFile(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout,
            errorDomain: errorDomain
        )
        let transcriptionID = try await createTranscription(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout,
            errorDomain: errorDomain
        )
        try await pollTranscriptionStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptionID,
            timeout: timeout,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkSonioxRequestBuilder.makeFilesRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadFile(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = VoiceInkSonioxRequestBuilder.makeUploadFileRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try VoiceInkSonioxTranscriptionCodec.uploadedFileID(from: data)
    }

    private func createTranscription(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let request = try VoiceInkSonioxRequestBuilder.makeCreateTranscriptionRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            fileID: fileID,
            model: model,
            language: language,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return try VoiceInkSonioxTranscriptionCodec.createdTranscriptionID(from: data)
    }

    private func pollTranscriptionStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkSonioxRequestBuilder.makeTranscriptionStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? VoiceInkSonioxTranscriptionCodec.status(from: data).lowercased() {
                switch status {
                case "completed":
                    return .finished(())
                case "failed":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Soniox transcription job failed."]
                    )
                default:
                    break
                }
            }

            return .keepPolling
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        let request = VoiceInkSonioxRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: 2,
            errorDomain: errorDomain
        )
        return VoiceInkSonioxTranscriptionCodec.transcript(from: data)
    }
}

public struct VoiceInkPreparedSonioxUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkSonioxTranscriptionCodec {
    public static func uploadedFileID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxIDResponse.self, from: data).id
    }

    public static func createdTranscriptionID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxIDResponse.self, from: data).id
    }

    public static func status(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSonioxStatusResponse.self, from: data).status
    }

    public static func transcript(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(VoiceInkSonioxTranscriptResponse.self, from: data) {
            return decoded.text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum VoiceInkSonioxRequestBuilder {
    public static func makeUploadFileRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedSonioxUploadRequest {
        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addFile(name: "file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedSonioxUploadRequest(request: request, body: form.data)
    }

    public static func makeCreateTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        fileID: String,
        model: String,
        language: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var payload: [String: Any] = [
            "file_id": fileID,
            "model": model,
            "enable_speaker_diarization": false
        ]

        if !customVocabulary.isEmpty {
            payload["context"] = ["terms": customVocabulary]
        }

        if let language, !language.isEmpty {
            payload["language_hints"] = [language]
            payload["language_hints_strict"] = true
            payload["enable_language_identification"] = true
        } else {
            payload["enable_language_identification"] = true
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptionsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptionStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptionURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeFilesRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.sonioxFilesURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private struct VoiceInkSonioxIDResponse: Decodable {
    let id: String
}

private struct VoiceInkSonioxStatusResponse: Decodable {
    let status: String
}

private struct VoiceInkSonioxTranscriptResponse: Decodable {
    let text: String
}

public struct VoiceInkSpeechmaticsTranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String = "audio.wav",
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = VoiceInkTranscriptionModelProvider.speechmatics.requiredAPIErrorDomain
    ) async throws -> String {
        let jobID = try await submitJob(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        try await pollJobStatus(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
        return try await fetchTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: jobID,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkSpeechmaticsRequestBuilder.makeJobsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func submitJob(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String?,
        operatingPoint: String,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = try VoiceInkSpeechmaticsRequestBuilder.makeSubmitJobRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            fileName: fileName,
            language: language,
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkSpeechmaticsTranscriptionCodec.submittedJobID(from: data)
    }

    private func pollJobStatus(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkSpeechmaticsRequestBuilder.makeJobStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            if let status = try? VoiceInkSpeechmaticsTranscriptionCodec.jobStatus(from: data).lowercased() {
                switch status {
                case "done":
                    return .finished(())
                case "rejected":
                    throw NSError(
                        domain: errorDomain,
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was rejected."]
                    )
                case "deleted":
                    throw NSError(
                        domain: errorDomain,
                        code: 410,
                        userInfo: [NSLocalizedDescriptionKey: "Speechmatics transcription job was deleted."]
                    )
                default:
                    break
                }
            }

            return .keepPolling
        }
    }

    private func fetchTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = VoiceInkSpeechmaticsRequestBuilder.makeTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            id: id,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return VoiceInkSpeechmaticsTranscriptionCodec.transcript(from: data)
    }
}

public struct VoiceInkPreparedSpeechmaticsUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public enum VoiceInkSpeechmaticsTranscriptionCodec {
    public static func submittedJobID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSpeechmaticsSubmitJobResponse.self, from: data).id
    }

    public static func jobStatus(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkSpeechmaticsJobStatusResponse.self, from: data).job.status
    }

    public static func transcript(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    public static func speechmaticsLanguage(from language: String?) -> String {
        guard let language, !language.isEmpty, language != "auto" else { return "auto" }
        switch language {
        case "zh":
            return "cmn"
        default:
            return language
        }
    }
}

public enum VoiceInkSpeechmaticsRequestBuilder {
    public static func makeSubmitJobRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        operatingPoint: String = "enhanced",
        customVocabulary: [String] = [],
        boundary: String = "Boundary-\(UUID().uuidString)",
        timeout: TimeInterval? = nil
    ) throws -> VoiceInkPreparedSpeechmaticsUploadRequest {
        let config = VoiceInkSpeechmaticsSubmitJobConfig.make(
            language: VoiceInkSpeechmaticsTranscriptionCodec.speechmaticsLanguage(from: language),
            operatingPoint: operatingPoint,
            customVocabulary: customVocabulary
        )
        let configData = try JSONSerialization.data(withJSONObject: config)
        guard let configString = String(data: configData, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        var form = VoiceInkMultipartFormData(boundary: boundary)
        form.addField(name: "config", value: configString)
        form.addFile(name: "data_file", fileName: fileName, mimeType: "audio/wav", fileData: audioData)

        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedSpeechmaticsUploadRequest(request: request, body: form.data)
    }

    public static func makeJobStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsTranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeJobsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.speechmaticsJobsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}

private enum VoiceInkSpeechmaticsSubmitJobConfig {
    static func make(
        language: String,
        operatingPoint: String,
        customVocabulary: [String]
    ) -> [String: Any] {
        var transcriptionConfig: [String: Any] = [
            "language": language,
            "operating_point": operatingPoint
        ]
        if !customVocabulary.isEmpty {
            transcriptionConfig["additional_vocab"] = customVocabulary.map { ["content": $0] }
        }
        return [
            "type": "transcription",
            "transcription_config": transcriptionConfig
        ]
    }
}

private struct VoiceInkSpeechmaticsSubmitJobResponse: Decodable {
    let id: String
}

private struct VoiceInkSpeechmaticsJobStatusResponse: Decodable {
    let job: Job

    struct Job: Decodable {
        let status: String
    }
}

public struct VoiceInkAssemblyAITranscriptionClient: Sendable {
    public init() {}

    public func transcribeAudioData(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        maxWaitSeconds: TimeInterval = 300,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        errorDomain: String = VoiceInkTranscriptionModelProvider.assemblyAI.requiredAPIErrorDomain
    ) async throws -> String {
        let uploadURL = try await uploadAudio(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        let transcriptID = try await createTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: uploadURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try await pollTranscript(
            baseURL: baseURL,
            apiKey: apiKey,
            id: transcriptID,
            maxWaitSeconds: maxWaitSeconds,
            timeout: timeout,
            errorDomain: errorDomain
        )
    }

    public func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        await verifyAPIKeyDetailed(baseURL: baseURL, apiKey: apiKey).isValid
    }

    public func verifyAPIKeyDetailed(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval = 10
    ) async -> VoiceInkAPIKeyVerificationResult {
        await VoiceInkAPIKeyVerificationPolicy.verify(
            apiKey: apiKey,
            request: VoiceInkAssemblyAIRequestBuilder.makeTranscriptsRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: timeout
            )
        )
    }

    private func uploadAudio(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let preparedRequest = VoiceInkAssemblyAIRequestBuilder.makeUploadAudioRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioData: audioData,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedUpload(
            request: preparedRequest.request,
            body: preparedRequest.body,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkAssemblyAITranscriptionCodec.uploadedAudioURL(from: data)
    }

    private func createTranscript(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String],
        timeout: TimeInterval,
        maxRetries: Int,
        errorDomain: String
    ) async throws -> String {
        let request = try VoiceInkAssemblyAIRequestBuilder.makeCreateTranscriptRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary,
            timeout: timeout
        )
        let data = try await VoiceInkRetriedRequest.validatedData(
            for: request,
            timeout: timeout,
            maxRetries: maxRetries,
            errorDomain: errorDomain
        )
        return try VoiceInkAssemblyAITranscriptionCodec.createdTranscriptID(from: data)
    }

    private func pollTranscript(
        baseURL: URL,
        apiKey: String,
        id: String,
        maxWaitSeconds: TimeInterval,
        timeout: TimeInterval,
        errorDomain: String
    ) async throws -> String {
        try await VoiceInkRemotePollingPolicy.pollValidatedData(
            request: {
                VoiceInkAssemblyAIRequestBuilder.makeTranscriptStatusRequest(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    id: id,
                    timeout: timeout
                )
            },
            errorDomain: errorDomain,
            maxWaitSeconds: maxWaitSeconds
        ) { data in
            let transcript = try VoiceInkAssemblyAITranscriptionCodec.transcriptStatus(from: data)
            switch transcript.status.lowercased() {
            case "completed":
                return .finished(transcript.text ?? "")
            case "error":
                throw NSError(
                    domain: errorDomain,
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: transcript.error ?? "AssemblyAI transcription failed."]
                )
            default:
                return .keepPolling
            }
        }
    }
}

public struct VoiceInkPreparedAssemblyAIUploadRequest {
    public let request: URLRequest
    public let body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

public struct VoiceInkAssemblyAITranscriptStatus: Equatable, Sendable {
    public let status: String
    public let text: String?
    public let error: String?

    public init(status: String, text: String?, error: String?) {
        self.status = status
        self.text = text
        self.error = error
    }
}

public enum VoiceInkAssemblyAITranscriptionCodec {
    public static func uploadedAudioURL(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkAssemblyAIUploadResponse.self, from: data).uploadURL
    }

    public static func createdTranscriptID(from data: Data) throws -> String {
        try JSONDecoder().decode(VoiceInkAssemblyAITranscriptCreateResponse.self, from: data).id
    }

    public static func transcriptStatus(from data: Data) throws -> VoiceInkAssemblyAITranscriptStatus {
        let decoded = try JSONDecoder().decode(VoiceInkAssemblyAITranscriptStatusResponse.self, from: data)
        return VoiceInkAssemblyAITranscriptStatus(
            status: decoded.status,
            text: decoded.text,
            error: decoded.error
        )
    }
}

public enum VoiceInkAssemblyAIRequestBuilder {
    public static func makeUploadAudioRequest(
        baseURL: URL,
        apiKey: String,
        audioData: Data,
        timeout: TimeInterval? = nil
    ) -> VoiceInkPreparedAssemblyAIUploadRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAIUploadURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return VoiceInkPreparedAssemblyAIUploadRequest(request: request, body: audioData)
    }

    public static func makeCreateTranscriptRequest(
        baseURL: URL,
        apiKey: String,
        audioURL: String,
        model: String,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = [],
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        let speechModels = speechModels(for: model)
        let primarySpeechModel = speechModels.first ?? model
        var payload: [String: Any] = [
            "audio_url": audioURL,
            "speech_models": speechModels,
            "punctuate": true,
            "format_text": true
        ]

        if let language, !language.isEmpty, language != "auto" {
            payload["language_code"] = language
        } else {
            payload["language_detection"] = true
        }

        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyterms = normalizedKeyterms(customVocabulary, model: primarySpeechModel)
        if supportsPrompt(speechModels), !trimmedPrompt.isEmpty {
            payload["prompt"] = appendedKeyterms(keyterms, to: trimmedPrompt)
        } else if !keyterms.isEmpty {
            payload["keyterms_prompt"] = keyterms
        }

        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptStatusRequest(
        baseURL: URL,
        apiKey: String,
        id: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptURL(from: baseURL, id: id))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    public static func makeTranscriptsRequest(
        baseURL: URL,
        apiKey: String,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: baseURL))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    static func speechModels(for model: String) -> [String] {
        switch model {
        case "universal-3-pro":
            return ["universal-3-pro", "universal-2"]
        case "universal-2":
            return ["universal-2"]
        case "universal-streaming", "universal-streaming-english", "universal-streaming-multilingual", "whisper-rt":
            return ["universal-2"]
        default:
            return [model]
        }
    }

    static func supportsPrompt(_ speechModels: [String]) -> Bool {
        speechModels.contains("universal-3-pro")
    }

    static func normalizedKeyterms(_ terms: [String], model: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let limit = model == "universal-2" ? 200 : 1_000
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.split(separator: " ").count
            guard !trimmed.isEmpty, trimmed.count <= 50, wordCount <= 6 else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }

    static func appendedKeyterms(_ keyterms: [String], to prompt: String) -> String {
        guard !keyterms.isEmpty else { return prompt }
        return "\(prompt)\n\nBoost these terms when they appear in the audio: \(keyterms.joined(separator: ", "))."
    }
}

private struct VoiceInkAssemblyAIUploadResponse: Decodable {
    let uploadURL: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
    }
}

private struct VoiceInkAssemblyAITranscriptCreateResponse: Decodable {
    let id: String
}

private struct VoiceInkAssemblyAITranscriptStatusResponse: Decodable {
    let status: String
    let text: String?
    let error: String?
}

public struct VoiceInkRemoteTranscriptionService: VoiceInkAudioTranscriptionService, Sendable {
    private let provider: VoiceInkProviderKind?
    private let transport: VoiceInkTranscriptionTransport
    private let apiBaseURL: URL
    private let openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient
    private let deepgramClient: VoiceInkDeepgramTranscriptionClient
    private let geminiClient: VoiceInkGeminiTranscriptionClient
    private let mistralClient: VoiceInkMistralTranscriptionClient
    private let elevenLabsClient: VoiceInkElevenLabsTranscriptionClient
    private let sonioxClient: VoiceInkSonioxTranscriptionClient
    private let speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient
    private let assemblyAIClient: VoiceInkAssemblyAITranscriptionClient
    private let xaiClient: VoiceInkXAITranscriptionClient

    public init(
        provider: VoiceInkProviderKind,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.init(
            provider: provider,
            transport: provider.transcriptionTransport,
            apiBaseURL: provider.transcriptionAPIBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient,
            geminiClient: geminiClient,
            mistralClient: mistralClient,
            elevenLabsClient: elevenLabsClient,
            sonioxClient: sonioxClient,
            speechmaticsClient: speechmaticsClient,
            assemblyAIClient: assemblyAIClient,
            xaiClient: xaiClient
        )
    }

    public init(
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.init(
            provider: nil,
            transport: transport,
            apiBaseURL: apiBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient,
            geminiClient: geminiClient,
            mistralClient: mistralClient,
            elevenLabsClient: elevenLabsClient,
            sonioxClient: sonioxClient,
            speechmaticsClient: speechmaticsClient,
            assemblyAIClient: assemblyAIClient,
            xaiClient: xaiClient
        )
    }

    init(
        provider: VoiceInkProviderKind?,
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.provider = provider
        self.transport = transport
        self.apiBaseURL = apiBaseURL
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
        self.geminiClient = geminiClient
        self.mistralClient = mistralClient
        self.elevenLabsClient = elevenLabsClient
        self.sonioxClient = sonioxClient
        self.speechmaticsClient = speechmaticsClient
        self.assemblyAIClient = assemblyAIClient
        self.xaiClient = xaiClient
    }

    public func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        let audioFile = try VoiceInkCloudTranscriptionAudioFile.load(from: fileURL)
        return try await transcribeAudioData(
            apiKey: apiKey,
            model: model,
            audioData: audioFile.data,
            fileName: audioFile.fileName,
            language: language,
            options: fileTranscriptionOptions(
                prompt: prompt,
                customVocabulary: customVocabulary
            )
        )
    }

    func fileTranscriptionOptions(
        prompt: String?,
        customVocabulary: [String] = []
    ) -> VoiceInkRemoteTranscriptionOptions {
        guard let provider else {
            return VoiceInkRemoteTranscriptionOptions(
                prompt: VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt(prompt),
                customVocabulary: customVocabulary
            )
        }

        return VoiceInkRemoteTranscriptionOptions.batchDefaults(
            forProviderKind: provider,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    func providerAPIErrorDomain(defaultingTo defaultProvider: VoiceInkTranscriptionModelProvider) -> String {
        guard provider?.transcriptionTransport == transport,
              let providerErrorDomain = provider?.transcriptionModelProvider?.apiErrorDomain else {
            return defaultProvider.apiErrorDomain ?? VoiceInkRemoteTranscriptionOptions.defaultOpenAICompatibleErrorDomain
        }
        return providerErrorDomain
    }

    public func transcribeAudioData(
        apiKey: String,
        model: String,
        audioData: Data,
        fileName: String,
        language: String? = nil,
        options: VoiceInkRemoteTranscriptionOptions = VoiceInkRemoteTranscriptionOptions()
    ) async throws -> String {
        switch transport {
        case .nvidiaRiva:
            guard #available(macOS 15, iOS 18, *) else {
                throw VoiceInkCloudTranscriptionError.unsupportedOperatingSystem(NVIDIAParakeet.minimumOSMessage)
            }
            guard model == NVIDIAParakeet.modelName else {
                throw VoiceInkCloudTranscriptionError.unsupportedProvider
            }
            guard let pcmData = VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: audioData), !pcmData.isEmpty else {
                throw VoiceInkCloudTranscriptionError.invalidAudioFormat("NVIDIA requires nonempty 16 kHz mono PCM16 WAV audio.")
            }
            do {
                return try await NVIDIAParakeetClient.transcribe(pcm16Data: pcmData, apiKey: apiKey)
            } catch NVIDIAParakeetError.emptyTranscript {
                throw VoiceInkCloudTranscriptionError.noTranscriptionReturned
            }
        case .openAICompatible:
            return try await openAICompatibleClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: options.prompt,
                responseFormat: options.openAICompatibleResponseFormat,
                temperature: options.openAICompatibleTemperature,
                errorDomain: options.openAICompatibleErrorDomain,
                timeout: options.openAICompatibleTimeout,
                maxRetries: options.openAICompatibleMaxRetries,
                allowPlainTextFallback: options.openAICompatibleAllowsPlainTextFallback
            )
        case .deepgram:
            return try await deepgramClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language,
                paragraphs: options.deepgramParagraphs,
                diarize: options.deepgramDiarize,
                timeout: options.deepgramTimeout
            )
        case .geminiGenerateContent:
            return try await geminiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                timeout: 60
            )
        case .mistral:
            return try await mistralClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                errorDomain: providerAPIErrorDomain(defaultingTo: .mistral),
                timeout: 30,
                maxRetries: 2
            )
        case .elevenLabs:
            return try await elevenLabsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                timeout: 30,
                maxRetries: 2
            )
        case .soniox:
            return try await sonioxClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: options.customVocabulary
            )
        case .speechmatics:
            return try await speechmaticsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: options.customVocabulary
            )
        case .assemblyAI:
            return try await assemblyAIClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language,
                prompt: options.prompt,
                customVocabulary: options.customVocabulary,
                errorDomain: providerAPIErrorDomain(defaultingTo: .assemblyAI)
            )
        case .xai:
            return try await xaiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                format: true,
                errorDomain: providerAPIErrorDomain(defaultingTo: .xai),
                timeout: 60,
                maxRetries: 2
            )
        case .localWhisper, .localFluidAudio:
            throw URLError(.unsupportedURL)
        case .nativeApple:
            throw VoiceInkCloudTranscriptionError.unsupportedProvider
        }
    }

}
