// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsVault",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretsVault", targets: ["SecretsVault"])
    ],
    dependencies: [
        .package(path: "../SecretsModels"),
        .package(path: "../SecretsCrypto"),
        .package(path: "../SecretsPersistence"),
        .package(path: "../SecretsProxyCore")
    ],
    targets: [
        .target(
            name: "SecretsVault",
            dependencies: [
                .product(name: "SecretsModels", package: "SecretsModels"),
                .product(name: "SecretsCrypto", package: "SecretsCrypto"),
                .product(name: "SecretsPersistence", package: "SecretsPersistence"),
                .product(name: "SecretsProxyCore", package: "SecretsProxyCore")
            ],
            path: "Sources/SecretsVault"
        ),
        .testTarget(
            name: "SecretsVaultTests",
            dependencies: ["SecretsVault"],
            path: "Tests/SecretsVaultTests"
        )
    ]
)
