import SwiftUI

/// Catalog of tag-based skill collections. A collection expands at
/// agent-resolve time to every skill whose frontmatter `tags` matches
/// one of `includedTags`. Today the runtime side reads the existing
/// `~/.clawjs/skills/<id>/SKILL.md` corpus; the editor here only
/// manages the collection definitions.
struct SkillCollectionsHomeView: View {
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var editor: SkillCollection?

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editor) { draft in
            SkillCollectionEditorSheet(initial: draft, isPresented: Binding(
                get: { editor != nil },
                set: { if !$0 { editor = nil } }
            )) { saved in
                store.upsertCollection(saved)
                editor = nil
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Skill Collections")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(store.skillCollections.count) collection\(store.skillCollections.count == 1 ? "" : "s") · ~/.clawjs/skill-collections/")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "plus", label: "New collection", isPrimary: true) {
                editor = SkillCollection.newDraft()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if store.skillCollections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "square.stack")
                    .font(BodyFont.system(size: 28, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Text("No collections yet")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Collections bundle skills by tag so agents can subscribe to a topic instead of allow-listing one skill at a time.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                IconChipButton(symbol: "plus", label: "New collection", isPrimary: true) {
                    editor = SkillCollection.newDraft()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 14)],
                          alignment: .leading, spacing: 14) {
                    ForEach(store.skillCollections) { c in
                        CollectionCard(collection: c)
                            .onTapGesture {
                                appState.navigate(to: .skillCollectionDetail(id: c.id))
                            }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
        }
    }
}

private struct CollectionCard: View {
    let collection: SkillCollection
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack")
                    .foregroundColor(Palette.textSecondary)
                Text(collection.name)
                    .font(BodyFont.system(size: 13.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
            }
            if !collection.description.isEmpty {
                Text(collection.description)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
            }
            FlowChips(items: collection.includedTags)
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

// MARK: - Detail

struct SkillCollectionDetailView: View {
    let collectionId: String
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var showEditor: Bool = false
    @State private var deleteConfirm: Bool = false

    private var collection: SkillCollection? { store.collection(id: collectionId) }

    var body: some View {
        if let collection {
            VStack(spacing: 0) {
                header(for: collection)
                CardDivider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !collection.description.isEmpty {
                            Text(collection.description)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("INCLUDED TAGS")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            FlowChips(items: collection.includedTags)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SUBSCRIBED AGENTS")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            let users = store.agents.filter { $0.skillCollectionIds.contains(collection.id) }
                            if users.isEmpty {
                                Text("No agents subscribe to this collection yet.")
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
                SkillCollectionEditorSheet(initial: collection, isPresented: $showEditor) { saved in
                    store.upsertCollection(saved)
                    showEditor = false
                }
            }
            .alert("Delete \(collection.name)?",
                   isPresented: $deleteConfirm) {
                Button("Delete", role: .destructive) {
                    store.deleteCollection(id: collection.id)
                    appState.navigate(to: .skillCollectionsHome)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the collection and unsubscribes every agent referencing it.")
            }
        } else {
            VStack(spacing: 10) {
                Text("Collection not found")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                IconChipButton(symbol: "arrow.left", label: "Back") {
                    appState.navigate(to: .skillCollectionsHome)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for c: SkillCollection) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(c.includedTags.count) tag\(c.includedTags.count == 1 ? "" : "s") · updated \(c.updatedAt, style: .relative)")
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

// MARK: - Editor

struct SkillCollectionEditorSheet: View {
    let initial: SkillCollection
    @Binding var isPresented: Bool
    let onSave: (SkillCollection) -> Void
    @State private var draft: SkillCollection
    @State private var newTag: String = ""

    init(initial: SkillCollection, isPresented: Binding<Bool>,
         onSave: @escaping (SkillCollection) -> Void) {
        self.initial = initial
        self._isPresented = isPresented
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(initial.createdAt == initial.updatedAt ? "New collection" : "Edit collection")
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
                        TextField("Research", text: $draft.name)
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
                    field("Tags") {
                        if draft.includedTags.isEmpty {
                            Text("No tags yet. Add one below.")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        } else {
                            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                ForEach(draft.includedTags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(BodyFont.system(size: 11, wght: 600))
                                            .foregroundColor(Palette.textPrimary)
                                        Button {
                                            draft.includedTags.removeAll { $0 == tag }
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
                        HStack(spacing: 8) {
                            TextField("tag-name", text: $newTag)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(fieldBg)
                                .onSubmit { commitTag() }
                            IconChipButton(symbol: "plus") { commitTag() }
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
        .frame(width: 580, height: 520)
    }

    private func commitTag() {
        let value = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty, !draft.includedTags.contains(value) else { return }
        draft.includedTags.append(value)
        newTag = ""
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
