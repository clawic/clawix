import SwiftUI

struct ContactsScreen: View {

    @StateObject private var manager = ContactsManager()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ContactsToolbar(manager: manager)
                HStack(spacing: 0) {
                    ContactsSubSidebar(manager: manager)
                    contentColumns
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ContactsTokens.Surface.window)
            .task { await manager.bootstrap() }

            if manager.isCreating {
                modalScrim {
                    manager.endCreate()
                }
                ContactCreateModal(manager: manager) {
                    manager.endCreate()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if manager.isMergeOpen {
                modalScrim {
                    manager.isMergeOpen = false
                }
                MergeDuplicatesView(manager: manager) {
                    manager.isMergeOpen = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let id = manager.editingSmartGroupID,
               let group = manager.groupsByID[id] {
                modalScrim {
                    manager.editingSmartGroupID = nil
                }
                SmartGroupConfigView(manager: manager, draft: group) {
                    manager.editingSmartGroupID = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(ContactsTokens.Motion.editToggle, value: manager.isCreating)
        .animation(ContactsTokens.Motion.editToggle, value: manager.isMergeOpen)
        .animation(ContactsTokens.Motion.editToggle, value: manager.editingSmartGroupID)
    }

    @ViewBuilder
    private var contentColumns: some View {
        switch manager.access {
        case .unknown, .requesting:
            centered("Loading contacts…")
        case .denied(let reason):
            centered("Contacts access denied", subtitle: reason)
        case .unavailable:
            centered("Contacts unavailable")
        case .granted:
            HStack(spacing: 0) {
                ContactsList(manager: manager)
                detailColumn
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            if let contact = manager.selectedContact {
                if manager.isEditing {
                    ContactEditView(
                        manager: manager,
                        draft: contact,
                        isNew: false,
                        onCancel: { manager.cancelEdit() },
                        onSave: { saved in
                            Task { await manager.commit(saved) }
                        }
                    )
                    .transition(.opacity)
                    .id("edit-\(contact.id)")
                } else {
                    ContactDetail(manager: manager, contact: contact)
                        .transition(.opacity)
                        .id("read-\(contact.id)")
                }
            } else {
                centered("No Contact Selected",
                         subtitle: manager.contacts.isEmpty
                            ? "Add a new contact to get started."
                            : "Pick a contact from the list to see details.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ContactsTokens.Surface.detail)
            }
        }
        .frame(minWidth: ContactsTokens.Geometry.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        .animation(ContactsTokens.Motion.editToggle, value: manager.isEditing)
        .animation(ContactsTokens.Motion.selection, value: manager.selectedContactID)
    }

    private func centered(_ title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: ContactsTokens.TypeSize.emptyTitle, weight: .medium))
                .foregroundColor(ContactsTokens.Ink.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: ContactsTokens.TypeSize.emptySubtitle))
                    .foregroundColor(ContactsTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modalScrim(onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
            .transition(.opacity)
    }
}
