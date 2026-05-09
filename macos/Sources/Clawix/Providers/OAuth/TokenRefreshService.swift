import AIProviders
import Foundation

/// Background actor that walks every OAuth account on a 60s timer and
/// refreshes their access tokens before they expire (5-min lookahead).
/// Pauses when the vault is locked; resumes on `VaultLifecycle.didUnlock`.
@MainActor
final class TokenRefreshService: ObservableObject {

    static let shared = TokenRefreshService()

    private var timer: Timer?
    private var failures: [UUID: Int] = [:]
    private let maxFailures = 3
    private let lookahead: TimeInterval = 5 * 60
    private let interval: TimeInterval = 60

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        Task { @MainActor in await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() async {
        let store = AIAccountVaultStore.shared
        let accounts = (try? store.listAccounts()) ?? []
        for account in accounts {
            guard case .oauth(let flavor) = account.authMethod, account.isEnabled else { continue }
            do {
                let credentials = try store.revealCredentials(accountId: account.id)
                guard let refreshToken = credentials.refreshToken else { continue }
                if let expiresAt = credentials.expiresAt,
                   expiresAt.timeIntervalSinceNow > lookahead {
                    continue
                }
                let strategy = OAuthRegistry.strategy(for: flavor)
                let tokens = try await strategy.refresh(refreshToken: refreshToken)
                try store.updateCredentials(
                    accountId: account.id,
                    apiKey: nil,
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken ?? refreshToken,
                    expiresAt: tokens.expiresAt,
                    scope: tokens.scope
                )
                failures[account.id] = 0
            } catch {
                let count = (failures[account.id] ?? 0) + 1
                failures[account.id] = count
                if count >= maxFailures {
                    _ = try? store.updateAccount(
                        id: account.id,
                        label: nil,
                        isEnabled: false,
                        baseURLOverride: .none,
                        accountEmail: .none
                    )
                }
            }
        }
        AIAccountStoreObservable.shared.refresh()
    }
}
