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
        .package(path: "../shared/ClawixCore"),
        // Engine layer: hosts the bridge server, the pairing service,
        // the Clawix subprocess wrapper, and the persistence repos
        // that the LaunchAgent daemon needs to stay alive when the
        // GUI is closed. Currently a thin layer that will absorb more
        // of `AppState`'s engine-side responsibilities as the daemon
        // refactor progresses.
        .package(path: "../shared/ClawixEngine"),
        // Secrets vault data model (Codable records; pure Foundation).
        .package(path: "../shared/SecretsModels"),
        // Secrets vault crypto primitives (Argon2id KDF + ChaCha20-Poly1305
        // AEAD + verifier + LockableSecret + calibration).
        .package(path: "../shared/SecretsCrypto"),
        // Argon2id reference implementation, vendored.
        .package(path: "../shared/ClawixArgon2"),
        // Secrets vault persistence (GRDB schema, migrator, record conformances).
        .package(path: "../shared/SecretsPersistence"),
        // High-level secrets vault store (CRUD + per-item key wrapping).
        .package(path: "../shared/SecretsVault"),
        // Wire types + placeholder resolver + redactor shared with the helper.
        .package(path: "../shared/SecretsProxyCore"),
        // Global keyboard-shortcut binding library. Powers the
        // user-customizable cancel shortcut and the Last/Retry
        // quick-action bindings; supports any key + modifier combo
        // via Carbon EventHotKey so the bindings fire regardless of
        // foreground app.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0"),
        // Lucide icons as SF Symbol-style assets. Imported as
        // `Image(lucide: .someName)` from SwiftUI views that prefer
        // the Lucide visual over Apple's SF Symbols. Already vendored
        // into `.build/checkouts` by an earlier resolution; this
        // declaration restores it as an explicit dependency so the
        // linker actually pulls in the static lib's symbols.
        .package(url: "https://github.com/lcandy2/LucideIcon.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Clawix",
            dependencies: [
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
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LucideIcon", package: "LucideIcon")
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
        )
    ]
)
