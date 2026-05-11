import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// "References" landing screen. Drop zone for new references plus a
/// masonry of saved ones. From here the user can extract a candidate
/// palette out of an image reference and apply it to an existing style
/// or to a fresh duplicate of a builtin.
struct ReferencesHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var store: DesignStore = .shared

    @State private var query: String = ""
    @State private var selectedType: ReferenceType? = nil
    @State private var dropTargeted: Bool = false
    @State private var statusMessage: StatusMessage?
    @State private var pendingDelete: ReferenceManifest?
    @State private var addSheet: Bool = false
    @State private var extractTarget: ReferenceManifest?

    private struct StatusMessage: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case info, error }
    }

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
            if let status = statusMessage {
                statusBanner(status)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)
            }
            typeStrip
                .padding(.horizontal, 32)
                .padding(.bottom, 14)
            Divider().opacity(0.18)
            ScrollView {
                if filteredReferences.isEmpty {
                    dropZone
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                } else {
                    VStack(spacing: 18) {
                        dropZone
                            .padding(.horizontal, 32)
                            .padding(.top, 24)
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16, alignment: .top)
                        ], spacing: 16) {
                            ForEach(filteredReferences) { ref in
                                ReferenceCard(reference: ref,
                                              onDelete: { pendingDelete = ref },
                                              onExtract: { extractTarget = ref })
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    }
                }
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .onDrop(of: [.fileURL, .image, .url, .pdf], isTargeted: $dropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .alert(item: $pendingDelete) { ref in
            Alert(
                title: Text("Delete \"\(ref.name)\"?"),
                message: Text("The reference and its asset will be removed from disk and unlinked from any style."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteReference(ref)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $addSheet) {
            AddReferenceSheet { name, source, type, tags in
                addManualReference(name: name, source: source, type: type, tags: tags)
            }
        }
        .sheet(item: $extractTarget) { ref in
            ExtractPaletteSheet(reference: ref) { message, isError in
                statusMessage = StatusMessage(text: message, kind: isError ? .error : .info)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("References")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Inspiration library. Web pages, PDFs, images and screenshots feed your styles. Drag-and-drop files anywhere on this screen to add them.")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(2)
            }
            Spacer()
            Button {
                addSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add reference")
                        .font(BodyFont.system(size: 12.5, wght: 600))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
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
            typeChip(label: "All", active: selectedType == nil) { selectedType = nil }
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

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: dropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(dropTargeted ? Palette.pastelBlue : Color(white: 0.55))
            Text(dropTargeted ? "Release to ingest" : "Drop images, PDFs or web links here")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(dropTargeted ? Palette.pastelBlue : Color(white: 0.75))
            Text("Supports JPG, PNG, PDF and URLs. The reference is saved to your library and can be linked to any style.")
                .font(BodyFont.system(size: 11.5, wght: 400))
                .foregroundColor(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dropTargeted ? Palette.pastelBlue.opacity(0.10) : Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            dropTargeted ? Palette.pastelBlue.opacity(0.50) : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1, dash: dropTargeted ? [] : [4, 4])
                        )
                )
        )
    }

    private func statusBanner(_ status: StatusMessage) -> some View {
        let isError = status.kind == .error
        return HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isError ? Color(red: 0.95, green: 0.45, blue: 0.45) : Color(red: 0.40, green: 0.85, blue: 0.55))
            Text(status.text)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button {
                statusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((isError ? Color.red : Color.green).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke((isError ? Color.red : Color.green).opacity(0.30), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Drop + persistence

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    DispatchQueue.main.async {
                        if let url, error == nil {
                            ingest(localURL: url)
                        } else if let error {
                            statusMessage = StatusMessage(text: "Could not read drop: \(error.localizedDescription)", kind: .error)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        if let url, !url.isFileURL {
                            ingest(webURL: url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    DispatchQueue.main.async {
                        if let data, error == nil {
                            ingest(imageData: data, suggestedName: "Pasted image")
                        }
                    }
                }
            }
        }
        return accepted
    }

    private func ingest(localURL: URL) {
        let utiType = referenceType(forFileURL: localURL)
        let id = generateId(type: utiType, name: localURL.lastPathComponent)
        let manifest = ReferenceManifest(
            schemaVersion: 1,
            id: id,
            type: utiType,
            name: localURL.deletingPathExtension().lastPathComponent,
            source: localURL.path,
            tags: [],
            description: nil,
            styleIds: [],
            extractedStyle: nil,
            createdAt: nowIso(),
            updatedAt: nowIso()
        )
        do {
            let stored = try store.addReference(manifest, assetSource: localURL)
            statusMessage = StatusMessage(text: "Added \(stored.name)", kind: .info)
        } catch {
            statusMessage = StatusMessage(text: "Could not add reference: \(error.localizedDescription)", kind: .error)
        }
    }

    private func ingest(webURL: URL) {
        let id = generateId(type: .web, name: webURL.host ?? "web")
        let manifest = ReferenceManifest(
            schemaVersion: 1,
            id: id,
            type: .web,
            name: webURL.host ?? webURL.absoluteString,
            source: webURL.absoluteString,
            tags: [],
            description: nil,
            styleIds: [],
            extractedStyle: nil,
            createdAt: nowIso(),
            updatedAt: nowIso()
        )
        do {
            _ = try store.addReference(manifest)
            statusMessage = StatusMessage(text: "Added \(manifest.name)", kind: .info)
        } catch {
            statusMessage = StatusMessage(text: "Could not add reference: \(error.localizedDescription)", kind: .error)
        }
    }

    private func ingest(imageData: Data, suggestedName: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clawix-drop-\(UUID().uuidString).png")
        do {
            try imageData.write(to: tempURL)
            ingest(localURL: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            statusMessage = StatusMessage(text: "Could not save dropped image: \(error.localizedDescription)", kind: .error)
        }
    }

    private func addManualReference(name: String, source: String, type: ReferenceType, tags: [String]) {
        let id = generateId(type: type, name: name)
        let manifest = ReferenceManifest(
            schemaVersion: 1,
            id: id,
            type: type,
            name: name,
            source: source.isEmpty ? nil : source,
            tags: tags.isEmpty ? nil : tags,
            description: nil,
            styleIds: [],
            extractedStyle: nil,
            createdAt: nowIso(),
            updatedAt: nowIso()
        )
        do {
            _ = try store.addReference(manifest)
            statusMessage = StatusMessage(text: "Added \(manifest.name)", kind: .info)
        } catch {
            statusMessage = StatusMessage(text: "Could not add reference: \(error.localizedDescription)", kind: .error)
        }
    }

    private func deleteReference(_ ref: ReferenceManifest) {
        do {
            try store.deleteReference(ref)
            statusMessage = StatusMessage(text: "Deleted \(ref.name)", kind: .info)
        } catch {
            statusMessage = StatusMessage(text: "Could not delete: \(error.localizedDescription)", kind: .error)
        }
    }

    private func referenceType(forFileURL url: URL) -> ReferenceType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic": return .image
        case "mp4", "mov", "m4v": return .video
        default:
            if let utType = UTType(filenameExtension: ext) {
                if utType.conforms(to: .image) { return .image }
                if utType.conforms(to: .pdf) { return .pdf }
                if utType.conforms(to: .movie) { return .video }
            }
            return .snippet
        }
    }

    private func generateId(type: ReferenceType, name: String) -> String {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(40)
        let suffix = String(UUID().uuidString.split(separator: "-").first ?? "0000").lowercased().prefix(4)
        return "\(type.rawValue).\(slug.isEmpty ? type.rawValue : String(slug))-\(suffix)"
    }

    private func nowIso() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

// MARK: - Reference card

private struct ReferenceCard: View {
    let reference: ReferenceManifest
    let onDelete: () -> Void
    let onExtract: () -> Void

    @State private var hovered: Bool = false
    @ObservedObject private var store: DesignStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewBlock
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
                    if let styleIds = reference.styleIds, !styleIds.isEmpty {
                        Text("· linked to \(styleIds.count) style\(styleIds.count == 1 ? "" : "s")")
                            .font(BodyFont.system(size: 10.5, wght: 500))
                            .foregroundColor(Palette.pastelBlue)
                            .lineLimit(1)
                    } else if let tags = reference.tags, !tags.isEmpty {
                        Text("· \(tags.joined(separator: ", "))")
                            .font(BodyFont.system(size: 10.5, wght: 500))
                            .foregroundColor(Color(white: 0.45))
                            .lineLimit(1)
                    }
                }
            }
            if reference.type == .image {
                Button {
                    onExtract()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Extract palette")
                            .font(BodyFont.system(size: 11, wght: 600))
                    }
                    .foregroundColor(Palette.pastelBlue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.pastelBlue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
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
        .contextMenu {
            if reference.type == .image {
                Button("Extract palette", action: onExtract)
                Divider()
            }
            Button("Delete reference", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        if reference.type == .image, let nsImage = loadAssetImage() {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color(white: 0.65))
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 0.5)
            )
        }
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

    private func loadAssetImage() -> NSImage? {
        guard let asset = reference.asset else { return nil }
        let url = store.referenceDir(for: reference.id).appendingPathComponent(asset)
        return NSImage(contentsOf: url)
    }
}

// MARK: - Add reference sheet

private struct AddReferenceSheet: View {
    var onAdd: (String, String, ReferenceType, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var source: String = ""
    @State private var type: ReferenceType = .web
    @State private var tagsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add reference")
                .font(BodyFont.system(size: 18, wght: 600))
                .foregroundColor(Palette.textPrimary)
            field("Name", text: $name, placeholder: "Acme landing")
            field("Source (URL or path)", text: $source, placeholder: "https://example.com", monospaced: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("TYPE")
                    .font(BodyFont.system(size: 10, wght: 700))
                    .foregroundColor(Color(white: 0.55))
                    .tracking(0.5)
                Picker("", selection: $type) {
                    ForEach(ReferenceType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            field("Tags (comma-separated)", text: $tagsText, placeholder: "inspo, brand")
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(white: 0.80))
                Button("Add") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    onAdd(name, source, type, tags)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(Palette.pastelBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.pastelBlue.opacity(0.15))
                )
                .disabled(name.isEmpty)
                .opacity(name.isEmpty ? 0.5 : 1.0)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Palette.background)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(size: 12, design: .monospaced) : BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Extract palette sheet

private struct ExtractPaletteSheet: View {
    let reference: ReferenceManifest
    var onComplete: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: DesignStore = .shared

    @State private var result: PaletteExtractor.Result?
    @State private var loadError: String?
    @State private var selectedStyleId: String = ""
    @State private var newStyleName: String = ""
    @State private var applyMode: ApplyMode = .duplicate

    private enum ApplyMode: String, CaseIterable, Identifiable {
        case duplicate, overwrite
        var id: String { rawValue }
        var label: String {
            switch self {
            case .duplicate: return "Apply to a new style"
            case .overwrite: return "Overwrite an existing style"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.pastelBlue)
                Text("Extract palette from \"\(reference.name)\"")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
            }
            if let error = loadError {
                Text(error)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Color(red: 0.95, green: 0.50, blue: 0.50))
            }
            if let result = result {
                paletteRow(result)
                rolesRow(result)
                Divider().opacity(0.18)
                applyPicker
                if applyMode == .duplicate {
                    field("New style name", text: $newStyleName, placeholder: "Acme · derived")
                } else {
                    nonBuiltinPicker
                }
            } else if loadError == nil {
                ProgressView("Sampling image…")
                    .controlSize(.small)
                    .foregroundColor(Color(white: 0.75))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(white: 0.80))
                Button("Apply") { apply() }
                    .buttonStyle(.plain)
                    .foregroundColor(Palette.pastelBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.pastelBlue.opacity(0.15))
                    )
                    .disabled(result == nil || !canApply)
                    .opacity(result == nil || !canApply ? 0.5 : 1.0)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Palette.background)
        .onAppear { runExtraction() }
    }

    private var canApply: Bool {
        switch applyMode {
        case .duplicate: return !newStyleName.isEmpty
        case .overwrite: return !selectedStyleId.isEmpty
        }
    }

    private func paletteRow(_ result: PaletteExtractor.Result) -> some View {
        HStack(spacing: 4) {
            ForEach(result.palette, id: \.self) { hex in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .help(hex)
            }
        }
    }

    private func rolesRow(_ result: PaletteExtractor.Result) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)], spacing: 8) {
            roleChip("bg", result.bg)
            roleChip("surface", result.surface)
            roleChip("fg", result.fg)
            roleChip("fg-muted", result.fgMuted)
            roleChip("accent", result.accent)
            roleChip("accent-2", result.accent2)
            roleChip("border", result.border)
        }
    }

    private func roleChip(_ label: String, _ hex: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(hex.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var applyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPLY")
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            Picker("", selection: $applyMode) {
                ForEach(ApplyMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var nonBuiltinPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TARGET STYLE")
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            let candidates = store.styles.filter { $0.builtin != true }
            if candidates.isEmpty {
                Text("No editable styles. Duplicate a builtin first or pick \"Apply to a new style\" above.")
                    .font(BodyFont.system(size: 12, wght: 400))
                    .foregroundColor(Color(white: 0.55))
            } else {
                Picker("", selection: $selectedStyleId) {
                    Text("Choose…").tag("")
                    ForEach(candidates) { style in
                        Text(style.name).tag(style.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 700))
                .foregroundColor(Color(white: 0.55))
                .tracking(0.5)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.border, lineWidth: 0.5)
                        )
                )
        }
    }

    private func runExtraction() {
        guard let asset = reference.asset else {
            loadError = "This reference has no local asset to sample."
            return
        }
        let url = store.referenceDir(for: reference.id).appendingPathComponent(asset)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let r = try PaletteExtractor.extract(from: url)
                DispatchQueue.main.async {
                    self.result = r
                    self.newStyleName = "\(reference.name) · derived"
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    private func apply() {
        guard let result else { return }
        let baseStyle: StyleManifest
        switch applyMode {
        case .duplicate:
            let seed = store.styles.first { $0.id == "claw" } ?? store.styles.first
            guard let source = seed else {
                onComplete("No source style available.", true)
                dismiss(); return
            }
            do {
                let newId = try store.duplicateStyle(source, newName: newStyleName)
                guard var copy = store.style(id: newId) else {
                    onComplete("Could not load duplicated style.", true)
                    dismiss(); return
                }
                copy = result.apply(onto: copy)
                copy.references = Array(Set((copy.references ?? []) + [reference.id]))
                try store.updateStyle(copy)
                try store.toggleReferenceLink(referenceId: reference.id, styleId: newId)
                onComplete("Created \(newStyleName) from extracted palette.", false)
                dismiss()
            } catch {
                onComplete("Could not create style: \(error.localizedDescription)", true)
                dismiss()
            }
            return
        case .overwrite:
            guard let target = store.style(id: selectedStyleId) else {
                onComplete("Target style not found.", true)
                dismiss(); return
            }
            baseStyle = target
        }
        do {
            var manifest = result.apply(onto: baseStyle)
            manifest.references = Array(Set((manifest.references ?? []) + [reference.id]))
            try store.updateStyle(manifest)
            try store.toggleReferenceLink(referenceId: reference.id, styleId: baseStyle.id)
            onComplete("Applied palette to \(baseStyle.name).", false)
            dismiss()
        } catch {
            onComplete("Could not apply: \(error.localizedDescription)", true)
            dismiss()
        }
    }
}
