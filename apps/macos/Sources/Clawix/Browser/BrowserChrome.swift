import SwiftUI

// MARK: - Tab strip

struct BrowserTabStrip: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredTabId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ReviewTabPill()

            ForEach(appState.browserTabs) { tab in
                BrowserTabPill(
                    tab: tab,
                    isActive: appState.activeBrowserTabId == tab.id,
                    isHovered: hoveredTabId == tab.id,
                    onSelect: { appState.activeBrowserTabId = tab.id },
                    onClose:  { appState.closeBrowserTab(tab.id) }
                )
                .onHover { hovering in
                    if hovering { hoveredTabId = tab.id }
                    else if hoveredTabId == tab.id { hoveredTabId = nil }
                }
            }

            NewTabButton {
                appState.newBrowserTab()
            }

            Spacer(minLength: 0)

            ChromeIconButton(systemName: "arrow.up.left.and.arrow.down.right") {}
                .accessibilityLabel("Maximize")

            Button {
                appState.isRightSidebarOpen.toggle()
            } label: {
                SidebarToggleIcon(
                    side: .right,
                    size: 16,
                    color: appState.isRightSidebarOpen
                        ? Color(white: 0.78)
                        : Color(white: 0.55)
                )
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show right sidebar")
            .padding(.trailing, 12)
        }
        .padding(.leading, 10)
        .frame(height: 44)
        .background(Color.black)
    }
}

private struct ReviewTabPill: View {
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    var body: some View {
        Button {
            appState.closeBrowserPanel()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(white: 0.86))
                Text("Review")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(white: 0.92))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.07) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .hoverHint(L10n.t("Back to review panel"), placement: .below)
    }
}

private struct BrowserTabPill: View {
    let tab: BrowserTab
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                FaviconView(url: tab.faviconURL, size: 14)

                Text(displayTitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isActive ? .white : Color(white: 0.78))
                    .lineLimit(1)

                if isHovered || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(white: 0.78))
                            .frame(width: 14, height: 14)
                            .background(
                                Circle().fill(Color.white.opacity(0.10))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close tab")
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 180)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if !tab.title.isEmpty { return tab.title }
        if let host = tab.url.host { return host.replacingOccurrences(of: "www.", with: "") }
        return tab.url.absoluteString
    }

    private var background: Color {
        if isActive  { return Color.white.opacity(0.10) }
        if isHovered { return Color.white.opacity(0.05) }
        return .clear
    }
}

private struct NewTabButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.78))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .hoverHint(L10n.t("New tab"), placement: .below)
    }
}

// MARK: - Navigation bar

struct BrowserNavigationBar: View {
    @ObservedObject var controller: BrowserTabController

    var body: some View {
        HStack(spacing: 6) {
            ChromeIconButton(systemName: "chevron.left",
                             enabled: controller.canGoBack) {
                controller.goBack()
            }
            .accessibilityLabel("Back")
            .hoverHint(L10n.t("Back"), placement: .below)

            ChromeIconButton(systemName: "chevron.right",
                             enabled: controller.canGoForward) {
                controller.goForward()
            }
            .accessibilityLabel("Forward")
            .hoverHint(L10n.t("Forward"), placement: .below)

            ChromeIconButton(systemName: controller.isLoading
                             ? "xmark"
                             : "arrow.clockwise") {
                if controller.isLoading {
                    controller.webView.stopLoading()
                } else {
                    controller.reload()
                }
            }
            .accessibilityLabel(controller.isLoading ? L10n.t("Stop") : L10n.t("Reload"))
            .hoverHint(controller.isLoading ? L10n.t("Stop loading") : L10n.t("Reload"), placement: .below)

            BrowserURLField(controller: controller)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

            ChromeIconButton(systemName: "viewfinder") {}
                .accessibilityLabel("Lens")
                .hoverHint(L10n.t("Lens"), placement: .below)
            ChromeIconButton(systemName: "plus") {}
                .accessibilityLabel("Add")
                .hoverHint(L10n.t("Add"), placement: .below)
            ChromeIconButton(systemName: "ellipsis") {}
                .accessibilityLabel("More options")
                .hoverHint(L10n.t("More options"), placement: .below)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.black)
    }
}

private struct ChromeIconButton: View {
    let systemName: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered && enabled ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foreground: Color {
        if !enabled { return Color(white: 0.32) }
        return hovered ? Color(white: 0.92) : Color(white: 0.72)
    }
}

// MARK: - URL field

struct BrowserURLField: View {
    @ObservedObject var controller: BrowserTabController
    @State private var draft: String = ""
    @State private var editing: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(url: controller.faviconURL, size: 14)
                .padding(.leading, 12)

            TextField("", text: $draft, onCommit: commit)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 12.5))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .onChange(of: isFocused) { _, focused in
                    editing = focused
                    if focused {
                        draft = controller.currentURL.absoluteString
                    } else {
                        syncFromController()
                    }
                }
        }
        .frame(height: 28)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(editing ? 0.18 : 0.08), lineWidth: 0.7)
        )
        .onAppear { syncFromController() }
        .onChange(of: controller.currentURL) { _, _ in
            if !editing { syncFromController() }
        }
    }

    private func commit() {
        controller.loadString(draft)
        isFocused = false
    }

    private func syncFromController() {
        let url = controller.currentURL
        if let host = url.host {
            // Match the look of Safari's URL field: hostname only.
            draft = host.replacingOccurrences(of: "www.", with: "")
        } else {
            draft = url.absoluteString
        }
    }
}

// MARK: - Favicon

struct FaviconView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .font(.system(size: size - 2, weight: .regular))
            .foregroundColor(Color(white: 0.55))
    }
}
