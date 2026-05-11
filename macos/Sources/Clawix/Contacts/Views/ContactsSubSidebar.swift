import SwiftUI

struct ContactsSubSidebar: View {
    @ObservedObject var manager: ContactsManager
    @State private var expandedAccounts: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("On My Mac")
                    smartRow(title: "All Contacts",
                             icon: AnyView(LucideIcon(.idCard, size: 12)
                                .foregroundColor(ContactsTokens.Ink.secondary)),
                             selection: .allContacts)
                    smartRow(title: "Favorites",
                             icon: AnyView(LucideIcon(.star, size: 12)
                                .foregroundColor(ContactsTokens.Accent.favorite)),
                             selection: .favorites)
                    smartRow(title: "Recently Added",
                             icon: AnyView(LucideIcon(.clock, size: 12)
                                .foregroundColor(ContactsTokens.Ink.secondary)),
                             selection: .recentlyAdded)
                    smartRow(title: "Birthdays",
                             icon: AnyView(LucideIcon(.circleDot, size: 11)
                                .foregroundColor(ContactsTokens.Accent.smart)),
                             selection: .birthdays)
                    Spacer().frame(height: 14)

                    if !manager.accounts.isEmpty {
                        sectionHeader("Accounts")
                        ForEach(manager.accounts) { account in
                            accountRow(account)
                        }
                        Spacer().frame(height: 14)
                    }

                    if !normalGroups.isEmpty {
                        sectionHeader("Groups")
                        ForEach(normalGroups) { group in
                            groupRow(group)
                        }
                        Spacer().frame(height: 14)
                    }

                    if !smartGroups.isEmpty {
                        sectionHeader("Smart Groups")
                        ForEach(smartGroups) { group in
                            groupRow(group)
                        }
                        Spacer().frame(height: 14)
                    }
                }
                .padding(.horizontal, ContactsTokens.Spacing.subSidebarInset)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .thinScrollers()

            Spacer(minLength: 0)

            footer
        }
        .frame(width: ContactsTokens.Geometry.subSidebarWidth)
        .background(ContactsTokens.Surface.subSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(ContactsTokens.Divider.seam).frame(width: 1)
        }
    }

    private var normalGroups: [ContactsGroup] {
        manager.groups.filter { $0.kind == .normal }
    }

    private var smartGroups: [ContactsGroup] {
        manager.groups.filter { $0.kind == .smart }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: ContactsTokens.TypeSize.subSidebarHeader, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(ContactsTokens.Ink.tertiary)
            .padding(.vertical, 4)
    }

    private func smartRow(title: String, icon: AnyView, selection: ContactsSelection) -> some View {
        let isSelected = manager.selection == selection
        return Button {
            withAnimation(ContactsTokens.Motion.selection) {
                manager.selection = selection
                manager.selectedContactID = nil
            }
        } label: {
            HStack(spacing: 8) {
                icon
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: ContactsTokens.TypeSize.subSidebarRow))
                    .foregroundColor(ContactsTokens.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: ContactsTokens.Geometry.subSidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? ContactsTokens.Surface.rowSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func accountRow(_ account: ContactsAccount) -> some View {
        let isSelected = manager.selection == .account(account.id)
        let expanded = expandedAccounts.contains(account.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ContactsTokens.Motion.groupDisclose) {
                    if expanded { expandedAccounts.remove(account.id) }
                    else { expandedAccounts.insert(account.id) }
                }
                manager.selection = .account(account.id)
                manager.selectedContactID = nil
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(.chevronRight, size: 9)
                        .foregroundColor(ContactsTokens.Ink.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(ContactsTokens.Motion.groupDisclose, value: expanded)
                        .frame(width: 12)
                    Text(account.title)
                        .font(.system(size: ContactsTokens.TypeSize.subSidebarRow,
                                      weight: .medium))
                        .foregroundColor(ContactsTokens.Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: ContactsTokens.Geometry.subSidebarRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .fill(isSelected ? ContactsTokens.Surface.rowSelected : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(groupsFor(account: account.id)) { group in
                    groupRow(group, indented: true)
                }
            }
        }
    }

    private func groupsFor(account id: String) -> [ContactsGroup] {
        manager.groups.filter { $0.accountID == id }
    }

    private func groupRow(_ group: ContactsGroup, indented: Bool = false) -> some View {
        let isSelected = manager.selection == .group(group.id)
        let smart = group.kind == .smart
        return Button {
            withAnimation(ContactsTokens.Motion.selection) {
                manager.selection = .group(group.id)
                manager.selectedContactID = nil
            }
        } label: {
            HStack(spacing: 8) {
                if smart {
                    LucideIcon(.workflow, size: 11)
                        .foregroundColor(ContactsTokens.Accent.smart)
                        .frame(width: 16, alignment: .center)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(group.color)
                        .frame(width: 9, height: 9)
                        .frame(width: 16, alignment: .center)
                }
                Text(group.title)
                    .font(.system(size: ContactsTokens.TypeSize.subSidebarRow))
                    .foregroundColor(ContactsTokens.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, indented ? 22 : 8)
            .padding(.trailing, 8)
            .frame(height: ContactsTokens.Geometry.subSidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? ContactsTokens.Surface.rowSelected : Color.clear)
                    .padding(.leading, indented ? 18 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if group.kind == .smart {
                Button("Edit Smart Group") {
                    manager.editingSmartGroupID = group.id
                }
                .disabled(manager.isReadOnly)
            }
            Button("Delete Group", role: .destructive) {
                Task { await manager.deleteGroup(group.id) }
            }
            .disabled(manager.isReadOnly)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                addNormalGroup()
            } label: {
                LucideIcon(.plus, size: 13)
                    .foregroundColor(manager.isReadOnly
                                     ? ContactsTokens.Ink.tertiary
                                     : ContactsTokens.Ink.primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(manager.isReadOnly)
            .help(manager.isReadOnly ? "Read-only" : "New Group")

            Button {
                addSmartGroup()
            } label: {
                LucideIcon(.workflow, size: 12)
                    .foregroundColor(manager.isReadOnly
                                     ? ContactsTokens.Ink.tertiary
                                     : ContactsTokens.Accent.smart)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(manager.isReadOnly)
            .help(manager.isReadOnly ? "Read-only" : "New Smart Group")

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .overlay(alignment: .top) {
            Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
        }
    }

    private func addNormalGroup() {
        guard !manager.isReadOnly else { return }
        let accountID = manager.accounts.first?.id ?? "local"
        let g = ContactsGroup(
            id: "grp-\(UUID().uuidString.prefix(8))",
            accountID: accountID,
            title: "New Group",
            color: ContactsTokens.AvatarPalette.colors.randomElement() ?? ContactsTokens.Accent.primary,
            kind: .normal,
            smartRule: nil
        )
        Task { await manager.saveSmartGroup(g) }
    }

    private func addSmartGroup() {
        guard !manager.isReadOnly else { return }
        let accountID = manager.accounts.first?.id ?? "local"
        let id = "smart-\(UUID().uuidString.prefix(8))"
        let g = ContactsGroup(
            id: id,
            accountID: accountID,
            title: "New Smart Group",
            color: ContactsTokens.Accent.smart,
            kind: .smart,
            smartRule: SmartGroupRule(matchAll: true, conditions: [
                SmartGroupRule.Condition(id: UUID().uuidString, field: .givenName,
                                         op: .contains, value: "")
            ])
        )
        Task {
            await manager.saveSmartGroup(g)
            manager.editingSmartGroupID = id
        }
    }
}
