import SwiftUI

struct SmartGroupConfigView: View {
    @ObservedObject var manager: ContactsManager
    @State var draft: ContactsGroup
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 520, height: 480)
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
            LucideIcon(.workflow, size: 13)
                .foregroundColor(ContactsTokens.Accent.smart)
            TextField("Smart Group Name", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ContactsTokens.Ink.primary)
            Spacer()
            Button("Cancel", action: onClose)
                .buttonStyle(.plain)
                .foregroundColor(ContactsTokens.Ink.secondary)
                .font(.system(size: 12))
            Button("Save") {
                Task { await manager.saveSmartGroup(draft); onClose() }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                    .fill(ContactsTokens.Accent.primary)
            )
            .disabled(manager.isReadOnly)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ContactsTokens.Divider.hairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            matchModeRow
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(currentRule.conditions) { condition in
                        ConditionRow(
                            condition: bindingFor(condition),
                            onRemove: { removeCondition(condition.id) }
                        )
                    }
                }
            }
            .thinScrollers()
            Button {
                addCondition()
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(.plus, size: 11)
                        .foregroundColor(ContactsTokens.Accent.primary)
                    Text("Add Condition")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ContactsTokens.Accent.primary)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ContactsTokens.Radius.row, style: .continuous)
                        .stroke(ContactsTokens.Divider.hairline.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(16)
    }

    private var currentRule: SmartGroupRule {
        draft.smartRule ?? SmartGroupRule(matchAll: true, conditions: [])
    }

    private var matchModeRow: some View {
        HStack(spacing: 8) {
            Text("Match")
                .font(.system(size: 12))
                .foregroundColor(ContactsTokens.Ink.secondary)
            Picker("", selection: Binding(
                get: { currentRule.matchAll ? "all" : "any" },
                set: { newVal in
                    var rule = currentRule
                    rule.matchAll = (newVal == "all")
                    draft.smartRule = rule
                }
            )) {
                Text("all").tag("all")
                Text("any").tag("any")
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            Text("of the following conditions:")
                .font(.system(size: 12))
                .foregroundColor(ContactsTokens.Ink.secondary)
            Spacer()
        }
    }

    private func bindingFor(_ condition: SmartGroupRule.Condition) -> Binding<SmartGroupRule.Condition> {
        Binding(
            get: {
                currentRule.conditions.first(where: { $0.id == condition.id }) ?? condition
            },
            set: { newValue in
                var rule = currentRule
                if let idx = rule.conditions.firstIndex(where: { $0.id == condition.id }) {
                    rule.conditions[idx] = newValue
                }
                draft.smartRule = rule
            }
        )
    }

    private func addCondition() {
        var rule = currentRule
        rule.conditions.append(SmartGroupRule.Condition(
            id: UUID().uuidString,
            field: .givenName,
            op: .contains,
            value: ""
        ))
        draft.smartRule = rule
    }

    private func removeCondition(_ id: String) {
        var rule = currentRule
        rule.conditions.removeAll(where: { $0.id == id })
        draft.smartRule = rule
    }
}

private struct ConditionRow: View {
    @Binding var condition: SmartGroupRule.Condition
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.field) {
                ForEach(SmartGroupRule.Field.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Picker("", selection: $condition.op) {
                ForEach(SmartGroupRule.Op.allCases) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            if condition.op.needsValue {
                TextField("value", text: $condition.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            } else {
                Spacer()
            }

            Button(action: onRemove) {
                LucideIcon(.minus, size: 11)
                    .foregroundColor(ContactsTokens.Ink.danger)
                    .frame(width: 22, height: 22)
                    .background(Circle().stroke(ContactsTokens.Ink.danger.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
