import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

enum IntelligenceLevel: String, CaseIterable, Identifiable {
    case low, medium, high, extra
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low:    return String(localized: "Low", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .medium: return String(localized: "Medium", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .high:   return String(localized: "High", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .extra:  return String(localized: "Extra high", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var clawixEffort: String {
        switch self {
        case .low:    return "low"
        case .medium: return "medium"
        case .high:   return "high"
        case .extra:  return "xhigh"
        }
    }
}

enum SpeedLevel: String, CaseIterable, Identifiable {
    case standard, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return String(localized: "Standard", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "Fast", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
    var description: String {
        switch self {
        case .standard: return String(localized: "Default speed, normal usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "1.5x faster speed, higher usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
}

enum PermissionMode: String, CaseIterable, Identifiable {
    case defaultPermissions, autoReview, fullAccess
    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultPermissions: return String(localized: "Default permissions", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .autoReview:         return String(localized: "Automatic review", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fullAccess:         return String(localized: "Full access", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var iconName: String {
        switch self {
        case .defaultPermissions: return "hand.raised"
        case .autoReview:         return "checkmark.shield"
        case .fullAccess:         return "exclamationmark.octagon"
        }
    }

    var accent: Color {
        switch self {
        case .defaultPermissions: return Color(white: 0.78)
        case .autoReview:         return Color(red: 0.34, green: 0.62, blue: 1.0)
        case .fullAccess:         return Color(red: 0.95, green: 0.50, blue: 0.20)
        }
    }

    /// Maps to the Codex daemon `approval_policy` accepted by
    /// `thread/start`. Default permissions surfaces approval requests
    /// for actions the sandbox can't authorise on its own; the other
    /// two never prompt.
    var codexApprovalPolicy: String {
        switch self {
        case .defaultPermissions: return "on-request"
        case .autoReview:         return "never"
        case .fullAccess:         return "never"
        }
    }

    /// Maps to the Codex daemon `sandbox_mode` accepted by
    /// `thread/start`. Workspace-write keeps Codex inside the project
    /// cwd; danger-full-access drops the sandbox entirely.
    var codexSandbox: String {
        switch self {
        case .defaultPermissions: return "workspace-write"
        case .autoReview:         return "workspace-write"
        case .fullAccess:         return "danger-full-access"
        }
    }

    static let userDefaultsKey = "ClawixPermissionMode"

    static func loadPersisted() -> PermissionMode {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: userDefaultsKey),
           let mode = PermissionMode(rawValue: raw) {
            return mode
        }
        return .defaultPermissions
    }

    func persist() {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        defaults.set(rawValue, forKey: PermissionMode.userDefaultsKey)
    }
}

enum AgentRuntimeChoice: String, CaseIterable, Identifiable {
    case codex
    case opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    static let runtimeKey = "ClawixAgentRuntime"
    static let openCodeModelKey = "ClawixOpenCodeModel"
    static let defaultOpenCodeModel = "deepseekv4/deepseek-v4-pro"

    @MainActor
    static func visibleCases() -> [AgentRuntimeChoice] {
        FeatureFlags.shared.isVisible(.openCode) ? allCases : [.codex]
    }

    @MainActor
    static func loadPersisted() -> AgentRuntimeChoice {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: runtimeKey),
           let runtime = AgentRuntimeChoice(rawValue: raw) {
            if runtime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                return .codex
            }
            return runtime
        }
        return .codex
    }

    static func persistedOpenCodeModel() -> String {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        return defaults.string(forKey: openCodeModelKey) ?? defaultOpenCodeModel
    }

    @MainActor
    static func persist(runtime: AgentRuntimeChoice, openCodeModel: String) {
        let resolvedRuntime: AgentRuntimeChoice = {
            if runtime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                return .codex
            }
            return runtime
        }()
        for defaults in [
            UserDefaults(suiteName: appPrefsSuite) ?? .standard,
            UserDefaults(suiteName: "clawix.bridge") ?? .standard
        ] {
            defaults.set(resolvedRuntime.rawValue, forKey: runtimeKey)
            defaults.set(openCodeModel, forKey: openCodeModelKey)
        }
    }
}

enum Personality: String, CaseIterable, Identifiable {
    case friendly
    case pragmatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friendly:  return "Friendly"
        case .pragmatic: return "Pragmatic"
        }
    }

    var blurb: String {
        switch self {
        case .friendly:  return "Warm, collaborative, and helpful"
        case .pragmatic: return "Concise, task-focused, and direct"
        }
    }

    static let userDefaultsKey = "ClawixPersonality"

    static func loadPersisted() -> Personality {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: userDefaultsKey),
           let value = Personality(rawValue: raw) {
            return value
        }
        return .pragmatic
    }

    func persist() {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        defaults.set(rawValue, forKey: Personality.userDefaultsKey)
    }
}

struct ComposerAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    var filename: String { url.lastPathComponent }

    var isImage: Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"]
        return imageExts.contains(url.pathExtension.lowercased())
    }
}

struct FindMatch: Equatable, Identifiable {
    let id = UUID()
    let messageId: UUID
    let range: NSRange

    static func == (lhs: FindMatch, rhs: FindMatch) -> Bool {
        lhs.messageId == rhs.messageId
            && lhs.range.location == rhs.range.location
            && lhs.range.length == rhs.range.length
    }
}

final class ComposerState: ObservableObject {
    @Published var text: String = ""
    /// Files staged in the composer (paperclip menu / drag-and-drop /
    /// future paste). On `sendMessage` each url is prepended to the
    /// outgoing text as `@<path>` and the array is cleared.
    @Published var attachments: [ComposerAttachment] = []
    /// Bumped whenever something wants to pull keyboard focus back into
    /// the composer (e.g. ⌘N from home, switching chats from the
    /// sidebar). The composer text editor watches this token and calls
    /// `makeFirstResponder` on change.
    @Published var focusToken: Int = 0
}
