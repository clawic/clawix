import Foundation
import CommanderCore

enum ClawixHostBootstrap {
    private struct Registry: Codable {
        var schemaVersion: Int
        var activeHostId: String?
        var hosts: [HostDescriptor]
        var updatedAt: String
    }

    static func runOnce() {
        do {
            try registerHost()
        } catch {
            NSLog("Clawix host registration failed: \(error.localizedDescription)")
        }
    }

    private static func registerHost() throws {
        let config = HostConfiguration.clawix
        let registryURL = try registryFileURL()
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var registry = try readRegistry(from: registryURL)
        let now = Timestamp.now()
        let stateDir = StatePaths.stateDirectory(environment: [
            "CLAW_HOST_ID": config.id,
            "CLAW_HOST_DISPLAY_NAME": config.displayName,
            "CLAW_HOST_APP_SUPPORT_NAME": config.appSupportDirectoryName,
            "CLAW_HOST_CLI_NAME": config.cliExecutableName,
            "CLAW_HOST_DAEMON_NAME": config.daemonExecutableName,
            "CLAW_HOST_LAUNCH_AGENT_LABEL": config.launchAgentLabel,
            "CLAW_HOST_MACH_SERVICE": config.machServiceName ?? "",
        ])
        let endpoint = HostEndpoint(
            transport: .unixSocket,
            address: try StatePaths.daemonSocketFile(environment: ["CLAW_HOST_HOME": stateDir.path]).path
        )
        let host = HostDescriptor(
            id: config.id,
            displayName: config.displayName,
            kind: .embedded,
            bundleId: Bundle.main.bundleIdentifier,
            executablePath: Bundle.main.executablePath,
            appSupportDir: stateDir.path,
            endpoint: endpoint,
            capabilities: CapabilityCatalog.all.map { capability in
                var copy = capability
                copy.brokerRequired = capability.requiresOSPermission || capability.riskLevel == "destructive" || capability.riskLevel == "cost"
                copy.destructive = capability.riskLevel == "destructive"
                copy.costSensitive = capability.riskLevel == "cost"
                return copy
            },
            registeredAt: registry.hosts.first(where: { $0.id == config.id })?.registeredAt ?? now,
            updatedAt: now
        )

        registry.hosts.removeAll { $0.id == host.id }
        registry.hosts.append(host)
        registry.hosts.sort { $0.id < $1.id }
        if registry.activeHostId == nil {
            registry.activeHostId = host.id
        }
        registry.updatedAt = now

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }

    private static func readRegistry(from url: URL) throws -> Registry {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Registry(schemaVersion: 1, activeHostId: nil, hosts: [], updatedAt: Timestamp.now())
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Registry.self, from: data)
    }

    private static func registryFileURL() throws -> URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claw", isDirectory: true)
            .appendingPathComponent("hosts", isDirectory: true)
        return appSupport.appendingPathComponent("registry.json")
    }
}
