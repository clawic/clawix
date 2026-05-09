import AIProviders
import Foundation

/// Centralized UserDefaults keys used by features to remember which
/// `(provider account, model)` they last picked. Keeps every key in one
/// place so JSON-export, factory-reset, and "feature uses provider"
/// audits can enumerate them.
enum FeatureRouting {

    /// Identifier of an in-app feature that consumes a provider.
    /// Adding a new feature: append a case + UI consumes
    /// `FeatureProviderPicker(featureId: .myNewFeature, capability: .x)`.
    enum FeatureID: String, CaseIterable, Codable, Sendable {
        case enhancement
        case sttCloud
        case ttsCloud
    }

    static func providerAccountKey(_ feature: FeatureID) -> String {
        "feature.\(feature.rawValue).providerAccountId"
    }

    static func modelKey(_ feature: FeatureID) -> String {
        "feature.\(feature.rawValue).modelId"
    }

    static func providerEnabledKey(_ provider: ProviderID) -> String {
        "provider.\(provider.rawValue).enabled"
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
        let defaults = UserDefaults.standard
        guard let accountIdString = defaults.string(forKey: providerAccountKey(feature)),
              let accountId = UUID(uuidString: accountIdString) else {
            return nil
        }
        guard let accounts = try? store.listAccounts(),
              let account = accounts.first(where: { $0.id == accountId }),
              account.isEnabled,
              isProviderEnabled(account.providerId)
        else {
            return nil
        }
        let modelId = defaults.string(forKey: modelKey(feature))
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
        let defaults = UserDefaults.standard
        defaults.set(accountId.uuidString.lowercased(), forKey: providerAccountKey(feature))
        defaults.set(modelId, forKey: modelKey(feature))
    }

    static func clearSelection(feature: FeatureID) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: providerAccountKey(feature))
        defaults.removeObject(forKey: modelKey(feature))
    }

    static func isProviderEnabled(_ provider: ProviderID) -> Bool {
        let key = providerEnabledKey(provider)
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setProviderEnabled(_ provider: ProviderID, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: providerEnabledKey(provider))
    }
}
