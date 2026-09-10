// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceInkQwen",
    platforms: [.macOS(.v14)],
    products: [.library(name: "VoiceInkQwen", targets: ["VoiceInkQwen"])],
    dependencies: [
        .package(url: "https://github.com/negentropi/mlx-audio-swift.git", revision: "b02fd514e0e859601bf0b3420087bb81c5f46b7c"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "0.10.0")
    ],
    targets: [
        .target(name: "VoiceInkQwen", dependencies: [
            .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "HuggingFace", package: "swift-huggingface")
        ], resources: [.copy("Resources")]),
        .testTarget(name: "VoiceInkQwenTests", dependencies: ["VoiceInkQwen"], resources: [.copy("Fixtures")])
    ]
)
