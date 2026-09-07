import Foundation

/// Compiles with the actual Foundation policy, without MLX or test-framework stubs.
@main
struct QwenOfficialStreamingPolicyProof {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
    static func encode(_ text: String) -> [Int] { text.unicodeScalars.map { Int($0.value) } }
    static func decode(_ ids: [Int]) -> String {
        String(String.UnicodeScalarView(ids.compactMap { UnicodeScalar($0) }))
    }

    static func main() {
        var audio = QwenOfficialStreamingPolicy(chunkSamples: 4)
        audio.append([0, 1, 2])
        expect(audio.takeAudio() == nil, "Do not decode unavailable chunk samples")
        audio.append([3, 4, 5, 6, 7, 8])
        expect(audio.takeAudio() == [0, 1, 2, 3], "First pass starts at utterance sample zero")
        expect(audio.takeAudio() == [0, 1, 2, 3, 4, 5, 6, 7], "Second pass retains all earlier context")
        expect(audio.takeAudio() == nil, "Do not pad a partial tail")
        expect(audio.takeAudio(finalTail: true) == [0, 1, 2, 3, 4, 5, 6, 7, 8], "Tail includes every new sample and all context")
        expect(audio.takeAudio(finalTail: true) == nil, "Empty finish must not request another decode")

        var prefix = QwenOfficialStreamingPolicy()
        expect(prefix.prefix(finalTail: false, encode: encode, decode: decode).isEmpty, "First pass has no prefix")
        prefix.accept(prefix: "", generated: "OLD WRONG RESULT")
        expect(prefix.prefix(finalTail: false, encode: encode, decode: decode).isEmpty, "Second pass has no prefix")
        prefix.accept(prefix: "", generated: "ABCDEFGHIJ")
        expect(prefix.rawDecoded == "ABCDEFGHIJ", "New decode replaces old suffix instead of appending a window")
        let kept = prefix.prefix(finalTail: false, encode: encode, decode: decode)
        expect(kept == "ABCDE", "Subsequent passes roll back exactly five tokens")
        prefix.accept(prefix: kept, generated: " revised")
        expect(prefix.rawDecoded == "ABCDE revised", "Retained prefix plus fresh suffix is the entire raw state")

        var unicode = QwenOfficialStreamingPolicy()
        unicode.accept(prefix: "", generated: "first")
        unicode.accept(prefix: "", generated: "second")
        let tokens: (String) -> [Int] = { _ in Array(1...10) }
        let partialUnicode: ([Int]) -> String = { $0.count == 5 ? "ABCD\u{fffd}" : String(repeating: "A", count: $0.count) }
        expect(unicode.prefix(finalTail: false, encode: tokens, decode: partialUnicode) == "AAAA", "Regular rollback expands beyond incomplete Unicode")
        expect(unicode.prefix(finalTail: true, encode: tokens, decode: partialUnicode) == "ABCD\u{fffd}", "Control must preserve official final-tail Unicode limitation")
        expect(unicode.prefix(finalTail: false, encode: { _ in [65,66,67] }, decode: decode).isEmpty, "Regular short prefix rolls back to empty")
        expect(unicode.prefix(finalTail: true, encode: { _ in [65,66,67] }, decode: decode) == "A", "Official final-tail retains at least one token")

        let repeated = String(repeating: "very ", count: 21) + "good"
        let raw = "language English<asr_text>" + repeated
        prefix.accept(prefix: "", generated: raw)
        expect(QwenOfficialStreamingPolicy.output(raw).text == repeated, "Preserve legitimate repeated words; no global repetition cleaner")
        expect(prefix.rawDecoded == raw, "Display parsing must not alter prefix token state")
        let mixed = QwenOfficialStreamingPolicy.output("language CHINESE<asr_text>我們用 Swift build。")
        expect(mixed.language == "Chinese" && mixed.text == "我們用 Swift build。", "Parse auto-language and mixed words")
        expect(QwenOfficialStreamingPolicy.output("language None<asr_text>").text.isEmpty, "Empty-audio protocol remains empty")
        expect(QwenOfficialStreamingPolicy.output("language Chinese").text == "language Chinese", "Preserve official no-marker fallback as documented")
        print("{\"passed\":true,\"checks\":20,\"official_revision\":\"\(QwenOfficialStreamingPolicy.sourceRevision)\",\"global_repetition_filter\":false}")
    }
}
