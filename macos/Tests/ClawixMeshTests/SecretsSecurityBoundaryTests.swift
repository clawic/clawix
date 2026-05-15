import XCTest
@testable import Clawix

final class SecretsSecurityBoundaryTests: XCTestCase {
    func testSecretsServiceDoesNotUseDiskAdminTokenFallback() throws {
        let source = try readSource("ClawJS/ClawJSServiceManager.swift")

        XCTAssertFalse(
            source.contains("adminTokenFromDataDir(for: .secrets)"),
            "Secrets clients must not recover bearer/admin tokens from disk."
        )
        XCTAssertFalse(
            source.contains("writeAdminToken"),
            "The supervisor must not write per-session admin tokens to .admin-token files."
        )
        XCTAssertTrue(
            source.contains("for tokenURL in staleAdminTokenURLs(for: service)"),
            "Launching token-authenticated services must remove known stale .admin-token files."
        )
        XCTAssertFalse(
            source.contains("legacyClawWorkspace"),
            "Secrets launch cleanup must not keep retired .clawjs sidecar token compatibility."
        )
        XCTAssertTrue(
            source.contains("if adminTokenEnvVar[service] != nil { return false }"),
            "Token-authenticated services must not adopt an existing local sidecar through a disk bearer token."
        )
    }

    func testSecretsServiceDoesNotExposeTokensInEnvironment() throws {
        let source = try readSource("ClawJS/ClawJSServiceManager.swift")
        let environmentBody = try extractFunctionBody(
            named: "private static func environment(",
            from: source,
            until: "    private static func secretsBootstrapData"
        )

        XCTAssertTrue(
            environmentBody.contains("CLAW_SECRETS_BOOTSTRAP_STDIN"),
            "Secrets launch should use an anonymous bootstrap channel instead of token-bearing environment variables."
        )
        XCTAssertTrue(
            source.contains("hostAssertionKeyBase64"),
            "Secrets host assertions must be bootstrapped over stdin alongside signed-host material."
        )
        XCTAssertFalse(
            environmentBody.contains("env[\"CLAW_SECRETS_TOKEN\"] = adminToken"),
            "The Secrets admin bearer must not be visible through process environment inspection."
        )
        XCTAssertFalse(
            environmentBody.contains("env[\"CLAW_SECRETS_ADMIN_TOKEN\"] = adminToken"),
            "The Secrets admin bearer must not be visible through process environment inspection."
        )
        XCTAssertFalse(
            environmentBody.contains("env[\"CLAW_SECRETS_SIGNED_HOST_TOKEN\"] = signedHostToken"),
            "The signed-host token must not be visible through process environment inspection."
        )
        XCTAssertFalse(
            environmentBody.contains("env[\"CLAW_SECRETS_HOST_ASSERTION_KEY_BASE64\"]"),
            "The Secrets host assertion key must not be visible through process environment inspection."
        )
    }

    func testIntegratedServiceTokensUseStdinBootstrapNotEnvironmentOrDisk() throws {
        let source = try readSource("ClawJS/ClawJSServiceManager.swift")
        let environmentBody = try extractFunctionBody(
            named: "private static func environment(",
            from: source,
            until: "    private static func secretsBootstrapData"
        )

        XCTAssertTrue(
            source.contains("localAdminBootstrapData(adminToken: adminToken)"),
            "Database, Drive, Index, Audio, Sessions, and Publishing tokens must be sent through anonymous stdin bootstrap."
        )
        XCTAssertTrue(
            environmentBody.contains("CLAW_LOCAL_ADMIN_BOOTSTRAP_STDIN"),
            "Integrated services should receive only a non-secret bootstrap flag in the environment."
        )
        for tokenEnv in [
            "CLAW_DATABASE_ADMIN_TOKEN",
            "CLAW_DRIVE_ADMIN_TOKEN",
            "CLAW_SEARCH_ADMIN_TOKEN",
            "CLAW_AUDIO_SHARED_SECRET",
            "CLAW_SESSIONS_SHARED_SECRET",
            "CLAW_PUBLISHING_TOKEN",
        ] {
            XCTAssertFalse(
                environmentBody.contains("env[\"\(tokenEnv)\"] = adminToken"),
                "\(tokenEnv) must not be visible through process environment inspection."
            )
        }
        XCTAssertTrue(
            source.contains("env.removeValue(forKey: \"CLAW_SECRETS_KEK_BASE64\")"),
            "Host bootstrapping should scrub inherited token/KEK environment variables before spawning services."
        )
        XCTAssertFalse(
            source.contains(".appendingPathComponent(\".admin-token\", isDirectory: false)\n        try Data(token.utf8).write"),
            "Integrated service tokens must not be persisted to .admin-token files."
        )
        XCTAssertFalse(
            environmentBody.contains("CLAW_PUBLISHING_TOKEN_STORE"),
            "Clawix-owned Publishing must not use a disk token store for its host-session admin token."
        )
    }

