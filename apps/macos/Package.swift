// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Clawix",
            path: "Sources/Clawix",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
