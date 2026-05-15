import SwiftUI

// Shared building blocks used by Settings, Voice to Text, Secrets and any
// future feature page. One source of truth for the page header,
// section labels, cards, dividers, label/toggle/dropdown rows, info
// banners and the small chip/circle/filter buttons that live in
// feature chrome (Secrets header, Audit filter strip).

// MARK: - PageHeader

struct PageHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.bottom, 26)
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(BodyFont.system(size: 13, wght: 600))
            .foregroundColor(Palette.textPrimary)
            .padding(.leading, 3)
            .padding(.bottom, 14)
            .padding(.top, 28)
    }
}

// MARK: - SettingsCard

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .liftWhenSettingsDropdownOpen()
    }
}

// MARK: - CardDivider

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

// MARK: - RowLabel

struct RowLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
            if let detail {
                Text(detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - ToggleRow

struct ToggleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            PillToggle(isOn: $isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - DropdownRow

struct DropdownRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let options: [(T, String)]
    @Binding var selection: T
    var iconForOption: ((T) -> AnyView?)? = nil
    var descriptionForOption: ((T) -> String?)? = nil
    var minWidth: CGFloat = 160

    var body: some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            SettingsDropdown(
                options: options,
                selection: $selection,
                iconForOption: iconForOption,
                descriptionForOption: descriptionForOption,
                minWidth: minWidth
            )
        }
        .liftWhenSettingsDropdownOpen()
    }
}

// MARK: - InfoBanner

/// Filled banner for transient or persistent feedback inside a settings
/// or feature page. `.ok` for success (green), `.error` for failures
/// (red), `.danger` for persistent caution states like "this secret is
/// flagged as compromised" (orange).
struct InfoBanner: View {
    enum Kind {
        case ok
        case error
        case danger
    }

    let text: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            LucideIcon.auto(iconName, size: 13)
                .foregroundColor(.white)
            Text(text)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
        )
    }

    private var iconName: String {
        switch kind {
        case .ok:     return "checkmark.circle.fill"
        case .error:  return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.shield.fill"
        }
    }

    private var fill: Color {
        switch kind {
        case .ok:     return Color.green.opacity(0.65)
        case .error:  return Color.red.opacity(0.7)
        case .danger: return Color.orange.opacity(0.7)
        }
    }
}

// MARK: - IconChipButton

/// Compact tool button used inside feature chrome (Secrets header,
/// Audit header). Fixed 28pt height capsule with optional label, dark
/// fill that bumps on hover, hairline stroke matching the canonical
/// dropdown trigger. `isPrimary` raises the resting fill so the CTA
/// reads above the cluster.
struct IconChipButton: View {
    let symbol: String
    var label: LocalizedStringKey? = nil
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let isLocked = Self.lockSymbolState(symbol) {
                    SecretsIcon(size: 13, lineWidth: 1.15,
                                color: Palette.textPrimary,
                                isLocked: isLocked)
                } else {
                    IconImage(symbol, size: 11)
                        .foregroundColor(Palette.textPrimary)
                }
                if let label {
                    Text(label)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
            }
            .padding(.horizontal, label == nil ? 9 : 11)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var fill: Color {
        let base: CGFloat = isPrimary ? 0.165 : 0.135
        let value = base + (hovered ? 0.03 : 0)
        return Color(white: value)
    }

    /// Routes lock-shaped SF Symbol names to the project's custom
    /// `SecretsIcon`, so any chip that asks for a padlock renders the
    /// same glyph used elsewhere in the Secrets feature.
    private static func lockSymbolState(_ symbol: String) -> Bool? {
        switch symbol {
        case "lock", "lock.fill", "lock.shield": return true
        case "lock.open", "lock.open.fill":      return false
        default:                                 return nil
        }
    }
}

// MARK: - IconCircleButton

/// Tiny inline action button (eye / copy / xmark) used inside field
/// rows and sheet headers. 24×24, 6pt radius, near-invisible at rest,
/// gets a soft white tint on hover.
struct IconCircleButton: View {
    let symbol: String
    var size: CGFloat = 24
    var symbolSize: CGFloat = 11
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(symbol, size: 11)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.10 : 0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - FilterChip

/// Horizontal filter chip used in scrollable strips that don't fit
/// `SlidingSegmented` (eg. the Audit log with 11 event kinds). 26pt
/// height, soft active state matching the canonical segmented track.
struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(active ? Palette.textPrimary : Palette.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(active ? Color.white.opacity(0.10) : .clear, lineWidth: 0.5)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var fill: Color {
        if active {
            return Color(white: 0.20 + (hovered ? 0.02 : 0))
        }
        return Color(white: 0.135 + (hovered ? 0.03 : 0))
    }
}
