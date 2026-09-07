// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceInkNVIDIA",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "VoiceInkNVIDIA", targets: ["VoiceInkNVIDIA"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.3"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.28.0"),
        .package(url: "https://github.com/negentropi/grpc-swift-nio-transport.git", revision: "65adb0bc4721a6c4695e1956af9552970c06a59f"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.4.1")
    ],
    targets: [
        .target(name: "VoiceInkNVIDIA", dependencies: [
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            .product(name: "GRPCCore", package: "grpc-swift-2"),
            // gRPC's default eventLoopGroup argument emits NIOTS references in this target.
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            .product(name: "GRPCNIOTransportHTTP2TransportServices", package: "grpc-swift-nio-transport"),
            .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf")
        ], resources: [.copy("Resources/ThirdPartyNotices")]),
        .testTarget(name: "VoiceInkNVIDIATests", dependencies: ["VoiceInkNVIDIA"])
    ]
)
