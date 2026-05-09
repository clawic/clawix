// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsModels",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretsModels", targets: ["SecretsModels"])
    ],
    targets: [
        .target(
            name: "SecretsModels",
            path: "Sources/SecretsModels"
        ),
        .testTarget(
            name: "SecretsModelsTests",
            dependencies: ["SecretsModels"],
            path: "Tests/SecretsModelsTests"
        )
    ]
)
