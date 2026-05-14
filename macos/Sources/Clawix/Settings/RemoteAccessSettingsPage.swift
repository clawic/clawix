import AppKit
import SwiftUI
import ClawixEngine

/// Settings → Remote access. Pairs the Mac with a self-hosted relay
/// coordinator so the iPhone (and other Macs) can reach this host
/// from outside the LAN through MeshKit. The user enters a
/// coordinator URL + their email, requests a magic link, and the page
/// guides them through pasting the resulting token. Everything is
/// opt-in: a Mac without a coordinator configured keeps working
/// exactly as before (LAN + Bonjour + Tailscale).
struct RemoteAccessSettingsPage: View {

    @AppStorage(ClawixPersistentSurfaceKeys.remoteCoordinatorUrl) private var coordinatorUrlString: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteEmail) private var email: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteDeviceId) private var savedDeviceId: String = ""
    @AppStorage(ClawixPersistentSurfaceKeys.remoteTenantId) private var savedTenantId: String = ""

    @State private var pasteToken: String = ""
    @State private var status: Status = .idle
    @State private var inFlight: Bool = false

    private enum Status: Equatable {
        case idle
        case info(String)
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    coordinatorSection
                    magicLinkSection
                    pairedDeviceSection
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Remote access")
                .font(.system(size: 18, weight: .semibold))
            Text("Connect this Mac to a self-hosted clawix-relay so the iPhone and other devices can reach you from outside your LAN.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var coordinatorSection: some View {
        sectionCard(title: "Coordinator", subtitle: "Base URL of your relay deployment.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://relay.example.com", text: $coordinatorUrlString)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: coordinatorUrlString) { _, newValue in
                        PairingService.shared.coordinatorURL = URL(string: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                Text("Stored locally. Used by this Mac to register itself and by future pairings to embed the URL in the QR.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var magicLinkSection: some View {
        sectionCard(title: "Magic-link sign-in", subtitle: "Request a sign-in link via email. The coordinator opens the link and copies a token back.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button("Send magic link") {
                        Task { await sendMagicLink() }
                    }
                    .disabled(inFlight || coordinatorUrlString.isEmpty || !email.contains("@"))
                    if inFlight { ProgressView().controlSize(.small) }
                }
                Divider().padding(.vertical, 4)
                Text("Paste the token from the email confirmation:")
                    .font(.system(size: 12))
                TextField("mlk_…", text: $pasteToken)
                    .textFieldStyle(.roundedBorder)
                Button("Register this Mac") {
                    Task { await consumeToken() }
                }
                .disabled(inFlight || pasteToken.isEmpty)
                statusView
            }
        }
    }

    @ViewBuilder
    private var pairedDeviceSection: some View {
        if !savedDeviceId.isEmpty {
            sectionCard(title: "Paired", subtitle: nil) {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Device id") { Text(savedDeviceId).font(.system(size: 11, design: .monospaced)) }
                    LabeledContent("Tenant") { Text(savedTenantId).font(.system(size: 11, design: .monospaced)) }
                    Button("Forget this Mac on the coordinator") {
                        Task { await forget() }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .info(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func currentClient() -> CoordinatorClient? {
        guard let url = URL(string: coordinatorUrlString) else { return nil }
        return CoordinatorClient(baseURL: url)
    }

    private func sendMagicLink() async {
        guard let client = currentClient() else {
            status = .error("Invalid coordinator URL")
            return
        }
        inFlight = true
        defer { inFlight = false }
        do {
            try await client.requestMagicLink(
                email: email,
                deviceLabel: Host.current().localizedName ?? "Mac",
                platform: "macos"
            )
            status = .info("Magic link sent to \(email). Open it on this Mac, then paste the token below.")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func consumeToken() async {
        guard let client = currentClient() else {
            status = .error("Invalid coordinator URL")
            return
        }
        inFlight = true
        defer { inFlight = false }
        do {
            let session = try await client.consumeMagicLink(
                token: pasteToken.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceLabel: Host.current().localizedName ?? "Mac",
                platform: "macos",
                platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                irohNodeID: PairingService.shared.irohNodeID
            )
            savedDeviceId = session.deviceId
            savedTenantId = session.tenantId
            pasteToken = ""
            status = .info("This Mac is registered as \(session.deviceId). Refresh token stashed locally.")
            RelayCredentialStore.storeRefreshToken(session.refreshToken, forDeviceId: session.deviceId)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func forget() async {
        savedDeviceId = ""
        savedTenantId = ""
        status = .info("Local pairing forgotten. Revoke the device from the coordinator's Devices page to fully unpair.")
    }
}

private enum RelayCredentialStore {
    /// Persist the refresh token using the standard defaults suite.
    /// Long-term storage moves into the bridge daemon, which owns the
    /// credential lifecycle for both the GUI and the CLI; this entry
    /// point is intentionally lightweight so the settings page can be
    /// built without pulling in the keychain.
    static func storeRefreshToken(_ token: String, forDeviceId deviceId: String) {
        UserDefaults.standard.set(token, forKey: "clawix.relay.refresh.\(deviceId)")
    }
}
