import SwiftUI

/// Per-thing card. The visual canon for IoT devices: squircle
/// background, kind icon, label, area pill, status badge, and an
/// inline control surface (toggle / slider / lock button) when the
/// thing's primary capability supports it. Long-tap or chevron opens
/// the full detail view.
struct ThingCard: View {
    let thing: ThingRecord
    var onTap: () -> Void

    @EnvironmentObject private var manager: IoTManager
    @State private var sliderValue: Double = 0
    @State private var dispatching: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                kindIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: thing.label)
                        .font(BodyFont.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: thing.kind.rawValue.capitalized)
                            .font(BodyFont.system(size: 10))
                            .foregroundColor(Palette.textTertiary)
                        if let areaLabel = manager.areaLabel(forId: thing.areaId) {
                            Text(verbatim: "·")
                                .foregroundColor(Palette.textTertiary)
                            Text(verbatim: areaLabel)
                                .font(BodyFont.system(size: 10))
                                .foregroundColor(Palette.textTertiary)
                        }
                    }
                }
                Spacer()
                riskBadge
            }

            controlSurface
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isOn ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.06),
                            lineWidth: 0.5,
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        .onAppear {
            if let value = primaryNumericCapability?.observedDouble {
                sliderValue = value
            }
        }
    }

    // MARK: - Kind icon

    private var kindSymbol: String {
        switch thing.kind {
        case .light: return "lightbulb"
        case .switchKind: return "switch.2"
        case .climate: return "thermometer.medium"
        case .cover: return "rectangle.split.1x2"
        case .lock: return "lock"
        case .sensor: return "sensor"
        case .camera: return "video"
        case .media: return "play.rectangle"
        case .vacuum: return "wind"
        case .appliance: return "oven"
        case .presence: return "person.fill"
        case .energy: return "bolt"
        }
    }

    @ViewBuilder
    private var kindIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.20) : Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
            Image(systemName: kindSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isOn ? Color.accentColor : Palette.textSecondary)
        }
    }

    // MARK: - Risk badge

    @ViewBuilder
    private var riskBadge: some View {
        let (label, color): (String, Color) = {
            switch thing.risk {
            case .safe: return ("safe", Color.green.opacity(0.55))
            case .caution: return ("caution", Color.orange.opacity(0.65))
            case .restricted: return ("restricted", Color.red.opacity(0.65))
            }
        }()
        Text(verbatim: label)
            .font(BodyFont.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    // MARK: - Control surface

    @ViewBuilder
    private var controlSurface: some View {
        if let power = powerCapability {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { power.observedBool ?? false },
                    set: { newValue in dispatch(action: newValue ? "on" : "off", capability: "power", value: newValue) },
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.accentColor)

                if let brightness = brightnessCapability {
                    Slider(
                        value: $sliderValue,
                        in: 0...100,
                        onEditingChanged: { editing in
                            if !editing {
                                dispatch(action: "set", capability: brightness.key, value: Int(sliderValue))
                            }
                        },
                    )
                    .controlSize(.small)
                    .tint(Color.accentColor)
                }
                Spacer()
                if dispatching {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(Palette.textTertiary)
                }
            }
        } else if thing.kind == .lock {
            HStack {
                Button {
                    let locked = lockCapability?.observedString == "locked"
                    dispatch(action: locked ? "unlock" : "lock", capability: "lock_state", value: locked ? "unlocked" : "locked")
                } label: {
                    Text(verbatim: lockCapability?.observedString == "locked" ? "Unlock" : "Lock")
                        .font(BodyFont.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        } else if thing.kind == .sensor {
            Text(verbatim: primaryNumericCapability?.observedDouble.map { "\($0)" } ?? "—")
                .font(BodyFont.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
        } else {
            EmptyView()
        }
    }

    // MARK: - Capability helpers

    private var powerCapability: CapabilityRecord? {
        thing.capabilities.first(where: { $0.key == "power" || $0.key == "on" })
    }

    private var brightnessCapability: CapabilityRecord? {
        thing.capabilities.first(where: { $0.key == "brightness" })
    }

    private var lockCapability: CapabilityRecord? {
        thing.capabilities.first(where: { $0.key == "lock_state" || $0.key == "locked" })
    }

    private var primaryNumericCapability: CapabilityRecord? {
        thing.capabilities.first(where: { $0.observedDouble != nil })
    }

    private var isOn: Bool {
        powerCapability?.observedBool ?? false
    }

    // MARK: - Dispatch

    private func dispatch(action: String, capability: String, value: Any?) {
        let request = IoTActionRequest(
            homeId: nil,
            selector: nil,
            area: nil,
            family: nil,
            capability: capability,
            action: action,
            value: value.map { ToolJSONValue($0) },
            targets: [thing.id],
        )
        dispatching = true
        Task {
            defer { dispatching = false }
            _ = try? await manager.runAction(request)
        }
    }
}
