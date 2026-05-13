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
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        // Wire types shared with the iOS companion. Pure Foundation, no
        // SwiftUI, no platform-specific code. Tests live in the package.
        .package(path: "../packages/ClawixCore"),
        // Engine layer: hosts the bridge server, the pairing service,
        // the Clawix subprocess wrapper, and the persistence repos
        // that the LaunchAgent daemon needs to stay alive when the
        // GUI is closed. Currently a thin layer that will absorb more
        // of `AppState`'s engine-side responsibilities as the daemon
        // refactor progresses.
        .package(path: "../packages/ClawixEngine"),
        // Secrets data model (Codable records; pure Foundation).
        .package(path: "../packages/SecretsModels"),
        // Secrets crypto primitives (Argon2id KDF + ChaCha20-Poly1305
        // AEAD + verifier + LockableSecret + calibration).
        .package(path: "../packages/SecretsCrypto"),
        // Argon2id reference implementation, vendored.
        .package(path: "../packages/ClawixArgon2"),
        // Secrets persistence (GRDB schema, migrator, record conformances).
        .package(path: "../packages/SecretsPersistence"),
        // High-level Secrets store (CRUD + per-item key wrapping).
        .package(path: "../packages/SecretsVault"),
        // Wire types + placeholder resolver + redactor shared with the helper.
        .package(path: "../packages/SecretsProxyCore"),
        // Static catalog of cloud AI providers (OpenAI, Anthropic, Groq,
        // Gemini, ...) plus the AIAccountStore protocol the Settings →
        // Model Providers panel persists accounts against. Pure Foundation,
        // shared with iOS even though the macOS app is the only consumer
        // for the v1 panel UI.
        .package(path: "../packages/AIProviders"),
        // Global keyboard-shortcut binding library. Powers the
        // user-customizable cancel shortcut and the Last/Retry
        // quick-action bindings; supports any key + modifier combo
        // via Carbon EventHotKey so the bindings fire regardless of
        // foreground app.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0"),
        // PTY-backed terminal emulator (xterm-256color). Owns the
        // `forkpty` + read loop + escape-sequence parser the integrated
        // terminal panel renders. Pure Swift, no extra signing surface.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        // Local framework host runtime. Clawix embeds this under its own
        // signed identity instead of calling a standalone Claw.app.
        .package(path: "../../../clawjs/apps/host")
    ],
    targets: [
        .testTarget(
            name: "ClawixMeshTests",
            dependencies: [
                "Clawix",
                .product(name: "ClawixCore", package: "ClawixCore")
            ],
            path: "Tests/ClawixMeshTests"
        ),
        .executableTarget(
            name: "Clawix",
            dependencies: [
                "ClawixSimulatorKitShim",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ClawixCore", package: "ClawixCore"),
                .product(name: "ClawixEngine", package: "ClawixEngine"),
                .product(name: "SecretsModels", package: "SecretsModels"),
                .product(name: "SecretsCrypto", package: "SecretsCrypto"),
                .product(name: "ClawixArgon2", package: "ClawixArgon2"),
                .product(name: "SecretsPersistence", package: "SecretsPersistence"),
                .product(name: "SecretsVault", package: "SecretsVault"),
                .product(name: "SecretsProxyCore", package: "SecretsProxyCore"),
                .product(name: "AIProviders", package: "AIProviders"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "ClawHostKit", package: "host")
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
        ),
        .target(
            name: "ClawixSimulatorKitShim",
            path: "Sources/ClawixSimulatorKitShim",
            publicHeadersPath: "include"
        )
    ]
)
