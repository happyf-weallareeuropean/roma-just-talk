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

    private static func checkTranscriptionOutputFilter() throws {
        let midSentenceContext = RomaTranscriptionOutputFilter.TextInsertionContext(precedingText: "...so this")
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
            RomaTranscriptionOutputFilter.applyInsertionSpacing("model", context: midSentenceContext) == " model",
            "shared insertion spacing should add a leading space after words"
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
                "mm-hmm... uh-huh, I think so.",
                "I think so.",
                "hyphenated pause sounds"
            ),
            (
                "This, um, works.",
                "This works.",
                "embedded comma pause filler"
            ),
            (
                "This; eh, works.",
                "This works.",
                "embedded semicolon pause filler"
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
                "Use [beeping] now.",
                "Use now.",
                "bracketed beeping artifact"
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
                "We should ship we should ship this.",
                "We should ship this.",
                "repeated short phrase"
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
                "Let's meet at two, no actually three.",
                "Let's meet at three.",
                "no actually correction"
            ),
            (
                "Let's meet at two, actually no, three.",
                "Let's meet at three.",
                "actually no correction"
            ),
            (
                "Use model, rather, module.",
                "Use module.",
                "bounded rather correction"
            ),
            (
                "Use model replace that with module.",
                "Use module.",
                "replace that with correction"
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
                "Use model, make that module.",
                "Use module.",
                "make that correction"
            ),
            (
                "Set color blue, sorry red.",
                "Set color red.",
                "sorry correction"
            ),
            (
                "Wrong phrase scratch that. Right phrase.",
                "Right phrase.",
                "scratch that correction"
            ),
            (
                "Wrong phrase cancel that. Right phrase.",
                "Right phrase.",
                "cancel that correction"
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
                "Wrong phrase forget that. Right phrase.",
                "Right phrase.",
                "forget that correction"
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
                "My top goals are one finish the report two send the slides.",
                "My top goals are\n1. finish the report\n2. send the slides.",
                "cardinal spoken sequence list"
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
                "The command change that to is useful.",
                "The command change that to is useful.",
                "change command prose guard"
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
                "There is no wait time.",
                "There is no wait time.",
                "no wait prose guard"
            ),
            (
                "I would rather wait.",
                "I would rather wait.",
                "rather prose guard"
            ),
            (
                "Scratch that itch.",
                "Scratch that itch.",
                "scratch command prose guard"
            ),
            (
                "Cancel that meeting.",
                "Cancel that meeting.",
                "cancel that prose guard"
            ),
            (
                "Disregard that warning.",
                "Disregard that warning.",
                "disregard that prose guard"
            ),
            (
                "Ignore that warning.",
                "Ignore that warning.",
                "ignore that prose guard"
            ),
            (
                "Forget that idea.",
                "Forget that idea.",
                "forget that prose guard"
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
                "I meant what I said.",
                "I meant what I said.",
                "i meant prose guard"
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
                "Okay, this works.",
                "Okay, this works.",
                "okay prose guard"
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
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("Model.", context: midSentenceContext) == "model",
            "insertion polish should lowercase final mid-sentence word"
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
            RomaTranscriptionOutputFilter.applyInsertionPolish("[Model!]", context: nil) == "model",
            "insertion polish should strip noisy punctuation from bracketed final fragments"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[A final word.]", context: nil) == "a final word",
            "insertion polish should strip noisy punctuation from bracketed final phrases"
        )
        try require(
            RomaTranscriptionOutputFilter.applyInsertionPolish("[A final word!]", context: nil) == "a final word",
            "insertion polish should strip noisy sentence marks from bracketed final phrases"
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
            merged.clipboardRestoreConfiguration() == WindowsClipboardRestoreConfiguration(
                restoreClipboard: true,
                restoreDelaySeconds: 0.75
            ),
            "merged config should resolve clipboard restore settings"
        )
        try require(merged.usesHoldHook == true, "CLI hold flag should enable hold mode")
        try require(merged.holdTimeoutSeconds == 22, "CLI timeout should override hold timeout")
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

        let model = TranscriptionModelDescriptor(
            name: "proof",
            displayName: "Proof",
            provider: .custom
        )
        let request = WindowsDictationRuntimeRequest(
            outputURL: URL(fileURLWithPath: "/tmp/windows-runtime-proof.wav"),
            model: model,
            trigger: .toggle(recordSeconds: 0)
        )

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
