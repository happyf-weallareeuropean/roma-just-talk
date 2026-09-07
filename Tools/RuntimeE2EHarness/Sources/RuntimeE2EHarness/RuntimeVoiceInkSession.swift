import AppKit
import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import RuntimeE2ECore

struct RuntimeVoiceInkSessionInfo: Codable {
    let selectedAppPath: String
    let selectionSource: RuntimeVoiceInkSelection.Source
    let audioDeviceUID: String
    let originallyRunningPaths: [String]
}

private struct RuntimeVoiceInkRestorationJournal: Codable {
    let bundleIdentifier: String
    let originalAudioInputMode: String?
    let originalAudioInputModeExisted: Bool
    let originalSelectedDeviceUID: String?
    let originalSelectedDeviceUIDExisted: Bool
    let originalSystemMuteMode: String?
    // Older crash journals did not override recording mute.
    let originalSystemMuteModeExisted: Bool?
    let originallyRunningPaths: [String]
}

final class RuntimeVoiceInkSession {
    static let journalURL = URL(fileURLWithPath: "/tmp/roma-runtime-e2e-restoration.json")

    let info: RuntimeVoiceInkSessionInfo
    private let journal: RuntimeVoiceInkRestorationJournal
    private var restored = false

    private init(info: RuntimeVoiceInkSessionInfo, journal: RuntimeVoiceInkRestorationJournal) {
        self.info = info
        self.journal = journal
    }

    static func start(
        configuration: RuntimeHarnessConfiguration,
        audioDeviceUID: String
    ) throws -> RuntimeVoiceInkSession {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            try restoreFromJournal()
        }

