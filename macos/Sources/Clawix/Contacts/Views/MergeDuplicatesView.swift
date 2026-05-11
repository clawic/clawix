import SwiftUI

struct MergeDuplicatesView: View {
    @ObservedObject var manager: ContactsManager
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 640, height: 480)
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.sheet, style: .continuous)
                .fill(ContactsTokens.Surface.detail)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.sheet, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            LucideIcon(.listChecks, size: 13)
                .foregroundColor(ContactsTokens.Accent.primary)
            Text("Merge \(candidates.count) Contacts")
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
    }

    private var content: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(candidates) { contact in
                    column(for: contact)
                }
            }
            .padding(16)
        }
        .thinScrollers()
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Conflicting values keep the first contact's value.")
                .font(.system(size: 11))
                .foregroundColor(ContactsTokens.Ink.tertiary)
            Spacer()
            Button("Cancel", action: onClose)
                .buttonStyle(.plain)
                .foregroundColor(ContactsTokens.Ink.secondary)
                .font(.system(size: 12))
            Button("Merge") {
                Task { await manager.performMerge(); onClose() }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .fill(ContactsTokens.Accent.primary)
            )
            .disabled(manager.isReadOnly)
            .help(manager.isReadOnly ? "Read-only" : "Merge")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .top) {
            Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
        }
    }

    private var candidates: [Contact] {
        manager.mergeCandidateIDs.compactMap { manager.contactsByID[$0] }
    }

    private func column(for contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ContactsAvatar(contact: contact, size: 56)
            Text(contact.fullName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ContactsTokens.Ink.primary)
            if let job = contact.jobTitle, let org = contact.organization {
                Text("\(job), \(org)")
                    .font(.system(size: 11))
                    .foregroundColor(ContactsTokens.Ink.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(contact.fields) { f in
                    HStack(spacing: 6) {
                        Text(f.label.lowercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ContactsTokens.Ink.tertiary)
                            .frame(width: 50, alignment: .trailing)
                        Text(f.value)
                            .font(.system(size: 11))
                            .foregroundColor(ContactsTokens.Ink.primary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline, lineWidth: 0.5)
                )
        )
    }
}
