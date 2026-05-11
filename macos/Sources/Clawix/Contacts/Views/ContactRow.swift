import SwiftUI

struct ContactRow: View {
    let contact: Contact
    let isSelected: Bool
    let isMergeCandidate: Bool
    let onSelect: () -> Void
    let onToggleMerge: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ContactsAvatar(contact: contact,
                               size: ContactsTokens.Geometry.avatarRow)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.fullName)
                        .font(.system(size: ContactsTokens.TypeSize.listRowName,
                                      weight: isSelected ? .semibold : .regular))
                        .foregroundColor(ContactsTokens.Ink.primary)
                        .lineLimit(1)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: ContactsTokens.TypeSize.listRowSub))
                            .foregroundColor(ContactsTokens.Ink.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if contact.isFavorite {
                    LucideIcon(.star, size: 10)
                        .foregroundColor(ContactsTokens.Accent.favorite)
                }
                if isMergeCandidate {
                    LucideIcon(.circleCheck, size: 12)
                        .foregroundColor(ContactsTokens.Accent.primary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: ContactsTokens.Geometry.listRowHeight)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .fill(rowFill)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(ContactsTokens.Motion.hover) { hovered = h }
        }
        .contextMenu {
            Button(isMergeCandidate ? "Remove From Merge" : "Add To Merge", action: onToggleMerge)
        }
    }

    private var subtitle: String? {
        if let job = contact.jobTitle, let org = contact.organization {
            return "\(job), \(org)"
        }
        if let org = contact.organization { return org }
        if let phone = contact.primaryPhone { return phone }
        if let email = contact.primaryEmail { return email }
        return nil
    }

    private var rowFill: Color {
        if isSelected { return ContactsTokens.Surface.rowSelected }
        if hovered { return ContactsTokens.Surface.rowHover }
        return .clear
    }
}
