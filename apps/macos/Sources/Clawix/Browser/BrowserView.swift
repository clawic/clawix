import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var store = BrowserControllerStore()

    private var activeTab: BrowserTab? {
        guard let id = appState.activeBrowserTabId else { return nil }
        return appState.browserTabs.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabStrip()
            Divider().background(Color.white.opacity(0.06))

            if let tab = activeTab {
                let controller = store.controller(for: tab, appState: appState)
                BrowserNavigationBar(controller: controller)
                Divider().background(Color.white.opacity(0.06))
                BrowserWebView(controller: controller)
                    .id(tab.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.browserTabs.map(\.id)) { _, newIds in
            store.discardOrphans(currentTabIds: Set(newIds))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(white: 0.40))
            Text("No tabs open")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
            Button {
                appState.newBrowserTab()
            } label: {
                Text("New tab")
                    .font(.system(size: 12, weight: .medium))
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
