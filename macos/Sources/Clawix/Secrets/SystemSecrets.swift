import Foundation
import SecretsModels
import SecretsVault

/// Centralized read/write of secrets that the app itself owns (not the
/// user's hand-curated vault entries): API keys for cloud LLM providers
/// (Enhancement) and cloud transcription endpoints (Groq / Deepgram /
/// Custom). These live in a dedicated container called "Clawix System"
/// inside the same encrypted Secrets the user already has, so the app
/// never has to touch the macOS Keychain to persist a secret.
///
/// The container is created lazily on the first write. Reads return nil
/// if Secrets is not unlocked (callers treat that as "provider not
/// configured" and surface an unlock prompt at the call site).
@MainActor
enum SystemSecrets {

    /// Display name of the dedicated container. Created on demand.
    static let containerName = "Clawix System"

    // MARK: - Public API

    /// Replaces (or removes, if `value` is empty) the secret stored under
    /// `internalName` inside the system container. Throws when Secrets
    /// is not unlocked.
    static func set(
        internalName: String,
        title: String,
        value: String,
        allowedHosts: [String] = []
    ) async throws {
        guard let store = SecretsManager.shared.store else {
            throw SecretsManager.Error.notUnlocked
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
        let created = try store.createSecret(in: container, draft: draft)
        _ = try store.updateGovernance(
            secretId: created.id,
            to: Governance(
                allowedHosts: allowedHosts,
                allowedHeaders: ["Authorization", "x-api-key"],
                allowInUrl: false,
                allowInBody: false,
                allowInEnv: false,
                allowInsecureTransport: false,
                allowLocalNetwork: false,
                approvalMode: .auto
            )
        )
    }

    /// Reads the cleartext secret stored under `internalName`. Returns
    /// nil when Secrets is locked or the secret does not exist.
    static func read(internalName: String) async -> String? {
        guard let store = SecretsManager.shared.store else { return nil }
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

    /// True iff Secrets is unlocked AND a non-trashed secret exists at
    /// `internalName`. Does not reveal the value.
    static func has(internalName: String) async -> Bool {
        guard let store = SecretsManager.shared.store else { return false }
        guard let secret = try? store.fetchSecret(byInternalName: internalName) else { return false }
        return secret.trashedAt == nil
    }

    /// Performs an outbound HTTP request through the Secrets broker. The
    /// `value` field is injected inside the broker, so callers never receive
    /// the API key as a Swift string.
    static func brokerHttp(
        internalName: String,
        method: String,
        url: URL,
        headers: [String: String],
        body: String?,
        agent: String,
        riskTier: String,
        approvalSatisfied: Bool,
        timeoutMs: Int? = nil
    ) async throws -> ClawJSSecretsClient.BrokerHTTPResponse {
        guard await has(internalName: internalName) else {
            throw SecretsManager.Error.notUnlocked
        }
        if let host = url.host,
           let store = SecretsManager.shared.store,
           let secret = try? store.fetchSecret(byInternalName: internalName),
           secret.governance.allowedHosts.isEmpty {
            _ = try? store.updateGovernance(
                secretId: secret.id,
                to: Governance(
                    allowedHosts: [host],
                    allowedHeaders: ["Authorization", "x-api-key"],
                    allowInUrl: false,
                    allowInBody: false,
                    allowInEnv: false,
                    allowInsecureTransport: false,
                    allowLocalNetwork: false,
                    approvalMode: .auto
                )
            )
        }
        return try await ClawJSSecretsClient.local().brokerHttp(
            method: method,
            url: url,
            headers: headers,
            body: body,
            agent: agent,
            riskTier: riskTier,
            declaredFields: [
                .init(secretName: internalName, fieldName: "value", placement: "header")
            ],
            approvalSatisfied: approvalSatisfied,
            timeoutMs: timeoutMs
        )
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
        try await SystemSecrets.set(
            internalName: internalName(for: provider),
            title: "Enhancement - \(provider.rawValue)",
            value: key,
            allowedHosts: allowedHosts(for: provider)
        )
    }

    static func apiKey(for provider: EnhancementProviderID) async -> String? {
        await SystemSecrets.read(internalName: internalName(for: provider))
    }

    static func hasAPIKey(for provider: EnhancementProviderID) async -> Bool {
        await SystemSecrets.has(internalName: internalName(for: provider))
    }

    static func internalName(for provider: EnhancementProviderID) -> String {
        "enhancement.\(provider.rawValue)"
    }

    private static func allowedHosts(for provider: EnhancementProviderID) -> [String] {
        switch provider {
        case .openai:
            return ["api.openai.com"]
        case .anthropic:
            return ["api.anthropic.com"]
        case .groq:
            return ["api.groq.com"]
        case .mistral:
            return ["api.mistral.ai"]
        case .xai:
            return ["api.x.ai"]
        case .openrouter:
            return ["openrouter.ai"]
        case .custom:
            guard let raw = UserDefaults.standard.string(forKey: EnhancementSettings.baseURLKey(for: provider.rawValue)),
                  let host = URL(string: raw)?.host,
                  !host.isEmpty else { return [] }
            return [host]
        case .ollama:
            return ["localhost", "127.0.0.1"]
        }
    }
}

// MARK: - Cloud transcription provider keys

@MainActor
enum CloudTranscriptionSecrets {
    static func setAPIKey(_ key: String, for provider: CloudTranscriptionProvider) async throws {
        try await SystemSecrets.set(
            internalName: internalName(for: provider),
            title: "Transcription - \(provider.rawValue)",
            value: key,
            allowedHosts: allowedHosts(for: provider)
        )
    }

    static func apiKey(for provider: CloudTranscriptionProvider) async -> String? {
        await SystemSecrets.read(internalName: internalName(for: provider))
    }

    static func hasAPIKey(for provider: CloudTranscriptionProvider) async -> Bool {
        await SystemSecrets.has(internalName: internalName(for: provider))
    }

    static func internalName(for provider: CloudTranscriptionProvider) -> String {
        "transcription.\(provider.rawValue)"
    }

    private static func allowedHosts(for provider: CloudTranscriptionProvider) -> [String] {
        switch provider {
        case .groq:
            return ["api.groq.com"]
        case .deepgram:
            return ["api.deepgram.com"]
        case .custom:
            guard let raw = UserDefaults.standard.string(forKey: "\(CloudTranscriptionProvider.baseURLKeyPrefix).\(provider.rawValue)"),
                  let host = URL(string: raw)?.host,
                  !host.isEmpty else { return [] }
            return [host]
        }
    }
}
