import Foundation
import ClawixCore
import Observation

// Source-of-truth state container for the SwiftUI tree. Phase 3 ships
// it backed by mock data so the views render before the real WS
// client (Phase 4) is wired. Every public mutation is the same
// surface the real client will drive.

@Observable
final class BridgeStore {

    enum ConnectionState: Equatable {
        case unpaired
        case connecting
        case connected(macName: String?)
        case error(message: String)
    }

    var connection: ConnectionState = .unpaired
    var chats: [WireChat] = []
    var messagesByChat: [String: [WireMessage]] = [:]
    var openChatId: String?

    init() {}

    static func mock() -> BridgeStore {
        let s = BridgeStore()
        s.connection = .connected(macName: "studio Mac")
        s.chats = MockData.chats
        s.messagesByChat = [
            MockData.chats[0].id: MockData.messages
        ]
        return s
    }

    // Intents the UI calls. Phase 4 will route these through the WS
    // client; for Phase 3 they mutate the local mock store so the
    // SwiftUI previews behave as expected.

    func openChat(_ chatId: String) {
        openChatId = chatId
        if messagesByChat[chatId] == nil {
            messagesByChat[chatId] = []
        }
    }

    func closeChat() {
        openChatId = nil
    }

    func sendPrompt(chatId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = WireMessage(
            id: UUID().uuidString,
            role: .user,
            content: trimmed,
            timestamp: Date()
        )
        messagesByChat[chatId, default: []].append(userMsg)
    }

    func messages(for chatId: String) -> [WireMessage] {
        messagesByChat[chatId] ?? []
    }

    func chat(_ chatId: String) -> WireChat? {
        chats.first { $0.id == chatId }
    }
}
