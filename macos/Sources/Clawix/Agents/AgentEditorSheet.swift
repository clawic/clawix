import SwiftUI

/// Form sheet used for both creating a new agent and editing an
/// existing one. Wires the user's edits into a local draft so the
/// caller can persist atomically on `Save`. Keeps the surface compact
/// (single column, no tabs): the Settings tab on `AgentDetailView`
/// covers read-only deep inspection; the editor is fast-edit.
struct AgentEditorSheet: View {
    @EnvironmentObject private var store: AgentStore

    let initial: Agent
    @Binding var isPresented: Bool
    let onSave: (Agent) -> Void

    @State private var draft: Agent
    @State private var newPersonalityId: String = ""
    @State private var newCollectionId: String = ""
    @State private var newSkill: String = ""
    @State private var newSecret: String = ""
    @State private var newTag: String = ""
    @State private var newProjectId: String = ""
    @State private var newBindingChannel: String = ""
    @State private var newBindingConnection: String = ""

    init(initial: Agent,
         isPresented: Binding<Bool>,
         onSave: @escaping (Agent) -> Void) {
        self.initial = initial
        self._isPresented = isPresented
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection
                    runtimeSection
                    instructionsSection
                    personalitiesSection
                    skillsSection
                    secretsSection
                    projectsSection
                    integrationsSection
                    autonomySection
                    delegationSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
            CardDivider()
            footer
        }
        .frame(width: 720, height: 720)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Stored at ~/.clawjs/agents/\(draft.id)/")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconCircleButton(symbol: "xmark") { isPresented = false }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var headerTitle: String {
        if initial.isBuiltin { return "Inspect built-in agent" }
        if initial.createdAt == initial.updatedAt { return "New agent" }
        return "Edit agent"
    }

    // MARK: - Sections

    private var identitySection: some View {
        section(title: "Identity") {
            labeledField("Name") {
                TextField("My agent", text: $draft.name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .disabled(draft.isBuiltin)
            }
            labeledField("Role") {
                TextField("Software engineer, brand writer, researcher…",
                          text: $draft.role)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
            }
            labeledField("Avatar tint (hex)") {
                HStack(spacing: 8) {
                    TextField("#7C9CFF", text: $draft.avatar.tintHex)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(fieldBackground)
                    AgentAvatarBadge(avatar: draft.avatar, size: 30)
                }
            }
        }
    }

    private var runtimeSection: some View {
        section(title: "Runtime") {
            labeledField("Runtime") {
                Picker("", selection: $draft.runtime) {
                    ForEach(AgentRuntimeKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(draft.isBuiltin)
                .onChange(of: draft.runtime) { _, newRuntime in
                    if draft.model.isEmpty {
                        draft.model = newRuntime.defaultModel
                    }
                }
            }
            labeledField("Model") {
                TextField(draft.runtime.defaultModel, text: $draft.model)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
            }
        }
    }

    private var instructionsSection: some View {
        section(title: "Free-text instructions") {
            TextEditor(text: $draft.instructionsFreeText)
                .font(.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .frame(minHeight: 100, maxHeight: 220)
                .padding(8)
                .background(fieldBackground)
                .scrollContentBackground(.hidden)
        }
    }

    private var personalitiesSection: some View {
        section(title: "Personalities") {
            chipList(items: $draft.personalityIds, placeholder: "personality.id") {
                $0
            }
            HStack(spacing: 8) {
                if !store.personalities.isEmpty {
                    Menu {
                        ForEach(store.personalities) { p in
                            Button(p.name) {
                                if !draft.personalityIds.contains(p.id) {
                                    draft.personalityIds.append(p.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add from catalog", systemImage: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
                TextField("personality.id", text: $newPersonalityId)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitPersonality() }
                IconChipButton(symbol: "plus") { commitPersonality() }
            }
        }
    }

    private var skillsSection: some View {
        section(title: "Skills") {
            HStack(spacing: 6) {
                Text("COLLECTIONS")
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            chipList(items: $draft.skillCollectionIds, placeholder: "collection.id") { $0 }
            HStack(spacing: 8) {
                if !store.skillCollections.isEmpty {
                    Menu {
                        ForEach(store.skillCollections) { c in
                            Button(c.name) {
                                if !draft.skillCollectionIds.contains(c.id) {
                                    draft.skillCollectionIds.append(c.id)
                                }
                            }
                        }
                    } label: {
                        Label("Subscribe", systemImage: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
                TextField("collection.id", text: $newCollectionId)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitCollection() }
                IconChipButton(symbol: "plus") { commitCollection() }
            }
            HStack(spacing: 6) {
                Text("ALLOWLIST")
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            chipList(items: $draft.skillAllowlist, placeholder: "skill-id") { $0 }
            HStack(spacing: 8) {
                TextField("skill-id", text: $newSkill)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitSkill() }
                IconChipButton(symbol: "plus") { commitSkill() }
            }
        }
    }

    private var secretsSection: some View {
        section(title: "Secrets") {
            HStack(spacing: 6) {
                Text("TAG SUBSCRIPTIONS")
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            chipList(items: $draft.secretTags, placeholder: "tag") { $0 }
            HStack(spacing: 8) {
                TextField("tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitTag() }
                IconChipButton(symbol: "plus") { commitTag() }
            }
            HStack(spacing: 6) {
                Text("ALLOWLIST")
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            chipList(items: $draft.secretAllowlist, placeholder: "secret-id") { $0 }
            HStack(spacing: 8) {
                TextField("secret-id", text: $newSecret)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitSecret() }
                IconChipButton(symbol: "plus") { commitSecret() }
            }
        }
    }

    private var projectsSection: some View {
        section(title: "Projects") {
            chipList(items: $draft.projectIds, placeholder: "project-uuid") { $0 }
            HStack(spacing: 8) {
                TextField("project-uuid", text: $newProjectId)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitProject() }
                IconChipButton(symbol: "plus") { commitProject() }
            }
        }
    }

    private var integrationsSection: some View {
        section(title: "Integrations") {
            ForEach(draft.integrationBindings) { binding in
                HStack(spacing: 8) {
                    Image(systemName: store.connection(id: binding.connectionId)?.service.icon ?? "link")
                        .foregroundColor(Palette.textSecondary)
                    Text(store.connection(id: binding.connectionId)?.label ?? binding.connectionId)
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text("· \(binding.channelRef) · \(binding.direction.rawValue)")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                    IconCircleButton(symbol: "trash") {
                        draft.integrationBindings.removeAll { $0.id == binding.id }
                    }
                }
            }
            HStack(spacing: 8) {
                Picker("", selection: $newBindingConnection) {
                    Text("Connection").tag("")
                    ForEach(store.connections) { c in
                        Text(c.label).tag(c.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220, alignment: .leading)
                TextField("channel-ref", text: $newBindingChannel)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(fieldBackground)
                    .onSubmit { commitBinding() }
                IconChipButton(symbol: "plus") { commitBinding() }
            }
        }
    }

    private var autonomySection: some View {
        section(title: "Autonomy") {
            Picker("", selection: $draft.autonomyLevel) {
                ForEach(AgentAutonomyLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(draft.autonomyLevel.blurb)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
        }
    }

    private var delegationSection: some View {
        section(title: "Delegation") {
            labeledField("Reports to (agent id, optional)") {
                TextField("", text: Binding(
                    get: { draft.delegation.reportsTo ?? "" },
                    set: { draft.delegation.reportsTo = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(fieldBackground)
            }
            HStack {
                Toggle(isOn: $draft.delegation.scopeInherits) {
                    Text("Subagent invocations inherit caller scope")
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            IconChipButton(symbol: "xmark", label: "Cancel") { isPresented = false }
            IconChipButton(symbol: "checkmark", label: "Save", isPrimary: true) {
                onSave(draft)
                isPresented = false
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private func chipList(items: Binding<[String]>,
                          placeholder: String,
                          render: @escaping (String) -> String) -> some View {
        if items.wrappedValue.isEmpty {
            Text("Empty.")
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
        } else {
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(items.wrappedValue, id: \.self) { value in
                    HStack(spacing: 4) {
                        Text(render(value))
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(Palette.textPrimary)
                        Button {
                            items.wrappedValue.removeAll { $0 == value }
                        } label: {
                            Image(systemName: "xmark")
                                .font(BodyFont.system(size: 9, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
        }
    }

    private func commitPersonality() {
        let value = newPersonalityId.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.personalityIds.contains(value) else { return }
        draft.personalityIds.append(value)
        newPersonalityId = ""
    }

    private func commitCollection() {
        let value = newCollectionId.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.skillCollectionIds.contains(value) else { return }
        draft.skillCollectionIds.append(value)
        newCollectionId = ""
    }

    private func commitSkill() {
        let value = newSkill.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.skillAllowlist.contains(value) else { return }
        draft.skillAllowlist.append(value)
        newSkill = ""
    }

    private func commitSecret() {
        let value = newSecret.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.secretAllowlist.contains(value) else { return }
        draft.secretAllowlist.append(value)
        newSecret = ""
    }

    private func commitTag() {
        let value = newTag.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.secretTags.contains(value) else { return }
        draft.secretTags.append(value)
        newTag = ""
    }

    private func commitProject() {
        let value = newProjectId.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.projectIds.contains(value) else { return }
        draft.projectIds.append(value)
        newProjectId = ""
    }

    private func commitBinding() {
        guard !newBindingConnection.isEmpty else { return }
        let channel = newBindingChannel.trimmingCharacters(in: .whitespaces)
        guard !channel.isEmpty else { return }
        let binding = AgentIntegrationBinding(
            id: UUID().uuidString,
            connectionId: newBindingConnection,
            channelRef: channel,
            direction: .both,
            label: nil
        )
        draft.integrationBindings.append(binding)
        newBindingChannel = ""
    }
}
