// swift-tools-version: 5.9
import PackageDescription

// `clawix-menubar` is the optional menu bar surface for the standalone
// `clawix` CLI. It does NOT ship inside Clawix.app (the GUI has its
// own status item driven by SwiftUI); it is downloaded by the npm
// postinstall into ~/.clawix/bin/ alongside the daemon, and started
// on demand by `clawix up`. The menu shows daemon status, a Pairing
// QR window, and a one-click "Install Clawix.app" hop into the full
// GUI.
//
// Like the daemon, this target depends on ClawixEngine + ClawixCore
// so the QR payload, pairing token storage and bonjour name share a
// single implementation across surfaces.

let package = Package(
    name: "clawix-menubar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../packages/ClawixCore"),
        .package(path: "../../../packages/ClawixEngine")
    ],
    targets: [
        .executableTarget(
            name: "clawix-menubar",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine")
            ],
            path: "Sources/clawix-menubar"
        )
    ]
)