    func testSecretsServiceUsesKeychainPlatformKeyForKekBootstrap() throws {
        let managerSource = try readSource("ClawJS/ClawJSServiceManager.swift")
        let clientSource = try readSource("ClawJS/ClawJSSecretsClient.swift")
        let lockScreenSource = try readSource("Secrets/SecretsLockScreen.swift")
        let reauthSource = try readSource("Secrets/SecretsReauthentication.swift")
        let platformKeySource = try readSource("Secrets/SecretsPlatformKey.swift")
        let localSecretKeySource = try readSource("Secrets/SecretsLocalSecretKey.swift")
        let xpcClientSource = try readSource("Secrets/SecretsXPCAssertionClient.swift")
        let xpcServiceSource = try readProjectSource("Sources/ClawixSecretsXPC/main.swift")
        let packageSource = try readProjectSource("Package.swift")
        let devScript = try readProjectSource("scripts/dev.sh")

        XCTAssertTrue(
            managerSource.contains("SecretsPlatformKey.loadOrCreate()"),
            "Secrets launch must provide a host-protected platform KEK to the ClawJS vault."
        )
        XCTAssertTrue(
            managerSource.contains("payload[\"kekBase64\"] = platformKey.base64EncodedString()"),
            "The platform KEK should travel only in the anonymous bootstrap payload."
        )
        XCTAssertTrue(
            platformKeySource.contains("SECRETS-PLATFORM-KEYCHAIN-OK"),
            "Keychain use for the Secrets platform KEK must be explicit and auditable."
        )
        XCTAssertTrue(
            platformKeySource.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"),
            "The Secrets platform KEK must be device-local, not portable Keychain material."
        )
        XCTAssertTrue(
            localSecretKeySource.contains("SECRETS-SECRET-KEY-KEYCHAIN-OK"),
            "Keychain use for the user Secret Key must be explicit and auditable."
        )
        XCTAssertTrue(
            localSecretKeySource.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"),
            "The user Secret Key must be device-local, not portable Keychain material."
        )
        XCTAssertTrue(
            clientSource.contains("body: [\"password\": password, \"secretKey\": secretKey]"),
            "The Mac client must send password + Secret Key to the ClawJS vault."
        )
        XCTAssertTrue(
            clientSource.contains("SecretsXPCAssertionClient.shared.assertionHeader"),
            "Sensitive Secrets requests must obtain per-request assertions through the native XPC boundary."
        )
        XCTAssertTrue(
            xpcClientSource.contains("NSXPCConnection(serviceName: serviceName)"),
            "The Mac app must call a bundled Secrets-only XPC service for host assertions."
        )
        XCTAssertTrue(
            xpcServiceSource.contains("NSXPCListener.service()"),
            "The Secrets XPC service must be a native bundled XPC service."
        )
        XCTAssertTrue(
            xpcServiceSource.contains("SecCodeCopyGuestWithAttributes"),
            "The Secrets XPC service must verify the caller code signature before issuing assertions."
        )
        XCTAssertTrue(
            xpcServiceSource.contains("kSecCodeInfoTeamIdentifier"),
            "The Secrets XPC service must compare caller TeamIdentifier against the signed service, not just bundle identifier text."
        )
        XCTAssertTrue(
            xpcServiceSource.contains("CLXAllowedCallerIdentifier"),
            "The Secrets XPC service must pin the allowed caller to the enclosing Clawix bundle identifier."
        )
        XCTAssertTrue(
            packageSource.contains("name: \"ClawixSecretsXPC\""),
            "The Secrets XPC service must compile as a separate native executable target."
        )
        XCTAssertTrue(
            devScript.contains("Contents/XPCServices/ClawixSecretsXPC.xpc"),
            "The dev app bundle must embed the Secrets XPC service in Contents/XPCServices."
        )
        XCTAssertTrue(
            clientSource.contains("secrets/unlock-local"),
            "Local biometric unlock must go through a dedicated signed-host endpoint."
        )
        XCTAssertTrue(
            reauthSource.contains(".deviceOwnerAuthenticationWithBiometrics"),
            "Convenient local unlock must use biometric/Secure Enclave-backed local authentication."
        )
        XCTAssertTrue(
            lockScreenSource.contains("unlockWithBiometrics"),
            "The lock screen must expose the local biometric unlock path when available."
        )
        XCTAssertTrue(
            clientSource.contains("\"oldPassword\": old, \"oldSecretKey\": oldSecretKey, \"newPassword\": new"),
            "Password changes must prove the previous password + Secret Key before rotation."
        )
    }

