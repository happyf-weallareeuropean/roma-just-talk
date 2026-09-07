import Testing
@testable import VoiceInkQwen

@Test func traditionalPresentationPreservesMixedLanguageAndRepetition() throws {
    #expect(try QwenTextPresentation.traditional("我们用 SwiftUI 和 café 测试，版本 v1.95.1。")
        == "我們用 SwiftUI 和 café 測試，版本 v1.95.1。")
    #expect(try QwenTextPresentation.traditional("Run swift test --filter Qwen; naïve façade — 1.95.1")
        == "Run swift test --filter Qwen; naïve façade — 1.95.1")
    #expect(try QwenTextPresentation.traditional("对对对，no no no！") == "對對對，no no no！")
    #expect(try QwenTextPresentation.traditional("我們用 SwiftUI。") == "我們用 SwiftUI。")
}
