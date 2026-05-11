import SwiftUI

struct AlertsTabView: View {
    @ObservedObject var manager: IndexManager

    private var pending: [ClawJSIndexClient.Alert] {
        manager.alerts.filter { $0.ackAt == nil }
    }
    private var acked: [ClawJSIndexClient.Alert] {
        manager.alerts.filter { $0.ackAt != nil }
    }

    var body: some View {
        Group {
            if manager.alerts.isEmpty {
                ContentUnavailableView(
                    "No alerts yet",
                    systemImage: "bell.slash",
                    description: Text("Monitors with alert rules will push here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !pending.isEmpty {
                            SectionTitle(text: "Pending (\(pending.count))")
                            ForEach(pending) { alert in
                                AlertRow(alert: alert, entity: entityFor(alert)) {
                                    Task { await manager.ackAlert(id: alert.id) }
                                }
                            }
                        }
                        if !acked.isEmpty {
                            SectionTitle(text: "Acknowledged")
                            ForEach(acked) { alert in
                                AlertRow(alert: alert, entity: entityFor(alert), onAck: nil)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .thinScrollers()
            }
        }
    }

    private func entityFor(_ alert: ClawJSIndexClient.Alert) -> ClawJSIndexClient.Entity? {
        guard let id = alert.entityId else { return nil }
        return manager.entities.first { $0.id == id }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(BodyFont.system(size: 10.5, wght: 700))
            .kerning(0.5)
            .foregroundColor(.white.opacity(0.50))
            .padding(.top, 6)
    }
}

private struct AlertRow: View {
    let alert: ClawJSIndexClient.Alert
    let entity: ClawJSIndexClient.Entity?
    let onAck: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon.auto(iconName, size: 14)
                .foregroundColor(.orange)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.orange.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(.white.opacity(0.92))
                if let summary {
                    Text(summary)
                        .font(BodyFont.system(size: 11.5, wght: 400))
                        .foregroundColor(.white.opacity(0.60))
                }
                if let entity {
                    Text(entity.title ?? entity.identityKey)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }
                Text(alert.ts.prefix(19))
                    .font(BodyFont.system(size: 10.5, wght: 400))
                    .foregroundColor(.white.opacity(0.40))
            }
            Spacer()
            if let onAck {
                Button(action: onAck) {
                    Text("Ack")
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(alert.ackAt == nil ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
        )
    }

    private var headline: String {
        switch alert.ruleKind {
        case "field_decrease":
            let field = alert.payload["field"]?.asString ?? "value"
            let pct = alert.payload["deltaPct"]?.asNumber ?? 0
            return "\(field.capitalized) dropped \(Int(pct))%"
        case "field_increase":
            let field = alert.payload["field"]?.asString ?? "value"
            let pct = alert.payload["deltaPct"]?.asNumber ?? 0
            return "\(field.capitalized) rose \(Int(pct))%"
        case "new_entity":
            return "New entity captured"
        case "rating_drop":
            return "Rating dropped"
        case "field_match":
            return "\(alert.payload["field"]?.asString ?? "Field") matched"
        case "absence":
            return "\(alert.payload["field"]?.asString ?? "Field") missing"
        default:
            return alert.ruleKind
        }
    }

    private var summary: String? {
        let before = alert.payload["before"]?.asNumber
        let after = alert.payload["after"]?.asNumber
        if let before, let after {
            return "from \(before) to \(after)"
        }
        return nil
    }

    private var iconName: String {
        switch alert.ruleKind {
        case "field_decrease", "rating_drop": return "arrow.down.circle"
        case "field_increase": return "arrow.up.circle"
        case "new_entity": return "plus.circle"
        case "field_match": return "checkmark.circle"
        case "absence": return "questionmark.circle"
        default: return "bell"
        }
    }
}
