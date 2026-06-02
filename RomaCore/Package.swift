// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RomaCore",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "RomaCore",
            targets: ["RomaCore"]
        ),
        .executable(
            name: "RomaCoreChecks",
            targets: ["RomaCoreChecks"]
        ),
        .executable(
            name: "RomaProofAgent",
            targets: ["RomaProofAgent"]
        )
    ],
    targets: [
        .target(
            name: "CMiniaudio",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CWindowsSupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RomaCore",
            dependencies: ["CMiniaudio", "CWindowsSupport"]
        ),
        .executableTarget(
            name: "RomaCoreChecks",
            dependencies: ["RomaCore"]
        ),
        .executableTarget(
            name: "RomaProofAgent",
            dependencies: ["RomaCore"]
        )
    ]
)
