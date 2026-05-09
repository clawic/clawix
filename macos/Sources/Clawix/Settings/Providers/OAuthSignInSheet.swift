import AIProviders
import SwiftUI

/// Hosts `OAuthCoordinator` and shows a spinner while the system web
/// session runs. Closes itself on success or failure.
struct OAuthSignInSheet: View {
    let provider: ProviderDefinition
    let flavor: OAuthFlavor

    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = OAuthCoordinator()
    @State private var error: String?
    @State private var didStart = false

    var body: some View {
        VStack(spacing: 18) {
            ProviderBrandIcon(brand: provider.brand, size: 40)
            Text("Sign in with \(provider.displayName)")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            if coordinator.inFlight {
                Text("Complete the flow in your browser…")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                ProgressView()
                    .controlSize(.small)
            } else if let error {
                Text(error)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Button("Try again") { startFlow() }
                    .buttonStyle(.bordered)
            } else {
                Text("A browser window will open shortly.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 360)
        .background(Palette.background)
        .onAppear {
            if !didStart {
                didStart = true
                startFlow()
            }
        }
    }

    private func startFlow() {
        error = nil
        Task { @MainActor in
            do {
                _ = try await coordinator.signIn(flavor: flavor)
                dismiss()
            } catch let coordError as OAuthCoordinator.CoordinatorError {
                error = coordError.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