    func testConnectionAuthDoesNotReadOrMigratePreV1Plaintext() throws {
        let source = try readSource("Agents/AgentStore.swift")

        XCTAssertFalse(source.contains("func readConnectionAuth"))
        XCTAssertFalse(source.contains("migrateLegacyConnectionAuth"))
        XCTAssertFalse(source.contains("readLegacyConnectionAuth"))
        XCTAssertFalse(source.contains("legacyConnectionAuthURL"))
        XCTAssertFalse(source.contains("auth.encrypted"))
        XCTAssertFalse(source.contains("revealField"))
        XCTAssertTrue(source.contains("func hasConnectionAuth(connectionId: String) -> Bool"))
        XCTAssertTrue(source.contains("store.fetchSecret(byInternalName: internalName)"))
    }

    func testSystemProviderSecretsDoNotExposePlaintextReadHelpers() throws {
        let source = try readSource("Secrets/SystemSecrets.swift")

        XCTAssertFalse(
            source.contains("static func read(internalName:"),
            "System-owned provider secrets must be used through brokerHttp, not generic plaintext reads."
        )
        XCTAssertFalse(
            source.contains("static func apiKey(for provider:"),
            "Provider-specific API key helpers must not return plaintext to provider code."
        )
    }

    func testAIAccountCredentialRevealFailsClosed() throws {
        let source = try readSource("Providers/AIAccountSecretsStore.swift")
        let body = try extractFunctionBody(
            named: "func revealCredentials(accountId: UUID) throws -> AIAccountCredentials",
            from: source,
            until: "    nonisolated func credentialExpiresAt"
        )

        XCTAssertTrue(
            body.contains("throw AIAccountStoreError.credentialMissing"),
            "The revealCredentials protocol method must fail closed."
        )
        XCTAssertFalse(body.contains("store.revealField"))
        XCTAssertFalse(body.contains("revealCredentialsRaw"))
        XCTAssertFalse(body.contains("return credentials"))
    }

    func testEncryptedBackupRequiresNativeReauthentication() throws {
        let source = try readSource("Secrets/SecretsSettingsPage.swift")

        XCTAssertTrue(
            source.contains("SecretsReauthentication.require(reason: \"Export an encrypted Secrets backup from Clawix.\")"),
            "Backup export must reauthenticate in the signed host before calling the Secrets backend."
        )
        XCTAssertTrue(
            source.contains("exportEncryptedBackup(passphrase: passphrase, reauthSatisfied: true)"),
            "Backup export must pass explicit reauthSatisfied evidence to the backend."
        )
        XCTAssertTrue(
            source.contains("SecretsReauthentication.require(reason: \"Restore an encrypted Secrets backup in Clawix.\")"),
            "Backup restore must reauthenticate in the signed host before calling the Secrets backend."
        )
        XCTAssertTrue(
            source.contains("importEncryptedBackup(data, passphrase: passphrase, reauthSatisfied: true)"),
            "Backup restore must pass explicit reauthSatisfied evidence to the backend."
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    private func extractFunctionBody(named name: String, from source: String, until marker: String) throws -> String {
        guard let start = source.range(of: name)?.lowerBound else {
            XCTFail("Could not find \(name)")
            return ""
        }
        guard let end = source.range(of: marker, range: start..<source.endIndex)?.lowerBound else {
            XCTFail("Could not find marker \(marker)")
            return ""
        }
        return String(source[start..<end])
    }
}
