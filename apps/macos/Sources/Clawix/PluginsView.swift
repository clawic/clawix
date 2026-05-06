import SwiftUI

struct PluginsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("Plugins")

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach($appState.plugins) { $plugin in
                        PluginRow(plugin: $plugin)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct PluginRow: View {
    @Binding var plugin: Plugin

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: plugin.iconName)
                .font(BodyFont.system(size: 16))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cardFill)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                    .font(BodyFont.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(plugin.description)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textTertiary)
            }

            Spacer()

            PillToggle(isOn: $plugin.isEnabled)
                .accessibilityLabel(L10n.a11yPluginToggle(name: plugin.name, isOn: plugin.isEnabled))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plugin.name)
    }

}
