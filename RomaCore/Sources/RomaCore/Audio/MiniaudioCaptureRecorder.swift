import CMiniaudio
import Foundation

public enum MiniaudioCaptureRecorderError: Error, Equatable, CustomStringConvertible {
    case alreadyCapturing
    case notCapturing
    case notRecording
    case missingOutputFile
    case createFailed(result: Int32)
    case startFailed(result: Int32)
    case stopFailed(result: Int32)

    public var description: String {
        switch self {
        case .alreadyCapturing:
            return "miniaudio capture is already running"
        case .notCapturing:
            return "miniaudio capture is not running"
        case .notRecording:
            return "miniaudio recording is not active"
        case .missingOutputFile:
            return "miniaudio recording has no output file"
        case .createFailed(let result):
            return "miniaudio capture create failed with result \(result)"
        case .startFailed(let result):
            return "miniaudio capture start failed with result \(result)"
        case .stopFailed(let result):
            return "miniaudio capture stop failed with result \(result)"
        }
    }
}

public final class MiniaudioCaptureRecorder: RollingRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private let preRollBuffer: PCMPreRollBuffer
    private var device: OpaquePointer?
    private var isRecording = false
    private var outputFile: URL?
    private var recordedSamples: [Int16] = []
    private var recordingPreRollSampleCount = 0
    private var _onAudioChunk: (@Sendable (Data) -> Void)?

    public let preRollConfiguration: PreRollConfiguration

    public static let miniaudioVersion = "0.11.25"

    public var onAudioChunk: (@Sendable (Data) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onAudioChunk
        }
        set {
            lock.lock()
            _onAudioChunk = newValue
            lock.unlock()
        }
    }

    public init(preRollConfiguration: PreRollConfiguration = PreRollConfiguration()) {
        self.preRollConfiguration = preRollConfiguration
        preRollBuffer = PCMPreRollBuffer(configuration: preRollConfiguration)
    }

    deinit {
        destroyDevice()
    }

    public func startPreRollBuffering() async throws {
        try prepareForCaptureStart()

        var createdDevice: OpaquePointer?
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        let createResult = roma_miniaudio_capture_create(
            UInt32(preRollConfiguration.outputFormat.sampleRate),
            UInt32(preRollConfiguration.outputFormat.channelCount),
            miniaudioCaptureCallback,
            unmanagedSelf,
            &createdDevice
        )
        guard createResult == 0, let createdDevice else {
            throw MiniaudioCaptureRecorderError.createFailed(result: createResult)
        }

        let startResult = roma_miniaudio_capture_start(createdDevice)
        guard startResult == 0 else {
            roma_miniaudio_capture_destroy(createdDevice)
            throw MiniaudioCaptureRecorderError.startFailed(result: startResult)
        }

        storeStartedDevice(createdDevice)
    }

    public func startRecording(toOutputFile url: URL) async throws {
        let preRollSamples = preRollBuffer.snapshotSamples()
        let callback = try prepareForRecordingStart(preRollSamples: preRollSamples, outputFile: url)

        if let callback, !preRollSamples.isEmpty {
            callback(Self.pcmData(from: preRollSamples))
        }
    }

    public func finishRecording() async throws -> RecordedAudio {
        let (outputFile, samples, preRollSampleCount) = try takeFinishedRecording()

        try PCM16WAVFile.write(
            samples: samples,
            to: outputFile,
            format: preRollConfiguration.outputFormat
        )

        return RecordedAudio(
            fileURL: outputFile,
            format: preRollConfiguration.outputFormat,
            sampleCount: samples.count,
            includedPreRollSampleCount: preRollSampleCount
        )
    }

    public func stopCapture() async {
        destroyDevice()
    }

    private func prepareForCaptureStart() throws {
        lock.lock()
        guard device == nil else {
            lock.unlock()
            throw MiniaudioCaptureRecorderError.alreadyCapturing
        }
        preRollBuffer.clear()
        recordedSamples.removeAll(keepingCapacity: true)
        recordingPreRollSampleCount = 0
        isRecording = false
        outputFile = nil
        lock.unlock()
    }

    private func storeStartedDevice(_ startedDevice: OpaquePointer) {
        lock.lock()
        device = startedDevice
        lock.unlock()
    }

    private func prepareForRecordingStart(
        preRollSamples: [Int16],
        outputFile: URL
    ) throws -> (@Sendable (Data) -> Void)? {
        lock.lock()
        guard device != nil else {
            lock.unlock()
            throw MiniaudioCaptureRecorderError.notCapturing
        }
        self.outputFile = outputFile
        recordedSamples = preRollSamples
        recordingPreRollSampleCount = preRollSamples.count
        isRecording = true
        let callback = _onAudioChunk
        lock.unlock()
        return callback
    }

    private func takeFinishedRecording() throws -> (URL, [Int16], Int) {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            throw MiniaudioCaptureRecorderError.notRecording
        }
        guard let outputFile else {
            lock.unlock()
            throw MiniaudioCaptureRecorderError.missingOutputFile
        }
        let samples = recordedSamples
        let preRollSampleCount = recordingPreRollSampleCount
        recordedSamples.removeAll(keepingCapacity: true)
        recordingPreRollSampleCount = 0
        isRecording = false
        self.outputFile = nil
        lock.unlock()
        return (outputFile, samples, preRollSampleCount)
    }

    fileprivate func handleCapturedSamples(_ samples: UnsafePointer<Int16>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        let copiedSamples = Array(UnsafeBufferPointer(start: samples, count: sampleCount))
        preRollBuffer.append(samples: copiedSamples)

        lock.lock()
        let shouldRecord = isRecording
        if shouldRecord {
            recordedSamples.append(contentsOf: copiedSamples)
        }
        let callback = shouldRecord ? _onAudioChunk : nil
        lock.unlock()

        callback?(Self.pcmData(from: copiedSamples))
    }

    private func destroyDevice() {
        lock.lock()
        let currentDevice = device
        device = nil
        isRecording = false
        outputFile = nil
        recordedSamples.removeAll(keepingCapacity: true)
        recordingPreRollSampleCount = 0
        lock.unlock()

        guard let currentDevice else { return }
        let stopResult = roma_miniaudio_capture_stop(currentDevice)
        if stopResult != 0 {
            // Destroy still uninitializes the device; stop failure is non-fatal during teardown.
        }
        roma_miniaudio_capture_destroy(currentDevice)
    }

    private static func pcmData(from samples: [Int16]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<Int16>.size)

        for sample in samples {
            let value = UInt16(bitPattern: sample)
            data.append(contentsOf: [
                UInt8(value & 0x00FF),
                UInt8((value & 0xFF00) >> 8)
            ])
        }
        return data
    }
}

private func miniaudioCaptureCallback(
    samples: UnsafePointer<Int16>?,
    sampleCount: UInt32,
    userData: UnsafeMutableRawPointer?
) {
    guard let samples, let userData else { return }

    let recorder = Unmanaged<MiniaudioCaptureRecorder>
        .fromOpaque(userData)
        .takeUnretainedValue()
    recorder.handleCapturedSamples(samples, sampleCount: Int(sampleCount))
}
