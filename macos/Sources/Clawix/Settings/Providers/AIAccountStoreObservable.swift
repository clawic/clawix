import AIProviders
import Combine
import Foundation
import SwiftUI

/// Thin SwiftUI bridge over `AIAccountStore`. Re-publishes the latest
/// accounts list and exposes mutating helpers that refresh on success.
/// Backed by `AIAccountSecretsStore.shared` in production; tests inject
/// any `AIAccountStore`.
@MainActor
final class AIAccountStoreObservable: ObservableObject {

    static let shared = AIAccountStoreObservable()

    @Published private(set) var accounts: [ProviderAccount] = []
    @Published var lastError: String?

    private let store: AIAccountStore

    init(store: AIAccountStore = AIAccountSecretsStore.shared) {
        self.store = store
        refresh()
    }

    func refresh() {
        do {
            accounts = try store.listAccounts()
        } catch {
            accounts = []
            lastError = (error as? AIAccountStoreError).map(humanize) ?? error.localizedDescription
        }
    }

    func accounts(for provider: ProviderID) -> [ProviderAccount] {
        accounts.filter { $0.providerId == provider }
    }

    @discardableResult
    func create(_ draft: ProviderAccountDraft) -> ProviderAccount? {
        do {
            let account = try store.createAccount(draft)
            refresh()
            return account
        } catch {
            lastError = humanize(error)
            return nil
        }
    }

    func updateLabel(id: UUID, label: String) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: label,
                isEnabled: nil,
                baseURLOverride: .none,
                accountEmail: .none
            )
            refresh()
        } catch {
            lastError = humanize(error)
        }
    }

    func setEnabled(id: UUID, enabled: Bool) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: nil,
                isEnabled: enabled,
                baseURLOverride: .none,
                accountEmail: .none
            )
            refresh()
        } catch {
            lastError = humanize(error)
        }
    }

    func setBaseURL(id: UUID, url: URL?) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: nil,
                isEnabled: nil,
                baseURLOverride: .some(url),
                accountEmail: .none
            )
            refresh()
        } catch {
            lastError = humanize(error)
        }
    }

    func delete(id: UUID) {
        do {
            try store.deleteAccount(id: id)
            for feature in FeatureRouting.FeatureID.allCases {
                let key = FeatureRouting.providerAccountKey(feature)
                if UserDefaults.standard.string(forKey: key) == id.uuidString.lowercased() {
                    FeatureRouting.clearSelection(feature: feature)
                }
            }
            refresh()
        } catch {
            lastError = humanize(error)
        }
    }

    private func humanize(_ error: Error) -> String {
        if let storeError = error as? AIAccountStoreError {
            switch storeError {
            case .vaultLocked: return "Secrets is locked. Unlock it in Settings → Secrets."
            case .accountNotFound: return "This account no longer exists."
            case .providerUnknown: return "Unknown provider."
            case .credentialMissing: return "No credentials stored for this account."
            case .duplicateLabel: return "Another account already uses this label."
            case .underlying(let msg): return msg
            }
        }
        return error.localizedDescription
    }
}
