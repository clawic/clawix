import SwiftUI
import UniformTypeIdentifiers

struct SettingsBottomButton: View {
    @Binding var open: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 11) {
                SettingsIcon(size: 16)
                    .frame(width: 15)
                    .foregroundColor(open ? .white : Color(white: hovered ? 0.92 : 0.78))
                Text("Settings")
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(open ? .white : Color(white: 0.92))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel("Settings")
        .accessibilityAddTraits(open ? .isSelected : [])
    }

    private var backgroundFill: Color {
        // Sidebar tabs (open/selected and hover) use white-opacity so the
        // full-row glow stays soft; the wallpaper-tint side effect is
        // accepted here because the user prefers the look to a stable
        // solid gray.
        if open    { return Color.white.opacity(0.06) }
        if hovered { return Color.white.opacity(0.035) }
        return .clear
    }
}

struct SettingsAccountPopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var isOpen: Bool
    @State private var limitsExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsAccountRow(title: appState.auth.info?.email ?? L10n.t("Connected account"),
                               icon: "person.circle",
                               trailing: nil)
            MenuStandardDivider()
                .padding(.vertical, 4)
            SettingsAccountRow(title: L10n.t("Settings"),
                               icon: "clawix.settings",
                               trailing: nil) {
                appState.currentRoute = .settings
                isOpen = false
            }
            SettingsLimitsSection(expanded: $limitsExpanded)
            SettingsAccountRow(title: L10n.t("Sign out"),
                               icon: "clawix.signout",
                               trailing: nil) {
                isOpen = false
                appState.performBackendLogout()
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 268)
        .menuStandardBackground()
    }
}

struct SettingsLimitsSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var expanded: Bool

    private var windows: [RateLimitWindow] {
        guard let snapshot = appState.rateLimits else { return [] }
        return [snapshot.primary, snapshot.secondary].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsLimitsHeaderRow(expanded: $expanded)
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { entry in
                        SettingsLimitsValueRow(
                            label: SettingsLimitsFormatter.windowLabel(for: entry.element),
                            percent: SettingsLimitsFormatter.percentLabel(for: entry.element),
                            detail: SettingsLimitsFormatter.resetLabel(for: entry.element)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .clipped()
    }
}

struct SettingsLimitsHeaderRow: View {
    @Binding var expanded: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.22)) {
                expanded.toggle()
            }
        }) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                UsageIcon(size: 15, lineWidth: 1.7)
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(MenuStyle.rowIcon)
                Text("Remaining usage limits")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                LucideIcon(.chevronDown, size: 11)
                    .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                    .foregroundColor(MenuStyle.rowSubtle)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

enum SettingsLimitsFormatter {
    static func windowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else { return "" }
        if mins == 10080 {
            return String(localized: "Weekly", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            return "\(mins / 60)h"
        }
        return "\(mins)min"
    }

    static func percentLabel(for window: RateLimitWindow) -> String {
        "\(window.usedPercent)%"
    }

    static func resetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        }
        return formatter.string(from: date)
    }

    /// Long-form variant used by the Settings → Usage page.
    static func detailedWindowLabel(for window: RateLimitWindow) -> String {
        guard let mins = window.windowDurationMins, mins > 0 else {
            return String(localized: "Usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 10080 {
            return String(localized: "Weekly usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins == 1440 {
            return String(localized: "Daily usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        if mins % 60 == 0 {
            let template = String(localized: "%lld-hour usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, locale: AppLocale.current, Int(mins / 60))
        }
        let template = String(localized: "%lld-minute usage limit", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, locale: AppLocale.current, Int(mins))
    }

    /// Long-form reset label, e.g. "Resets at 18:39" / "Resets on 5 mayo".
    static func detailedResetLabel(for window: RateLimitWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        if Calendar.current.isDateInToday(date) {
            // Force 24h "HH:mm" regardless of locale's AM/PM convention.
            formatter.dateFormat = "HH:mm"
            let template = String(localized: "Resets at %@", bundle: AppLocale.bundle, locale: AppLocale.current)
            return String(format: template, formatter.string(from: date))
        }
        // Full month name (MMMM) so Spanish reads "5 mayo" instead of "5 may.".
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let template = String(localized: "Resets on %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, formatter.string(from: date))
    }

    static func perModelSectionTitle(name: String) -> String {
        let template = String(localized: "Usage limits for %@", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, name)
    }

    static func creditTitle(for credits: CreditsSnapshot) -> String {
        if credits.unlimited {
            return String(localized: "Unlimited credit", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        let balance = credits.balance ?? "0"
        let template = String(localized: "%@ credit remaining", bundle: AppLocale.bundle, locale: AppLocale.current)
        return String(format: template, balance)
    }
}

struct SettingsLimitsValueRow: View {
    let label: String
    let percent: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(BodyFont.system(size: 12, weight: .medium))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            Text(verbatim: percent)
                .font(BodyFont.system(size: 12))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: detail)
                .font(BodyFont.system(size: 12))
                .foregroundColor(MenuStyle.rowSubtle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
        .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
        .padding(.vertical, MenuStyle.rowVerticalPadding)
    }
}

struct SettingsAccountRow: View {
    let title: String
    let icon: String
    let trailing: String?
    var action: (() -> Void)? = nil

    @State private var hovered = false

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if icon == "clawix.settings" {
                        SettingsIcon(size: 16)
                    } else if icon == "clawix.signout" {
                        SignOutIcon(size: 16)
                            .offset(x: 1)
                    } else {
                        LucideIcon.auto(icon, size: 14)
                    }
                }
                .frame(width: 18, alignment: .center)
                .foregroundColor(MenuStyle.rowIcon)
                Text(title)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
                if let trailingIcon = trailing {
                    LucideIcon.auto(trailingIcon, size: 11)
                        .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing != nil ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .disabled(action == nil)
    }
}
