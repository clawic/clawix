import SwiftUI

/// Modal form for connecting a channel account against one of the
/// concrete adapters (`bluesky`, `mastodon`, `devnull`). The fields and
/// their validation are derived from the family id; the rest of publishing's
/// 56 skeleton families do not surface this sheet (the Channels list
/// shows "Coming soon" for them).
struct PublishingConnectSheet: View {
    let family: ClawJSPublishingClient.Family
    let onClose: () -> Void

    @EnvironmentObject private var manager: PublishingManager
    @State private var fields: [String: String] = [:]
    @State private var submitting = false
    @State private var errorMessage: String?

    private var spec: [Field] {
        switch family.id {
        case "bluesky":
            return [
                .init(key: "identifier", label: "Handle", placeholder: "handle.bsky.social", isSecure: false),
                .init(key: "password",  label: "App password", placeholder: "App password", isSecure: true),
                .init(key: "pds",       label: "PDS (optional)", placeholder: "https://bsky.social", isSecure: false),
            ]
        case "mastodon":
            return [
                .init(key: "instance_url", label: "Instance URL", placeholder: "https://mastodon.social", isSecure: false),
                .init(key: "access_token", label: "Access token", placeholder: "Access token", isSecure: true),
            ]
        case "devnull":
            return [
                .init(key: "display_name",       label: "Display name", placeholder: "Test", isSecure: false),
                .init(key: "provider_account_id", label: "Provider account id", placeholder: "smoke", isSecure: false),
            ]
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Connect \(family.name)")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: family.group.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(BodyFont.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(spec, id: \.key) { field in
                    fieldRow(field)
                }
            }

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.85))
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Cancel") { onClose() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Button("Connect") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitting || !validates)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Palette.background)
    }

    private var validates: Bool {
        for field in spec {
            if field.label.contains("optional") { continue }
            let value = fields[field.key] ?? ""
            if value.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        }
        return true
    }

    @ViewBuilder
    private func fieldRow(_ field: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: field.label)
                .font(BodyFont.system(size: 11.5, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            Group {
                if field.isSecure {
                    SecureField(field.placeholder, text: binding(for: field.key))
                } else {
                    TextField(field.placeholder, text: binding(for: field.key))
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
            .foregroundColor(Palette.textPrimary)
            .font(BodyFont.system(size: 12.5, weight: .regular))
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { fields[key] ?? "" },
            set: { fields[key] = $0 }
        )
    }

    private func submit() {
        submitting = true
        errorMessage = nil
        let payload = fields.compactMapValues { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let familyId = family.id
        Task { @MainActor in
            defer { submitting = false }
            do {
                _ = try await manager.connect(familyId: familyId, payload: payload)
                onClose()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    struct Field {
        let key: String
        let label: String
        let placeholder: String
        let isSecure: Bool
    }
}
