import SwiftUI

// MARK: - Tab strip

struct BrowserTabStrip: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredItemId: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(appState.sidebarItems) { item in
                SidebarItemPill(
                    item: item,
                    isActive: appState.activeSidebarItemId == item.id,
                    isHovered: hoveredItemId == item.id,
                    onSelect: { appState.activeSidebarItemId = item.id },
                    onClose:  { appState.closeSidebarItem(item.id) }
                )
                .onHover { hovering in
                    if hovering { hoveredItemId = item.id }
                    else if hoveredItemId == item.id { hoveredItemId = nil }
                }
            }

            NewTabButton {
                appState.newBrowserTab()
            }

            Spacer(minLength: 0)

            ChromeMaximizeButton()
                .accessibilityLabel(appState.isRightSidebarMaximized ? "Restore panel size" : "Maximize panel")

            // The window chrome owns the right toggle; reserve its
            // footprint so the maximize button doesn't slide under it.
            Color.clear.frame(width: 30, height: 1)
        }
        .padding(.leading, 10)
        .frame(height: 36)
        .background(Color.black)
    }
}

private struct SidebarItemPill: View {
    let item: SidebarItem
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                leadingIcon

                Text(displayTitle)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(isActive ? .white : Color(white: 0.78))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: 132)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(background)
            )
            .overlay(alignment: .trailing) {
                if isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(BodyFont.system(size: 9, weight: .bold))
                            .foregroundColor(Color(white: 0.95))
                            .frame(width: 14, height: 14)
                            .background(
                                Circle().fill(Color.white.opacity(0.18))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close tab")
                    .padding(.trailing, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .web(let p):
            FaviconView(url: p.faviconURL, size: 14)
        case .file:
            FileChipIcon(size: 13)
                .foregroundColor(Color(white: 0.78))
                .frame(width: 14, height: 14)
        }
    }

    private var displayTitle: String {
        switch item {
        case .web(let p):
            if !p.title.isEmpty { return p.title }
            if let host = p.url.host { return host.replacingOccurrences(of: "www.", with: "") }
            return p.url.absoluteString
        case .file(let p):
            return (p.path as NSString).lastPathComponent
        }
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
                .font(BodyFont.system(size: 12, weight: .semibold))
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
    @Binding var moreMenuOpen: Bool

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
    }
}

struct BrowserMoreMenuAnchorKey: PreferenceKey {
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
                .font(BodyFont.system(size: 12, weight: .medium))
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

private struct ChromeMaximizeButton: View {
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                appState.isRightSidebarMaximized.toggle()
            }
        } label: {
            CornerBracketsIcon(
                size: 13,
                variant: appState.isRightSidebarMaximized ? .collapsed : .expanded,
                lineWidth: 1.6
            )
            .foregroundColor(foreground)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foreground: Color {
        hovered ? Color(white: 0.92) : Color(white: 0.72)
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
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 0)
                if trailingCheck {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 11, weight: .semibold))
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
                .font(BodyFont.system(size: 13))
                .foregroundColor(MenuStyle.rowText)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                stepperButton(symbol: "minus", hovered: $hoverMinus, action: onZoomOut)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 14)

                Text(percentText)
                    .font(BodyFont.system(size: 12))
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
                    .font(BodyFont.system(size: 11, weight: .medium))
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
                .font(BodyFont.system(size: 11, weight: .semibold))
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
                .font(BodyFont.system(size: 12.5, wght: 500))
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

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .transition(.opacity)
            } else {
                MonogramFavicon(seed: url?.host ?? "?", size: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.18), value: image != nil)
        .onAppear { syncFromCache() }
        .onChange(of: url) { _, _ in syncFromCache() }
        .task(id: url) { await load() }
    }

    /// Pull synchronously through the memory + disk tiers so any host
    /// the user has ever visited paints on the first frame, not after a
    /// `.task` hop. Disk reads are mmap'd and cost <1ms for a favicon.
    private func syncFromCache() {
        guard let url else { image = nil; return }
        image = FaviconCache.shared.cachedImageOrLoadFromDisk(for: url)
    }

    private func load() async {
        guard let url else { return }
        if let cached = FaviconCache.shared.cachedImageOrLoadFromDisk(for: url) {
            image = cached
            return
        }
        if let loaded = await FaviconCache.shared.image(for: url) {
            image = loaded
            return
        }
        // Page-declared favicon couldn't be loaded (404, weird format,
        // etc.). Fall back to Google's PNG service for the same host.
        if let host = url.host,
           let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"),
           google != url,
           let loaded = await FaviconCache.shared.image(for: google) {
            image = loaded
        }
    }
}

/// Identity placeholder shown while a favicon is loading or when the
/// host has none. The first letter of the host on a stable hue derived
/// from the host string reads as "this is the site", not "loading".
private struct MonogramFavicon: View {
    let seed: String
    let size: CGFloat

    private var letter: String {
        let host = seed.replacingOccurrences(of: "www.", with: "")
        return host.first.map { String($0).uppercased() } ?? "•"
    }

    private var fillColor: Color {
        // Deterministic FNV-1a so a given host always lands on the same
        // hue, regardless of process restarts. Swift's `Hasher` would
        // re-seed per process and recolor the placeholder on relaunch.
        var hash: UInt32 = 0x811c9dc5
        for byte in seed.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        let bucket = Int(hash % 8)
        let hues: [Double] = [0.58, 0.04, 0.34, 0.74, 0.92, 0.13, 0.50, 0.84]
        return Color(hue: hues[bucket], saturation: 0.32, brightness: 0.42)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(fillColor)
            .overlay(
                Text(letter)
                    .font(BodyFont.system(size: size * 0.62, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            )
            .frame(width: size, height: size)
    }
}
