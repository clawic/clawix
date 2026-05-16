import SwiftUI

struct ContactDetail: View {
    @ObservedObject var manager: ContactsManager
    let contact: Contact

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                groupChips
                fieldsList
                if let note = contact.note, !note.isEmpty {
                    noteCard(note)
                }
            }
            .padding(.horizontal, ContactsTokens.Spacing.detailInset)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollers()
        .background(ContactsTokens.Surface.detail)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ContactsTokens.Spacing.avatarToTitle) {
            ContactsAvatar(contact: contact,
                           size: ContactsTokens.Geometry.avatarHero,
                           hoverable: true)
                .draggable(vCardURL ?? URL(fileURLWithPath: "/dev/null"))

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.fullName)
                    .font(.system(size: ContactsTokens.TypeSize.detailName, weight: .semibold))
                    .foregroundColor(ContactsTokens.Ink.primary)
                if let job = contact.jobTitle, let org = contact.organization {
                    Text("\(job), \(org)")
                        .font(.system(size: ContactsTokens.TypeSize.detailSubtitle))
                        .foregroundColor(ContactsTokens.Ink.secondary)
                } else if let org = contact.organization {
                    Text(org)
                        .font(.system(size: ContactsTokens.TypeSize.detailSubtitle))
                        .foregroundColor(ContactsTokens.Ink.secondary)
                } else if let job = contact.jobTitle {
                    Text(job)
                        .font(.system(size: ContactsTokens.TypeSize.detailSubtitle))
                        .foregroundColor(ContactsTokens.Ink.secondary)
                }
            }
            Spacer()
            actionCluster
        }
    }

    private var actionCluster: some View {
        HStack(spacing: 6) {
            iconButton(.star, color: contact.isFavorite ? ContactsTokens.Accent.favorite : nil,
                       help: contact.isFavorite ? "Unfavorite" : "Favorite") {
                Task { await manager.toggleFavorite(contact.id) }
            }
            .disabled(manager.isReadOnly)

            iconButton(.zap, color: nil, help: manager.isReadOnly ? "Read-only" : "Edit") {
                manager.startEdit()
            }
            .disabled(manager.isReadOnly)

            iconButton(.trash, color: nil, help: manager.isReadOnly ? "Read-only" : "Delete") {
                Task { await manager.delete(contact.id) }
            }
            .disabled(manager.isReadOnly)

            iconButton(.share2, color: nil, help: "Share vCard") {
                shareVCard()
            }
        }
    }

    private func iconButton(_ icon: LucideIcon.Kind, color: Color?, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 13)
                .foregroundColor(color ?? ContactsTokens.Ink.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var groupChips: some View {
        let chips = contact.groupIDs.compactMap { manager.groupsByID[$0] }
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips) { group in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(group.color)
                            .frame(width: 7, height: 7)
                        Text(group.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ContactsTokens.Ink.primary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: ContactsTokens.Radius.chip, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: ContactsTokens.Radius.chip, style: .continuous)
                                    .stroke(ContactsTokens.Divider.hairline, lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    private var fieldsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(contact.fields) { field in
                ContactFieldRow(field: field)
                if field.id != contact.fields.last?.id {
                    Rectangle()
                        .fill(ContactsTokens.Divider.fieldRow)
                        .frame(height: 1)
                        .padding(.leading, 90)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline, lineWidth: 0.5)
                )
        )
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(ContactsTokens.Ink.tertiary)
            Text(note)
                .font(.system(size: ContactsTokens.TypeSize.fieldValue))
                .foregroundColor(ContactsTokens.Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline, lineWidth: 0.5)
                )
        )
    }

    private var vCardURL: URL? {
        guard let data = manager.encodeVCard(for: contact) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(contact.fullName).vcf")
        try? data.write(to: url)
        return url
    }

    private func shareVCard() {
        guard let data = manager.encodeVCard(for: contact) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(contact.fullName).vcf")
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            return
        }
    }
}

private struct ContactFieldRow: View {
    let field: ContactField
    @State private var hovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: ContactsTokens.Spacing.fieldLabelToValue) {
            Text(field.label.lowercased())
                .font(.system(size: ContactsTokens.TypeSize.fieldLabel, weight: .medium))
                .foregroundColor(ContactsTokens.Ink.secondary)
                .frame(width: 76, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                if field.kind == .birthday, let d = ISO8601DateFormatter().date(from: field.value) {
                    Text(formatBirthday(d))
                        .font(.system(size: ContactsTokens.TypeSize.fieldValue))
                        .foregroundColor(ContactsTokens.Ink.primary)
                } else {
                    Text(field.value)
                        .font(.system(size: ContactsTokens.TypeSize.fieldValue))
                        .foregroundColor(ContactsTokens.Ink.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, ContactsTokens.Spacing.fieldRowVertical)
        .frame(minHeight: ContactsTokens.Geometry.fieldRowMinHeight)
        .background(Color.white.opacity(hovered ? 0.03 : 0))
        .onHover { h in
            withAnimation(ContactsTokens.Motion.hover) { hovered = h }
        }
    }

    private func formatBirthday(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"
        return fmt.string(from: date)
    }
}
