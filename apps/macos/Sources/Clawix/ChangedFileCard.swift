import SwiftUI
import AppKit

/// Pill card rendered under an assistant message for every file the agent
/// touched during the turn (apply_patch). Layout matches Codex Desktop:
/// a square doc icon, the file name + "Document · MD" subtitle, and a
/// trailing "Open ⌄" pill that pops a menu of editors.
struct ChangedFileCard: View {
    let path: String

    @EnvironmentObject var appState: AppState
    @State private var hovered = false
    /// Window-coordinates frame of the entire "Open" pill, captured every
    /// layout pass via a GeometryReader. Used to anchor the NSPanel popup
    /// in screen coordinates so it can escape the chat scroll-view's clip
    /// and sibling z-order entirely. Anchored on the pill (not just the
    /// chevron) so the popup left-aligns with the "Open" label.
    @State private var openPillWindowFrame: CGRect = .zero

    private var fileURL: URL { URL(fileURLWithPath: path) }
    private var fileName: String { fileURL.lastPathComponent }
    private var subtitle: String {
        let ext = fileURL.pathExtension
        let kind = String(localized: "Document",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        if ext.isEmpty { return kind }
        return "\(kind) · \(ext.uppercased())"
    }

    var body: some View {
        HStack(spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 8)
            openPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.07 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Whole card opens the file in the sidebar preview. The "Open"
        // pill has its own identical tap handler so taps on the pill
        // body never get swallowed by intermediate hit-testing; the
        // chevron declares a more local gesture and stays the only path
        // to the editor dropdown.
        .onTapGesture {
            appState.openFileInSidebar(path)
        }
        .onHover { hovered = $0 }
        // Smoother, slightly longer easing so the highlight breathes
        // instead of snapping in/out of hover.
        .animation(.easeInOut(duration: 0.22), value: hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(fileName), \(subtitle)"))
    }

    // MARK: - Icon

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.07))
                .frame(width: 44, height: 44)
            FileChipIcon(size: 18)
                .foregroundColor(Color(white: 0.82))
        }
    }

    // MARK: - Open pill

    /// "Open ⌄" pill that mirrors the Codex Desktop card. The label area
    /// runs the same open-in-sidebar action as the parent card; the
    /// chevron is the only sub-region that intercepts the tap and pops
    /// the editor dropdown.
    private var openPill: some View {
        HStack(spacing: 4) {
            Text(String(localized: "Open",
                        bundle: AppLocale.bundle,
                        locale: AppLocale.current))
                .font(BodyFont.system(size: 14, weight: .regular))
                .foregroundColor(Color(white: 0.94))
                // SwiftUI Text on macOS hijacks the I-beam cursor and
                // swallows taps over its glyphs. Pass-through so the
                // parent pill owns both the pointer cursor and the tap.
                .allowsHitTesting(false)

            Image(systemName: "chevron.down")
                .font(BodyFont.system(size: 10, weight: .semibold))
                .foregroundColor(Color(white: 0.72))
                .padding(.leading, 2)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase { NSCursor.pointingHand.set() }
                }
                .onTapGesture {
                    presentMenuPanel()
                }
                .accessibilityLabel("Open with…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.pointingHand.set() }
        }
        .onTapGesture {
            appState.openFileInSidebar(path)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        // Track the whole pill's window frame so the popup anchors on
        // the pill's bottom-left edge.
        .background(OpenPillWindowFrameReader(frame: $openPillWindowFrame))
    }

    private func presentMenuPanel() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        // Anchor the popup's top-left at the pill's bottom-left in screen
        // coordinates so the menu left-aligns with the "Open" label.
        let screenRect = window.convertToScreen(openPillWindowFrame)
        let anchorPoint = NSPoint(x: screenRect.minX, y: screenRect.minY)
        ChangedFileMenuPanel.present(leftTopAnchor: anchorPoint, path: path)
    }
}

// MARK: - Open pill frame reader

