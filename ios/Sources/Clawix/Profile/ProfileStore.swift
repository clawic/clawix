import Combine
import Foundation
import SwiftUI

/// iOS-side mirror of the macOS `ProfileManager`. Owns the HTTP client, holds
/// state for the four tab surfaces (Feed / Chats / Marketplace / Profile),
/// and orchestrates the live refresh cadence.
@MainActor
final class ProfileStore: ObservableObject {

    enum LoadState: Equatable {
        case idle, loading, ready, error(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var me: ProfileClient.Profile?
    @Published private(set) var feed: [ProfileClient.FeedEntry] = []
    @Published private(set) var threads: [ProfileClient.ChatThread] = []
    @Published private(set) var intents: [ProfileClient.DiscoveredIntent] = []

    var client: ProfileClient?

    func configure(origin: URL, bearer: String?) {
        client = ProfileClient(origin: origin, bearer: bearer)
    }

    func bootstrap() async {
        guard let client else { state = .error("Pair with a host first"); return }
        state = .loading
        do {
            async let me = client.me()
            async let feed = client.listFeed()
            async let threads = client.listChats()
            async let intents = client.discoveredIntents()
            self.me = try await me
            self.feed = try await feed
            self.threads = try await threads
            self.intents = try await intents
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func refreshFeed() async {
        guard let client else { return }
        do { self.feed = try await client.listFeed() }
        catch { /* keep last good */ }
    }

    func refreshChats() async {
        guard let client else { return }
        do { self.threads = try await client.listChats() }
        catch { /* keep last good */ }
    }

    func refreshMarketplace() async {
        guard let client else { return }
        do { self.intents = try await client.discoveredIntents() }
        catch { /* keep last good */ }
    }

    func loadMessages(peer: String) async -> [ProfileClient.ChatMessage] {
        guard let client else { return [] }
        return (try? await client.listMessages(peer: peer)) ?? []
    }

    func sendMessage(peer: String, body: String) async -> ProfileClient.ChatMessage? {
        guard let client else { return nil }
        return try? await client.sendMessage(peer: peer, body: body)
    }

    func expressInterest(intentId: String) async {
        guard let client else { return }
        _ = try? await client.expressInterest(intentId: intentId)
    }

    func pair(link: String) async -> ProfileClient.Handle? {
        guard let client else { return nil }
        return try? await client.pair(pairingLink: link)
    }
}
