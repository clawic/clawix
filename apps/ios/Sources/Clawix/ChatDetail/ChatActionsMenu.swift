import SwiftUI

// Custom popover content for the chat top-bar ellipsis. Sits inside a
// system popover (`.presentationCompactAdaptation(.popover)`) so the
// frame, arrow, dimming and dismissal are native, but the rows are
// drawn by us so we can use the same custom glyphs the macOS sidebar
// menu uses (PencilIconView for rename, ArchiveIconView for archive)
// instead of falling back to SF Symbols. UIKit's UIMenu silently
// strips arbitrary SwiftUI views from menu items, which is why this
// goes through a popover and not `Menu { ... }`.
struct ChatActionsMenu: View {
    let onRename: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(title: "Rename", action: onRename) {
                PencilIconView(color: Palette.textPrimary, lineWidth: 1.4)
                    .frame(width: 18, height: 18)
            }
            Divider()
                .overlay(Color.white.opacity(0.08))
            row(title: "Archive", action: onArchive) {
                ArchiveIconView(
                    color: Palette.textPrimary,
                    lineWidth: 1.4,
                    size: 18
                )
            }
        }
        .frame(minWidth: 220)
        .padding(.vertical, 4)
        .background(Palette.surface)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func row<Icon: View>(
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(BodyFont.manrope(size: 16, wght: 500))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 24)
                icon()
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
