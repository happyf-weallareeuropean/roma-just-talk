import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import os
import VoiceInkCore

struct PreRollStreamingEmissionGate {
    private var isActive = false
    private var queuedLiveChunks: [Data] = []

    mutating func begin() {
        isActive = true
        queuedLiveChunks.removeAll(keepingCapacity: true)
    }

    mutating func queueLiveChunkIfNeeded(_ data: Data) -> Bool {
        guard isActive else { return false }
        queuedLiveChunks.append(data)
        return true
    }

    mutating func finish() -> [Data] {
        isActive = false
        return takeQueuedChunks()
    }

    mutating func takeQueuedChunks() -> [Data] {
        let queued = queuedLiveChunks
        queuedLiveChunks.removeAll(keepingCapacity: true)
        return queued
    }

    mutating func cancel() {
        isActive = false
        queuedLiveChunks.removeAll(keepingCapacity: true)
    }
}

// MARK: - Core Audio Recorder (AUHAL-based, does not change system default device)
final class CoreAudioRecorder: @unchecked Sendable {
    // MARK: - Properties

    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.coreAudioRecorder
    )

    private var audioUnit: AudioUnit?
    private var audioFile: ExtAudioFileRef?

    private let fileAccessLock = NSCondition()
    private var streamingDeliveriesInFlight = 0
    private var captureInputFrames: Int64 = 0
    private var captureOutputFrames: Int64 = 0
    private var recordingPCM: RecordingPCMCounts?

    private struct RecordingPCMCounts {
        let nativeRate: Double
        let nativeChannels: UInt32
        let inputClockStart: Int64
        let outputClockStart: Int64
        let preRollPCMFrames: Int
        var inputClockCut: Int64 = 0
        var outputClockCut: Int64 = 0
        var nativeFrames: Int64 = 0
        var conversionCallbacks = 0
        var minCallbackFrames: UInt32 = .max
        var maxCallbackFrames: UInt32 = 0
        var rejectedNativeFrames: Int64 = 0
        var conversionRejects = 0
        var tailConversionRejects = 0
        var livePCMFrames: Int64 = 0
        var tailPCMFrames: Int64 = 0
        var mixedFormat = false
        var streamingContinuous: Bool

        var details: String {
            "nativeRate=\(nativeRate) nativeChannels=\(nativeChannels) nativeFrames=\(nativeFrames) "
                + "conversionCallbacks=\(conversionCallbacks) minCallbackFrames=\(conversionCallbacks == 0 ? 0 : minCallbackFrames) maxCallbackFrames=\(maxCallbackFrames) "
                + "rejectedNativeFrames=\(rejectedNativeFrames) conversionRejects=\(conversionRejects) tailConversionRejects=\(tailConversionRejects) "
                + "preRollPCMFrames=\(preRollPCMFrames) livePCMFrames=\(livePCMFrames) tailPCMFrames=\(tailPCMFrames) "
                + "inputClockStart=\(inputClockStart) inputClockCut=\(inputClockCut) outputClockStart=\(outputClockStart) outputClockCut=\(outputClockCut) "
                + "mixedFormat=\(mixedFormat) streamingContinuous=\(streamingContinuous)"
        }
    }
    private var isCapturing = false
    private var isRecording = false
    private var currentDeviceID: AudioDeviceID = 0
    private var recordingURL: URL?
    private let preRollBuffer = VoiceInkPCM16PreRollBuffer(
        sampleRate: VoiceInkPCM16Audio.mono16kSampleRateHz,
        durationSeconds: VoiceInkAudioPreRollPolicy.durationSeconds
    )
    private let preRollStreamingChunkBytes = VoiceInkPCM16Audio.byteCount(forMono16kDuration: 0.1)
    private var preRollStreamingGate = PreRollStreamingEmissionGate()

    // Device format (what the hardware provides)
    private var deviceFormat = AudioStreamBasicDescription()
    // Output format (16kHz mono PCM Int16 for transcription)
    private var outputFormat = AudioStreamBasicDescription()

    // Conversion buffer
    private var conversionBuffer: UnsafeMutablePointer<Int16>?
    private var conversionBufferSize: UInt32 = 0
    private var streamConverter: VoiceInkPCM16StreamConverter?

    // Audio metering (thread-safe)
    private let meterLock = NSLock()
    private var _averagePower: Float = -160.0
    private var _peakPower: Float = -160.0

    var averagePower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _averagePower
    }

    var peakPower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _peakPower
    }

    // Pre-allocated render buffer (to avoid malloc in real-time callback)
    private var renderBuffer: UnsafeMutablePointer<Float32>?
    private var renderBufferSize: UInt32 = 0

    /// Called on the audio thread with raw PCM data (16-bit, 16kHz, mono) for streaming.
    private var audioChunkCallback: ((_ data: Data) -> Void)?
    var onAudioChunk: ((_ data: Data) -> Void)? {
        get {
            fileAccessLock.lock()
            defer { fileAccessLock.unlock() }
            return audioChunkCallback
        }
        set {
            fileAccessLock.lock()
            if newValue == nil { recordingPCM?.streamingContinuous = false }
            audioChunkCallback = newValue
            fileAccessLock.unlock()
        }
    }

    // MARK: - Initialization

    init() {}

    deinit {
        stopRecording()
    }

    // MARK: - Public Interface

    /// Opens the input device and keeps a small PCM ring buffer warm without writing to disk.
    func startPreBuffering(deviceID: AudioDeviceID) throws {
        if isRecording {
            return
        }

        if isCapturing, currentDeviceID == deviceID, inputFormatMatchesConfiguration() {
            return
        }

        stopRecording()

        if deviceID == 0 {
            logger.error("Cannot start pre-roll buffering - no valid audio device (deviceID is 0)")
            throw CoreAudioRecorderError.failedToSetDevice(status: 0)
        }

        guard isDeviceAvailable(deviceID) else {
            logger.error("Cannot start pre-roll buffering - device \(deviceID, privacy: .public) is no longer available")
            throw CoreAudioRecorderError.deviceNotAvailable
        }

        currentDeviceID = deviceID
        preRollBuffer.clear()

        logger.notice("🎙️ Starting pre-roll buffering from device \(deviceID, privacy: .public)")
        logDeviceDetails(deviceID: deviceID)

        try createAudioUnit()
        try setInputDevice(deviceID)
        try configureFormats()
        try setupInputCallback()
        try startAudioUnit()

        isCapturing = true
    }

    /// Starts recording from the specified device to the given URL (WAV format)
    func startRecording(
        toOutputFile url: URL,
        deviceID: AudioDeviceID,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) throws {
        if deviceID == 0 {
            logger.error("Cannot start recording - no valid audio device (deviceID is 0)")
            throw CoreAudioRecorderError.failedToSetDevice(status: 0)
        }

        // Validate device still exists before proceeding with setup
        guard isDeviceAvailable(deviceID) else {
            logger.error("Cannot start recording - device \(deviceID, privacy: .public) is no longer available")
            throw CoreAudioRecorderError.deviceNotAvailable
        }

        if isRecording {
            finishRecording(latencyTraceToken: latencyTraceToken)
        }

        if !isCapturing || currentDeviceID != deviceID || !inputFormatMatchesConfiguration() {
            try startPreBuffering(deviceID: deviceID)
        }

        logger.notice("🎙️ Starting recording from device \(deviceID, privacy: .public)")

        recordingURL = url
        let outputFileSpan = VoiceInkLatencyTrace.shared.begin(
            "core_audio.output_file.create",
            token: latencyTraceToken
        )
        let fileRef: ExtAudioFileRef
        do {
            fileRef = try createOutputFile(at: url)
            VoiceInkLatencyTrace.shared.end(outputFileSpan, details: "result=success")
        } catch {
            VoiceInkLatencyTrace.shared.end(
                outputFileSpan,
                details: "result=failure error=\(String(describing: type(of: error)))"
            )
            throw error
        }

        var preRollData = Data()
        var preRollDeliveryInFlight = false
        let preRollSnapshotSpan = VoiceInkLatencyTrace.shared.begin(
            "core_audio.pre_roll.snapshot_and_write",
            token: latencyTraceToken
        )
        fileAccessLock.lock()
        do {
            audioFile = fileRef
            preRollData = preRollBuffer.snapshotData()
            if !preRollData.isEmpty {
                try writePCMDataToFile(preRollData)
                if audioChunkCallback != nil {
                    preRollStreamingGate.begin()
                    streamingDeliveriesInFlight += 1
                    preRollDeliveryInFlight = true
                }
            }
            beginRecordingPCMCountsLocked(preRollData: preRollData)
            isRecording = true
            fileAccessLock.unlock()
        } catch {
            audioFile = nil
            preRollStreamingGate.cancel()
            fileAccessLock.unlock()
            ExtAudioFileDispose(fileRef)
            VoiceInkLatencyTrace.shared.end(
                preRollSnapshotSpan,
                details: "result=failure bytes=\(preRollData.count) error=\(String(describing: type(of: error)))"
            )
            throw error
        }
        VoiceInkLatencyTrace.shared.end(
            preRollSnapshotSpan,
            details: "result=success bytes=\(preRollData.count)"
        )

        if !preRollData.isEmpty {
            let preRollEmitSpan = VoiceInkLatencyTrace.shared.begin(
                "core_audio.pre_roll.emit_to_stream",
                token: latencyTraceToken
            )
            emitPreRollDataToStreaming(preRollData)
            finishPreRollStreamingEmission()
            if preRollDeliveryInFlight { completeStreamingDelivery() }
            VoiceInkLatencyTrace.shared.end(
                preRollEmitSpan,
                details: "bytes=\(preRollData.count)"
            )
            logger.notice("🎙️ Wrote pre-roll buffer bytes=\(preRollData.count, privacy: .public)")
        }
    }

    /// Finishes the WAV file while leaving the AudioUnit open so the next hotkey has pre-roll.
    func finishRecording(
        keepCapturing: Bool = true,
        latencyTraceToken: VoiceInkLatencyTrace.Token? = nil
    ) {
        let latencySpan = VoiceInkLatencyTrace.shared.begin(
            "core_audio.finish_recording",
            token: latencyTraceToken
        )
        let start = Date()

        fileAccessLock.lock()
        guard isRecording || audioFile != nil else {
            while streamingDeliveriesInFlight > 0 { fileAccessLock.wait() }
            fileAccessLock.unlock()
            VoiceInkLatencyTrace.shared.end(latencySpan)
            return
        }
        let tail = finishConvertedSegmentLocked()
        let ownedTailCount = tail == nil ? 0 : 1
        streamingDeliveriesInFlight += ownedTailCount
        isRecording = false
        let file = audioFile
        audioFile = nil
        preRollBuffer.clear()
        recordingPCM?.inputClockCut = captureInputFrames
        recordingPCM?.outputClockCut = captureOutputFrames
        // Freeze before wait releases the lock and admits the next pre-roll callbacks.
        let finishedPCM = recordingPCM
        recordingPCM = nil
        // Previously admitted audio must reach streaming before Recorder clears its callback.
        while streamingDeliveriesInFlight > ownedTailCount { fileAccessLock.wait() }
        fileAccessLock.unlock()
        if let tail {
            tail.handler(tail.data)
            completeStreamingDelivery()
        }

        if let file {
            ExtAudioFileDispose(file)
        }

        recordingURL = nil
        if let finishedPCM {
            VoiceInkLatencyTrace.shared.event(
                "core_audio.pcm_recording",
                details: finishedPCM.details,
                token: latencyTraceToken
            )
        }
        VoiceInkLatencyTrace.shared.end(
            latencySpan,
            details: "keepCapturing=\(keepCapturing)"
        )
        logger.notice("finishRecording completed keepCapturing=\(keepCapturing, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
    }

    /// Stops the current recording
    func stopRecording() {
        guard isRecording || isCapturing || audioUnit != nil else {
            logger.notice("stopRecording: skipped, not recording and no audio unit")
            return
        }
        logger.notice("stopRecording: stopping core audio recorder")

        finishRecording(keepCapturing: false)

        // Stop and dispose AudioUnit
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        fileAccessLock.lock()
        streamConverter = nil
        fileAccessLock.unlock()

        // Close audio file
        if let file = audioFile {
            ExtAudioFileDispose(file)
            audioFile = nil
        }

        // Free conversion buffer
        if let buffer = conversionBuffer {
            buffer.deallocate()
            conversionBuffer = nil
            conversionBufferSize = 0
        }

        // Free render buffer
        if let buffer = renderBuffer {
            buffer.deallocate()
            renderBuffer = nil
            renderBufferSize = 0
        }

        isRecording = false
        isCapturing = false
        currentDeviceID = 0
        recordingURL = nil
        preRollBuffer.clear()
        preRollStreamingGate.cancel()

        // Reset meters
        meterLock.lock()
        _averagePower = -160.0
        _peakPower = -160.0
        meterLock.unlock()
    }

    var isCurrentlyRecording: Bool { isRecording }
    var isPreBuffering: Bool { isCapturing && !isRecording }
    var currentRecordingURL: URL? { recordingURL }
    var currentDevice: AudioDeviceID { currentDeviceID }

    /// Switches to a new input device mid-recording without stopping the file write
    func switchDevice(to newDeviceID: AudioDeviceID) throws {
        guard isCapturing, let unit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Don't switch if it's the same device
        guard newDeviceID != currentDeviceID || !inputFormatMatchesConfiguration() else { return }

        let oldDeviceID = currentDeviceID
        logger.notice("🎙️ Switching recording device from \(oldDeviceID, privacy: .public) to \(newDeviceID, privacy: .public)")

        // Step 1: Stop the AudioUnit (but keep file open)
        var status = AudioOutputUnitStop(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToStop(status: status)
        }
        fileAccessLock.lock()
        let tail = finishConvertedSegmentLocked()
        let ownedTailCount = tail == nil ? 0 : 1
        streamingDeliveriesInFlight += ownedTailCount
        streamConverter?.reset()
        resetCapturePCMClockLocked()
        while streamingDeliveriesInFlight > ownedTailCount { fileAccessLock.wait() }
        fileAccessLock.unlock()
        if let tail {
            tail.handler(tail.data)
            completeStreamingDelivery()
        }

        // Step 2: Uninitialize to allow reconfiguration
        status = AudioUnitUninitialize(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioUnitUninitialize returned \(status, privacy: .public)")
        }

        // Step 3: Set the new device
        var device = newDeviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            // Try to recover by restarting with old device
            logger.error("Failed to set new device: \(status, privacy: .public). Attempting recovery...")
            var recoveryDevice = oldDeviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &recoveryDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
            AudioUnitInitialize(unit)
            AudioOutputUnitStart(unit)
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }

        // Step 4: Get new device format
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var newDeviceFormat = AudioStreamBasicDescription()
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &newDeviceFormat,
            &formatSize
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Step 5: Configure callback format for new device
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: newDeviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: newDeviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Step 6: Reallocate buffers if needed
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * newDeviceFormat.mChannelsPerFrame
        if bufferSamples > renderBufferSize {
            renderBuffer?.deallocate()
            renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
            renderBufferSize = bufferSamples
        }

        // Reallocate conversion buffer if new sample rate requires more space
        try configureStreamConverter(for: newDeviceFormat)

        // Update stored format
        deviceFormat = newDeviceFormat
        currentDeviceID = newDeviceID
        preRollBuffer.clear()

        // Step 7: Reinitialize and restart
        status = AudioUnitInitialize(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }

        status = AudioOutputUnitStart(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToStart(status: status)
        }

        logger.notice("🎙️ Successfully switched to device \(newDeviceID, privacy: .public)")
    }

    // MARK: - AudioUnit Setup

    private func createAudioUnit() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            logger.error("AudioUnit not found - HAL Output component unavailable")
            throw CoreAudioRecorderError.audioUnitNotFound
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            logger.error("Failed to create AudioUnit instance: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateAudioUnit(status: status)
        }

        self.audioUnit = audioUnit

        // Enable input on element 1 (input scope)
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Element 1 = input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to enable audio input: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToEnableInput(status: status)
        }

        // Disable output on element 0 (output scope)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // Element 0 = output
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to disable audio output: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToDisableOutput(status: status)
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.error("Failed to set input device \(deviceID, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }
    }

    private func configureFormats() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Get the device's native format (input scope, element 1)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &deviceFormat,
            &formatSize
        )

        if status != noErr {
            logger.error("Failed to get device format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Configure output format: 16kHz, mono, PCM Int16
        outputFormat = AudioStreamBasicDescription(
            mSampleRate: VoiceInkPCM16Audio.mono16kSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(VoiceInkPCM16Audio.bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(VoiceInkPCM16Audio.bytesPerSample),
            mChannelsPerFrame: UInt32(VoiceInkPCM16Audio.monoChannelCount),
            mBitsPerChannel: UInt32(VoiceInkPCM16Audio.bitsPerSample),
            mReserved: 0
        )

        // Set callback format (Float32 for processing, then convert to Int16 for file)
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: deviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: deviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            logger.error("Failed to set audio format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Log format details
        let devSampleRate = deviceFormat.mSampleRate
        let devChannels = deviceFormat.mChannelsPerFrame
        let devBits = deviceFormat.mBitsPerChannel
        let outSampleRate = outputFormat.mSampleRate
        let outChannels = outputFormat.mChannelsPerFrame
        let outBits = outputFormat.mBitsPerChannel
        logger.notice("🎙️ Device format: sampleRate=\(devSampleRate, privacy: .public), channels=\(devChannels, privacy: .public), bitsPerChannel=\(devBits, privacy: .public)")
        logger.notice("🎙️ Output format: sampleRate=\(outSampleRate, privacy: .public), channels=\(outChannels, privacy: .public), bitsPerChannel=\(outBits, privacy: .public)")
        if devSampleRate != outSampleRate {
            logger.notice("🎙️ Converting: \(Int(devSampleRate), privacy: .public)Hz → \(Int(outSampleRate), privacy: .public)Hz")
        }

        // Pre-allocate buffers for real-time callback (avoid malloc in callback)
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * deviceFormat.mChannelsPerFrame
        renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
        renderBufferSize = bufferSamples

        // Pre-allocate conversion buffer (output is always smaller due to downsampling)
        try configureStreamConverter(for: deviceFormat)
    }

    private func configureStreamConverter(for format: AudioStreamBasicDescription) throws {
        guard let converter = VoiceInkPCM16StreamConverter(
            inputSampleRate: format.mSampleRate,
            channelCount: Int(format.mChannelsPerFrame)
        ), converter.maximumOutputFrameCount <= Int(UInt32.max) else {
            throw CoreAudioRecorderError.failedToSetFormat(status: kAudio_ParamError)
        }
        if converter.maximumOutputFrameCount > Int(conversionBufferSize) {
            conversionBuffer?.deallocate()
            conversionBuffer = .allocate(capacity: converter.maximumOutputFrameCount)
            conversionBufferSize = UInt32(converter.maximumOutputFrameCount)
        }
        fileAccessLock.lock()
        streamConverter = converter
        resetCapturePCMClockLocked()
        fileAccessLock.unlock()
    }

    private func inputFormatMatchesConfiguration() -> Bool {
        guard let audioUnit else { return false }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                   1, &format, &size) == noErr else { return false }
        return format.mSampleRate == deviceFormat.mSampleRate
            && format.mChannelsPerFrame == deviceFormat.mChannelsPerFrame
    }

    private func setupInputCallback() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to set input callback: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetCallback(status: status)
        }
    }

    private func createOutputFile(at url: URL) throws -> ExtAudioFileRef {
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create ExtAudioFile for writing
        var fileRef: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &fileRef
        )

        if status != noErr {
            logger.error("Failed to create audio file at \(url.path, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateFile(status: status)
        }

        guard let fileRef else {
            logger.error("Failed to create audio file at \(url.path, privacy: .public): missing file reference")
            throw CoreAudioRecorderError.failedToCreateFile(status: -1)
        }

        // Set client format (what we'll write)
        status = ExtAudioFileSetProperty(
            fileRef,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &outputFormat
        )

        if status != noErr {
            logger.error("Failed to set file format: \(status, privacy: .public)")
            ExtAudioFileDispose(fileRef)
            throw CoreAudioRecorderError.failedToSetFileFormat(status: status)
        }

        return fileRef
    }

    private func startAudioUnit() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var status = AudioUnitInitialize(audioUnit)
        if status != noErr {
            logger.error("Failed to initialize AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }

        status = AudioOutputUnitStart(audioUnit)
        if status != noErr {
            logger.error("Failed to start AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToStart(status: status)
        }
    }

    // MARK: - Input Callback

    private let inputCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in

        let recorder = Unmanaged<CoreAudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.handleInputBuffer(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inBusNumber: inBusNumber,
            inNumberFrames: inNumberFrames
        )
    }

    private func handleInputBuffer(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) -> OSStatus {

        guard let audioUnit = audioUnit, isCapturing, let renderBuf = renderBuffer else {
            return noErr
        }

        // Use pre-allocated buffer for input data
        let channelCount = deviceFormat.mChannelsPerFrame
        let requiredSamples = inNumberFrames * channelCount

        // Safety check - shouldn't happen with 4096 max frames
        guard requiredSamples <= renderBufferSize else {
            return noErr
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * channelCount
        let bufferSize = inNumberFrames * bytesPerFrame

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: channelCount,
                mDataByteSize: bufferSize,
                mData: renderBuf
            )
        )

        // Render audio from the input
        let status = AudioUnitRender(
            audioUnit,
            ioActionFlags,
            inTimeStamp,
            inBusNumber,
            inNumberFrames,
            &bufferList
        )

        if status != noErr {
            return status
        }

        // Calculate audio meters from input buffer
        calculateMeters(from: &bufferList, frameCount: inNumberFrames)

        // Convert and write to file
        convertAndWriteToFile(inputBuffer: &bufferList, frameCount: inNumberFrames)

        return noErr
    }

    private func calculateMeters(from bufferList: inout AudioBufferList, frameCount: UInt32) {
        guard let data = bufferList.mBuffers.mData else { return }
        guard frameCount > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float32.self)
        let channelCount = Int(deviceFormat.mChannelsPerFrame)
        let totalSamples = Int(frameCount) * channelCount

        guard totalSamples > 0 else { return }

        var sum: Float = 0.0
        var peak: Float = 0.0

        for i in 0..<totalSamples {
            let sample = abs(samples[i])
            sum += sample * sample
            if sample > peak {
                peak = sample
            }
        }

        let rms = sqrt(sum / Float(totalSamples))
        let avgDb = 20.0 * log10(max(rms, 0.000001))
        let peakDb = 20.0 * log10(max(peak, 0.000001))

        meterLock.lock()
        _averagePower = avgDb
        _peakPower = peakDb
        meterLock.unlock()
    }

    private func beginRecordingPCMCountsLocked(preRollData: Data) {
        recordingPCM = RecordingPCMCounts(
            nativeRate: deviceFormat.mSampleRate,
            nativeChannels: deviceFormat.mChannelsPerFrame,
            inputClockStart: captureInputFrames,
            outputClockStart: captureOutputFrames,
            preRollPCMFrames: VoiceInkPCM16Audio.sampleCount(inData: preRollData),
            streamingContinuous: audioChunkCallback != nil
        )
    }

    private func resetCapturePCMClockLocked() {
        captureInputFrames = 0
        captureOutputFrames = 0
        // A reset invalidates start/cut subtraction even when the new format is identical.
        recordingPCM?.mixedFormat = true
    }

    private func convertAndWriteToFile(inputBuffer: inout AudioBufferList, frameCount: UInt32) {
        fileAccessLock.lock()
        if recordingPCM != nil {
            recordingPCM!.conversionCallbacks += 1
            recordingPCM!.minCallbackFrames = min(recordingPCM!.minCallbackFrames, frameCount)
            recordingPCM!.maxCallbackFrames = max(recordingPCM!.maxCallbackFrames, frameCount)
        }
        guard let inputData = inputBuffer.mBuffers.mData,
              let streamConverter, let outputBuffer = conversionBuffer,
              let written = streamConverter.convert(inputData.assumingMemoryBound(to: Float32.self), frameCount: Int(frameCount),
                                                    to: outputBuffer, outputCapacity: Int(conversionBufferSize)) else {
            recordingPCM?.conversionRejects += 1
            recordingPCM?.rejectedNativeFrames += Int64(frameCount)
            fileAccessLock.unlock()
            return
        }
        captureInputFrames += Int64(frameCount)
        captureOutputFrames += Int64(written)
        recordingPCM?.nativeFrames += Int64(frameCount)
        recordingPCM?.livePCMFrames += Int64(written)
        let delivery = consumeConvertedSamplesLocked(written)
        if delivery != nil { streamingDeliveriesInFlight += 1 }
        fileAccessLock.unlock()
        if let delivery {
            delivery.handler(delivery.data)
            completeStreamingDelivery()
        }
    }

    private func completeStreamingDelivery() {
        fileAccessLock.lock()
        streamingDeliveriesInFlight -= 1
        fileAccessLock.broadcast()
        fileAccessLock.unlock()
    }

    private typealias AudioDelivery = (data: Data, handler: (Data) -> Void)

    private func finishConvertedSegmentLocked() -> AudioDelivery? {
        guard let streamConverter, let conversionBuffer,
              let written = streamConverter.finishSegment(to: conversionBuffer,
                                                          outputCapacity: Int(conversionBufferSize)) else {
            recordingPCM?.tailConversionRejects += 1
            return nil
        }
        captureOutputFrames += Int64(written)
        recordingPCM?.tailPCMFrames += Int64(written)
        return consumeConvertedSamplesLocked(written)
    }

    private func consumeConvertedSamplesLocked(_ frameCount: Int) -> AudioDelivery? {
        guard frameCount > 0, let outputBuffer = conversionBuffer else { return nil }
        let outputFrameCount = UInt32(frameCount)
        var outputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(VoiceInkPCM16Audio.monoChannelCount),
                mDataByteSize: outputFrameCount * UInt32(VoiceInkPCM16Audio.bytesPerSample),
                mData: outputBuffer
            )
        )

        preRollBuffer.append(outputBuffer, sampleCount: Int(outputFrameCount))
        if isRecording, let file = audioFile {
            let writeStatus = ExtAudioFileWrite(file, outputFrameCount, &outputBufferList)
            if writeStatus != noErr {
                logger.error("🎙️ ExtAudioFileWrite failed with status: \(writeStatus, privacy: .public)")
            }
        }
        if isRecording, let audioChunkCallback {
            let byteCount = Int(outputFrameCount) * VoiceInkPCM16Audio.bytesPerSample
            let data = Data(bytes: outputBuffer, count: byteCount)
            if !preRollStreamingGate.queueLiveChunkIfNeeded(data) {
                return (data, audioChunkCallback)
            }
        }
        return nil
    }

    private func writePCMDataToFile(_ data: Data) throws {
        guard let file = audioFile else { return }
        guard data.count >= VoiceInkPCM16Audio.bytesPerSample else { return }

        let frameCount = UInt32(VoiceInkPCM16Audio.sampleCount(inData: data))
        var mutableData = data
        let writeStatus: OSStatus = mutableData.withUnsafeMutableBytes { rawBuffer in
            var outputBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(VoiceInkPCM16Audio.monoChannelCount),
                    mDataByteSize: frameCount * UInt32(VoiceInkPCM16Audio.bytesPerSample),
                    mData: rawBuffer.baseAddress
                )
            )
            return ExtAudioFileWrite(file, frameCount, &outputBufferList)
        }

        if writeStatus != noErr {
            logger.error("🎙️ Failed to write pre-roll buffer: \(writeStatus, privacy: .public)")
            throw CoreAudioRecorderError.failedToWriteFile(status: writeStatus)
        }
    }

    private func emitPreRollDataToStreaming(_ data: Data) {
        guard let onAudioChunk else { return }

        for chunk in VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: preRollStreamingChunkBytes) {
            onAudioChunk(chunk)
        }
    }

    private func finishPreRollStreamingEmission() {
        while true {
            fileAccessLock.lock()
            let queuedLiveChunks = preRollStreamingGate.takeQueuedChunks()
            let audioChunkHandler = audioChunkCallback
            if queuedLiveChunks.isEmpty {
                _ = preRollStreamingGate.finish()
                fileAccessLock.unlock()
                return
            }
            fileAccessLock.unlock()
            for chunk in queuedLiveChunks { audioChunkHandler?(chunk) }
        }
    }

    // MARK: - Device Info Logging

    private func logDeviceDetails(deviceID: AudioDeviceID) {
        // Get device name
        let deviceName = VoiceInkMacOSCoreAudioRecorderDiagnostics.knownText(
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
        )

        // Get device UID
        let deviceUID = VoiceInkMacOSCoreAudioRecorderDiagnostics.knownText(
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
        )

        // Get transport type
        let transportType = getTransportType(deviceID: deviceID)

        // Get manufacturer
        let manufacturer = VoiceInkMacOSCoreAudioRecorderDiagnostics.knownText(
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString)
        )

        logger.notice("\(VoiceInkMacOSCoreAudioRecorderDiagnostics.deviceInfoMessage(name: deviceName, uid: deviceUID), privacy: .public)")
        logger.notice("\(VoiceInkMacOSCoreAudioRecorderDiagnostics.deviceDetailsMessage(transport: transportType, manufacturer: manufacturer), privacy: .public)")

        // Get buffer frame size
        if let bufferSize = getBufferFrameSize(deviceID: deviceID) {
            logger.notice("\(VoiceInkMacOSCoreAudioRecorderDiagnostics.bufferLatencyMessage(bufferFrameSize: bufferSize), privacy: .public)")
        }
    }

    private func getDeviceStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var property: CFString?

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )

        if status == noErr, let cfString = property {
            return cfString as String
        }
        return nil
    }

    private func getTransportType(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        if status != noErr {
            return VoiceInkMacOSCoreAudioRecorderDiagnostics.transportText(.unknown)
        }

        let transportKind: VoiceInkMacOSCoreAudioRecorderDiagnostics.TransportKind
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            transportKind = .builtIn
        case kAudioDeviceTransportTypeUSB:
            transportKind = .usb
        case kAudioDeviceTransportTypeBluetooth:
            transportKind = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            transportKind = .bluetoothLE
        case kAudioDeviceTransportTypeAggregate:
            transportKind = .aggregate
        case kAudioDeviceTransportTypeVirtual:
            transportKind = .virtual
        case kAudioDeviceTransportTypePCI:
            transportKind = .pci
        case kAudioDeviceTransportTypeFireWire:
            transportKind = .fireWire
        case kAudioDeviceTransportTypeDisplayPort:
            transportKind = .displayPort
        case kAudioDeviceTransportTypeHDMI:
            transportKind = .hdmi
        case kAudioDeviceTransportTypeAVB:
            transportKind = .avb
        case kAudioDeviceTransportTypeThunderbolt:
            transportKind = .thunderbolt
        default:
            transportKind = .other(transportType)
        }

        return VoiceInkMacOSCoreAudioRecorderDiagnostics.transportText(transportKind)
    }

    private func getBufferFrameSize(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bufferSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &bufferSize
        )

        return status == noErr ? bufferSize : nil
    }

    /// Checks if a device is currently available using Apple's kAudioDevicePropertyDeviceIsAlive
    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isAlive
        )

        return status == noErr && isAlive == 1
    }
}

