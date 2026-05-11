import SwiftUI

struct ContactEditView: View {
    @ObservedObject var manager: ContactsManager
    @State var draft: Contact
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (Contact) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                identitySection
                fieldsSection
                addFieldRow
                noteSection
                Spacer()
            }
            .padding(.horizontal, ContactsTokens.Spacing.detailInset)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollers()
        .background(ContactsTokens.Surface.detail)
    }

    private var header: some View {
        HStack(spacing: ContactsTokens.Spacing.avatarToTitle) {
            ContactsAvatar(contact: draft, size: ContactsTokens.Geometry.avatarHero)
            VStack(alignment: .leading, spacing: 8) {
                TextField("First Name", text: $draft.givenName)
                    .textFieldStyle(.plain)
                    .font(.system(size: ContactsTokens.TypeSize.detailName, weight: .semibold))
                    .foregroundColor(ContactsTokens.Ink.primary)
                TextField("Last Name", text: $draft.familyName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(ContactsTokens.Ink.primary)
                HStack(spacing: 10) {
                    TextField("Company", text: Binding(
                        get: { draft.organization ?? "" },
                        set: { draft.organization = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: ContactsTokens.TypeSize.detailSubtitle))
                        .foregroundColor(ContactsTokens.Ink.secondary)
                    TextField("Title", text: Binding(
                        get: { draft.jobTitle ?? "" },
                        set: { draft.jobTitle = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: ContactsTokens.TypeSize.detailSubtitle))
                        .foregroundColor(ContactsTokens.Ink.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Save") {
                    onSave(draft)
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
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(ContactsTokens.Ink.secondary)
                    .font(.system(size: 12))
                    .padding(.horizontal, 18)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                            .stroke(ContactsTokens.Divider.hairline, lineWidth: 1)
                    )
            }
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(isNew ? "NEW CONTACT" : "EDIT")
            HStack {
                Toggle("Favorite", isOn: $draft.isFavorite)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundColor(ContactsTokens.Ink.primary)
                Spacer()
                Picker("Account", selection: $draft.accountID) {
                    ForEach(manager.accounts) { acc in
                        Text(acc.title).tag(acc.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
        }
    }

    private var fieldsSection: some View {
        VStack(spacing: 0) {
            ForEach($draft.fields) { $field in
                FieldEditRow(field: $field, onRemove: {
                    withAnimation(ContactsTokens.Motion.fieldAppend) {
                        draft.fields.removeAll(where: { $0.id == field.id })
                    }
                })
                if field.id != draft.fields.last?.id {
                    Rectangle()
                        .fill(ContactsTokens.Divider.fieldRow)
                        .frame(height: 1)
                        .padding(.leading, 110)
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

    private var addFieldRow: some View {
        Menu {
            ForEach(ContactField.Kind.allCases) { kind in
                Button(kind.displayName) {
                    appendField(kind)
                }
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(.plus, size: 11)
                    .foregroundColor(ContactsTokens.Accent.primary)
                Text("Add Field")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ContactsTokens.Accent.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .stroke(ContactsTokens.Divider.hairline.opacity(0.6), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("NOTE")
            TextEditor(text: Binding(
                get: { draft.note ?? "" },
                set: { draft.note = $0.isEmpty ? nil : $0 }))
                .font(.system(size: ContactsTokens.TypeSize.fieldValue))
                .foregroundColor(ContactsTokens.Ink.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                        .overlay(
                            RoundedRectangle(cornerRadius: ContactsTokens.Radius.card, style: .continuous)
                                .stroke(ContactsTokens.Divider.hairline, lineWidth: 0.5)
                        )
                )
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(ContactsTokens.Ink.tertiary)
    }

    private func appendField(_ kind: ContactField.Kind) {
        withAnimation(ContactsTokens.Motion.fieldAppend) {
            draft.fields.append(ContactField(
                id: UUID().uuidString,
                kind: kind,
                label: kind.defaultLabel,
                value: ""
            ))
        }
    }
}

private struct FieldEditRow: View {
    @Binding var field: ContactField
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ContactsTokens.Spacing.fieldLabelToValue) {
            Button {
            } label: {
                LucideIcon(.minus, size: 11)
                    .foregroundColor(ContactsTokens.Ink.danger)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().stroke(ContactsTokens.Ink.danger.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onTapGesture(perform: onRemove)
            .help("Remove Field")
            .padding(.top, 4)

            Menu {
                let labels = ContactField.Kind.availableLabels[field.kind] ?? []
                ForEach(labels, id: \.self) { lbl in
                    Button(lbl) { field.label = lbl }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(field.label.lowercased())
                        .font(.system(size: ContactsTokens.TypeSize.fieldLabel, weight: .medium))
                        .foregroundColor(ContactsTokens.Accent.primary)
                    LucideIcon(.chevronDown, size: 8)
                        .foregroundColor(ContactsTokens.Accent.primary)
                }
                .frame(width: 76, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.top, 4)

            TextField(field.kind.displayName, text: $field.value)
                .textFieldStyle(.plain)
                .font(.system(size: ContactsTokens.TypeSize.fieldValue))
                .foregroundColor(ContactsTokens.Ink.primary)
                .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, ContactsTokens.Spacing.fieldRowVertical)
        .frame(minHeight: ContactsTokens.Geometry.fieldRowMinHeight)
    }
}
