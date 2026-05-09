import SwiftUI

/// Sidebar entry for the Secrets vault. Visually matches the top-level
/// `SidebarButton` rows (`New chat`, `Search`) so the row height,
/// padding, font, hover/selected colors and corner radius are identical
/// across the whole sidebar nav.
struct SecretsToolRow: View {
    @EnvironmentObject private var vault: VaultManager
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                SecretsIcon(
                    size: 13.8,
                    lineWidth: 1.28,
                    color: iconColor,
                    isLocked: vault.state == .locked || vault.state == .unlocking
                )
                .frame(width: 15, height: 15)
                Text("Secrets")
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel("Secrets")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id("Secrets-\(isSelected)")
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.92)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}
