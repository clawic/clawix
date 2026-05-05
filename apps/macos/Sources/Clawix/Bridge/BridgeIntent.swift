import Foundation
import ClawixCore

@MainActor
enum BridgeIntent {

    /// Routes an authenticated inbound frame to the right `AppState` /
    /// `BridgeBus` operation. Frames that are server-only or that
    /// have no authenticated meaning are ignored.
    static func dispatch(
        body: BridgeBody,
        appState: AppState?,
        bus: BridgeBus,
        session: BridgeSession
    ) {
        switch body {
        case .listChats:
            session.send(BridgeFrame(.chatsSnapshot(chats: bus.currentChats())))

        case .openChat(let chatIdString):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            // Mirror what selecting a chat in the Mac UI does: pull
            // the rollout file off disk so `chat.messages` is populated
            // before we hand it to the bridge subscriber. Without this
            // every `notLoaded` thread shows up empty on the iPhone.
            appState?.hydrateHistoryFromBridge(chatId: uuid)
            let messages = bus.subscribe(chatId: uuid)
            session.send(BridgeFrame(.messagesSnapshot(chatId: chatIdString, messages: messages)))

        case .sendPrompt(let chatIdString, let text):
            guard let uuid = UUID(uuidString: chatIdString) else {
                session.send(BridgeFrame(.errorEvent(code: "badChatId", message: chatIdString)))
                return
            }
            appState?.sendUserMessageFromBridge(chatId: uuid, text: text)

        case .auth, .authOk, .authFailed, .versionMismatch,
             .chatsSnapshot, .chatUpdated, .messagesSnapshot,
             .messageAppended, .messageStreaming, .errorEvent:
            // Either already handled (auth) or server-only.
            break
        }
    }
}
