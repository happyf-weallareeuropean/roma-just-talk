import Foundation
@testable import VoiceInkCore

final class PCM16AudioSamplesTests: XCTestCase {

    func testStreamingResamplingPreservesWholeWaveformAcrossCallbackSizes() {
        for rate in [48_000.0, 44_100, 16_000, 8_000] {
            for channels in [1, 2] {
                let frames = Int(rate) + 7
                let input = (0..<(frames * channels)).map { sample -> Float32 in
                    let frame = sample / channels
                    return Float32(0.7 * sin(Double(frame) * 0.031 + Double(sample % channels)))
                }
                let expected = wholePCM(input, rate: rate, channels: channels)
                for packets in [[512], [512, 257, 1024, 511], [1, 2, 7, 3], [510]] {
                    XCTAssertEqual(streamPCM(input, rate: rate, channels: channels, packets: packets), expected)
                }
            }
        }
    }

    func testStreamingResamplingKeepsTheSampleBeforeAnUnalignedCallbackBoundary() {
        let input = (0..<1536).map { Float32($0) / 2000 }
        let output = streamPCM(input, rate: 48_000, packets: [512])
        XCTAssertEqual(output.count, 512)
        XCTAssertEqual(Array(output[168...172]), [8257, 8306, 8355, 8404, 8453])
    }

    func testStreamingUpsamplingWaitsForFutureInputAndFlushesOnlyOnceAtRecordingCut() {
        let converter = VoiceInkPCM16StreamConverter(inputSampleRate: 8_000, channelCount: 1)!
        XCTAssertEqual(streamAppend([0, 1], converter: converter), [0, 16_383, 32_767])
        XCTAssertEqual(streamAppend([0], converter: converter), [16_383, 0])
        XCTAssertEqual(streamFinish(converter), [0])
        XCTAssertEqual(streamFinish(converter), [])
        // Capture continues at the next global output position, without repeating the cut tail.
        XCTAssertEqual(streamAppend([1], converter: converter), [32_767])
        XCTAssertEqual(streamFinish(converter), [32_767])
    }

    func testStreamingResetDoesNotInterpolateAcrossCaptureOrDeviceLifetimes() {
        let converter = VoiceInkPCM16StreamConverter(inputSampleRate: 8_000, channelCount: 1)!
        XCTAssertEqual(streamAppend([1], converter: converter), [32_767])
        converter.reset()
        XCTAssertEqual(streamAppend([-1], converter: converter), [-32_767])
        XCTAssertEqual(streamFinish(converter), [-32_767])
    }

    func testStreamingRecordingCutsPreserveDownsamplePhaseForFollowingPreRoll() {
        let converter = VoiceInkPCM16StreamConverter(inputSampleRate: 48_000, channelCount: 1)!
        let input = (0..<1536).map { Float32($0) / 2000 }
        var output: [Int16] = []
        for offset in stride(from: 0, to: input.count, by: 512) {
            output += streamAppend(Array(input[offset..<(offset + 512)]), converter: converter)
            output += streamFinish(converter)
        }
        XCTAssertEqual(output, wholePCM(input, rate: 48_000))
    }

