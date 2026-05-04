import Foundation
import ClawixCore

extension Chat {
    func toWire() -> WireChat {
        let last = messages.last
        return WireChat(
            id: id.uuidString,
            title: title,
            createdAt: createdAt,
            isPinned: isPinned,
            isArchived: isArchived,
            hasActiveTurn: hasActiveTurn,
            lastMessageAt: last?.timestamp,
            lastMessagePreview: last.flatMap { String($0.content.prefix(140)) },
            branch: branch,
            cwd: cwd
        )
    }
}

extension ChatMessage {
    func toWire() -> WireMessage {
        let role: WireRole = (self.role == .user) ? .user : .assistant
        return WireMessage(
            id: id.uuidString,
            role: role,
            content: content,
            reasoningText: reasoningText,
            streamingFinished: streamingFinished,
            isError: isError,
            timestamp: timestamp
        )
    }
}
