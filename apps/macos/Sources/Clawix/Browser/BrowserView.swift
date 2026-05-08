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

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                BrowserTabStrip()
                Divider().background(Color.white.opacity(0.06))

                if let payload = activeWeb {
                    let controller = store.controller(for: payload, appState: appState)
                    BrowserNavigationBar(controller: controller, moreMenuOpen: $moreMenuOpen)
                    Divider().background(Color.white.opacity(0.06))
                    BrowserWebView(controller: controller)
                        .id(payload.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let payload = activeFile {
                    FileViewerPanel(path: payload.path)
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            LucideIcon(.globe, size: 28)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
