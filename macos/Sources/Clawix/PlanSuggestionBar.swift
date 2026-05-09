import SwiftUI

/// Pill that floats above the composer when the user has typed the
/// word "plan" in their draft and plan mode is currently OFF. Offers a
/// one-click shortcut to turn plan mode on (or `Shift + Tab` from the
/// keyboard) and an X to dismiss the hint for the current draft.
struct PlanSuggestionBar: View {
    let onUsePlanMode: () -> Void
    let onDismiss: () -> Void

    @State private var hoverUse = false
    @State private var hoverDismiss = false

    var body: some View {
        HStack(spacing: 10) {
            LucideIcon(.listChecks, size: 13)
                .foregroundColor(Color(white: 0.88))

            Text(L10n.t("Create a plan"))
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.92))

            shortcutPill

            Spacer(minLength: 4)

            usePlanModeButton

            dismissButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.13))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    private var shortcutPill: some View {
        HStack(spacing: 0) {
            Text(verbatim: "Shift + Tab")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Color(white: 0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var usePlanModeButton: some View {
        Button(action: onUsePlanMode) {
            Text(L10n.t("Use plan mode"))
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.94))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(hoverUse ? 0.13 : 0.08))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoverUse = $0 }
        .animation(.easeOut(duration: 0.12), value: hoverUse)
        .accessibilityLabel(L10n.t("Use plan mode"))
        .hoverHint(L10n.t("Use plan mode"))
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            LucideIcon(.x, size: 11)
                .foregroundColor(Color.white.opacity(hoverDismiss ? 0.9 : 0.55))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverDismiss = $0 }
        .animation(.easeOut(duration: 0.12), value: hoverDismiss)
        .accessibilityLabel(L10n.t("Dismiss plan suggestion"))
    }
}
