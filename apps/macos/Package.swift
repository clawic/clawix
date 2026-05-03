// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // SQLite-backed local persistence. Statically linked SQLite, no
        // system framework dep. Replaces the legacy JSON blob store.
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "Clawix",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Clawix",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
