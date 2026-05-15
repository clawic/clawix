import AIProviders
import Foundation

/// Centralized framework routing for the `(provider account, model)`
/// each feature should use. Credentials remain in the host vault; the
/// framework stores only opaque account refs and policy/config records.
@MainActor
enum FeatureRouting {

    /// Identifier of an in-app feature that consumes a provider.
    /// Adding a new feature: append a case + UI consumes
    /// `FeatureProviderPicker(featureId: .myNewFeature, capability: .x)`.
    enum FeatureID: String, CaseIterable, Codable, Sendable {
        case enhancement
        case sttCloud
        case ttsCloud

        var defaultCapability: Capability {
            switch self {
            case .enhancement: return .chat
            case .sttCloud: return .stt
            case .ttsCloud: return .tts
            }
        }
    }

    /// Resolves the last selected `(account, model)` for a feature,
    /// validating that the account still exists and is enabled for
    /// the requested capability. Returns nil when the user hasn't
    /// picked anything yet, or when the previous selection has been
    /// invalidated (account deleted, provider disabled).
    @MainActor
    static func resolve(
        feature: FeatureID,
        capability: Capability,
        store: AIAccountStore
    ) -> (account: ProviderAccount, model: ModelDefinition)? {
        guard let route = route(feature: feature, capability: capability),
              let accountRef = route.accountRef,
              let accountId = parseAccountId(from: accountRef) else {
            return nil
        }
        guard let accounts = try? store.listAccounts(),
              let account = accounts.first(where: { $0.id == accountId }),
              account.isEnabled,
              isProviderEnabled(account.providerId)
        else {
            return nil
        }
        let modelId = route.model
            ?? ProviderCatalog.defaultModel(for: capability, in: account.providerId)?.id
        guard let modelId,
              let model = ProviderCatalog.model(providerId: account.providerId, modelId: modelId),
              model.capabilities.contains(capability)
        else {
            return nil
        }
        return (account, model)
    }

    static func setSelection(
        feature: FeatureID,
        accountId: UUID,
        modelId: String
    ) {
        guard let accounts = try? AIAccountSecretsStore.shared.listAccounts(),
              let account = accounts.first(where: { $0.id == accountId }) else { return }
        try? ClawJSFrameworkRecordsClient.shared.setProviderRoute(
            feature: feature.rawValue,
            capability: feature.defaultCapability.rawValue,
            provider: account.providerId.rawValue,
            model: modelId,
            accountRef: accountRef(provider: account.providerId, accountId: accountId)
        )
    }

    static func clearSelection(feature: FeatureID) {
        try? ClawJSFrameworkRecordsClient.shared.deleteProviderRoute(
            feature: feature.rawValue,
            capability: feature.defaultCapability.rawValue
        )
    }

    static func clearSelections(forAccountId accountId: UUID) {
        guard let routes = try? ClawJSFrameworkRecordsClient.shared.listProviderRoutes() else { return }
        for route in routes where parseAccountId(from: route.accountRef ?? "") == accountId {
            guard let feature = FeatureID(rawValue: route.feature) else { continue }
            try? ClawJSFrameworkRecordsClient.shared.deleteProviderRoute(
                feature: feature.rawValue,
                capability: route.capability
            )
        }
    }

    static func isProviderEnabled(_ provider: ProviderID) -> Bool {
        guard let settings = try? ClawJSFrameworkRecordsClient.shared.listProviderSettings(),
              let setting = settings.first(where: { $0.provider == provider.rawValue }) else { return true }
        return setting.enabled
    }

    static func setProviderEnabled(_ provider: ProviderID, enabled: Bool) {
        try? ClawJSFrameworkRecordsClient.shared.setProviderEnabled(provider.rawValue, enabled: enabled)
    }

    private static func route(feature: FeatureID, capability: Capability) -> ClawJSFrameworkRecordsClient.ProviderRoute? {
        guard let routes = try? ClawJSFrameworkRecordsClient.shared.listProviderRoutes() else { return nil }
        return routes.first { $0.feature == feature.rawValue && $0.capability == capability.rawValue }
    }

    private static func accountRef(provider: ProviderID, accountId: UUID) -> String {
        "vault://providers/\(provider.rawValue)/\(accountId.uuidString.lowercased())"
    }

    private static func parseAccountId(from accountRef: String) -> UUID? {
        UUID(uuidString: accountRef.split(separator: "/").last.map(String.init) ?? "")
    }
}
