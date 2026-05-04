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
