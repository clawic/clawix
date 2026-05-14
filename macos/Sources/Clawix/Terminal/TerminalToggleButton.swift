import SwiftUI

/// Tiny chrome button that flips the integrated terminal panel open
/// and closed. Lives in `ContentTopChrome`'s right cluster so it sits
/// next to the file/editor opener: a "developer tools" group on the
/// trailing edge of the chat chrome.
struct TerminalToggleButton: View {
    @AppStorage(ClawixPersistentSurfaceKeys.terminalPanelOpen, store: SidebarPrefs.store)
    private var open: Bool = false
    @State private var hovered: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
        } label: {
            LucideIcon(.terminal, size: 13)
                .foregroundColor(open
                    ? Palette.textPrimary
                    : Color(white: hovered ? 0.78 : 0.55))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(open
                            ? Color(white: 0.16)
                            : (hovered ? Color(white: 0.12) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help("Toggle terminal (⌃`)")
        .accessibilityLabel("Toggle terminal panel")
    }
}
