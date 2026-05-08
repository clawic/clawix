import SwiftUI
import SecretsModels
import SecretsVault

struct SecretDetailPane: View {
    @EnvironmentObject private var vault: VaultManager
    @EnvironmentObject private var appState: AppState
    let secret: SecretRecord

    enum DetailTab: Hashable { case overview, permissions, activity, grants }

    @State private var fields: [SecretFieldRecord] = []
    @State private var revealed: [String: String] = [:]
    @State private var notes: String? = nil
    @State private var error: String?
    @State private var tab: DetailTab = .overview
    @State private var events: [DecryptedAuditEvent] = []
    @State private var copiedField: String? = nil
    @State private var menuOpen: Bool = false

    private var tabOptions: [(DetailTab, String)] {
        [
            (.overview,    "Overview"),
            (.permissions, "Permissions"),
            (.activity,    "Activity \(events.count)"),
            (.grants,      "Grants")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            SlidingSegmented(
                selection: $tab,
                options: tabOptions,
                height: 30,
                fontSize: 11.5
            )
            .frame(maxWidth: 480)
            .padding(.bottom, 16)

            if secret.isCompromised {
                InfoBanner(
                    text: "This secret is marked as compromised. Reveal and copy still work for forensics, but rotate the underlying credential elsewhere ASAP.",
                    kind: .danger
                )
                .padding(.bottom, 14)
            }

            if let error {
                InfoBanner(text: error, kind: .error)
                    .padding(.bottom, 12)
            }

            tabBody
                .id(tab)
                .transition(.opacity.combined(with: .softNudge(y: 3)))
                .animation(.easeOut(duration: 0.18), value: tab)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { reloadAll() }
        .onChange(of: secret.id) { _, _ in reloadAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: secret.title)
                    .font(BodyFont.system(size: 18, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 6) {
                    badge(secret.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                    Text(verbatim: secret.internalName)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer(minLength: 12)
            actionsMenu
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button(secret.isCompromised ? "Clear compromise flag" : "Mark as compromised") {
                toggleCompromised()
            }
            Divider()
            Button(role: .destructive) {
                requestMoveToTrash()
            } label: {
                Text("Move to trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(white: 0.135))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Tab body

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .overview:
            overviewContent
        case .permissions:
            PermissionsTab(secret: secret, onChanged: { reloadEvents() })
        case .activity:
            activityContent
        case .grants:
            GrantsTab(secret: secret, onChanged: { reloadEvents() })
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Fields")
                .padding(.top, 0)

            SettingsCard {
                if fields.isEmpty {
                    fieldEmptyState(symbol: "key.slash", text: "This version has no fields.")
                } else {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { idx, field in
                        if idx > 0 {
                            CardDivider()
                        }
                        FieldRow(
                            field: field,
                            displayValue: displayValue(for: field),
                            isRevealed: revealed[field.fieldName] != nil,
                            isCopiedFlashing: copiedField == field.fieldName,
                            onToggleReveal: { toggleReveal(field) },
                            onCopy: { copyValue(field) }
                        )
                    }
                }
            }

            if let notesText = notes, !notesText.isEmpty {
                SectionLabel(title: "Notes")
                SettingsCard {
                    Text(verbatim: notesText)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        if events.isEmpty {
            fieldEmptyState(symbol: "clock", text: "No events yet for this secret.")
                .padding(.vertical, 14)
        } else {
            SettingsCard {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    if idx > 0 {
                        CardDivider()
                    }
                    EventRow(event: event)
                }
            }
        }
    }

    private func fieldEmptyState(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: text)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func displayValue(for field: SecretFieldRecord) -> String {
        if !field.isSecret { return field.publicValue ?? "—" }
        if let revealedValue = revealed[field.fieldName] {
            return revealedValue
        }
        return "••••••••••••"
    }

    private func badge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BodyFont.system(size: 10, wght: 600))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }

    private func reloadAll() {
        reloadFields()
        reloadEvents()
    }

    private func reloadFields() {
        guard let store = vault.store else { return }
        do {
            fields = try store.fetchFields(forSecret: secret.id, version: secret.currentVersionId)
            notes = try store.revealNotes(secret: secret)
            revealed = [:]
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func reloadEvents() {
        guard let audit = vault.audit else {
            events = []
            return
        }
        do {
            events = try audit.eventsForSecret(secret.id, limit: 100)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func toggleReveal(_ field: SecretFieldRecord) {
        guard let store = vault.store else { return }
        if revealed[field.fieldName] != nil {
            withAnimation(.easeOut(duration: 0.18)) {
                revealed[field.fieldName] = nil
            }
            return
        }
        do {
            let r = try store.revealField(field, purpose: .reveal)
            withAnimation(.easeOut(duration: 0.18)) {
                revealed[field.fieldName] = r.value
            }
            reloadEvents()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func copyValue(_ field: SecretFieldRecord) {
        guard let store = vault.store else { return }
        do {
            let r = try store.revealField(field, purpose: .copy)
            guard let value = r.value else { return }
            reloadEvents()
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(value, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) {
                copiedField = field.fieldName
            }
            let fieldName = field.fieldName
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if copiedField == fieldName {
                    withAnimation(.easeOut(duration: 0.25)) {
                        copiedField = nil
                    }
                }
            }
            // Auto-clear after the secret's clipboard window.
            let seconds = max(secret.clipboardClearSeconds, 0)
            if seconds > 0 {
                let pasteboardString = value
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                    let pb = NSPasteboard.general
                    if pb.string(forType: .string) == pasteboardString {
                        pb.clearContents()
                    }
                }
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func requestMoveToTrash() {
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Move to trash?",
            body: LocalizedStringKey("'\(secret.title)' will be moved to the trash and auto-purged in 30 days. You can restore it from there until then."),
            confirmLabel: "Move to trash",
            isDestructive: true,
            onConfirm: { moveToTrash() }
        )
    }

    private func moveToTrash() {
        guard let store = vault.store else { return }
        do {
            try store.trashSecret(id: secret.id)
            vault.reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func toggleCompromised() {
        guard let store = vault.store else { return }
        do {
            try store.setCompromised(id: secret.id, flag: !secret.isCompromised)
            vault.reload()
            reloadEvents()
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Field row

private struct FieldRow: View {
    let field: SecretFieldRecord
    let displayValue: String
    let isRevealed: Bool
    let isCopiedFlashing: Bool
    let onToggleReveal: () -> Void
    let onCopy: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: field.fieldName)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                badge(field.fieldKind.rawValue)
                if field.placement != .none {
                    badge(field.placement.rawValue)
                }
                Spacer()
                if isCopiedFlashing {
                    Text("Copied")
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Color.green.opacity(0.85))
                        .transition(.opacity)
                }
            }
            HStack(spacing: 8) {
                Text(verbatim: displayValue)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if field.isSecret {
                    IconCircleButton(symbol: isRevealed ? "eye.slash" : "eye", action: onToggleReveal)
                }
                IconCircleButton(symbol: "doc.on.doc", action: onCopy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MenuRowHover(active: hovered))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private func badge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BodyFont.system(size: 10, wght: 600))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}
