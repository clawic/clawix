import SwiftUI

/// Read-only catalog of Skills on iOS. Mirrors the macOS catalog page
/// but adapted to NavigationStack. v1 is browse-only: list + detail.
/// Edit, activation, sync target toggles ship in v2 once the v6 bridge
/// frames land (currently macOS-only).
///
/// Entry point: a tab/sheet from the iOS root (wired in by the
/// integrator in `ClawixApp.swift` or wherever the iOS root lives).
struct SkillsListView: View {
    /// Seed catalog used until the bridge serves the user's real
    /// central library. Same shape as macOS to keep the eventual
    /// refactor of these models into a shared package painless.
    @State private var catalog: [SkillSpec] = SkillsSeedCatalogIOS.builtins
    @State private var query: String = ""
    @State private var kindFilter: SkillKind? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                kindFilterBar
                List(filtered) { skill in
                    NavigationLink(value: skill.slug) {
                        SkillRowView(skill: skill)
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: String.self) { slug in
                    if let skill = catalog.first(where: { $0.slug == slug }) {
                        SkillDetailReadOnlyView(skill: skill)
                    } else {
                        Text("Skill not found").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search skills")
        }
    }

    private var filtered: [SkillSpec] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.filter { skill in
            if let kindFilter, skill.kind != kindFilter { return false }
            guard !q.isEmpty else { return true }
            if skill.name.lowercased().contains(q) { return true }
            if skill.description.lowercased().contains(q) { return true }
            if skill.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var kindFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                kindChip(nil, label: "All")
                ForEach(SkillKind.allCases) { kind in
                    kindChip(kind, label: kind.label)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func kindChip(_ kind: SkillKind?, label: String) -> some View {
        Button {
            kindFilter = kind
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(kindFilter == kind ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(kindFilter == kind ? Color.accentColor : Color.gray.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct SkillRowView: View {
    let skill: SkillSpec
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: skill.kind.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.gray.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.system(size: 14, weight: .semibold))
                Text(skill.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Read-only detail

private struct SkillDetailReadOnlyView: View {
    let skill: SkillSpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: skill.kind.icon)
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.gray.opacity(0.14))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(.system(size: 18, weight: .semibold))
                        Text("\(skill.kind.label) · v\(skill.version)\(skill.author.map { " · by \($0)" } ?? "")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(skill.description)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)

                if !skill.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(skill.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.gray.opacity(0.12)))
                            }
                        }
                    }
                }

                bodyCard
            }
            .padding(16)
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(skill.body)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.gray.opacity(0.06))
                )
        }
    }
}

// MARK: - Seed catalog (iOS-local, deduplicated from macOS until we
// extract the catalog into a shared package).

enum SkillsSeedCatalogIOS {
    static let builtins: [SkillSpec] = [
        SkillSpec(
            slug: "ceo-pragmatic",
            name: "CEO · Pragmatic",
            description: "Founder/CEO mindset: outcomes over process, terse, prioritises what moves the needle this week.",
            version: "0.1.0",
            kind: .personality,
            body: "You operate as a pragmatic CEO. Bias to outcomes over process. Cut filler sentences. Single-CTA messages.",
            scope: .global,
            tags: ["leadership", "executive", "decision-making"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),
        SkillSpec(
            slug: "engineer-rigorous",
            name: "Engineer · Rigorous",
            description: "Senior engineer mindset: traces root causes, names tradeoffs, never ships without a verification step.",
            version: "0.1.0",
            kind: .personality,
            body: "You think like a senior staff engineer. Trace root causes. Name tradeoffs explicitly. Always propose a verification step before declaring work done.",
            scope: .global,
            tags: ["engineering", "debugging", "rigor"],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        ),
        SkillSpec(
            slug: "email-writing",
            name: "Email writing",
            description: "Compose an email with the right tone, length and intent. Configure once, save as your own.",
            version: "0.1.0",
            kind: .procedure,
            body: "Write an email matching: tone={{tone}}, length={{length}}, intent={{intent}}.",
            scope: .global,
            tags: ["email", "writing", "communication"],
            syncTo: [],
            syncMode: .symlink,
            params: [
                SkillParam(key: "tone", label: "Tone", type: .enumValue, options: ["formal", "neutral", "casual"], defaultValue: .string("formal"), required: true, prompt: nil),
                SkillParam(key: "length", label: "Length", type: .enumValue, options: ["short", "medium", "long"], defaultValue: .string("short"), required: true, prompt: nil),
                SkillParam(key: "intent", label: "Intent", type: .enumValue, options: ["cold", "follow-up", "reminder"], defaultValue: .string("cold"), required: true, prompt: nil)
            ],
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: true,
            importedFrom: nil,
            author: "clawjs",
            updatedAt: nil
        )
    ]
}
