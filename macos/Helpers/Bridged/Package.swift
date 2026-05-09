// swift-tools-version: 5.9
import PackageDescription

// `clawix-bridged` is the LaunchAgent daemon that hosts the bridge to
// the iPhone companion (and, in Phase 3, to the macOS GUI as a
// loopback client). It is shipped inside the .app bundle at
// `Contents/Helpers/clawix-bridged` and registered with launchd via
// `SMAppService.agent(plistName:)` so it survives Cmd+Q of the GUI,
// app crashes, and logout/login.
//
// The daemon is a thin shell over `ClawixEngine`: it instantiates a
// `BridgeServer`, plugs in an `EngineHost` adapter to its in-process
// chat store, and runs the main run loop. Today the daemon ships with
// a stub `EmptyEngineHost` (no chats, no codex subprocess) so the
// build chain can be validated end-to-end while the AgentBackend
// layer is migrated piece by piece.

let package = Package(
    name: "clawix-bridged",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../packages/ClawixCore"),
        .package(path: "../../../packages/ClawixEngine"),
        // Re-pinned here even though `ClawixEngine` already pulls it in
        // transitively: `import WhisperKit` from the executable's own
        // sources requires the symbol in the package graph at this
        // level so SwiftPM exposes the public products. Used by the
        // `--download-model <variant>` maintenance flag.
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "clawix-bridged",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/clawix-bridged"
        )
    ]
)
