import SwiftUI

struct ContactsList: View {
    @ObservedObject var manager: ContactsManager

    var body: some View {
        VStack(spacing: 0) {
            mergeBar
            if sections.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section(header: header(section.header)) {
                                ForEach(section.contacts) { contact in
                                    ContactRow(
                                        contact: contact,
                                        isSelected: manager.selectedContactID == contact.id,
                                        isMergeCandidate: manager.mergeCandidateIDs.contains(contact.id),
                                        onSelect: {
                                            manager.selectContact(contact.id)
                                        },
                                        onToggleMerge: {
                                            manager.toggleMerge(contact.id)
                                        }
                                    )
                                    .transition(.opacity)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .thinScrollers()
            }
        }
        .frame(width: ContactsTokens.Geometry.listColumnWidth)
        .background(ContactsTokens.Surface.listColumn)
        .overlay(alignment: .trailing) {
            Rectangle().fill(ContactsTokens.Divider.seam).frame(width: 1)
        }
    }

    private var sections: [SectionedContacts] {
        manager.sectionedContacts()
    }

    @ViewBuilder
    private func header(_ title: String?) -> some View {
        if let title {
            HStack {
                Text(title)
                    .font(.system(size: ContactsTokens.TypeSize.listSectionHeader, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(ContactsTokens.Ink.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: ContactsTokens.Geometry.sectionHeaderHeight)
            .background(ContactsTokens.Surface.sectionHeader)
        } else {
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            LucideIcon(.idCard, size: 22)
                .foregroundColor(ContactsTokens.Ink.tertiary)
            Text("No Contacts")
                .font(.system(size: ContactsTokens.TypeSize.emptyTitle, weight: .medium))
                .foregroundColor(ContactsTokens.Ink.secondary)
            if !manager.searchQuery.isEmpty {
                Text("No matches for \"\(manager.searchQuery)\"")
                    .font(.system(size: ContactsTokens.TypeSize.emptySubtitle))
                    .foregroundColor(ContactsTokens.Ink.tertiary)
            }
        }
    }

    @ViewBuilder
    private var mergeBar: some View {
        if manager.mergeCandidateIDs.count >= 2 {
            HStack(spacing: 8) {
                LucideIcon(.listChecks, size: 12)
                    .foregroundColor(ContactsTokens.Accent.primary)
                Text("\(manager.mergeCandidateIDs.count) selected to merge")
                    .font(.system(size: 12))
                    .foregroundColor(ContactsTokens.Ink.primary)
                Spacer()
                Button("Clear") {
                    manager.mergeCandidateIDs.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundColor(ContactsTokens.Ink.secondary)
                .font(.system(size: 12))
                Button("Merge") {
                    manager.isMergeOpen = true
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.chip, style: .continuous)
                        .fill(ContactsTokens.Accent.primary)
                )
                .foregroundColor(.white)
                .font(.system(size: 12, weight: .semibold))
                .disabled(manager.isReadOnly)
                .help(manager.isReadOnly ? "Read-only" : "Merge Selected")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(ContactsTokens.Surface.window)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
            }
        }
    }
}
