import Foundation
import AppKit

@MainActor
final class SecretsLifecycle {

    private weak var vault: SecretsManager?
    private var observers: [NSObjectProtocol] = []

    init(attaching vault: SecretsManager) {
        self.vault = vault
        installObservers()
    }

    deinit {
        let observers = self.observers
        // Detach from default centers without hopping back to MainActor; observers
        // are token-based and removeObserver(_:) is safe from any thread.
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.vault?.lock() }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.vault?.lock() }
        })

        // Screen lock from the Apple menu / hot-corner / TouchID prompt comes
        // over the distributed notification center, not the local one.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.vault?.lock() }
        })

        // App quitting via Cmd-Q. Lock synchronously so the master key never
        // outlives the visible window.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.vault?.lock() }
        })
    }
}
