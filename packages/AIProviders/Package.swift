// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIProviders",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AIProviders", targets: ["AIProviders"])
    ],
    targets: [
        .target(name: "AIProviders", path: "Sources/AIProviders"),
        .testTarget(
            name: "AIProvidersTests",
            dependencies: ["AIProviders"],
            path: "Tests/AIProvidersTests"
        )
    ]
)
