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
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "Clawix",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GRDB", package: "GRDB.swift")
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
