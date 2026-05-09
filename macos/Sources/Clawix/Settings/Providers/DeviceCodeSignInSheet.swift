import AIProviders
import AppKit
import SwiftUI

/// Device-code flow UI: shows the `user_code`, copies on demand, opens
/// the verification URL, and polls until GitHub returns an access token.
struct DeviceCodeSignInSheet: View {
    let provider: ProviderDefinition
    let flavor: DeviceCodeFlavor

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIAccountStoreObservable.shared

    @State private var deviceCode: GitHubCopilotDeviceFlow.DeviceCode?
    @State private var error: String?
    @State private var phase: Phase = .requesting

    enum Phase {
        case requesting
        case waiting
        case done
    }

    var body: some View {
        VStack(spacing: 18) {
            ProviderBrandIcon(brand: provider.brand, size: 40)
            Text("Sign in with \(provider.displayName)")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)

            switch phase {
            case .requesting:
                ProgressView()
                Text("Requesting device code…")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            case .waiting:
                if let deviceCode {
                    waitingContent(deviceCode)
                }
            case .done:
                Text("Connected.")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Color.green)
            }

            if let error {
                Text(error)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 380)
        .background(Palette.background)
        .onAppear { Task { await runFlow() } }
    }

    @ViewBuilder
    private func waitingContent(_ code: GitHubCopilotDeviceFlow.DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text(code.userCode)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .buttonStyle(.bordered)
                Button {
                    NSWorkspace.shared.open(code.verificationUri)
                } label: {
                    Label("Open browser", systemImage: "arrow.up.right.square")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Waiting for authorization…")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    private func runFlow() async {
        let flow = GitHubCopilotDeviceFlow()
        do {
            phase = .requesting
            let device = try await flow.requestDeviceCode()
            deviceCode = device
            phase = .waiting
            NSWorkspace.shared.open(device.verificationUri)
            let accessToken = try await flow.pollAccessToken(
                deviceCode: device.deviceCode,
                interval: device.interval,
                expiresAt: device.expiresAt
            )
            _ = try flow.persistAccount(githubAccessToken: accessToken, accountEmail: nil)
            store.refresh()
            phase = .done
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
