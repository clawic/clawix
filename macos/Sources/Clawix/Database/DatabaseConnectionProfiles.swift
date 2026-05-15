import Combine
import Foundation

enum DatabaseConnectionAuthStorage: String, Codable, CaseIterable, Identifiable {
    case askEveryTime
    case secretVault
    case notRequired

    var id: String { rawValue }

    var label: String {
        switch self {
        case .askEveryTime: return "Ask every time"
        case .secretVault:  return "Secrets"
        case .notRequired:  return "Not required"
        }
    }
}

enum DatabaseConnectionSSLMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case preferred
    case required
    case verifyCA
    case verifyFull

    var id: String { rawValue }

    var label: String {
        switch self {
        case .disabled:   return "Disabled"
        case .preferred:  return "Preferred"
        case .required:   return "Required"
        case .verifyCA:   return "Verify CA"
        case .verifyFull: return "Verify full"
        }
    }
}

enum DatabaseConnectionNegotiation: String, Codable, CaseIterable, Identifiable {
    case engineDefault
    case postgres
    case mysql
    case direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .engineDefault: return "Engine default"
        case .postgres:      return "Postgres"
        case .mysql:         return "MySQL"
        case .direct:        return "Direct"
        }
    }
}

enum DatabaseConnectionSSHVersion: String, Codable, CaseIterable, Identifiable {
    case current
    case compat095 = "compat-0.9.5"

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "current":
            self = .current
        case "compat-0.9.5", "legacy":
            self = .compat095
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown SSH version: \(rawValue)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .current:   return "SSH 0.11"
        case .compat095: return "SSH 0.9.5 compatibility"
        }
    }
}

struct DatabaseConnectionProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var engineId: String
    var name: String
    var groupName: String
    var tag: String
    var statusColor: String
    var hostOrPath: String
    var port: Int?
    var username: String
    var databaseName: String
    var authStorage: DatabaseConnectionAuthStorage
    var sslMode: DatabaseConnectionSSLMode
    var negotiation: DatabaseConnectionNegotiation
    var sslKeyPath: String
    var sslCertificatePath: String
    var sslCAPath: String
    var bootstrapSQL: String
    var loadSystemSchemas: Bool
    var disableChannelBinding: Bool
    var sshEnabled: Bool
    var sshHost: String
    var sshPort: Int
    var sshUsername: String
    var sshAuthStorage: DatabaseConnectionAuthStorage
    var sshUsesPrivateKey: Bool
    var sshPrivateKeyPath: String
    var sshVersion: DatabaseConnectionSSHVersion
    var updatedAt: Date

    var engine: DatabaseWorkbenchEngine? {
        DatabaseWorkbenchPreferences.supportedEngines.first { $0.id == engineId }
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled connection" : name
    }

    static func draft(engine: DatabaseWorkbenchEngine? = DatabaseWorkbenchPreferences.supportedEngines.first) -> DatabaseConnectionProfile {
        let resolved = engine ?? DatabaseWorkbenchPreferences.supportedEngines[0]
        return DatabaseConnectionProfile(
            id: UUID(),
            engineId: resolved.id,
            name: "New \(resolved.label) connection",
            groupName: "local",
            tag: "local",
            statusColor: "gray",
            hostOrPath: resolved.supportsFileOpen ? "" : "127.0.0.1",
            port: resolved.defaultPort,
            username: "",
            databaseName: "",
            authStorage: .askEveryTime,
            sslMode: resolved.supportsSSL ? .preferred : .disabled,
            negotiation: resolved.id == "postgresql" ? .postgres : .engineDefault,
            sslKeyPath: "",
            sslCertificatePath: "",
            sslCAPath: "",
            bootstrapSQL: "",
            loadSystemSchemas: true,
            disableChannelBinding: false,
            sshEnabled: false,
            sshHost: "",
            sshPort: 22,
            sshUsername: "",
            sshAuthStorage: .askEveryTime,
            sshUsesPrivateKey: false,
            sshPrivateKeyPath: "",
            sshVersion: .current,
            updatedAt: Date()
        )
    }
}

