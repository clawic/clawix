import SwiftUI
import SecretsModels
import SecretsVault

struct SecretDetailPane: View {
    @EnvironmentObject private var vault: SecretsManager
    @EnvironmentObject private var appState: AppState
    let secret: SecretRecord

    @State private var fields: [SecretFieldRecord] = []
    @State private var revealed: [String: String] = [:]
    @State private var notes: String? = nil
    @State private var error: String?
    @State private var events: [DecryptedAuditEvent] = []
    @State private var copiedField: String? = nil
    @State private var titleCopiedFlash: Bool = false
    @State private var permissionsSheetOpen: Bool = false
    @State private var grantsSheetOpen: Bool = false
    @State private var activitySheetOpen: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if secret.isCompromised {
                    InfoBanner(
                        text: "This secret is marked as compromised. Reveal and copy still work for forensics, but rotate the underlying credential elsewhere ASAP.",
                        kind: .danger
                    )
                }

                if let error {
                    InfoBanner(text: error, kind: .error)
                }

                fieldsStack
                if let notesText = notes, !notesText.isEmpty {
                    notesCard(notesText)
                }
                metaGrid
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .thinScrollers()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { reloadAll() }
        .onChange(of: secret.id) { _, _ in reloadAll() }
        .sheet(isPresented: $permissionsSheetOpen) {
            DetailModalSheet(
                title: "Permissions",
                subtitle: secret.title,
                isPresented: $permissionsSheetOpen
            ) {
                PermissionsTab(secret: secret, onChanged: { reloadEvents() })
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $grantsSheetOpen) {
            DetailModalSheet(
                title: "Agent grants",
                subtitle: secret.title,
                isPresented: $grantsSheetOpen
            ) {
                GrantsTab(secret: secret, onChanged: { reloadEvents() })
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $activitySheetOpen) {
            DetailModalSheet(
                title: "Activity",
                subtitle: "\(events.count) event\(events.count == 1 ? "" : "s")",
                isPresented: $activitySheetOpen
            ) {
                activitySheetBody
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            iconTile
            VStack(alignment: .leading, spacing: 7) {
                titleRow
                chipRow
            }
            Spacer(minLength: 12)
            actionsCluster
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.105))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            SecretKindIcon(kind: secret.kind, size: 28, color: Palette.textPrimary)
        }
        .frame(width: 60, height: 60)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: secret.title)
                .font(BodyFont.system(size: 19, wght: 700))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if secret.isCompromised {
                LucideIcon(.shieldAlert, size: 12)
                    .foregroundColor(Color.red.opacity(0.85))
            }
            if titleCopiedFlash {
                Text("Title copied")
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Color.green.opacity(0.85))
                    .transition(.opacity)
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            chip(secret.kind.friendlyLabel, leadingDot: false)
            chip(secret.internalName, leadingDot: true)
        }
    }

    private func chip(_ text: String, leadingDot: Bool) -> some View {
        HStack(spacing: 5) {
            if leadingDot {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 3, height: 3)
            }
            Text(verbatim: text)
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var actionsCluster: some View {
        HStack(spacing: 6) {
            IconChipButton(symbol: "list.bullet.rectangle", label: "Activity") {
                activitySheetOpen = true
            }
            actionsMenu
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Copy title") { copyTitle() }
            Divider()
            Button("Permissions") { permissionsSheetOpen = true }
            Button("Agent grants") { grantsSheetOpen = true }
            Divider()
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
            LucideIcon(.ellipsis, size: 13)
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

    // MARK: - Fields

    private var fieldsStack: some View {
        Group {
            if fields.isEmpty {
                emptyStateCard(symbol: "key", text: "This version has no fields.")
            } else {
                VStack(spacing: 10) {
                    ForEach(fields, id: \.id) { field in
                        FieldCard(
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
        }
    }

    private func notesCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("notes")
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: text)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DetailCardBackground())
    }

    // MARK: - Meta grid

    private var metaGrid: some View {
        HStack(alignment: .top, spacing: 10) {
            metaCard(label: "last modified", value: formatTimestamp(secret.updatedAt))
            metaCard(label: "created",       value: formatTimestamp(secret.createdAt))
        }
    }

    private func metaCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: value)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DetailCardBackground())
    }

    private func emptyStateCard(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            LucideIcon.auto(symbol, size: 15.5)
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: text)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 28)
        .background(DetailCardBackground())
    }

    // MARK: - Activity sheet body

    @ViewBuilder
    private var activitySheetBody: some View {
        if events.isEmpty {
            emptyStateCard(symbol: "clock", text: "No events yet for this secret.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    if idx > 0 {
                        CardDivider()
                    }
                    EventRow(event: event)
                }
            }
            .background(DetailCardBackground())
        }
    }

    // MARK: - Helpers

    private func displayValue(for field: SecretFieldRecord) -> String {
        if !field.isSecret { return field.publicValue ?? "—" }
        if let revealedValue = revealed[field.fieldName] {
            return revealedValue
        }
        return "••••••••••••"
    }

    private func formatTimestamp(_ ts: Timestamp) -> String {
        let date = ts.asDate
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        if revealed[field.fieldName] != nil {
            withAnimation(.easeOut(duration: 0.18)) {
                revealed[field.fieldName] = nil
            }
            return
        }
        Task { @MainActor in
            do {
                try await SecretsReauthentication.require(reason: "Reveal this secret value in Clawix.")
                guard let store = vault.store else { return }
                let r = try store.revealField(field, purpose: .reveal)
                withAnimation(.easeOut(duration: 0.18)) {
                    revealed[field.fieldName] = r.value
                }
                reloadEvents()
            } catch {
                self.error = String(describing: error)
            }
        }
    }

    private func copyValue(_ field: SecretFieldRecord) {
        Task { @MainActor in
            do {
                try await SecretsReauthentication.require(reason: "Copy this secret value from Clawix.")
                guard let store = vault.store else { return }
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
    }

    private func copyTitle() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(secret.title, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { titleCopiedFlash = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeOut(duration: 0.25)) { titleCopiedFlash = false }
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

// MARK: - Field card

private struct FieldCard: View {
    let field: SecretFieldRecord
    let displayValue: String
    let isRevealed: Bool
    let isCopiedFlashing: Bool
    let onToggleReveal: () -> Void
    let onCopy: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: field.fieldName.lowercased())
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                if isCopiedFlashing {
                    Text("Copied")
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(Color.green.opacity(0.85))
                        .transition(.opacity)
                }
                if field.placement != .none {
                    miniBadge(field.placement.rawValue)
                }
                miniBadge(field.fieldKind.rawValue)
            }
            HStack(spacing: 6) {
                Text(verbatim: displayValue)
                    .font(.system(size: 13, weight: .regular, design: valueDesign))
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: hovered ? 0.10 : 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var valueDesign: Font.Design {
        // Public scalars (display name, hint) read better in the body
        // font; the actual secret material uses mono so the eye lands on
        // every character.
        field.isSecret ? .monospaced : .default
    }

    private func miniBadge(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BodyFont.system(size: 9.5, wght: 600))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
    }
}

// MARK: - Card background

private struct DetailCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Modal wrapper for Permissions / Grants / Activity

private struct DetailModalSheet<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BodyFont.system(size: 17, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(verbatim: subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 13)
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScrollers()
        }
        .frame(width: 560, height: 540)
        .sheetStandardBackground()
    }
}
