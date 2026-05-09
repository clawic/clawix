import Foundation
import SecretsModels

public struct Anomaly: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case newHost
        case newAgent
        case usageSpike
        case failedUnlockSpike
        case offHoursAccess
    }

    public let id: String
    public let kind: Kind
    public let secretId: EntityID?
    public let secretInternalName: String?
    public let detectedAt: Timestamp
    public let summary: String

    public init(kind: Kind, secretId: EntityID?, secretInternalName: String?, detectedAt: Timestamp, summary: String) {
        // ID is stable per (kind, secret, summary fragment) so duplicate
        // detections within a small window dedupe naturally.
        let key = "\(kind.rawValue)|\(secretId?.uuidString ?? "_")|\(summary)"
        self.id = key
        self.kind = kind
        self.secretId = secretId
        self.secretInternalName = secretInternalName
        self.detectedAt = detectedAt
        self.summary = summary
    }
}

/// Heuristic anomaly detector. Walks decrypted audit events and flags
/// patterns that warrant a closer look: hosts never seen for that
/// secret, agents never seen, rate spikes, failed-unlock bursts, and
/// off-hours access. Caller is responsible for writing the
/// corresponding `anomaly_detected` audit row when a new anomaly is
/// surfaced (so duplicates within the same window aren't double-logged).
public enum AnomalyDetector {

    public static let lookbackWindowMs: Timestamp = 24 * 60 * 60 * 1000
    public static let baselineWindowMs: Timestamp = 7 * 24 * 60 * 60 * 1000
    public static let usageSpikeFactor: Double = 3.0
    public static let failedUnlockThreshold: Int = 5
    public static let offHoursStartHour: Int = 1
    public static let offHoursEndHour: Int = 6

    public static func detect(events: [DecryptedAuditEvent], now: Timestamp = Clock.now()) -> [Anomaly] {
        var anomalies: [Anomaly] = []

        let lookbackStart = now - lookbackWindowMs
        let baselineStart = now - baselineWindowMs

        // Group events by secret. Empty secretId -> skip in per-secret heuristics.
        var perSecret: [EntityID: [DecryptedAuditEvent]] = [:]
        var allFailedUnlocks: [DecryptedAuditEvent] = []
        var byInternalName: [EntityID: String] = [:]
        for event in events {
            if event.kind == .vaultFailedUnlock {
                allFailedUnlocks.append(event)
            }
            if let id = event.secretId {
                perSecret[id, default: []].append(event)
                if let name = event.payload.secretInternalNameFrozen {
                    byInternalName[id] = name
                }
            }
        }

        // newHost / newAgent / off-hours / usageSpike per secret.
        for (secretId, secretEvents) in perSecret {
            let lookback = secretEvents.filter { $0.timestamp >= lookbackStart }
            let baseline = secretEvents.filter { $0.timestamp >= baselineStart && $0.timestamp < lookbackStart }
            let internalName = byInternalName[secretId]

            // newHost
            let baselineHosts = Set(baseline.compactMap { $0.payload.host })
            let lookbackHosts = Set(lookback.compactMap { $0.payload.host })
            let newHosts = lookbackHosts.subtracting(baselineHosts).filter { !$0.isEmpty }
            for host in newHosts {
                anomalies.append(Anomaly(
                    kind: .newHost,
                    secretId: secretId,
                    secretInternalName: internalName,
                    detectedAt: now,
                    summary: "First-time host '\(host)' for secret \(internalName ?? secretId.uuidString)"
                ))
            }

            // newAgent
            let baselineAgents = Set(baseline.compactMap { $0.payload.agentName })
            let lookbackAgents = Set(lookback.compactMap { $0.payload.agentName })
            let newAgents = lookbackAgents.subtracting(baselineAgents).filter { !$0.isEmpty }
            for agent in newAgents {
                anomalies.append(Anomaly(
                    kind: .newAgent,
                    secretId: secretId,
                    secretInternalName: internalName,
                    detectedAt: now,
                    summary: "First-time agent '\(agent)' for secret \(internalName ?? secretId.uuidString)"
                ))
            }

            // usage spike
            let lookbackCount = Double(lookback.count)
            let baselineCount = Double(baseline.count)
            // Normalize by window length: lookback is 1 day, baseline is 6 days (between baselineStart and lookbackStart).
            let baselineRatePerDay = baselineCount / 6.0
            if lookbackCount >= 5, lookbackCount > baselineRatePerDay * usageSpikeFactor, baselineRatePerDay >= 0.5 {
                anomalies.append(Anomaly(
                    kind: .usageSpike,
                    secretId: secretId,
                    secretInternalName: internalName,
                    detectedAt: now,
                    summary: "Usage spike for \(internalName ?? secretId.uuidString): \(Int(lookbackCount)) ops in 24h vs \(String(format: "%.1f", baselineRatePerDay))/day baseline"
                ))
            }

            // off-hours: any event in lookback window with hour-of-day in [offHoursStartHour, offHoursEndHour).
            let cal = Calendar(identifier: .gregorian)
            let offHours = lookback.filter { event in
                let date = event.timestamp.asDate
                let hour = cal.component(.hour, from: date)
                return hour >= offHoursStartHour && hour < offHoursEndHour
            }
            if !offHours.isEmpty {
                anomalies.append(Anomaly(
                    kind: .offHoursAccess,
                    secretId: secretId,
                    secretInternalName: internalName,
                    detectedAt: now,
                    summary: "\(offHours.count) off-hours access(es) (between \(offHoursStartHour):00 and \(offHoursEndHour):00) for \(internalName ?? secretId.uuidString)"
                ))
            }
        }

        // failed-unlock spike (vault-wide).
        let recentFails = allFailedUnlocks.filter { $0.timestamp >= lookbackStart }
        if recentFails.count >= failedUnlockThreshold {
            anomalies.append(Anomaly(
                kind: .failedUnlockSpike,
                secretId: nil,
                secretInternalName: nil,
                detectedAt: now,
                summary: "\(recentFails.count) failed vault unlock attempts in the last 24h"
            ))
        }

        return anomalies
    }
}
