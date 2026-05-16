import SwiftUI

struct ContactsToolbar: View {
    @ObservedObject var manager: ContactsManager
    @FocusState private var searchFocused: Bool
    @State private var searchExpanded: Bool = false
    @State private var sortMenuOpen: Bool = false

    var body: some View {
        HStack(spacing: ContactsTokens.Spacing.toolbarButtonGap) {
            createButton
            searchField
            Spacer(minLength: 12)
            Text(manager.selectionTitle())
                .font(.system(size: ContactsTokens.TypeSize.toolbar, weight: .semibold))
                .foregroundColor(ContactsTokens.Ink.primary)
            Spacer(minLength: 12)
            sortControl
            shareControl
        }
        .padding(.leading, ContactsTokens.Spacing.toolbarLeading)
        .padding(.trailing, ContactsTokens.Spacing.toolbarTrailing)
        .frame(height: ContactsTokens.Geometry.toolbarHeight)
        .background(ContactsTokens.Surface.window)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
        }
    }

    private var createButton: some View {
        Button {
            manager.startCreate()
        } label: {
            LucideIcon(.plus, size: 13)
                .foregroundColor(manager.isReadOnly
                                 ? ContactsTokens.Ink.tertiary
                                 : ContactsTokens.Ink.primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .fill(Color.white.opacity(manager.isReadOnly ? 0 : 0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(manager.isReadOnly)
        .help(manager.isReadOnly ? "Read-only" : "New Contact")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            LucideIcon(.search, size: 11)
                .foregroundColor(ContactsTokens.Ink.secondary)
            TextField("Search", text: $manager.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: ContactsTokens.TypeSize.toolbar))
                .foregroundColor(ContactsTokens.Ink.primary)
                .focused($searchFocused)
            if !manager.searchQuery.isEmpty {
                Button {
                    manager.searchQuery = ""
                } label: {
                    LucideIcon(.circleX, size: 11)
                        .foregroundColor(ContactsTokens.Ink.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: searchExpanded ? 320 : 220, height: 24)
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                .fill(ContactsTokens.Surface.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline, lineWidth: 1)
                )
        )
        .onChange(of: searchFocused) { _, focused in
            withAnimation(ContactsTokens.Motion.searchExpand) {
                searchExpanded = focused
            }
        }
    }

    private var sortControl: some View {
        Button {
            sortMenuOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                LucideIcon(.list, size: 11)
                    .foregroundColor(ContactsTokens.Ink.secondary)
                Text(manager.sortKey.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(ContactsTokens.Ink.primary)
                LucideIcon(.chevronDown, size: 9)
                    .foregroundColor(ContactsTokens.Ink.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .stroke(ContactsTokens.Divider.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $sortMenuOpen, arrowEdge: .bottom) {
            sortMenu
        }
    }

    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ContactsSortKey.allCases) { key in
                SortMenuRow(label: key.displayName,
                            isSelected: manager.sortKey == key) {
                    withAnimation(ContactsTokens.Motion.selection) {
                        manager.sortKey = key
                    }
                    sortMenuOpen = false
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .menuStandardBackground()
    }

    private var shareControl: some View {
        Button {
            shareSelected()
        } label: {
            LucideIcon(.share2, size: 12)
                .foregroundColor(manager.selectedContact == nil
                                 ? ContactsTokens.Ink.tertiary
                                 : ContactsTokens.Ink.primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .fill(Color.white.opacity(manager.selectedContact == nil ? 0 : 0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(manager.selectedContact == nil)
        .help("Share vCard")
    }

    private func shareSelected() {
        guard let c = manager.selectedContact, let data = manager.encodeVCard(for: c) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(c.fullName).vcf")
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            return
        }
    }
}

private struct SortMenuRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    LucideIcon(.check, size: 11)
                        .foregroundColor(ContactsTokens.Ink.primary)
                        .frame(width: 14)
                } else {
                    Spacer().frame(width: 14)
                }
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundColor(ContactsTokens.Ink.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