/// Reports the "Open" pill's frame in window-local coordinates whenever
/// layout changes. The popup panel uses this to land in the right place
/// even when the chat scroll view scrolls between layout passes.
private struct OpenPillWindowFrameReader: NSViewRepresentable {
    @Binding var frame: CGRect

    func makeNSView(context: Context) -> Reader {
        let v = Reader()
        v.onFrameChange = { rect in
            DispatchQueue.main.async { frame = rect }
        }
        return v
    }

    func updateNSView(_ nsView: Reader, context: Context) {
        nsView.onFrameChange = { rect in
            DispatchQueue.main.async { frame = rect }
        }
    }

    final class Reader: NSView {
        var onFrameChange: ((CGRect) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        private func report() {
            guard window != nil else { return }
            let r = convert(bounds, to: nil)
            onFrameChange?(r)
        }
    }
}

// MARK: - Menu content

private struct ChangedFileMenuContent: View {
    let path: String
    let onPick: () -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ChangedFileOpenAction.editorActions) { action in
                row(action)
            }
            MenuStandardDivider()
            row(.openInFolder)
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 220)
        // Opaque chrome (no blur, no 18% bleed) so the dropdown fully
        // hides whatever sits behind it. The translucent menu chrome
        // would read as a stacking glitch over chat messages.
        .menuStandardBackground(opaque: true)
    }

    @ViewBuilder
    private func row(_ action: ChangedFileOpenAction) -> some View {
        Button {
            action.run(path: path)
            onPick()
        } label: {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                action.iconView
                    .frame(width: 22, alignment: .center)
                Text(action.title)
                    .font(BodyFont.system(size: 13.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .background(MenuRowHover(active: hovered == action.id))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = action.id }
            else if hovered == action.id { hovered = nil }
        }
    }
}

// MARK: - Borderless panel host

/// Hosts `ChangedFileMenuContent` in a borderless non-activating panel so
/// the dropdown escapes the chat scroll view's clip and sibling z-order
/// entirely. Click-outside, Escape and any selected item dismiss it,
/// matching the sidebar's right-click context menu.
@MainActor
final class ChangedFileMenuPanel: NSObject {
    private static var current: ChangedFileMenuPanel?

    private let panel: NSPanel
    private let shadowMargin: CGFloat
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    private init(rootView: AnyView, size: NSSize, shadowMargin: CGFloat) {
        self.shadowMargin = shadowMargin
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        super.init()
    }

    /// Present the menu with its visible top-left corner pinned at
    /// `leftTopAnchor` (already in screen coordinates) plus a small
    /// vertical gap so the popup sits just below the trigger pill.
    static func present(leftTopAnchor: NSPoint, path: String) {
        current?.close()

        var holder: ChangedFileMenuPanel!
        let dismiss: () -> Void = { holder?.close() }

        let content = ChangedFileMenuContent(path: path, onPick: dismiss)

        // Shadow on the menu chrome paints outside the SwiftUI bounds; pad
        // the hosting panel so the shadow isn't clipped at the edges.
        let shadowMargin: CGFloat = 30
        let padded = AnyView(
            content
                .padding(.horizontal, shadowMargin)
                .padding(.top, shadowMargin - 8)
                .padding(.bottom, shadowMargin + 8)
        )

        let measureController = NSHostingController(rootView: padded)
        let fitting = measureController.sizeThatFits(in: NSSize(width: 400, height: 1200))
        let size = NSSize(width: ceil(fitting.width), height: ceil(fitting.height))

        let p = ChangedFileMenuPanel(
            rootView: padded,
            size: size,
            shadowMargin: shadowMargin
        )
        holder = p
        current = p
        p.show(leftTopAnchor: leftTopAnchor)
    }