        let resolution = try resolveApplication(configuration: configuration)
        let runningPaths = runningApplications(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            .compactMap { $0.bundleURL?.path }
            .sorted()
        let snapshot = try preferenceSnapshot(bundleIdentifier: configuration.voiceInkBundleIdentifier)
        let journal = RuntimeVoiceInkRestorationJournal(
            bundleIdentifier: configuration.voiceInkBundleIdentifier,
            originalAudioInputMode: snapshot.audioInputMode,
            originalAudioInputModeExisted: snapshot.audioInputModeExisted,
            originalSelectedDeviceUID: snapshot.selectedDeviceUID,
            originalSelectedDeviceUIDExisted: snapshot.selectedDeviceUIDExisted,
            originalSystemMuteMode: snapshot.systemMuteMode,
            originalSystemMuteModeExisted: snapshot.systemMuteModeExisted,
            originallyRunningPaths: runningPaths
        )
        try writeJournal(journal)

        do {
            try terminateRunningApplications(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            setPreference("Custom Device", key: "audioInputMode", bundleIdentifier: configuration.voiceInkBundleIdentifier)
            setPreference(audioDeviceUID, key: "selectedAudioDeviceUID", bundleIdentifier: configuration.voiceInkBundleIdentifier)
            // BlackHole is both speaker output and microphone input in this test.
            setPreference("never", key: "systemMuteMode", bundleIdentifier: configuration.voiceInkBundleIdentifier)
            try synchronize(bundleIdentifier: configuration.voiceInkBundleIdentifier)
            try launchApplication(
                atPath: resolution.path,
                bundleIdentifier: configuration.voiceInkBundleIdentifier
            )
        } catch {
            try? restoreFromJournal()
            throw error
        }

        return RuntimeVoiceInkSession(
            info: RuntimeVoiceInkSessionInfo(
                selectedAppPath: resolution.path,
                selectionSource: resolution.source,
                audioDeviceUID: audioDeviceUID,
                originallyRunningPaths: runningPaths
            ),
            journal: journal
        )
    }

    func restore() throws {
        guard !restored else { return }
        try Self.restore(journal: journal)
        restored = true
        try? FileManager.default.removeItem(at: Self.journalURL)
    }

    func relaunchForRun(bundleIdentifier: String) throws {
        try Self.terminateRunningApplications(bundleIdentifier: bundleIdentifier)
        try Self.launchApplication(atPath: info.selectedAppPath, bundleIdentifier: bundleIdentifier)
    }

    static func restoreFromJournal() throws {
        let data = try Data(contentsOf: journalURL)
        let journal = try JSONDecoder().decode(RuntimeVoiceInkRestorationJournal.self, from: data)
        try restore(journal: journal)
        try FileManager.default.removeItem(at: journalURL)
    }

    private static func restore(journal: RuntimeVoiceInkRestorationJournal) throws {
        try terminateRunningApplications(bundleIdentifier: journal.bundleIdentifier)
        restorePreference(
            journal.originalAudioInputMode,
            existed: journal.originalAudioInputModeExisted,
            key: "audioInputMode",
            bundleIdentifier: journal.bundleIdentifier
        )
        restorePreference(
            journal.originalSelectedDeviceUID,
            existed: journal.originalSelectedDeviceUIDExisted,
            key: "selectedAudioDeviceUID",
            bundleIdentifier: journal.bundleIdentifier
        )
        if let existed = journal.originalSystemMuteModeExisted {
            restorePreference(
                journal.originalSystemMuteMode,
                existed: existed,
                key: "systemMuteMode",
                bundleIdentifier: journal.bundleIdentifier
            )
        }
        try synchronize(bundleIdentifier: journal.bundleIdentifier)
        for path in journal.originallyRunningPaths {
            try launchApplication(atPath: path, bundleIdentifier: journal.bundleIdentifier)
        }
    }

    private static func resolveApplication(
        configuration: RuntimeHarnessConfiguration
    ) throws -> RuntimeVoiceInkSelection {
        let bundleIdentifier = configuration.voiceInkBundleIdentifier
        let runningPaths = runningApplications(bundleIdentifier: bundleIdentifier)
            .compactMap { $0.bundleURL?.path }
        let buildDirectoryPath = NSString(string: configuration.voiceInkBuildDirectory).expandingTildeInPath
        let buildDirectoryURL = URL(fileURLWithPath: buildDirectoryPath, isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        let buildCandidates = ((try? FileManager.default.contentsOfDirectory(
            at: buildDirectoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []).compactMap { url -> RuntimeVoiceInkCandidate? in
            guard url.pathExtension.lowercased() == "app",
                  Bundle(url: url)?.bundleIdentifier == bundleIdentifier,
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isDirectory == true else {
                return nil
            }
            return RuntimeVoiceInkCandidate(
                path: url.path,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        let workspacePath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?.path
        guard let selection = RuntimeVoiceInkCandidateSelector.select(
            explicitPath: configuration.voiceInkAppPath.map {
                NSString(string: $0).expandingTildeInPath
            },
            runningPaths: runningPaths,
            buildDirectoryPath: buildDirectoryPath,
            buildCandidates: buildCandidates,
            workspaceInstalledPath: workspacePath
        ) else {
            throw RuntimeVoiceInkSessionError.applicationNotFound(bundleIdentifier)
        }
        return selection
    }

    private static func preferenceSnapshot(
        bundleIdentifier: String
    ) throws -> (
        audioInputMode: String?,
        audioInputModeExisted: Bool,
        selectedDeviceUID: String?,
        selectedDeviceUIDExisted: Bool,
        systemMuteMode: String?,
        systemMuteModeExisted: Bool
    ) {
        let appID = bundleIdentifier as CFString
        let audioMode = CFPreferencesCopyAppValue("audioInputMode" as CFString, appID)
        let deviceUID = CFPreferencesCopyAppValue("selectedAudioDeviceUID" as CFString, appID)
        let systemMuteMode = CFPreferencesCopyAppValue("systemMuteMode" as CFString, appID)
        if let systemMuteMode {
            guard let mode = systemMuteMode as? String,
                  ["auto", "always", "never"].contains(mode) else {
                throw RuntimeVoiceInkSessionError.unsupportedSystemMuteMode
            }
        }
        return (
            audioMode as? String,
            audioMode != nil,
            deviceUID as? String,
            deviceUID != nil,
            systemMuteMode as? String,
            systemMuteMode != nil
        )
    }

    private static func setPreference(
        _ value: String,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            value as CFString,
            bundleIdentifier as CFString
        )
    }

    private static func restorePreference(
        _ value: String?,
        existed: Bool,
        key: String,
        bundleIdentifier: String
    ) {
        CFPreferencesSetAppValue(
            key as CFString,
            existed ? value as CFString? : nil,
            bundleIdentifier as CFString
        )
    }

    private static func synchronize(bundleIdentifier: String) throws {
        guard CFPreferencesAppSynchronize(bundleIdentifier as CFString) else {
            throw RuntimeVoiceInkSessionError.preferenceSynchronizationFailed
        }
    }

    private static func runningApplications(bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    private static func terminateRunningApplications(bundleIdentifier: String) throws {
        let applications = runningApplications(bundleIdentifier: bundleIdentifier)
        let processIdentifiers = applications.map(\.processIdentifier)
        var acceptedProcessIdentifiers: [pid_t] = []
        for application in applications {
            guard application.terminate() else {
                throw RuntimeVoiceInkSessionError.applicationWouldNotTerminate
            }
            acceptedProcessIdentifiers.append(application.processIdentifier)
        }
        try appendTerminationEvidence(processIdentifiers: acceptedProcessIdentifiers)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let capturedProcessesExited = processIdentifiers.allSatisfy {
                !processExists(processIdentifier: $0)
            }
            if capturedProcessesExited,
               runningApplications(bundleIdentifier: bundleIdentifier).isEmpty {
                return
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeVoiceInkSessionError.applicationWouldNotTerminate
    }

    private static func appendTerminationEvidence(processIdentifiers: [pid_t]) throws {
        guard let evidencePath = ProcessInfo.processInfo.environment[
            "RUNTIME_E2E_VOICEINK_TERMINATION_EVENTS"
        ], !evidencePath.isEmpty, !processIdentifiers.isEmpty else {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let lines = processIdentifiers.map { "\(timestamp)\t\($0)\n" }.joined()
        let evidenceURL = URL(fileURLWithPath: evidencePath)
        if !FileManager.default.fileExists(atPath: evidencePath) {
            try Data().write(to: evidenceURL, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: evidenceURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.utf8))
    }

    private static func processExists(processIdentifier: pid_t) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    private static func launchApplication(atPath path: String, bundleIdentifier: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-n", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeVoiceInkSessionError.launchFailed(path)
        }

        let sourceBundleURL = URL(fileURLWithPath: path).standardizedFileURL
        guard let sourceExecutableURL = Bundle(url: sourceBundleURL)?.executableURL else {
            throw RuntimeVoiceInkSessionError.launchIdentityUnavailable(path)
        }
        let sourceExecutableSHA256 = try sha256(path: sourceExecutableURL.path)
        let requireAppTranslocation = ProcessInfo.processInfo.environment[
            "RUNTIME_E2E_REQUIRE_APP_TRANSLOCATION"
        ] == "true"
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let launch = try runningApplications(bundleIdentifier: bundleIdentifier).compactMap({ application -> (
                application: NSRunningApplication,
                bundlePath: String,
                executableSHA256: String
            )? in
                guard let runningBundleURL = application.bundleURL?.standardizedFileURL,
                      Bundle(url: runningBundleURL)?.bundleIdentifier == bundleIdentifier,
                      let runningExecutableURL = Bundle(url: runningBundleURL)?.executableURL else {
                    return nil
                }
                let runningExecutableSHA256 = try sha256(path: runningExecutableURL.path)
                guard RuntimeVoiceInkLaunchIdentityPolicy.accepts(
                    sourceBundlePath: sourceBundleURL.path,
                    runningBundlePath: runningBundleURL.path,
                    sourceExecutableSHA256: sourceExecutableSHA256,
                    runningExecutableSHA256: runningExecutableSHA256,
                    requireAppTranslocation: requireAppTranslocation
                ) else {
                    return nil
                }
                return (application, runningBundleURL.path, runningExecutableSHA256)
            }).first {
                try appendLaunchEvidence(
                    processIdentifier: launch.application.processIdentifier,
                    sourceBundlePath: sourceBundleURL.path,
                    runningBundlePath: launch.bundlePath,
                    sourceExecutableSHA256: sourceExecutableSHA256,
                    runningExecutableSHA256: launch.executableSHA256
                )
                return
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        throw RuntimeVoiceInkSessionError.launchTimedOut(path)
    }

    private static func sha256(path: String) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path)))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appendLaunchEvidence(
        processIdentifier: pid_t,
        sourceBundlePath: String,
        runningBundlePath: String,
        sourceExecutableSHA256: String,
        runningExecutableSHA256: String
    ) throws {
        guard let evidencePath = ProcessInfo.processInfo.environment[
            "RUNTIME_E2E_VOICEINK_LAUNCH_EVENTS"
        ], !evidencePath.isEmpty else {
            return
        }
        let fields = [
            ISO8601DateFormatter().string(from: Date()),
            String(processIdentifier),
            sourceExecutableSHA256,
            runningExecutableSHA256,
            sourceBundlePath,
            runningBundlePath
        ]
        guard fields.allSatisfy({ !$0.contains("\t") && !$0.contains("\n") }) else {
            throw RuntimeVoiceInkSessionError.launchEvidenceInvalid
        }
        let line = Data((fields.joined(separator: "\t") + "\n").utf8)
        let evidenceURL = URL(fileURLWithPath: evidencePath)
        if !FileManager.default.fileExists(atPath: evidencePath) {
            try Data().write(to: evidenceURL, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: evidenceURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private static func writeJournal(_ journal: RuntimeVoiceInkRestorationJournal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)
    }
}

enum RuntimeVoiceInkSessionError: Error, CustomStringConvertible {
    case applicationNotFound(String)
    case applicationWouldNotTerminate
    case preferenceSynchronizationFailed
    case unsupportedSystemMuteMode
    case launchFailed(String)
    case launchIdentityUnavailable(String)
    case launchEvidenceInvalid
    case launchTimedOut(String)

    var description: String {
        switch self {
        case .applicationNotFound(let identifier):
            return "Could not resolve VoiceInk app for \(identifier)"
        case .applicationWouldNotTerminate:
            return "VoiceInk did not terminate within 10 seconds; preferences were not changed"
        case .preferenceSynchronizationFailed:
            return "Could not synchronize VoiceInk audio preferences"
        case .unsupportedSystemMuteMode:
            return "Unsupported recording-mute preference; no preferences were changed"
        case .launchFailed(let path):
            return "Could not launch VoiceInk at \(path)"
        case .launchIdentityUnavailable(let path):
            return "Could not inspect the launched VoiceInk identity at \(path)"
        case .launchEvidenceInvalid:
            return "VoiceInk launch evidence contains an unsupported tab or newline"
        case .launchTimedOut(let path):
            return "VoiceInk launch timed out at \(path)"
        }
    }
}
