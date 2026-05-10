import SwiftUI
import ClawixCore

struct HostEditorSheet: View {
    @ObservedObject var store: MeshStore
    let onClose: () -> Void

    @State private var mode: Mode = .pairMac
    @State private var pairingHost: String = ""
    @State private var pairingPort: String = "7779"
    @State private var pairingToken: String = ""
    @State private var pairingProfile: PeerPermissionProfile = .scoped
    @State private var pairingInFlight = false
    @State private var pairingError: String? = nil
    @State private var pairingSuccessName: String? = nil

    enum Mode: String, CaseIterable, Equatable, Hashable {
        case pairMac
        case sshServer

        var label: String {
            switch self {
            case .pairMac:    return "Pair a Mac"
            case .sshServer:  return "Add SSH server"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)

            modePicker
                .padding(.horizontal, 22)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch mode {
                    case .pairMac:    pairMacBody
                    case .sshServer:  sshServerBody
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
            .thinScrollers()
            .frame(maxHeight: 480)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .frame(width: 520)
        .sheetStandardBackground()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a host")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Register another machine so this Mac can run jobs on it.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
        }
    }

    private var modePicker: some View {
        SlidingSegmented(
            selection: $mode,
            options: [
                (.pairMac, Mode.pairMac.label),
                (.sshServer, Mode.sshServer.label)
            ]
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mode bodies

    @ViewBuilder
    private var pairMacBody: some View {
        EditorCard {
            EditorFieldLabel("Host")
            EditorTextField(placeholder: "192.168.1.20 or my-mac.local", text: $pairingHost)
        }
        EditorCard {
            EditorFieldLabel("HTTP port")
            EditorTextField(placeholder: "7779", text: $pairingPort)
        }
        EditorCard {
            EditorFieldLabel("Pairing token")
            EditorTextField(placeholder: "Token from the other Mac", text: $pairingToken, secure: true)
        }
        EditorCard {
            EditorFieldLabel("Trust profile")
            SlidingSegmented(
                selection: $pairingProfile,
                options: [
                    (.scoped, "Scoped"),
                    (.fullTrust, "Full trust"),
                    (.askPerTask, "Ask")
                ]
            )
        }
        if let name = pairingSuccessName {
            InfoBanner(text: "Linked with \(name)", kind: .ok)
        }
        if let error = pairingError {
            InfoBanner(text: error, kind: .error)
        }
    }

    @ViewBuilder
    private var sshServerBody: some View {
        EditorCard {
            EditorFieldLabel("Coming soon")
            Text("SSH host registration will become available when this Mac can store host credentials through the background bridge.")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        EditorCard {
            EditorFieldLabel("What it will accept")
            VStack(alignment: .leading, spacing: 6) {
                fieldRow("Display name", "e.g. Hetzner VPS")
                fieldRow("Host / IP", "vps.example.com")
                fieldRow("SSH user", "ubuntu / root / deploy")
                fieldRow("Auth", "Private key, password or agent")
                fieldRow("Permission profile", "Scoped / Full trust / Ask per task")
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SheetCancelButtonStyle())
            Button(action: { Task { await commit() } }) {
                HStack(spacing: 6) {
                    if pairingInFlight {
                        ProgressView().controlSize(.small)
                    }
                    Text(commitLabel)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCommit)
            .buttonStyle(SheetPrimaryButtonStyle(enabled: canCommit))
        }
    }

    private var commitLabel: String {
        switch mode {
        case .pairMac:    return pairingInFlight ? "Linking…" : "Link Mac"
        case .sshServer:  return "Add server"
        }
    }

    private var canCommit: Bool {
        switch mode {
        case .sshServer:
            return false
        case .pairMac:
            return !pairingInFlight
                && !pairingHost.trimmingCharacters(in: .whitespaces).isEmpty
                && Int(pairingPort) != nil
                && !pairingToken.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func commit() async {
        switch mode {
        case .sshServer:
            return
        case .pairMac:
            pairingInFlight = true
            pairingError = nil
            pairingSuccessName = nil
            defer { pairingInFlight = false }
            let host = pairingHost.trimmingCharacters(in: .whitespaces)
            let token = pairingToken.trimmingCharacters(in: .whitespaces)
            let port = Int(pairingPort) ?? 7779
            await store.pair(host: host, httpPort: port, token: token, profile: pairingProfile)
            if case .success(let name) = store.lastPairingResult {
                pairingSuccessName = name
                pairingHost = ""
                pairingToken = ""
                try? await Task.sleep(nanoseconds: 600_000_000)
                onClose()
            } else if case .failure(let message) = store.lastPairingResult {
                pairingError = message
            }
        }
    }
}

// MARK: - Editor primitives

private struct EditorCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

private struct EditorFieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 13, wght: 600))
            .foregroundColor(Palette.textPrimary)
    }
}

private struct EditorTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(BodyFont.system(size: 13, wght: 500))
        .foregroundColor(Palette.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
