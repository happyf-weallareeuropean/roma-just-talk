// swift-tools-version: 6.2
import PackageDescription

// Stage complete VoiceInkQwen, VoiceInkCore and VoiceInkNVIDIA packages as siblings in this directory.
let package = Package(
    name: "QwenRuntimeProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "VoiceInkQwen"), .package(path: "VoiceInkCore")],
    targets: [
        .executableTarget(name: "QwenRuntimeProbe", dependencies: [
            .product(name: "VoiceInkQwen", package: "voiceinkqwen"),
            .product(name: "VoiceInkCore", package: "voiceinkcore")
        ], path: "Sources")
    ]
)
