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
            cwd: cwd,
            lastTurnInterrupted: lastTurnInterrupted
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
            timestamp: timestamp,
            timeline: timeline.map { $0.toWire() },
            workSummary: workSummary?.toWire()
        )
    }
}

extension AssistantTimelineEntry {
    func toWire() -> WireTimelineEntry {
        switch self {
        case .reasoning(let id, let text):
            return .reasoning(id: id.uuidString, text: text)
        case .tools(let id, let items):
            return .tools(id: id.uuidString, items: items.map { $0.toWire() })
        }
    }
}

extension WorkItem {
    func toWire() -> WireWorkItem {
        let status: WireWorkItemStatus
        switch self.status {
        case .inProgress: status = .inProgress
        case .completed:  status = .completed
        case .failed:     status = .failed
        }
        switch kind {
        case .command(let text, let actions):
            return WireWorkItem(
                id: id,
                kind: "command",
                status: status,
                commandText: text,
                commandActions: actions.map { $0.rawValue }
            )
        case .fileChange(let paths):
            return WireWorkItem(
                id: id,
                kind: "fileChange",
                status: status,
                paths: paths
            )
        case .webSearch:
            return WireWorkItem(id: id, kind: "webSearch", status: status)
        case .mcpTool(let server, let tool):
            return WireWorkItem(
                id: id,
                kind: "mcpTool",
                status: status,
                mcpServer: server,
                mcpTool: tool
            )
        case .dynamicTool(let name):
            return WireWorkItem(
                id: id,
                kind: "dynamicTool",
                status: status,
                dynamicToolName: name
            )
        case .imageGeneration:
            return WireWorkItem(id: id, kind: "imageGeneration", status: status)
        case .imageView:
            return WireWorkItem(id: id, kind: "imageView", status: status)
        }
    }
}

extension WorkSummary {
    func toWire() -> WireWorkSummary {
        WireWorkSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            items: items.map { $0.toWire() }
        )
    }
}
