import SwiftUI

/// Protocol-specific add paths inside the Discovery / Add device tab.
/// Each row hosts a compact form for one protocol that needs special
/// onboarding beyond the generic discovery feed:
///
///   - Matter: paste the pairing code (printed on the device or
///     decoded from the QR sticker).
///   - HomeKit: start the local HAP bridge and display the setup code
///     the user types into Apple Home.
///   - MQTT: enter broker URL + optional credentials so the daemon
///     opens a connection and surfaces Zigbee2MQTT topics in the feed.
struct IoTProtocolPaths: View {
    @EnvironmentObject private var manager: IoTManager

    @State private var matterPairing: String = ""
    @State private var matterLabel: String = ""
    @State private var matterStatus: String?

    @State private var homekitLabel: String = ""
    @State private var homekitSetupCode: String?
    @State private var homekitStatus: String?

    @State private var mqttUrl: String = "mqtt://"
    @State private var mqttUsername: String = ""
    @State private var mqttPassword: String = ""
    @State private var mqttStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Protocol-specific paths")
                .font(BodyFont.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
            matterCard
            homekitCard
            mqttCard
        }
    }

    @ViewBuilder
    private var matterCard: some View {
        protocolCard(title: "Matter", subtitle: "Paste the device's pairing code or QR-encoded payload.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Pairing", binding: $matterPairing, placeholder: "MT:0000000000")
                formRow(label: "Label", binding: $matterLabel, placeholder: "Bedside Matter lamp (optional)")
                if let matterStatus {
                    Text(verbatim: matterStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(matterStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await commissionMatter() }
                    } label: {
                        Text(verbatim: "Commission")
                            .font(BodyFont.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.40))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(matterPairing.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var homekitCard: some View {
        protocolCard(title: "Apple HomeKit", subtitle: "Advertise Clawix as a HomeKit bridge; pair from the Home app on iOS / macOS.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Label", binding: $homekitLabel, placeholder: "Clawix (optional)")
                if let homekitSetupCode {
                    HStack {
                        Text(verbatim: "Setup code")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textTertiary)
                            .frame(width: 80, alignment: .leading)
                        Text(verbatim: homekitSetupCode)
                            .font(BodyFont.system(size: 14, weight: .semibold).monospaced())
                            .foregroundColor(Palette.textPrimary)
                        Spacer()
                    }
                }
                if let homekitStatus {
                    Text(verbatim: homekitStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(homekitStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await startBridge() }
                    } label: {
                        Text(verbatim: "Start bridge")
                            .font(BodyFont.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.40))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var mqttCard: some View {
        protocolCard(title: "MQTT / Zigbee2MQTT", subtitle: "Connect to your broker; Zigbee2MQTT devices appear in the discovery feed.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Broker URL", binding: $mqttUrl, placeholder: "mqtt://192.168.1.50:1883")
                formRow(label: "Username", binding: $mqttUsername, placeholder: "(optional)")
                secureRow(label: "Password", binding: $mqttPassword, placeholder: "(optional)")
                if let mqttStatus {
                    Text(verbatim: mqttStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(mqttStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await disconnectMqtt() }
                    } label: {
                        Text(verbatim: "Disconnect")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await connectMqtt() }
                    } label: {
                        Text(verbatim: "Connect")
                            .font(BodyFont.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.40))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(mqttUrl.isEmpty || mqttUrl == "mqtt://")
                }
            }
        }
    }

    @ViewBuilder
    private func protocolCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: subtitle)
                    .font(BodyFont.system(size: 10))
                    .foregroundColor(Palette.textTertiary)
            }
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func formRow(label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
        }
    }

    @ViewBuilder
    private func secureRow(label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 80, alignment: .leading)
            SecureField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
        }
    }

    // MARK: - Actions

    private func commissionMatter() async {
        do {
            let response = try await manager.commissionMatter(
                pairingCode: matterPairing,
                label: matterLabel.isEmpty ? nil : matterLabel,
            )
            if let error = response["error"] as? String {
                matterStatus = "Error: \(error)"
            } else if let nodeId = response["nodeId"] as? String {
                matterStatus = "Paired as node \(nodeId)."
                matterPairing = ""
                matterLabel = ""
            } else {
                matterStatus = "Commissioned."
            }
        } catch {
            matterStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func startBridge() async {
        do {
            let response = try await manager.startHomeKitBridge(label: homekitLabel.isEmpty ? nil : homekitLabel)
            if let error = response["error"] as? String {
                homekitStatus = "Error: \(error)"
            } else if let code = response["setupCode"] as? String {
                homekitSetupCode = code
                let advertising = (response["advertising"] as? Bool) ?? false
                homekitStatus = advertising ? "Bridge advertising on the local network." : "Setup code ready. Open the Home app and tap Add Accessory."
            }
        } catch {
            homekitStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func connectMqtt() async {
        do {
            let response = try await manager.connectMqtt(
                url: mqttUrl,
                username: mqttUsername.isEmpty ? nil : mqttUsername,
                password: mqttPassword.isEmpty ? nil : mqttPassword,
            )
            if (response["connected"] as? Bool) == true {
                mqttStatus = "Connected. Zigbee2MQTT devices will appear in the feed."
            } else if let reason = response["reason"] as? String {
                mqttStatus = "Error: \(reason)"
            } else {
                mqttStatus = "Connect attempt sent."
            }
        } catch {
            mqttStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func disconnectMqtt() async {
        do {
            try await manager.disconnectMqtt()
            mqttStatus = "Disconnected."
        } catch {
            mqttStatus = "Error: \(error.localizedDescription)"
        }
    }
}
