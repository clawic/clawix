import SwiftUI
import AppKit

/// Horizontal row of removable chips rendered above the QuickAsk prompt
/// input. One chip per pending attachment in `controller.pendingAttachments`.
/// Renders nothing when the list is empty, keeping vertical space tight
/// in the compact HUD layout.
struct QuickAskChipsBar: View {
    @ObservedObject var controller: QuickAskController

    var body: some View {
        if controller.pendingAttachments.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(controller.pendingAttachments) { attachment in
                        QuickAskChip(
                            attachment: attachment,
                            onRemove: { controller.removeAttachment(attachment.id) }
                        )
                    }
                }
                .padding(.horizontal, 9)
            }
            .frame(height: 30)
        }
    }
}

private struct QuickAskChip: View {
    let attachment: QuickAskAttachment
    let onRemove: () -> Void

    @State private var hovered = false
    @State private var removeHovered = false

    var body: some View {
        HStack(spacing: attachment.isImage ? 6 : 4) {
            leadingContent
            Text(displayLabel)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.94))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(0)
            if hovered {
                Button(action: onRemove) {
                    LucideIcon(.x, size: 10)
                        .foregroundColor(Color(white: removeHovered ? 1.0 : 0.78))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { removeHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: removeHovered)
                .accessibilityLabel("Remove attachment")
                .transition(.opacity)
                .layoutPriority(1)
            }
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
        .help(attachment.url.path)
    }

    @ViewBuilder
    private var leadingContent: some View {
        if attachment.isImage, let thumb = NSImage(contentsOf: attachment.url) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(Circle())
        } else {
            LucideIcon.auto(iconName, size: 11)
                .foregroundColor(Color(white: 0.60))
                .frame(width: 18, height: 18)
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .screenshot: return "camera.viewfinder"
        case .camera:     return "camera"
        case .clipboard:  return "doc.on.clipboard"
        case .selection:  return "text.alignleft"
        case .paste:      return "doc.on.doc"
        case .drop, .file:
            return attachment.isPDF ? "doc.richtext" : "doc"
        }
    }

    private var displayLabel: String {
        if let preview = attachment.previewText, !preview.isEmpty {
            return preview
        }
        return attachment.filename
    }
}
