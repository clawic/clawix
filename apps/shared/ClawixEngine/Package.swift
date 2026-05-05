// swift-tools-version: 5.9
import PackageDescription

// ClawixEngine is the runtime that hosts the bridge between any Clawix
// front-end (the macOS GUI today, an `clawix-bridged` LaunchAgent
// daemon tomorrow) and the Clawix backend subprocess. It owns the
// types the bridge protocol speaks in (`Chat`, `ChatMessage`, …), the
// `PairingService` token + QR generator, the WebSocket server, and
// later the `ClawixClient` subprocess wrapper.
//
// The package is platform-neutral and depends only on ClawixCore (the
// wire types) plus standard Foundation/Network/Combine, so the same
// sources can be linked into the GUI .app and a headless daemon
// without code duplication.

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
        .package(path: "../ClawixCore")
    ],
    targets: [
        .target(
            name: "ClawixEngine",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore")
            ],
            path: "Sources/ClawixEngine"
        )
    ]
)
