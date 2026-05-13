import SwiftUI

/// Catalog of reusable personalities. Each entry is a markdown prompt
/// fragment plugged into one or more agents (`agent.personalityIds`)
/// and concatenated in order to produce the system prompt the runtime
/// receives. The home grid mirrors `AgentsHomeView` for consistency.
struct PersonalitiesHomeView: View {
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var editor: AgentPersonality?

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editor) { draft in
            PersonalityEditorSheet(initial: draft, isPresented: Binding(
                get: { editor != nil },
                set: { if !$0 { editor = nil } }
            )) { saved in
                store.upsertAgentPersonality(saved)
                editor = nil
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Personalities")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(store.personalities.count) personalit\(store.personalities.count == 1 ? "y" : "ies") · ~/.claw/personalities/")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "plus", label: "New personality", isPrimary: true) {
                editor = AgentPersonality.newDraft()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if store.personalities.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)],
                          alignment: .leading, spacing: 14) {
                    ForEach(store.personalities) { p in
                        PersonalityCard(personality: p)
                            .onTapGesture { appState.navigate(to: .personalityDetail(id: p.id)) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "theatermasks")
                .font(BodyFont.system(size: 28, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Text("No personalities yet")
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Personalities are short markdown fragments you can plug into agents to shape their voice.")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            IconChipButton(symbol: "plus", label: "New personality", isPrimary: true) {
                editor = AgentPersonality.newDraft()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }
}

private struct PersonalityCard: View {
    let personality: AgentPersonality
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "theatermasks")
                    .foregroundColor(Palette.textSecondary)
                Text(personality.name)
                    .font(BodyFont.system(size: 13.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Text("v\(personality.version)")
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
            }
            if !personality.description.isEmpty {
                Text(personality.description)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovered = $0 }
    }
}

// MARK: - Detail view

struct PersonalityDetailView: View {
    let personalityId: String
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var showEditor: Bool = false
    @State private var deleteConfirm: Bool = false

    private var personality: AgentPersonality? { store.personality(id: personalityId) }

    var body: some View {
        if let personality {
            VStack(spacing: 0) {
                header(for: personality)
                CardDivider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !personality.description.isEmpty {
                            Text(personality.description)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PROMPT")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            Text(personality.promptMarkdown.isEmpty ?
                                 "Empty. Click Edit to add the prompt." :
                                 personality.promptMarkdown)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundColor(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.03))
                                )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("USED BY")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            let users = store.agents.filter { $0.personalityIds.contains(personality.id) }
                            if users.isEmpty {
                                Text("No agents plug this personality in yet.")
                                    .font(BodyFont.system(size: 12, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                            } else {
                                FlowChips(items: users.map(\.name))
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollers()
            }
            .sheet(isPresented: $showEditor) {
                PersonalityEditorSheet(initial: personality, isPresented: $showEditor) { saved in
                    store.upsertAgentPersonality(saved)
                    showEditor = false
                }
            }
            .alert("Delete \(personality.name)?",
                   isPresented: $deleteConfirm) {
                Button("Delete", role: .destructive) {
                    store.deleteAgentPersonality(id: personality.id)
                    appState.navigate(to: .personalitiesHome)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the personality and unplugs it from every agent that referenced it.")
            }
        } else {
            VStack(spacing: 10) {
                Text("Personality not found")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                IconChipButton(symbol: "arrow.left", label: "Back") {
                    appState.navigate(to: .personalitiesHome)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for p: AgentPersonality) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Version \(p.version) · updated \(p.updatedAt, style: .relative)")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "pencil", label: "Edit") { showEditor = true }
            IconChipButton(symbol: "trash") { deleteConfirm = true }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

// MARK: - Editor sheet

struct PersonalityEditorSheet: View {
    let initial: AgentPersonality
    @Binding var isPresented: Bool
    let onSave: (AgentPersonality) -> Void
    @State private var draft: AgentPersonality

    init(initial: AgentPersonality, isPresented: Binding<Bool>,
         onSave: @escaping (AgentPersonality) -> Void) {
        self.initial = initial
        self._isPresented = isPresented
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(initial.createdAt == initial.updatedAt ? "New personality" : "Edit personality")
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                IconCircleButton(symbol: "xmark") { isPresented = false }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            CardDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("Mentor irónico", text: $draft.name)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(fieldBg)
                    }
                    field("Description") {
                        TextField("One-line summary", text: $draft.description)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(fieldBg)
                    }
                    field("Prompt (markdown)") {
                        TextEditor(text: $draft.promptMarkdown)
                            .font(.system(size: 12.5, design: .monospaced))
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(fieldBg)
                            .scrollContentBackground(.hidden)
                    }
                    field("Version") {
                        Stepper(value: $draft.version, in: 1...999) {
                            Text("v\(draft.version)")
                                .font(BodyFont.system(size: 12.5, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
            CardDivider()
            HStack {
                Spacer()
                IconChipButton(symbol: "xmark", label: "Cancel") { isPresented = false }
                IconChipButton(symbol: "checkmark", label: "Save", isPrimary: true) {
                    onSave(draft)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 620, height: 580)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }

    private var fieldBg: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}
