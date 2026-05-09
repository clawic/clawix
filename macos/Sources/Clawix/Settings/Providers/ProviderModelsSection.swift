import AIProviders
import SwiftUI

/// Read-only catalog of models the provider exposes. v1 doesn't let
/// the user edit this; the list is curated in code. Capability badges
/// help the user understand what each model is for.
struct ProviderModelsSection: View {
    let provider: ProviderDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Available models")
            SettingsCard {
                ForEach(Array(provider.models.enumerated()), id: \.element.id) { idx, model in
                    if idx > 0 { CardDivider() }
                    ModelRow(model: model)
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: ModelDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(model.id)
                    .font(BodyFont.system(size: 11, wght: 500).monospaced())
                    .foregroundColor(Palette.textSecondary)
                if let context = model.contextWindow {
                    Text("Context window: \(context.formatted()) tokens")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer(minLength: 12)
            FlowCapabilityBadges(capabilities: Array(model.capabilities).sorted { $0.rawValue < $1.rawValue })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct FlowCapabilityBadges: View {
    let capabilities: [Capability]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(capabilities, id: \.rawValue) { cap in
                Text(cap.rawValue)
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
    }
}
