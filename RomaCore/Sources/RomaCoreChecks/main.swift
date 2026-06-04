import Foundation
import RomaCore

@main
struct RomaCoreChecks {
    static func main() async throws {
        try checkDefaultPreRollContract()
        try checkAudioDurationReporting()
        try checkPreRollBufferKeepsChronologicalSamples()
        try checkPCM16WAVFileWritesCanonicalHeader()
        try checkMiniaudioRecorderUsesSpeechPCMContract()
        try checkOpenAICompatibleMultipartBody()
        try checkWhisperCLITranscriptionService()
        try checkTranscriptionOutputFilter()
        try checkPostSTTCleanupTortureCorpus()
        try checkWordReplacementProcessor()
        try checkCommandLineOptions()
        try checkWindowsAgentConfiguration()
        try checkWindowsHotKeyProofDescriptor()
        try checkWindowsLowLevelKeyboardHookProofDescriptor()
        try await checkWindowsDictationRuntimeDescriptor()
        try checkWindowsClipboardPayloadIsCFUnicodeText()
        try checkWindowsDPAPISecretStoreContract()
        try checkWindowsPermissionSurface()
        try checkTranscriptionRequestMetadata()
        try await checkDictationPipelineTranscribesAndInserts()
        try await checkFakeAdaptersSatisfyCorePorts()
        try checkWindowsProofScriptContracts()
        try checkSourcesDoNotImportApplePlatformFrameworks()
    }

    private static func checkDefaultPreRollContract() throws {
        let configuration = PreRollConfiguration()

        try require(configuration.durationSeconds == 3, "default pre-roll should stay at 3 seconds")
        try require(configuration.outputFormat == .speechPCM16kMono, "default format should be speechPCM16kMono")
        try require(configuration.outputFormat.sampleRate == 16_000, "sample rate should be 16 kHz")
        try require(configuration.outputFormat.channelCount == 1, "channel count should be mono")
        try require(configuration.outputFormat.sampleFormat == .signedInteger16, "sample format should be Int16")
    }

    private static func checkAudioDurationReporting() throws {
        let mono = AudioChunkFormat(sampleRate: 16_000, channelCount: 1, sampleFormat: .signedInteger16)
        try require(mono.durationSeconds(sampleCount: 0) == 0, "empty PCM should be zero seconds")
        try require(mono.durationSeconds(sampleCount: 8_000) == 0.5, "mono PCM duration should derive from samples")

        let stereo = AudioChunkFormat(sampleRate: 48_000, channelCount: 2, sampleFormat: .signedInteger16)
        try require(
            stereo.durationSeconds(sampleCount: 96_000) == 1,
            "interleaved PCM duration should divide samples by channel count"
        )

        let recording = RecordedAudio(
            fileURL: URL(fileURLWithPath: "/tmp/roma-duration-proof.wav"),
            format: mono,
            sampleCount: 32_000,
            includedPreRollSampleCount: 8_000
        )
        try require(recording.durationSeconds == 2, "recording duration should derive from captured samples")
        try require(
            recording.includedPreRollSeconds == 0.5,
            "reported pre-roll should derive from captured pre-roll samples"
        )
    }

    private static func checkPreRollBufferKeepsChronologicalSamples() throws {
        let buffer = PCMPreRollBuffer(sampleRate: 5, seconds: 1)

        try require(buffer.capacitySamples == 5, "pre-roll capacity should derive from sample rate and seconds")
        try require(buffer.snapshotSamples().isEmpty, "empty pre-roll buffer should snapshot empty")

        buffer.append(samples: [1, 2, 3])
        try require(buffer.snapshotSamples() == [1, 2, 3], "pre-roll should preserve initial order")

        buffer.append(samples: [4, 5, 6])
        try require(
            buffer.snapshotSamples() == [2, 3, 4, 5, 6],
            "pre-roll should keep newest samples in chronological order after wrap"
        )
        try require(buffer.availableSampleCount == 5, "pre-roll should report capacity when full")

        let data = buffer.snapshotData()
        try require(data.count == 10, "pre-roll snapshot data should be Int16 PCM")
        let decodedData = try decodeInt16LittleEndian(data)
        try require(
            decodedData == [2, 3, 4, 5, 6],
            "pre-roll data should round-trip as little-endian Int16"
        )

        buffer.append(samples: [10, 11, 12, 13, 14, 15, 16])
        try require(
            buffer.snapshotSamples() == [12, 13, 14, 15, 16],
            "oversized append should keep last capacity samples"
        )

        buffer.clear()
        try require(buffer.availableSampleCount == 0, "clear should reset available samples")
        try require(buffer.snapshotSamples().isEmpty, "clear should reset snapshot")
    }

