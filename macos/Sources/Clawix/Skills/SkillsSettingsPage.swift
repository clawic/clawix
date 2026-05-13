import SwiftUI

/// Settings tab for the global Skills system. Per-skill configuration
/// (activation, parameters, sync targets) lives in `SkillDetailView`.
/// This page is for everything that applies across the whole library:
///
/// - Registered sync targets (Codex, Hermes, Cursor, custom).
/// - External dirs to scan for auto-import.
/// - Auto-import toggle (default ON).
/// - "Re-sync all" action.
struct SkillsSettingsPage: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("ClawixSkillsAutoImport") private var autoImportEnabled: Bool = true

    @State private var newTargetLabel: String = ""
    @State private var newTargetHome: String = ""

    private var store: SkillsStore? { appState.skillsStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                autoImportCard
                syncTargetsCard
                externalDirsCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skills")
                .font(.system(size: 22, weight: .semibold))
            Text("System-wide settings for the Skills library. Per-skill configuration lives in the catalog.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var autoImportCard: some View {
        sectionCard(title: "Auto-import", subtitle: "On startup, scan the configured external dirs and pull any new SKILL.md files into your central library. Originals get replaced with symlinks back to the central, so the source agents (Codex, Hermes) keep reading from their own paths transparently.") {
            Toggle("Auto-import on startup", isOn: $autoImportEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var syncTargetsCard: some View {
        sectionCard(title: "Sync targets", subtitle: "External agents that receive your skills via filesystem links. Toggle per-skill in the catalog detail panel.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store?.syncTargets ?? []) { target in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label).font(.system(size: 12.5, weight: .medium))
                            Text(target.home)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(target.mode.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                        Button(role: .destructive) {
                            store?.removeSyncTarget(id: target.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.5)
                }

                addTargetRow
            }
        }
    }

    private var addTargetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a target").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            HStack {
                TextField("Label (e.g. \"Cursor · myproject\")", text: $newTargetLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                TextField("Home dir (e.g. ~/path/.cursor/skills)", text: $newTargetHome)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addTarget()
                } label: {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(newTargetLabel.isEmpty || newTargetHome.isEmpty)
            }
        }
        .padding(.top, 6)
    }

    private func addTarget() {
        let label = newTargetLabel.trimmingCharacters(in: .whitespaces)
        let home = newTargetHome.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !home.isEmpty else { return }
        let id = label.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "·", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let expanded = (home as NSString).expandingTildeInPath
        let target = SkillSyncTarget(
            id: id,
            label: label,
            home: expanded,
            mode: .symlink,
            lastSyncedAt: nil,
            lastError: nil
        )
        store?.registerSyncTarget(target)
        newTargetLabel = ""
        newTargetHome = ""
    }

    private var externalDirsCard: some View {
        sectionCard(title: "External dirs (read-only discovery)", subtitle: "Where the auto-importer looks for skills built by other agents. Pulled into your central library on first sight; originals replaced with symlinks back.") {
            VStack(alignment: .leading, spacing: 6) {
                externalDirRow(path: "~/.codex/skills", agent: "Codex CLI")
                externalDirRow(path: "~/.hermes/skills", agent: "HermesAgent")
                Text("Add custom dirs by editing ~/.claw/config.yaml — UI for arbitrary dirs ships in the next iteration.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func externalDirRow(path: String, agent: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(path).font(.system(size: 12, design: .monospaced))
                Text(agent).font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer()
            let exists = FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
            Text(exists ? "found" : "not present")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(exists ? .green : .secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(exists ? Color.green.opacity(0.12) : Color.gray.opacity(0.10)))
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, subtitle: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            content()
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.gray.opacity(0.12), lineWidth: 0.5)
        )
    }
}
