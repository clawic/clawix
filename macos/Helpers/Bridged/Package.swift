// swift-tools-version: 5.9
import PackageDescription

// `clawix-bridged` is the bridge daemon shared between Apple platforms
// (where launchd hosts it via `SMAppService.agent(plistName:)`) and
// Linux (where systemd hosts it via a user unit at
// `~/.config/systemd/user/clawix-bridge.service`). The same Swift source
// powers both targets; platform-specific symbols are guarded with
// `#if canImport(...)`.

let package = Package(
    name: "clawix-bridged",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../packages/ClawixCore"),
        .package(path: "../../../packages/ClawixEngine"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "clawix-bridged",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine"),
                .product(name: "WhisperKit", package: "WhisperKit", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/clawix-bridged",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
