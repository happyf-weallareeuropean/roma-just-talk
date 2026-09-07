import CryptoKit
import Foundation

public enum QwenRuntimeError: Error, LocalizedError {
    case notInstalled
    case busy
    case invalidFile(String)
    case invalidAudio
    case outputLimitReached
    case textConversionUnavailable

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "Download the bilingual model before using it offline."
        case .busy: "The bilingual model is finishing another operation."
        case .invalidFile(let name): "The bilingual model file \(name) failed verification. Download the model again."
        case .invalidAudio: "Audio must contain finite mono samples at 16 kHz."
        case .outputLimitReached: "This recording exceeded the bilingual model's output limit. Split the recording and retry."
        case .textConversionUnavailable: "Traditional Chinese text conversion is unavailable."
        }
    }
}

public struct QwenDownloadProgress: Sendable {
    public enum Phase: Sendable { case downloading, verifying, ready }
    public let phase: Phase
    public let fractionCompleted: Double
}

struct QwenSnapshot: Decodable, Sendable {
    struct File: Decodable, Sendable {
        let file: String
        let bytes: Int64
        let sha256: String

        func verifySize(at directory: URL) throws {
            let url = directory.appendingPathComponent(file)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  Int64(values.fileSize ?? -1) == bytes else {
                throw QwenRuntimeError.invalidFile(file)
            }
        }

        func verify(at directory: URL) throws {
            try Task.checkCancellation()
            try verifySize(at: directory)
            let url = directory.appendingPathComponent(file)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
                throw QwenRuntimeError.invalidFile(file)
            }
        }
    }

    let repo: String
    let revision: String
    let files: [File]
    let tokenizer: File

    static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Resources") else {
            throw QwenRuntimeError.invalidFile("snapshot.json")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func isPresent(at directory: URL) -> Bool {
        do {
            for file in files { try file.verifySize(at: directory) }
            try tokenizer.verifySize(at: directory)
            return true
        } catch { return false }
    }

    func verify(at directory: URL, includingTokenizer: Bool = true) throws {
        for file in files { try file.verify(at: directory) }
        if includingTokenizer { try tokenizer.verify(at: directory) }
        // The loader reads every safetensors file, so unlisted weights cannot be ignored.
        let allowed = Set(files.map(\.file))
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.pathExtension == "safetensors" && !allowed.contains(url.lastPathComponent) {
            throw QwenRuntimeError.invalidFile(url.lastPathComponent)
        }
    }

    func copyTokenizer(to directory: URL) throws {
        guard let resources = Bundle.module.resourceURL else {
            throw QwenRuntimeError.invalidFile(tokenizer.file)
        }
        let resourceDirectory = resources.appendingPathComponent("Resources")
        try tokenizer.verify(at: resourceDirectory)
        try FileManager.default.copyItem(
            at: resourceDirectory.appendingPathComponent(tokenizer.file),
            to: directory.appendingPathComponent(tokenizer.file)
        )
    }
}
