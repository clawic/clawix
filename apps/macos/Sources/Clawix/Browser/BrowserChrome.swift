import SwiftUI

// MARK: - Tab strip

struct BrowserTabStrip: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredTabId: UUID?

    var body: some View {
        HStack(spacing: 6) {
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

            // The window chrome owns the right toggle; reserve its
            // footprint so the maximize button doesn't slide under it.
            Color.clear.frame(width: 30, height: 1)
        }
        .padding(.leading, 10)
        .frame(height: 44)
        .background(Color.black)
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
    @State private var moreMenuOpen = false

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
            ChromeIconButton(systemName: "ellipsis", isActive: moreMenuOpen) {
                moreMenuOpen.toggle()
            }
            .accessibilityLabel("More options")
            .hoverHint(L10n.t("More options"), placement: .below)
            .anchorPreference(key: BrowserMoreMenuAnchorKey.self, value: .bounds) { $0 }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.black)
        .overlayPreferenceValue(BrowserMoreMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if moreMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    BrowserMoreOptionsMenu(
                        controller: controller,
                        isOpen: $moreMenuOpen
                    )
                    .offset(
                        x: buttonFrame.maxX - BrowserMoreOptionsMenu.menuWidth,
                        y: buttonFrame.maxY + 6
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(moreMenuOpen)
        }
        .animation(MenuStyle.openAnimation, value: moreMenuOpen)
    }
}

private struct BrowserMoreMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct ChromeIconButton: View {
    let systemName: String
    var enabled: Bool = true
    var isActive: Bool = false
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
                        .fill(backgroundColor)
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
        if isActive { return Color(white: 0.96) }
        return hovered ? Color(white: 0.92) : Color(white: 0.72)
    }

    private var backgroundColor: Color {
        if isActive { return Color.white.opacity(0.10) }
        if hovered && enabled { return Color.white.opacity(0.07) }
        return .clear
    }
}

// MARK: - More options menu

struct BrowserMoreOptionsMenu: View {
    @ObservedObject var controller: BrowserTabController
    @Binding var isOpen: Bool
    @State private var hovered: String?

    static let menuWidth: CGFloat = 268

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            simpleRow(id: "hardReload", title: "Hard reload") {
                controller.hardReload()
                isOpen = false
            }
            simpleRow(
                id: "deviceToolbar",
                title: "Show device toolbar",
                trailingCheck: controller.mobileMode
            ) {
                controller.toggleMobileMode()
                isOpen = false
            }

            MenuStandardDivider().padding(.vertical, 4)

            ZoomRow(
                pageZoom: controller.pageZoom,
                onZoomOut: { controller.zoomOut() },
                onZoomIn:  { controller.zoomIn()  },
                onReset:   { controller.resetZoom() }
            )

            MenuStandardDivider().padding(.vertical, 4)

            simpleRow(id: "clearCookies", title: "Clear cookies") {
                controller.clearCookies { controller.reload() }
                isOpen = false
            }
            simpleRow(id: "clearCache", title: "Clear cache") {
                controller.clearCache { controller.reload() }
                isOpen = false
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.menuWidth, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }

    private func simpleRow(
        id: String,
        title: LocalizedStringKey,
        trailingCheck: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                if trailingCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding + 4)
            .padding(.vertical, MenuStyle.rowVerticalPadding + 1)
            .background(MenuRowHover(active: hovered == id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = id }
            else if hovered == id { hovered = nil }
        }
    }
}

private struct ZoomRow: View {
    let pageZoom: Double
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    @State private var hoverMinus = false
    @State private var hoverPlus = false
    @State private var hoverReset = false

    private var percentText: String {
        "\(Int((pageZoom * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Zoom")
                .font(.system(size: 13))
                .foregroundColor(MenuStyle.rowText)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                stepperButton(symbol: "minus", hovered: $hoverMinus, action: onZoomOut)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 14)

                Text(percentText)
                    .font(.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .frame(minWidth: 38)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 14)

                stepperButton(symbol: "plus", hovered: $hoverPlus, action: onZoomIn)
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hoverReset ? MenuStyle.rowText : MenuStyle.rowSubtle)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverReset = $0 }
        }
        .padding(.horizontal, MenuStyle.rowHorizontalPadding + 4)
        .padding(.vertical, MenuStyle.rowVerticalPadding - 1)
    }

    private func stepperButton(symbol: String, hovered: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hovered.wrappedValue ? MenuStyle.rowText : MenuStyle.rowIcon)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered.wrappedValue = $0 }
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

    @State private var hostFallback: URL?

    var body: some View {
        Group {
            if let resolved = hostFallback ?? url {
                AsyncImage(url: resolved) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        retryView
                    case .empty:
                        Color.clear
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .onChange(of: url) { _, _ in hostFallback = nil }
    }

    /// If AsyncImage fails to render the page-declared favicon (404, an
    /// odd format, etc.) swap in Google's PNG service for the same host
    /// so we always show something rather than the bare globe glyph.
    private var retryView: some View {
        Group {
            if hostFallback == nil,
               let url,
               let host = url.host,
               let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"),
               google != url {
                Color.clear
                    .onAppear { hostFallback = google }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .font(.system(size: size - 2, weight: .regular))
            .foregroundColor(Color(white: 0.55))
    }
}
