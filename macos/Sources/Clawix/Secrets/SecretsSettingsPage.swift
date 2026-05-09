import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SecretsModels
import SecretsVault

/// Settings page that aggregates all the power-user surfaces of the secrets
/// vault: CLI install, import / export, audit jump, integrity check,
/// danger-zone reset. Lives in the main Settings sidebar under the
/// "Secrets" entry; the Secrets vault data lives in the dedicated
/// `secretsHome` route, this is just the operations panel.
struct SecretsSettingsPage: View {
    @EnvironmentObject private var vault: VaultManager
    @EnvironmentObject private var appState: AppState

    @State private var importPreview: ImportPreview?
    @State private var importPreviewFormat: VaultManager.ImportFormat?
    @State private var importBanner: String?
    @State private var importErrorBanner: String?
    @State private var integrityResult: AuditIntegrityReport?
    @State private var symlinkResult: String?
    @State private var showBackupSheet = false
    @State private var showRestoreSheet = false
    @State private var pendingBackupData: Data?
    @AppStorage("secrets.advancedExpanded") private var advancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: "Secrets vault",
                    subtitle: "Store API keys and passwords for Codex. Import what you have, keep it backed up, keep it private."
                )

                if let banner = importBanner {
                    InfoBanner(text: banner, kind: .ok)
                        .padding(.bottom, 4)
                }
                if let banner = importErrorBanner {
                    InfoBanner(text: banner, kind: .error)
                        .padding(.bottom, 4)
                }

                setupBanner

                cliSection
                importsSection
                backupSection

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    auditSection
                        .padding(.top, 12)
                } label: {
                    Text("Advanced")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                }
                .padding(.top, 28)
                .padding(.bottom, 8)

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
        }
        .thinScrollers()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .sheet(isPresented: $showBackupSheet) {
            BackupExportSheet(isPresented: $showBackupSheet)
        }
        .sheet(isPresented: $showRestoreSheet) {
            BackupImportSheet(isPresented: $showRestoreSheet, data: pendingBackupData ?? Data())
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var cliSection: some View {
        SectionLabel(title: "Codex CLI helper")
        SettingsCard {
            SettingsRow {
                statusLabel(
                    title: "Codex shell access",
                    detail: symlinkInstalled
                        ? "Installed at ~/bin/clawix-secrets-proxy."
                        : "Not installed. Codex can’t read your vault from the shell yet."
                )
            } trailing: {
                IconChipButton(
                    symbol: "link",
                    label: symlinkInstalled ? "Reinstall" : "Install",
                    isPrimary: !symlinkInstalled,
                    action: installSymlink
                )
            }
            if let symlinkResult {
                Text(symlinkResult)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color.green.opacity(0.78))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var auditSection: some View {
        SectionLabel(title: "Audit")
        SettingsCard {
            SettingsRow {
                RowLabel(
                    title: "Open the activity log",
                    detail: "Browse every event the vault has logged."
                )
            } trailing: {
                IconChipButton(
                    symbol: "arrow.up.right.square",
                    label: "Open",
                    action: { appState.currentRoute = .secretsHome }
                )
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Check audit log integrity",
                    detail: "Confirm no events were tampered with or deleted."
                )
            } trailing: {
                IconChipButton(
                    symbol: "checkmark.shield",
                    label: "Verify",
                    action: runIntegrity
                )
            }
            if let report = integrityResult {
                Text(verbatim: integritySummary(report))
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(report.isIntact ? Color.green.opacity(0.78) : Color.red.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var importsSection: some View {
        SectionLabel(title: "Import secrets")
        SettingsCard {
            SettingsRow {
                RowLabel(
                    title: "Bring secrets from another manager",
                    detail: "1Password, Bitwarden, or a .env file."
                )
            } trailing: {
                importMenu(label: "Import…")
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        SectionLabel(title: "Encrypted backup")
        SettingsCard {
            SettingsRow {
                RowLabel(
                    title: "Export vault to file",
                    detail: "Pack everything into one encrypted file you can keep on a USB drive or another Mac."
                )
            } trailing: {
                IconChipButton(
                    symbol: "arrow.up.doc",
                    label: "Export…",
                    isPrimary: true,
                    action: { showBackupSheet = true }
                )
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Restore from a backup file",
                    detail: "Pick a .clawixvault. Existing secrets keep their newest version."
                )
            } trailing: {
                IconChipButton(
                    symbol: "arrow.down.doc",
                    label: "Choose file…",
                    action: pickRestoreFile
                )
            }
        }
    }

    @ViewBuilder
    private var setupBanner: some View {
        if !symlinkInstalled {
            setupBannerCard(
                icon: "exclamationmark.shield.fill",
                tint: Color.orange,
                title: "Codex can’t read your vault yet",
                detail: "Install the helper so the Codex shell command can use the secrets you store here."
            ) {
                IconChipButton(
                    symbol: "link",
                    label: "Install",
                    isPrimary: true,
                    action: installSymlink
                )
            }
        } else if vault.secrets.isEmpty {
            setupBannerCard(
                icon: "info.circle.fill",
                tint: Color.blue.opacity(0.85),
                title: "Your vault is empty",
                detail: "Bring your existing passwords from 1Password, Bitwarden, or a .env file."
            ) {
                importMenu(label: "Import…")
            }
        }
    }

    private func setupBannerCard<CTA: View>(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder cta: () -> CTA
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            LucideIcon.auto(icon, size: 16)
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            cta()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.40), lineWidth: 0.7)
                )
        )
        .padding(.bottom, 6)
    }

    private func importMenu(label: LocalizedStringKey) -> some View {
        Menu {
            Button("1Password CSV") {
                pickAndImport(format: .onePassword, allowed: [.commaSeparatedText, .plainText])
            }
            Button("Bitwarden CSV") {
                pickAndImport(format: .bitwarden, allowed: [.commaSeparatedText, .plainText])
            }
            Button(".env file") {
                pickAndImport(format: .env, allowed: [.plainText, .data])
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon.auto("doc", size: 11)
                    .foregroundColor(Palette.textPrimary)
                Text(label)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
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

    // The Status row shows a runtime-derived detail string (the
    // symlink path or the not-installed warning). RowLabel takes
    // LocalizedStringKey, which can't accept a runtime String at the
    // call site, so the equivalent VStack is rendered inline here.
    private func statusLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
            Text(verbatim: detail)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func integritySummary(_ report: AuditIntegrityReport) -> String {
        if report.isIntact {
            return "Audit chain intact, \(report.totalEvents) events verified."
        }
        return "Audit chain broken at event \(report.firstBrokenAt?.uuidString ?? "?")"
    }

    // MARK: - Helpers

    // The legacy UDS proxy + CLI symlink are gone: the bundled `claw`
    // CLI lives inside the .app at Contents/Helpers/clawjs and is
    // invoked directly by the app and by scripts-dev wrappers.
    private var symlinkInstalled: Bool { false }

    private func installSymlink() {
        if let url = vault.installCliSymlink() {
            symlinkResult = "Installed at \(url.path)"
        } else {
            symlinkResult = vault.lastError ?? "Could not install symlink (helper not found in app bundle?)"
        }
    }

    private func runIntegrity() {
        integrityResult = vault.runIntegrityCheck()
    }

    private func pickAndImport(format: VaultManager.ImportFormat, allowed: [UTType]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowed
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose a file to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let preview = try vault.importSecrets(from: text, format: format)
            importBanner = "Imported \(preview.drafts.count) secret\(preview.drafts.count == 1 ? "" : "s") from \(preview.format)" +
                (preview.warnings.isEmpty ? "." : ". \(preview.warnings.count) warning\(preview.warnings.count == 1 ? "" : "s") (rows skipped).")
            importErrorBanner = nil
        } catch {
            importErrorBanner = "Import failed: \(error)"
            importBanner = nil
        }
    }

    private func pickRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.title = "Choose a .clawixvault backup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard BackupCodec.verifyMagic(data: data) else {
                importErrorBanner = "Not a valid .clawixvault file (magic header mismatch)."
                return
            }
            pendingBackupData = data
            showRestoreSheet = true
        } catch {
            importErrorBanner = "Could not read file: \(error)"
        }
    }
}

// MARK: - Backup sheets

private struct BackupExportSheet: View {
    @EnvironmentObject private var vault: VaultManager
    @Binding var isPresented: Bool
    @State private var passphrase: String = ""
    @State private var passphraseConfirm: String = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Export encrypted backup")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Palette.textSecondary)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            Text("Pick a passphrase to protect the backup. It is independent of the vault master password and is required to restore.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
            VaultCard {
                VStack(spacing: 12) {
                    VaultPasswordField(placeholder: "Backup passphrase", text: $passphrase)
                    VaultPasswordField(placeholder: "Confirm passphrase", text: $passphraseConfirm)
                    if let error { VaultErrorLine(text: error) }
                    HStack(spacing: 10) {
                        VaultSecondaryButton(title: "Cancel") { isPresented = false }
                        VaultPrimaryButton(
                            title: "Export and choose location…",
                            isLoading: isWorking,
                            isEnabled: passphrase.count >= 8 && passphrase == passphraseConfirm
                        ) {
                            export()
                        }
                    }
                }
            }
        }
        .frame(width: 420)
        .padding(22)
        .background(Color(white: 0.07))
    }

    private func export() {
        guard passphrase == passphraseConfirm, passphrase.count >= 8 else {
            error = "Passphrase too short or doesn't match."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let data = try vault.exportEncryptedBackup(passphrase: passphrase)
                let panel = NSSavePanel()
                panel.title = "Save vault backup"
                panel.nameFieldStringValue = "clawix.clawixvault"
                panel.allowedContentTypes = [.data]
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url, options: .atomic)
                    isPresented = false
                }
            } catch {
                self.error = String(describing: error)
            }
        }
    }
}

