import Foundation

enum HostActionSurface: String, Codable, CaseIterable {
    case screenTools
    case macUtilities

    var approvalKey: String {
        switch self {
        case .screenTools:
            return HostActionPolicy.screenToolsApprovalKey
        case .macUtilities:
            return HostActionPolicy.macUtilitiesApprovalKey
        }
    }
}

enum HostActionOrigin: String, Codable {
    case userInterface
    case appIntent
    case agent
    case framework

    var isUserApproved: Bool {
        switch self {
        case .userInterface, .appIntent:
            return true
        case .agent, .framework:
            return false
        }
    }
}

enum HostActionPolicy {
    enum Approval: String, Codable, CaseIterable {
        case alwaysAsk
        case alwaysAllow
        case alwaysBlock
    }

    struct Authorization: Equatable {
        let allowed: Bool
        let outcome: String
        let reason: String?
    }

    struct AuditEvent: Codable, Equatable {
        let timestamp: String
        let surface: HostActionSurface
        let action: String
        let origin: HostActionOrigin
        let approval: Approval
        let outcome: String
        let reason: String?
    }

    static let screenToolsApprovalKey = "clawix.hostPolicy.screenTools.approval"
    static let macUtilitiesApprovalKey = "clawix.hostPolicy.macUtilities.approval"
    static let auditFilename = "host-action-audit.jsonl"

    static func approval(
        for surface: HostActionSurface,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    ) -> Approval {
        guard let raw = defaults.string(forKey: surface.approvalKey),
              let approval = Approval(rawValue: raw) else {
            return .alwaysAsk
        }
        return approval
    }

    @discardableResult
    static func authorize(
        surface: HostActionSurface,
        action: String,
        origin: HostActionOrigin,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard,
        auditURL: URL? = nil,
        now: Date = Date()
    ) -> Authorization {
        let policy = approval(for: surface, defaults: defaults)
        let authorization: Authorization
        switch policy {
        case .alwaysAllow:
            authorization = Authorization(allowed: true, outcome: "allowed", reason: nil)
        case .alwaysBlock:
            authorization = Authorization(allowed: false, outcome: "blocked", reason: "Host policy blocks this action.")
        case .alwaysAsk:
            if origin.isUserApproved {
                authorization = Authorization(allowed: true, outcome: "allowed", reason: nil)
            } else {
                authorization = Authorization(
                    allowed: false,
                    outcome: "requiresApproval",
                    reason: "Requires explicit host approval."
                )
            }
        }

        appendAudit(
            AuditEvent(
                timestamp: Self.timestampFormatter.string(from: now),
                surface: surface,
                action: action,
                origin: origin,
                approval: policy,
                outcome: authorization.outcome,
                reason: authorization.reason
            ),
            to: auditURL ?? defaultAuditURL()
        )
        return authorization
    }

    private static func defaultAuditURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Clawix", isDirectory: true)
            .appendingPathComponent(auditFilename)
    }

    private static func appendAudit(_ event: AuditEvent, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(event)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Audit failures must not execute the action silently. The caller
            // still receives the policy decision, and diagnostics carry the
            // audit write problem for local investigation.
            NSLog("Clawix host action audit write failed: \(error.localizedDescription)")
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