    private static func checkPCM16WAVFileWritesCanonicalHeader() throws {
        let samples: [Int16] = [0, 32_767, -32_768, 42]
        let format = AudioChunkFormat(sampleRate: 8_000, channelCount: 1, sampleFormat: .signedInteger16)
        let wavData = try PCM16WAVFile.makeData(samples: samples, format: format)

        try require(wavData.count == 52, "WAV data should include 44 byte header plus sample bytes")
        try require(try asciiString(wavData, offset: 0, count: 4) == "RIFF", "WAV should start with RIFF")
        try require(try readUInt32LittleEndian(wavData, offset: 4) == 44, "RIFF chunk size should include payload")
        try require(try asciiString(wavData, offset: 8, count: 4) == "WAVE", "WAV should identify WAVE format")
        try require(try asciiString(wavData, offset: 12, count: 4) == "fmt ", "WAV should include fmt chunk")
        try require(try readUInt32LittleEndian(wavData, offset: 16) == 16, "fmt chunk should be PCM size")
        try require(try readUInt16LittleEndian(wavData, offset: 20) == 1, "audio format should be PCM")
        try require(try readUInt16LittleEndian(wavData, offset: 22) == 1, "channel count should be mono")
        try require(try readUInt32LittleEndian(wavData, offset: 24) == 8_000, "sample rate should be encoded")
        try require(try readUInt32LittleEndian(wavData, offset: 28) == 16_000, "byte rate should be encoded")
        try require(try readUInt16LittleEndian(wavData, offset: 32) == 2, "block align should be encoded")
        try require(try readUInt16LittleEndian(wavData, offset: 34) == 16, "bits per sample should be Int16")
        try require(try asciiString(wavData, offset: 36, count: 4) == "data", "WAV should include data chunk")
        try require(try readUInt32LittleEndian(wavData, offset: 40) == 8, "data chunk size should match PCM bytes")
        try require(
            try decodeInt16LittleEndian(wavData.subdata(in: 44..<wavData.count)) == samples,
            "WAV payload should be little-endian Int16 PCM"
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roma-core-wav-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try PCM16WAVFile.write(samples: samples, to: outputURL, format: format)
        try require(try Data(contentsOf: outputURL) == wavData, "WAV file write should round-trip bytes")

        do {
            _ = try PCM16WAVFile.makeData(pcmData: Data([0]), format: format)
            throw CheckFailure("unaligned PCM should be rejected")
        } catch PCM16WAVFile.WriteError.pcmDataNotInt16Aligned(let byteCount) {
            try require(byteCount == 1, "unaligned PCM error should report byte count")
        }
    }

    private static func checkMiniaudioRecorderUsesSpeechPCMContract() throws {
        let recorder = MiniaudioCaptureRecorder()

        try require(MiniaudioCaptureRecorder.miniaudioVersion == "0.11.25", "miniaudio version should be pinned")
        try require(recorder.preRollConfiguration.durationSeconds == 3, "miniaudio recorder should keep 3 second pre-roll")
        try require(
            recorder.preRollConfiguration.outputFormat == .speechPCM16kMono,
            "miniaudio recorder should capture the shared speech PCM contract"
        )
    }

    private static func checkOpenAICompatibleMultipartBody() throws {
        let audioData = Data([0x52, 0x49, 0x46, 0x46])
        let multipart = OpenAICompatibleMultipartRequestBuilder.makeBody(
            audioData: audioData,
            fileName: "proof.wav",
            modelName: "whisper-large-v3-turbo",
            language: "en",
            prompt: "roma vocabulary",
            boundary: "Boundary-RomaProof"
        )
        let body = String(decoding: multipart.data, as: UTF8.self)

        try require(
            multipart.contentType == "multipart/form-data; boundary=Boundary-RomaProof",
            "multipart content type should include the boundary"
        )
        try require(body.contains("name=\"file\"; filename=\"proof.wav\""), "multipart should include the audio file field")
        try require(body.contains("Content-Type: audio/wav"), "multipart should mark the audio as WAV")
        try require(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"), "multipart should include model")
        try require(body.contains("name=\"response_format\"\r\n\r\njson"), "multipart should request JSON response")
        try require(body.contains("name=\"temperature\"\r\n\r\n0"), "multipart should keep deterministic temperature")
        try require(body.contains("name=\"language\"\r\n\r\nen"), "multipart should include explicit language")
        try require(body.contains("name=\"prompt\"\r\n\r\nroma vocabulary"), "multipart should include prompt")
        try require(multipart.data.range(of: audioData) != nil, "multipart should preserve raw audio bytes")
        try require(body.hasSuffix("--Boundary-RomaProof--\r\n"), "multipart should close the boundary")
    }

    private static func checkWhisperCLITranscriptionService() throws {
        let configuration = WhisperCLITranscriptionConfiguration(
            executableURL: URL(fileURLWithPath: "/tools/whisper-cli"),
            modelURL: URL(fileURLWithPath: "/models/ggml-base.en.bin"),
            outputDirectoryURL: URL(fileURLWithPath: "/tmp/roma-whisper", isDirectory: true),
            extraArguments: ["--beam-size", "1"],
            timeoutSeconds: 42
        )
        let request = TranscriptionRequest(
            audioURL: URL(fileURLWithPath: "/tmp/proof.wav"),
            model: TranscriptionModelDescriptor(
                name: "ggml-base.en.bin",
                displayName: "Base EN",
                provider: .whisper
            ),
            language: "en",
            prompt: "roma just talk"
        )
        let invocation = configuration.makeInvocation(
            for: request,
            outputBaseName: "local-proof"
        )

        try require(invocation.executableURL.path == "/tools/whisper-cli", "whisper CLI invocation should keep executable")
        try require(
            invocation.arguments == [
                "-m", "/models/ggml-base.en.bin",
                "-f", "/tmp/proof.wav",
                "-nt",
                "-np",
                "-oj",
                "-of", "/tmp/roma-whisper/local-proof",
                "-l", "en",
                "--prompt", "roma just talk",
                "--beam-size", "1"
            ],
            "whisper CLI invocation should map model, audio, JSON output, hints, and extra args"
        )
        try require(
            invocation.jsonOutputURL.path == "/tmp/roma-whisper/local-proof.json",
            "whisper CLI invocation should derive JSON output path"
        )
        try require(configuration.timeoutSeconds == 42, "whisper CLI config should keep timeout")

        let topLevelJSON = Data(#"{"text":" roma just talk ","language":"en","duration":1.5}"#.utf8)
        let topLevelResult = try WhisperCLITranscriptionService.decodeJSONResult(from: topLevelJSON)
        try require(
            topLevelResult == TranscriptionResult(text: "roma just talk", language: "en", durationSeconds: 1.5),
            "whisper CLI parser should decode simple text JSON"
        )

        let segmentedJSON = Data(
            #"{"result":{"language":"en","duration":1.25},"transcription":[{"text":" roma "},{"text":"just talk"}]}"#.utf8
        )
        let segmentedResult = try WhisperCLITranscriptionService.decodeJSONResult(from: segmentedJSON)
        try require(
            segmentedResult == TranscriptionResult(text: "roma just talk", language: "en", durationSeconds: 1.25),
            "whisper CLI parser should decode segmented whisper.cpp JSON"
        )

        do {
            _ = try WhisperCLITranscriptionService.decodeJSONResult(from: Data(#"{"text":"   "}"#.utf8))
            throw CheckFailure("whisper CLI parser should reject empty text")
        } catch WhisperCLITranscriptionError.noTranscriptionReturned {
        }
    }

    private static func checkTranscriptionOutputFilter() throws {
        let midSentenceContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "...so this")
        let listIntroContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Tasks:")
        let sentenceStartContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
        let selectedMidSentenceContext = RomaTranscriptionOutputFilter.TextInsertionContext(
            precedingText: "Use ",
            selectedText: "old"
        )

        try require(
            RomaTranscriptionOutputFilter.filter(
                "hmm.... eh... I I think think this this works.",
                removesFillerWords: true
            ) == "I think this works.",
            "shared filter should remove pause noise and repeated words"
        )
        try require(
            RomaTranscriptionOutputFilter.filter("Open quote hello comma world close quote.") == "\"hello, world\".",
            "shared filter should apply spoken enclosure and punctuation commands"
        )
        try require(
            RomaTranscriptionOutputFilter.filter("Open https colon slash slash docs dot example dot com slash api.") ==
                "Open https://docs.example.com/api",
            "shared filter should apply guarded spoken URL cleanup"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.", context: midSentenceContext) == "model",
            "shared insertion polish should lowercase mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.\"", context: midSentenceContext) == "model",
            "shared insertion polish should remove trailing generated quotes after final punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!\"", context: midSentenceContext) == "model",
            "shared insertion polish should remove trailing generated quotes after emphatic punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!”", context: midSentenceContext) == "model",
            "shared insertion polish should remove trailing smart quotes after emphatic punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("The Model.", context: midSentenceContext) ==
                "the model",
            "shared insertion polish should lowercase title-cased mid-sentence phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("The API.", context: midSentenceContext) == "the API",
            "shared insertion polish should preserve acronyms inside mid-sentence phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The LLM Router.",
                context: midSentenceContext
            ) == "the LLM router",
            "shared insertion polish should lowercase generated tech nouns after acronyms"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The iOS App.",
                context: midSentenceContext
            ) == "the iOS app",
            "shared insertion polish should lowercase generated tech nouns after mixed-case product tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The URL Parser.",
                context: midSentenceContext
            ) == "the URL parser",
            "shared insertion polish should lowercase generated parser nouns after acronyms"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("New York.", context: midSentenceContext) == "New York",
            "shared insertion polish should preserve proper-name mid-sentence phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Felix.", context: midSentenceContext) == "Felix",
            "shared insertion polish should preserve proper-name mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Felix is ready.", context: midSentenceContext) ==
                "Felix is ready",
            "shared insertion polish should preserve proper-name mid-sentence phrase starts"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("U.S.", context: midSentenceContext) == "U.S.",
            "shared insertion polish should preserve abbreviation periods in mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[U.S.]", context: midSentenceContext) == "U.S.",
            "shared insertion polish should preserve abbreviation periods in bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[Ph.D.]", context: midSentenceContext) == "Ph.D.",
            "shared insertion polish should preserve mixed abbreviation periods in bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "J.R.R. Tolkien.",
                context: midSentenceContext
            ) == "J.R.R. Tolkien",
            "shared insertion polish should strip trailing periods after internal initial abbreviations"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The appointment with Dr. Smith.",
                context: midSentenceContext
            ) == "the appointment with Dr. Smith",
            "shared insertion polish should strip trailing periods after embedded honorific abbreviations"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy exclamation marks from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model?", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy question marks from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model -", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy hyphens from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model —", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy dashes from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model /", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy slashes from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model \\", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy backslashes from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model |", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy pipe symbols from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model //", context: midSentenceContext) == "model",
            "shared insertion polish should remove repeated noisy slash symbols from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model ||", context: midSentenceContext) == "model",
            "shared insertion polish should remove repeated noisy pipe symbols from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model。", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy full-width periods from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model？", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy full-width question marks from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model！", context: midSentenceContext) == "model",
            "shared insertion polish should remove noisy full-width exclamation marks from mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("What?", context: midSentenceContext) == "what?",
            "shared insertion polish should preserve one-word question fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"Model!\"", context: midSentenceContext) == "\"model\"",
            "shared insertion polish should trim noisy marks inside quoted short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("(Model!)", context: midSentenceContext) == "(model)",
            "shared insertion polish should trim noisy marks inside parenthesized short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("{Model?}", context: midSentenceContext) == "{model}",
            "shared insertion polish should trim noisy marks inside braced short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"Model!\".", context: midSentenceContext) == "\"model\"",
            "shared insertion polish should trim trailing periods after quoted noisy fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("(Model!).", context: midSentenceContext) == "(model)",
            "shared insertion polish should trim trailing periods after parenthesized noisy fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("{Model?}.", context: midSentenceContext) == "{model}",
            "shared insertion polish should trim trailing periods after braced noisy fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("'Model.'", context: midSentenceContext) == "'model'",
            "shared insertion polish should trim noisy periods inside single-quoted short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"What?\".", context: midSentenceContext) == "\"what?\"",
            "shared insertion polish should preserve quoted one-word questions"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("state-of-the-art", context: midSentenceContext) ==
                "state-of-the-art",
            "shared insertion polish should preserve internal hyphens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("/users", context: midSentenceContext) == "/users",
            "shared insertion polish should preserve compact path fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("docs/", context: midSentenceContext) == "docs/",
            "shared insertion polish should preserve trailing path slash fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("docs//", context: midSentenceContext) == "docs//",
            "shared insertion polish should preserve compact double-slash fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("... [Model.]", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap ellipsis-prefixed bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("— [Model.]", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap dash-prefixed bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("| [Model.]", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap pipe-prefixed bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"[Model.]\"", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap quoted square-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("([Model.])", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap parenthesized square-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<Model.>", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy angle-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "< A final word. >",
                context: midSentenceContext
            ) == "a final word",
            "shared insertion polish should unwrap spaced angle-bracketed phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<[Model.]>", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap angle-wrapped square-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<|Model.|>", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap angle-wrapped pipe fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<model>", context: midSentenceContext) == "<model>",
            "shared insertion polish should preserve literal angle tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("*Model.*", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy starred fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("_Model._", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy underscored fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("**Model.**", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy bold markdown fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("__Model.__", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy bold underscore fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("*model*", context: midSentenceContext) == "*model*",
            "shared insertion polish should preserve literal starred tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("_model_", context: midSentenceContext) == "_model_",
            "shared insertion polish should preserve literal underscored tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("• Model.", context: midSentenceContext) == "model",
            "shared insertion polish should remove leading bullet fragment noise"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1. Model.", context: midSentenceContext) == "model",
            "shared insertion polish should remove generated numbered fragment markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1) Model.", context: midSentenceContext) == "model",
            "shared insertion polish should remove generated parenthesized number markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("# Model.", context: midSentenceContext) == "model",
            "shared insertion polish should remove generated heading fragment markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1. Model.", context: listIntroContext) == "1. model",
            "shared insertion polish should preserve numbered markers after list introducers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("# Model.", context: listIntroContext) == "# model",
            "shared insertion polish should preserve heading markers after list introducers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("【Model.】", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap corner-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("【Model!】", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap noisy emphatic corner-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("《Model.》", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap book-title-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("（Model.）", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap full-width parenthesized fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("... 【Model.】", context: midSentenceContext) == "model",
            "shared insertion polish should unwrap ellipsis-prefixed corner-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\ndetails.", context: midSentenceContext) == "\ndetails",
            "shared insertion polish should preserve leading line breaks"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\n\nDetails.", context: midSentenceContext) == "\n\nDetails",
            "shared insertion polish should preserve leading paragraph breaks"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("model", context: midSentenceContext) == " model",
            "shared insertion spacing should add a leading space after words"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing(
                "1. finish the report\n2. send the slides",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Tasks:")
            ) == "\n1. finish the report\n2. send the slides",
            "shared insertion spacing should start numbered lists on a new line"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing(
                "- first item\n- second item",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Tasks:")
            ) == "\n- first item\n- second item",
            "shared insertion spacing should start bullet lists on a new line"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing(
                "\n1. finish the report",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Tasks:")
            ) == "\n1. finish the report",
            "shared insertion spacing should not double-prefix existing list newlines"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.", context: selectedMidSentenceContext) == "model",
            "shared insertion polish should lowercase selected mid-sentence replacements"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("model", context: selectedMidSentenceContext) == "model",
            "shared insertion spacing should not add a leading space when replacing selected text"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.", context: sentenceStartContext) == "Model",
            "shared insertion polish should preserve sentence-start casing"
        )
        try require(
            RomaTranscriptionOutputFilter.applyCleanupPreferences(
                "Model.",
                punctuationMode: .removeTrailingPeriod,
                shouldLowercase: true
            ) == "model",
            "shared cleanup preferences should remove a trailing period and lowercase"
        )
    }

    private static func checkPostSTTCleanupTortureCorpus() throws {
        let filterCases: [(input: String, expected: String, note: String)] = [
            (
                "hmm.... eh... I I think think this this works.",
                "I think this works.",
                "pause noise and repeated words"
            ),
            (
                "ahem... I think this works.",
                "I think this works.",
                "leading ahem pause filler"
            ),
            (
                "ehm... I think this works.",
                "I think this works.",
                "leading ehm pause filler"
            ),
            (
                "I, I think this works.",
                "I think this works.",
                "punctuated repeated word"
            ),
            (
                "This this.",
                "This.",
                "final repeated word punctuation"
            ),
            (
                "No, no, this is wrong.",
                "No, no, this is wrong.",
                "preserved punctuated repeated word"
            ),
            (
                "I - I think this works.",
                "I think this works.",
                "separator repeated pronoun"
            ),
            (
                "I-I think this works.",
                "I think this works.",
                "tight separator repeated pronoun"
            ),
            (
                "This — this works.",
                "This works.",
                "dash separated repeated word"
            ),
            (
                "This-this works.",
                "This works.",
                "tight dash separated repeated word"
            ),
            (
                "x - x is zero.",
                "x - x is zero.",
                "single-letter separator repeat guard"
            ),
            (
                "x-x is zero.",
                "x-x is zero.",
                "tight single-letter separator repeat guard"
            ),
            (
                "No - no, this is wrong.",
                "No - no, this is wrong.",
                "preserved separator repeated word"
            ),
            (
                "No-no, this is wrong.",
                "No-no, this is wrong.",
                "tight preserved separator repeated word"
            ),
            (
                "I think this works! I think this works.",
                "I think this works.",
                "duplicate short sentence with mismatched punctuation"
            ),
            (
                "I think this works. I think this works!",
                "I think this works.",
                "duplicate short sentence with trailing emphatic punctuation"
            ),
            (
                "I think this works. I think this works",
                "I think this works.",
                "duplicate short sentence with missing trailing punctuation"
            ),
            (
                "Hello world! Hello world.",
                "Hello world.",
                "duplicate short sentence with leading emphatic punctuation"
            ),
            (
                "No? No.",
                "No? No.",
                "one-word repeated question guard"
            ),
            (
                "So this. Model.",
                "So this model.",
                "generated sentence boundary before short continuation fragment"
            ),
            (
                "So this. Model",
                "So this model",
                "generated sentence boundary before short continuation fragment without terminal punctuation"
            ),
            (
                "So this. The model",
                "So this the model",
                "generated sentence boundary before short article continuation fragment without terminal punctuation"
            ),
            (
                "So this. Model final word",
                "So this model final word",
                "generated sentence boundary before multi-word continuation fragment without terminal punctuation"
            ),
            (
                "So this. [Model.]",
                "So this model.",
                "generated sentence boundary before bracketed short continuation fragment"
            ),
            (
                "So this, [Model.]",
                "So this model.",
                "generated comma before bracketed short continuation fragment"
            ),
            (
                "So this - [Model.]",
                "So this model.",
                "generated dash before bracketed short continuation fragment"
            ),
            (
                "So this: [Model.]",
                "So this model.",
                "generated colon before bracketed short continuation fragment"
            ),
            (
                "So this. \"[Model.]\"",
                "So this model.",
                "generated sentence boundary before quoted bracketed short continuation fragment"
            ),
            (
                "So this. ([Model.])",
                "So this model.",
                "generated sentence boundary before parenthesized bracketed short continuation fragment"
            ),
            (
                "So this. <[Model.]>",
                "So this model.",
                "generated sentence boundary before angle-wrapped bracketed short continuation fragment"
            ),
            (
                "So this. 【Model.】",
                "So this model.",
                "generated sentence boundary before full-width bracketed short continuation fragment"
            ),
            (
                "So this. *Model.*",
                "So this model.",
                "generated sentence boundary before markdown-wrapped short continuation fragment"
            ),
            (
                "So this, \"[Model.]\"",
                "So this model.",
                "generated comma before quoted bracketed short continuation fragment"
            ),
            (
                "I think this is. [A final word.]",
                "I think this is a final word.",
                "generated sentence boundary before bracketed short continuation phrase"
            ),
            (
                "I live in. [U.S.]",
                "I live in U.S.",
                "generated sentence boundary before bracketed abbreviation fragment"
            ),
            (
                "It is. What?",
                "It is. What?",
                "single-word generated question boundary guard"
            ),
            (
                "It is. [What?]",
                "It is. [What?]",
                "bracketed single-word generated question boundary guard"
            ),
            (
                "It works. Model",
                "It works. Model",
                "complete sentence before unpunctuated generated fragment guard"
            ),
            (
                "mm-hmm... uh-huh, I think so.",
                "I think so.",
                "hyphenated pause sounds"
            ),
            (
                "um yeah this works.",
                "this works.",
                "leading pause plus yeah acknowledgement filler"
            ),
            (
                "hmm yes this works.",
                "this works.",
                "leading pause plus yes acknowledgement filler"
            ),
            (
                "uh sure this works.",
                "this works.",
                "leading pause plus sure acknowledgement filler"
            ),
            (
                "eh yep okay this works.",
                "this works.",
                "leading pause plus yep acknowledgement chain before content"
            ),
            (
                "hmm yes so this works.",
                "this works.",
                "leading pause plus yes-so filler chain before content"
            ),
            (
                "um yeah.",
                "",
                "standalone pause plus yeah acknowledgement filler"
            ),
            (
                "hmm okay.",
                "",
                "standalone pause plus okay acknowledgement filler"
            ),
            (
                "hmm yes.",
                "",
                "standalone pause plus yes acknowledgement filler"
            ),
            (
                "uh sure.",
                "",
                "standalone pause plus sure acknowledgement filler"
            ),
            (
                "uh all right.",
                "",
                "standalone pause plus all right acknowledgement filler"
            ),
            (
                "uh okay yeah.",
                "",
                "standalone pause plus acknowledgement chain filler"
            ),
            (
                "eh yep okay.",
                "",
                "standalone pause plus yep acknowledgement chain filler"
            ),
            (
                "hmm all right yeah.",
                "",
                "standalone pause plus multi-word acknowledgement chain filler"
            ),
            (
                "um right okay.",
                "",
                "standalone pause plus reversed acknowledgement chain filler"
            ),
            (
                "um yeah right.",
                "yeah right.",
                "standalone pause plus literal yeah-right guard"
            ),
            (
                "uh okay I think this works.",
                "I think this works.",
                "leading pause plus okay acknowledgement filler"
            ),
            (
                "uh okay yeah this works.",
                "this works.",
                "leading pause plus acknowledgement chain before content"
            ),
            (
                "hmm all right this works.",
                "this works.",
                "leading pause plus all right acknowledgement filler"
            ),
            (
                "This works, um yes.",
                "This works.",
                "terminal pause plus yes acknowledgement filler"
            ),
            (
                "This works, uh sure.",
                "This works.",
                "terminal pause plus sure acknowledgement filler"
            ),
            (
                "Yes, this works.",
                "Yes, this works.",
                "no-pause yes acknowledgement prose guard"
            ),
            (
                "Sure this works.",
                "Sure this works.",
                "no-pause sure acknowledgement prose guard"
            ),
            (
                "hmm — I think this works.",
                "I think this works.",
                "leading pause filler with dash separator"
            ),
            (
                "eh... : this works.",
                "this works.",
                "leading pause filler with colon separator"
            ),
            (
                "— I think this works.",
                "— I think this works.",
                "leading dash without filler guard"
            ),
            (
                "- item one.",
                "- item one",
                "leading list marker without filler guard"
            ),
            (
                "This, um, works.",
                "This works.",
                "embedded comma pause filler"
            ),
            (
                "This, ahem, works.",
                "This works.",
                "embedded ahem pause filler"
            ),
            (
                "This; eh, works.",
                "This works.",
                "embedded semicolon pause filler"
            ),
            (
                "This, ehm, works.",
                "This works.",
                "embedded ehm pause filler"
            ),
            (
                "This… hmm, works.",
                "This works.",
                "embedded ellipsis pause filler"
            ),
            (
                "[blank_audio]",
                "",
                "standalone bracketed underscored non-speech artifact"
            ),
            (
                "[U.S.]",
                "U.S.",
                "standalone bracketed abbreviation guard"
            ),
            (
                "[Ph.D.]",
                "Ph.D.",
                "standalone bracketed mixed abbreviation guard"
            ),
            (
                "[humming].",
                "",
                "standalone bracketed non-speech artifact with outer punctuation"
            ),
            (
                "<|nospeech|>",
                "",
                "standalone nospeech special token"
            ),
            (
                "Use <|no_speech|> now.",
                "Use now.",
                "inline no speech special token"
            ),
            (
                "Use <|silence|> now.",
                "Use now.",
                "inline silence special token"
            ),
            (
                "Use <|endoftext|> now.",
                "Use now.",
                "inline endoftext special token"
            ),
            (
                "Use <|startoftranscript|> now.",
                "Use now.",
                "inline startoftranscript special token"
            ),
            (
                "Use <|notimestamps|> now.",
                "Use now.",
                "inline notimestamps special token"
            ),
            (
                "Use <|transcribe|> now.",
                "Use now.",
                "inline transcribe special token"
            ),
            (
                "Use <|en|> now.",
                "Use now.",
                "inline english language special token"
            ),
            (
                "Use <|zh|> now.",
                "Use now.",
                "inline chinese language special token"
            ),
            (
                "Use <|haw|> now.",
                "Use now.",
                "inline three-letter language special token"
            ),
            (
                "Use <|0.00|> now.",
                "Use now.",
                "inline timestamp special token"
            ),
            (
                "Use <model> now.",
                "Use <model> now.",
                "angle token literal guard"
            ),
            (
                "Use <|model|> now.",
                "Use <|model|> now.",
                "unknown pipe token literal guard"
            ),
            (
                "[speaker 1]",
                "",
                "standalone bracketed speaker number label"
            ),
            (
                "(Speaker_00)",
                "",
                "standalone bracketed speaker underscore label"
            ),
            (
                "Use [cough] now.",
                "Use now.",
                "bracketed cough artifact"
            ),
            (
                "Use {sighing} now.",
                "Use now.",
                "bracketed sigh artifact"
            ),
            (
                "Use [humming] now.",
                "Use now.",
                "bracketed humming artifact"
            ),
            (
                "Use [humming softly] now.",
                "Use now.",
                "bracketed humming descriptor artifact"
            ),
            (
                "Use (mumbling) now.",
                "Use now.",
                "bracketed mumbling artifact"
            ),
            (
                "Use (mumbling indistinctly) now.",
                "Use now.",
                "bracketed mumbling descriptor artifact"
            ),
            (
                "Use [unintelligible] now.",
                "Use now.",
                "bracketed unintelligible artifact"
            ),
            (
                "Use (crosstalk) now.",
                "Use now.",
                "bracketed crosstalk artifact"
            ),
            (
                "Use [blank audio] now.",
                "Use now.",
                "bracketed blank audio artifact"
            ),
            (
                "Use [blank_audio] now.",
                "Use now.",
                "bracketed underscored blank audio artifact"
            ),
            (
                "Use [no_speech] now.",
                "Use now.",
                "bracketed underscored no speech artifact"
            ),
            (
                "Use [no-speech] now.",
                "Use now.",
                "bracketed hyphenated no speech artifact"
            ),
            (
                "Use [empty_audio] now.",
                "Use now.",
                "bracketed underscored empty audio artifact"
            ),
            (
                "Use [no sound] now.",
                "Use now.",
                "bracketed no sound artifact"
            ),
            (
                "Use [silent] now.",
                "Use now.",
                "bracketed silent artifact"
            ),
            (
                "Use [silence continues] now.",
                "Use now.",
                "bracketed silence descriptor artifact"
            ),
            (
                "Use [speaking foreign language] now.",
                "Use now.",
                "bracketed speaking foreign language artifact"
            ),
            (
                "Use [speaking-foreign-language] now.",
                "Use now.",
                "bracketed hyphenated speaking foreign language artifact"
            ),
            (
                "Use [laughing] now.",
                "Use now.",
                "bracketed laughing artifact"
            ),
            (
                "Use [keyboard typing] now.",
                "Use now.",
                "bracketed keyboard typing artifact"
            ),
            (
                "Use [keyboard typing softly] now.",
                "Use now.",
                "bracketed keyboard typing descriptor artifact"
            ),
            (
                "Use [typing sounds] now.",
                "Use now.",
                "bracketed typing sounds artifact"
            ),
            (
                "Use [keyboard-typing] now.",
                "Use now.",
                "bracketed hyphenated keyboard typing artifact"
            ),
            (
                "Use [phone ringing] now.",
                "Use now.",
                "bracketed phone ringing artifact"
            ),
            (
                "Use (phone_ringing) now.",
                "Use now.",
                "bracketed underscored phone ringing artifact"
            ),
            (
                "Use [phone ringing loudly] now.",
                "Use now.",
                "bracketed phone ringing descriptor artifact"
            ),
            (
                "Use [beeping] now.",
                "Use now.",
                "bracketed beeping artifact"
            ),
            (
                "Use [beep sounds] now.",
                "Use now.",
                "bracketed beep sounds artifact"
            ),
            (
                "Use [music playing] now.",
                "Use now.",
                "bracketed music playing artifact"
            ),
            (
                "Use [background chatter] now.",
                "Use now.",
                "bracketed background chatter artifact"
            ),
            (
                "Use [crowd noise] now.",
                "Use now.",
                "bracketed crowd noise artifact"
            ),
            (
                "Use [static noise] now.",
                "Use now.",
                "bracketed static noise artifact"
            ),
            (
                "Use [speaker 1] now.",
                "Use now.",
                "bracketed speaker number label"
            ),
            (
                "Use (Speaker_00) now.",
                "Use now.",
                "bracketed speaker underscore label"
            ),
            (
                "Use [00:00] now.",
                "Use now.",
                "bracketed transcript timestamp"
            ),
            (
                "Use (00:01:12) now.",
                "Use now.",
                "parenthesized transcript timestamp"
            ),
            (
                "Use [00:01 - 00:03] now.",
                "Use now.",
                "bracketed transcript timestamp range"
            ),
            (
                "Use [00:00 timestamp] now.",
                "Use now.",
                "bracketed transcript timestamp label"
            ),
            (
                "sighs... I think this works.",
                "I think this works.",
                "leading unbracketed sigh artifact"
            ),
            (
                "coughs, this works.",
                "this works.",
                "leading unbracketed cough artifact"
            ),
            (
                "Laughs. this should stay.",
                "this should stay.",
                "leading unbracketed laugh artifact"
            ),
            (
                "This works. coughs.",
                "This works.",
                "terminal unbracketed cough artifact"
            ),
            (
                "clears throat. I think this works.",
                "I think this works.",
                "leading unbracketed clears throat artifact"
            ),
            (
                "background noise. This is ready.",
                "This is ready.",
                "leading unbracketed background noise artifact"
            ),
            (
                "ambient noise. Continue now.",
                "Continue now.",
                "leading unbracketed ambient noise artifact"
            ),
            (
                "background sounds. Continue now.",
                "Continue now.",
                "leading unbracketed background sounds artifact"
            ),
            (
                "inaudible. please continue.",
                "please continue.",
                "leading unbracketed inaudible artifact"
            ),
            (
                "no speech. Use this.",
                "Use this.",
                "leading unbracketed no speech artifact"
            ),
            (
                "music playing. Let's continue.",
                "Let's continue.",
                "leading unbracketed music playing artifact"
            ),
            (
                "keyboard typing. Use this.",
                "Use this.",
                "leading unbracketed keyboard typing artifact"
            ),
            (
                "phone ringing. Call me back.",
                "Call me back.",
                "leading unbracketed phone ringing artifact"
            ),
            (
                "static noise. Continue now.",
                "Continue now.",
                "leading unbracketed static noise artifact"
            ),
            (
                "foreign language. Continue now.",
                "Continue now.",
                "leading unbracketed foreign language artifact"
            ),
            (
                "speaking foreign language. Continue now.",
                "Continue now.",
                "leading unbracketed speaking foreign language artifact"
            ),
            (
                "The background noise matters.",
                "The background noise matters.",
                "unbracketed background noise prose guard"
            ),
            (
                "Ambient noise levels matter.",
                "Ambient noise levels matter.",
                "unbracketed ambient noise prose guard"
            ),
            (
                "Background sounds can help focus.",
                "Background sounds can help focus.",
                "unbracketed background sounds prose guard"
            ),
            (
                "Clears throat exercises help.",
                "Clears throat exercises help.",
                "unbracketed clears throat prose guard"
            ),
            (
                "Music playing helps focus.",
                "Music playing helps focus.",
                "unbracketed music playing prose guard"
            ),
            (
                "Keyboard typing speed matters.",
                "Keyboard typing speed matters.",
                "unbracketed keyboard typing prose guard"
            ),
            (
                "The phone ringing woke me.",
                "The phone ringing woke me.",
                "unbracketed phone ringing prose guard"
            ),
            (
                "Static noise matters.",
                "Static noise matters.",
                "unbracketed static noise prose guard"
            ),
            (
                "The foreign language class starts soon.",
                "The foreign language class starts soon.",
                "unbracketed foreign language prose guard"
            ),
            (
                "Speaking foreign language phrases helps.",
                "Speaking foreign language phrases helps.",
                "unbracketed speaking foreign language prose guard"
            ),
            (
                "The dog coughs.",
                "The dog coughs.",
                "unbracketed cough verb guard"
            ),
            (
                "Laughs are contagious.",
                "Laughs are contagious.",
                "unbracketed laugh noun guard"
            ),
            (
                "Use [breath control] now.",
                "Use [breath control] now.",
                "bracketed literal breath phrase guard"
            ),
            (
                "Use [unclear goal] now.",
                "Use [unclear goal] now.",
                "bracketed literal unclear phrase guard"
            ),
            (
                "Use [speech notes] now.",
                "Use [speech notes] now.",
                "bracketed literal speech phrase guard"
            ),
            (
                "Use [sound design] now.",
                "Use [sound design] now.",
                "bracketed literal sound phrase guard"
            ),
            (
                "Use [music theory] now.",
                "Use [music theory] now.",
                "bracketed literal music phrase guard"
            ),
            (
                "Use [background color] now.",
                "Use [background color] now.",
                "bracketed literal background phrase guard"
            ),
            (
                "Use [crowd size] now.",
                "Use [crowd size] now.",
                "bracketed literal crowd phrase guard"
            ),
            (
                "Use [mumble rap] now.",
                "Use [mumble rap] now.",
                "bracketed literal mumble phrase guard"
            ),
            (
                "Use [silence policy] now.",
                "Use [silence policy] now.",
                "bracketed literal silence phrase guard"
            ),
            (
                "Use [static site] now.",
                "Use [static site] now.",
                "bracketed literal static phrase guard"
            ),
            (
                "Use [ringing endorsement] now.",
                "Use [ringing endorsement] now.",
                "bracketed literal ringing phrase guard"
            ),
            (
                "Use [beep test] now.",
                "Use [beep test] now.",
                "bracketed literal beep phrase guard"
            ),
            (
                "Use [12:30 PM] now.",
                "Use [12:30 PM] now.",
                "bracketed literal time phrase guard"
            ),
            (
                "Use [12:30] now.",
                "Use [12:30] now.",
                "bracketed literal clock time guard"
            ),
            (
                "Use [chapter 00:00] now.",
                "Use [chapter 00:00] now.",
                "bracketed timestamp prose guard"
            ),
            (
                "Use chapter 00:00 now.",
                "Use chapter 00:00 now.",
                "inline timecode punctuation guard"
            ),
            (
                "Use [foreign language class] now.",
                "Use [foreign language class] now.",
                "bracketed literal foreign language phrase guard"
            ),
            (
                "Use [typing speed] now.",
                "Use [typing speed] now.",
                "bracketed literal typing phrase guard"
            ),
            (
                "Use [typing-speed] now.",
                "Use [typing-speed] now.",
                "bracketed literal hyphenated typing phrase guard"
            ),
            (
                "Use [speaker notes] now.",
                "Use [speaker notes] now.",
                "bracketed literal speaker phrase guard"
            ),
            (
                "I was like going there.",
                "I was going there.",
                "unpunctuated like filler"
            ),
            (
                "We are kind of almost done.",
                "We are almost done.",
                "unpunctuated kind of hedge filler"
            ),
            (
                "This is sort of really close.",
                "This is really close.",
                "unpunctuated sort of hedge filler"
            ),
            (
                "It is kinda basically ready.",
                "It is basically ready.",
                "unpunctuated kinda hedge filler"
            ),
            (
                "They are sorta just waiting.",
                "They are just waiting.",
                "unpunctuated sorta hedge filler"
            ),
            (
                "You know, this works.",
                "this works.",
                "leading you know filler"
            ),
            (
                "I mean, this works.",
                "this works.",
                "leading i mean filler"
            ),
            (
                "You know this works.",
                "this works.",
                "unpunctuated leading you know filler before this clause"
            ),
            (
                "I mean this works.",
                "this works.",
                "unpunctuated leading i mean filler before this clause"
            ),
            (
                "You know what I mean this works.",
                "this works.",
                "unpunctuated leading you know what i mean filler before this clause"
            ),
            (
                "Well, this works.",
                "this works.",
                "punctuated leading well filler before this clause"
            ),
            (
                "Well this works.",
                "this works.",
                "unpunctuated leading well filler before this clause"
            ),
            (
                "Well I think this works.",
                "I think this works.",
                "unpunctuated leading well filler before i clause"
            ),
            (
                "Well, I mean, this works.",
                "this works.",
                "leading well i mean filler chain"
            ),
            (
                "Well, you know this works.",
                "this works.",
                "leading well you know filler chain"
            ),
            (
                "Okay well this works.",
                "this works.",
                "leading okay well filler chain"
            ),
            (
                "Okay, well, this works.",
                "this works.",
                "punctuated leading okay well filler chain"
            ),
            (
                "Yeah well this works.",
                "this works.",
                "leading yeah well filler chain"
            ),
            (
                "Right, well, I think this works.",
                "I think this works.",
                "leading right well filler chain"
            ),
            (
                "Okay yeah this works.",
                "this works.",
                "leading okay yeah filler chain"
            ),
            (
                "Okay, yeah, this works.",
                "this works.",
                "punctuated leading okay yeah filler chain"
            ),
            (
                "Right okay I think this works.",
                "I think this works.",
                "leading right okay filler chain"
            ),
            (
                "All right yeah this works.",
                "this works.",
                "leading all right yeah filler chain"
            ),
            (
                "Right yeah this works.",
                "this works.",
                "leading right yeah filler chain"
            ),
            (
                "Okay right this works.",
                "this works.",
                "leading okay right filler chain"
            ),
            (
                "Like, this works.",
                "this works.",
                "leading like filler"
            ),
            (
                "Okay so this works.",
                "this works.",
                "leading okay so filler"
            ),
            (
                "Okay, um, so this works.",
                "this works.",
                "leading okay pause so filler"
            ),
            (
                "Okay, you know, this works.",
                "this works.",
                "leading okay you know filler chain"
            ),
            (
                "Okay, I mean, this works.",
                "this works.",
                "leading okay i mean filler chain"
            ),
            (
                "Yeah, like, this works.",
                "this works.",
                "leading yeah like filler chain"
            ),
            (
                "Right, you know what I mean, this works.",
                "this works.",
                "leading right long filler chain"
            ),
            (
                "All right, so this works.",
                "this works.",
                "leading all right so filler"
            ),
            (
                "Right so this works.",
                "this works.",
                "leading right so filler"
            ),
            (
                "Yeah, so this works.",
                "this works.",
                "leading yeah so filler"
            ),
            (
                "Yeah, hmm, so this works.",
                "this works.",
                "leading yeah pause so filler"
            ),
            (
                "This works you know.",
                "This works.",
                "terminal discourse filler"
            ),
            (
                "This works you know what I mean.",
                "This works.",
                "long terminal discourse filler"
            ),
            (
                "This works, you know what I mean.",
                "This works.",
                "punctuated long terminal discourse filler"
            ),
            (
                "This works, um yeah.",
                "This works.",
                "terminal pause plus acknowledgement filler"
            ),
            (
                "This works, yeah okay.",
                "This works.",
                "terminal acknowledgement chain filler"
            ),
            (
                "This works, right okay.",
                "This works.",
                "terminal reversed acknowledgement chain filler"
            ),
            (
                "This works, yeah right.",
                "This works, yeah right.",
                "terminal literal yeah-right guard"
            ),
            (
                "This works okay.",
                "This works okay.",
                "terminal okay prose guard"
            ),
            (
                "This works, right?",
                "This works, right?",
                "terminal right question guard"
            ),
            (
                "The EHM project stays.",
                "The EHM project stays.",
                "all-caps ehm acronym prose guard"
            ),
            (
                "The AHEM marker stays.",
                "The AHEM marker stays.",
                "all-caps ahem marker prose guard"
            ),
            (
                "Thank you for watching.",
                "",
                "standalone watching boilerplate"
            ),
            (
                "Thanks for listening.",
                "",
                "standalone listening boilerplate"
            ),
            (
                "Thanks everyone for watching.",
                "",
                "standalone everyone watching boilerplate"
            ),
            (
                "Okay. Thanks for listening.",
                "Okay.",
                "terminal listening boilerplate"
            ),
            (
                "Okay. Thanks so much for listening!",
                "Okay.",
                "terminal emphatic listening boilerplate"
            ),
            (
                "Okay. Don't forget to like and subscribe.",
                "Okay.",
                "terminal like and subscribe boilerplate"
            ),
            (
                "Okay. Be sure to like and subscribe.",
                "Okay.",
                "terminal be sure subscribe boilerplate"
            ),
            (
                "Thank you for listening carefully.",
                "Thank you for listening carefully.",
                "listening prose guard"
            ),
            (
                "Thank you everyone for listening carefully.",
                "Thank you everyone for listening carefully.",
                "everyone listening prose guard"
            ),
            (
                "End with thanks for listening.",
                "End with thanks for listening.",
                "embedded listening prose guard"
            ),
            (
                "End with thanks everyone for watching.",
                "End with thanks everyone for watching.",
                "embedded everyone watching prose guard"
            ),
            (
                "Please subscribe to the newsletter.",
                "Please subscribe to the newsletter.",
                "subscribe newsletter prose guard"
            ),
            (
                "Be sure to like and subscribe to updates.",
                "Be sure to like and subscribe to updates.",
                "like subscribe updates prose guard"
            ),
            (
                "you know.",
                "",
                "standalone you know filler"
            ),
            (
                "you know what I mean.",
                "",
                "standalone you know what I mean filler"
            ),
            (
                "I think this works. I think this works.",
                "I think this works.",
                "duplicate short sentence"
            ),
            (
                "I think this works. I think this works",
                "I think this works.",
                "duplicate short sentence missing trailing punctuation"
            ),
            (
                "New York. New York",
                "New York. New York",
                "intentional repeated sentence guard"
            ),
            (
                "We should ship we should ship this.",
                "We should ship this.",
                "repeated short phrase"
            ),
            (
                "I think we should ship we should ship this.",
                "I think we should ship this.",
                "inline repeated short phrase"
            ),
            (
                "I think this is, this is ready.",
                "I think this is ready.",
                "inline comma repeated short phrase"
            ),
            (
                "Let's meet at two, wait no, three.",
                "Let's meet at three.",
                "wait no correction"
            ),
            (
                "Let's meet at two, no wait, three.",
                "Let's meet at three.",
                "no wait correction"
            ),
            (
                "Let's meet at two wait no three tomorrow.",
                "Let's meet at three tomorrow.",
                "wait no correction should preserve suffix"
            ),
            (
                "Let's meet at two no actually three tomorrow.",
                "Let's meet at three tomorrow.",
                "no actually correction should preserve suffix"
            ),
            (
                "Let's meet at two o clock wait no three tomorrow.",
                "Let's meet at three tomorrow.",
                "wait no correction should replace spoken time phrase"
            ),
            (
                "Let's meet at two o clock wait no three thirty tomorrow.",
                "Let's meet at three thirty tomorrow.",
                "wait no correction should preserve suffix after spoken time phrase"
            ),
            (
                "Let's meet at two thirty wait no three o clock tomorrow.",
                "Let's meet at three o clock tomorrow.",
                "wait no correction should replace alternate spoken time phrase"
            ),
            (
                "Call at 9 30 a m wait no 10 45 a m tomorrow.",
                "Call at 10:45 AM tomorrow.",
                "wait no correction should replace numeric spoken time phrase"
            ),
            (
                "Meet on June second wait no June third tomorrow.",
                "Meet on June 3 tomorrow.",
                "wait no correction should replace spoken date phrase"
            ),
            (
                "Meet on June second wait no third tomorrow.",
                "Meet on June 3 tomorrow.",
                "wait no correction should preserve spoken date month"
            ),
            (
                "Meet on June twenty second wait no twenty third tomorrow.",
                "Meet on June 23 tomorrow.",
                "wait no correction should preserve multi-word spoken date month"
            ),
            (
                "Meet on June second 2026 wait no third tomorrow.",
                "Meet on June 3, 2026 tomorrow.",
                "wait no correction should preserve spoken date year"
            ),
            (
                "Meet on June second 2026 wait no July third 2027 tomorrow.",
                "Meet on July 3, 2027 tomorrow.",
                "wait no correction should replace full spoken date with year"
            ),
            (
                "Pay twenty dollars wait no thirty dollars tomorrow.",
                "Pay $30 tomorrow.",
                "wait no correction should replace spoken currency phrase"
            ),
            (
                "Pay twenty dollars wait no thirty tomorrow.",
                "Pay $30 tomorrow.",
                "wait no correction should preserve spoken currency unit"
            ),
            (
                "Pay 20 dollars wait no 25 dollars tomorrow.",
                "Pay $25 tomorrow.",
                "wait no correction should replace numeric currency phrase"
            ),
            (
                "Pay dollar sign twenty wait no dollar sign thirty tomorrow.",
                "Pay $30 tomorrow.",
                "wait no correction should replace leading currency sign phrase"
            ),
            (
                "Progress is eighty five percent wait no ninety percent done.",
                "Progress is 90% done.",
                "wait no correction should replace spoken percent phrase"
            ),
            (
                "Progress is eighty five percent wait no ninety done.",
                "Progress is 90% done.",
                "wait no correction should preserve spoken percent unit"
            ),
            (
                "I lost twenty pounds wait no thirty pounds.",
                "I lost thirty pounds.",
                "wait no correction should preserve pound weight wording"
            ),
            (
                "Pay nineteen point nine nine dollars wait no twenty dollars tomorrow.",
                "Pay $20 tomorrow.",
                "wait no correction should replace decimal currency phrase"
            ),
            (
                "Pay twenty dollars wait no nineteen point nine nine dollars tomorrow.",
                "Pay $19.99 tomorrow.",
                "wait no correction should insert decimal currency phrase"
            ),
            (
                "Pay nineteen point nine nine dollars wait no twenty tomorrow.",
                "Pay $20 tomorrow.",
                "wait no correction should preserve decimal currency unit"
            ),
            (
                "Pay twenty dollars wait no nineteen point nine nine tomorrow.",
                "Pay $19.99 tomorrow.",
                "wait no correction should preserve currency unit for decimal value"
            ),
            (
                "Pay dollar sign nineteen point nine nine wait no dollar sign twenty tomorrow.",
                "Pay $20 tomorrow.",
                "wait no correction should replace leading decimal currency phrase"
            ),
            (
                "Progress is eighty five point five percent wait no ninety percent done.",
                "Progress is 90% done.",
                "wait no correction should replace decimal percent phrase"
            ),
            (
                "Progress is eighty five percent wait no eighty five point five done.",
                "Progress is 85.5% done.",
                "wait no correction should preserve percent unit for decimal value"
            ),
            (
                "Open docs dot example dot com wait no app dot example dot com today.",
                "Open app.example.com today.",
                "wait no correction should replace spoken domain phrase"
            ),
            (
                "Open docs dot example dot com slash api wait no docs dot example dot com slash v2 today.",
                "Open docs.example.com/v2 today.",
                "wait no correction should replace spoken URL path phrase"
            ),
            (
                "Email old at sign example dot com wait no new at sign example dot com today.",
                "Email new@example.com today.",
                "wait no correction should replace spoken email phrase"
            ),
            (
                "Use user underscore id wait no account underscore id today.",
                "Use account_id today.",
                "wait no correction should replace spoken identifier phrase"
            ),
            (
                "Open docs dot example dot com wait no dot org today.",
                "Open docs.example.org today.",
                "wait no correction should replace spoken domain suffix"
            ),
            (
                "Open docs dot example dot com slash api wait no slash v2 today.",
                "Open docs.example.com/v2 today.",
                "wait no correction should replace spoken path suffix"
            ),
            (
                "Email old at sign example dot com wait no at sign new dot com today.",
                "Email old@new.com today.",
                "wait no correction should replace spoken email domain suffix"
            ),
            (
                "Use user underscore id wait no underscore name today.",
                "Use user_name today.",
                "wait no correction should replace spoken identifier suffix"
            ),
            (
                "Use camel case user id wait no account id.",
                "Use accountId.",
                "wait no correction should replace camel case argument"
            ),
            (
                "Set variable snake case user id wait no account id.",
                "Set variable account_id.",
                "wait no correction should replace snake case argument"
            ),
            (
                "Use kebab case user id wait no account id.",
                "Use account-id.",
                "wait no correction should replace kebab case argument"
            ),
            (
                "Use pascal case user profile wait no account owner.",
                "Use AccountOwner.",
                "wait no correction should replace pascal case argument"
            ),
            (
                "Use title case weekly report wait no release notes.",
                "Use Release Notes.",
                "wait no correction should replace title case argument"
            ),
            (
                "Use all caps urgent wait no high priority now.",
                "Use HIGH PRIORITY now.",
                "wait no correction should replace all caps argument"
            ),
            (
                "Use lowercase VoiceInk wait no ROMA today.",
                "Use roma today.",
                "wait no correction should replace lowercase argument"
            ),
            (
                "Use capitalize felix wait no roma tomorrow.",
                "Use Roma tomorrow.",
                "wait no correction should replace capitalize argument"
            ),
            (
                "Heading two roadmap wait no release notes.",
                "## release notes",
                "wait no correction should replace markdown heading argument"
            ),
            (
                "Todo buy milk wait no call mom.",
                "- [ ] call mom",
                "wait no correction should replace markdown todo argument"
            ),
            (
                "Checked task review PR wait no ship release.",
                "- [x] ship release",
                "wait no correction should replace checked markdown task argument"
            ),
            (
                "Use inline code user id wait no account id.",
                "Use `account id`.",
                "wait no correction should replace inline code argument"
            ),
            (
                "Markdown link VoiceInk docs to docs dot example dot com slash api wait no Roma docs.",
                "[Roma docs](docs.example.com/api)",
                "wait no correction should replace markdown link label"
            ),
            (
                "Markdown link VoiceInk docs to docs dot example dot com slash api wait no docs dot example dot com slash v2.",
                "[VoiceInk docs](docs.example.com/v2)",
                "wait no correction should replace markdown link target"
            ),
            (
                "Markdown link VoiceInk docs to docs dot example dot com slash api wait no to docs dot example dot com slash v2.",
                "[VoiceInk docs](docs.example.com/v2)",
                "wait no correction should replace markdown link target after repeated to"
            ),
            (
                "Use model, oops module.",
                "Use module.",
                "oops correction"
            ),
            (
                "Use model, oops actually module.",
                "Use module.",
                "oops actually correction"
            ),
            (
                "Use model, whoops, module.",
                "Use module.",
                "whoops correction"
            ),
            (
                "Use model, my bad, module.",
                "Use module.",
                "my bad correction"
            ),
            (
                "Use model, my bad, I mean module.",
                "Use module.",
                "my bad i mean correction"
            ),
            (
                "Use model, um actually module.",
                "Use module.",
                "pause before actually correction"
            ),
            (
                "Use model, uh I mean module.",
                "Use module.",
                "pause before i mean correction"
            ),
            (
                "Let's meet at two, hmm wait no three.",
                "Let's meet at three.",
                "pause before wait no correction"
            ),
            (
                "Use model, ahem wait no module.",
                "Use module.",
                "ahem before wait no correction"
            ),
            (
                "Use model, ehm wait no module.",
                "Use module.",
                "ehm before wait no correction"
            ),
            (
                "Use model, wait module.",
                "Use module.",
                "bare wait correction"
            ),
            (
                "Use model, wait new module.",
                "Use new module.",
                "bare wait short phrase correction"
            ),
            (
                "Use model, hold on module.",
                "Use module.",
                "hold on hesitation correction"
            ),
            (
                "Use model, hang on new module.",
                "Use new module.",
                "hang on hesitation correction"
            ),
            (
                "Use model, on second thought module.",
                "Use module.",
                "on second thought hesitation correction"
            ),
            (
                "Use model, um on second thought module.",
                "Use module.",
                "pause filler before on second thought correction"
            ),
            (
                "Let's meet at two, on second thought three tomorrow.",
                "Let's meet at three tomorrow.",
                "on second thought correction should preserve suffix"
            ),
            (
                "Use model, let me rephrase module.",
                "Use module.",
                "let me rephrase correction"
            ),
            (
                "Use model, uh let me rephrase module.",
                "Use module.",
                "pause filler before let me rephrase correction"
            ),
            (
                "Let's meet at two, let me rephrase three tomorrow.",
                "Let's meet at three tomorrow.",
                "let me rephrase correction should preserve suffix"
            ),
            (
                "Use model, backtrack module.",
                "Use module.",
                "backtrack correction"
            ),
            (
                "Use model, back track module.",
                "Use module.",
                "spaced back track correction"
            ),
            (
                "Let's meet at two... backtrack three.",
                "Let's meet at three.",
                "backtrack correction should preserve suffix"
            ),
            (
                "Use model, to clarify module.",
                "Use module.",
                "to clarify correction"
            ),
            (
                "Use model, um to clarify module.",
                "Use module.",
                "pause filler before to clarify correction"
            ),
            (
                "Let's meet at two, to clarify three tomorrow.",
                "Let's meet at three tomorrow.",
                "to clarify correction should preserve suffix"
            ),
            (
                "Use model, just to clarify module.",
                "Use module.",
                "just to clarify correction"
            ),
            (
                "Use model, um just to clarify module.",
                "Use module.",
                "pause filler before just to clarify correction"
            ),
            (
                "Use model, to be clear module.",
                "Use module.",
                "to be clear correction"
            ),
            (
                "Use model, just to be clear module.",
                "Use module.",
                "just to be clear correction"
            ),
            (
                "Use model, for clarity module.",
                "Use module.",
                "for clarity correction"
            ),
            (
                "Let's meet at two, just to be clear three tomorrow.",
                "Let's meet at three tomorrow.",
                "just to be clear correction should preserve suffix"
            ),
            (
                "Use model, I mean to say module.",
                "Use module.",
                "i mean to say correction"
            ),
            (
                "Use model, um I mean to say module.",
                "Use module.",
                "pause filler before i mean to say correction"
            ),
            (
                "Let's meet at two, I mean to say three tomorrow.",
                "Let's meet at three tomorrow.",
                "i mean to say correction should preserve suffix"
            ),
            (
                "Use model, I meant to say module.",
                "Use module.",
                "i meant to say correction"
            ),
            (
                "Use model, uh I meant to say module.",
                "Use module.",
                "pause filler before i meant to say correction"
            ),
            (
                "Let's meet at two, I meant to say three tomorrow.",
                "Let's meet at three tomorrow.",
                "i meant to say correction should preserve suffix"
            ),
            (
                "Use model, what I mean is module.",
                "Use module.",
                "what i mean is correction"
            ),
            (
                "Use model, um what I mean is module.",
                "Use module.",
                "pause filler before what i mean is correction"
            ),
            (
                "Let's meet at two, what I mean is three tomorrow.",
                "Let's meet at three tomorrow.",
                "what i mean is correction should preserve suffix"
            ),
            (
                "Use model, wait actually module.",
                "Use module.",
                "wait actually correction"
            ),
            (
                "Use model, wait, I mean module.",
                "Use module.",
                "wait i mean correction"
            ),
            (
                "Use model... wait, I meant module.",
                "Use module.",
                "wait i meant correction"
            ),
            (
                "Let's meet at two, wait actually three.",
                "Let's meet at three.",
                "wait actually replacement correction"
            ),
            (
                "Use model no I mean module.",
                "Use module.",
                "no i mean correction"
            ),
            (
                "Use model no, I meant module.",
                "Use module.",
                "no i meant correction"
            ),
            (
                "Use model no actually module.",
                "Use module.",
                "no actually correction"
            ),
            (
                "Use model, correction module.",
                "Use module.",
                "correction marker cleanup"
            ),
            (
                "Use model, correction actually module.",
                "Use module.",
                "correction actually marker cleanup"
            ),
            (
                "Use model, sorry, actually module.",
                "Use module.",
                "sorry actually marker cleanup"
            ),
            (
                "Use old model, correction the new module.",
                "Use the new module.",
                "correction marker article cleanup"
            ),
            (
                "Let's meet at two, no actually three.",
                "Let's meet at three.",
                "no actually correction"
            ),
            (
                "Use model, actually make it module.",
                "Use module.",
                "actually make it correction"
            ),
            (
                "Use model, better make it module.",
                "Use module.",
                "better make it correction"
            ),
            (
                "Use model, make it module.",
                "Use module.",
                "make it correction"
            ),
            (
                "Use model, make it a module.",
                "Use a module.",
                "make it article correction"
            ),
            (
                "Let's meet at two, actually no, three.",
                "Let's meet at three.",
                "actually no correction"
            ),
            (
                "Use model actually wait no module.",
                "Use module.",
                "actually wait no correction"
            ),
            (
                "Use model, actually wait, no module.",
                "Use module.",
                "punctuated actually wait no correction"
            ),
            (
                "Use model actually wait nevermind module.",
                "Use module.",
                "actually wait nevermind correction"
            ),
            (
                "Use model, actually wait, never mind module.",
                "Use module.",
                "punctuated actually wait never mind correction"
            ),
            (
                "Use model actually wait nevermind module today.",
                "Use module today.",
                "actually wait nevermind correction should preserve suffix"
            ),
            (
                "Let's meet at two, actually never mind, three.",
                "Let's meet at three.",
                "actually never mind correction"
            ),
            (
                "Let's meet at two never mind three tomorrow.",
                "Let's meet at three tomorrow.",
                "never mind correction should preserve suffix"
            ),
            (
                "Use model wait never mind module.",
                "Use module.",
                "wait never mind correction"
            ),
            (
                "Use model, rather, module.",
                "Use module.",
                "bounded rather correction"
            ),
            (
                "Let's meet at two or actually three.",
                "Let's meet at three.",
                "or actually single-word correction"
            ),
            (
                "Use model or wait no module.",
                "Use module.",
                "or wait no single-word correction"
            ),
            (
                "Use model, instead module.",
                "Use module.",
                "bounded instead correction"
            ),
            (
                "Use old model, instead the new module.",
                "Use the new module.",
                "bounded instead article correction"
            ),
            (
                "Use model replace that with module.",
                "Use module.",
                "replace that with correction"
            ),
            (
                "Use model replace it with module.",
                "Use module.",
                "replace it with correction"
            ),
            (
                "Use model replace that with a module.",
                "Use a module.",
                "replace that with article correction"
            ),
            (
                "Set color blue change it to red.",
                "Set color red.",
                "change it to correction"
            ),
            (
                "Use the model replace that with a module.",
                "Use a module.",
                "replace article phrase with article correction"
            ),
            (
                "Use old model replace that with a new module.",
                "Use a new module.",
                "replace phrase with article correction"
            ),
            (
                "Use old model replace that with the new module.",
                "Use the new module.",
                "replace phrase with definite article correction"
            ),
            (
                "Use the old model replace that with a new module.",
                "Use a new module.",
                "replace article phrase with multi-word article correction"
            ),
            (
                "Use the old model replace that with the new module.",
                "Use the new module.",
                "replace article phrase with definite article correction"
            ),
            (
                "Use the old model replace it with the new module.",
                "Use the new module.",
                "replace it article phrase with definite article correction"
            ),
            (
                "Use model, sorry I mean module.",
                "Use module.",
                "sorry i mean correction"
            ),
            (
                "Use model, I meant module.",
                "Use module.",
                "i meant correction"
            ),
            (
                "Use model, sorry I meant module.",
                "Use module.",
                "sorry i meant correction"
            ),
            (
                "Use model, I should say module.",
                "Use module.",
                "i should say correction"
            ),
            (
                "Use model, make that module.",
                "Use module.",
                "make that correction"
            ),
            (
                "Please, make it red.",
                "Please, make it red.",
                "single-prefix polite make it guard"
            ),
            (
                "Please, make that red.",
                "Please, make that red.",
                "single-prefix polite make that guard"
            ),
            (
                "Please, call it module.",
                "Please, call it module.",
                "single-prefix polite call it guard"
            ),
            (
                "Use model, call it module.",
                "Use module.",
                "call it correction"
            ),
            (
                "Use model, call it a module.",
                "Use a module.",
                "call it article correction"
            ),
            (
                "Use the model, call it a module.",
                "Use a module.",
                "call it article phrase correction"
            ),
            (
                "Set color blue, sorry red.",
                "Set color red.",
                "sorry correction"
            ),
            (
                "Set color blue sorry red.",
                "Set color red.",
                "bare sorry correction"
            ),
            (
                "Use local sorry cloud.",
                "Use cloud.",
                "bare sorry one-word correction"
            ),
            (
                "Wrong phrase scratch that. Right phrase.",
                "Right phrase.",
                "scratch that correction"
            ),
            (
                "Wrong phrase scratch that out. Right phrase.",
                "Right phrase.",
                "scratch that out correction"
            ),
            (
                "Wrong phrase scratch this. Right phrase.",
                "Right phrase.",
                "scratch this correction"
            ),
            (
                "Wrong phrase scratch this out. Right phrase.",
                "Right phrase.",
                "scratch this out correction"
            ),
            (
                "Wrong phrase strike that right phrase.",
                "right phrase.",
                "natural strike that correction"
            ),
            (
                "Wrong phrase strike this right phrase.",
                "right phrase.",
                "natural strike this correction"
            ),
            (
                "Wrong phrase strike that out right phrase.",
                "right phrase.",
                "natural strike that out correction"
            ),
            (
                "Wrong phrase strike this out right phrase.",
                "right phrase.",
                "natural strike this out correction"
            ),
            (
                "Wrong phrase cross that out right phrase.",
                "right phrase.",
                "natural cross that out correction"
            ),
            (
                "Wrong phrase cross this out right phrase.",
                "right phrase.",
                "natural cross this out correction"
            ),
            (
                "Wrong phrase delete that right phrase.",
                "right phrase.",
                "natural delete that correction"
            ),
            (
                "Wrong phrase delete this right phrase.",
                "right phrase.",
                "natural delete this correction"
            ),
            (
                "Wrong phrase cancel that. Right phrase.",
                "Right phrase.",
                "cancel that correction"
            ),
            (
                "Wrong phrase cancel this. Right phrase.",
                "Right phrase.",
                "cancel this correction"
            ),
            (
                "Wrong phrase disregard that. Right phrase.",
                "Right phrase.",
                "disregard that correction"
            ),
            (
                "Wrong phrase ignore that. Right phrase.",
                "Right phrase.",
                "ignore that correction"
            ),
            (
                "Wrong phrase ignore this. Right phrase.",
                "Right phrase.",
                "ignore this correction"
            ),
            (
                "Wrong phrase forget that. Right phrase.",
                "Right phrase.",
                "forget that correction"
            ),
            (
                "Wrong phrase forget this. Right phrase.",
                "Right phrase.",
                "forget this correction"
            ),
            (
                "Wrong phrase cut that. Right phrase.",
                "Right phrase.",
                "cut that correction"
            ),
            (
                "Wrong phrase drop that. Right phrase.",
                "Right phrase.",
                "drop that correction"
            ),
            (
                "Use model scratch this modules.",
                "Use modules.",
                "scratch this inline correction"
            ),
            (
                "Use old model delete last word module.",
                "Use old module.",
                "delete last word correction"
            ),
            (
                "Use old model delete the last word module.",
                "Use old module.",
                "delete the last word correction"
            ),
            (
                "Use old model delete previous word module.",
                "Use old module.",
                "delete previous word correction"
            ),
            (
                "Use old model delete that word module.",
                "Use old module.",
                "delete that word correction"
            ),
            (
                "Use old model undo this word module.",
                "Use old module.",
                "undo this word correction"
            ),
            (
                "Use old model scratch last word module.",
                "Use old module.",
                "scratch last word correction"
            ),
            (
                "Use old wrong model delete last two words module.",
                "Use old module.",
                "delete last two words correction"
            ),
            (
                "Use old wrong model undo the previous two words module.",
                "Use old module.",
                "undo the previous two words correction"
            ),
            (
                "Use old wrong model undo previous three words module.",
                "Use module.",
                "undo previous three words correction"
            ),
            (
                "Use old wrong model delete last 2 words module.",
                "Use old module.",
                "delete last digit-count words correction"
            ),
            (
                "Use model delete last word.",
                "Use",
                "terminal delete last word correction"
            ),
            (
                "Use old model delete last two words.",
                "Use",
                "terminal delete last two words correction"
            ),
            (
                "First sentence. Wrong sentence. delete last sentence. Right sentence.",
                "First sentence. Right sentence.",
                "delete last sentence correction"
            ),
            (
                "First sentence. Wrong sentence. remove the previous sentence. Right sentence.",
                "First sentence. Right sentence.",
                "remove the previous sentence correction"
            ),
            (
                "First sentence. Wrong sentence. delete that sentence. Right sentence.",
                "First sentence. Right sentence.",
                "delete that sentence correction"
            ),
            (
                "First sentence. Wrong sentence. undo this sentence. Right sentence.",
                "First sentence. Right sentence.",
                "undo this sentence correction"
            ),
            (
                "First sentence. Wrong sentence. scratch last sentence. Right sentence.",
                "First sentence. Right sentence.",
                "scratch last sentence correction"
            ),
            (
                "First line new line wrong line delete last line right line.",
                "First line\nright line.",
                "delete last line after spoken newline"
            ),
            (
                "First line new line wrong line delete the previous line right line.",
                "First line\nright line.",
                "delete the previous line after spoken newline"
            ),
            (
                "First line new line wrong line delete that line right line.",
                "First line\nright line.",
                "delete that line after spoken newline"
            ),
            (
                "First line press enter wrong line undo previous line right line.",
                "First line\nright line.",
                "undo previous line after enter command"
            ),
            (
                "First line press enter wrong line undo this line right line.",
                "First line\nright line.",
                "undo this line after enter command"
            ),
            (
                "Intro new paragraph wrong paragraph delete last paragraph right paragraph.",
                "Intro\n\nright paragraph.",
                "delete last paragraph after spoken paragraph"
            ),
            (
                "Intro new paragraph wrong paragraph remove the previous paragraph right paragraph.",
                "Intro\n\nright paragraph.",
                "remove the previous paragraph after spoken paragraph"
            ),
            (
                "Intro new paragraph wrong paragraph delete that paragraph right paragraph.",
                "Intro\n\nright paragraph.",
                "delete that paragraph after spoken paragraph"
            ),
            (
                "Intro skip a line wrong paragraph undo previous paragraph right paragraph.",
                "Intro\n\nright paragraph.",
                "undo previous paragraph after skip line"
            ),
            (
                "Intro skip a line wrong paragraph undo this paragraph right paragraph.",
                "Intro\n\nright paragraph.",
                "undo this paragraph after skip line"
            ),
            (
                "Open quote hello comma world close quote.",
                "\"hello, world\".",
                "spoken enclosure and punctuation"
            ),
            (
                "Quote hello comma world unquote.",
                "\"hello, world\".",
                "quote unquote enclosure"
            ),
            (
                "Single quote hello comma world single quote.",
                "'hello, world'.",
                "single quote pair enclosure"
            ),
            (
                "Put model in parentheses.",
                "(model).",
                "put in parentheses enclosure"
            ),
            (
                "Put model in brackets.",
                "[model].",
                "put in brackets enclosure"
            ),
            (
                "Wrap user id in braces.",
                "{user id}.",
                "wrap in braces enclosure"
            ),
            (
                "Put hello comma world in quotes.",
                "\"hello, world\".",
                "put in quotes enclosure"
            ),
            (
                "Use open parenthesis model end parenthesis now.",
                "Use (model) now.",
                "end parenthesis enclosure"
            ),
            (
                "Use open bracket draft end bracket now.",
                "Use [draft] now.",
                "end bracket enclosure"
            ),
            (
                "Use open brace user id colon one end brace now.",
                "Use {user id: one} now.",
                "end brace enclosure"
            ),
            (
                "Hello, comma world.",
                "Hello, world.",
                "spoken comma over auto comma"
            ),
            (
                "Hello, comma, world.",
                "Hello, world.",
                "spoken comma over repeated auto comma"
            ),
            (
                "Hello! exclamation mark.",
                "Hello!",
                "spoken exclamation over auto exclamation"
            ),
            (
                "Are you ready? question mark.",
                "Are you ready?",
                "spoken question mark over auto question mark"
            ),
            (
                "Are you ready question point.",
                "Are you ready?",
                "spoken question point command"
            ),
            (
                "Are you ready question sign.",
                "Are you ready?",
                "spoken question sign command"
            ),
            (
                "Ship it exclamation sign.",
                "Ship it!",
                "spoken exclamation sign command"
            ),
            (
                "Wait ellipsis maybe.",
                "Wait... maybe.",
                "spoken ellipsis command"
            ),
            (
                "Wait dot dot dot maybe.",
                "Wait... maybe.",
                "spoken dot dot dot command"
            ),
            (
                "Wait em dash maybe.",
                "Wait — maybe.",
                "spoken em dash command"
            ),
            (
                "Use model dash name.",
                "Use model-name.",
                "compact dash command guard"
            ),
            (
                "Run git commit dash dash amend.",
                "Run git commit --amend.",
                "spoken long CLI flag command"
            ),
            (
                "Run npm install dash dash save dash dev.",
                "Run npm install --save-dev.",
                "spoken hyphenated long CLI flag command"
            ),
            (
                "Use dash dash help and dash dash version.",
                "Use --help and --version.",
                "repeated spoken long CLI flag commands"
            ),
            (
                "My top goals are one finish the report two send the slides.",
                "My top goals are\n1. finish the report\n2. send the slides.",
                "cardinal spoken sequence list"
            ),
            (
                "Number one finish the report number two send the slides.",
                "1. finish the report\n2. send the slides.",
                "number-prefixed spoken sequence list"
            ),
            (
                "My top goals are number one finish the report number two send the slides.",
                "My top goals are\n1. finish the report\n2. send the slides.",
                "prefixed number spoken sequence list"
            ),
            (
                "Plan first confirm scope second ship patch.",
                "Plan\n1. confirm scope\n2. ship patch.",
                "ordinal spoken sequence list"
            ),
            (
                "Intro skip a line Details.",
                "Intro\n\nDetails.",
                "skip a line paragraph command"
            ),
            (
                "Intro start a new paragraph Details.",
                "Intro\n\nDetails.",
                "start a new paragraph command"
            ),
            (
                "Intro break here Details.",
                "Intro\n\nDetails.",
                "break here paragraph command"
            ),
            (
                "Intro split here Details.",
                "Intro\n\nDetails.",
                "split here paragraph command"
            ),
            (
                "New line details.",
                "\ndetails.",
                "leading new line command"
            ),
            (
                "New paragraph Details.",
                "\n\nDetails.",
                "leading new paragraph command"
            ),
            (
                "Press enter details.",
                "\ndetails.",
                "leading press enter command"
            ),
            (
                "First thing new sentence second thing.",
                "First thing. Second thing.",
                "new sentence command"
            ),
            (
                "First thing next sentence API stays uppercase.",
                "First thing. API stays uppercase.",
                "next sentence command preserves acronym case"
            ),
            (
                "First press enter second.",
                "First\nsecond.",
                "press enter line command"
            ),
            (
                "First hit return key second.",
                "First\nsecond.",
                "hit return key line command"
            ),
            (
                "Column one press tab column two.",
                "Column one\tcolumn two.",
                "press tab command"
            ),
            (
                "Column one hit tab key column two.",
                "Column one\tcolumn two.",
                "hit tab key command"
            ),
            (
                "Bullet parent indent bullet child outdent bullet sibling.",
                "- parent\n  - child\n- sibling",
                "nested bullet indent outdent command"
            ),
            (
                "Bullet parent sub bullet child bullet sibling.",
                "- parent\n  - child\n  - sibling",
                "nested bullet sub command"
            ),
            (
                "Bullet parent indent bullet child dedent bullet sibling.",
                "- parent\n  - child\n- sibling",
                "nested bullet dedent command"
            ),
            (
                "Number one parent indent number one child outdent number two sibling.",
                "1. parent\n  1. child\n2. sibling",
                "nested numbered outline command"
            ),
            (
                "One parent indent one child outdent two sibling.",
                "1. parent\n  1. child\n2. sibling",
                "bare nested numbered outline command"
            ),
            (
                "Number one parent sub number one child number two sibling.",
                "1. parent\n  1. child\n  2. sibling",
                "sub nested numbered outline command"
            ),
            (
                "Use api slash users.",
                "Use api/users.",
                "spoken slash command"
            ),
            (
                "Use chat no space GPT today.",
                "Use chatGPT today.",
                "spoken no space command"
            ),
            (
                "Use happy no space f no space coding.",
                "Use happyfcoding.",
                "chained spoken no space command"
            ),
            (
                "Use the api key for the url.",
                "Use the API key for the URL.",
                "common technical acronym casing"
            ),
            (
                "The ui and ux need ai polish.",
                "The UI and UX need AI polish.",
                "short technical acronym casing"
            ),
            (
                "Return json from the sql query.",
                "Return JSON from the SQL query.",
                "data technical acronym casing"
            ),
            (
                "Use all caps api key.",
                "Use API KEY.",
                "all caps text case command"
            ),
            (
                "Please uppercase urgent.",
                "Please URGENT.",
                "uppercase text case command"
            ),
            (
                "Use lowercase VoiceInk.",
                "Use voiceink.",
                "lowercase text case command"
            ),
            (
                "Use lowercase API.",
                "Use api.",
                "explicit lowercase overrides acronym casing"
            ),
            (
                "Use capitalize felix.",
                "Use Felix.",
                "capitalize text case command"
            ),
            (
                "Use title case weekly report.",
                "Use Weekly Report.",
                "title case text command"
            ),
            (
                "Markdown table name age row Felix thirty row Roma one.",
                "| name | age |\n| --- | --- |\n| Felix | thirty |\n| Roma | one |",
                "compact spoken markdown table"
            ),
            (
                "Table name column age row Felix column thirty.",
                "| name | age |\n| --- | --- |\n| Felix | thirty |",
                "explicit column spoken markdown table"
            ),
            (
                "Table manners matter.",
                "Table manners matter.",
                "table prose guard"
            ),
            (
                ".env file.",
                ".env file.",
                "dot-prefixed token guard"
            ),
            (
                "Use version one two today.",
                "Use version one two today.",
                "spoken sequence version guard"
            ),
            (
                "Open https colon slash slash docs dot example dot com slash api.",
                "Open https://docs.example.com/api",
                "spoken URL command"
            ),
            (
                "I can apostrophe t go.",
                "I can't go.",
                "spoken contraction"
            ),
            (
                "Felix apostrophe s laptop is ready.",
                "Felix's laptop is ready.",
                "spoken possessive"
            ),
            (
                "The phrase replace that with is useful.",
                "The phrase replace that with is useful.",
                "replace command prose guard"
            ),
            (
                "The phrase replace it with is useful.",
                "The phrase replace it with is useful.",
                "replace it command prose guard"
            ),
            (
                "The command change that to is useful.",
                "The command change that to is useful.",
                "change command prose guard"
            ),
            (
                "The command change it to is useful.",
                "The command change it to is useful.",
                "change it command prose guard"
            ),
            (
                "The phrase no I mean is useful.",
                "The phrase no I mean is useful.",
                "no i mean phrase guard"
            ),
            (
                "The phrase no actually is useful.",
                "The phrase no actually is useful.",
                "no actually phrase guard"
            ),
            (
                "Let's wait actually until tomorrow.",
                "Let's wait actually until tomorrow.",
                "wait actually prose guard"
            ),
            (
                "The phrase wait actually is useful.",
                "The phrase wait actually is useful.",
                "wait actually phrase guard"
            ),
            (
                "The phrase, wait actually, is useful.",
                "The phrase, wait actually, is useful.",
                "punctuated wait actually phrase guard"
            ),
            (
                "Please change that to red.",
                "Please change that to red.",
                "single-prefix change that prose guard"
            ),
            (
                "Please change it to red.",
                "Please change it to red.",
                "single-prefix change it prose guard"
            ),
            (
                "Please replace it with red.",
                "Please replace it with red.",
                "single-prefix replace it prose guard"
            ),
            (
                "Delete that file.",
                "Delete that file.",
                "delete command prose guard"
            ),
            (
                "The delete last word shortcut is useful.",
                "The delete last word shortcut is useful.",
                "delete last word prose guard"
            ),
            (
                "The delete the last word shortcut is useful.",
                "The delete the last word shortcut is useful.",
                "delete the last word prose guard"
            ),
            (
                "The delete last two words shortcut is useful.",
                "The delete last two words shortcut is useful.",
                "delete counted words prose guard"
            ),
            (
                "The delete that word shortcut is useful.",
                "The delete that word shortcut is useful.",
                "delete that word prose guard"
            ),
            (
                "Explain how to remove this word from docs.",
                "Explain how to remove this word from docs.",
                "remove this word prose guard"
            ),
            (
                "The delete last sentence command is useful.",
                "The delete last sentence command is useful.",
                "delete last sentence prose guard"
            ),
            (
                "Explain how to remove the previous sentence from docs.",
                "Explain how to remove the previous sentence from docs.",
                "remove the previous sentence prose guard"
            ),
            (
                "The delete that sentence command is useful.",
                "The delete that sentence command is useful.",
                "delete that sentence prose guard"
            ),
            (
                "Explain how to remove this sentence from docs.",
                "Explain how to remove this sentence from docs.",
                "remove this sentence prose guard"
            ),
            (
                "The delete last line command is useful.",
                "The delete last line command is useful.",
                "delete last line prose guard"
            ),
            (
                "The delete last paragraph command is useful.",
                "The delete last paragraph command is useful.",
                "delete last paragraph prose guard"
            ),
            (
                "Explain how to undo the previous line in docs.",
                "Explain how to undo the previous line in docs.",
                "undo the previous line prose guard"
            ),
            (
                "Explain how to remove the previous paragraph from docs.",
                "Explain how to remove the previous paragraph from docs.",
                "remove the previous paragraph prose guard"
            ),
            (
                "The delete that line command is useful.",
                "The delete that line command is useful.",
                "delete that line prose guard"
            ),
            (
                "Explain how to remove this paragraph from docs.",
                "Explain how to remove this paragraph from docs.",
                "remove this paragraph prose guard"
            ),
            (
                "The first item is setup. The second item is launch.",
                "The first item is setup. The second item is launch.",
                "spoken sequence prose guard"
            ),
            (
                "The number one priority is focus.",
                "The number one priority is focus.",
                "number one prose guard"
            ),
            (
                "Compare option one and two tomorrow.",
                "Compare option one and two tomorrow.",
                "connector spoken sequence prose guard"
            ),
            (
                "The phrase skip a line is useful.",
                "The phrase skip a line is useful.",
                "skip a line prose guard"
            ),
            (
                "Explain how to start a new paragraph in docs.",
                "Explain how to start a new paragraph in docs.",
                "start a new paragraph prose guard"
            ),
            (
                "The break here is intentional.",
                "The break here is intentional.",
                "break here prose guard"
            ),
            (
                "The new sentence command is useful.",
                "The new sentence command is useful.",
                "new sentence command prose guard"
            ),
            (
                "Explain how to start a new sentence in docs.",
                "Explain how to start a new sentence in docs.",
                "new sentence docs prose guard"
            ),
            (
                "There is no space here.",
                "There is no space here.",
                "no space grammar guard"
            ),
            (
                "I want no spaces here.",
                "I want no spaces here.",
                "no spaces grammar guard"
            ),
            (
                "The no space command is useful.",
                "The no space command is useful.",
                "no space command prose guard"
            ),
            (
                "The press enter shortcut is useful.",
                "The press enter shortcut is useful.",
                "press enter shortcut prose guard"
            ),
            (
                "Explain how to press enter in docs.",
                "Explain how to press enter in docs.",
                "press enter prose guard"
            ),
            (
                "The press tab shortcut is useful.",
                "The press tab shortcut is useful.",
                "press tab shortcut prose guard"
            ),
            (
                "Explain how to press tab in docs.",
                "Explain how to press tab in docs.",
                "press tab prose guard"
            ),
            (
                "All caps is loud.",
                "All caps is loud.",
                "all caps prose guard"
            ),
            (
                "The all caps command is useful.",
                "The all caps command is useful.",
                "all caps command prose guard"
            ),
            (
                "I prefer lowercase VoiceInk.",
                "I prefer lowercase VoiceInk.",
                "lowercase prose guard"
            ),
            (
                "I am sorry this happened.",
                "I am sorry this happened.",
                "sorry prose guard"
            ),
            (
                "I am really sorry this happened.",
                "I am really sorry this happened.",
                "bare sorry apology intensifier guard"
            ),
            (
                "Sorry for the delay.",
                "Sorry for the delay.",
                "leading sorry apology guard"
            ),
            (
                "I said sorry yesterday.",
                "I said sorry yesterday.",
                "reported sorry apology guard"
            ),
            (
                "I am, um actually, not sure.",
                "I am actually, not sure.",
                "pause before actually prose guard"
            ),
            (
                "This is, hmm actually, pretty good.",
                "This is actually, pretty good.",
                "copula pause before actually prose guard"
            ),
            (
                "Like this is really good.",
                "this is really good.",
                "leading unpunctuated like filler before this clause"
            ),
            (
                "Like I think this works.",
                "I think this works.",
                "leading unpunctuated like filler before i clause"
            ),
            (
                "Like it is ready.",
                "it is ready.",
                "leading unpunctuated like filler before it clause"
            ),
            (
                "Like this model, the old one works.",
                "Like this model, the old one works.",
                "leading like comparison noun phrase guard"
            ),
            (
                "Like a model, this is compact.",
                "Like a model, this is compact.",
                "leading like article comparison guard"
            ),
            (
                "Basically this is ready.",
                "this is ready.",
                "leading basically filler before this clause"
            ),
            (
                "Basically, I think this works.",
                "I think this works.",
                "punctuated leading basically filler before i clause"
            ),
            (
                "Basically it is ready.",
                "it is ready.",
                "leading basically filler before it clause"
            ),
            (
                "Basically a model is just a function.",
                "Basically a model is just a function.",
                "leading basically article noun phrase guard"
            ),
            (
                "Basically the model is ready.",
                "Basically the model is ready.",
                "leading basically determiner noun phrase guard"
            ),
            (
                "So this is ready.",
                "this is ready.",
                "leading so filler before this clause"
            ),
            (
                "So this works.",
                "this works.",
                "leading so filler before this works clause"
            ),
            (
                "So, I think this works.",
                "I think this works.",
                "punctuated leading so filler before i clause"
            ),
            (
                "So... it is ready.",
                "it is ready.",
                "ellipsis leading so filler before it clause"
            ),
            (
                "So that we can ship, keep it stable.",
                "So that we can ship, keep it stable.",
                "leading so purpose clause guard"
            ),
            (
                "So long as this works, we can ship.",
                "So long as this works, we can ship.",
                "leading so long as guard"
            ),
            (
                "So the model is ready.",
                "So the model is ready.",
                "leading so determiner noun phrase guard"
            ),
            (
                "There is no wait time.",
                "There is no wait time.",
                "no wait prose guard"
            ),
            (
                "Please wait, module loads.",
                "Please wait, module loads.",
                "bare wait prose guard"
            ),
            (
                "Please hold on, module loads.",
                "Please hold on, module loads.",
                "hold on prose guard"
            ),
            (
                "Please hang on, module loads.",
                "Please hang on, module loads.",
                "hang on prose guard"
            ),
            (
                "On second thought, module loads.",
                "On second thought, module loads.",
                "on second thought prose guard"
            ),
            (
                "Let me rephrase, module loads.",
                "Let me rephrase, module loads.",
                "let me rephrase prose guard"
            ),
            (
                "To clarify, module loads.",
                "To clarify, module loads.",
                "to clarify prose guard"
            ),
            (
                "Just to clarify, module loads.",
                "Just to clarify, module loads.",
                "just to clarify prose guard"
            ),
            (
                "To be clear, module loads.",
                "To be clear, module loads.",
                "to be clear prose guard"
            ),
            (
                "Just to be clear, module loads.",
                "Just to be clear, module loads.",
                "just to be clear prose guard"
            ),
            (
                "For clarity, module loads.",
                "For clarity, module loads.",
                "for clarity prose guard"
            ),
            (
                "I mean to say, module loads.",
                "I mean to say, module loads.",
                "i mean to say prose guard"
            ),
            (
                "I meant to say, module loads.",
                "I meant to say, module loads.",
                "i meant to say prose guard"
            ),
            (
                "What I mean is, module loads.",
                "What I mean is, module loads.",
                "what i mean is prose guard"
            ),
            (
                "The phrase actually wait no is useful.",
                "The phrase actually wait no is useful.",
                "actually wait no phrase guard"
            ),
            (
                "Please delete that file.",
                "Please delete that file.",
                "delete that prose guard"
            ),
            (
                "Please cross that bridge.",
                "Please cross that bridge.",
                "cross that prose guard"
            ),
            (
                "The phrase actually wait nevermind is useful.",
                "The phrase actually wait nevermind is useful.",
                "actually wait nevermind phrase guard"
            ),
            (
                "We need to backtrack module changes.",
                "We need to backtrack module changes.",
                "backtrack prose guard"
            ),
            (
                "Please never mind the details.",
                "Please never mind the details.",
                "never mind prose guard"
            ),
            (
                "I would rather wait.",
                "I would rather wait.",
                "rather prose guard"
            ),
            (
                "Use model instead of module.",
                "Use model instead of module.",
                "instead of prose guard"
            ),
            (
                "Use local or actually cloud models.",
                "Use local or actually cloud models.",
                "or actually multi-word alternative guard"
            ),
            (
                "The phrase or actually is useful.",
                "The phrase or actually is useful.",
                "or actually phrase guard"
            ),
            (
                "I would instead wait.",
                "I would instead wait.",
                "instead prose guard"
            ),
            (
                "Scratch that itch.",
                "Scratch that itch.",
                "scratch command prose guard"
            ),
            (
                "Scratch this itch.",
                "Scratch this itch.",
                "scratch this command prose guard"
            ),
            (
                "I want to scratch that itch.",
                "I want to scratch that itch.",
                "inline scratch that prose guard"
            ),
            (
                "I want to scratch this itch.",
                "I want to scratch this itch.",
                "inline scratch this prose guard"
            ),
            (
                "I want to delete that file.",
                "I want to delete that file.",
                "inline delete that prose guard"
            ),
            (
                "I want to delete this file.",
                "I want to delete this file.",
                "inline delete this prose guard"
            ),
            (
                "Can you delete that file?",
                "Can you delete that file?",
                "request delete that prose guard"
            ),
            (
                "Can you delete this file?",
                "Can you delete this file?",
                "request delete this prose guard"
            ),
            (
                "I will ignore that warning.",
                "I will ignore that warning.",
                "inline ignore that prose guard"
            ),
            (
                "I will ignore this warning.",
                "I will ignore this warning.",
                "inline ignore this prose guard"
            ),
            (
                "Cancel that meeting.",
                "Cancel that meeting.",
                "cancel that prose guard"
            ),
            (
                "Cancel this meeting.",
                "Cancel this meeting.",
                "cancel this prose guard"
            ),
            (
                "Disregard that warning.",
                "Disregard that warning.",
                "disregard that prose guard"
            ),
            (
                "Disregard this warning.",
                "Disregard this warning.",
                "disregard this prose guard"
            ),
            (
                "Ignore that warning.",
                "Ignore that warning.",
                "ignore that prose guard"
            ),
            (
                "Ignore this warning.",
                "Ignore this warning.",
                "ignore this prose guard"
            ),
            (
                "Forget that idea.",
                "Forget that idea.",
                "forget that prose guard"
            ),
            (
                "Forget this idea.",
                "Forget this idea.",
                "forget this prose guard"
            ),
            (
                "Cut that cable.",
                "Cut that cable.",
                "cut that prose guard"
            ),
            (
                "Drop that topic.",
                "Drop that topic.",
                "drop that prose guard"
            ),
            (
                "New York New York is the title.",
                "New York New York is the title.",
                "intentional repeated phrase guard"
            ),
            (
                "I saw New York New York in the title.",
                "I saw New York New York in the title.",
                "inline intentional repeated phrase guard"
            ),
            (
                "He said I know, I know.",
                "He said I know, I know.",
                "inline intentional repeated clause guard"
            ),
            (
                "Use dot notation.",
                "Use dot notation.",
                "dot command prose guard"
            ),
            (
                "The question mark command is useful.",
                "The question mark command is useful.",
                "question mark command prose guard"
            ),
            (
                "The exclamation sign command is useful.",
                "The exclamation sign command is useful.",
                "exclamation sign command prose guard"
            ),
            (
                "The colon operator is useful.",
                "The colon operator is useful.",
                "colon operator prose guard"
            ),
            (
                "The ellipsis symbol is useful.",
                "The ellipsis symbol is useful.",
                "ellipsis symbol prose guard"
            ),
            (
                "The word api is lowercase in this example.",
                "The word api is lowercase in this example.",
                "literal acronym prose guard"
            ),
            (
                "Use api.url in the example.",
                "Use api.url in the example.",
                "dotted acronym token guard"
            ),
            (
                "The dash dash pattern is useful.",
                "The dash dash pattern is useful.",
                "dash dash prose guard"
            ),
            (
                "Quote from the docs.",
                "Quote from the docs.",
                "quote prose guard"
            ),
            (
                "The value in parentheses is optional.",
                "The value in parentheses is optional.",
                "in parentheses prose guard"
            ),
            (
                "This is like magic.",
                "This is like magic.",
                "like simile guard"
            ),
            (
                "This is a kind of model.",
                "This is a kind of model.",
                "kind of noun guard"
            ),
            (
                "I like that sort of work.",
                "I like that sort of work.",
                "sort of noun guard"
            ),
            (
                "This is kind of magic.",
                "This is kind of magic.",
                "kind of unlisted adjective guard"
            ),
            (
                "I meant what I said.",
                "I meant what I said.",
                "i meant prose guard"
            ),
            (
                "Oops, I forgot the model.",
                "Oops, I forgot the model.",
                "leading oops prose guard"
            ),
            (
                "Oops actually I forgot the model.",
                "Oops actually I forgot the model.",
                "leading oops actually prose guard"
            ),
            (
                "My bad idea still works.",
                "My bad idea still works.",
                "my bad prose guard"
            ),
            (
                "The correction module is ready.",
                "The correction module is ready.",
                "correction prose guard"
            ),
            (
                "We can actually make it work.",
                "We can actually make it work.",
                "actually make it prose guard"
            ),
            (
                "We had better make it work.",
                "We had better make it work.",
                "better make it prose guard"
            ),
            (
                "I should say this carefully.",
                "I should say this carefully.",
                "i should say prose guard"
            ),
            (
                "Please make that red.",
                "Please make that red.",
                "make that prose guard"
            ),
            (
                "We can make that work.",
                "We can make that work.",
                "make that clause prose guard"
            ),
            (
                "Please call it module.",
                "Please call it module.",
                "call it prose guard"
            ),
            (
                "We can call it done.",
                "We can call it done.",
                "call it clause prose guard"
            ),
            (
                "This, however, works.",
                "This, however, works.",
                "embedded comma prose guard"
            ),
            (
                "I lost twenty pounds.",
                "I lost twenty pounds.",
                "currency cleanup weight guard"
            ),
            (
                "This is a trial period",
                "This is a trial period",
                "period command prose guard"
            ),
            (
                "Use the Oxford comma",
                "Use the Oxford comma",
                "comma command prose guard"
            ),
            (
                "I know you know.",
                "I know you know.",
                "terminal you know guard"
            ),
            (
                "You know this already.",
                "You know this already.",
                "leading you know prose guard"
            ),
            (
                "you know?",
                "you know?",
                "standalone you know question guard"
            ),
            (
                "I mean business.",
                "I mean business.",
                "leading i mean prose guard"
            ),
            (
                "I mean the model is ready.",
                "I mean the model is ready.",
                "unpunctuated leading i mean determiner noun phrase guard"
            ),
            (
                "Well water is clean.",
                "Well water is clean.",
                "leading well noun phrase guard"
            ),
            (
                "Okay well water is clean.",
                "Okay well water is clean.",
                "leading okay well noun phrase guard"
            ),
            (
                "Okay yeah the model is ready.",
                "Okay yeah the model is ready.",
                "leading okay yeah determiner noun phrase guard"
            ),
            (
                "Yeah this works.",
                "Yeah this works.",
                "single yeah acknowledgement prose guard"
            ),
            (
                "um yeah the model is ready.",
                "yeah the model is ready.",
                "pause plus yeah determiner noun phrase guard"
            ),
            (
                "um yeah right this works.",
                "yeah right this works.",
                "pause plus literal yeah right guard"
            ),
            (
                "Yeah right this works.",
                "Yeah right this works.",
                "literal yeah right prose guard"
            ),
            (
                "Yeah right, this works.",
                "Yeah right, this works.",
                "comma literal yeah right prose guard"
            ),
            (
                "Yeah, right, this works.",
                "Yeah, right, this works.",
                "punctuated literal yeah right prose guard"
            ),
            (
                "Okay right the model is ready.",
                "Okay right the model is ready.",
                "leading okay right determiner noun phrase guard"
            ),
            (
                "Wellness works.",
                "Wellness works.",
                "wellness word boundary guard"
            ),
            (
                "Okay, this works.",
                "Okay, this works.",
                "okay prose guard"
            ),
            (
                "Okay, I mean business.",
                "Okay, I mean business.",
                "okay i mean prose guard"
            ),
            (
                "All right, I mean business.",
                "All right, I mean business.",
                "all right i mean prose guard"
            ),
            (
                "Well, I mean business.",
                "Well, I mean business.",
                "well i mean prose guard"
            ),
            (
                "Right, like magic happens.",
                "Right, like magic happens.",
                "right like simile guard"
            ),
            (
                "Right, this works.",
                "Right, this works.",
                "right prose guard"
            ),
            (
                "Do you know what I mean?",
                "Do you know what I mean?",
                "terminal you know what I mean guard"
            ),
            (
                "\"What?\".",
                "\"What?\".",
                "punctuation before closing quote guard"
            ),
            (
                "【What?】",
                "【What?】",
                "punctuation before non-ascii closing boundary guard"
            )
        ]

        for testCase in filterCases {
            let output = RomaTranscriptionOutputFilter.filter(testCase.input, removesFillerWords: true)
            try require(
                output == testCase.expected,
                "post-STT cleanup corpus failed \(testCase.note); output=\(output)"
            )
        }

        try require(
            RomaTranscriptionOutputFilter.filter(
                "hmm... Hello comma world. Hello comma world.",
                cleanupLevel: .raw,
                removesFillerWords: true
            ) == "hmm... Hello comma world. Hello comma world.",
            "raw cleanup should preserve fillers and spoken commands"
        )
        try require(
            RomaTranscriptionOutputFilter.filter(
                "This, um, works.",
                cleanupLevel: .raw,
                removesFillerWords: true
            ) == "This, um, works.",
            "raw cleanup should preserve embedded pause punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.filter(
                "Wrong phrase scratch that. Right phrase.",
                cleanupLevel: .light,
                removesFillerWords: true
            ) == "Wrong phrase scratch that. Right phrase.",
            "light cleanup should preserve backtracking erase commands"
        )
        try require(
            RomaTranscriptionOutputFilter.filter(
                "This, um, works.",
                cleanupLevel: .light,
                removesFillerWords: true
            ) == "This, um, works.",
            "light cleanup should preserve embedded pause punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.filter(
                "This, um, works.",
                removesFillerWords: true
            ) == "This works.",
            "polished cleanup should remove embedded pause punctuation"
        )

        let midSentenceContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "...so this")
        let listIntroContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Tasks:")
        let wordContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Use")
        let compactTokenContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "docs")
        let emailUserContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "felix")
        let variableContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "user")
        let unmatchedStraightQuoteContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "She said \"hello")
        let openSmartQuoteContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "She said “")
        let closingSmartQuoteContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "She said “hello”")
        let closingSmartSingleQuoteContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "She said ‘hello’")
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.", context: midSentenceContext) == "model",
            "insertion polish should lowercase final mid-sentence word"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.\"", context: midSentenceContext) == "model",
            "insertion polish should remove trailing generated quotes after final punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!\"", context: midSentenceContext) == "model",
            "insertion polish should remove trailing generated quotes after emphatic punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!”", context: midSentenceContext) == "model",
            "insertion polish should remove trailing smart quotes after emphatic punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model?\"", context: midSentenceContext) == "model",
            "insertion polish should remove trailing generated quotes after noisy question punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model!]", context: midSentenceContext) == "model",
            "insertion polish should remove trailing generated brackets after emphatic punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model?)", context: midSentenceContext) == "model",
            "insertion polish should remove trailing generated parens after noisy question punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("【Model!】", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy emphatic corner-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("What?\"", context: midSentenceContext) == "what?\"",
            "insertion polish should preserve trailing quotes after question words"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("【What?】", context: midSentenceContext) == "【what?】",
            "insertion polish should preserve corner-bracketed question words"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing(
                RomaTranscriptionOutputFilter.applyInsertionPolish(
                    RomaTranscriptionOutputFilter.filter("【What?】"),
                    context: midSentenceContext
                ),
                context: midSentenceContext
            ) == " 【what?】",
            "insertion pipeline should not add internal spacing before non-ascii closing boundaries"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("What?]", context: midSentenceContext) == "what?]",
            "insertion polish should preserve trailing brackets after question words"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("U.S.\"", context: midSentenceContext) == "U.S.",
            "insertion polish should preserve abbreviation periods when removing trailing generated quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("hello", context: openSmartQuoteContext) == "hello",
            "insertion spacing should not add space after opening smart quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("again", context: closingSmartQuoteContext) == " again",
            "insertion spacing should add space after closing smart quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("again", context: closingSmartSingleQuoteContext) == " again",
            "insertion spacing should add space after closing smart single quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing(
                "1. finish the report",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done\n")
            ) == "1. finish the report",
            "insertion spacing should not add a list boundary after an existing newline"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("”", context: wordContext) == "”",
            "insertion spacing should not add space before closing smart quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("’", context: wordContext) == "’",
            "insertion spacing should not add space before closing smart single quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("]", context: wordContext) == "]",
            "insertion spacing should not add space before closing brackets"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("}", context: wordContext) == "}",
            "insertion spacing should not add space before closing braces"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "Model is actually ready.",
                context: midSentenceContext
            ) == "model is actually ready",
            "insertion polish should strip auto period from longer mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "A Final Word.",
                context: midSentenceContext
            ) == "a final word",
            "insertion polish should lowercase title-cased short mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The LLM Router.",
                context: midSentenceContext
            ) == "the LLM router",
            "insertion polish should lowercase title-cased tech nouns after acronyms"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The iOS App.",
                context: midSentenceContext
            ) == "the iOS app",
            "insertion polish should lowercase title-cased tech nouns after mixed-case product tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "The URL Parser.",
                context: midSentenceContext
            ) == "the URL parser",
            "insertion polish should lowercase title-cased parser nouns after acronyms"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "New York.",
                context: midSentenceContext
            ) == "New York",
            "insertion polish should preserve proper-name short mid-sentence phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "Model is actually ready!",
                context: midSentenceContext
            ) == "model is actually ready!",
            "insertion polish should preserve explicit emphatic mid-sentence fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "First sentence. Second sentence.",
                context: midSentenceContext
            ) == "first sentence. Second sentence.",
            "insertion polish should preserve trailing period on multi-sentence mid-sentence text"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[Model.]", context: nil) == "model",
            "insertion polish should unwrap bracketed final fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[Model.].", context: nil) == "model",
            "insertion polish should unwrap bracketed final fragments with outer punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[Model!]", context: nil) == "model",
            "insertion polish should strip noisy punctuation from bracketed final fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[A final word.]", context: nil) == "a final word",
            "insertion polish should strip noisy punctuation from bracketed final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[A final word.].", context: nil) == "a final word",
            "insertion polish should strip noisy punctuation from bracketed final phrases with outer punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[A final word!]", context: nil) == "a final word",
            "insertion polish should strip noisy sentence marks from bracketed final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<Model.>", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy angle-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "< A final word. >",
                context: midSentenceContext
            ) == "a final word",
            "insertion polish should unwrap spaced angle-bracketed phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<[Model.]>", context: midSentenceContext) == "model",
            "insertion polish should unwrap angle-wrapped square-bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "\"[A final word.]\".",
                context: midSentenceContext
            ) == "\"a final word\"",
            "insertion polish should unwrap quoted square-bracketed final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<【Model.】>", context: midSentenceContext) == "model",
            "insertion polish should unwrap angle-wrapped full-width bracketed fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<|Model.|>", context: midSentenceContext) == "model",
            "insertion polish should unwrap angle-wrapped pipe fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("<model>", context: midSentenceContext) == "<model>",
            "insertion polish should preserve literal angle tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("*Model.*", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy starred fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("_Model._", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy underscored fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("**Model.**", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy bold markdown fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("__Model.__", context: midSentenceContext) == "model",
            "insertion polish should unwrap noisy bold underscore fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("*model*", context: midSentenceContext) == "*model*",
            "insertion polish should preserve literal starred tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("_model_", context: midSentenceContext) == "_model_",
            "insertion polish should preserve literal underscored tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("• Model.", context: midSentenceContext) == "model",
            "insertion polish should remove leading bullet fragment noise"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1. Model.", context: midSentenceContext) == "model",
            "insertion polish should remove generated numbered fragment markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1) Model.", context: midSentenceContext) == "model",
            "insertion polish should remove generated parenthesized number markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("# Model.", context: midSentenceContext) == "model",
            "insertion polish should remove generated heading fragment markers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("1. Model.", context: listIntroContext) == "1. model",
            "insertion polish should preserve numbered markers after list introducers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("# Model.", context: listIntroContext) == "# model",
            "insertion polish should preserve heading markers after list introducers"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("'Model.'", context: nil) == "'model'",
            "insertion polish should strip noisy periods inside single-quoted final words"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"A final word.\"", context: nil) == "\"a final word\"",
            "insertion polish should strip noisy periods inside quoted final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"A final word.\".", context: nil) == "\"a final word\"",
            "insertion polish should strip outer punctuation after quoted final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("“A final word.”.", context: nil) == "“a final word”",
            "insertion polish should strip outer punctuation after smart-quoted final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("(A final word.).", context: nil) == "(a final word)",
            "insertion polish should strip outer punctuation after parenthesized final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\"U.S.\"", context: nil) == "\"U.S.\"",
            "insertion polish should preserve quoted abbreviation periods"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "\"This is a longer sentence.\"",
                context: nil
            ) == "\"This is a longer sentence.\"",
            "insertion polish should preserve quoted full-sentence periods"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "\"This is a longer sentence.\".",
                context: nil
            ) == "\"This is a longer sentence.\"",
            "insertion polish should strip redundant outer punctuation after quoted full sentences"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("It works. [Model.]", context: nil) ==
                "It works. [Model.]",
            "insertion polish should preserve inline bracketed fragments after complete sentences"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("It works, [Model.]", context: nil) ==
                "It works, [Model.]",
            "insertion polish should preserve inline bracketed fragments after complete clauses"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("It works. \"[Model.]\"", context: nil) ==
                "It works. \"[Model.]\"",
            "insertion polish should preserve inline quoted bracket fragments after complete sentences"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("... Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading ellipsis from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("— Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading dashes from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(": Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading separators from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("/ Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading slash separators from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("\\ Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading backslash separators from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("| Model.", context: midSentenceContext) == "model",
            "insertion polish should strip leading pipe separators from short fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("/users", context: wordContext) == "/users",
            "insertion polish should preserve compact leading slash fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("|model", context: wordContext) == "|model",
            "insertion polish should preserve compact leading pipe fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("This is good.", context: nil) == "This is good.",
            "insertion polish should preserve no-context full sentence capitalization"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model is actually ready.", context: nil) ==
                "Model is actually ready.",
            "insertion polish should preserve no-context longer sentence punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("... This is good.", context: nil) == "This is good.",
            "insertion polish should strip leading pause ellipsis from full sentences"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(".env file.", context: nil) == ".env file.",
            "insertion polish should preserve leading dot tokens"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "This is good.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "This is good.",
            "insertion polish should preserve sentence-start full sentence punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "Model is actually ready.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "Model is actually ready.",
            "insertion polish should preserve longer sentence-start punctuation"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Question mark.", context: midSentenceContext) == "?",
            "insertion polish should attach standalone punctuation commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Ellipsis.", context: midSentenceContext) == "...",
            "insertion polish should attach standalone ellipsis commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Dot dot dot.", context: midSentenceContext) == "...",
            "insertion polish should attach standalone dot dot dot commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Em dash.", context: midSentenceContext) == " —",
            "insertion polish should attach standalone em dash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("M-dash.", context: midSentenceContext) == " —",
            "insertion polish should attach standalone hyphenated m-dash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Emdash.", context: midSentenceContext) == " —",
            "insertion polish should attach standalone compact emdash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Slash.", context: compactTokenContext) == "/",
            "insertion polish should attach standalone slash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Forward slash.", context: compactTokenContext) == "/",
            "insertion polish should attach standalone forward slash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Backslash.", context: compactTokenContext) == "\\",
            "insertion polish should attach standalone backslash commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Dot.", context: compactTokenContext) == ".",
            "insertion polish should attach standalone dot commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Hyphen.", context: compactTokenContext) == "-",
            "insertion polish should attach standalone hyphen commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("At sign.", context: emailUserContext) == "@",
            "insertion polish should attach standalone at sign commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("@", context: emailUserContext) == "@",
            "insertion spacing should not add a space before at signs"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Underscore.", context: variableContext) == "_",
            "insertion polish should attach standalone underscore commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("_", context: variableContext) == "_",
            "insertion spacing should not add a space before underscores"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "Ellipsis.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "Ellipsis",
            "insertion polish should not attach standalone ellipsis at sentence start"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "M-dash.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "M-dash.",
            "insertion polish should not attach standalone m-dash at sentence start"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "Slash.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "Slash",
            "insertion polish should not attach standalone slash at sentence start"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                "At sign.",
                context: RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "Done. ")
            ) == "At sign.",
            "insertion polish should not attach standalone at sign at sentence start"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Comma.", context: closingSmartQuoteContext) == ",",
            "insertion polish should attach comma commands after closing smart quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Question mark.", context: closingSmartSingleQuoteContext) == "?",
            "insertion polish should attach question mark commands after closing smart single quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Open quote.", context: wordContext) == "\"",
            "insertion polish should attach standalone open quote commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("\"", context: wordContext) == " \"",
            "insertion spacing should add a space before standalone opening straight quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Close quote.", context: unmatchedStraightQuoteContext) == "\"",
            "insertion polish should attach standalone close quote commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("\"", context: unmatchedStraightQuoteContext) == "\"",
            "insertion spacing should attach standalone closing straight quotes"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                RomaTranscriptionOutputFilter.filter("Close quote."),
                context: unmatchedStraightQuoteContext
            ) == "\"",
            "insertion polish should strip auto periods after filtered standalone quote commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Open parenthesis.", context: wordContext) == "(",
            "insertion polish should attach standalone open parenthesis commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("(", context: wordContext) == " (",
            "insertion spacing should add a space before standalone opening parenthesis commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("End parenthesis.", context: variableContext) == ")",
            "insertion polish should attach standalone end parenthesis commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Close bracket.", context: variableContext) == "]",
            "insertion polish should attach standalone close bracket commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionSpacing("]", context: variableContext) == "]",
            "insertion spacing should attach standalone closing bracket commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("End brace.", context: variableContext) == "}",
            "insertion polish should attach standalone end brace commands"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish(
                RomaTranscriptionOutputFilter.filter("Open bracket."),
                context: wordContext
            ) == "[",
            "insertion polish should strip auto periods after filtered standalone bracket commands"
        )
    }

    private static func checkWordReplacementProcessor() throws {
        let rules = [
            RomaWordReplacementRule(originalText: "model context protocol", replacementText: "MCP"),
            RomaWordReplacementRule(originalText: "model", replacementText: "ignored-shorter"),
            RomaWordReplacementRule(originalText: "roma, just talk", replacementText: "roma-just-talk"),
            RomaWordReplacementRule(originalText: "disabled", replacementText: "enabled", isEnabled: false)
        ]

        let replacementOutput = RomaWordReplacementProcessor.apply(
            rules,
            to: "Use model context protocol with just talk, not disabled."
        )
        try require(
            replacementOutput == "Use MCP with roma-just-talk, not disabled.",
            "word replacements should apply enabled longest-first comma variants; output=\(replacementOutput)"
        )
        try require(
            RomaWordReplacementProcessor.apply(
                [RomaWordReplacementRule(originalText: "cat", replacementText: "dog")],
                to: "cat scatter cat."
            ) == "dog scatter dog.",
            "spaced-script replacements should respect word boundaries"
        )
        try require(
            RomaWordReplacementProcessor.apply(
                [RomaWordReplacementRule(originalText: "東京", replacementText: "Tokyo")],
                to: "東京駅"
            ) == "Tokyo駅",
            "non-spaced-script replacements should fall back to substring replacement"
        )
    }

    private static func checkCommandLineOptions() throws {
        let options = RomaCommandLineOptions([
            "--seconds", "2.5",
            "--replace", "just talk=roma-just-talk",
            "--replace", "model context protocol=MCP",
            "--api-key-env", "ROMA_KEY"
        ])

        try require(options.contains("--seconds"), "options should detect present flags")
        try require(!options.contains("--paste"), "options should detect absent flags")
        try require(try options.doubleValue(after: "--seconds", default: 1) == 2.5, "options should parse doubles")
        try require(try options.doubleValue(after: "--missing", default: 7) == 7, "options should use numeric defaults")
        try require(options.optionalValue(after: "--missing") == nil, "missing optional values should be nil")

        let rules = try RomaCommandLineText.wordReplacementRules(from: options)
        try require(
            rules == [
                RomaWordReplacementRule(originalText: "just talk", replacementText: "roma-just-talk"),
                RomaWordReplacementRule(originalText: "model context protocol", replacementText: "MCP")
            ],
            "command-line replacement rules should parse repeated --replace values"
        )
        try require(
            RomaCommandLineText.isValidEnvironmentName("ROMA_KEY_1"),
            "environment names should allow letters, underscores, and digits after the first character"
        )
        try require(
            !RomaCommandLineText.isValidEnvironmentName("1ROMA_KEY"),
            "environment names should reject leading digits"
        )

        let keySource = try TranscriptionAPIKeySource.make(from: options)
        try require(keySource == .environment(name: "ROMA_KEY"), "api key source should parse environment options")

        do {
            _ = try TranscriptionAPIKeySource.make(from: RomaCommandLineOptions([
                "--api-key-env", "ROMA_KEY",
                "--api-key-name", "groq"
            ]))
            throw CheckFailure("api key parser should reject conflicting key sources")
        } catch RomaCommandLineOptionsError.conflictingOptions {
        }

        do {
            _ = try RomaCommandLineText.wordReplacementRule(from: "missing equals")
            throw CheckFailure("replacement parser should reject malformed values")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }
    }

    private static func checkWindowsAgentConfiguration() throws {
        let base = RomaWindowsAgentConfiguration(
            endpoint: "https://api.example.com/v1/audio/transcriptions",
            model: "base-model",
            apiKeyName: "groq",
            shouldPaste: false,
            restoreClipboardAfterPaste: false,
            usesHoldHook: false,
            recordSeconds: 2,
            wordReplacements: [
                RomaWordReplacementRule(originalText: "base", replacementText: "BASE")
            ]
        )
        let merged = try base.applyingOverrides(from: RomaCommandLineOptions([
            "--model", "override-model",
            "--api-key-env", "ROMA_KEY",
            "--hold-hook",
            "--paste",
            "--restore-clipboard",
            "--clipboard-restore-delay", "0.75",
            "--timeout", "22",
            "--replace", "just talk=roma-just-talk"
        ]))

        try require(try merged.requireEndpoint() == "https://api.example.com/v1/audio/transcriptions", "config should keep endpoint")
        try require(try merged.requireModel() == "override-model", "CLI should override model")
        try require(merged.apiKeyEnvironment == "ROMA_KEY", "CLI env key should override stored key")
        try require(merged.apiKeyName == nil, "CLI env key should clear stored key name")
        try require(merged.shouldPaste == true, "CLI paste flag should enable paste")
        try require(merged.restoreClipboardAfterPaste == true, "CLI restore flag should enable clipboard restore")
        try require(merged.clipboardRestoreDelaySeconds == 0.75, "CLI restore delay should override config")
        try require(
            RomaWindowsAgentConfiguration.defaultRecordSeconds == 2,
            "Windows agent default record duration should stay shared"
        )
        try require(
            RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds == 15,
            "Windows agent default hold timeout should stay shared"
        )
        try require(
            RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds == 15_000,
            "Windows agent default hold timeout milliseconds should stay shared"
        )
        try require(
            WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds == 2,
            "Windows clipboard restore default delay should stay shared"
        )
        try require(
            WindowsClipboardRestoreConfiguration().restoreDelaySeconds ==
                WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds,
            "Windows clipboard restore configuration should use the shared default delay"
        )
        try require(
            WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(fromSeconds: 0.75) == 750,
            "Windows clipboard restore delay conversion should use shared milliseconds"
        )
        try require(
            WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(
                fromSeconds: WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds
            ) == 2_000,
            "Windows clipboard restore default delay should convert to milliseconds"
        )
        try require(
            WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(
                fromSeconds: WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds
            ) == UInt32.max,
            "Windows clipboard restore maximum delay should fit Sleep milliseconds"
        )
        try require(
            WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(fromSeconds: .nan) == nil,
            "Windows clipboard restore delay conversion should reject NaN"
        )
        try require(
            WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds(
                fromSeconds: WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds + 0.001
            ) == nil,
            "Windows clipboard restore delay conversion should reject values above Sleep range"
        )
        try require(
            RomaWindowsAgentConfiguration().clipboardRestoreConfiguration().restoreDelaySeconds ==
                WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds,
            "Windows agent clipboard restore configuration should use the shared default delay"
        )
        try require(
            try RomaWindowsAgentConfiguration().resolvedRecordDurationNanoseconds() == 2_000_000_000,
            "Windows default record duration conversion should stay shared"
        )
        try require(
            try RomaWindowsAgentConfiguration(
                recordSeconds: RomaWindowsAgentConfiguration.minimumRecordSeconds
            ).resolvedRecordDurationNanoseconds() == 1,
            "Windows record duration conversion should preserve the minimum nanosecond"
        )
        try require(
            merged.clipboardRestoreConfiguration() == WindowsClipboardRestoreConfiguration(
                restoreClipboard: true,
                restoreDelaySeconds: 0.75
            ),
            "merged config should resolve clipboard restore settings"
        )
        try require(merged.usesHoldHook == true, "CLI hold flag should enable hold mode")
        try require(merged.holdTimeoutSeconds == 22, "CLI timeout should override hold timeout")
        try require(
            try merged.resolvedHoldTimeoutMilliseconds() == 22_000,
            "Windows hold timeout conversion should be shared"
        )
        try require(
            try RomaWindowsAgentConfiguration(holdTimeoutSeconds: 0.001).resolvedHoldTimeoutMilliseconds() == 1,
            "Windows hold timeout conversion should preserve the minimum millisecond"
        )
        try require(
            try RomaWindowsAgentConfiguration().resolvedHoldTimeoutMilliseconds() ==
                RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds,
            "Windows default hold timeout conversion should use the shared millisecond default"
        )
        try require(
            merged.wordReplacements == [
                RomaWordReplacementRule(originalText: "just talk", replacementText: "roma-just-talk")
            ],
            "CLI replacement values should override config replacements"
        )
        try require(
            try merged.apiKeySource() == .environment(name: "ROMA_KEY"),
            "merged config should resolve env key source"
        )

        let localWhisper = try merged.applyingOverrides(from: RomaCommandLineOptions([
            "--whisper-cli", "/tools/whisper-cli",
            "--whisper-model", "/models/ggml-base.en.bin",
            "--whisper-output-dir", "/tmp/roma-whisper",
            "--whisper-arg", "--beam-size",
            "--whisper-arg", "1"
        ]))
        try require(localWhisper.usesWhisperCLI, "whisper CLI config should select local transcription")
        try require(localWhisper.endpoint == nil, "whisper CLI override should clear cloud endpoint")
        try require(localWhisper.model == nil, "whisper CLI override should clear cloud model")
        try require(localWhisper.apiKeyEnvironment == nil, "whisper CLI override should clear env key")
        try require(localWhisper.apiKeyName == nil, "whisper CLI override should clear stored key")
        try require(
            localWhisper.whisperExtraArguments == ["--beam-size", "1"],
            "whisper CLI config should preserve repeated extra args"
        )
        try localWhisper.validateTranscriptionSettings()
        let whisperCLIConfiguration = try localWhisper.whisperCLIConfiguration()
        try require(
            whisperCLIConfiguration.executableURL.path == "/tools/whisper-cli",
            "whisper CLI config should resolve executable URL"
        )
        try require(
            whisperCLIConfiguration.modelURL.path == "/models/ggml-base.en.bin",
            "whisper CLI config should resolve model URL"
        )

        let cloudAgain = try localWhisper.applyingOverrides(from: RomaCommandLineOptions([
            "--endpoint", "https://api.example.com/v1/audio/transcriptions",
            "--model", "cloud-model",
            "--api-key-env", "ROMA_KEY"
        ]))
        try require(!cloudAgain.usesWhisperCLI, "cloud override should clear local whisper mode")
        try require(cloudAgain.whisperCLIPath == nil, "cloud override should clear whisper CLI path")
        try require(cloudAgain.whisperModelPath == nil, "cloud override should clear whisper model path")
        try require(
            try cloudAgain.requireModel() == "cloud-model",
            "cloud override should keep cloud model"
        )

        let url = URL(fileURLWithPath: "/tmp/roma-windows-agent-config-check.json")
        try merged.write(to: url)
        let loaded = try RomaWindowsAgentConfiguration.load(from: url)
        try require(loaded == merged, "config should round-trip through JSON")

        do {
            _ = try RomaWindowsAgentConfiguration(
                apiKeyEnvironment: "ROMA_KEY",
                apiKeyName: "groq"
            ).apiKeySource()
            throw CheckFailure("config should reject conflicting api key sources")
        } catch RomaCommandLineOptionsError.conflictingOptions {
        }

        do {
            try RomaWindowsAgentConfiguration(
                restoreClipboardAfterPaste: false,
                clipboardRestoreDelaySeconds: 2
            ).validate()
            throw CheckFailure("config should reject restore delay when clipboard restore is disabled")
        } catch RomaCommandLineOptionsError.conflictingOptions {
        }

        do {
            try RomaWindowsAgentConfiguration(recordSeconds: 0).validate()
            throw CheckFailure("config should reject zero toggle record duration")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                recordSeconds: RomaWindowsAgentConfiguration.minimumRecordSeconds / 2
            ).validate()
            throw CheckFailure("config should reject toggle durations below nanosecond resolution")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(holdTimeoutSeconds: 0).validate()
            throw CheckFailure("config should reject zero hold timeout")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                holdTimeoutSeconds: RomaWindowsAgentConfiguration.minimumHoldTimeoutSeconds / 2
            ).validate()
            throw CheckFailure("config should reject hold timeouts below millisecond resolution")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(recordSeconds: .infinity).validate()
            throw CheckFailure("config should reject non-finite toggle record duration")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                recordSeconds: RomaWindowsAgentConfiguration.maximumRecordSeconds + 1
            ).validate()
            throw CheckFailure("config should reject oversized toggle record duration")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                holdTimeoutSeconds: RomaWindowsAgentConfiguration.maximumHoldTimeoutSeconds + 1
            ).validate()
            throw CheckFailure("config should reject oversized hold timeout")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(clipboardRestoreDelaySeconds: .nan).validate()
            throw CheckFailure("config should reject non-finite clipboard restore delay")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                clipboardRestoreDelaySeconds: WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds + 1
            ).validate()
            throw CheckFailure("config should reject oversized clipboard restore delay")
        } catch RomaCommandLineOptionsError.invalidOptionValue {
        }

        do {
            try RomaWindowsAgentConfiguration(
                endpoint: "https://api.example.com/v1/audio/transcriptions",
                model: "cloud-model",
                apiKeyEnvironment: "ROMA_KEY",
                whisperCLIPath: "/tools/whisper-cli",
                whisperModelPath: "/models/ggml-base.en.bin"
            ).validateTranscriptionSettings()
            throw CheckFailure("config should reject mixed cloud and whisper CLI transcription settings")
        } catch RomaCommandLineOptionsError.conflictingOptions {
        }
    }

    private static func checkWindowsHotKeyProofDescriptor() throws {
        let hotKey = WindowsHotKey.proofToggle

        try require(hotKey.id == 1, "proof hotkey should use the thread-local proof id")
        try require(hotKey.modifiers.contains(.control), "proof hotkey should include Ctrl")
        try require(hotKey.modifiers.contains(.shift), "proof hotkey should include Shift")
        try require(hotKey.modifiers.contains(.noRepeat), "proof hotkey should avoid auto-repeat")
        try require(!hotKey.modifiers.contains(.win), "proof hotkey should avoid OS-reserved Win key chords")
        try require(hotKey.modifiers.rawValue == 0x4006, "proof hotkey should map to Ctrl+Shift+MOD_NOREPEAT")
        try require(hotKey.virtualKeyCode == 0x52, "proof hotkey should use virtual-key R")
        try require(hotKey.displayName == "Ctrl+Shift+R", "proof hotkey display name should be readable")

        #if !os(Windows)
        let proofSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RomaCore/Windows/WindowsRegisterHotKeyProof.swift"),
            encoding: .utf8
        )
        try require(
            proofSource.contains("assertRegistrationAvailable") &&
                proofSource.contains("RegisterHotKey(nil, hotKey.id") &&
                proofSource.contains("UnregisterHotKey(nil, hotKey.id)"),
            "Windows hotkey proof should expose a register/unregister availability check"
        )
        #endif
    }

    private static func checkWindowsLowLevelKeyboardHookProofDescriptor() throws {
        let chord = WindowsLowLevelKeyboardHookChord.proofHold

        try require(chord.virtualKeyCode == 0x52, "low-level hook proof should use virtual-key R")
        try require(
            chord.requiredModifiers == 0x3,
            "low-level hook proof should require Ctrl+Shift"
        )
        try require(chord.displayName == "Ctrl+Shift+R", "low-level hook proof should match the hotkey proof")

        let result = WindowsLowLevelKeyboardHookResult(
            observedEvents: 0x3
        )
        try require(result.observedKeyDown, "low-level hook result should expose keydown")
        try require(result.observedKeyUp, "low-level hook result should expose keyup")

        if !WindowsLowLevelKeyboardHookProof.isRuntimeAvailable {
            do {
                _ = try WindowsLowLevelKeyboardHookProof.waitForHold(timeoutMilliseconds: 1)
                throw CheckFailure("low-level hook should be unsupported off Windows")
            } catch WindowsLowLevelKeyboardHookError.unsupported {
            }
            do {
                _ = try WindowsLowLevelKeyboardHookProof.waitForKeyDown(timeoutMilliseconds: 1)
                throw CheckFailure("low-level hook keydown wait should be unsupported off Windows")
            } catch WindowsLowLevelKeyboardHookError.unsupported {
            }
            do {
                _ = try WindowsLowLevelKeyboardHookProof.waitForKeyUp(timeoutMilliseconds: 1)
                throw CheckFailure("low-level hook keyup wait should be unsupported off Windows")
            } catch WindowsLowLevelKeyboardHookError.unsupported {
            }
        }
    }

    private static func checkWindowsDictationRuntimeDescriptor() async throws {
        guard !WindowsDictationRuntime.isRuntimeAvailable else { return }

        try WindowsDictationRuntime.validateTrigger(.toggle(recordSeconds: 1))
        try WindowsDictationRuntime.validateTrigger(.hold(timeoutMilliseconds: 1))

        do {
            try WindowsDictationRuntime.validateTrigger(.toggle(recordSeconds: 0))
            throw CheckFailure("Windows dictation runtime should reject zero toggle record duration")
        } catch WindowsDictationRuntimeError.invalidRecordDuration(_) {
        }

        do {
            try WindowsDictationRuntime.validateTrigger(
                .toggle(recordSeconds: RomaWindowsAgentConfiguration.minimumRecordSeconds / 2)
            )
            throw CheckFailure("Windows dictation runtime should reject toggle durations below nanosecond resolution")
        } catch WindowsDictationRuntimeError.invalidRecordDuration(_) {
        }

        do {
            try WindowsDictationRuntime.validateTrigger(.toggle(recordSeconds: .infinity))
            throw CheckFailure("Windows dictation runtime should reject non-finite toggle record duration")
        } catch WindowsDictationRuntimeError.invalidRecordDuration(_) {
        }

        do {
            try WindowsDictationRuntime.validateTrigger(
                .toggle(recordSeconds: RomaWindowsAgentConfiguration.maximumRecordSeconds + 1)
            )
            throw CheckFailure("Windows dictation runtime should reject oversized toggle record duration")
        } catch WindowsDictationRuntimeError.invalidRecordDuration(_) {
        }

        do {
            try WindowsDictationRuntime.validateTrigger(.hold(timeoutMilliseconds: 0))
            throw CheckFailure("Windows dictation runtime should reject zero hold timeout")
        } catch WindowsDictationRuntimeError.invalidHoldTimeoutMilliseconds(_) {
        }

        let model = TranscriptionModelDescriptor(
            name: "proof",
            displayName: "Proof",
            provider: .custom
        )
        let request = WindowsDictationRuntimeRequest(
            outputURL: URL(fileURLWithPath: "/tmp/windows-runtime-proof.wav"),
            model: model,
            trigger: .toggle(recordSeconds: 1)
        )
        try WindowsDictationRuntime.validateRequest(request)
        try WindowsDictationRuntime.validateRequest(
            WindowsDictationRuntimeRequest(
                outputURL: URL(fileURLWithPath: "/tmp/windows-runtime-proof.wav"),
                model: model,
                shouldPaste: true,
                clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration(
                    restoreClipboard: false,
                    restoreDelaySeconds: .infinity
                ),
                trigger: .toggle(recordSeconds: 1)
            )
        )

        do {
            try WindowsDictationRuntime.validateRequest(
                WindowsDictationRuntimeRequest(
                    outputURL: URL(fileURLWithPath: "/tmp/windows-runtime-proof.wav"),
                    model: model,
                    shouldPaste: true,
                    clipboardRestoreConfiguration: WindowsClipboardRestoreConfiguration(
                        restoreDelaySeconds: .nan
                    ),
                    trigger: .toggle(recordSeconds: 1)
                )
            )
            throw CheckFailure("Windows dictation runtime should reject non-finite clipboard restore delay")
        } catch WindowsDictationRuntimeError.invalidClipboardRestoreDelay(_) {
        }

        do {
            _ = try await WindowsDictationRuntime.run(
                request,
                transcriptionService: FakeTranscriptionService()
            )
            throw CheckFailure("Windows dictation runtime should be unsupported off Windows")
        } catch WindowsDictationRuntimeError.unsupported {
        }
    }

    private static func checkWindowsClipboardPayloadIsCFUnicodeText() throws {
        let data = WindowsClipboardPayload.cfUnicodeTextData(for: "roma proof")

        try require(data.count == 22, "CF_UNICODETEXT should include UTF-16LE bytes plus null terminator")
        try require(try readUInt16LittleEndian(data, offset: 0) == 0x0072, "payload should start with r")
        try require(try readUInt16LittleEndian(data, offset: 2) == 0x006F, "payload should encode o")
        try require(try readUInt16LittleEndian(data, offset: data.count - 2) == 0, "payload should be null terminated")
        let decodedCodeUnits = try decodeUTF16LittleEndian(data)
        try require(
            Array(decodedCodeUnits.dropLast()) == Array("roma proof".utf16),
            "payload should round-trip the original UTF-16 code units"
        )
        try require(
            WindowsClipboardPayload.text(fromCFUnicodeTextData: data) == "roma proof",
            "CF_UNICODETEXT payload should decode for clipboard restore"
        )

        let emojiText = "roma \u{1F399}"
        try require(
            WindowsClipboardPayload.text(fromCFUnicodeTextData: WindowsClipboardPayload.cfUnicodeTextData(for: emojiText)) == emojiText,
            "CF_UNICODETEXT decoding should preserve surrogate pairs"
        )
        try require(
            WindowsClipboardPayload.text(fromCFUnicodeTextData: Data([0x72])) == nil,
            "CF_UNICODETEXT decoding should reject unaligned data"
        )
    }

    private static func checkWindowsDPAPISecretStoreContract() throws {
        try require(
            try WindowsDPAPISecretStore.fileName(forKey: "groqAPIKey") == "67726f714150494b6579.dpapi",
            "secret file names should be deterministic UTF-8 hex"
        )
        do {
            _ = try WindowsDPAPISecretStore.fileName(forKey: "   ")
            throw CheckFailure("empty secret keys should be rejected")
        } catch WindowsDPAPISecretError.invalidKey {
        }

        let plaintext = Data("roma just talk proof secret".utf8)
        if WindowsDPAPIProtectedData.isRuntimeAvailable {
            let protected = try WindowsDPAPIProtectedData.protect(plaintext)
            try require(!protected.isEmpty, "DPAPI protected data should not be empty")
            try require(protected != plaintext, "DPAPI protected data should not equal plaintext")
            try require(try WindowsDPAPIProtectedData.unprotect(protected) == plaintext, "DPAPI data should round-trip")

            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("roma-secret-check-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let store = WindowsDPAPISecretStore(directoryURL: directoryURL)
            try store.save("roma secret", forKey: "proof")
            try require(try store.get("proof") == "roma secret", "DPAPI store should retrieve saved secrets")
            try store.delete("proof")
            try require(try store.get("proof") == nil, "DPAPI store delete should remove secrets")
        } else {
            do {
                _ = try WindowsDPAPIProtectedData.protect(plaintext)
                throw CheckFailure("DPAPI protect should be unsupported off Windows")
            } catch WindowsDPAPISecretError.unsupported {
            }
        }
    }

    private static func checkWindowsPermissionSurface() throws {
        let surface = WindowsPermissionSurface.minimumMVP

        try require(
            surface.minimumPermissions == ["microphone", "hotkey", "clipboard"],
            "Windows MVP permission surface should stay minimal"
        )
        try require(
            surface.osPermissionGrants == ["microphone"],
            "Windows MVP should only require a microphone OS grant"
        )
        try require(
            surface.nativeCapabilities.contains("RegisterHotKey"),
            "Windows permission doctor should separate RegisterHotKey from OS grants"
        )
        try require(
            surface.nativeCapabilities.contains("SendInput"),
            "Windows permission doctor should separate paste injection from OS grants"
        )
        try require(
            surface.microphoneSettingsPath.contains("Microphone"),
            "Windows permission surface should point users to microphone settings"
        )
        try require(
            surface.requiresDesktopAppMicrophoneAccess,
            "Windows microphone proof should require desktop app microphone access"
        )
        try require(!surface.hotKeyPermissionPrompt, "RegisterHotKey should not be documented as a prompt flow")
        try require(!surface.pastePermissionPrompt, "SendInput paste should not be documented as a prompt flow")
        try require(surface.pasteIntegrityLimit == "equal_or_lower", "paste integrity limit should be explicit")
        try require(!surface.adminRequired, "Windows MVP should not require admin")
        try require(
            surface.startupMechanism == "user_startup_folder_shortcut",
            "Windows startup should stay a no-admin per-user shortcut"
        )
        try require(!surface.startupPermissionPrompt, "Startup folder shortcut should not be documented as a prompt flow")
        try require(!surface.screenCaptureRequired, "Windows MVP should not require screen capture")
    }

    private static func checkTranscriptionRequestMetadata() throws {
        let model = TranscriptionModelDescriptor(
            name: "ggml-base.en",
            displayName: "Whisper Base English",
            provider: .whisper,
            supportedLanguages: ["en": "English"]
        )
        let request = TranscriptionRequest(
            audioURL: URL(fileURLWithPath: "/tmp/proof.wav"),
            model: model,
            language: "en",
            prompt: "short dictation",
            customVocabulary: ["roma"]
        )

        try require(request.model.provider == .whisper, "request should carry provider")
        try require(request.language == "en", "request should carry language")
        try require(request.customVocabulary == ["roma"], "request should carry vocabulary")
    }

    private static func checkDictationPipelineTranscribesAndInserts() async throws {
        let recorder = FakeRecorder()
        let inserter = FakeTextInsertion()
        let transcriber = FakeTranscriptionService(expectedFileName: "pipeline-proof.wav")
        let pipeline = DictationPipeline(
            recorder: recorder,
            transcriptionService: transcriber,
            textInsertion: inserter
        )
        let model = TranscriptionModelDescriptor(
            name: "cloud-proof",
            displayName: "Cloud Proof",
            provider: .custom
        )
        let request = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/pipeline-proof.wav"),
            model: model,
            language: "en",
            prompt: "roma",
            shouldInsertTranscription: true
        )

        try await recorder.startPreRollBuffering()
        let result = try await pipeline.runRecordingWindow(request) {}

        try require(result.session.status == .completed, "pipeline session should complete")
        try require(result.session.recordedAudio.fileURL.path == "/tmp/pipeline-proof.wav", "pipeline should record to requested output")
        try require(result.session.rawText == "roma just talk proof", "pipeline should store raw transcript")
        try require(result.session.insertedText == "roma just talk proof", "pipeline should store inserted transcript")
        try require(result.transcription.text == "roma just talk proof", "pipeline should return transcription result")
        try require(result.processedText == "roma just talk proof", "pipeline should return processed transcript")
        try require(await inserter.pastedText == "roma just talk proof", "pipeline should paste through injected text insertion")
        try require(recorder.stopCaptureCallCount == 1, "pipeline should stop capture after success")

        let cleanupRecorder = FakeRecorder()
        let cleanupInserter = FakeTextInsertion()
        let cleanupPipeline = DictationPipeline(
            recorder: cleanupRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "cleanup-proof.wav",
                text: "hmm... Model."
            ),
            textInsertion: cleanupInserter
        )
        let cleanupRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/cleanup-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                removesFillerWords: true,
                wordReplacements: [
                    RomaWordReplacementRule(originalText: "model", replacementText: "roma")
                ],
                insertionContext: TextInsertionContext(precedingText: "Use")
            )
        )

        try await cleanupRecorder.startPreRollBuffering()
        let cleanupResult = try await cleanupPipeline.runRecordingWindow(cleanupRequest) {}

        try require(cleanupResult.session.rawText == "hmm... Model.", "pipeline should preserve raw STT text")
        try require(cleanupResult.processedText == " roma", "pipeline should clean, replace, and space inserted text")
        try require(cleanupResult.session.insertedText == " roma", "pipeline session should store processed inserted text")
        try require(await cleanupInserter.pastedText == " roma", "pipeline should paste processed text")

        let midSentenceRecorder = FakeRecorder()
        let midSentenceInserter = FakeTextInsertion()
        let midSentencePipeline = DictationPipeline(
            recorder: midSentenceRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "mid-sentence-proof.wav",
                text: "Model."
            ),
            textInsertion: midSentenceInserter
        )
        let midSentenceRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/mid-sentence-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await midSentenceRecorder.startPreRollBuffering()
        let midSentenceResult = try await midSentencePipeline.runRecordingWindow(midSentenceRequest) {}

        try require(
            midSentenceResult.processedText == " model",
            "pipeline should lowercase and remove trailing punctuation for mid-sentence fragments"
        )
        try require(
            midSentenceResult.session.insertedText == " model",
            "pipeline session should store mid-sentence polished inserted text"
        )
        try require(
            await midSentenceInserter.pastedText == " model",
            "pipeline should paste mid-sentence polished text"
        )

        let bracketedFragmentRecorder = FakeRecorder()
        let bracketedFragmentInserter = FakeTextInsertion()
        let bracketedFragmentPipeline = DictationPipeline(
            recorder: bracketedFragmentRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "bracketed-fragment-proof.wav",
                text: "[Model.]"
            ),
            textInsertion: bracketedFragmentInserter
        )
        let bracketedFragmentRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/bracketed-fragment-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await bracketedFragmentRecorder.startPreRollBuffering()
        let bracketedFragmentResult = try await bracketedFragmentPipeline.runRecordingWindow(
            bracketedFragmentRequest
        ) {}

        try require(
            bracketedFragmentResult.session.rawText == "[Model.]",
            "pipeline should preserve raw bracketed STT artifact text"
        )
        try require(
            bracketedFragmentResult.processedText == " model",
            "pipeline should unwrap bracketed STT artifacts during mid-sentence polish"
        )
        try require(
            bracketedFragmentResult.session.insertedText == " model",
            "pipeline session should store bracketed artifact polish"
        )
        try require(
            await bracketedFragmentInserter.pastedText == " model",
            "pipeline should paste bracketed artifact polish"
        )

        let bracketedAbbreviationRecorder = FakeRecorder()
        let bracketedAbbreviationInserter = FakeTextInsertion()
        let bracketedAbbreviationPipeline = DictationPipeline(
            recorder: bracketedAbbreviationRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "bracketed-abbreviation-proof.wav",
                text: "[U.S.]"
            ),
            textInsertion: bracketedAbbreviationInserter
        )
        let bracketedAbbreviationRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/bracketed-abbreviation-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await bracketedAbbreviationRecorder.startPreRollBuffering()
        let bracketedAbbreviationResult = try await bracketedAbbreviationPipeline.runRecordingWindow(
            bracketedAbbreviationRequest
        ) {}

        try require(
            bracketedAbbreviationResult.processedText == " U.S.",
            "pipeline should preserve abbreviation periods in bracketed mid-sentence fragments"
        )
        try require(
            await bracketedAbbreviationInserter.pastedText == " U.S.",
            "pipeline should paste abbreviation periods in bracketed mid-sentence fragments"
        )

        let bracketedMixedAbbreviationRecorder = FakeRecorder()
        let bracketedMixedAbbreviationInserter = FakeTextInsertion()
        let bracketedMixedAbbreviationPipeline = DictationPipeline(
            recorder: bracketedMixedAbbreviationRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "bracketed-mixed-abbreviation-proof.wav",
                text: "[Ph.D.]"
            ),
            textInsertion: bracketedMixedAbbreviationInserter
        )
        let bracketedMixedAbbreviationRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/bracketed-mixed-abbreviation-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await bracketedMixedAbbreviationRecorder.startPreRollBuffering()
        let bracketedMixedAbbreviationResult = try await bracketedMixedAbbreviationPipeline.runRecordingWindow(
            bracketedMixedAbbreviationRequest
        ) {}

        try require(
            bracketedMixedAbbreviationResult.processedText == " Ph.D.",
            "pipeline should preserve mixed abbreviation periods in bracketed mid-sentence fragments"
        )
        try require(
            await bracketedMixedAbbreviationInserter.pastedText == " Ph.D.",
            "pipeline should paste mixed abbreviation periods in bracketed mid-sentence fragments"
        )

        let initialNameRecorder = FakeRecorder()
        let initialNameInserter = FakeTextInsertion()
        let initialNamePipeline = DictationPipeline(
            recorder: initialNameRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "initial-name-proof.wav",
                text: "J.R.R. Tolkien."
            ),
            textInsertion: initialNameInserter
        )
        let initialNameRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/initial-name-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "I met")
            )
        )

        try await initialNameRecorder.startPreRollBuffering()
        let initialNameResult = try await initialNamePipeline.runRecordingWindow(initialNameRequest) {}

        try require(
            initialNameResult.processedText == " J.R.R. Tolkien",
            "pipeline should strip noisy trailing periods after internal initial abbreviations"
        )
        try require(
            await initialNameInserter.pastedText == " J.R.R. Tolkien",
            "pipeline should paste internal initial abbreviations without noisy trailing periods"
        )

        let quotedFragmentRecorder = FakeRecorder()
        let quotedFragmentInserter = FakeTextInsertion()
        let quotedFragmentPipeline = DictationPipeline(
            recorder: quotedFragmentRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "quoted-fragment-proof.wav",
                text: "\"Model!\"."
            ),
            textInsertion: quotedFragmentInserter
        )
        let quotedFragmentRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/quoted-fragment-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await quotedFragmentRecorder.startPreRollBuffering()
        let quotedFragmentResult = try await quotedFragmentPipeline.runRecordingWindow(
            quotedFragmentRequest
        ) {}

        try require(
            quotedFragmentResult.processedText == " \"model\"",
            "pipeline should clean quoted noisy mid-sentence final fragments"
        )
        try require(
            await quotedFragmentInserter.pastedText == " \"model\"",
            "pipeline should paste quoted noisy mid-sentence final fragments"
        )

        let smartQuotedFragmentRecorder = FakeRecorder()
        let smartQuotedFragmentInserter = FakeTextInsertion()
        let smartQuotedFragmentPipeline = DictationPipeline(
            recorder: smartQuotedFragmentRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "smart-quoted-fragment-proof.wav",
                text: "“Model.”."
            ),
            textInsertion: smartQuotedFragmentInserter
        )
        let smartQuotedFragmentRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/smart-quoted-fragment-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "...so this")
            )
        )

        try await smartQuotedFragmentRecorder.startPreRollBuffering()
        let smartQuotedFragmentResult = try await smartQuotedFragmentPipeline.runRecordingWindow(
            smartQuotedFragmentRequest
        ) {}

        try require(
            smartQuotedFragmentResult.processedText == " “model”",
            "pipeline should clean smart-quoted noisy mid-sentence final fragments"
        )
        try require(
            await smartQuotedFragmentInserter.pastedText == " “model”",
            "pipeline should paste smart-quoted noisy mid-sentence final fragments"
        )

        let properNameReplacementRecorder = FakeRecorder()
        let properNameReplacementInserter = FakeTextInsertion()
        let properNameReplacementPipeline = DictationPipeline(
            recorder: properNameReplacementRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "proper-name-replacement-proof.wav",
                text: "felix."
            ),
            textInsertion: properNameReplacementInserter
        )
        let properNameReplacementRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/proper-name-replacement-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                wordReplacements: [
                    RomaWordReplacementRule(originalText: "felix", replacementText: "Felix")
                ],
                insertionContext: TextInsertionContext(precedingText: "I met")
            )
        )

        try await properNameReplacementRecorder.startPreRollBuffering()
        let properNameReplacementResult = try await properNameReplacementPipeline.runRecordingWindow(
            properNameReplacementRequest
        ) {}

        try require(
            properNameReplacementResult.processedText == " Felix",
            "pipeline should preserve proper-name replacement casing during mid-sentence polish"
        )
        try require(
            properNameReplacementResult.session.insertedText == " Felix",
            "pipeline session should store proper-name replacement casing"
        )
        try require(
            await properNameReplacementInserter.pastedText == " Felix",
            "pipeline should paste proper-name replacement casing"
        )

        let selectedReplacementRecorder = FakeRecorder()
        let selectedReplacementInserter = FakeTextInsertion()
        let selectedReplacementPipeline = DictationPipeline(
            recorder: selectedReplacementRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "selected-replacement-proof.wav",
                text: "Model."
            ),
            textInsertion: selectedReplacementInserter
        )
        let selectedReplacementRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/selected-replacement-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                insertionContext: TextInsertionContext(precedingText: "Use ", selectedText: "old")
            )
        )

        try await selectedReplacementRecorder.startPreRollBuffering()
        let selectedReplacementResult = try await selectedReplacementPipeline.runRecordingWindow(
            selectedReplacementRequest
        ) {}

        try require(
            selectedReplacementResult.processedText == "model",
            "pipeline should polish selected replacements without adding a leading space"
        )
        try require(
            selectedReplacementResult.session.insertedText == "model",
            "pipeline session should store selected replacement text without leading space"
        )
        try require(
            await selectedReplacementInserter.pastedText == "model",
            "pipeline should paste selected replacement text without leading space"
        )

        let fillerOnlyRecorder = FakeRecorder()
        let fillerOnlyInserter = FakeTextInsertion()
        let fillerOnlyPipeline = DictationPipeline(
            recorder: fillerOnlyRecorder,
            transcriptionService: FakeTranscriptionService(
                expectedFileName: "filler-only-proof.wav",
                text: "hmm.... eh..."
            ),
            textInsertion: fillerOnlyInserter
        )
        let fillerOnlyRequest = DictationPipelineRequest(
            outputURL: URL(fileURLWithPath: "/tmp/filler-only-proof.wav"),
            model: model,
            shouldInsertTranscription: true,
            textProcessing: DictationTextProcessingConfiguration(
                removesFillerWords: true,
                insertionContext: TextInsertionContext(precedingText: "Use ", selectedText: "old")
            )
        )

        try await fillerOnlyRecorder.startPreRollBuffering()
        let fillerOnlyResult = try await fillerOnlyPipeline.runRecordingWindow(fillerOnlyRequest) {}

        try require(fillerOnlyResult.processedText.isEmpty, "pipeline should clean filler-only speech to empty text")
        try require(fillerOnlyResult.session.insertedText == nil, "pipeline should not store empty inserted text")
        try require(await fillerOnlyInserter.pastedText == nil, "pipeline should not paste empty cleaned text")

        let missingInserterPipeline = DictationPipeline(
            recorder: FakeRecorder(),
            transcriptionService: transcriber
        )
        do {
            _ = try await missingInserterPipeline.runRecordingWindow(request) {}
            throw CheckFailure("pipeline should reject insertion without text insertion adapter")
        } catch DictationPipelineError.missingTextInsertion {
        }
    }

    private static func checkFakeAdaptersSatisfyCorePorts() async throws {
        let recorder = FakeRecorder()
        let inserter = FakeTextInsertion()
        let transcriber = FakeTranscriptionService()

        try await recorder.startPreRollBuffering()
        try await recorder.startRecording(toOutputFile: URL(fileURLWithPath: "/tmp/proof.wav"))
        let recordedAudio = try await recorder.finishRecording()

        let model = TranscriptionModelDescriptor(
            name: "cloud-proof",
            displayName: "Cloud Proof",
            provider: .custom
        )
        let result = try await transcriber.transcribe(
            TranscriptionRequest(audioURL: recordedAudio.fileURL, model: model)
        )
        try await inserter.pasteAtCursor(result.text)

        try require(recordedAudio.includedPreRollSeconds == 3, "recorded audio should report pre-roll")
        try require(result.text == "roma just talk proof", "transcription should return proof text")
        let pastedText = await inserter.pastedText
        try require(pastedText == "roma just talk proof", "text insertion should receive proof text")
    }

    private static func checkSourcesDoNotImportApplePlatformFrameworks() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot.appendingPathComponent("Sources/RomaCore")
        let bannedImports = [
            "AppKit",
            "ApplicationServices",
            "AudioToolbox",
            "AVFoundation",
            "Carbon",
            "Charts",
            "Cocoa",
            "CoreAudio",
            "CoreGraphics",
            "CoreML",
            "FluidAudio",
            "IOKit",
            "LaunchAtLogin",
            "MediaRemoteAdapter",
            "NaturalLanguage",
            "PermissionFlow",
            "ScreenCaptureKit",
            "Security",
            "SelectedTextKit",
            "Sparkle",
            "Speech",
            "SwiftData",
            "SwiftUI",
            "UniformTypeIdentifiers",
            "Vision",
            "whisper"
        ]

        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            throw CheckFailure("could not enumerate \(sourcesRoot.path)")
        }

        let swiftFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }

        try require(!swiftFiles.isEmpty, "RomaCore should contain Swift sources")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for bannedImport in bannedImports {
                try require(
                    !source.contains("import \(bannedImport)"),
                    "\(file.path) imports \(bannedImport), which blocks Windows portability"
                )
            }
        }
    }

    private static func checkWindowsProofScriptContracts() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryRoot = packageRoot.deletingLastPathComponent()
        let scriptsRoot = packageRoot.appendingPathComponent("Scripts")
        let packageScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("package-windows-agent.ps1"),
            encoding: .utf8
        )
        let installScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("install-windows-agent.ps1"),
            encoding: .utf8
        )
        let smokeScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("smoke-windows-agent.ps1"),
            encoding: .utf8
        )
        let runScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("run-windows-agent.ps1"),
            encoding: .utf8
        )
        let windowsProofScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("windows-proof.ps1"),
            encoding: .utf8
        )
        let foregroundSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/CWindowsSupport/roma_windows_foreground.c"),
            encoding: .utf8
        )
        let pasteProofSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/RomaCore/Windows/WindowsPasteProof.swift"),
            encoding: .utf8
        )
        let keyboardHookSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/RomaCore/Windows/WindowsLowLevelKeyboardHookProof.swift"
            ),
            encoding: .utf8
        )
        let windowsDictationRuntimeSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/RomaCore/Windows/WindowsDictationRuntime.swift"
            ),
            encoding: .utf8
        )
        let proveScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("prove-windows-agent-artifact.ps1"),
            encoding: .utf8
        )
        let checkReportScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("check-windows-proof-report.ps1"),
            encoding: .utf8
        )
        let checkSetScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("check-windows-proof-set.ps1"),
            encoding: .utf8
        )
        let laptopProofScript = try String(
            contentsOf: scriptsRoot.appendingPathComponent("run-windows-laptop-proof.ps1"),
            encoding: .utf8
        )
        let windowsAgentSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/RomaWindowsAgent/main.swift"),
            encoding: .utf8
        )
        let proofAgentSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/RomaProofAgent/main.swift"),
            encoding: .utf8
        )
        let workflowScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/romacore.yml"),
            encoding: .utf8
        )

        try require(
            packageScript.contains(#""source_commit=$($gitMetadata.Commit)""#),
            "Windows package manifest should record the source git commit"
        )
        try require(
            packageScript.contains(#""source_dirty=$($gitMetadata.Dirty)""#),
            "Windows package manifest should record whether source was dirty"
        )
        try require(
            packageScript.contains("package-windows-agent.ps1 must run on Windows"),
            "Windows package script should reject non-Windows hosts"
        )
        try require(
            !packageScript.contains("$nonWindowsPreferred"),
            "Windows package script should not package non-Windows executables as .exe files"
        )
        guard let gitMetadataRange = packageScript.range(
            of: "$gitMetadata = Get-GitMetadata -RepositoryRoot $packageRoot"
        ),
              let outputDirCreationRange = packageScript.range(
                of: "New-Item -ItemType Directory -Force -Path $OutputDir"
              ) else {
            throw CheckFailure("Windows package script should record source provenance before output setup")
        }
        try require(
            gitMetadataRange.lowerBound < outputDirCreationRange.lowerBound,
            "Windows package script should record source provenance before creating proof artifacts"
        )
        try require(
            checkReportScript.contains("function Assert-ManifestSourceProof"),
            "Windows proof checker should validate manifest source provenance"
        )
        try require(
            checkReportScript.contains("source_repository to identify the packaged source repository"),
            "Windows proof checker should reject placeholder source repositories"
        )
        try require(
            checkReportScript.contains("source_commit to be a 40-character git SHA"),
            "Windows proof checker should reject missing or malformed source commits"
        )
        try require(
            proofAgentSource.contains(#"print("native_windows_adapters=true")"#),
            "Windows proof agent should print native adapter runtime availability on Windows"
        )
        try require(
            proofAgentSource.contains(#"case "windows-hotkey-availability-proof":"#) &&
                proofAgentSource.contains(#"print("hotkey_registration_available=true")"#),
            "Windows proof agent should expose a noninteractive RegisterHotKey availability proof"
        )
        try require(
            windowsDictationRuntimeSource.contains("let pipeline = DictationPipeline(") &&
                windowsDictationRuntimeSource.contains("WindowsClipboardTextInsertion("),
            "Windows dictation runtime should compose the shared DictationPipeline with the Windows paste adapter"
        )
        try require(
            proofAgentSource.contains(#"print("windows_dictation_runtime_uses_pipeline_source=true")"#),
            "Windows proof agent should expose that Windows runtime uses the shared DictationPipeline"
        )
        let doctorDefaultOutputLines = [
            #"print("default_record_seconds=\(RomaWindowsAgentConfiguration.defaultRecordSeconds)")"#,
            #"print("default_hold_timeout_seconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds)")"#,
            #"print("default_hold_timeout_milliseconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds)")"#,
            #"print("default_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds)")"#,
            #"print("maximum_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds)")"#
        ]
        for outputLine in doctorDefaultOutputLines {
            try require(
                windowsAgentSource.contains(outputLine),
                "Windows agent doctor should expose shared default line \(outputLine)"
            )
            try require(
                proofAgentSource.contains(outputLine),
                "Windows proof agent doctor should expose shared default line \(outputLine)"
            )
        }
        try require(
            proofAgentSource.contains(#"print("default_timeout_seconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutSeconds)")"#) &&
                proofAgentSource.contains(#"print("default_timeout_milliseconds=\(RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds)")"#),
            "Windows keyboard hook doctor should expose shared hold timeout defaults"
        )
        let pipelineSourceAssertions = [
            ("windows-proof.ps1", windowsProofScript),
            ("package-windows-agent.ps1", packageScript),
            ("prove-windows-agent-artifact.ps1", proveScript)
        ]
        for (scriptName, scriptSource) in pipelineSourceAssertions {
            try require(
                scriptSource.contains(#"-Expected "windows_dictation_runtime_uses_pipeline_source=true""#),
                "\(scriptName) should assert that the Windows runtime uses the shared DictationPipeline"
            )
        }
        let hotKeyAvailabilityProofAssertions = [
            ("windows-proof.ps1", windowsProofScript, "windows-hotkey-availability-proof", "hotkey_registration_available=true"),
            ("prove-windows-agent-artifact.ps1", proveScript, "windows-hotkey-availability-proof", "hotkey_registration_available=true"),
            ("check-windows-proof-report.ps1", checkReportScript, "register_hotkey_available", #"Assert-Boolean -Object $Proof -Name "register_hotkey_available" -Expected $true"#)
        ]
        for (scriptName, scriptSource, commandMarker, proofMarker) in hotKeyAvailabilityProofAssertions {
            try require(
                scriptSource.contains(commandMarker) &&
                    scriptSource.contains(proofMarker),
                "\(scriptName) should assert default RegisterHotKey availability"
            )
        }
        try require(
            proveScript.contains(
                #"windows_dictation_runtime_uses_pipeline_source = $Output.Contains("windows_dictation_runtime_uses_pipeline_source=true")"#
            ),
            "Windows artifact proof reports should record that the Windows runtime uses the shared DictationPipeline"
        )
        try require(
            checkReportScript.contains(
                #"Assert-Boolean -Object $Proof -Name "windows_dictation_runtime_uses_pipeline_source" -Expected $true"#
            ),
            "Windows proof checker should require that the Windows runtime uses the shared DictationPipeline"
        )
        try require(
            proofAgentSource.contains(
                #"print("default_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds)")"#
            ) &&
                proofAgentSource.contains(
                    #"print("maximum_clipboard_restore_delay_seconds=\(WindowsClipboardRestoreConfiguration.maximumRestoreDelaySeconds)")"#
                ),
            "Windows paste doctor should expose shared clipboard restore delay defaults"
        )
        let proofDefaultAssertions = [
            "default_record_seconds=2.0",
            "default_hold_timeout_seconds=15.0",
            "default_hold_timeout_milliseconds=15000",
            "default_clipboard_restore_delay_seconds=2.0",
            "maximum_clipboard_restore_delay_seconds=4294967.295",
            "default_timeout_seconds=15.0",
            "default_timeout_milliseconds=15000"
        ]
        for expectedLine in proofDefaultAssertions {
            try require(
                windowsProofScript.contains(#"Assert-OutputContains -Output "#) &&
                    windowsProofScript.contains(#"-Expected "\#(expectedLine)""#),
                "Windows proof script should assert doctor default output \(expectedLine)"
            )
        }
        let proofReportDefaultFields = [
            "default_record_seconds",
            "default_hold_timeout_seconds",
            "default_hold_timeout_milliseconds",
            "default_clipboard_restore_delay_seconds",
            "maximum_clipboard_restore_delay_seconds"
        ]
        for field in proofReportDefaultFields {
            try require(
                proveScript.contains(#"\#(field) = $Output.Contains("#),
                "Windows artifact proof reports should record doctor default field \(field)"
            )
            try require(
                checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "\#(field)" -Expected $true"#),
                "Windows proof report checker should require doctor default field \(field)"
            )
        }
        let artifactDefaultAssertions = [
            "default_record_seconds=2.0",
            "default_hold_timeout_seconds=15.0",
            "default_hold_timeout_milliseconds=15000",
            "default_clipboard_restore_delay_seconds=2.0",
            "maximum_clipboard_restore_delay_seconds=4294967.295",
            "default_timeout_seconds=15.0",
            "default_timeout_milliseconds=15000"
        ]
        for expectedLine in artifactDefaultAssertions {
            try require(
                proveScript.contains(#"Assert-OutputContains -Output "#) &&
                    proveScript.contains(#"-Expected "\#(expectedLine)""#),
                "Windows artifact proof script should assert doctor default output \(expectedLine)"
            )
        }
        let packageDefaultAssertions = [
            "default_record_seconds=2.0",
            "default_hold_timeout_seconds=15.0",
            "default_hold_timeout_milliseconds=15000",
            "default_clipboard_restore_delay_seconds=2.0",
            "maximum_clipboard_restore_delay_seconds=4294967.295"
        ]
        for expectedLine in packageDefaultAssertions {
            try require(
                packageScript.contains(#"Assert-OutputContains -Output $proofAgentOutputText"#) &&
                    packageScript.contains(#"-Expected "\#(expectedLine)""#),
                "Windows package script should assert packaged proof-agent default output \(expectedLine)"
            )
            try require(
                smokeScript.contains(#"Assert-OutputContains -Output $doctorOutput"#) &&
                    smokeScript.contains(#"-Expected "\#(expectedLine)""#),
                "Windows smoke script should assert packaged agent default output \(expectedLine)"
            )
            try require(
                runScript.contains("function Assert-OutputContains") &&
                    runScript.contains(#"Assert-OutputContains -Output $doctorOutput"#) &&
                    runScript.contains(#"-Expected "\#(expectedLine)""#),
                "Windows run script should assert installed launcher default output \(expectedLine)"
            )
        }
        try require(
            pasteProofSource.contains(
                "restoreDelaySeconds: TimeInterval = WindowsClipboardRestoreConfiguration.defaultRestoreDelaySeconds"
            ),
            "Windows paste proof options should share the clipboard restore delay default"
        )
        try require(
            pasteProofSource.contains("WindowsClipboardRestoreConfiguration.restoreDelayMilliseconds") &&
                !pasteProofSource.contains("min(max(delaySeconds, 0)"),
            "Windows paste proof should share clipboard restore delay validation"
        )
        try require(
            keyboardHookSource.contains(
                "timeoutMilliseconds: UInt32 = RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds"
            ) &&
                !keyboardHookSource.contains("timeoutMilliseconds: UInt32 = 15_000"),
            "Windows keyboard hook proof should share the agent hold timeout default"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "native_windows_adapters" -Expected $true"#),
            "Windows proof checker should require native adapter runtime evidence from the proof agent"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "dictation_runtime" -Expected $true"#),
            "Windows proof checker should require the user-facing agent to report WindowsDictationRuntime"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "recorder_miniaudio" -Expected $true"#),
            "Windows proof checker should require the user-facing agent to report miniaudio recording"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "paste_win32_clipboard_sendinput" -Expected $true"#),
            "Windows proof checker should require the user-facing agent to report Win32 paste"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Proof -Name "secret_store_dpapi" -Expected $true"#),
            "Windows proof checker should require the user-facing agent to report DPAPI secrets"
        )
        try require(
            checkReportScript.contains(#""agent_runtime_wiring""#),
            "Windows proof profiles should print agent runtime wiring coverage"
        )
        try require(
            proveScript.contains("reported_ordered_hold_sequence"),
            "Windows artifact proof reports should record ordered hold-to-talk runtime evidence"
        )
        try require(
            proveScript.contains(#"$sampleRate = Get-OutputNumber -Content $content -Name "sample_rate""#) &&
                proveScript.contains(#"$channelCount = Get-OutputNumber -Content $content -Name "channels""#) &&
                proveScript.contains("reported_speech_pcm_contract"),
            "Windows artifact proof reports should record the dictation audio speech PCM contract"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $Runtime -Name "reported_ordered_hold_sequence" -Expected $true"#),
            "Windows proof checker should require ordered hold-to-talk runtime evidence"
        )
        try require(
            checkReportScript.contains(#"Assert-Boolean -Object $runtime -Name "reported_speech_pcm_contract" -Expected $true"#) &&
                checkReportScript.contains(#"Assert-NumberEquals -Object $runtime -Name "sample_rate" -Expected 16000"#) &&
                checkReportScript.contains(#"Assert-NumberEquals -Object $runtime -Name "channels" -Expected 1"#),
            "Windows proof checker should require the dictation audio speech PCM contract"
        )
        try require(
            foregroundSource.contains("AttachThreadInput"),
            "Windows foreground paste adapter should bridge input queues before SetForegroundWindow"
        )
        try require(
            foregroundSource.contains("SetForegroundWindow"),
            "Windows foreground paste adapter should call SetForegroundWindow"
        )
        try require(
            checkSetScript.contains("manifest.source_commit"),
            "Windows proof-set checker should compare source commits across laptop reports"
        )
        try require(
            checkSetScript.contains("proof_set_source_commit="),
            "Windows proof-set checker should print matched source commit evidence"
        )
        try require(
            checkSetScript.contains("Full laptop proof requires a clean packaged source checkout"),
            "Windows proof-set checker should reject dirty packaged source for final laptop proof"
        )
        try require(
            checkSetScript.contains("function Assert-SameArtifactSmokeProofSet") &&
                checkSetScript.contains("Artifact smoke proof requires a clean packaged source checkout") &&
                checkSetScript.contains("proof_set_artifact_smoke_package_fingerprint="),
            "Windows artifact smoke proof-set checker should tie doctor and install reports to one package"
        )
        try require(
            laptopProofScript.contains("ProofSessionId"),
            "Windows laptop proof runner should stamp every report with one proof session id"
        )
        try require(
            laptopProofScript.contains("startup-shortcuts"),
            "Windows laptop proof runner should use proof-owned startup shortcut directories"
        )
        try require(
            laptopProofScript.contains("cloudStartupShortcutDir") &&
                laptopProofScript.contains("localStartupShortcutDir"),
            "Windows laptop proof runner should keep cloud and local startup shortcut proofs separate"
        )
        try require(
            laptopProofScript.contains(#"$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")"#),
            "Windows laptop proof runner should distinguish explicit clipboard restore delay from the default"
        )
        try require(
            laptopProofScript.contains(#"if ($NoRestoreClipboard -and $hasExplicitClipboardRestoreDelay)"#),
            "Windows laptop proof runner should reject no-restore plus explicit restore delay before invoking nested scripts"
        )
        let clipboardRestoreDelayConflictScripts = [
            ("windows-proof.ps1", windowsProofScript),
            ("run-windows-agent.ps1", runScript),
            ("smoke-windows-agent.ps1", smokeScript),
            ("install-windows-agent.ps1", installScript),
            ("prove-windows-agent-artifact.ps1", proveScript)
        ]
        for (scriptName, scriptSource) in clipboardRestoreDelayConflictScripts {
            try require(
                scriptSource.contains(#"$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")"#) &&
                    scriptSource.contains(#"if ($NoRestoreClipboard -and $hasExplicitClipboardRestoreDelay)"#),
                "\(scriptName) should reject no-restore plus explicit restore delay before forwarding options"
            )
        }
        try require(
            installScript.contains("Assert-InstalledAgentNotRunning") &&
                installScript.contains("close the listener before reinstalling or upgrading"),
            "Windows installer should fail early when the installed listener is running"
        )
        try require(
            installScript.contains(#""RomaProofAgent.exe""#) &&
                installScript.contains(#""run-windows-laptop-proof.ps1""#) &&
                installScript.contains(#""check-windows-proof-set.ps1""#),
            "Windows installer should preserve the packaged proof surface"
        )
        try require(
            proveScript.contains("installed_proof_agent") &&
                proveScript.contains("installed_laptop_proof_script") &&
                proveScript.contains("installed_check_set_script"),
            "Windows artifact proof reports should record the installed proof surface"
        )
        try require(
            checkReportScript.contains("installed_proof_agent_matches_package") &&
                checkReportScript.contains("installed_laptop_proof_script_matches_package") &&
                checkReportScript.contains("installed_check_set_script_matches_package"),
            "Windows proof checker should verify installed proof surface hashes"
        )
        try require(
            checkSetScript.contains("proof_session_id"),
            "Windows proof-set checker should compare proof session ids across laptop reports"
        )
        try require(
            checkSetScript.contains("proof_set_session_id="),
            "Windows proof-set checker should print matched proof session evidence"
        )
        try require(
            workflowScript.contains("Verify clean Windows package provenance"),
            "Windows CI should explicitly verify clean package provenance"
        )
        try require(
            workflowScript.contains(#"source_dirty=false"#),
            "Windows CI should fail artifacts packaged from dirty source"
        )
    }

    private static func asciiString(_ data: Data, offset: Int, count: Int) throws -> String {
        try require(offset >= 0, "offset should be nonnegative")
        try require(count >= 0, "count should be nonnegative")
        try require(offset + count <= data.count, "ASCII read should stay inside data")

        return String(decoding: data[offset..<(offset + count)], as: UTF8.self)
    }

    private static func readUInt16LittleEndian(_ data: Data, offset: Int) throws -> UInt16 {
        try require(offset >= 0, "offset should be nonnegative")
        try require(offset + 2 <= data.count, "UInt16 read should stay inside data")

        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func decodeUTF16LittleEndian(_ data: Data) throws -> [UInt16] {
        try require(data.count.isMultiple(of: MemoryLayout<UInt16>.size), "UTF-16 data should be UInt16-aligned")

        return try stride(from: 0, to: data.count, by: MemoryLayout<UInt16>.size).map { offset in
            try readUInt16LittleEndian(data, offset: offset)
        }
    }

    private static func readUInt32LittleEndian(_ data: Data, offset: Int) throws -> UInt32 {
        try require(offset >= 0, "offset should be nonnegative")
        try require(offset + 4 <= data.count, "UInt32 read should stay inside data")

        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func decodeInt16LittleEndian(_ data: Data) throws -> [Int16] {
        try require(data.count.isMultiple(of: MemoryLayout<Int16>.size), "PCM data should be Int16-aligned")

        return stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size).map { offset in
            let low = UInt16(data[offset])
            let high = UInt16(data[offset + 1]) << 8
            return Int16(bitPattern: low | high)
        }
    }

    fileprivate static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private enum FakeRecorderError: Error {
    case missingOutputFile
}

private final class FakeRecorder: RollingRecorder, @unchecked Sendable {
    var onAudioChunk: (@Sendable (Data) -> Void)?
    let preRollConfiguration = PreRollConfiguration()
    private(set) var stopCaptureCallCount = 0
    private var outputFile: URL?

    func startPreRollBuffering() async throws {}

    func startRecording(toOutputFile url: URL) async throws {
        outputFile = url
    }

    func finishRecording() async throws -> RecordedAudio {
        guard let outputFile else { throw FakeRecorderError.missingOutputFile }
        return RecordedAudio(
            fileURL: outputFile,
            durationSeconds: 5,
            includedPreRollSeconds: preRollConfiguration.durationSeconds
        )
    }

    func stopCapture() async {
        stopCaptureCallCount += 1
    }
}

private actor FakeTextInsertion: TextInsertion {
    private(set) var pastedText: String?

    func pasteAtCursor(_ text: String) async throws {
        pastedText = text
    }
}

private struct FakeTranscriptionService: TranscriptionService {
    var expectedFileName = "proof.wav"
    var text = "roma just talk proof"

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try RomaCoreChecks.require(
            request.audioURL.lastPathComponent == expectedFileName,
            "request should carry \(expectedFileName)"
        )
        return TranscriptionResult(text: text)
    }
}
