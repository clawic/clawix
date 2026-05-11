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

    @State private var tuyaAppKey: String = ""
    @State private var tuyaAppSecret: String = ""
    @State private var tuyaBaseUrl: String = ""
    @State private var tuyaStatus: String?

    @State private var googleUrl: String = ""
    @State private var googleClientId: String = ""
    @State private var googleClientSecret: String = ""
    @State private var googleAgentUserId: String = ""
    @State private var googleHomeGraphToken: String = ""
    @State private var googleStatus: String?

    @State private var alexaUrl: String = ""
    @State private var alexaClientSecret: String = ""
    @State private var alexaGatewayToken: String = ""
    @State private var alexaGatewayUrl: String = ""
    @State private var alexaStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Protocol-specific paths")
                .font(BodyFont.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
            matterCard
            homekitCard
            mqttCard
            tuyaCard
            googleCard
            alexaCard
        }
    }

    @ViewBuilder
    private var tuyaCard: some View {
        protocolCard(title: "Tuya / Smart Life", subtitle: "Cloud OpenAPI bridge for Wi-Fi devices sold under Smart Life and many white-label brands.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Client id", binding: $tuyaAppKey, placeholder: "Project Access ID")
                secureRow(label: "Client secret", binding: $tuyaAppSecret, placeholder: "Project Access Secret")
                formRow(label: "Region URL", binding: $tuyaBaseUrl, placeholder: "https://openapi.tuyaeu.com (optional)")
                if let tuyaStatus {
                    Text(verbatim: tuyaStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(tuyaStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await syncTuya() }
                    } label: {
                        Text(verbatim: "Sync devices")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await disconnectTuya() }
                    } label: {
                        Text(verbatim: "Disconnect")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await connectTuya() }
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
                    .disabled(tuyaAppKey.isEmpty || tuyaAppSecret.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var googleCard: some View {
        protocolCard(title: "Google Home", subtitle: "Bridge to Google Assistant + Google Home app via Smart Home Actions. Requires your own public fulfillment URL.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Fulfillment", binding: $googleUrl, placeholder: "https://your-tunnel.example/iot")
                formRow(label: "Client id", binding: $googleClientId, placeholder: "OAuth client id")
                secureRow(label: "Client secret", binding: $googleClientSecret, placeholder: "OAuth client secret")
                formRow(label: "Agent user id", binding: $googleAgentUserId, placeholder: "stable per-user id")
                secureRow(label: "HomeGraph", binding: $googleHomeGraphToken, placeholder: "Service-account token (optional)")
                if let googleStatus {
                    Text(verbatim: googleStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(googleStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await disconnectGoogle() }
                    } label: {
                        Text(verbatim: "Disconnect")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await connectGoogle() }
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
                    .disabled(googleUrl.isEmpty || googleClientId.isEmpty || googleClientSecret.isEmpty || googleAgentUserId.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var alexaCard: some View {
        protocolCard(title: "Amazon Alexa", subtitle: "Bridge to Alexa voice + the Alexa app via Smart Home Skills. Requires your own public fulfillment URL.") {
            VStack(alignment: .leading, spacing: 6) {
                formRow(label: "Fulfillment", binding: $alexaUrl, placeholder: "https://your-tunnel.example/iot")
                secureRow(label: "Client secret", binding: $alexaClientSecret, placeholder: "OAuth client secret")
                secureRow(label: "Gateway token", binding: $alexaGatewayToken, placeholder: "Skill Messaging token (optional)")
                formRow(label: "Gateway URL", binding: $alexaGatewayUrl, placeholder: "https://api.amazonalexa.com/v3/events (optional)")
                if let alexaStatus {
                    Text(verbatim: alexaStatus)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(alexaStatus.hasPrefix("Error") ? .red.opacity(0.8) : Palette.textTertiary)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await disconnectAlexa() }
                    } label: {
                        Text(verbatim: "Disconnect")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await connectAlexa() }
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
                    .disabled(alexaUrl.isEmpty || alexaClientSecret.isEmpty)
                }
            }
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

    private func connectTuya() async {
        do {
            let response = try await manager.connectTuya(
                appKey: tuyaAppKey,
                appSecret: tuyaAppSecret,
                baseUrl: tuyaBaseUrl.isEmpty ? nil : tuyaBaseUrl,
            )
            if (response["connected"] as? Bool) == true {
                tuyaStatus = "Connected. Use Sync devices to import your Tuya fleet."
            } else if let reason = response["reason"] as? String {
                tuyaStatus = "Error: \(reason)"
            } else {
                tuyaStatus = "Connect attempt sent."
            }
        } catch {
            tuyaStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func syncTuya() async {
        do {
            let response = try await manager.syncTuya()
            if let error = response["error"] as? String {
                tuyaStatus = "Error: \(error)"
            } else if let devices = response["devices"] as? [Any] {
                tuyaStatus = "Synced \(devices.count) Tuya device\(devices.count == 1 ? "" : "s")."
            }
        } catch {
            tuyaStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func disconnectTuya() async {
        do {
            try await manager.disconnectTuya()
            tuyaStatus = "Disconnected."
        } catch {
            tuyaStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func connectGoogle() async {
        do {
            let response = try await manager.connectGoogleHome(
                publicFulfillmentUrl: googleUrl,
                oauthClientId: googleClientId,
                oauthClientSecret: googleClientSecret,
                agentUserId: googleAgentUserId,
                homeGraphToken: googleHomeGraphToken.isEmpty ? nil : googleHomeGraphToken,
            )
            if (response["connected"] as? Bool) == true {
                googleStatus = "Connected. Fulfillment endpoint authenticates against the secret."
            } else if let reason = response["reason"] as? String {
                googleStatus = "Error: \(reason)"
            }
        } catch {
            googleStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func disconnectGoogle() async {
        do {
            try await manager.disconnectGoogleHome()
            googleStatus = "Disconnected."
        } catch {
            googleStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func connectAlexa() async {
        do {
            let response = try await manager.connectAlexa(
                publicFulfillmentUrl: alexaUrl,
                oauthClientSecret: alexaClientSecret,
                eventGatewayToken: alexaGatewayToken.isEmpty ? nil : alexaGatewayToken,
                eventGatewayUrl: alexaGatewayUrl.isEmpty ? nil : alexaGatewayUrl,
            )
            if (response["connected"] as? Bool) == true {
                alexaStatus = "Connected. Fulfillment endpoint authenticates against the secret."
            } else if let reason = response["reason"] as? String {
                alexaStatus = "Error: \(reason)"
            }
        } catch {
            alexaStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func disconnectAlexa() async {
        do {
            try await manager.disconnectAlexa()
            alexaStatus = "Disconnected."
        } catch {
            alexaStatus = "Error: \(error.localizedDescription)"
        }
    }
}
