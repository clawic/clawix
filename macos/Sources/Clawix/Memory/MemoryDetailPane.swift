import SwiftUI

/// Right pane: full memory detail with title, metadata pills, body, tags,
/// and Edit/Delete actions. When `note` is nil, shows a placeholder.
struct MemoryDetailPane: View {

    let note: ClawJSMemoryClient.MemoryNote?
    let onEdit: (ClawJSMemoryClient.MemoryNote) -> Void
    let onDelete: (ClawJSMemoryClient.MemoryNote) -> Void

    @State private var showOriginal = false

    var body: some View {
        Group {
            if let note {
                detail(for: note)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.25))
            Text("Select a memory")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(for note: ClawJSMemoryClient.MemoryNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(note: note)
                pillsRow(note: note)
                if !displayBody(for: note).isEmpty {
                    Text(displayBody(for: note))
                        .font(BodyFont.system(size: 13.5, wght: 400))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if !note.tags.isEmpty {
                    tagsRow(note.tags)
                }
                if note.originalBody != nil {
                    Toggle(isOn: $showOriginal) {
                        Text("Show original (before user edit)")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
                actionsRow(note: note)
            }
            .padding(20)
        }
    }

    private func header(note: ClawJSMemoryClient.MemoryNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(BodyFont.system(size: 19, wght: 700))
                .foregroundColor(.white)
                .textSelection(.enabled)
            Text(note.id)
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(.white.opacity(0.4))
                .textSelection(.enabled)
        }
    }

    private func pillsRow(note: ClawJSMemoryClient.MemoryNote) -> some View {
        MemoryFlowLayout(spacing: 6) {
            pill(text: typeLabel(note), color: .blue)
            pill(text: kindLabel(note), color: .gray)
            if let project = note.scopeProject { pill(text: "@\(project)", color: .green) }
            if let agent = note.scopeAgent { pill(text: "agent:\(agent)", color: .purple) }
            if let user = note.scopeUser { pill(text: "user:\(user)", color: .pink) }
            if let createdBy = note.createdBy { pill(text: "by \(createdBy)", color: .orange) }
            if let updated = note.lastEditedAt ?? note.updatedAt {
                pill(text: String(updated.prefix(10)), color: .gray)
            }
        }
    }

    private func tagsRow(_ tags: [String]) -> some View {
        MemoryFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
            }
        }
    }

    private func actionsRow(note: ClawJSMemoryClient.MemoryNote) -> some View {
        HStack(spacing: 8) {
            Button(action: { onEdit(note) }) {
                Text("Edit")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)

            Button(action: { onDelete(note) }) {
                Text("Delete")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.red.opacity(0.4), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func displayBody(for note: ClawJSMemoryClient.MemoryNote) -> String {
        if showOriginal, let original = note.originalBody { return original }
        return note.body
    }

    private func typeLabel(_ note: ClawJSMemoryClient.MemoryNote) -> String {
        let raw = note.semanticKind ?? note.type
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func kindLabel(_ note: ClawJSMemoryClient.MemoryNote) -> String {
        note.kind == "entity" ? "Entity" : "Memory"
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(color.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(color.opacity(0.4), lineWidth: 0.5)
            )
    }
}

/// Lightweight horizontal flow layout. Wrap children to the next line
/// when they overflow the container width. Used for pill rows.
struct MemoryFlowLayout: Layout {

    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = compute(subviews: subviews, maxWidth: maxWidth)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + max(0, CGFloat(rows.count - 1) * lineSpacing)
        let totalWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = compute(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func compute(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.width + (current.indices.isEmpty ? 0 : spacing) + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            if !current.indices.isEmpty { current.width += spacing }
            current.indices.append(index)
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
