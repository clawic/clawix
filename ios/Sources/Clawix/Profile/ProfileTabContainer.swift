import SwiftUI

/// Bottom-tabbed container for the mp/2.0.0 Profile / Feed / Chats /
/// Marketplace surfaces. Instantiated by `RootView` once a daemon credential
/// is available.
struct ProfileTabContainer: View {
    @StateObject private var store = ProfileStore()
    @State private var didConfigure = false

    let origin: URL
    let bearer: String?

    var body: some View {
        TabView {
            FeedView(store: store)
                .tabItem { Label("Feed", systemImage: "rectangle.stack") }

            P2PChatView(store: store)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }

            MarketplaceView(store: store)
                .tabItem { Label("Market", systemImage: "tag") }

            ProfileView(store: store)
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
        .task {
            if !didConfigure {
                store.configure(origin: origin, bearer: bearer)
                didConfigure = true
                await store.bootstrap()
            }
        }
    }
}
