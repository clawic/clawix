import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Adaptive 3-pane Drive screen: folder breadcrumbs + content grid/list +
/// optional detail pane. Content view chooses grid (Photos-style) when
/// the folder is mostly images, list (Finder-style) otherwise. Decision
/// is per-folder and remembered in `@SceneStorage`.
struct DriveScreen: View {

    enum Mode: Equatable {
        case admin
        case photos
        case documents
        case recent
        case folder(String)
    }

    @StateObject private var manager = DriveManager()
    @State private var selectedItemId: String? = nil
    @State private var isUploadDialogPresented = false
    @State private var duplicatePromptForExisting: ClawJSDriveClient.DriveItem? = nil
    @State private var pendingUploadURL: URL? = nil
    @State private var viewMode: ViewMode = .auto

    let mode: Mode

    enum ViewMode: String, CaseIterable {
        case auto, grid, list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            applyMode()
            manager.boot()
            DriveTools.bind(manager)
        }
        .onChange(of: mode) { _, _ in applyMode() }
        .onReceive(NotificationCenter.default.publisher(for: .driveQuickUploadRequested)) { _ in
            if canUpload {
                isUploadDialogPresented = true
            }
        }
        .alert("Already in Drive", isPresented: Binding(
            get: { duplicatePromptForExisting != nil },
            set: { if !$0 { duplicatePromptForExisting = nil } }
        )) {
            Button("Replace") {
                if let url = pendingUploadURL {
                    Task { @MainActor in
                        _ = await manager.upload(fileURL: url, parentId: manager.currentParentId, allowOverwrite: true)
                        duplicatePromptForExisting = nil
                    }
                }
            }
            Button("Keep both") {
                if let url = pendingUploadURL {
                    Task { @MainActor in
                        _ = await manager.upload(fileURL: url, parentId: manager.currentParentId, allowOverwrite: true)
                        duplicatePromptForExisting = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { duplicatePromptForExisting = nil }
        } message: {
            if let existing = duplicatePromptForExisting {
                Text("\"\(existing.name)\" with the same content already exists in your Drive.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(headerTitle).font(.system(size: 20, weight: .semibold))
            Spacer()
            TextField("Search", text: Binding(get: { manager.query }, set: { manager.setQuery($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Button { isUploadDialogPresented = true } label: {
                Label("Upload", systemImage: "plus")
            }
            .disabled(!canUpload)
        }
        .padding(12)
        .fileImporter(isPresented: $isUploadDialogPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    pendingUploadURL = url
                    Task { @MainActor in
                        let result = await manager.upload(fileURL: url, parentId: manager.currentParentId)
                        if case .failure(let error) = result, case .duplicateExists(let existing) = error {
                            duplicatePromptForExisting = existing
                        } else {
                            pendingUploadURL = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .loading, .authenticating:
            ProgressView("Connecting to Drive...").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ContentUnavailableView("Drive unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unauthenticated, .ready:
            HSplitView {
                folderTree
                    .frame(
                        minWidth: 220,
                        idealWidth: 260,
                        maxWidth: 320,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let id = selectedItemId, let item = visibleItems.first(where: { $0.id == id }) {
                    DriveItemDetailPane(item: item, manager: manager)
                        .frame(
                            minWidth: 280,
                            idealWidth: 320,
                            maxWidth: 420,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var folderTree: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(["my-drive", "recent", "starred", "shared", "trash"], id: \.self) { view in
                Button {
                    manager.setView(view)
                } label: {
                    HStack {
                        Image(systemName: iconFor(view))
                        Text(label(for: view))
                        Spacer()
                        Text(String(count(for: view)))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(manager.currentView == view ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.vertical, 6)
            Text("Breadcrumbs").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            ForEach(manager.breadcrumbs, id: \.id) { crumb in
                Button {
                    manager.setParent(crumb.id)
                } label: {
                    Text(crumb.name).padding(.horizontal, 10)
                }.buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private var contentBody: some View {
        Group {
            if visibleItems.isEmpty {
                ContentUnavailableView(
                    "Empty",
                    systemImage: "tray",
                    description: Text("Drag a file here or click Upload."),
                )
            } else {
                if effectiveLayout == .grid {
                    DriveGridView(items: visibleItems, selectedId: $selectedItemId, manager: manager)
                } else {
                    DriveListView(items: visibleItems, selectedId: $selectedItemId, manager: manager)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard canUpload else { return false }
            handleDrop(providers: providers)
            return true
        }
    }

    private var effectiveLayout: ViewMode {
        if viewMode != .auto { return viewMode }
        // Auto: grid when ≥70% of items are images.
        let images = visibleItems.filter { isImage($0) }.count
        return visibleItems.count > 0 && Double(images) / Double(visibleItems.count) >= 0.7 ? .grid : .list
    }

    private var visibleItems: [ClawJSDriveClient.DriveItem] {
        switch mode {
        case .photos:
            return manager.items.filter { $0.kind == "folder" || isImage($0) }
        case .documents:
            return manager.items.filter { $0.kind == "folder" || !isImage($0) }
        case .admin, .recent, .folder:
            return manager.items
        }
    }

    private func isImage(_ item: ClawJSDriveClient.DriveItem) -> Bool {
        (item.mimeType ?? "").starts(with: "image/")
    }

    private var headerTitle: String {
        switch mode {
        case .photos: return "Photos"
        case .documents: return "Documents"
        case .recent: return "Recent"
        case .admin: return "Drive"
        case .folder: return manager.breadcrumbs.last?.name ?? "Folder"
        }
    }

    private var canUpload: Bool {
        if case .ready = manager.state { return true }
        return false
    }

    private func applyMode() {
        selectedItemId = nil
        switch mode {
        case .photos:
            manager.setView("my-drive")
            // Photos timeline filters by mime client-side via grid layout decision.
        case .documents:
            manager.setView("my-drive")
        case .recent:
            manager.setView("recent")
        case .admin:
            manager.setView("my-drive")
            manager.setParent(nil)
        case .folder(let id):
            manager.setView("my-drive")
            manager.setParent(id)
        }
    }

    private func iconFor(_ view: String) -> String {
        switch view {
        case "my-drive": return "internaldrive"
        case "recent": return "clock"
        case "starred": return "star"
        case "shared": return "person.2"
        case "trash": return "trash"
        default: return "folder"
        }
    }

    private func label(for view: String) -> String {
        switch view {
        case "my-drive": return "My Drive"
        case "recent": return "Recent"
        case "starred": return "Starred"
        case "shared": return "Shared"
        case "trash": return "Trash"
        default: return view
        }
    }

    private func count(for view: String) -> Int {
        switch view {
        case "my-drive": return manager.counts.myDrive
        case "recent": return manager.counts.recent
        case "starred": return manager.counts.starred
        case "shared": return manager.counts.shared
        case "trash": return manager.counts.trash
        default: return 0
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in
                        pendingUploadURL = url
                        let result = await manager.upload(fileURL: url, parentId: manager.currentParentId)
                        if case .failure(let error) = result, case .duplicateExists(let existing) = error {
                            duplicatePromptForExisting = existing
                        } else {
                            pendingUploadURL = nil
                        }
                    }
                }
            }
        }
    }
}

struct DriveGridView: View {
    let items: [ClawJSDriveClient.DriveItem]
    @Binding var selectedId: String?
    let manager: DriveManager

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    DriveItemTile(item: item, manager: manager, isSelected: selectedId == item.id)
                        .onTapGesture(count: 2) {
                            if item.kind == "folder" { manager.setParent(item.id) }
                        }
                        .onTapGesture { selectedId = item.id }
                }
            }
            .padding(12)
        }
    }
}

struct DriveListView: View {
    let items: [ClawJSDriveClient.DriveItem]
    @Binding var selectedId: String?
    let manager: DriveManager

    var body: some View {
        Table(items, selection: $selectedId) {
            TableColumn("Name") { item in
                HStack {
                    Image(systemName: item.kind == "folder" ? "folder.fill" : "doc")
                        .foregroundStyle(.secondary)
                    Text(item.name)
                }
            }
            TableColumn("Modified") { item in Text(formatRelative(item.updatedAt)).foregroundStyle(.secondary) }
            TableColumn("Size") { item in Text(formatSize(item.sizeBytes)).foregroundStyle(.secondary) }
        }
    }

    private func formatRelative(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes == 0 { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct DriveItemTile: View {
    let item: ClawJSDriveClient.DriveItem
    let manager: DriveManager
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                if let img = thumbnail {
                    Image(nsImage: img).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: item.kind == "folder" ? "folder.fill" : "photo")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            Text(item.name).lineLimit(2).multilineTextAlignment(.center).font(.caption)
        }
        .task(id: item.id) {
            if (item.mimeType ?? "").starts(with: "image/") {
                if let data = await manager.thumbnail(for: item.id, size: 256), let img = NSImage(data: data) {
                    thumbnail = img
                }
            }
        }
    }
}

struct DriveItemDetailPane: View {
    let item: ClawJSDriveClient.DriveItem
    let manager: DriveManager
    @State private var exif: ClawJSDriveClient.ExifRecord?
    @State private var shares: ClawJSDriveClient.AllSharesResponse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name).font(.headline)
                Text(item.mimeType ?? item.kind).foregroundStyle(.secondary)
                if item.sizeBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file)).font(.caption)
                }
                Divider()
                if let exif {
                    Group {
                        Text("EXIF").font(.subheadline.bold())
                        if let taken = exif.takenAt { Text("Taken: \(taken)") }
                        if let cam = exif.cameraModel { Text("Camera: \(cam)") }
                        if let lat = exif.latitude, let lon = exif.longitude {
                            Text(String(format: "GPS: %.4f, %.4f", lat, lon))
                        }
                        if let w = exif.width, let h = exif.height {
                            Text("Size: \(w)×\(h)")
                        }
                    }
                }
                Divider()
                Text("Sharing").font(.subheadline.bold())
                HStack {
                    Button("Share via Tailnet") {
                        Task { _ = try? await manager.client.createTailnetShare(item.id); shares = try? await manager.client.listAllShares(item.id) }
                    }
                    Button("Public link") {
                        Task { _ = try? await manager.client.createTunnelShare(item.id); shares = try? await manager.client.listAllShares(item.id) }
                    }
                    Button("Agent token") {
                        Task {
                            _ = try? await manager.client.createAgentShare(item.id, capabilityKind: "drive.item.read", ttlMinutes: 10, reason: nil, agentName: "agent")
                            shares = try? await manager.client.listAllShares(item.id)
                        }
                    }
                }
                if let shares {
                    if !shares.tailnet.isEmpty { Text("Tailnet: \(shares.tailnet.count)") }
                    if !shares.tunnel.isEmpty { Text("Tunnels: \(shares.tunnel.count)") }
                    if !shares.agent.isEmpty { Text("Agents: \(shares.agent.count)") }
                }
                Divider()
                HStack {
                    Button("Trash", role: .destructive) {
                        Task { @MainActor in await manager.trash(item.id) }
                    }
                    Button(item.starred ? "Unstar" : "Star") {
                        Task { @MainActor in await manager.star(item.id, starred: !item.starred) }
                    }
                }
            }
            .padding(16)
        }
        .task(id: item.id) {
            self.exif = try? await manager.client.getExif(item.id)
            self.shares = try? await manager.client.listAllShares(item.id)
        }
    }
}
