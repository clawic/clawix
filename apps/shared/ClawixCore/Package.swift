// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawixCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ClawixCore", targets: ["ClawixCore"])
    ],
    targets: [
        .target(
            name: "ClawixCore",
            path: "Sources/ClawixCore",
            exclude: ["BridgeProtocol.md"]
        ),
        .testTarget(
            name: "ClawixCoreTests",
            dependencies: ["ClawixCore"],
            path: "Tests/ClawixCoreTests"
        )
    ]
)
