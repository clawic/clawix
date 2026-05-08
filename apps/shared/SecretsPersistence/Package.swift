// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsPersistence",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretsPersistence", targets: ["SecretsPersistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(path: "../SecretsModels")
    ],
    targets: [
        .target(
            name: "SecretsPersistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SecretsModels", package: "SecretsModels")
            ],
            path: "Sources/SecretsPersistence"
        ),
        .testTarget(
            name: "SecretsPersistenceTests",
            dependencies: ["SecretsPersistence"],
            path: "Tests/SecretsPersistenceTests"
        )
    ]
)
