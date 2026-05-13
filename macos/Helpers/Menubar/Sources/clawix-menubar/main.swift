import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Network
import ClawixEngine

// `clawix-menubar` is a tiny accessory app: it adds a status item to
// the system menu bar, polls the bridge daemon over loopback, and
// exposes a single window with the pairing QR. The CLI launches it
// with `clawix up` and tears it down with `clawix stop`. Quitting the
// menubar from its own menu does NOT stop the daemon; the daemon is a
// separate launchd-managed process.

@MainActor
final class MenubarApp: NSObject, NSApplicationDelegate {

    private let port: UInt16 = 24080
    private let pairing = PairingService(
        defaults: UserDefaults(suiteName: "clawix.bridge") ?? .standard,
        port: 24080
    )

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var isDaemonUp: Bool = false
    private var qrWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = brandTemplateImage()
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
        }
        rebuildMenu()
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshDaemonStatus() }
        }
        pollTimer?.tolerance = 0.5
        Task { @MainActor in self.refreshDaemonStatus() }
    }

    private func refreshDaemonStatus() {
        probeDaemon { [weak self] up in
            Task { @MainActor in
                guard let self else { return }
                if self.isDaemonUp != up {
                    self.isDaemonUp = up
                    self.rebuildMenu()
                }
            }
        }
    }

    private func probeDaemon(_ completion: @escaping (Bool) -> Void) {
        // Quick TCP connect to loopback. The daemon binds 127.0.0.1
        // first (always available) and then advertises the LAN IP via
        // bonjour, so loopback is a reliable up/down check independent
        // of whether the user is on WiFi.
        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)
        var resolved = false
        let resolve: (Bool) -> Void = { up in
            guard !resolved else { return }
            resolved = true
            connection.cancel()
            completion(up)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:        resolve(true)
            case .failed, .cancelled, .waiting:
                resolve(false)
            default: break
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { resolve(false) }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = isDaemonUp
            ? "Bridge: running on port \(port)"
            : "Bridge: not running"
        let header = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let lan = PairingService.currentLANIPv4() {
            let net = NSMenuItem(title: "LAN: \(lan)", action: nil, keyEquivalent: "")
            net.isEnabled = false
            menu.addItem(net)
        }
        if let ts = PairingService.currentTailscaleIPv4() {
            let net = NSMenuItem(title: "Tailscale: \(ts)", action: nil, keyEquivalent: "")
            net.isEnabled = false
            menu.addItem(net)
        }

        menu.addItem(.separator())

        let qrItem = NSMenuItem(
            title: "Show Pairing QR…",
            action: #selector(showQR),
            keyEquivalent: "p"
        )
        qrItem.target = self
        qrItem.isEnabled = isDaemonUp
        menu.addItem(qrItem)

        let copyItem = NSMenuItem(
            title: "Copy Pairing JSON",
            action: #selector(copyPairingJSON),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = isDaemonUp
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let logsItem = NSMenuItem(
            title: "Open Bridge Logs",
            action: #selector(openLogs),
            keyEquivalent: ""
        )
        logsItem.target = self
        menu.addItem(logsItem)

        let restartItem = NSMenuItem(
            title: "Restart Bridge",
            action: #selector(restartBridge),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(.separator())

        let appPath = "/Applications/Clawix.app"
        if FileManager.default.fileExists(atPath: appPath) {
            let openApp = NSMenuItem(
                title: "Open Clawix.app",
                action: #selector(openClawixApp),
                keyEquivalent: ""
            )
            openApp.target = self
            menu.addItem(openApp)
        } else {
            let installApp = NSMenuItem(
                title: "Install Clawix.app…",
                action: #selector(installClawixApp),
                keyEquivalent: ""
            )
            installApp.target = self
            menu.addItem(installApp)
        }

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About clawix CLI",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: "Quit clawix-menubar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showQR() {
        let payload = pairing.qrPayload()
        if let win = qrWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = QRView(frame: NSRect(x: 0, y: 0, width: 320, height: 380), payload: payload)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pair iPhone"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        qrWindow = window
    }

    @objc private func copyPairingJSON() {
        let payload = pairing.qrPayload()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    @objc private func openLogs() {
        let url = URL(fileURLWithPath: "/tmp/clawix-bridge.err")
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/tmp")])
            return
        }
        if let consoleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: consoleURL, configuration: config)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func restartBridge() {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/clawix.bridge"]
        try? process.run()
    }

    @objc private func openClawixApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Clawix.app"))
    }

    @objc private func installClawixApp() {
        // Defer to the npm CLI's `install-app` command, which handles
        // the DMG download, mount, copy and detach. The menubar binary
        // intentionally does not embed that flow so the install logic
        // lives in one place (the CLI) and the menubar stays small.
        let cli = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".clawix/bin/clawix")
        let script = """
        do shell script "'\(cli.path)' install-app" with administrator privileges
        """
        if let appleScript = NSAppleScript(source: "tell application \"Terminal\" to do script \"\(cli.path) install-app\"") {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        } else {
            _ = script
        }
    }

    @objc private func openAbout() {
        let alert = NSAlert()
        alert.messageText = "clawix CLI"
        alert.informativeText = "Standalone bridge for the Codex CLI. Runs in the menu bar; the heavy lifting is in clawix-bridge."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func brandTemplateImage() -> NSImage {
        // The brand mark squircle: a single evenodd-filled path in a
        // 16-point template image. Mirrors `macos/.../ClawixLogoIcon.swift`
        // shape parameters but rendered at status-bar size.
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = true
        image.lockFocus()
        let path = NSBezierPath()
        let r: CGFloat = 4
        let inset: CGFloat = 1
        let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        path.appendRoundedRect(rect, xRadius: r, yRadius: r)
        let inner = NSRect(x: rect.minX + 3.5, y: rect.minY + 5.5, width: rect.width - 7, height: rect.height - 9)
        let visor = NSBezierPath(roundedRect: inner, xRadius: 2, yRadius: 2)
        path.append(visor.reversed)
        NSColor.black.setFill()
        path.fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
final class QRView: NSView {
    private let payload: String
    private let imageView = NSImageView()
    private let captionLabel = NSTextField(labelWithString: "Scan with Clawix on your iPhone")
    private let hostLabel = NSTextField(labelWithString: "")

    init(frame frameRect: NSRect, payload: String) {
        self.payload = payload
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView.image = QRView.makeQR(from: payload, size: 240)
        imageView.imageScaling = .scaleNone
        imageView.frame = NSRect(x: 40, y: 90, width: 240, height: 240)
        addSubview(imageView)

        captionLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        captionLabel.textColor = NSColor(white: 1.0, alpha: 0.6)
        captionLabel.alignment = .center
        captionLabel.frame = NSRect(x: 0, y: 60, width: bounds.width, height: 16)
        addSubview(captionLabel)

        if let host = PairingService.currentLANIPv4() {
            hostLabel.stringValue = "\(host):24080"
        } else {
            hostLabel.stringValue = "loopback only"
        }
        hostLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        hostLabel.textColor = NSColor(white: 1.0, alpha: 0.45)
        hostLabel.alignment = .center
        hostLabel.frame = NSRect(x: 0, y: 36, width: bounds.width, height: 14)
        addSubview(hostLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeQR(from text: String, size: CGFloat) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return NSImage() }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = MenubarApp()
    app.delegate = delegate
    app.run()
}
