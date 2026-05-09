import AIProviders
import AppKit
import AuthenticationServices
import Foundation

/// Owns the in-progress OAuth dance: launches `ASWebAuthenticationSession`,
/// extracts the authorization code from the callback URL, exchanges it
/// for tokens, persists the new account.
@MainActor
final class OAuthCoordinator: NSObject, ObservableObject {

    enum CoordinatorError: Error, LocalizedError {
        case userCancelled
        case stateMismatch
        case missingCode
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled: return "Sign-in was cancelled."
            case .stateMismatch: return "OAuth state mismatch (possible CSRF)."
            case .missingCode: return "No authorization code in callback URL."
            case .underlying(let s): return s
            }
        }
    }

    @Published var inFlight = false
    @Published var lastError: String?

    private var session: ASWebAuthenticationSession?

    /// Runs the full flow for `flavor` and persists a new account on
    /// success. Returns the new account.
    func signIn(flavor: OAuthFlavor) async throws -> ProviderAccount {
        inFlight = true
        defer { inFlight = false }
        let strategy = OAuthRegistry.strategy(for: flavor)
        let authorization = strategy.startAuthorization()
        let callbackURL = try await runWebSession(start: authorization.url, scheme: "clawix")
        guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            throw CoordinatorError.missingCode
        }
        guard returnedState == authorization.state else {
            throw CoordinatorError.stateMismatch
        }
        guard let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CoordinatorError.missingCode
        }
        let tokens = try await strategy.exchangeCode(code, verifier: authorization.codeVerifier)
        let store = AIAccountVaultStore.shared
        let label = labelFromTokens(tokens, store: store, providerId: strategy.providerId)
        let draft = ProviderAccountDraft(
            providerId: strategy.providerId,
            label: label,
            authMethod: .oauth(flavor),
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            scope: tokens.scope,
            accountEmail: tokens.accountEmail
        )
        let account = try store.createAccount(draft)
        AIAccountStoreObservable.shared.refresh()
        return account
    }

    private func labelFromTokens(_ tokens: OAuthTokens, store: AIAccountStore, providerId: ProviderID) -> String {
        if let email = tokens.accountEmail, !email.isEmpty { return email }
        let count = (try? store.listAccounts(for: providerId).count) ?? 0
        return count == 0 ? "Personal" : "Account \(count + 1)"
    }

    private func runWebSession(start: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: start,
                callbackURLScheme: scheme
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: CoordinatorError.userCancelled)
                    } else {
                        continuation.resume(throwing: CoordinatorError.underlying(error.localizedDescription))
                    }
                    return
                }
                if let error {
                    continuation.resume(throwing: CoordinatorError.underlying(error.localizedDescription))
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CoordinatorError.missingCode)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }
}

extension OAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Pull the key window from AppKit. macOS provides one even
        // when no window is attached to a SwiftUI scene.
        DispatchQueue.main.sync {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }
}
