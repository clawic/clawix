import SwiftUI
import SecretsModels

/// Per-kind icon for secret records. Renders Lucide glyphs (key, lock,
/// terminal, database, braces, id-card, badge-check, webhook, file-text,
/// link) so the secrets list reads as part of the same visual family as
/// the rest of the chrome (Settings, sidebar, command palette).
struct SecretKindIcon: View {
    let kind: SecretKind
    var size: CGFloat = 18
    /// Kept for source compatibility with older call sites; Lucide is a
    /// font, so stroke weight comes from the glyph itself.
    var lineWidth: CGFloat = 1.3
    var color: Color = Color(white: 0.86)

    var body: some View {
        LucideIcon(lucideKind, size: size)
            .foregroundColor(color)
            .frame(width: size, height: size)
    }

    private var lucideKind: LucideIcon.Kind {
        switch kind {
        case .apiKey:                return .key
        case .passwordLogin:         return .lock
        case .oauthToken:            return .link
        case .sshIdentity:           return .terminal
        case .databaseUrl:           return .database
        case .envBundle:             return .braces
        case .structuredCredentials: return .idCard
        case .certificate:           return .badgeCheck
        case .webhookSecret:         return .webhook
        case .secureNote:            return .fileText
        }
    }
}

extension SecretKind {
    /// Human-readable category label used in the list subtitle and any
    /// other piece of chrome that needs a one-shot description of the
    /// kind. Distinct from `rawValue`, which is the persisted snake_case
    /// id meant for storage and the proxy wire format.
    var friendlyLabel: String {
        switch self {
        case .apiKey:                return "API key"
        case .passwordLogin:         return "Password"
        case .oauthToken:            return "OAuth token"
        case .sshIdentity:           return "SSH key"
        case .databaseUrl:           return "Database URL"
        case .envBundle:             return "Env bundle"
        case .structuredCredentials: return "Credentials"
        case .certificate:           return "Certificate"
        case .webhookSecret:         return "Webhook"
        case .secureNote:            return "Note"
        }
    }
}