    private func show(leftTopAnchor: NSPoint) {
        let size = panel.frame.size
        // The visible menu sits inset by `shadowMargin` from each side of
        // the panel, with the top inset being `shadowMargin - 8` to match
        // the asymmetric padding wrapping the content. Position so the
        // visible menu's top-left corner lands at `leftTopAnchor` minus a
        // gap below the pill.
        let topPadding = shadowMargin - 8
        let menuVisibleWidth = size.width - 2 * shadowMargin
        let gap: CGFloat = 14
        var origin = NSPoint(
            x: leftTopAnchor.x - shadowMargin,
            y: leftTopAnchor.y + topPadding - size.height - gap
        )

        let hostScreen = NSScreen.screens.first {
            NSPointInRect(leftTopAnchor, $0.frame)
        } ?? NSScreen.main

        if let screen = hostScreen {
            let visible = screen.visibleFrame
            let inset: CGFloat = 6
            let minX = visible.minX + inset - shadowMargin
            let maxX = visible.maxX - inset - menuVisibleWidth - shadowMargin
            origin.x = min(max(origin.x, minX), max(minX, maxX))

            // If we'd drop below the screen, flip and anchor the visible
            // menu's bottom edge at the pill's top edge instead.
            if origin.y < visible.minY + inset - (shadowMargin + 8) {
                origin.y = leftTopAnchor.y - (shadowMargin + 8) + gap
                let maxY = visible.maxY - inset - size.height + (shadowMargin + 8)
                if origin.y > maxY { origin.y = maxY }
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        installMonitors()
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel { return event }
            self.close()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.close()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 = Escape.
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }
}

// MARK: - Open actions

private enum ChangedFileOpenAction: Identifiable {
    case editor(EditorOption)
    case openInFolder

    var id: String {
        switch self {
        case .editor(let e):  return "editor.\(e.bundleId)"
        case .openInFolder:   return "openInFolder"
        }
    }

    var title: String {
        switch self {
        case .editor(let e):
            return e.name
        case .openInFolder:
            return String(localized: "Open in folder",
                          bundle: AppLocale.bundle,
                          locale: AppLocale.current)
        }
    }

    @ViewBuilder
    var iconView: some View {
        switch self {
        case .editor(let e):
            AppIconImage(bundleId: e.bundleId,
                         fallbackPath: e.fallbackPath,
                         size: 18)
        case .openInFolder:
            AppIconImage(bundleId: "com.apple.finder",
                         fallbackPath: "/System/Library/CoreServices/Finder.app",
                         size: 18)
        }
    }

    func run(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        switch self {
        case .editor(let editor):
            ChangedFileOpenAction.openInEditor(editor: editor, fileURL: fileURL)
        case .openInFolder:
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private static func openInEditor(editor: EditorOption, fileURL: URL) {
        let appURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId)
            ?? (FileManager.default.fileExists(atPath: editor.fallbackPath)
                ? URL(fileURLWithPath: editor.fallbackPath)
                : nil)
        guard let appURL else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    /// Editor entries shown in the dropdown, in the same order as Codex
    /// Desktop's "Open with" menu.
    static let editorActions: [ChangedFileOpenAction] = [
        .editor(.init(bundleId: "com.microsoft.VSCode", name: "VS Code",
                      fallbackPath: "/Applications/Visual Studio Code.app")),
        .editor(.init(bundleId: "com.todesktop.230313mzl4w4u92", name: "Cursor",
                      fallbackPath: "/Applications/Cursor.app")),
        .editor(.init(bundleId: "com.apple.Terminal", name: "Terminal",
                      fallbackPath: "/System/Applications/Utilities/Terminal.app")),
        .editor(.init(bundleId: "com.mitchellh.ghostty", name: "Ghostty",
                      fallbackPath: "/Applications/Ghostty.app")),
        .editor(.init(bundleId: "com.apple.dt.Xcode", name: "Xcode",
                      fallbackPath: "/Applications/Xcode.app")),
        .editor(.init(bundleId: "com.google.android.studio", name: "Android Studio",
                      fallbackPath: "/Applications/Android Studio.app")),
    ]
}
