import SwiftUI

@main
struct ClawixApp: App {
    @State private var store = BridgeStore.mock()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootView: View {
    @Bindable var store: BridgeStore
    @State private var paired: Bool = true

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if !paired {
                PairingView(onPaired: { paired = true })
                    .transition(.opacity)
            } else {
                NavigationStack {
                    ChatListView(
                        store: store,
                        onOpen: { store.openChat($0) }
                    )
                    .navigationDestination(isPresented: openChatBinding) {
                        if let id = store.openChatId {
                            ChatDetailView(
                                store: store,
                                chatId: id,
                                onBack: { store.closeChat() }
                            )
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: paired)
    }

    private var openChatBinding: Binding<Bool> {
        Binding(
            get: { store.openChatId != nil },
            set: { if !$0 { store.closeChat() } }
        )
    }
}

#Preview("Root") {
    RootView(store: BridgeStore.mock())
}
