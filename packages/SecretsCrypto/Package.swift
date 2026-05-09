// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsCrypto",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretsCrypto", targets: ["SecretsCrypto"])
    ],
    dependencies: [
        .package(path: "../ClawixArgon2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "SecretsCrypto",
            dependencies: [
                .product(name: "ClawixArgon2", package: "ClawixArgon2"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/SecretsCrypto"
        ),
        .testTarget(
            name: "SecretsCryptoTests",
            dependencies: ["SecretsCrypto"],
            path: "Tests/SecretsCryptoTests"
        )
    ]
)
