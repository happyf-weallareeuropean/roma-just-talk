import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

public enum NVIDIAParakeetError: Error, LocalizedError {
    case missingAPIKey
    case invalidAudio
    case emptyTranscript
    case unavailableModel

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your NVIDIA API key to use this cloud model."
        case .invalidAudio: "NVIDIA requires nonempty 16 kHz mono PCM16 audio."
        case .emptyTranscript: "NVIDIA returned no transcription."
        case .unavailableModel: "The NVIDIA zh-TW speech service returned no model configuration."
        }
    }
}

@available(macOS 15, iOS 18, *)
public enum NVIDIAParakeetClient {
    public static func transcribe(pcm16Data: Data, apiKey: String) async throws -> String {
        let request = try recognitionRequest(pcm16Data: pcm16Data, apiKey: apiKey)
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
    }

    public static func verifyAPIKey(_ apiKey: String) async throws {
        let headers = try metadata(apiKey: apiKey)
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
