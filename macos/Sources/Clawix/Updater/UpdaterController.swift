import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController!

    // Persist a pending update across launches. Without this, the chip
    // is blind between Sparkle's 24h scheduled checks: `updateAvailable`
    // resets to false on every relaunch and only lights up again when
    // `didFindValidUpdate` fires, which only happens during an actual
    // check.
    nonisolated static let pendingBuildKey = "ClawixPendingUpdateBuild"
    nonisolated static let pendingDisplayKey = "ClawixPendingUpdateDisplay"

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        restorePendingUpdateIfStillNewer()
        // Force a silent check on every launch so the chip lights up
        // promptly instead of waiting for Sparkle's 24h cron to fire.
        controller.updater.checkForUpdatesInBackground()
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
        let build = item.versionString
        let display = item.displayVersionString
        Task { @MainActor in
            self.updateAvailable = true
            self.pendingVersion = display
            UserDefaults.standard.set(build, forKey: Self.pendingBuildKey)
            UserDefaults.standard.set(display, forKey: Self.pendingDisplayKey)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.clearPendingUpdate()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.clearPendingUpdate()
            // Sparkle is about to move the .app bundle. The
            // LaunchAgent daemon (`clawix-bridge`) holds file
            // handles into Contents/Helpers/, which would block the
            // swap. Tell BackgroundBridgeService to unregister; it
            // re-registers on next launch via
            // `restoreAfterUpdateIfNeeded()`.
            BackgroundBridgeService.shared.prepareForUpdateInstall()
        }
    }

    private func clearPendingUpdate() {
        updateAvailable = false
        pendingVersion = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingBuildKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingDisplayKey)
    }

    private func restorePendingUpdateIfStillNewer() {
        let defaults = UserDefaults.standard
        guard let pendingBuildString = defaults.string(forKey: Self.pendingBuildKey),
              let pendingBuild = Int(pendingBuildString) else {
            return
        }
        let installedBuildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let installedBuild = Int(installedBuildString) ?? 0
        guard pendingBuild > installedBuild else {
            // The user already moved past the pending build (manual
            // install, side-load, etc.). Drop the stale marker.
            defaults.removeObject(forKey: Self.pendingBuildKey)
            defaults.removeObject(forKey: Self.pendingDisplayKey)
            return
        }
        updateAvailable = true
        pendingVersion = defaults.string(forKey: Self.pendingDisplayKey)
    }
}
