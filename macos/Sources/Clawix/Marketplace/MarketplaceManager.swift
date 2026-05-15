import Combine
import Foundation

/// State orchestrator for the marketplace tab. Owns the marketplace/1.0.0 client and
/// publishes the data the SwiftUI views render.
@MainActor
final class MarketplaceManager: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var roots: [ClawJSMarketplaceClient.RootKey] = []
    @Published private(set) var devices: [ClawJSMarketplaceClient.DeviceKey] = []
    @Published private(set) var roles: [ClawJSMarketplaceClient.RoleKey] = []
    @Published private(set) var myOffers: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var myWants: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var observedIntents: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var nativeIntentsFromPeers: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var receipts: [ClawJSMarketplaceClient.MatchReceipt] = []
    @Published private(set) var inbound: [ClawJSMarketplaceClient.InboundMessage] = []
    @Published private(set) var peerLevels: [ClawJSMarketplaceClient.PeerLevel] = []
    @Published private(set) var brokers: [ClawJSMarketplaceClient.Broker] = []
    @Published var selectedVertical: String? = nil

    private var marketplace: ClawJSMarketplaceClient

    init() {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
        let index = ClawJSIndexClient(bearerToken: token)
        self.marketplace = ClawJSMarketplaceClient(indexClient: index)
    }

    func ensureToken() {
        if marketplace.indexClient.bearerToken == nil {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
            marketplace.indexClient.bearerToken = token
        }
    }

    func refresh() async {
        ensureToken()
        state = .loading
        do {
            async let rootsTask = marketplace.listRoots()
            async let devicesTask = marketplace.listDevices()
            async let rolesTask = marketplace.listRoles()
            async let nativeOffersTask = marketplace.listIntents(filter: .init(side: "offer", provenance: "native"))
            async let nativeWantsTask = marketplace.listIntents(filter: .init(side: "want", provenance: "native"))
            async let observedTask = marketplace.listIntents(filter: .init(provenance: "observed"))
            async let receiptsTask = marketplace.listMatchReceipts()
            async let inboundTask = marketplace.listInbound()
            async let peerLevelsTask = marketplace.listPeerLevels()
            async let brokersTask = marketplace.listBrokers()

            let (roots, devices, roles, nativeOffers, nativeWants, observed, receipts, inbound, peers, brokers) = try await (
                rootsTask, devicesTask, rolesTask,
                nativeOffersTask, nativeWantsTask, observedTask,
                receiptsTask, inboundTask, peerLevelsTask, brokersTask
            )

            self.roots = roots
            self.devices = devices
            self.roles = roles
            // Native intents whose `roleKeyId` matches a local role are mine; others are peers'.
            let localRoleIds = Set(roles.map(\.id))
            self.myOffers = nativeOffers.filter { roleKeyId in
                localRoleIds.contains(roleKeyId.roleKeyId ?? "")
            }
            self.myWants = nativeWants.filter { roleKeyId in
                localRoleIds.contains(roleKeyId.roleKeyId ?? "")
            }
            let peerNatives = (nativeOffers + nativeWants).filter { intent in
                guard let rid = intent.roleKeyId else { return true }
                return !localRoleIds.contains(rid)
            }
            self.nativeIntentsFromPeers = peerNatives
            self.observedIntents = observed
            self.receipts = receipts
            self.inbound = inbound
            self.peerLevels = peers
            self.brokers = brokers
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func markRead(messageId: String) async {
        ensureToken()
        do {
            try await marketplace.markRead(messageId: messageId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func updateIntentStatus(id: String, status: String) async {
        ensureToken()
        do {
            try await marketplace.updateIntentStatus(id: id, status: status)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        await refresh()
    }
}