struct DatabaseConnectionDryRunResult: Equatable {
    enum Status: Equatable {
        case passed
        case externalPending
        case failed
    }

    let status: Status
    let message: String
}

@MainActor
final class DatabaseConnectionProfileStore: ObservableObject {
    static let shared = DatabaseConnectionProfileStore()

    @Published private(set) var profiles: [DatabaseConnectionProfile] = []
    @Published private(set) var lastDryRun: DatabaseConnectionDryRunResult?

    private let defaults: UserDefaults
    private let key = "clawix.databaseWorkbench.connectionProfiles.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func upsert(_ profile: DatabaseConnectionProfile) {
        var saved = normalized(profile)
        saved.updatedAt = Date()
        profiles.removeAll { $0.id == saved.id }
        profiles.insert(saved, at: 0)
        persist()
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    func duplicate(id: UUID) {
        guard var copy = profiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = "\(copy.displayName) Copy"
        copy.updatedAt = Date()
        profiles.insert(copy, at: 0)
        persist()
    }

    @discardableResult
    func dryRun(_ profile: DatabaseConnectionProfile) -> DatabaseConnectionDryRunResult {
        let result = Self.dryRun(profile, fileManager: fileManager)
        lastDryRun = result
        return result
    }

    static func dryRun(
        _ profile: DatabaseConnectionProfile,
        fileManager: FileManager = .default
    ) -> DatabaseConnectionDryRunResult {
        let errors = validationErrors(for: profile)
        guard errors.isEmpty else {
            return .init(status: .failed, message: errors.joined(separator: " "))
        }

        guard let engine = profile.engine else {
            return .init(status: .failed, message: "Unsupported engine.")
        }

        if engine.supportsFileOpen {
            let path = expanded(profile.hostOrPath)
            if fileManager.fileExists(atPath: path) {
                return .init(status: .passed, message: "\(engine.label) file profile is reachable.")
            }
            return .init(status: .failed, message: "Database file does not exist.")
        }

        return .init(
            status: .externalPending,
            message: "Profile is complete. Real connectivity requires explicit approval before opening a network session."
        )
    }

    static func validationErrors(for profile: DatabaseConnectionProfile) -> [String] {
        var errors: [String] = []
        guard let engine = profile.engine else {
            return ["Select a supported engine."]
        }
        if profile.displayName == "Untitled connection" {
            errors.append("Name is required.")
        }
        let target = profile.hostOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty {
            errors.append(engine.supportsFileOpen ? "File path is required." : "Host is required.")
        }
        if !engine.supportsFileOpen {
            guard let port = profile.port, (1...65_535).contains(port) else {
                errors.append("Port must be between 1 and 65535.")
                return errors
            }
        }
        if profile.sshEnabled {
            if !engine.supportsSSH {
                errors.append("\(engine.label) does not support SSH tunneling in this profile.")
            }
            if profile.sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("SSH host is required.")
            }
            if !(1...65_535).contains(profile.sshPort) {
                errors.append("SSH port must be between 1 and 65535.")
            }
            if profile.sshUsesPrivateKey && profile.sshPrivateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("SSH private key path is required.")
            }
        }
        if profile.sslMode != .disabled && !engine.supportsSSL {
            errors.append("\(engine.label) does not support SSL settings in this profile.")
        }
        return errors
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode([DatabaseConnectionProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }

    private func normalized(_ profile: DatabaseConnectionProfile) -> DatabaseConnectionProfile {
        var copy = profile
        if let engine = copy.engine {
            if engine.supportsFileOpen {
                copy.port = nil
                copy.sshEnabled = false
                if !engine.supportsSSL { copy.sslMode = .disabled }
            } else if copy.port == nil {
                copy.port = engine.defaultPort
            }
        }
        return copy
    }

    static func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