    func testStreamingInvalidBufferDoesNotConsumeInputOrDiscardPendingTail() {
        let converter = VoiceInkPCM16StreamConverter(inputSampleRate: 8_000, channelCount: 1)!
        var output = [Int16](repeating: 123, count: 8)
        let rejected = [Float32(0), 1].withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { destination in
                converter.convert(input.baseAddress!, frameCount: 2, to: destination.baseAddress!, outputCapacity: 0)
            }
        }
        XCTAssertNil(rejected)
        XCTAssertEqual(streamAppend([0, 1], converter: converter), [0, 16_383, 32_767])
        let rejectedFinish = output.withUnsafeMutableBufferPointer {
            converter.finishSegment(to: $0.baseAddress!, outputCapacity: 0)
        }
        XCTAssertNil(rejectedFinish)
        XCTAssertEqual(streamFinish(converter), [32_767])
        XCTAssertNil(VoiceInkPCM16StreamConverter(inputSampleRate: .infinity, channelCount: 1))
        XCTAssertNil(VoiceInkPCM16StreamConverter(inputSampleRate: 48_000, channelCount: 0))
    }

    func testStreamingChannelAverageAndClippingPreserveExistingPCMConvention() {
        let input: [Float32] = [0.5, -0.5, 1, 1, -2, -2, 2, 2]
        XCTAssertEqual(streamPCM(input, rate: 16_000, channels: 2, packets: [1]), [0, 32_767, -32_768, 32_767])
    }

    private func wholePCM(_ input: [Float32], rate: Double, channels: Int = 1) -> [Int16] {
        var output = [Int16](repeating: 0, count: input.count * 2 + 8)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                VoiceInkPCM16Audio.writeMonoPCM16Samples(
                    fromInterleavedFloat32Samples: source.baseAddress!, frameCount: input.count / channels,
                    channelCount: channels, inputSampleRate: rate,
                    to: destination.baseAddress!, outputCapacity: destination.count
                )
            }
        }
        return Array(output.prefix(written))
    }

    private func streamPCM(
        _ input: [Float32], rate: Double, channels: Int = 1, packets: [Int]
    ) -> [Int16] {
        let converter = VoiceInkPCM16StreamConverter(inputSampleRate: rate, channelCount: channels)!
        var output: [Int16] = []
        var offset = 0
        var packet = 0
        while offset < input.count {
            let end = min(input.count, offset + packets[packet % packets.count] * channels)
            output += streamAppend(Array(input[offset..<end]), converter: converter, channels: channels)
            offset = end
            packet += 1
        }
        output += streamFinish(converter)
        return output
    }

    private func streamAppend(
        _ input: [Float32], converter: VoiceInkPCM16StreamConverter, channels: Int = 1
    ) -> [Int16] {
        var output = [Int16](repeating: 0, count: converter.maximumOutputFrameCount)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                converter.convert(source.baseAddress!, frameCount: input.count / channels,
                                  to: destination.baseAddress!, outputCapacity: destination.count)
            }
        }
        XCTAssertTrue(written != nil)
        return Array(output.prefix(written ?? 0))
    }

    private func streamFinish(_ converter: VoiceInkPCM16StreamConverter) -> [Int16] {
        var output = [Int16](repeating: 0, count: converter.maximumOutputFrameCount)
        let written = output.withUnsafeMutableBufferPointer {
            converter.finishSegment(to: $0.baseAddress!, outputCapacity: $0.count)
        }
        XCTAssertTrue(written != nil)
        return Array(output.prefix(written ?? 0))
    }

    func testFloatSamplesDecodeLittleEndianPCM16Data() {
        let data = pcm16Data(samples: [Int16.min, -16_384, 0, 16_384, Int16.max])

        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)

        XCTAssertEqual(samples.count, 5)
        XCTAssertEqual(samples[0], -1.0)
        XCTAssertEqual(samples[1], Float(-16_384) / 32_767.0, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 0.0)
        XCTAssertEqual(samples[3], Float(16_384) / 32_767.0, accuracy: 0.0001)
        XCTAssertEqual(samples[4], 1.0)
    }

    func testFloatSamplesRejectNonRIFFWAVData() {
        var data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)
        data.append(pcm16Data(samples: [-1_000, 1_000]))

        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: data))
    }

    func testFloatSamplesReadPCMDataChunkAfterExtraWAVChunk() {
        let data = wavDataWithExtraChunk(samples: [-2_000, 2_000])

        let samples = VoiceInkPCM16Audio.floatSamples(fromWAVData: data)

        XCTAssertEqual(samples, [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testLittleEndianPCM16DataReadsPCMDataChunkAfterExtraWAVChunk() {
        let data = wavDataWithExtraChunk(samples: [-2_000, 2_000])

        XCTAssertEqual(
            VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: data),
            pcm16Data(samples: [-2_000, 2_000])
        )
    }

    func testWAVDataWritesCanonicalMono16kPCM16DataChunk() {
        let pcmData = pcm16Data(samples: [-2_000, 2_000])
        let wavData = VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcmData)

        XCTAssertEqual(VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: wavData), pcmData)
        XCTAssertEqual(VoiceInkPCM16Audio.floatSamples(fromWAVData: wavData), [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testWAVDataDropsTrailingPartialSampleByte() {
        let pcmData = Data([0x30, 0xF8, 0x7F])
        let wavData = VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcmData)

        XCTAssertEqual(
            VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: wavData),
            Data([0x30, 0xF8])
        )
    }

    func testFloatSamplesRejectUnsupportedRIFFWAVFormats() {
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], includeFmt: false)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], audioFormat: 3)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], channelCount: 2)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], sampleRate: 48_000)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], byteRate: 12_345)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], blockAlign: 4)))
        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: riffWAVData(samples: [-1_000, 1_000], bitsPerSample: 24)))
    }

    func testFloatSamplesRejectTooSmallWAVData() {
        let data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)

        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: data))
    }

    func testFloatSamplesCanReadWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("recording.wav")
        let data = wavData(samples: [-2_000, 2_000])
        try data.write(to: fileURL)

        let samples = try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: fileURL)

        XCTAssertEqual(samples, [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testFloatSamplesRejectTooSmallWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("empty.wav")
        try Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount).write(to: fileURL)

        XCTAssertNil(try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: fileURL))
    }

    func testLeveledFloatSamplesFromWAVDataBoostsQuietSpeechTowardTargetPeak() {
        let input = quietSpeechLikeSamples(peak: 100)
        let expected = input.map { Int16(Int($0) * 10) }

        let samples = VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: wavData(samples: input),
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(samples, expected.map { Float($0) / 32_767.0 })
    }

    func testLeveledFloatSamplesFromWAVDataLeavesNoiseFloorUnchanged() {
        let samples = VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: wavData(samples: [-4, 0, 4]),
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(samples, [
            Float(-4) / 32_767.0,
            0,
            Float(4) / 32_767.0
        ])
        XCTAssertNil(
            VoiceInkPCM16Audio.leveledFloatSamples(
                fromWAVData: Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount),
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            )
        )
    }

    func testWhisperAudioSamplesUseSharedLevelingDefaultsForWAVData() {
        let input = quietSpeechLikeSamples(peak: 1_000)
        let expected = input.map { Int16(Int($0) * 12) }

        let samples = VoiceInkWhisperAudioSamples.floatSamples(
            fromWAVData: wavData(samples: input)
        )

        XCTAssertEqual(samples, expected.map { Float($0) / 32_767.0 })
    }

    func testWhisperAudioSamplesCanReadWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("recording.wav")
        let input = quietSpeechLikeSamples(peak: 1_000)
        let expected = input.map { Int16(Int($0) * 12) }
        try wavData(samples: input).write(to: fileURL)

        let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: fileURL)

        XCTAssertEqual(samples, expected.map { Float($0) / 32_767.0 })
    }

    func testNormalizedMonoFloatSamplesPreserveSingleChannelNormalization() {
        let input: [Float] = [-0.25, 0.5, 1.0]

        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: 1,
            frameLength: input.count,
            sampleAt: { _, frame in input[frame] }
        )

        XCTAssertEqual(samples, [-0.25, 0.5, 1.0])
    }

    func testNormalizedMonoFloatSamplesAverageChannelsBeforeNormalizing() {
        let channels: [[Float]] = [
            [0.0, 0.5, 1.0],
            [0.0, 1.0, -1.0]
        ]

        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: channels.count,
            frameLength: channels[0].count,
            sampleAt: { channel, frame in channels[channel][frame] }
        )

        XCTAssertEqual(samples, [0.0, 1.0, 0.0])
    }

    func testNormalizedMonoFloatSamplesKeepSilenceAtZero() {
        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: 2,
            frameLength: 3,
            sampleAt: { _, _ in 0.0 }
        )

        XCTAssertEqual(samples, [0.0, 0.0, 0.0])
        XCTAssertEqual(
            VoiceInkPCM16Audio.normalizedMonoFloatSamples(
                channelCount: 0,
                frameLength: 3,
                sampleAt: { _, _ in 1.0 }
            ),
            []
        )
    }

    func testPCM16SamplesClampAndScaleFloatSamples() {
        let samples = VoiceInkPCM16Audio.pcm16Samples(
            fromFloatSamples: [-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0]
        )

        XCTAssertEqual(samples, [
            Int16(-32_767),
            Int16(-32_767),
            Int16(-16_383),
            Int16(0),
            Int16(16_383),
            Int16(32_767),
            Int16(32_767)
        ])
    }

    func testPCM16SamplesReturnEmptyForEmptyInput() {
        XCTAssertEqual(VoiceInkPCM16Audio.pcm16Samples(fromFloatSamples: []), [])
    }

    func testLeveledLittleEndianDataBoostsQuietSpeechTowardTargetPeak() {
        let input = quietSpeechLikeSamples(peak: 100)
        let expected = input.map { Int16(Int($0) * 10) }
        let data = pcm16Data(samples: input)

        let leveled = VoiceInkPCM16Audio.leveledLittleEndianData(
            data,
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(pcm16Samples(from: leveled), expected)
    }

    func testLeveledLittleEndianDataLeavesSilenceAndNoiseFloorUnchanged() {
        let silence = pcm16Data(samples: [0, 0, 0])
        let noiseFloor = pcm16Data(samples: [-4, 0, 4])

        XCTAssertEqual(
            VoiceInkPCM16Audio.leveledLittleEndianData(
                silence,
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            ),
            silence
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.leveledLittleEndianData(
                noiseFloor,
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            ),
            noiseFloor
        )
    }

    func testLeveledLittleEndianDataLeavesContinuousNoiseLikeAudioUnchanged() {
        let noiseSamples = Array(repeating: [Int16(-64), Int16(64)], count: 64).flatMap { $0 }
        let noise = pcm16Data(samples: noiseSamples)

        let leveled = VoiceInkPCM16Audio.leveledLittleEndianData(
            noise,
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(leveled, noise)
    }

    func testLeveledLittleEndianDataLeavesSingleImpulseUnchanged() {
        let impulse = pcm16Data(samples: sparseSamples([80: 100]))

        let leveled = VoiceInkPCM16Audio.leveledLittleEndianData(
            impulse,
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(leveled, impulse)
    }

    func testLeveledLittleEndianDataLeavesSparseImpulseTrainUnchanged() {
        var impulses: [Int: Int16] = [:]
        for index in stride(from: 20, through: 300, by: 20) {
            impulses[index] = index.isMultiple(of: 40) ? -100 : 100
        }
        let impulseTrain = pcm16Data(samples: sparseSamples(impulses, count: 1_000))

        let leveled = VoiceInkPCM16Audio.leveledLittleEndianData(
            impulseTrain,
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(leveled, impulseTrain)
    }

    func testConvertedMonoPCM16SampleCountUsesExistingTruncatedResamplePolicy() {
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 48_000,
                outputSampleRate: 16_000
            ),
            1
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 16_000,
                outputSampleRate: 16_000
            ),
            3
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 0,
                outputSampleRate: 16_000
            ),
            0
        )
    }

    func testWriteMonoPCM16SamplesAveragesInterleavedChannelsWithoutResampling() {
        let result = writeMonoPCM16Samples(
            input: [
                0.5, -0.5,
                1.0, 1.0,
                -2.0, -2.0
            ],
            frameCount: 3,
            channelCount: 2,
            inputSampleRate: 16_000,
            outputSampleRate: 16_000,
            outputCapacity: 3
        )

        XCTAssertEqual(result.written, 3)
        XCTAssertEqual(result.output, [0, 32_767, -32_768])
    }

    func testWriteMonoPCM16SamplesLinearlyResamplesInterleavedChannels() {
        let result = writeMonoPCM16Samples(
            input: [0.0, 1.0, 0.0],
            frameCount: 3,
            channelCount: 1,
            inputSampleRate: 2,
            outputSampleRate: 4,
            outputCapacity: 6
        )

        XCTAssertEqual(result.written, 6)
        XCTAssertEqual(result.output, [0, 16_383, 32_767, 16_383, 0, 0])
    }

    func testWriteMonoPCM16SamplesRejectsInsufficientCapacityAndInvalidInput() {
        let result = writeMonoPCM16Samples(
            input: [0.0, 1.0, 0.0],
            frameCount: 3,
            channelCount: 1,
            inputSampleRate: 2,
            outputSampleRate: 4,
            outputCapacity: 2,
            fillValue: 123
        )

        XCTAssertEqual(result.written, 0)
        XCTAssertEqual(result.output, [123, 123])
    }

    func testByteAndSampleCountsUseMono16kPCM16Format() {
        XCTAssertEqual(VoiceInkPCM16Audio.mono16kSampleRateHz, 16_000)
        XCTAssertEqual(VoiceInkPCM16Audio.mono16kSampleRate, 16_000.0)
        XCTAssertEqual(VoiceInkPCM16Audio.monoChannelCount, 1)
        XCTAssertEqual(VoiceInkPCM16Audio.bitsPerSample, 16)
        XCTAssertEqual(VoiceInkPCM16Audio.bytesPerSample, 2)
        XCTAssertFalse(VoiceInkPCM16Audio.isBigEndian)
        XCTAssertFalse(VoiceInkPCM16Audio.isFloatingPoint)
        XCTAssertEqual(VoiceInkPCM16Audio.byteCount(forMono16kDuration: 0.1), 3_200)
        XCTAssertEqual(VoiceInkPCM16Audio.sampleCount(forMono16kDuration: 0.1), 1_600)
    }

    func testMonoPCM16ChunksSplitDataOnSampleAlignedByteCounts() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 4)

        XCTAssertEqual(chunks, [
            Data([0, 1, 2, 3]),
            Data([4, 5, 6, 7])
        ])
    }

    func testMonoPCM16ChunksDropTrailingPartialSample() {
        let data = Data([0, 1, 2, 3, 4])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 4)

        XCTAssertEqual(chunks, [Data([0, 1, 2, 3])])
    }

    func testMonoPCM16ChunksAlignOddChunkSizeToSampleBoundary() {
        let data = Data([0, 1, 2, 3, 4, 5])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 3)

        XCTAssertEqual(chunks, [
            Data([0, 1]),
            Data([2, 3]),
            Data([4, 5])
        ])
    }

    func testMonoPCM16ChunksRejectEmptyDataAndTooSmallChunkSize() {
        XCTAssertEqual(VoiceInkPCM16Audio.monoPCM16Chunks(from: Data(), maxByteCount: 4), [])
        XCTAssertEqual(
            VoiceInkPCM16Audio.monoPCM16Chunks(from: Data([0, 1, 2, 3]), maxByteCount: 1),
            []
        )
    }

    private func pcm16Data(samples: [Int16]) -> Data {
        var data = Data()
        for sample in samples {
            let littleEndian = sample.littleEndian
            data.append(UInt8(truncatingIfNeeded: littleEndian))
            data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        }
        return data
    }

    private func pcm16Samples(from data: Data) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(data.count / VoiceInkPCM16Audio.bytesPerSample)

        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for byteIndex in stride(from: 0, to: data.count - 1, by: VoiceInkPCM16Audio.bytesPerSample) {
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                samples.append(Int16(bitPattern: rawValue))
            }
        }

        return samples
    }

    private func wavData(samples: [Int16]) -> Data {
        VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcm16Data(samples: samples))
    }

    private func quietSpeechLikeSamples(peak: Int16) -> [Int16] {
        sparseSamples([
            20: -peak,
            21: Int16(Int(peak) * -4 / 5),
            22: Int16(Int(peak) * -3 / 5),
            23: Int16(Int(peak) * -2 / 5),
            90: Int16(Int(peak) * 2 / 5),
            91: Int16(Int(peak) * 3 / 5),
            92: Int16(Int(peak) * 4 / 5),
            93: peak
        ])
    }

    private func sparseSamples(_ samplesByIndex: [Int: Int16], count: Int = 160) -> [Int16] {
        var samples = Array(repeating: Int16(0), count: count)
        for (index, sample) in samplesByIndex {
            samples[index] = sample
        }
        return samples
    }

    private func wavDataWithExtraChunk(samples: [Int16]) -> Data {
        let pcmData = pcm16Data(samples: samples)
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendUInt32LE(UInt32(4 + 24 + 12 + 8 + pcmData.count), to: &data)
        appendASCII("WAVE", to: &data)

        appendASCII("fmt ", to: &data)
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.monoChannelCount), to: &data)
        appendUInt32LE(UInt32(VoiceInkPCM16Audio.mono16kSampleRateHz), to: &data)
        appendUInt32LE(UInt32(VoiceInkPCM16Audio.mono16kSampleRateHz * VoiceInkPCM16Audio.bytesPerSample), to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.bytesPerSample), to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.bitsPerSample), to: &data)

        appendASCII("JUNK", to: &data)
        appendUInt32LE(3, to: &data)
        data.append(contentsOf: [0x12, 0x34, 0x56, 0])

        appendASCII("data", to: &data)
        appendUInt32LE(UInt32(pcmData.count), to: &data)
        data.append(pcmData)
        return data
    }

    private func riffWAVData(
        samples: [Int16],
        includeFmt: Bool = true,
        audioFormat: UInt16 = 1,
        channelCount: UInt16 = UInt16(VoiceInkPCM16Audio.monoChannelCount),
        sampleRate: UInt32 = UInt32(VoiceInkPCM16Audio.mono16kSampleRateHz),
        byteRate: UInt32? = nil,
        blockAlign: UInt16? = nil,
        bitsPerSample: UInt16 = UInt16(VoiceInkPCM16Audio.bitsPerSample)
    ) -> Data {
        let defaultBlockAlign = channelCount * ((bitsPerSample + 7) / 8)
        let formatBlockAlign = blockAlign ?? defaultBlockAlign
        let formatByteRate = byteRate ?? sampleRate * UInt32(defaultBlockAlign)
        let pcmData = pcm16Data(samples: samples)
        let formatChunkByteCount = includeFmt ? 24 : 0
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendUInt32LE(UInt32(4 + formatChunkByteCount + 8 + pcmData.count), to: &data)
        appendASCII("WAVE", to: &data)

        if includeFmt {
            appendASCII("fmt ", to: &data)
            appendUInt32LE(16, to: &data)
            appendUInt16LE(audioFormat, to: &data)
            appendUInt16LE(channelCount, to: &data)
            appendUInt32LE(sampleRate, to: &data)
            appendUInt32LE(formatByteRate, to: &data)
            appendUInt16LE(formatBlockAlign, to: &data)
            appendUInt16LE(bitsPerSample, to: &data)
        }

        appendASCII("data", to: &data)
        appendUInt32LE(UInt32(pcmData.count), to: &data)
        data.append(pcmData)
        return data
    }

    private func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 16))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 24))
    }

    private func writeMonoPCM16Samples(
        input: [Float32],
        frameCount: Int,
        channelCount: Int,
        inputSampleRate: Double,
        outputSampleRate: Double,
        outputCapacity: Int,
        fillValue: Int16 = 0
    ) -> (written: Int, output: [Int16]) {
        var output = Array(repeating: fillValue, count: outputCapacity)
        let written = input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                VoiceInkPCM16Audio.writeMonoPCM16Samples(
                    fromInterleavedFloat32Samples: inputBuffer.baseAddress!,
                    frameCount: frameCount,
                    channelCount: channelCount,
                    inputSampleRate: inputSampleRate,
                    outputSampleRate: outputSampleRate,
                    to: outputBuffer.baseAddress!,
                    outputCapacity: outputBuffer.count
                )
            }
        }
        return (written, output)
    }
}
