import Foundation
import SecretsModels
import SecretsVault

/// Centralized read/write of secrets that the app itself owns (not the
/// user's hand-curated vault entries). Provider accounts, model routes,
/// and provider credentials are framework-owned; this container remains
/// only for host-owned system secrets.
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
        bodyData: Data? = nil,
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
            bodyBase64: bodyData?.base64EncodedString(),
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
