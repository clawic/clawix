import SwiftUI

/// Thin compatibility wrappers around the canonical primitives in
/// SettingsKit + SheetChrome. Existing Secrets surfaces still call
/// `VaultCard` / `VaultPrimaryButton` / etc, but the visuals now come
/// from the shared design system. As each surface gets its phase-2..6
/// rewrite, calls migrate to the canonical primitives directly. Once
/// the migration is complete the file is reduced to just `VaultUI`.
enum VaultUI {

    /// Centered panel for vault chrome (lock screen, onboarding,
    /// recovery). Constrains width so it reads like a card on a wide
    /// content panel instead of stretching across the whole screen.
    static func centered<Content: View>(_ width: CGFloat = 420, @ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
                .frame(width: width)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VaultCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct VaultPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.black)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SheetPrimaryButtonStyle(enabled: isEnabled && !isLoading))
        .disabled(!isEnabled || isLoading)
    }
}

struct VaultSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SheetCancelButtonStyle())
    }
}

struct VaultPasswordField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        SecureField(placeholder, text: $text, onCommit: onSubmit)
            .sheetTextFieldStyle()
    }
}

struct VaultErrorLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11.5, wght: 500))
            .foregroundColor(Color.red.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
