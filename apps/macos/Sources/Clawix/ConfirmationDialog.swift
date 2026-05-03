import SwiftUI

// Reusable confirmation dialog. Mirrors the chrome of `ChatRenameSheet`
// (sheetStandardBackground, sheet button styles) for visual consistency
// with the rest of the modal stack.
//
// Triggered through `AppState.requestConfirmation(...)`. The caller
// provides title, body, primary button label, plus an `onConfirm`
// closure executed when the user accepts. Dismiss-on-cancel is the
// default; the request is cleared on either choice.
//
// Use this for any action that:
//   1. writes to files outside our app's sandbox (Codex's global state);
//   2. or is irreversible on our side (DB resets / mass deletes).
//
// Both title and body are LocalizedStringKey so SwiftUI looks them up
// in Localizable.strings automatically.

struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let body: LocalizedStringKey
    /// Localized confirm button label. Defaults to "Continue".
    let confirmLabel: LocalizedStringKey
    /// True for red destructive treatment, false for the standard primary.
    let isDestructive: Bool
    let onConfirm: () -> Void

    init(title: LocalizedStringKey,
         body: LocalizedStringKey,
         confirmLabel: LocalizedStringKey = "Continue",
         isDestructive: Bool = false,
         onConfirm: @escaping () -> Void) {
        self.title = title
        self.body = body
        self.confirmLabel = confirmLabel
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
    }
}

struct ConfirmationDialog: View {
    let request: ConfirmationRequest
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(request.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Text(request.body)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.78))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(SheetCancelButtonStyle())
                if request.isDestructive {
                    Button(action: confirm) { Text(request.confirmLabel) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(SheetDestructiveButtonStyle())
                } else {
                    Button(action: confirm) { Text(request.confirmLabel) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(SheetPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 480)
        .sheetStandardBackground()
    }

    private func confirm() {
        request.onConfirm()
        onClose()
    }
}
