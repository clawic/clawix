import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var store = BrowserControllerStore()
    @State private var moreMenuOpen = false

    private var activeWeb: SidebarItem.WebPayload? {
        if case .web(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeFile: SidebarItem.FilePayload? {
        if case .file(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeChat: SidebarItem.ChatPayload? {
        if case .chat(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    private var activeSimulator: SidebarItem.IOSSimulatorPayload? {
        if case .iosSimulator(let p) = appState.activeSidebarItem { return p }
        return nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                BrowserTabStrip()
                Divider().background(Color.white.opacity(0.06))

                if let payload = activeWeb {
                    let controller = store.controller(for: payload, appState: appState)
                    BrowserNavigationBar(controller: controller, moreMenuOpen: $moreMenuOpen)
                        .id(payload.id)
                    Divider().background(Color.white.opacity(0.06))
                    ZStack {
                        BrowserWebView(controller: controller)
                            .id(payload.id)
                        if let error = controller.lastNavigationError {
                            BrowserErrorOverlay(error: error) {
                                controller.reload()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeFile {
                    FileViewerPanel(path: payload.path)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeChat {
                    ChatView(chatId: payload.id, isSideChat: true)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeSimulator {
                    IOSSimulatorPanel(payload: payload)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(BrowserMoreMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if moreMenuOpen, let anchor, let payload = activeWeb {
                    let controller = store.controller(for: payload, appState: appState)
                    let buttonFrame = proxy[anchor]
                    BrowserMoreOptionsMenu(
                        controller: controller,
                        isOpen: $moreMenuOpen
                    )
                    .frame(width: BrowserMoreOptionsMenu.menuWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(moreMenuOpen)
        }
        .animation(MenuStyle.openAnimation, value: moreMenuOpen)
        .onChange(of: appState.sidebarItems.map(\.id)) { _, newIds in
            store.discardOrphans(currentTabIds: Set(newIds))
            if activeWeb == nil { moreMenuOpen = false }
        }
        .onChange(of: appState.pendingReloadTabId) { _, newValue in
            guard let tabId = newValue,
                  let payload = activeWeb,
                  payload.id == tabId
            else { return }
            let controller = store.controller(for: payload, appState: appState)
            controller.reload()
            appState.pendingReloadTabId = nil
        }
        .onChange(of: appState.pendingBrowserCommand) { _, newValue in
            guard let request = newValue else { return }
            handleBrowserCommand(request.action)
            appState.pendingBrowserCommand = nil
        }
        .onDisappear {
            store.teardownAll()
            moreMenuOpen = false
        }
    }

    private func handleBrowserCommand(_ action: BrowserCommandRequest.Action) {
        // newTab is the only action that doesn't require an active tab; the
        // others fall through silently when the panel is empty.
        if action == .newTab {
            appState.newBrowserTab()
            return
        }
        guard let payload = activeWeb else { return }
        let controller = store.controller(for: payload, appState: appState)
        switch action {
        case .newTab:
            return  // already handled above
        case .reload:
            controller.reload()
        case .focusURLBar:
            BrowserView.focusSequence &+= 1
            appState.pendingFocusURLBar = BrowserFocusURLBarRequest(
                tabId: payload.id,
                sequence: BrowserView.focusSequence
            )
        case .closeActiveTab:
            appState.closeSidebarItem(payload.id)
        case .zoomIn:
            controller.zoomIn()
        case .zoomOut:
            controller.zoomOut()
        case .zoomReset:
            controller.resetZoom()
        }
    }

    private static var focusSequence: UInt64 = 0

    private var emptyState: some View {
        VStack(spacing: 12) {
            LucideIcon(.globe, size: 19.5)
                .foregroundColor(Color(white: 0.40))
            Text("No tabs open")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
            Button {
                appState.newBrowserTab()
            } label: {
                Text("New tab")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(white: 0.20))
                    )
            }
            .buttonStyle(.plain)

            Button {
                appState.openIOSSimulator()
            } label: {
                Text("iOS Simulator")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(white: 0.20))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct BrowserErrorOverlay: View {
    let error: BrowserTabController.NavigationError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            LucideIcon(.circleAlert, size: 22.5)
                .foregroundColor(Color(white: 0.55))
            Text("Cannot load page")
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Color(white: 0.85))
            Text(error.message)
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(Color(white: 0.60))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let url = error.failedURL {
                Text(url.absoluteString)
                    .font(BodyFont.system(size: 11, wght: 400))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }
            Button(action: onRetry) {
                Text("Try again")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(white: 0.20))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
