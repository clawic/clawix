import SwiftUI

struct ContactCreateModal: View {
    @ObservedObject var manager: ContactsManager
    @State private var draft: Contact
    let onClose: () -> Void

    init(manager: ContactsManager, onClose: @escaping () -> Void) {
        self.manager = manager
        self.onClose = onClose
        _draft = State(initialValue: manager.newContactDraft())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Contact")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ContactsTokens.Ink.primary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    LucideIcon(.x, size: 12)
                        .foregroundColor(ContactsTokens.Ink.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
            }

            ContactEditView(
                manager: manager,
                draft: draft,
                isNew: true,
                onCancel: onClose,
                onSave: { saved in
                    Task {
                        await manager.commit(saved)
                        onClose()
                    }
                }
            )
        }
        .frame(width: 560, height: 580)
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.sheet, style: .continuous)
                .fill(ContactsTokens.Surface.detail)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.sheet, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
