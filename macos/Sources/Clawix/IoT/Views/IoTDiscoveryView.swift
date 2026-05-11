import SwiftUI

/// Discovery / add-device tab. Hosts the wizard:
///   1. User taps "Scan"; we call `iot.discovery.start` and the SSE
///      feed (`IoTDiscoveryFeed`) starts streaming `iot.discovery.found`
///      envelopes.
///   2. Discovered devices land in the card grid below. Each card
///      shows a "Add" button that registers the device with the
///      adapter the daemon suggested.
///   3. A manual-add form sits in a disclosure group for advanced
///      users (custom connectors, generic-http endpoints, etc.).
struct IoTDiscoveryView: View {
    @EnvironmentObject private var manager: IoTManager
    @StateObject private var feed = IoTDiscoveryFeed()

    @State private var scanning = false
    @State private var addingFingerprint: String?
    @State private var errorMessage: String?
    @State private var manualFormOpen = false

    @State private var manualLabel: String = ""
    @State private var manualKind: IoTThingKind = .switchKind
    @State private var manualConnectorId: String = "mock-simulator"
    @State private var manualTargetRef: String = ""

    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    if feed.devices.isEmpty {
                        emptyHint
                    } else {
                        ForEach(feed.devices) { device in
                            DiscoveryCard(
                                device: device,
                                isAdding: addingFingerprint == device.fingerprint,
                                onAdd: { Task { await add(device) } },
                            )
                        }
                    }

                    DisclosureGroup(isExpanded: $manualFormOpen) {
                        manualForm
                            .padding(.top, 8)
                    } label: {
                        Text(verbatim: "Add manually")
                            .font(BodyFont.system(size: 12, weight: .medium))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(.top, 12)

                    IoTProtocolPaths()
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .thinScrollers()
        }
        .onAppear {
            feed.connect()
        }
        .onDisappear {
            feed.disconnect()
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleScan() }
            } label: {
                HStack(spacing: 6) {
                    if scanning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(Palette.textPrimary)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11))
                    }
                    Text(verbatim: scanning ? "Stop scan" : "Scan local network")
                        .font(BodyFont.system(size: 12, weight: .medium))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            if feed.isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(verbatim: "Listening (\(feed.devices.count) found)")
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            Spacer()
            Button {
                feed.reset()
            } label: {
                Text(verbatim: "Clear")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(Palette.textTertiary)
            Text(verbatim: "No devices yet")
                .font(BodyFont.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: "Tap Scan to look for devices on your network, or expand the manual-add form below.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            formRow(label: "Label", binding: $manualLabel, placeholder: "Bedside lamp")
            HStack(spacing: 8) {
                Text(verbatim: "Kind")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $manualKind) {
                    ForEach(IoTThingKind.allCases, id: \.self) { kind in
                        Text(verbatim: kind.rawValue.capitalized).tag(kind)
                    }
                }
                .labelsHidden()
                Spacer()
            }
            formRow(label: "Connector", binding: $manualConnectorId, placeholder: "mock-simulator")
            formRow(label: "Target ref", binding: $manualTargetRef, placeholder: "sim://light/2")
            HStack {
                Spacer()
                Button {
                    Task { await addManual() }
                } label: {
                    Text(verbatim: "Add device")
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
                .disabled(manualLabel.isEmpty || manualTargetRef.isEmpty)
            }
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

    private func toggleScan() async {
        if scanning {
            try? await manager.stopDiscovery()
            scanning = false
        } else {
            feed.reset()
            scanning = true
            do {
                try await manager.startDiscovery(timeoutMs: 8000)
            } catch {
                errorMessage = error.localizedDescription
                scanning = false
            }
            // Auto-clear scanning flag after the daemon's timeout window.
            Task {
                try? await Task.sleep(nanoseconds: 9_000_000_000)
                scanning = false
            }
        }
    }

    private func add(_ device: DiscoveredDevice) async {
        addingFingerprint = device.fingerprint
        defer { addingFingerprint = nil }
        do {
            var input = IoTClient.AddThingInput()
            input.fingerprint = device.fingerprint
            _ = try await manager.addThing(input: input)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addManual() async {
        do {
            var input = IoTClient.AddThingInput()
            input.label = manualLabel
            input.kind = manualKind
            input.connectorId = manualConnectorId
            input.targetRef = manualTargetRef
            _ = try await manager.addThing(input: input)
            manualLabel = ""
            manualTargetRef = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DiscoveryCard: View {
    let device: DiscoveredDevice
    let isAdding: Bool
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundColor(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.label)
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: "\(device.kind) · \(device.connectorId) · \(device.targetRef)")
                    .font(BodyFont.system(size: 10))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: 4) {
                    if isAdding {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(Palette.textPrimary)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                    }
                    Text(verbatim: "Add")
                }
                .font(BodyFont.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.40))
                )
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
