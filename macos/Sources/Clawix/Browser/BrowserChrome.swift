import SwiftUI

// MARK: - Tab strip

struct BrowserTabStrip: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredItemId: UUID?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(appState.sidebarItems) { item in
                SidebarItemPill(
                    item: item,
                    isActive: appState.activeSidebarItemId == item.id,
                    isHovered: hoveredItemId == item.id,
                    isLoading: appState.browserTabsLoading.contains(item.id),
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
            .padding(.top, 2)

            SimulatorTabButton {
                appState.openIOSSimulator()
            }
            .padding(.top, 2)

            AndroidSimulatorTabButton {
                appState.openAndroidSimulator()
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            ChromeMaximizeButton()
                .padding(.top, 2)
                .accessibilityLabel(appState.isRightSidebarMaximized ? "Restore panel size" : "Maximize panel")

            // The window chrome owns the right toggle; reserve its
            // footprint so the maximize button doesn't slide under it.
            Color.clear.frame(width: 30, height: 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(height: 40)
        .background(Color.black)
    }
}

private struct SidebarItemPill: View {
    let item: SidebarItem
    let isActive: Bool
    let isHovered: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                leadingIcon

                Text(displayTitle)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(isActive ? .white : Color(white: 0.78))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: 132, alignment: .leading)
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
                Button(action: onClose) {
                    LucideIcon(.x, size: 10)
                        .foregroundColor(Color(white: 0.95))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle().fill(Color.white.opacity(0.18))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isActive ? 1 : 0)
                .allowsHitTesting(isHovered || isActive)
                .accessibilityHidden(!(isHovered || isActive))
                .accessibilityLabel(L10n.t("Close tab"))
                .padding(.trailing, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select tab \(displayTitle)")
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .web(let p):
            ZStack {
                FaviconView(url: p.faviconURL, size: 14)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    BrowserTabSpinner()
                }
            }
            .frame(width: 14, height: 14)
            .animation(.easeOut(duration: 0.12), value: isLoading)
        case .file:
            FileChipIcon(size: 13)
                .foregroundColor(Color(white: 0.78))
                .frame(width: 14, height: 14)
        case .chat:
            // Branch arrows mark a side chat tab so users can tell it
            // apart from web/file pills at a glance. Same icon used by
            // the menu's "Fork conversation" entry, since a side chat
            // is a silent fork at heart.
            BranchArrowsIconView(color: Color(white: 0.78), lineWidth: 1.0)
                .frame(width: 14, height: 14)
        case .iosSimulator:
            LucideIcon(.appWindow, size: 13)
                .foregroundColor(Color(white: 0.78))
                .frame(width: 14, height: 14)
        case .androidSimulator:
            LucideIcon.auto("smartphone", size: 13)
                .foregroundColor(Color(white: 0.78))
                .frame(width: 14, height: 14)
        }
    }

    private var displayTitle: String {
        switch item {
        case .web(let p):
            if !p.title.isEmpty { return p.title }
            if p.url.absoluteString == "about:blank" { return L10n.t("New tab") }
            if let host = p.url.host { return host.replacingOccurrences(of: "www.", with: "") }
            return p.url.absoluteString
        case .file(let p):
            return (p.path as NSString).lastPathComponent
        case .chat(let p):
            // Resolve dynamically from AppState so renames flow without
            // having to keep a copy in `ChatPayload`. Falls back to
            // "Side chat" until the user types the first prompt
            // (sendMessage promotes the prompt to the chat title).
            if let chat = appState.chat(byId: p.id), !chat.title.isEmpty {
                return chat.title
            }
            return "Side chat"
        case .iosSimulator(let p):
            return p.deviceName
        case .androidSimulator(let p):
            return p.deviceName
        }
    }

    private var background: Color {
        if isActive  { return Color.white.opacity(0.10) }
        if isHovered { return Color.white.opacity(0.05) }
        return .clear
    }
}

/// Thin rotating ring used in tab pills while a page is loading. Mirrors
/// the sidebar's `SidebarChatRowSpinner` (Sources/Clawix/SidebarView.swift)
/// and the find bar's `FindBarSpinner` so the three loading idioms read
/// as one family. Uses white-on-dark tones because the tab strip sits on
/// a black background.
private struct BrowserTabSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.79)
                .stroke(Color.white.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 11, height: 11)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

private struct NewTabButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon(.plus, size: 13)
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

private struct SimulatorTabButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("iOS")
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color(white: 0.78))
                .frame(width: 34, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel("iOS Simulator")
        .hoverHint("iOS Simulator", placement: .below)
    }
}

private struct AndroidSimulatorTabButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("Android")
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color(white: 0.78))
                .frame(width: 58, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel("Android Emulator")
        .hoverHint("Android Emulator", placement: .below)
    }
}

// MARK: - Navigation bar

struct BrowserNavigationBar: View {
    @EnvironmentObject var appState: AppState
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

            ChromeIconButton(systemName: "viewfinder") {
                controller.captureToClipboard()
            }
            .accessibilityLabel("Take screenshot")
            .hoverHint(L10n.t("Take screenshot"), placement: .below)
            ChromeIconButton(systemName: "plus") {
                appState.openIOSSimulator()
            }
            .accessibilityLabel("iOS Simulator")
            .hoverHint("iOS Simulator", placement: .below)
            ChromeIconButton(systemName: "smartphone") {
                appState.openAndroidSimulator()
            }
            .accessibilityLabel("Android Emulator")
            .hoverHint("Android Emulator", placement: .below)
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
            LucideIcon.auto(systemName, size: 13)
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
                title: "Use mobile user agent",
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
                    CheckIcon(size: 11)
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
                LucideIcon(.rotateCcw, size: 11)
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
            LucideIcon.auto(symbol, size: 11)
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
    @EnvironmentObject var appState: AppState
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
        .onChange(of: controller.id) { _, _ in
            // Switching to a different tab. Drop any in-flight edit state so
            // the field can't commit the previous tab's draft against the new
            // controller. The .id(payload.id) on BrowserNavigationBar already
            // recreates this view; this guard covers the case where SwiftUI
            // chooses to keep structural identity.
            editing = false
            isFocused = false
            syncFromController()
        }
        .onChange(of: controller.currentURL) { _, _ in
            if !editing { syncFromController() }
        }
        .onChange(of: appState.pendingFocusURLBar) { _, newValue in
            guard let request = newValue, request.tabId == controller.id else { return }
            draft = controller.currentURL.absoluteString
            editing = true
            isFocused = true
            // The TextField's underlying NSTextField becomes first responder
            // on the next runloop tick. Sending selectAll then highlights the
            // full URL so the user can replace it with a single keystroke,
            // matching Safari's Cmd+L behaviour.
            DispatchQueue.main.async {
                NSApp.sendAction(
                    #selector(NSText.selectAll(_:)),
                    to: nil,
                    from: nil
                )
            }
            appState.pendingFocusURLBar = nil
        }
    }

    private func commit() {
        let submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesCurrentURL =
            submitted == controller.currentURL.absoluteString ||
            submitted == displayString(for: controller.currentURL)
        if matchesCurrentURL, controller.lastNavigationError == nil {
            isFocused = false
            return
        }
        controller.loadString(submitted)
        isFocused = false
    }

    private func syncFromController() {
        draft = displayString(for: controller.currentURL)
    }

    private func displayString(for url: URL) -> String {
        if let host = url.host {
            // Match the look of Safari's URL field: hostname only.
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
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
