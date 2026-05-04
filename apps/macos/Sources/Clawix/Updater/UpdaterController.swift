import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func installUpdate() {
        controller.checkForUpdates(nil)
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
            self.pendingVersion = item.displayVersionString
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
            self.pendingVersion = nil
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = false
            self.pendingVersion = nil
        }
    }
}
