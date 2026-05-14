import AIProviders
import Foundation
import SecretsModels

@MainActor
enum AIAccountBroker {
    nonisolated static func secretName(for account: ProviderAccount) -> String {
        InternalName.encode(providerId: account.providerId, accountId: account.id)
    }

    static func send(
        account: ProviderAccount,
        fieldName: String = "value",
        placement: String = "header",
        method: String,
        url: URL,
        headers: [String: String],
        body: String?,
        bodyData: Data? = nil,
        agent: String,
        riskTier: String,
        timeoutSeconds: Int
    ) async throws -> (Data, Int) {
        let secretName = secretName(for: account)
        try ensureGovernance(
            secretName: secretName,
            url: url,
            headers: Array(headers.keys),
            placement: placement
        )
        let response = try await ClawJSSecretsClient.local().brokerHttp(
            method: method,
            url: url,
            headers: headers,
            body: body,
            bodyBase64: bodyData?.base64EncodedString(),
            agent: agent,
            riskTier: riskTier,
            declaredFields: [
                .init(secretName: secretName, fieldName: fieldName, placement: placement)
            ],
            approvalSatisfied: false,
            timeoutMs: timeoutSeconds * 1000
        )
        let status = response.status ?? 0
        if response.ok {
            if let bodyBase64 = response.bodyBase64,
               let data = Data(base64Encoded: bodyBase64) {
                return (data, status)
            }
            return (Data((response.bodyText ?? "").utf8), status)
        }
        throw AIClientError.http(status, response.bodyText ?? "")
    }

    private static func ensureGovernance(
        secretName: String,
        url: URL,
        headers: [String],
        placement: String
    ) throws {
        guard let store = SecretsManager.shared.store else {
            throw AIAccountStoreError.vaultLocked
        }
        guard let secret = try store.fetchSecret(byInternalName: secretName) else {
            throw AIAccountStoreError.accountNotFound
        }
        guard let host = url.host, !host.isEmpty else { return }
        var governance = secret.governance
        var changed = false
        if governance.allowedHosts.isEmpty {
            governance.allowedHosts = [host]
            changed = true
        }
        let headerSet = Set(governance.allowedHeaders.map { $0.lowercased() })
        let missingHeaders = headers.filter { !headerSet.contains($0.lowercased()) }
        if !missingHeaders.isEmpty {
            governance.allowedHeaders.append(contentsOf: missingHeaders)
            changed = true
        }
        if placement == "query", !governance.allowInUrl {
            governance.allowInUrl = true
            changed = true
        }
        if placement == "body", !governance.allowInBody {
            governance.allowInBody = true
            changed = true
        }
        if url.scheme == "http", isLocalHost(host), !governance.allowLocalNetwork {
            governance.allowLocalNetwork = true
            changed = true
        }
        if changed {
            _ = try store.updateGovernance(secretId: secret.id, to: governance)
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
