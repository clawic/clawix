import SwiftUI
import AppKit
import ImageIO

// MARK: - Composer attachment chips

struct ComposerAttachmentRow: View {
    let attachments: [ComposerAttachment]
    let onRemove: (UUID) -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    ComposerAttachmentChip(
                        attachment: att,
                        onRemove: { onRemove(att.id) },
                        onOpen: {
                            if att.isImage {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    appState.imagePreviewURL = att.url
                                }
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void
    let onOpen: () -> Void

    @State private var hovered = false
    @State private var removeHovered = false

    var body: some View {
        HStack(spacing: attachment.isImage ? 6 : 4) {
            HStack(spacing: attachment.isImage ? 6 : 4) {
                iconView
                Text(attachment.filename)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .help(attachment.isImage ? L10n.t("Click to enlarge") : attachment.url.path)
            Button(action: onRemove) {
                LucideIcon(.x, size: 11)
                    .foregroundColor(Color(white: removeHovered ? 1.0 : 0.78))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0.001)
            .accessibilityLabel(Text("\(L10n.t("Remove attachment")): \(attachment.filename)"))
            .accessibilityIdentifier("composer-attachment-remove-\(attachment.id.uuidString)")
            .accessibilityAction(named: Text(L10n.t("Remove attachment"))) {
                onRemove()
            }
            .onHover { removeHovered = $0 }
            .help(L10n.t("Remove attachment"))
            .layoutPriority(1)
        }
        .padding(.leading, attachment.isImage ? 9 : 7)
        .padding(.trailing, hovered ? 7 : 11)
        .padding(.vertical, 5)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.03 : 0))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .animation(.easeOut(duration: 0.14), value: hovered)
        .contentShape(Capsule(style: .continuous))
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if attachment.isImage {
            ComposerAttachmentImageIcon(url: attachment.url)
        } else {
            FileChipIcon(size: 10)
                .foregroundColor(Color(white: 0.60))
                .frame(width: 18, height: 18)
        }
    }
}

struct ComposerAttachmentImageIcon: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                FileChipIcon(size: 10)
                    .foregroundColor(Color(white: 0.60))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .task(id: url.standardizedFileURL.path) {
            image = await Self.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let cfURL = url as CFURL
            guard let source = CGImageSourceCreateWithURL(cfURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
