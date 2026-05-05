import SwiftUI
import AppKit

/// Right-sidebar file preview that mirrors the Codex Desktop reference:
/// a top tabs strip with the active file's name, a breadcrumb row with
/// `<folder> › <file>` and trailing actions, and a markdown body
/// rendered with `MarkdownDocumentView` for `.md` files (plain monospace
/// for everything else, placeholder for binaries / missing files).
struct FileViewerPanel: View {
    let path: String

    @EnvironmentObject var appState: AppState
    @State private var loaded: LoadedBody = .loading
    @State private var rawText: String = ""
    @State private var hoverMore = false
    @State private var hoverOpenExt = false
    @State private var hoverCopy = false
    @State private var copied = false

    private enum LoadedBody: Equatable {
        case loading
        case markdown([MarkdownBlock])
        case plain(String)
        case unavailable(String)
    }

    private var fileURL: URL { URL(fileURLWithPath: path) }
    private var fileName: String { fileURL.lastPathComponent }
    private var folderName: String {
        if let project = appState.selectedProject?.name, !project.isEmpty {
            return project
        }
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbRow
            divider
            content
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Preview of \(fileName)"))
        .task(id: path) { reload() }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
    }

    // MARK: - Breadcrumb row

    private var breadcrumbRow: some View {
        HStack(spacing: 6) {
            Text(folderName)
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.55))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(white: 0.35))
            Text(fileName)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(white: 0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            iconButton(systemName: "ellipsis",
                       size: 12,
                       hoverState: $hoverMore,
                       label: "More") { /* no-op for now */ }

            iconButton(systemName: "arrow.up.right.square",
                       size: 12,
                       hoverState: $hoverOpenExt,
                       label: "Open externally") {
                NSWorkspace.shared.open(fileURL)
            }

            iconButton(systemName: copied ? "checkmark" : "doc.on.doc",
                       size: 11,
                       hoverState: $hoverCopy,
                       label: "Copy contents") {
                copyContents()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch loaded {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .markdown(let blocks):
            ScrollView {
                MarkdownDocumentView(blocks: blocks)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

        case .plain(let raw):
            ScrollView {
                Text(raw)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Palette.textPrimary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .textSelection(.enabled)
            }

        case .unavailable(let reason):
            VStack(spacing: 8) {
                FileChipIcon(size: 30)
                    .foregroundColor(Color(white: 0.40))
                Text(reason)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(white: 0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconButton(systemName: String,
                            size: CGFloat,
                            hoverState: Binding<Bool>,
                            label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(Color(white: hoverState.wrappedValue ? 0.85 : 0.55))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hoverState.wrappedValue ? 0.06 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.12), value: hoverState.wrappedValue)
        .accessibilityLabel(label)
    }

    private func copyContents() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(rawText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }

    // MARK: - Loading

    private func reload() {
        loaded = .loading
        let url = fileURL
        Task.detached(priority: .userInitiated) {
            let result: (LoadedBody, String) = Self.load(url: url)
            await MainActor.run {
                self.loaded = result.0
                self.rawText = result.1
            }
        }
    }

    private static func load(url: URL) -> (LoadedBody, String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (.unavailable(
                String(localized: "File not found",
                       bundle: AppLocale.bundle,
                       locale: AppLocale.current)
            ), "")
        }
        guard let data = try? Data(contentsOf: url) else {
            return (.unavailable(
                String(localized: "Couldn't read file",
                       bundle: AppLocale.bundle,
                       locale: AppLocale.current)
            ), "")
        }
        if data.prefix(4096).contains(0) {
            return (.unavailable(
                String(localized: "Preview not available for binary files",
                       bundle: AppLocale.bundle,
                       locale: AppLocale.current)
            ), "")
        }
        guard let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .utf16) else {
            return (.unavailable(
                String(localized: "Couldn't decode file as text",
                       bundle: AppLocale.bundle,
                       locale: AppLocale.current)
            ), "")
        }
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return (.markdown(MarkdownParser.parse(raw)), raw)
        }
        return (.plain(raw), raw)
    }
}
