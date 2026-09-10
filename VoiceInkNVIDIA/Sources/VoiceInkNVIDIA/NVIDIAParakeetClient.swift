import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

public enum NVIDIAParakeetError: Error, LocalizedError {
    case missingAPIKey
    case invalidAudio
    case emptyTranscript
    case unavailableModel
    case invalidAPIKey
    case accessDenied
    case requestTimedOut
    case serviceUnavailable
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your NVIDIA API key to use this cloud model."
        case .invalidAudio: "NVIDIA requires nonempty 16 kHz mono PCM16 audio."
        case .emptyTranscript: "NVIDIA returned no transcription."
        case .unavailableModel: "The NVIDIA zh-TW speech service returned no model configuration."
        case .invalidAPIKey: "NVIDIA rejected this API key. Check the key or create a new one, then try again."
        case .accessDenied: "This NVIDIA API key does not have access to the zh-TW speech service. Check its permissions in NVIDIA."
        case .requestTimedOut: "NVIDIA took too long to respond. Check your connection and try again."
        case .serviceUnavailable: "Could not reach NVIDIA's speech service. Check your connection and try again later."
        case .requestFailed: "NVIDIA could not complete the request. Try again later."
        }
    }
}

@available(macOS 15, iOS 18, *)
public enum NVIDIAParakeetClient {
    public static func transcribe(pcm16Data: Data, apiKey: String) async throws -> String {
        let request = try recognitionRequest(pcm16Data: pcm16Data, apiKey: apiKey)
        do {
            return try await withGRPCClient(
                transport: try .http2NIOTS(
                    target: .dns(host: NVIDIAParakeet.host, port: 443),
                    transportSecurity: .tls
                )
            ) { client in
                let service = Nvidia_Riva_Asr_RivaSpeechRecognition.Client(wrapping: client)
                let response = try await service.recognize(request: request, options: options(timeout: .seconds(60)))
                return try transcript(from: response)
            }
        } catch let error as RPCError {
            throw transportError(error)
        }
    }

    public static func verifyAPIKey(_ apiKey: String) async throws {
        let headers = try metadata(apiKey: apiKey)
        do {
            try await withGRPCClient(
                transport: try .http2NIOTS(
                    target: .dns(host: NVIDIAParakeet.host, port: 443),
                    transportSecurity: .tls
                )
            ) { client in
                let service = Nvidia_Riva_Asr_RivaSpeechRecognition.Client(wrapping: client)
                let response = try await service.getRivaSpeechRecognitionConfig(
                    request: ClientRequest(message: Nvidia_Riva_Asr_RivaSpeechRecognitionConfigRequest(), metadata: headers),
                    options: options(timeout: .seconds(15))
                )
                guard !response.modelConfig.isEmpty else { throw NVIDIAParakeetError.unavailableModel }
            }
        } catch let error as RPCError {
            throw transportError(error)
        }
    }

    static func transportError(_ error: RPCError) -> any Error {
        // RPCError's localizedDescription exposes a Swift domain, not its gRPC status.
        switch error.code {
        case .unauthenticated: NVIDIAParakeetError.invalidAPIKey
        case .permissionDenied: NVIDIAParakeetError.accessDenied
        case .deadlineExceeded: NVIDIAParakeetError.requestTimedOut
        case .unavailable: NVIDIAParakeetError.serviceUnavailable
        case .cancelled: CancellationError()
        default: NVIDIAParakeetError.requestFailed
        }
    }

    static func recognitionRequest(pcm16Data: Data, apiKey: String) throws -> ClientRequest<Nvidia_Riva_Asr_RecognizeRequest> {
        guard !pcm16Data.isEmpty, pcm16Data.count.isMultiple(of: 2) else {
            throw NVIDIAParakeetError.invalidAudio
        }
        var message = Nvidia_Riva_Asr_RecognizeRequest()
        message.config.encoding = .linearPcm
        message.config.sampleRateHertz = 16_000
        // The dedicated NVIDIA function selects the bilingual zh-TW model by language.
        message.config.languageCode = NVIDIAParakeet.languageCode
        message.config.audioChannelCount = 1
        message.config.maxAlternatives = 1
        message.config.enableAutomaticPunctuation = true
        message.audio = pcm16Data
        return ClientRequest(message: message, metadata: try metadata(apiKey: apiKey))
    }

    static func transcript(from response: Nvidia_Riva_Asr_RecognizeResponse) throws -> String {
        let text = response.results.compactMap { $0.alternatives.first?.transcript }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { throw NVIDIAParakeetError.emptyTranscript }
        return text
    }

    static func metadata(apiKey: String) throws -> Metadata {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.rangeOfCharacter(from: .newlines) == nil else {
            throw NVIDIAParakeetError.missingAPIKey
        }
        return ["authorization": "Bearer \(key)", "function-id": .string(NVIDIAParakeet.functionID)]
    }

    private static func options(timeout: Duration) -> CallOptions {
        var options = CallOptions.defaults
        options.timeout = timeout
        return options
    }
}