private struct BackupImportSheet: View {
    @EnvironmentObject private var vault: VaultManager
    @Binding var isPresented: Bool
    let data: Data
    @State private var passphrase: String = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var resultText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Restore encrypted backup")
                    .font(BodyFont.system(size: 15.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Palette.textSecondary)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            Text("Enter the passphrase that was used when this backup was exported. Existing secrets with the same internal name will be skipped.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
            VaultCard {
                VStack(spacing: 12) {
                    VaultPasswordField(placeholder: "Backup passphrase", text: $passphrase)
                    if let error { VaultErrorLine(text: error) }
                    if let resultText {
                        Text(resultText)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Color.green.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        VaultSecondaryButton(title: "Cancel") { isPresented = false }
                        VaultPrimaryButton(title: "Restore", isLoading: isWorking, isEnabled: !passphrase.isEmpty) {
                            restore()
                        }
                    }
                }
            }
        }
        .frame(width: 420)
        .padding(22)
        .background(Color(white: 0.07))
    }

    private func restore() {
        guard !passphrase.isEmpty else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try vault.importEncryptedBackup(data, passphrase: passphrase)
                resultText = "Restored \(result.created) secret\(result.created == 1 ? "" : "s"); \(result.skipped) skipped as duplicates."
                error = nil
            } catch {
                self.error = String(describing: error)
                resultText = nil
            }
        }
    }
}
