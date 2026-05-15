import SwiftUI

/// Full-page detail for one IoT device. Reached from a card tap on
/// `IoTScreen` (route `SidebarRoute.iotDeviceDetail`). Shows every
/// capability, raw state, the device's connector metadata, and a
/// "Remove" action gated by the approval flow.
struct IoTDeviceDetailView: View {
    let deviceId: String
    @EnvironmentObject private var manager: IoTManager
    @EnvironmentObject private var appState: AppState

    @State private var removing = false
    @State private var errorMessage: String?

    private var device: IoTDeviceRecord? { manager.device(byId: deviceId) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                if let device {
                    content(for: device)
                } else {
                    Text(verbatim: "Device not found.")
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textTertiary)
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
                }
            }
            .thinScrollers()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(for device: IoTDeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Button {
                    appState.currentRoute = .iotHome
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text(verbatim: "Home")
                            .font(BodyFont.system(size: 12))
                    }
                    .foregroundColor(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: device.label)
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: "\(device.kind.rawValue.capitalized) · risk \(device.risk.rawValue) · connector \(device.connectorId)")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }

            DeviceCard(device: device, onTap: {})

            section(title: "Capabilities") {
                VStack(spacing: 6) {
                    if device.capabilities.isEmpty {
                        Text(verbatim: "(none declared)")
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textTertiary)
                    }
                    ForEach(device.capabilities) { capability in
                        capabilityRow(capability)
                    }
                }
            }

            section(title: "Targeting") {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow("ID", device.id)
                    detailRow("Target ref", device.targetRef)
                    detailRow("Aliases", device.aliases.joined(separator: ", "))
                    detailRow("Area", manager.areaLabel(forId: device.areaId) ?? "(unassigned)")
                }
            }

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
            }

            HStack {
                Spacer()
                Button {
                    Task { await remove(device) }
                } label: {
                    HStack(spacing: 4) {
                        if removing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(Palette.textPrimary)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                        }
                        Text(verbatim: "Remove device")
                            .font(BodyFont.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.red.opacity(0.30))
                    )
                }
                .buttonStyle(.plain)
                .disabled(removing)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func capabilityRow(_ capability: CapabilityRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: capability.label ?? capability.key)
                    .font(BodyFont.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: capability.key)
                    .font(BodyFont.system(size: 10))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer()
            Text(verbatim: observedSummary(capability))
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func observedSummary(_ capability: CapabilityRecord) -> String {
        if let bool = capability.observedBool { return bool ? "on" : "off" }
        if let number = capability.observedDouble { return "\(number)\(capability.unit.map { " \($0)" } ?? "")" }
        if let string = capability.observedString { return string }
        return "—"
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(BodyFont.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 88, alignment: .leading)
            Text(verbatim: value.isEmpty ? "—" : value)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textPrimary)
            Spacer()
        }
    }

    private func remove(_ device: IoTDeviceRecord) async {
        removing = true
        defer { removing = false }
        do {
            try await manager.removeDevice(device)
            appState.currentRoute = .iotHome
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
