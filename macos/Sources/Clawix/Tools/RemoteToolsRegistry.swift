import Foundation
import SwiftUI
import Combine

/// Aggregates tool catalogs from every feature manager that publishes
/// one. The aggregated list is the surface a runtime adapter hands to
/// the LLM as available functions, and the source debug panes read to
/// render per-feature catalogs.
///
/// Feature managers plug in by passing their catalog publisher here
/// without touching other domains' code.
@MainActor
final class RemoteToolsRegistry: ObservableObject {

    /// Flattened catalog the LLM-facing layer reads. Sorted by id so
    /// the order is stable across reloads and easy to diff in logs.
    @Published private(set) var tools: [RemoteToolDescriptor] = []

    /// Per-feature subset for debug surfaces that want to scope the
    /// view to one domain (e.g. "show me only the IoT tools").
    @Published private(set) var toolsByFeature: [String: [RemoteToolDescriptor]] = [:]

    private var cancellables: Set<AnyCancellable> = []

    /// Subscribes to a feature's tool publisher. Re-emits whenever the
    /// publisher updates so the aggregated catalog stays in sync with
    /// supervisor restarts and hot-reload paths.
    func attach<P: Publisher>(feature: String, tools publisher: P)
    where P.Output == [RemoteToolDescriptor], P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tools in
                self?.toolsByFeature[feature] = tools
                self?.rebuildFlat()
            }
            .store(in: &cancellables)
    }

    private func rebuildFlat() {
        tools = toolsByFeature.values
            .flatMap { $0 }
            .sorted { $0.id < $1.id }
    }
}
