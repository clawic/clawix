// swift-tools-version: 5.9
import PackageDescription

// `clawix-bridge` is the bridge daemon shared between Apple platforms
// (where launchd hosts it via `SMAppService.agent(plistName:)`) and
// Linux (where systemd hosts it via a user unit at
// `~/.config/systemd/user/clawix-bridge.service`). The same Swift source
// powers both targets; platform-specific symbols are guarded with
// `#if canImport(...)`.
//
// On Apple platforms the daemon ships embedded inside `Clawix.app/Contents/Helpers/`
// and survives Cmd+Q of the GUI. On Linux it ships at `/usr/lib/clawix/clawix-bridge`
// (.deb), `~/.clawix/bin/clawix-bridge` (npm postinstall), or inside the
// AppDir of the AppImage (`AppDir/usr/lib/clawix/clawix-bridge`).
//
// The daemon is a thin shell over `ClawixEngine`: it instantiates a
// `BridgeServer` (NWListener on Apple, SwiftNIO on Linux), plugs in an
// `EngineHost` adapter to its in-process chat store, and runs the main
// run loop.
//
// The daemon also embeds the Clawix web client (the React SPA built
// from `clawix/web/`). The build pipeline (`clawix/macos/scripts/dev.sh`
// and `clawix/scripts-dev/release.sh`) runs `pnpm --filter @clawix/web
// build` and copies `clawix/web/dist/` into
// `Sources/clawix-bridge/Resources/web-dist/` before `swift build`,
// so the resulting binary serves the SPA on its HTTP listener
// (port 24081 by default) without needing a separate hosting layer.

let package = Package(
    name: "clawix-bridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../packages/ClawixCore"),
        .package(path: "../../../packages/ClawixEngine"),
        // Pinned at the daemon level on Apple platforms because
        // `import WhisperKit` from main.swift requires the symbol in
        // the package graph at this layer; SwiftPM still exposes the
        // public products only when the host platform is Apple.
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // Combine shim for Linux. No-op on Apple (we import Combine).
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "clawix-bridge",
            dependencies: [
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine"),
                .product(name: "WhisperKit", package: "WhisperKit", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),
                .product(name: "OpenCombineFoundation", package: "OpenCombine", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/clawix-bridge",
            resources: [
                // The web SPA bundle. Empty placeholder (`.gitkeep`) when
                // the developer has not yet run `pnpm --filter @clawix/web
                // build`; the build script populates this directory before
                // invoking `swift build`.
                .copy("Resources/web-dist")
            ],
            swiftSettings: [
                // The executable lives in `main.swift`, which would
                // otherwise be treated by Swift as a script with implicit
                // top-level code. Combined with the `@main` attribute
                // that yields a build error. `-parse-as-library` tells
                // the compiler to honour `@main` and forbid implicit
                // top-level statements, which is what the daemon needs.
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
