import SwiftUI

/// Right-side detail panel for a single skill. Reached from the
/// catalog via `.skillDetail(slug:)`. Sections (top to bottom):
/// header (icon, name, kind/version/author), description, activation
/// toggles per scope, parameter form (only for templates), curated
/// presets, sync target toggles, body markdown viewer/editor,
/// destructive actions (freeze, delete) at the bottom.
struct SkillDetailView: View {
    let slug: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var vault: SecretsManager

    @State private var editingBody = false
    @State private var bodyDraft: String = ""
    @State private var paramDraft: [String: SkillParamValue] = [:]
    @State private var pendingDelete: SkillSpec?

    private var store: SkillsStore? { appState.skillsStore }
    private var skill: SkillSpec? { store?.skill(slug: slug) }

    var body: some View {
        ScrollView {
            if let skill {
                content(for: skill)
            } else {
                missingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hydrateDrafts() }
        .onChange(of: slug) { _, _ in hydrateDrafts() }
        .alert(item: $pendingDelete) { skill in
            Alert(
                title: Text("Delete \"\(skill.name)\"?"),
                message: Text("This removes the skill from your local catalog. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    store?.remove(slug: skill.slug)
                    appState.currentRoute = .skills
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(for skill: SkillSpec) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            backLink
            headerBlock(skill)
            descriptionBlock(skill)
            activationBlock(skill)
            if let params = skill.params, !params.isEmpty, !skill.isInstance {
                paramsBlock(skill, params: params)
            }
            if let presets = skill.presets, !presets.isEmpty {
                curatedPresetsBlock(skill, presets: presets)
            }
            if skill.isInstance {
                instanceBlock(skill)
            }
            syncBlock(skill)
            bodyBlock(skill)
            destructiveBlock(skill)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 60)
        .frame(maxWidth: 880, alignment: .leading)
    }

    private var backLink: some View {
        Button { appState.currentRoute = .skills } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("All skills").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func headerBlock(_ skill: SkillSpec) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: skill.kind.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.system(size: 22, weight: .semibold))
                HStack(spacing: 6) {
                    Text(skill.kind.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                    Text("v\(skill.version)").font(.system(size: 11)).foregroundColor(.secondary)
                    if let author = skill.author {
                        Text("·").foregroundColor(.secondary)
                        Text("by \(author)").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if skill.builtin {
                        Text("·").foregroundColor(.secondary)
                        Text("Built-in").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if let importedFrom = skill.importedFrom {
                        Text("·").foregroundColor(.secondary)
                        Text("imported from \(importedFrom)").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
        }
    }

    private func descriptionBlock(_ skill: SkillSpec) -> some View {
        Text(skill.description)
            .font(.system(size: 14))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Activation

    private func activationBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Activation", subtitle: "Where this skill is on. Chat overrides project; project overrides global.") {
            VStack(alignment: .leading, spacing: 6) {
                activationToggle(skill: skill, scopeTag: "global", label: "Active globally")
                if let projectId = currentProjectId, let projectName = currentProjectName {
                    activationToggle(skill: skill, scopeTag: "project:\(projectId)", label: "Active in project: \(projectName)")
                }
                if let chatId = currentChatId {
                    activationToggle(skill: skill, scopeTag: "chat:\(chatId.uuidString)", label: "Active in this chat only")
                }
            }
        }
    }

    private func activationToggle(skill: SkillSpec, scopeTag: String, label: String) -> some View {
        let isOn = store?.isActive(slug: skill.slug, atScope: scopeTag) ?? false
        return Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                store?.setActive(slug: skill.slug, scopeTag: scopeTag, active: newValue, params: paramDraft.isEmpty ? nil : paramDraft)
            }
        )) {
            Text(label).font(.system(size: 12.5))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: - Params (templates)

    private func paramsBlock(_ skill: SkillSpec, params: [SkillParam]) -> some View {
        sectionCard(
            title: "Parameters",
            subtitle: "Configure once, save as your own. The body uses {{key}} placeholders the daemon substitutes at compile-time."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(params) { param in
                    paramRow(param)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        store?.instantiate(template: skill, params: paramDraft, frozen: false)
                    } label: {
                        Text("Save as my skill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    Button {
                        // Use once: just toggle global active with these params,
                        // without persisting an instance.
                        store?.setActive(slug: skill.slug, scopeTag: "global", active: true, params: paramDraft)
                    } label: {
                        Text("Use once")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.gray.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func paramRow(_ param: SkillParam) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(param.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                if param.required {
                    Text("required")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            paramControl(param)
            if let prompt = param.prompt {
                Text(prompt).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func paramControl(_ param: SkillParam) -> some View {
        switch param.type {
        case .enumValue:
            let options = param.options ?? []
            Picker("", selection: Binding(
                get: { (paramDraft[param.key] ?? param.defaultValue ?? .string("")).displayString },
                set: { newValue in paramDraft[param.key] = .string(newValue) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 240, alignment: .leading)
        case .string:
            TextField("", text: Binding(
                get: { (paramDraft[param.key] ?? param.defaultValue ?? .string("")).displayString },
                set: { newValue in paramDraft[param.key] = .string(newValue) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .frame(maxWidth: 360)
        case .number:
            TextField("", value: Binding(
                get: {
                    if case .number(let n) = paramDraft[param.key] { return n }
                    if case .number(let n) = param.defaultValue { return n }
                    return Double(0)
                },
                set: { newValue in paramDraft[param.key] = .number(newValue) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 160)
        case .bool:
            Toggle("", isOn: Binding(
                get: {
                    if case .bool(let b) = paramDraft[param.key] { return b }
                    if case .bool(let b) = param.defaultValue { return b }
                    return false
                },
                set: { newValue in paramDraft[param.key] = .bool(newValue) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        case .secretRef:
            secretReferenceField(param)
        }
    }

    @ViewBuilder
    private func secretReferenceField(_ param: SkillParam) -> some View {
        if vault.state != .unlocked {
            HStack(spacing: 8) {
                Text("Unlock Secrets to choose a secret.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("Open Secrets") {
                    appState.currentRoute = .secretsHome
                }
                .font(.system(size: 11, weight: .semibold))
            }
        } else if vault.secrets.isEmpty {
            Text("No secrets available.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            Picker("", selection: Binding(
                get: {
                    if case .secretRef(let id) = paramDraft[param.key] { return id }
                    if case .secretRef(let id) = param.defaultValue { return id }
                    return ""
                },
                set: { newValue in
                    if newValue.isEmpty {
                        paramDraft.removeValue(forKey: param.key)
                    } else {
                        paramDraft[param.key] = .secretRef(id: newValue)
                    }
                }
            )) {
                Text("Choose a secret").tag("")
                ForEach(vault.secrets, id: \.internalName) { secret in
                    Text(secret.title.isEmpty ? secret.internalName : "\(secret.title) · \(secret.internalName)")
                        .tag(secret.internalName)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    // MARK: - Curated presets (template children)

    private func curatedPresetsBlock(_ skill: SkillSpec, presets: [SkillPreset]) -> some View {
        sectionCard(title: "Curated presets", subtitle: "Quick configurations the author bundled. Picking one creates an instance you can fine-tune.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(presets) { preset in
                    Button {
                        store?.instantiate(template: skill, params: preset.params, saveAs: preset.slug, frozen: false)
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(preset.label)
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer(minLength: 8)
                            Text("Save as instance")
                                .font(.system(size: 11)).foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.gray.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Instance block (when this is an instance, not a template)

    private func instanceBlock(_ skill: SkillSpec) -> some View {
        guard let ref = skill.instance else { return AnyView(EmptyView()) }
        let template = store?.skill(slug: ref.ofTemplate)
        return AnyView(sectionCard(title: ref.frozen ? "Frozen snapshot" : "Instance of template", subtitle: ref.frozen
            ? "Body has been rendered once and the link to the template was dropped. Future template updates won't propagate."
            : "Body is rendered live from the template. Click Freeze to lock in the current copy.") {
            VStack(alignment: .leading, spacing: 8) {
                if let template {
                    HStack(spacing: 6) {
                        Image(systemName: "link").font(.system(size: 11)).foregroundColor(.secondary)
                        Text("Template:").font(.system(size: 11)).foregroundColor(.secondary)
                        Button { appState.currentRoute = .skillDetail(slug: template.slug) } label: {
                            Text(template.name).font(.system(size: 12, weight: .medium)).foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !ref.params.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Params").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        ForEach(ref.params.keys.sorted(), id: \.self) { key in
                            HStack(spacing: 6) {
                                Text(key).font(.system(size: 11, weight: .medium))
                                Text("=").foregroundColor(.secondary)
                                Text(ref.params[key]?.displayString ?? "")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                if !ref.frozen {
                    HStack {
                        Spacer()
                        Button {
                            store?.freeze(instanceSlug: skill.slug)
                        } label: {
                            Text("Freeze")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.orange))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        })
    }

    // MARK: - Sync targets

    private func syncBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Sync to other agents", subtitle: "Materialise this skill in other agents' home dirs (~/.codex/skills, ~/.hermes/skills, …) via symlinks. They consume it as a normal SKILL.md.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store?.syncTargets ?? []) { target in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label).font(.system(size: 12.5, weight: .medium))
                            Text(target.home)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { skill.syncTo.contains(target.id) },
                            set: { newValue in store?.setSyncTarget(slug: skill.slug, target: target.id, enabled: newValue) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                if (store?.syncTargets.isEmpty ?? true) {
                    Text("No sync targets configured. Add them in Settings → Skills.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Body editor

    private func bodyBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Body (markdown)", subtitle: editingBody ? "Editing. Save to persist." : "What the model sees in its system prompt when this skill is active.", trailing: editButton(skill: skill)) {
            if editingBody {
                TextEditor(text: $bodyDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 240)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray.opacity(0.20), lineWidth: 0.5))
            } else {
                Text(skill.body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func editButton(skill: SkillSpec) -> AnyView {
        if skill.builtin {
            return AnyView(
                Text("Built-in (clone to edit)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            )
        }
        if editingBody {
            return AnyView(
                HStack(spacing: 6) {
                    Button("Cancel") {
                        editingBody = false
                        bodyDraft = skill.body
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 11, weight: .medium))
                    Button {
                        var copy = skill
                        copy.body = bodyDraft
                        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
                        store?.upsert(copy)
                        editingBody = false
                    } label: {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }
            )
        }
        return AnyView(
            Button { editingBody = true } label: {
                Text("Edit").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        )
    }

    // MARK: - Destructive

    private func destructiveBlock(_ skill: SkillSpec) -> some View {
        guard !skill.builtin else { return AnyView(EmptyView()) }
        return AnyView(
            HStack {
                Spacer()
                Button {
                    pendingDelete = skill
                } label: {
                    Text("Delete skill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.red.opacity(0.4), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
        )
    }

    // MARK: - Empty state

    private var missingState: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text("Skill not found.").font(.system(size: 15, weight: .semibold))
            Button("Back to all skills") { appState.currentRoute = .skills }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private var currentChatId: UUID? {
        if case let .chat(id) = appState.currentRoute { return id }
        return nil
    }

    private var currentProjectId: String? {
        if let chatId = currentChatId,
           let chat = appState.chats.first(where: { $0.id == chatId }),
           let pid = chat.projectId {
            return pid.uuidString
        }
        if let project = appState.selectedProject {
            return project.id.uuidString
        }
        return nil
    }

    private var currentProjectName: String? {
        guard let projectId = currentProjectId,
              let uuid = UUID(uuidString: projectId),
              let project = appState.projects.first(where: { $0.id == uuid }) else { return nil }
        return project.name
    }

    private func hydrateDrafts() {
        guard let skill else { return }
        bodyDraft = skill.body
        // Populate paramDraft from skill defaults or instance params.
        var draft: [String: SkillParamValue] = [:]
        if let instance = skill.instance {
            draft = instance.params
        } else if let params = skill.params {
            for param in params {
                if let def = param.defaultValue { draft[param.key] = def }
            }
        }
        paramDraft = draft
    }

    // MARK: - Section card chrome

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 4)
                if let trailing { trailing }
            }
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            content()
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.gray.opacity(0.12), lineWidth: 0.5)
        )
    }
}
