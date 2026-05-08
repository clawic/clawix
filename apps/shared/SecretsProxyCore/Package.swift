// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecretsProxyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "SecretsProxyCore", targets: ["SecretsProxyCore"])
    ],
    targets: [
        .target(
            name: "SecretsProxyCore",
            path: "Sources/SecretsProxyCore"
        ),
        .testTarget(
            name: "SecretsProxyCoreTests",
            dependencies: ["SecretsProxyCore"],
            path: "Tests/SecretsProxyCoreTests"
        )
    ]
)
