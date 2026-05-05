// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // In-app update framework. Verifies EdDSA signatures from the
        // appcast feed before applying any update; the public key lives
        // in the generated Info.plist (SUPublicEDKey).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // SQLite-backed local persistence. Statically linked SQLite, no
        // system framework dep. Replaces the legacy JSON blob store.
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        // Wire types shared with the iOS companion. Pure Foundation, no
        // SwiftUI, no platform-specific code. Tests live in the package.
        .package(path: "../shared/ClawixCore"),
        // Engine layer: hosts the bridge server, the pairing service,
        // the Clawix subprocess wrapper, and the persistence repos
        // that the LaunchAgent daemon needs to stay alive when the
        // GUI is closed. Currently a thin layer that will absorb more
        // of `AppState`'s engine-side responsibilities as the daemon
        // refactor progresses.
        .package(path: "../shared/ClawixEngine")
    ],
    targets: [
        .executableTarget(
            name: "Clawix",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine")
            ],
            path: "Sources/Clawix",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // SwiftPM bakes only @loader_path as rpath. Sparkle.framework
                // is copied to Contents/Frameworks/ by the build scripts, so
                // the executable needs this rpath to resolve it at launch.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
