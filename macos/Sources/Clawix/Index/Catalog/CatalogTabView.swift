import SwiftUI

/// Three-pane catalog: Type sidebar (left, 220pt), entity list/grid
/// (flex), detail pane (right, 380pt). Mirrors `DatabaseScreen` layout.
struct CatalogTabView: View {
    @ObservedObject var manager: IndexManager
    @State private var displayMode: DisplayMode = .grid
    @State private var selectedEntityId: String?
    @AppStorage("clawix.index.catalog.displayMode") private var storedDisplayMode: String = DisplayMode.grid.rawValue

    enum DisplayMode: String, Hashable {
        case grid
        case list
    }

    var body: some View {
        HStack(spacing: 0) {
            TypeSidebar(manager: manager)
                .frame(width: 220)
                .background(Color.black.opacity(0.18))

            CardDivider()

            VStack(spacing: 0) {
                CatalogToolbar(manager: manager, displayMode: $displayMode)
                CardDivider()
                EntityListGrid(
                    manager: manager,
                    displayMode: displayMode,
                    selectedEntityId: $selectedEntityId
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CardDivider()

            EntityDetailPane(manager: manager, entityId: selectedEntityId)
                .frame(width: 400)
                .background(Color.black.opacity(0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let restored = DisplayMode(rawValue: storedDisplayMode) {
                displayMode = restored
            }
        }
        .onChange(of: displayMode) { _, newValue in
            storedDisplayMode = newValue.rawValue
        }
    }
}

private struct TypeSidebar: View {
    @ObservedObject var manager: IndexManager

    private var allTotal: Int {
        manager.typeCounts.values.reduce(0, +)
    }

    private var canonicalEntries: [(IndexTypeMeta, Int)] {
        IndexTypeCatalog.canonicalOrder.compactMap { typeName in
            (IndexTypeCatalog.meta(for: typeName), manager.typeCounts[typeName] ?? 0)
        }
    }

    private var customEntries: [(IndexTypeMeta, Int)] {
        manager.types
            .filter { !$0.canonical }
            .map { (IndexTypeCatalog.meta(for: $0.name), manager.typeCounts[$0.name] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                TypeRow(
                    title: "All",
                    lucideName: "rectangle.stack",
                    count: allTotal,
                    isSelected: manager.selectedTypeFilter == nil,
                    accent: .white.opacity(0.7)
                ) {
                    manager.selectedTypeFilter = nil
                    Task { await manager.loadEntities() }
                }
                .padding(.top, 8)

                CatalogSectionHeader(title: "CANONICAL TYPES")
                ForEach(canonicalEntries, id: \.0.typeName) { meta, count in
                    TypeRow(
                        title: meta.displayName,
                        lucideName: meta.lucideName,
                        count: count,
                        isSelected: manager.selectedTypeFilter == meta.typeName,
                        accent: meta.accent
                    ) {
                        manager.selectedTypeFilter = meta.typeName
                        Task { await manager.loadEntities() }
                    }
                }

                if !customEntries.isEmpty {
                    CatalogSectionHeader(title: "CUSTOM TYPES")
                    ForEach(customEntries, id: \.0.typeName) { meta, count in
                        TypeRow(
                            title: meta.displayName,
                            lucideName: meta.lucideName,
                            count: count,
                            isSelected: manager.selectedTypeFilter == meta.typeName,
                            accent: meta.accent
                        ) {
                            manager.selectedTypeFilter = meta.typeName
                            Task { await manager.loadEntities() }
                        }
                    }
                }

                if !manager.tags.isEmpty {
                    CatalogSectionHeader(title: "TAGS")
                    ForEach(manager.tags) { tag in
                        TagRow(tag: tag)
                    }
                }

                if !manager.collections.isEmpty {
                    CatalogSectionHeader(title: "COLLECTIONS")
                    ForEach(manager.collections) { collection in
                        CollectionRow(collection: collection)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .thinScrollers()
    }
}

private struct CatalogSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(BodyFont.system(size: 10, wght: 600))
            .kerning(0.6)
            .foregroundColor(.white.opacity(0.40))
            .padding(.top, 14)
            .padding(.bottom, 4)
            .padding(.horizontal, 10)
    }
}

private struct TypeRow: View {
    let title: String
    let lucideName: String
    let count: Int
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                LucideIcon.auto(lucideName, size: 14)
                    .foregroundColor(accent)
                    .frame(width: 18)
                Text(title)
                    .font(BodyFont.system(size: 13, wght: isSelected ? 600 : 500))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.78))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : (hovered ? Color.white.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct TagRow: View {
    let tag: ClawJSIndexClient.Tag

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(parsedColor)
                .frame(width: 10, height: 10)
            Text(tag.name)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(.white.opacity(0.78))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var parsedColor: Color {
        if let raw = tag.color, raw.hasPrefix("#") {
            let hex = String(raw.dropFirst())
            if let value = UInt64(hex, radix: 16) {
                let r = Double((value >> 16) & 0xff) / 255.0
                let g = Double((value >> 8) & 0xff) / 255.0
                let b = Double(value & 0xff) / 255.0
                return Color(red: r, green: g, blue: b)
            }
        }
        return Color(white: 0.55)
    }
}

private struct CollectionRow: View {
    let collection: ClawJSIndexClient.Collection
    var body: some View {
        HStack(spacing: 10) {
            LucideIcon.auto("square.stack.3d.up", size: 13)
                .foregroundColor(.white.opacity(0.70))
                .frame(width: 18)
            Text(collection.name)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(.white.opacity(0.78))
            Spacer()
            Text("\(collection.memberCount)")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

private struct CatalogToolbar: View {
    @ObservedObject var manager: IndexManager
    @Binding var displayMode: CatalogTabView.DisplayMode

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                LucideIcon.auto("magnifyingglass", size: 12)
                    .foregroundColor(.white.opacity(0.5))
                TextField("", text: $manager.fullTextQuery, prompt: Text("Search entities…").foregroundColor(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12.5, wght: 400))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            Spacer()

            SlidingSegmented<CatalogTabView.DisplayMode>(
                selection: $displayMode,
                options: [(.grid, "Grid"), (.list, "List")],
                height: 26,
                fontSize: 11
            )
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct EntityListGrid: View {
    @ObservedObject var manager: IndexManager
    let displayMode: CatalogTabView.DisplayMode
    @Binding var selectedEntityId: String?

    private var filteredEntities: [ClawJSIndexClient.Entity] {
        let trimmed = manager.fullTextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return manager.entities }
        return manager.entities.filter { entity in
            let haystack = "\(entity.title ?? "") \(entity.sourceUrl ?? "") \(entity.identityKey)"
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        if filteredEntities.isEmpty {
            IndexEmptyState(
                title: "No entities yet",
                systemImage: "magnifyingglass",
                description: "Create a Search and run it. The agent's MCP tools will upsert entities here."
            )
        } else {
            ScrollView {
                Group {
                    if displayMode == .grid {
                        gridView
                    } else {
                        listView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .thinScrollers()
        }
    }

    private var gridView: some View {
        let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredEntities) { entity in
                IndexEntityCard(entity: entity) {
                    selectedEntityId = entity.id
                }
                .frame(height: cardHeight(for: entity))
            }
        }
    }

    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredEntities) { entity in
                EntityListRow(entity: entity, isSelected: selectedEntityId == entity.id) {
                    selectedEntityId = entity.id
                }
                CardDivider()
            }
        }
    }

    private func cardHeight(for entity: ClawJSIndexClient.Entity) -> CGFloat {
        switch IndexTypeCatalog.meta(for: entity.typeName).kind {
        case .media: return 240
        case .text: return 186
        case .data: return 174
        }
    }
}

private struct EntityListRow: View {
    let entity: ClawJSIndexClient.Entity
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                LucideIcon.auto(IndexTypeCatalog.meta(for: entity.typeName).lucideName, size: 14)
                    .foregroundColor(IndexTypeCatalog.meta(for: entity.typeName).accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.title ?? entity.sourceUrl ?? entity.identityKey)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(entity.typeName.capitalized)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(IndexTypeCatalog.meta(for: entity.typeName).accent)
                        Text("·")
                            .foregroundColor(.white.opacity(0.30))
                        Text(domain(from: entity.sourceUrl))
                            .font(BodyFont.system(size: 11, wght: 400))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let price = entity.data["price"]?.asNumber {
                    Text(String(format: "%.2f", price))
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.white.opacity(0.08) : (hovered ? Color.white.opacity(0.03) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private func domain(from url: String?) -> String {
        guard let url, let parsed = URL(string: url), let host = parsed.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}
