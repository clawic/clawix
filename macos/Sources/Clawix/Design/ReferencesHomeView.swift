import SwiftUI

/// "References" landing screen. Grid of inspiration items (web, pdf,
/// image, screenshot, snippet). Phase 2 ships read-only with a drop
/// zone hint; drag-and-drop ingestion lands in Phase 3 alongside
/// editing.
struct ReferencesHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var query: String = ""
    @State private var selectedType: ReferenceType? = nil

    private var filteredReferences: [ReferenceManifest] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.references.filter { ref in
            if let selectedType, ref.type != selectedType { return false }
            if trimmed.isEmpty { return true }
            let haystack = "\(ref.name) \(ref.source ?? "") \((ref.tags ?? []).joined(separator: " "))".lowercased()
            return haystack.contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 12)
            typeStrip
                .padding(.horizontal, 32)
                .padding(.bottom, 14)
            Divider().opacity(0.18)
            ScrollView {
                if filteredReferences.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16, alignment: .top)
                    ], spacing: 16) {
                        ForEach(filteredReferences) { ref in
                            ReferenceCard(reference: ref)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("References")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Inspiration library. Web pages, PDFs, images and screenshots that feed your styles.")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.55))
                TextField("Search references", text: $query)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.94))
                    .frame(width: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.border, lineWidth: 0.5)
                    )
            )
        }
    }

    private var typeStrip: some View {
        HStack(spacing: 8) {
            typeChip(label: "All", active: selectedType == nil) {
                selectedType = nil
            }
            ForEach(ReferenceType.allCases) { type in
                let count = store.references.filter { $0.type == type }.count
                typeChip(label: "\(type.displayName) (\(count))", active: selectedType == type) {
                    selectedType = (selectedType == type) ? nil : type
                }
                .opacity(count == 0 ? 0.4 : 1.0)
            }
            Spacer()
        }
    }

    private func typeChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(active ? Palette.textPrimary : Color(white: 0.65))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("No references yet")
                .font(BodyFont.system(size: 16, wght: 500))
                .foregroundColor(Color(white: 0.75))
            Text("Drop a web link, an image or a PDF here to start your inspiration library. Drag-and-drop ingestion lands with editing in the next release.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(white: 0.50))
                Text("Drop zone — read-only in this release")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Color(white: 0.50))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
    }
}

private struct ReferenceCard: View {
    let reference: ReferenceManifest

    @State private var hovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color(white: 0.65))
            }
            .frame(height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(reference.name)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                if let source = reference.source {
                    Text(source)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.55))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(reference.type.displayName)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(Color(white: 0.55))
                    if let tags = reference.tags, !tags.isEmpty {
                        Text("· \(tags.joined(separator: ", "))")
                            .font(BodyFont.system(size: 10.5, wght: 500))
                            .foregroundColor(Color(white: 0.45))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovered ? Palette.cardHover : Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.border, lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
    }

    private var icon: String {
        switch reference.type {
        case .web:        return "globe"
        case .pdf:        return "doc.richtext"
        case .image:      return "photo"
        case .video:      return "play.rectangle"
        case .screenshot: return "camera.viewfinder"
        case .snippet:    return "chevron.left.forwardslash.chevron.right"
        }
    }
}
