// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RomaCore",
    products: [
        .library(
            name: "RomaCore",
            targets: ["RomaCore"]
        ),
        .executable(
            name: "RomaCoreChecks",
            targets: ["RomaCoreChecks"]
        )
    ],
    targets: [
        .target(name: "RomaCore"),
        .executableTarget(
            name: "RomaCoreChecks",
            dependencies: ["RomaCore"]
        )
    ]
)
