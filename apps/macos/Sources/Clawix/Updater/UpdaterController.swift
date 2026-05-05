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
            // Sparkle is about to move the .app bundle. The
            // LaunchAgent daemon (`clawix-bridged`) holds file
            // handles into Contents/Helpers/, which would block the
            // swap. Tell BackgroundBridgeService to unregister; it
            // re-registers on next launch via
            // `restoreAfterUpdateIfNeeded()`.
            BackgroundBridgeService.shared.prepareForUpdateInstall()
        }
    }
}
