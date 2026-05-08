// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawixArgon2",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ClawixArgon2", targets: ["ClawixArgon2"])
    ],
    targets: [
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("blake2"),
                .define("ARGON2_NO_THREADS", to: "1")
            ]
        ),
        .target(
            name: "ClawixArgon2",
            dependencies: ["CArgon2"],
            path: "Sources/ClawixArgon2"
        ),
        .testTarget(
            name: "ClawixArgon2Tests",
            dependencies: ["ClawixArgon2"],
            path: "Tests/ClawixArgon2Tests"
        )
    ]
)
