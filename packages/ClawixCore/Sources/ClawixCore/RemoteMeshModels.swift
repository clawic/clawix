import Foundation

public enum PeerPermissionProfile: String, Codable, Equatable, Sendable {
    case fullTrust
    case scoped
    case askPerTask
}

public struct RemoteEndpoint: Codable, Equatable, Sendable {
    public var kind: String
    public var host: String
    public var bridgePort: Int
    public var httpPort: Int

    public init(kind: String, host: String, bridgePort: Int, httpPort: Int) {
        self.kind = kind
        self.host = host
        self.bridgePort = bridgePort
        self.httpPort = httpPort
    }
}

public struct NodeIdentity: Codable, Equatable, Sendable {
    public var nodeId: String
    public var displayName: String
    public var signingPublicKey: String
    public var agreementPublicKey: String
    public var endpoints: [RemoteEndpoint]
    public var capabilities: [String]

    public init(
        nodeId: String,
        displayName: String,
        signingPublicKey: String,
        agreementPublicKey: String,
        endpoints: [RemoteEndpoint],
        capabilities: [String]
    ) {
        self.nodeId = nodeId
        self.displayName = displayName
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
        self.endpoints = endpoints
        self.capabilities = capabilities
    }
}

public struct PeerRecord: Codable, Equatable, Sendable {
    public var nodeId: String
    public var displayName: String
    public var signingPublicKey: String
    public var agreementPublicKey: String
    public var endpoints: [RemoteEndpoint]
    public var permissionProfile: PeerPermissionProfile
    public var capabilities: [String]
    public var lastSeenAt: Date?
    public var revokedAt: Date?

    public init(
        nodeId: String,
        displayName: String,
        signingPublicKey: String,
        agreementPublicKey: String,
        endpoints: [RemoteEndpoint],
        permissionProfile: PeerPermissionProfile = .scoped,
        capabilities: [String],
        lastSeenAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.nodeId = nodeId
        self.displayName = displayName
        self.signingPublicKey = signingPublicKey
        self.agreementPublicKey = agreementPublicKey
        self.endpoints = endpoints
        self.permissionProfile = permissionProfile
        self.capabilities = capabilities
        self.lastSeenAt = lastSeenAt
        self.revokedAt = revokedAt
    }
}

public struct RemoteWorkspace: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var label: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, path: String, label: String, createdAt: Date = Date()) {
        self.id = id
        self.path = path
        self.label = label
        self.createdAt = createdAt
    }
}

public enum RemoteJobStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

public struct RemoteJob: Codable, Equatable, Sendable {
    public var id: String
    public var requesterNodeId: String
    public var workspacePath: String
    public var prompt: String
    public var status: RemoteJobStatus
    public var remoteChatId: String?
    public var remoteThreadId: String?
    public var resultText: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        requesterNodeId: String,
        workspacePath: String,
        prompt: String,
        status: RemoteJobStatus = .queued,
        remoteChatId: String? = nil,
        remoteThreadId: String? = nil,
        resultText: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.requesterNodeId = requesterNodeId
        self.workspacePath = workspacePath
        self.prompt = prompt
        self.status = status
        self.remoteChatId = remoteChatId
        self.remoteThreadId = remoteThreadId
        self.resultText = resultText
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RemoteJobEvent: Codable, Equatable, Sendable {
    public var id: String
    public var jobId: String
    public var type: String
    public var message: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, jobId: String, type: String, message: String, createdAt: Date = Date()) {
        self.id = id
        self.jobId = jobId
        self.type = type
        self.message = message
        self.createdAt = createdAt
    }
}
