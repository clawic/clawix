import SwiftUI
import AppKit

/// Compact one-row entry for `DictationSettingsPage` that surfaces
/// a count + a Manage button for the history viewer (#24), the
/// cleanup policies (#25), the export buttons (#26), and the metrics
/// view (#27). Keeping all four wired through a single sheet keeps
/// the page itself small and the user goes "Manage" → does what they
/// need.
struct TranscriptHistorySummaryRow: View {
    @ObservedObject var repo: TranscriptionsRepository
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcript history")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Button {
                sheetOpen = true
            } label: {
                Text("Manage")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $sheetOpen) {
            TranscriptHistorySheet(repo: repo, isPresented: $sheetOpen)
        }
    }

    private var detail: LocalizedStringKey {
        let count = repo.recent.count
        if count == 0 {
            return "Nothing yet. Every dictation gets logged here, with audio kept until cleanup or you opt out."
        }
        return "\(count)+ entries · search, export, run cleanup"
    }
}

// MARK: - Sheet (history + metrics + cleanup + export tabs)

struct TranscriptHistorySheet: View {
    @ObservedObject var repo: TranscriptionsRepository
    @Binding var isPresented: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case history, metrics, cleanup, backup
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .history: return "History"
            case .metrics: return "Metrics"
            case .cleanup: return "Cleanup"
            case .backup:  return "Backup"
            }
        }
    }

    @State private var tab: Tab = .history

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dictation data")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 16) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.title)
                            .font(BodyFont.system(size: 12.5, wght: 600))
                            .foregroundColor(tab == item ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tab == item ? Color.white.opacity(0.06) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            switch tab {
            case .history: TranscriptHistoryListView(repo: repo)
            case .metrics: TranscriptMetricsView(repo: repo)
            case .cleanup: TranscriptCleanupView(repo: repo)
            case .backup:  TranscriptBackupView()
            }
        }
        .frame(width: 760, height: 560)
        .background(Color(white: 0.10))
    }
}

// MARK: - History list

private struct TranscriptHistoryListView: View {
    @ObservedObject var repo: TranscriptionsRepository
    @State private var query: String = ""
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .padding(12)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { row in
                            TranscriptListRow(
                                record: row,
                                selected: selection == row.id,
                                onTap: { selection = row.id }
                            )
                            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        }
                    }
                }
                .thinScrollers()
            }
            .frame(width: 280)
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 0.5)

            if let id = selection,
               let row = repo.recent.first(where: { $0.id == id }) {
                TranscriptDetailView(record: row, onDelete: {
                    let target = id
                    selection = nil
                    Task { await repo.delete(id: target) }
                })
            } else {
                VStack {
                    Spacer()
                    Text("Pick a transcript on the left.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = repo.recent.first?.id }
        }
    }

    private var filtered: [TranscriptionRecord] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if needle.isEmpty { return repo.recent }
        return repo.recent.filter { row in
            row.originalText.lowercased().contains(needle)
                || (row.enhancedText?.lowercased().contains(needle) ?? false)
        }
    }
}

private struct TranscriptListRow: View {
    let record: TranscriptionRecord
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timestamp)
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                Text(record.originalText)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle().fill(selected ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var timestamp: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: record.timestamp)
    }
}

