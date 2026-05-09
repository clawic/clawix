import SwiftUI

/// Center pane: search field + list of memory rows. When the search has
/// active results, the pane shows them ranked by score; otherwise it
/// renders the topic/scope-filtered notes.
struct MemoryListPane: View {

    @Binding var searchText: String
    let isSearching: Bool
    let searchResults: [ClawJSMemoryClient.SearchResult]
    let notes: [ClawJSMemoryClient.MemoryNote]
    @Binding var selectedNoteId: String?
    let onSearchSubmit: () -> Void
    let onSearchClear: () -> Void
    let onEdit: (ClawJSMemoryClient.MemoryNote) -> Void
    let onDelete: (ClawJSMemoryClient.MemoryNote) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            CardDivider()
            if showingSearchResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(searchResults) { result in
                            MemorySearchResultRow(
                                result: result,
                                isSelected: selectedNoteId == result.id,
                                onTap: { selectedNoteId = result.id }
                            )
                        }
                        if searchResults.isEmpty {
                            emptyState(title: "No matches",
                                       subtitle: "Try a different query or save more memories.")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(notes) { note in
                            MemoryListRow(
                                note: note,
                                isSelected: selectedNoteId == note.id,
                                onTap: { selectedNoteId = note.id },
                                onEdit: { onEdit(note) },
                                onDelete: { onDelete(note) }
                            )
                        }
                        if notes.isEmpty {
                            emptyState(title: "No memories",
                                       subtitle: "Agents can save memories with `claw memory save`, or add one with the New button above.")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            TextField("Search memories", text: $searchText)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(.white)
                .onSubmit(onSearchSubmit)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.7))
            }
            if !searchText.isEmpty {
                Button(action: onSearchClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var showingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(.white.opacity(0.7))
            Text(subtitle)
                .font(BodyFont.system(size: 11.5, wght: 400))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MemoryListRow: View {
    let note: ClawJSMemoryClient.MemoryNote
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(kindColor.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(typeLabel)
                            .font(BodyFont.system(size: 10.5, wght: 600))
                            .foregroundColor(kindColor)
                        if let scope = scopeLabel {
                            Text("·")
                                .foregroundColor(.white.opacity(0.3))
                            Text(scope)
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        if let date = dateLabel {
                            Text("·")
                                .foregroundColor(.white.opacity(0.3))
                            Text(date)
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    if !note.body.isEmpty {
                        Text(snippet(of: note.body))
                            .font(BodyFont.system(size: 11.5, wght: 400))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
            Divider()
            Button("Copy ID") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.id, forType: .string)
                #endif
            }
        }
    }

    private var kindColor: Color {
        switch note.semanticKind ?? note.type {
        case "decision": return .orange
        case "preference": return .pink
        case "observation": return .cyan
        case "lesson": return .yellow
        case "task_context": return .blue
        case "claim": return .purple
        default:
            return note.kind == "entity" ? .green : .blue
        }
    }

    private var typeLabel: String {
        let raw = note.semanticKind ?? note.type
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var scopeLabel: String? {
        if let p = note.scopeProject { return "@\(p)" }
        if let a = note.scopeAgent { return "agent:\(a)" }
        if let u = note.scopeUser { return "user:\(u)" }
        return nil
    }

    private var dateLabel: String? {
        let raw = note.lastEditedAt ?? note.updatedAt ?? note.createdAt
        guard let raw else { return nil }
        return String(raw.prefix(10))
    }

    private func snippet(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count > 110 { return String(oneLine.prefix(110)) + "…" }
        return oneLine
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.10) }
        if hovered    { return Color.white.opacity(0.045) }
        return .clear
    }
}

private struct MemorySearchResultRow: View {
    let result: ClawJSMemoryClient.SearchResult
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.2f", result.score))
                        .font(BodyFont.system(size: 10, wght: 500))
                        .foregroundColor(.white.opacity(0.4))
                }
                if !result.excerpt.isEmpty {
                    Text(result.excerpt)
                        .font(BodyFont.system(size: 11.5, wght: 400))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : (hovered ? Color.white.opacity(0.045) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

