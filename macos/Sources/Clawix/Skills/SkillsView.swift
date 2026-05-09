import SwiftUI

/// Top-level page reachable from the sidebar (⌘⇧K). Renders the user's
/// central library: built-ins + user-created + auto-imported from
/// external agent dirs. Filters by kind/scope/tag, free-text search,
/// "+ New skill" button, and a Sync now action.
///
/// Layout: header bar → filter strip → grid of skill cards. Click a
/// card to open `SkillDetailView` in the same content column.
struct SkillsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var localStore: SkillsStore = SkillsStore()

    private var store: SkillsStore { appState.skillsStore ?? localStore }

    @State private var hoveringNew = false
    @State private var creatingNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                filterStrip
                if store.filtered().isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    grid
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $creatingNew) {
            SkillNewSheet(store: store, onClose: { creatingNew = false })
        }
        .onAppear {
            // Make sure the store seeded its catalog. If AppState owns
            // the canonical store this is a no-op; if we created a
            // local fallback the seed already ran in init.
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Skills")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Your central library. Activate per chat, project or globally. Sync to other agents on toggle.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            searchField
                .frame(maxWidth: 320)
            syncButton
            newSkillButton
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            TextField("Search skills…", text: Binding(
                get: { store.searchQuery },
                set: { store.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            if !store.searchQuery.isEmpty {
                Button { store.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
    }

    private var syncButton: some View {
        Button {
            Task { await store.syncNow() }
        } label: {
            HStack(spacing: 6) {
                if store.pendingOperation != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
                }
                Text("Sync now")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help(syncHelpText)
    }

    private var syncHelpText: String {
        if let date = store.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            return "Last synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Sync skills to ~/.codex/skills, ~/.hermes/skills, etc."
        }
    }

    private var newSkillButton: some View {
        Button { creatingNew = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New skill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(hoveringNew ? 0.95 : 0.85))
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveringNew = $0 }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                kindChip(nil, label: "All kinds")
                ForEach(SkillKind.allCases) { kind in
                    kindChip(kind, label: kind.label)
                }
                Spacer(minLength: 12)
                resetFiltersButton
            }
            tagCloud
        }
    }

    private func kindChip(_ kind: SkillKind?, label: String) -> some View {
        Button {
            store.kindFilter = kind
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(store.kindFilter == kind ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(store.kindFilter == kind ? Color.accentColor : Color.gray.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private var resetFiltersButton: some View {
        Button {
            store.kindFilter = nil
            store.scopeFilter = nil
            store.tagFilter = nil
            store.searchQuery = ""
        } label: {
            Text("Reset filters")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(hasAnyFilter ? 1 : 0)
    }

    private var hasAnyFilter: Bool {
        store.kindFilter != nil || store.scopeFilter != nil || store.tagFilter != nil || !store.searchQuery.isEmpty
    }

    private var tagCloud: some View {
        let tags = store.allTags()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(40), id: \.self) { tag in
                    tagChip(tag)
                }
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        Button {
            store.tagFilter = (store.tagFilter == tag) ? nil : tag
        } label: {
            Text("#\(tag)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(store.tagFilter == tag ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(store.tagFilter == tag ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(store.filtered()) { skill in
                SkillCardView(skill: skill, store: store) {
                    appState.currentRoute = .skillDetail(slug: skill.slug)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text(hasAnyFilter ? "No skills match these filters." : "No skills yet.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text(hasAnyFilter
                 ? "Try clearing some filters above, or create a new skill."
                 : "Create your first skill, or wait for the auto-importer to pull from ~/.codex/skills and ~/.hermes/skills.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button { creatingNew = true } label: {
                Text("New skill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Skill card

private struct SkillCardView: View {
    let skill: SkillSpec
    @ObservedObject var store: SkillsStore
    let onTap: () -> Void

    @State private var hovered = false

    private var globalActive: Bool {
        store.isActive(slug: skill.slug, atScope: "global")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: skill.kind.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.gray.opacity(0.12))
                        )
                    Text(skill.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if globalActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.green.opacity(0.85))
                            )
                    }
                }
                Text(skill.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(skill.kind.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.gray.opacity(0.12))
                        )
                    if skill.builtin {
                        Text("Built-in")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                    }
                    if let importedFrom = skill.importedFrom {
                        Text("via \(importedFrom)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                    }
                    if skill.isInstance {
                        Text("instance")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                    }
                    Spacer(minLength: 4)
                    if !skill.syncTo.isEmpty {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(skill.syncTo.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered ? Color.gray.opacity(0.10) : Color.gray.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(hovered ? 0.20 : 0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - New skill sheet (placeholder; full editor in SkillDetailView)

private struct SkillNewSheet: View {
    @ObservedObject var store: SkillsStore
    let onClose: () -> Void

    @State private var slug: String = ""
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var kind: SkillKind = .procedure
    @State private var skillBody: String = ""

    var canSubmit: Bool {
        !slug.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New skill")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Kind").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Picker("", selection: $kind) {
                    ForEach(SkillKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Slug").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextField("e.g. my-cold-email", text: $slug)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextField("Display name shown in the catalog", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextField("One-liner shown on the card", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Body (markdown)").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                TextEditor(text: $skillBody)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray.opacity(0.20), lineWidth: 0.5)
                    )
            }

            HStack {
                Spacer()
                Button {
                    submit()
                } label: {
                    Text("Create")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canSubmit ? Color.accentColor : Color.gray)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submit() {
        guard canSubmit else { return }
        let skill = SkillSpec(
            slug: slug.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            version: "0.1.0",
            kind: kind,
            body: skillBody,
            scope: .global,
            tags: [],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: false,
            importedFrom: nil,
            author: "you",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        store.upsert(skill)
        onClose()
    }
}
