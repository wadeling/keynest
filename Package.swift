// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeyNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KeyNest", targets: ["LLMVaultApp"])
    ],
    targets: [
        .executableTarget(
            name: "LLMVaultApp",
            path: "Sources/LLMVaultApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