// MARK: - Error Types

enum CoreAudioRecorderError: LocalizedError {
    case audioUnitNotFound
    case audioUnitNotInitialized
    case deviceNotAvailable
    case failedToCreateAudioUnit(status: OSStatus)
    case failedToEnableInput(status: OSStatus)
    case failedToDisableOutput(status: OSStatus)
    case failedToSetDevice(status: OSStatus)
    case failedToGetDeviceFormat(status: OSStatus)
    case failedToSetFormat(status: OSStatus)
    case failedToSetCallback(status: OSStatus)
    case failedToCreateFile(status: OSStatus)
    case failedToSetFileFormat(status: OSStatus)
    case failedToWriteFile(status: OSStatus)
    case failedToInitialize(status: OSStatus)
    case failedToStart(status: OSStatus)
    case failedToStop(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .audioUnitNotFound:
            return "HAL Output AudioUnit not found"
        case .audioUnitNotInitialized:
            return "AudioUnit not initialized"
        case .deviceNotAvailable:
            return "Audio device is no longer available"
        case .failedToCreateAudioUnit(let status):
            return "Failed to create AudioUnit: \(status)"
        case .failedToEnableInput(let status):
            return "Failed to enable input: \(status)"
        case .failedToDisableOutput(let status):
            return "Failed to disable output: \(status)"
        case .failedToSetDevice(let status):
            return "Failed to set input device: \(status)"
        case .failedToGetDeviceFormat(let status):
            return "Failed to get device format: \(status)"
        case .failedToStop(let status):
            return "Failed to stop AudioUnit: \(status)"
        case .failedToSetFormat(let status):
            return "Failed to set audio format: \(status)"
        case .failedToSetCallback(let status):
            return "Failed to set input callback: \(status)"
        case .failedToCreateFile(let status):
            return "Failed to create audio file: \(status)"
        case .failedToSetFileFormat(let status):
            return "Failed to set file format: \(status)"
        case .failedToWriteFile(let status):
            return "Failed to write audio file: \(status)"
        case .failedToInitialize(let status):
            return "Failed to initialize AudioUnit: \(status)"
        case .failedToStart(let status):
            return "Failed to start AudioUnit: \(status)"
        }
    }
}
