// swift-tools-version: 5.9
import PackageDescription

// `clawix-secrets-proxy` is the CLI helper that Codex / Claude Code / scripts
// invoke to use vault secrets without ever seeing the literal value. It
// connects to the live macOS app over a unix-domain socket and exchanges
// JSON-line frames using `SecretsProxyCore`. Bundled at
// `Clawix.app/Contents/Helpers/clawix-secrets-proxy`; usually symlinked at
// `~/bin/clawix-secrets-proxy` for ergonomic shell use.

let package = Package(
    name: "clawix-secrets-proxy",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../shared/SecretsProxyCore")
    ],
    targets: [
        .executableTarget(
            name: "clawix-secrets-proxy",
            dependencies: [
                .product(name: "SecretsProxyCore", package: "SecretsProxyCore")
            ],
            path: "Sources/SecretsProxy"
        )
    ]
)
