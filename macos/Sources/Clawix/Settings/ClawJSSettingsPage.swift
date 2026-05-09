import AppKit
import SwiftUI

/// Settings page that surfaces the state of the three ClawJS sidecar
/// services (database / memory / drive). Phase 3 wires the manager's
/// snapshots to the UI without consuming any service data yet; that
/// happens in Phase 4.
///
/// Today every service publishes `.blocked` because `@clawjs/cli` does
/// not expose a service-launch surface. The page renders that block
/// reason directly so the gap is visible to anyone investigating.
struct ClawJSSettingsPage: View {

    @StateObject private var manager = ClawJSServiceManager.shared
    @State private var advancedExpanded = false
    @State private var databaseProbe: DatabaseProbeResult?
    @State private var databaseProbeInFlight = false

    private enum DatabaseProbeResult: Equatable {
        case success(service: String, host: String, port: Int)
        case failure(message: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            bundleSection
                .padding(.top, 18)

            ForEach(ClawJSService.allCases) { service in
                serviceSection(for: service)
                    .padding(.top, 18)
            }

            advancedSection
                .padding(.top, 22)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ClawJS")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Sidecar services that back upcoming database, memory, and drive features.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Bundle card

    private var bundleSection: some View {
        SectionCard(title: "Bundle") {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Pinned version") {
                    Text(ClawJSRuntime.expectedVersion)
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                }
                Divider().background(Color.white.opacity(0.07))
                row(label: "Bundle available") {
                    if BackgroundBridgeService.shared.isDaemonReachable && !ClawJSRuntime.isAvailable {
                        statusPill(text: "Not required in daemon mode", color: .blue)
                    } else if ClawJSRuntime.isAvailable {
                        statusPill(text: "Yes", color: .green)
                    } else {
                        statusPill(text: "Missing", color: .orange)
                    }
                }
            }
        }
    }

    // MARK: - Per-service card

    private func serviceSection(for service: ClawJSService) -> some View {
        let snapshot = manager.snapshots[service]
        let state = snapshot?.state ?? .idle
        return SectionCard(title: service.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Status") {
                    statusPill(text: stateLabel(state), color: stateColor(state))
                }
                if case .blocked(let reason) = state {
                    blockedReason(reason)
                }
                if case .crashed(let reason) = state {
                    blockedReason(reason)
                }
                if case .daemonUnavailable(let reason) = state {
                    blockedReason(reason)
                }
                Divider().background(Color.white.opacity(0.07))
                row(label: "Port") {
                    Text(verbatim: "127.0.0.1:\(service.port)")
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .monospacedDigit()
                }
                Divider().background(Color.white.opacity(0.07))
                HStack(spacing: 12) {
                    Button("Open admin console") {
                        if let url = URL(string: "http://127.0.0.1:\(service.port)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(state.isReady ? Palette.textPrimary : Palette.textSecondary)
                    .disabled(!state.isReady)

                    Button("Reveal log") {
                        let url = ClawJSServiceManager.logFileURL(for: service)
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                }

                if service == .database, state.isReady {
                    Divider().background(Color.white.opacity(0.07))
                    databaseProbeRow
                    Divider().background(Color.white.opacity(0.07))
                    DatabaseManagerStatusRow()
                }
            }
        }
    }

    /// Smoke-test row for the database service: hits `/v1/health`
    /// (unauthenticated) and renders the response or the error inline.
    /// The first concrete consumer of `ClawJSDatabaseClient`; Phase 4
    /// proper (a Tasks panel that lists records) builds on top of this
    /// once the home layout is the right place to host it.
    @ViewBuilder
    private var databaseProbeRow: some View {
        HStack(spacing: 12) {
            Button("Probe /v1/health") {
                Task { await probeDatabase() }
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 11.5, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .disabled(databaseProbeInFlight)

            if databaseProbeInFlight {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        if let result = databaseProbe {
            switch result {
            case .success(let service, let host, let port):
                Text("\(service) reports \(host):\(port)")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            case .failure(let message):
                Text(message)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func probeDatabase() async {
        databaseProbeInFlight = true
        defer { databaseProbeInFlight = false }
        do {
            let response = try await ClawJSDatabaseClient().probeHealth()
            databaseProbe = .success(
                service: response.service,
                host: response.host,
                port: response.port
            )
        } catch {
            databaseProbe = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            SectionCard(title: "Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    row(label: "Workspace") {
                        Text(ClawJSServiceManager.workspaceURL.path)
                            .font(BodyFont.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Divider().background(Color.white.opacity(0.07))
                    ForEach(ClawJSService.allCases) { service in
                        HStack(spacing: 12) {
                            Text(service.displayName)
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(Palette.textPrimary)
                                .frame(width: 90, alignment: .leading)
                            Button("Restart") {
                                Task { await manager.restart(service) }
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            Button("Status JSON") {
                                if let json = statusJSON(for: service) {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(json, forType: .string)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            Spacer()
                        }
                    }
                }
            }
        } label: {
            Text("Advanced")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Row + pill helpers

    private func row<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            trailing()
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
        }
    }

    private func blockedReason(_ reason: String) -> some View {
        Text(reason)
            .font(BodyFont.system(size: 11.5))
            .foregroundColor(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stateLabel(_ state: ClawJSServiceState) -> String {
        switch state {
        case .idle:                return "Idle"
        case .blocked:             return "Blocked"
        case .starting:            return "Starting"
        case .ready:               return "Running"
        case .readyFromDaemon:     return "Running from daemon"
        case .crashed:             return "Crashed"
        case .daemonUnavailable:   return "Unavailable from daemon"
        case .suspendedForDaemon:  return "Daemon owns this"
        }
    }

    private func stateColor(_ state: ClawJSServiceState) -> Color {
        switch state {
        case .idle:                return Color.white.opacity(0.4)
        case .blocked:             return .orange
        case .starting:            return .yellow
        case .ready:               return .green
        case .readyFromDaemon:     return .green
        case .crashed:             return .red
        case .daemonUnavailable:   return .red
        case .suspendedForDaemon:  return .blue
        }
    }

    private func statusJSON(for service: ClawJSService) -> String? {
        guard let snapshot = manager.snapshots[service] else { return nil }
        var dict: [String: Any] = [
            "service": service.rawValue,
            "port": Int(service.port),
            "restartCount": snapshot.restartCount,
        ]
        switch snapshot.state {
        case .idle:                dict["state"] = "idle"
        case .blocked(let reason):
            dict["state"] = "blocked"
            dict["reason"] = reason
        case .starting:            dict["state"] = "starting"
        case .ready(let pid, let port):
            dict["state"] = "ready"
            dict["pid"] = Int(pid)
            dict["readyPort"] = Int(port)
        case .readyFromDaemon(let port):
            dict["state"] = "readyFromDaemon"
            dict["readyPort"] = Int(port)
        case .crashed(let reason):
            dict["state"] = "crashed"
            dict["reason"] = reason
        case .daemonUnavailable(let reason):
            dict["state"] = "daemonUnavailable"
            dict["reason"] = reason
        case .suspendedForDaemon:
            dict["state"] = "suspendedForDaemon"
        }
        if let lastError = snapshot.lastError { dict["lastError"] = lastError }
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
