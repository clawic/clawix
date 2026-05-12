import SwiftUI

struct TerminalPaneControls: View {
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            PaneControlButton(
                icon: TerminalSplitRightIcon(size: 12),
                help: "Split right",
                action: onSplitRight
            )
            PaneControlButton(
                icon: TerminalSplitDownIcon(size: 12),
                help: "Split down",
                action: onSplitDown
            )
            PaneControlButton(
                icon: LucideIcon(.x, size: 11),
                help: "Close pane",
                action: onClose
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                )
        )
        .opacity(hovered ? 1.0 : 0.55)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

private struct PaneControlButton: View {
    let icon: AnyView
    let help: String
    let action: () -> Void

    @State private var hovered: Bool = false

    init<Icon: View>(icon: Icon, help: String, action: @escaping () -> Void) {
        self.icon = AnyView(icon)
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            icon
                .foregroundColor(Color(white: hovered ? 0.95 : 0.75))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.10 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.10), value: hovered)
        .help(help)
        .accessibilityLabel(help)
    }
}
