import CWindowsSupport
import Foundation

public enum WindowsDPAPISecretError: Error, LocalizedError, Equatable {
    case unsupported
    case invalidArgument
    case protectFailed(lastError: UInt32)
    case unprotectFailed(lastError: UInt32)
    case invalidUTF8
    case invalidKey

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Windows DPAPI is not available on this platform."
        case .invalidArgument:
            return "Windows DPAPI received an invalid argument."
        case .protectFailed(let lastError):
            return "CryptProtectData failed with GetLastError=\(lastError)."
        case .unprotectFailed(let lastError):
            return "CryptUnprotectData failed with GetLastError=\(lastError)."
        case .invalidUTF8:
            return "The decrypted secret was not valid UTF-8."
        case .invalidKey:
            return "Secret keys must not be empty."
        }
    }
}

public enum WindowsDPAPIProtectedData {
    public static var isRuntimeAvailable: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    public static func protect(_ data: Data) throws -> Data {
        try withDPAPIOutput(data, operation: roma_windows_dpapi_protect)
    }

    public static func unprotect(_ data: Data) throws -> Data {
        try withDPAPIOutput(data, operation: roma_windows_dpapi_unprotect)
    }

    private static func withDPAPIOutput(
        _ data: Data,
        operation: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?, UnsafeMutablePointer<UInt32>?) -> roma_windows_secret_status_t
    ) throws -> Data {
        try data.withUnsafeBytes { inputBuffer in
            guard let input = inputBuffer.bindMemory(to: UInt8.self).baseAddress, inputBuffer.count > 0 else {
                throw WindowsDPAPISecretError.invalidArgument
            }

            var output: UnsafeMutablePointer<UInt8>?
            var outputCount = 0
            var lastError: UInt32 = 0
            let status = operation(input, inputBuffer.count, &output, &outputCount, &lastError)
            defer { roma_windows_secret_free(output) }

            switch status {
            case ROMA_WINDOWS_SECRET_OK:
                guard let output else { throw WindowsDPAPISecretError.invalidArgument }
                return Data(bytes: output, count: outputCount)
            case ROMA_WINDOWS_SECRET_UNSUPPORTED:
                throw WindowsDPAPISecretError.unsupported
            case ROMA_WINDOWS_SECRET_INVALID_ARGUMENT:
                throw WindowsDPAPISecretError.invalidArgument
            case ROMA_WINDOWS_SECRET_PROTECT_FAILED:
                throw WindowsDPAPISecretError.protectFailed(lastError: lastError)
            case ROMA_WINDOWS_SECRET_UNPROTECT_FAILED:
                throw WindowsDPAPISecretError.unprotectFailed(lastError: lastError)
            default:
                throw WindowsDPAPISecretError.invalidArgument
            }
        }
    }
}

public final class WindowsDPAPISecretStore: SecretStoring, @unchecked Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL = WindowsDPAPISecretStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    public func save(_ value: String, forKey key: String) throws {
        let fileURL = try url(forKey: key)
        let protectedData = try WindowsDPAPIProtectedData.protect(Data(value.utf8))

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try protectedData.write(to: fileURL, options: [.atomic])
    }

    public func get(_ key: String) throws -> String? {
        let fileURL = try url(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let protectedData = try Data(contentsOf: fileURL)
        let unprotectedData = try WindowsDPAPIProtectedData.unprotect(protectedData)
        guard let value = String(data: unprotectedData, encoding: .utf8) else {
            throw WindowsDPAPISecretError.invalidUTF8
        }
        return value
    }

    public func delete(_ key: String) throws {
        let fileURL = try url(forKey: key)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public static func defaultDirectoryURL() -> URL {
        #if os(Windows)
        if let appData = ProcessInfo.processInfo.environment["APPDATA"], !appData.isEmpty {
            return URL(fileURLWithPath: appData)
                .appendingPathComponent("roma-just-talk", isDirectory: true)
                .appendingPathComponent("secrets", isDirectory: true)
        }
        #endif

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".roma-just-talk", isDirectory: true)
            .appendingPathComponent("secrets", isDirectory: true)
    }

    public static func fileName(forKey key: String) throws -> String {
        let keyData = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !keyData.isEmpty else {
            throw WindowsDPAPISecretError.invalidKey
        }

        return keyData.map { byte in
            String(format: "%02x", byte)
        }.joined() + ".dpapi"
    }

    private func url(forKey key: String) throws -> URL {
        try directoryURL.appendingPathComponent(Self.fileName(forKey: key), isDirectory: false)
    }
}
