import Foundation
import SecretsModels
import SecretsVault

/// Centralized read/write of secrets that the app itself owns (not the
/// user's hand-curated vault entries): API keys for cloud LLM providers
/// (Enhancement) and cloud transcription endpoints (Groq / Deepgram /
/// Custom). These live in a dedicated container called "Clawix System"
/// inside the same encrypted vault the user already has, so the app
/// never has to touch the macOS Keychain to persist a secret.
///
/// The container is created lazily on the first write. Reads return nil
/// if the vault is not unlocked (callers treat that as "provider not
/// configured" and surface an unlock prompt at the call site).
@MainActor
enum SystemVaultSecrets {

    /// Display name of the dedicated container. Created on demand.
    static let containerName = "Clawix System"

    // MARK: - Public API

    /// Replaces (or removes, if `value` is empty) the secret stored under
    /// `internalName` inside the system container. Throws when the vault
    /// is not unlocked.
    static func set(internalName: String, title: String, value: String) async throws {
        guard let store = VaultManager.shared.store else {
            throw VaultManager.Error.notUnlocked
        }
        if let existing = try store.fetchSecret(byInternalName: internalName) {
            try store.trashSecret(id: existing.id)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let container = try ensureContainer(in: store)
        let draft = DraftSecret(
            kind: .apiKey,
            internalName: internalName,
            title: title,
            fields: [
                DraftField(
                    name: "value",
                    fieldKind: .password,
                    placement: .header,
                    isSecret: true,
                    isConcealed: true,
                    secretValue: trimmed,
                    sortOrder: 0
                )
            ]
        )
        _ = try store.createSecret(in: container, draft: draft)
    }

    /// Reads the cleartext secret stored under `internalName`. Returns
    /// nil when the vault is locked or the secret does not exist.
    static func read(internalName: String) async -> String? {
        guard let store = VaultManager.shared.store else { return nil }
        do {
            guard let secret = try store.fetchSecret(byInternalName: internalName) else {
                return nil
            }
            if secret.trashedAt != nil { return nil }
            let fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
            guard let field = fields.first(where: { $0.fieldName == "value" }) else { return nil }
            let revealed = try store.revealField(field, purpose: .reveal)
            return revealed.value
        } catch {
            return nil
        }
    }

    /// True iff the vault is unlocked AND a non-trashed secret exists at
    /// `internalName`. Does not reveal the value.
    static func has(internalName: String) async -> Bool {
        guard let store = VaultManager.shared.store else { return false }
        guard let secret = try? store.fetchSecret(byInternalName: internalName) else { return false }
        return secret.trashedAt == nil
    }

    // MARK: - Container

    private static func ensureContainer(in store: ClawJSSecretsStore) throws -> VaultRecord {
        let containers = try store.listVaults()
        if let existing = containers.first(where: { $0.name == containerName }) {
            return existing
        }
        return try store.createVault(name: containerName)
    }
}

// MARK: - Enhancement provider keys

@MainActor
enum EnhancementSecrets {
    static func setAPIKey(_ key: String, for provider: EnhancementProviderID) async throws {
        try await SystemVaultSecrets.set(
            internalName: internalName(for: provider),
            title: "Enhancement - \(provider.rawValue)",
            value: key
        )
    }

    static func apiKey(for provider: EnhancementProviderID) async -> String? {
        await SystemVaultSecrets.read(internalName: internalName(for: provider))
    }

    static func hasAPIKey(for provider: EnhancementProviderID) async -> Bool {
        await SystemVaultSecrets.has(internalName: internalName(for: provider))
    }

    private static func internalName(for provider: EnhancementProviderID) -> String {
        "enhancement.\(provider.rawValue)"
    }
}

// MARK: - Cloud transcription provider keys

@MainActor
enum CloudTranscriptionSecrets {
    static func setAPIKey(_ key: String, for provider: CloudTranscriptionProvider) async throws {
        try await SystemVaultSecrets.set(
            internalName: internalName(for: provider),
            title: "Transcription - \(provider.rawValue)",
            value: key
        )
    }

    static func apiKey(for provider: CloudTranscriptionProvider) async -> String? {
        await SystemVaultSecrets.read(internalName: internalName(for: provider))
    }

    static func hasAPIKey(for provider: CloudTranscriptionProvider) async -> Bool {
        await SystemVaultSecrets.has(internalName: internalName(for: provider))
    }

    private static func internalName(for provider: CloudTranscriptionProvider) -> String {
        "transcription.\(provider.rawValue)"
    }
}
