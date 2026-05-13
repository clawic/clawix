// swift-tools-version: 5.9
import PackageDescription

// ClawixEngine is the runtime that hosts the bridge between any Clawix
// front-end (the macOS GUI today, the `clawix-bridge` LaunchAgent /
// systemd user-service daemon, the iOS companion, the Linux Tauri GUI)
// and the Clawix backend subprocess. It owns the wire types
// (`Chat`, `ChatMessage`, …), the `PairingService`, the WebSocket server,
// and the `ClawixClient` subprocess wrapper.
//
// Cross-platform notes:
// - WhisperKit is Apple-only (CoreML). Gated to macOS/iOS via `.when(...)`.
// - Combine is Apple-only. On Linux we link OpenCombine, which is API
//   compatible. Source files use `#if canImport(Combine) import Combine
//   #else import OpenCombine #endif`.
// - Apple `Network` framework is Apple-only. The default WS implementation
//   uses NWListener/NWConnection on Apple platforms; on Linux a parallel
//   SwiftNIO implementation lives in BridgeServerNIO.swift / BridgeSessionNIO.swift.

let package = Package(
    name: "ClawixEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ClawixEngine", targets: ["ClawixEngine"])
    ],
    dependencies: [
        .package(path: "../ClawixCore"),
        // On-device Whisper inference. CoreML-backed, runs on the
        // Apple Neural Engine on Apple Silicon. Used by the macOS
        // GUI for the in-app dictation flow and by the Apple-side
        // daemon when an iPhone client requests a transcription.
        // Linux builds skip this and route dictation through whisper.cpp
        // spawned by the Tauri shell.
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // Combine shim for Linux. No-op on Apple (we import Combine).
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
        // SwiftNIO powers the WebSocket server on Linux where Apple's
        // Network framework is unavailable. On Apple platforms NIO is
        // still linked (for parity / shared types) but BridgeServer
        // routes through NWListener.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0")
    ],
    targets: [
        .target(
            name: "ClawixEngine",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "WhisperKit", package: "WhisperKit", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: [.linux])),
                .product(name: "NIOWebSocket", package: "swift-nio", condition: .when(platforms: [.linux])),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: [.linux])),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/ClawixEngine"
        ),
        .testTarget(
            name: "ClawixEngineTests",
            dependencies: ["ClawixEngine"],
            path: "Tests/ClawixEngineTests"
        )
    ]
)
