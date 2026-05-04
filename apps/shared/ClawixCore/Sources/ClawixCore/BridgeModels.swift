import Foundation

public enum WireRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

public struct WireChat: Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var createdAt: Date
    public var isPinned: Bool
    public var isArchived: Bool
    public var hasActiveTurn: Bool
    public var lastMessageAt: Date?
    public var lastMessagePreview: String?
    public var branch: String?
    public var cwd: String?

    public init(
        id: String,
        title: String,
        createdAt: Date,
        isPinned: Bool = false,
        isArchived: Bool = false,
        hasActiveTurn: Bool = false,
        lastMessageAt: Date? = nil,
        lastMessagePreview: String? = nil,
        branch: String? = nil,
        cwd: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.hasActiveTurn = hasActiveTurn
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.branch = branch
        self.cwd = cwd
    }
}

public struct WireMessage: Codable, Equatable, Sendable {
    public let id: String
    public let role: WireRole
    public var content: String
    public var reasoningText: String
    public var streamingFinished: Bool
    public var isError: Bool
    public let timestamp: Date

    public init(
        id: String,
        role: WireRole,
        content: String,
        reasoningText: String = "",
        streamingFinished: Bool = true,
        isError: Bool = false,
        timestamp: Date
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningText = reasoningText
        self.streamingFinished = streamingFinished
        self.isError = isError
        self.timestamp = timestamp
    }
}
