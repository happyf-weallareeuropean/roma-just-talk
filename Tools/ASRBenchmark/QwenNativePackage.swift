// swift-tools-version: 6.2
import PackageDescription

// Copy to a disposable directory as Package.swift beside Sources/Probe.swift.
let package = Package(
    name: "QwenNativeProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/negentropi/mlx-audio-swift.git", revision: "aee9bd1dffcf786f544d6562d971b3e25221e261"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.4")
    ],
    targets: [
        .executableTarget(name: "QwenNativeProbe", dependencies: [
            .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLX", package: "mlx-swift")
        ], path: "Sources")
    ]
)
