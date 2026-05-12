import Combine
import Foundation

/// State orchestrator for the marketplace tab. Owns the mp/1.0.0 client and
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
    @Published private(set) var roots: [ClawJSMpClient.RootKey] = []
    @Published private(set) var devices: [ClawJSMpClient.DeviceKey] = []
    @Published private(set) var roles: [ClawJSMpClient.RoleKey] = []
    @Published private(set) var myOffers: [ClawJSMpClient.Intent] = []
    @Published private(set) var myWants: [ClawJSMpClient.Intent] = []
    @Published private(set) var observedIntents: [ClawJSMpClient.Intent] = []
    @Published private(set) var nativeIntentsFromPeers: [ClawJSMpClient.Intent] = []
    @Published private(set) var receipts: [ClawJSMpClient.MatchReceipt] = []
    @Published private(set) var inbound: [ClawJSMpClient.InboundMessage] = []
    @Published private(set) var peerLevels: [ClawJSMpClient.PeerLevel] = []
    @Published private(set) var brokers: [ClawJSMpClient.Broker] = []
    @Published var selectedVertical: String? = nil

    private var mp: ClawJSMpClient

    init() {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
            ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
        let index = ClawJSIndexClient(bearerToken: token)
        self.mp = ClawJSMpClient(indexClient: index)
    }

    func ensureToken() {
        if mp.indexClient.bearerToken == nil {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromDataDir(for: .index))
            mp.indexClient.bearerToken = token
        }
    }

    func refresh() async {
        ensureToken()
        state = .loading
        do {
            async let rootsTask = mp.listRoots()
            async let devicesTask = mp.listDevices()
            async let rolesTask = mp.listRoles()
            async let nativeOffersTask = mp.listIntents(filter: .init(side: "offer", provenance: "native"))
            async let nativeWantsTask = mp.listIntents(filter: .init(side: "want", provenance: "native"))
            async let observedTask = mp.listIntents(filter: .init(provenance: "observed"))
            async let receiptsTask = mp.listMatchReceipts()
            async let inboundTask = mp.listInbound()
            async let peerLevelsTask = mp.listPeerLevels()
            async let brokersTask = mp.listBrokers()

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
        do { try await mp.markRead(messageId: messageId) } catch {}
    }

    func updateIntentStatus(id: String, status: String) async {
        ensureToken()
        do { try await mp.updateIntentStatus(id: id, status: status) } catch {}
        await refresh()
    }
}
