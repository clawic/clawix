import SwiftUI
import ClawixCore

@main
struct ClawixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = BridgeStore()
    @State private var client: BridgeClient?
    @State private var creds: Credentials? = CredentialStore.shared.load()

    var body: some Scene {
        WindowGroup {
            RootView(
                store: store,
                creds: $creds,
                onPair: handlePaired,
                onUnpair: handleUnpair
            )
            .preferredColorScheme(.dark)
            .onAppear(perform: bootstrap)
            .onChange(of: creds) { _, newValue in
                if let newValue {
                    connect(with: newValue)
                } else {
                    client?.disconnect()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhase(newPhase)
            }
        }
    }

    /// Honor the iOS app lifecycle so the WebSocket isn't left hanging
    /// while we're suspended.
    ///
    /// The Mac side of the bridge keeps a `BridgeSession` alive per
    /// connected iPhone. When the iPhone goes to background, iOS may
    /// keep the socket nominally open for a while and then silently
    /// kill it without flushing a close frame, leaving the Mac stuck
    /// with a zombie session that thinks the iPhone is still there.
    /// We close the socket actively on `.background` so the Mac
    /// drops the session immediately, and reopen on `.active` so
    /// returning to the app feels instant.
    ///
    /// `.inactive` is intentionally a no-op: it fires for transient
    /// overlays (notification banners, control center, app switcher
    /// peek) and reacting there would churn the connection for no
    /// reason.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            client?.suspend()
        case .active:
            if let creds {
                client?.connect(creds)
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func bootstrap() {
        #if DEBUG
        // Designer preview mode: launch with `CLAWIX_MOCK=1` (passed via
        // simctl `--launch-args ... --setenv CLAWIX_MOCK 1`) to bypass
        // the QR pairing flow and render the chat list / detail
        // surfaces with mock data so we can iterate on the visual
        // design without a paired Mac in the loop.
        if ProcessInfo.processInfo.environment["CLAWIX_MOCK"] == "1" {
            let mock = BridgeStore.mock()
            store.connection = mock.connection
            store.chats = mock.chats
            store.messagesByChat = mock.messagesByChat
            creds = Credentials(host: "127.0.0.1", port: 7777, token: "mock", macName: "studio Mac", tailscaleHost: nil)
            if ProcessInfo.processInfo.environment["CLAWIX_MOCK_OPEN_FIRST_CHAT"] == "1",
               let first = store.chats.first {
                store.openChatId = first.id
            }
            return
        }
        #endif
        // Warm the home + most-recent chats from the on-disk snapshot
        // BEFORE the bridge race kicks off. The user lands on a
        // populated chat list / detail screen instead of a blank one
        // while we negotiate WebSocket + auth. The bridge later
        // overwrites this with the canonical state.
        store.loadCachedSnapshot()
        if client == nil {
            let c = BridgeClient(store: store)
            store.attach(client: c)
            client = c
        }
        if let creds {
            connect(with: creds)
        }
    }

    private func connect(with creds: Credentials) {
        client?.connect(creds)
    }

    private func handlePaired(_ creds: Credentials) {
        self.creds = creds
    }

    private func handleUnpair() {
        client?.disconnect()
        CredentialStore.shared.clear()
        SnapshotCache.clear()
        store.chats = []
        store.messagesByChat = [:]
        store.openChatId = nil
        creds = nil
    }
}

// One NavigationStack at the root rules them all. Both `chat` and
// `project` pushes share the same path so SwiftUI doesn't end up with
// nested NavigationStacks fighting over the back gesture (which would
// freeze the chevron and the swipe-to-pop).
enum RootNav: Hashable {
    case chat(String)
    case project(String)
}

private struct PresentedFile: Identifiable, Equatable {
    let path: String
    var id: String { path }
}

private struct RootView: View {
    @Bindable var store: BridgeStore
    @Binding var creds: Credentials?
    let onPair: (Credentials) -> Void
    let onUnpair: () -> Void

    @State private var path = NavigationPath()
    @State private var presentedFile: PresentedFile?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if creds == nil {
                PairingView(onPaired: onPair)
                    .transition(.opacity)
            } else {
                NavigationStack(path: $path) {
                    ChatListView(
                        store: store,
                        onOpen: { id in
                            store.openChat(id)
                            path.append(RootNav.chat(id))
                        },
                        onOpenProject: { cwd in
                            path.append(RootNav.project(cwd))
                        },
                        onPair: onPair,
                        onUnpair: onUnpair,
                        onNewChat: {
                            // Mint a fresh chat id locally and route into
                            // the detail screen. The chat materializes on
                            // the Mac when the user sends the first
                            // message (see BridgeStore.sendPrompt's
                            // pending-newChats path).
                            let id = store.startNewChat()
                            path.append(RootNav.chat(id))
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                    .task {
                        // Honor `CLAWIX_MOCK_OPEN_FIRST_CHAT`: bootstrap()
                        // seeds `store.openChatId`, but navigation lives
                        // in this view's `path`. Push it on first appear
                        // so the designer lands directly in the chat
                        // detail without a manual tap.
                        if path.isEmpty, let id = store.openChatId {
                            path.append(RootNav.chat(id))
                        }
                    }
                    .navigationDestination(for: RootNav.self) { target in
                        switch target {
                        case .chat(let id):
                            ChatDetailView(
                                store: store,
                                chatId: id,
                                onBack: popLast,
                                onOpenFile: { filePath in
                                    presentedFile = PresentedFile(path: filePath)
                                },
                                onOpenProject: { cwd in
                                    // Reset to home and push the chosen
                                    // project, avoiding a stale breadcrumb:
                                    // home -> projectA -> chat -> projectB.
                                    var newPath = NavigationPath()
                                    newPath.append(RootNav.project(cwd))
                                    path = newPath
                                },
                                onNewChat: {
                                    // Swap the current chat for a fresh
                                    // one in place, with animations
                                    // disabled so the new conversation
                                    // appears as a screen reset rather
                                    // than a navigation push. Any earlier
                                    // breadcrumb (e.g. project) is kept.
                                    // Carry over the current chat's cwd
                                    // so the optimistic stub already
                                    // belongs to the same folder before
                                    // the daemon's echo lands.
                                    let inheritedCwd = store.chat(id)?.cwd
                                    let newId = store.startNewChat(cwd: inheritedCwd)
                                    var t = Transaction()
                                    t.disablesAnimations = true
                                    withTransaction(t) {
                                        if !path.isEmpty {
                                            path.removeLast()
                                        }
                                        path.append(RootNav.chat(newId))
                                    }
                                }
                            )
                            // Force a fresh subtree on chat-id change so
                            // the in-place swap performed by the
                            // new-chat button (removeLast + append in
                            // the same transaction) tears down the
                            // previous ChatDetailView and ComposerView
                            // instead of reusing them. Without this,
                            // the composer's `didAutofocus` and the
                            // detail's `isFreshChat` carry over from
                            // the prior chat and autofocus never fires.
                            .id(id)
                        case .project(let cwd):
                            let project = DerivedProject.from(chats: store.chats.filter { !$0.isArchived })
                                .first(where: { $0.cwd == cwd })
                            if let project {
                                ProjectDetailView(
                                    store: store,
                                    project: project,
                                    onOpen: { id in
                                        store.openChat(id)
                                        path.append(RootNav.chat(id))
                                    },
                                    onSwitchProject: { newCwd in
                                        // Replace the current project screen
                                        // instead of pushing on top, so back
                                        // still goes to the home and the
                                        // stack stays one project deep.
                                        if !path.isEmpty {
                                            path.removeLast()
                                        }
                                        path.append(RootNav.project(newCwd))
                                    },
                                    onBack: popLast
                                )
                            }
                        }
                    }
                }
                .sheet(item: $presentedFile) { item in
                    FileViewerView(store: store, path: item.path)
                        .preferredColorScheme(.dark)
                }
                .onChange(of: path) { _, newValue in
                    // Keep the legacy `openChatId` flag in sync: when the
                    // user pops every screen and we're back at the home
                    // (path empty), clear the open-chat state so the
                    // store treats the chat as closed.
                    if newValue.isEmpty {
                        store.closeChat()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: creds)
    }

    private func popLast() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}