private struct TranscriptDetailView: View {
    let record: TranscriptionRecord
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metaRow
                if let enhanced = record.enhancedText {
                    section(title: "Enhanced", body: enhanced, monospaced: false)
                    section(title: "Original", body: record.originalText, monospaced: false)
                } else {
                    section(title: "Transcript", body: record.originalText, monospaced: false)
                }
                HStack {
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(record.enhancedText ?? record.originalText, forType: .string)
                    }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete")
                    }
                }
            }
            .padding(20)
        }
        .thinScrollers()
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            metaLine("Timestamp", value: ISO8601DateFormatter().string(from: record.timestamp))
            if let model = record.modelUsed { metaLine("Model", value: model) }
            if let lang = record.language { metaLine("Language", value: lang) }
            metaLine("Duration", value: String(format: "%.1fs · %d words", record.durationSeconds, record.wordCount))
            if let path = record.audioFilePath {
                metaLine("Audio", value: URL(fileURLWithPath: path).lastPathComponent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private func metaLine(_ key: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func section(title: String, body: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            Text(body)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Metrics

private struct TranscriptMetricsView: View {
    @ObservedObject var repo: TranscriptionsRepository
    @State private var aggregates: TranscriptionsRepository.Aggregates?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    ProgressView().padding()
                } else if let agg = aggregates {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                        spacing: 12
                    ) {
                        statCard(title: "Total transcriptions", value: "\(agg.totalCount)")
                        statCard(title: "Total words", value: "\(agg.totalWords)")
                        statCard(
                            title: "Total audio recorded",
                            value: String(format: "%.1f min", agg.totalDurationSeconds / 60)
                        )
                        if agg.averageTranscriptionMs > 0 {
                            statCard(
                                title: "Avg transcription latency",
                                value: String(format: "%.0f ms", agg.averageTranscriptionMs)
                            )
                        }
                        if agg.averageEnhancementMs > 0 {
                            statCard(
                                title: "Avg enhancement latency",
                                value: String(format: "%.0f ms", agg.averageEnhancementMs)
                            )
                        }
                        if agg.totalCostUSD > 0 {
                            statCard(
                                title: "Estimated total cost",
                                value: String(format: "$%.3f", agg.totalCostUSD)
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .thinScrollers()
        .task {
            do {
                let agg = try await repo.aggregates()
                self.aggregates = agg
            } catch {
                NSLog("[Clawix.Metrics] failed: %@", error.localizedDescription)
            }
            self.loading = false
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            Text(value)
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Cleanup

private struct TranscriptCleanupView: View {
    @ObservedObject var repo: TranscriptionsRepository

    @AppStorage(CleanupScheduler.transcriptsEnabledKey) private var transcriptsEnabled = false
    @AppStorage(CleanupScheduler.transcriptsTTLKey) private var transcriptsTTLRaw = CleanupScheduler.TranscriptsTTL.d1.rawValue
    @AppStorage(CleanupScheduler.audioFilesEnabledKey) private var audioEnabled = false
    @AppStorage(CleanupScheduler.audioFilesTTLKey) private var audioTTLRaw = CleanupScheduler.AudioTTL.d7.rawValue

    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Transcripts cleanup") {
                    HStack {
                        Text("Auto-delete transcripts after")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Spacer()
                        PillToggle(isOn: $transcriptsEnabled)
                    }
                    if transcriptsEnabled {
                        Picker("TTL", selection: $transcriptsTTLRaw) {
                            ForEach(CleanupScheduler.TranscriptsTTL.allCases, id: \.rawValue) { ttl in
                                Text(ttl.displayName).tag(ttl.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }
                section("Audio cleanup") {
                    HStack {
                        Text("Auto-delete audio files after")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Spacer()
                        PillToggle(isOn: $audioEnabled)
                            .disabled(transcriptsEnabled)
                    }
                    if audioEnabled && !transcriptsEnabled {
                        Picker("TTL", selection: $audioTTLRaw) {
                            ForEach(CleanupScheduler.AudioTTL.allCases, id: \.rawValue) { ttl in
                                Text(ttl.displayName).tag(ttl.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                    if transcriptsEnabled {
                        Text("Disabled while \"Auto-delete transcripts\" is on (transcripts cleanup already removes audio).")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                Button {
                    running = true
                    Task {
                        await CleanupScheduler.shared.runOnce()
                        running = false
                    }
                } label: {
                    Text(running ? "Running…" : "Run cleanup now")
                }
                .disabled(running)
            }
            .padding(20)
        }
        .thinScrollers()
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Backup

private struct TranscriptBackupView: View {
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export transcripts as CSV or back up your dictation settings as JSON. API keys are never included in the JSON dump.")
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Export transcripts (CSV)") {
                    Task { await exportCSV() }
                }
                Button("Export settings (JSON)") {
                    exportJSON()
                }
                Button("Import settings (JSON)") {
                    importJSON()
                }
            }

            if let status {
                Text(status)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                    )
            }
        }
        .padding(20)
    }

    private func exportCSV() async {
        do {
            let url = try await DictationExportService.exportTranscripts()
            saveCopyOf(url, suggestedName: "clawix-transcripts.csv")
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        do {
            let url = try DictationExportService.exportSettings()
            saveCopyOf(url, suggestedName: "clawix-dictation-settings.json")
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        do {
            let count = try DictationExportService.importSettings(from: chosen)
            status = "Imported \(count) keys. Restart Clawix for the changes to take full effect."
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    private func saveCopyOf(_ source: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            status = "Saved to \(dest.lastPathComponent)."
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }
}
