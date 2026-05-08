import SwiftUI
import SecretsModels
import SecretsVault

struct SecretsAuditView: View {
    @EnvironmentObject private var vault: VaultManager
    let onBack: () -> Void

    @State private var events: [DecryptedAuditEvent] = []
    @State private var selectedKindFilter: AuditEventKind?
    @State private var error: String?

    private let filterKinds: [AuditEventKind] = [
        .adminCreate, .uiReveal, .uiCopy, .adminTrash, .adminPurge,
        .vaultUnlock, .vaultLock, .vaultPasswordChange, .vaultRecoveryUsed, .auditIntegrityFailed
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            kindFilterStrip
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconChipButton(
                symbol: "chevron.left",
                label: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Activity log")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if let report = vault.integrityReport {
                    integrityBadge(report)
                } else {
                    Text(verbatim: "\(events.count) events")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer()
            IconChipButton(
                symbol: "checkmark.shield",
                label: "Verify integrity",
                isPrimary: true,
                action: {
                    _ = vault.runIntegrityCheck()
                    reload()
                }
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func integrityBadge(_ report: AuditIntegrityReport) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(report.isIntact ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            if report.isIntact {
                Text(verbatim: "Chain intact · \(report.totalEvents) events verified")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.green.opacity(0.8))
            } else {
                Text("Chain broken at first compromised event")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color.red.opacity(0.85))
            }
        }
    }

    private var kindFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(
                    label: "All",
                    active: selectedKindFilter == nil,
                    action: { setFilter(nil) }
                )
                ForEach(filterKinds, id: \.self) { kind in
                    FilterChip(
                        label: kind.rawValue.replacingOccurrences(of: "_", with: " "),
                        active: selectedKindFilter == kind,
                        action: { setFilter(kind) }
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
        .animation(.easeOut(duration: 0.18), value: selectedKindFilter)
    }

    private var content: some View {
        Group {
            if let error {
                errorState(error)
            } else if events.isEmpty {
                emptyState
            } else {
                listState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            InfoBanner(text: message, kind: .error)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 64, height: 64)
                LucideIcon(.clock, size: 26)
                    .foregroundColor(Palette.textSecondary)
            }
            VStack(spacing: 4) {
                Text("No events to show")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(emptySubtitle)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySubtitle: String {
        if selectedKindFilter == nil {
            return "Activity is recorded as you create, reveal, or copy secrets. The log will fill up with use."
        }
        return "No \(selectedKindFilter!.rawValue.replacingOccurrences(of: "_", with: " ")) events recorded yet for this filter."
    }

    private var listState: some View {
        ScrollView {
            SettingsCard {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                    if idx > 0 {
                        CardDivider()
                    }
                    EventRow(event: event)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .thinScrollers()
        .transition(.opacity)
        .id(selectedKindFilter)
    }

    private func setFilter(_ kind: AuditEventKind?) {
        selectedKindFilter = kind
        reload()
    }

    private func reload() {
        guard let audit = vault.audit else {
            events = []
            return
        }
        do {
            let filter = AuditEventFilter(kinds: selectedKindFilter.map { [$0] } ?? [])
            events = try audit.filteredEvents(filter, limit: 500)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct EventRow: View {
    let event: DecryptedAuditEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sourceIcon
                .frame(width: 24, height: 24, alignment: .top)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: event.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    if let name = event.payload.secretInternalNameFrozen {
                        Text(verbatim: "· \(name)")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer(minLength: 12)
                    Text(verbatim: EventRow.formatter.localizedString(for: event.timestamp.asDate, relativeTo: Date()))
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                if let notes = event.payload.notes {
                    Text(verbatim: notes)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.72))
                }
                if let host = event.payload.host {
                    Text(verbatim: "→ \(host)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        let symbol: String = {
            switch event.source {
            case .ui: return "person.crop.circle"
            case .admin: return "wrench.and.screwdriver"
            case .proxy: return "arrow.right.arrow.left"
            case .system: return "gear"
            }
        }()
        LucideIcon.auto(symbol, size: 11.5)
            .foregroundColor(eventColor)
            .padding(5)
            .background(Circle().fill(Color.white.opacity(0.07)))
    }

    private var eventColor: Color {
        switch event.kind {
        case .auditIntegrityFailed, .anomalyDetected, .vaultFailedUnlock:
            return Color.red.opacity(0.85)
        case .uiReveal, .uiCopy:
            return Color.orange.opacity(0.85)
        case .adminCreate, .adminEdit, .vaultSetup, .vaultPasswordChange, .vaultRecoveryUsed:
            return Color.green.opacity(0.85)
        default:
            return Palette.textPrimary
        }
    }

    static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
