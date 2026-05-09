import AIProviders
import SwiftUI

struct ProviderListRow: View {
    let provider: ProviderDefinition
    let accountCount: Int
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ProviderBrandIcon(brand: provider.brand, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(provider.tagline)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                ProviderStatusPill(status: status)
                LucideIcon.auto("chevron-right", size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(hovered ? Color.white.opacity(0.025) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var status: ProviderStatusPill.Status {
        if !isEnabled { return .disabled }
        if accountCount == 0 { return .empty }
        return .configured(count: accountCount)
    }
}
