import SwiftUI
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

// Read-only viewer for the file pills under the assistant message. The
// iPhone has no filesystem access to the Mac's working tree, so the
// content is fetched on demand through the bridge: tapping a pill
// pushes this screen, the screen asks the store for the file, the
// store sends a `readFile` frame, and the Mac replies with a
// `fileSnapshot`. Markdown files render with the same
// `AssistantMarkdownView` we use for the assistant body so the look is
// continuous; everything else falls back to plain monospace.
struct FileViewerView: View {
    @Bindable var store: BridgeStore
    let path: String

    @Environment(\.dismiss) private var dismiss

    private var fileURL: URL { URL(fileURLWithPath: path) }
    private var fileName: String { fileURL.lastPathComponent }
    private var folderName: String {
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? "/" : parent
    }
    private var snapshot: BridgeStore.FileSnapshotState {
        store.fileSnapshots[path] ?? .loading
    }

    var body: some View {
        content
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task(id: path) {
                store.requestFile(path)
            }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            titlePill
            Spacer()
            GlassIconButton(systemName: "xmark", action: { dismiss() })
        }
    }

    private var titlePill: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(fileName)
                .font(BodyFont.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(folderName)
                .font(BodyFont.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: AppLayout.topBarPillHeight)
        .glassCapsule()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch snapshot {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let text, let isMarkdown):
            ScrollView {
                Group {
                    if isMarkdown {
                        AssistantMarkdownView(text: text)
                    } else {
                        plainBody(text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .textSelection(.enabled)
            }

        case .failed(let reason):
            VStack(spacing: 10) {
                Image(systemName: "doc.questionmark")
                    .font(BodyFont.system(size: 32, weight: .light))
                    .foregroundStyle(Palette.textTertiary)
                Text(reason)
                    .font(Typography.secondaryFont)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        }
    }

    private func plainBody(_ text: String) -> some View {
        Text(text)
            .font(Typography.monoFont)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(2)
    }

    // MARK: Actions

    private func copyContents() {
        guard case .loaded(let text, _) = snapshot else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        Haptics.success()
    }
}
