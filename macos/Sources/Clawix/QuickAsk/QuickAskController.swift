import AppKit
import Combine
import SwiftUI

/// Owns the QuickAsk floating panel: creates it lazily, shows/hides it
/// in response to the global hotkey, and persists the drag position so
/// the panel reappears wherever the user last left it.
@MainActor
final class QuickAskController: ObservableObject {

    static let shared = QuickAskController()

    private var panel: QuickAskPanel?
    private var positionObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?
    private var pasteEventMonitor: Any?

    private let defaults = UserDefaults.standard
    private let bottomCenterKey = "quickAsk.bottomCenter"
    private let legacyFrameKey = "quickAsk.panelFrame"
    private let chatIdKey = "quickAsk.activeChatId"
    private let defaultModelKey = "quickAsk.defaultModel"

    weak var appState: AppState?

    /// Compact mode footprint at its minimum (one-line prompt). Width
    /// is fixed; height grows with the prompt's measured content height
    /// up to `compactMaxVisibleHeight`, so a 15-line draft inflates the
    /// HUD to roughly 3.5x its closed size before the editor falls back
    /// to internal scrolling. See `compactVisibleSize`.
    static let compactMinVisibleSize = NSSize(width: 425, height: 88)
    /// Hard ceiling for the compact HUD height. Targets ~15 lines of
    /// prompt text, ~3x the one-line floor (88 -> ~340). Beyond this
    /// the `ComposerTextEditor` scrolls inside its NSScrollView.
    static let compactMaxVisibleHeight: CGFloat = 340
    /// `promptHeight` reading the editor reports for an empty / single
    /// line prompt. Used as the floor when extrapolating the compact
    /// panel's vertical growth.
    static let compactBasePromptHeight: CGFloat = 28
    static let expandedVisibleSize = NSSize(width: 442, height: 540)

    /// Transparent breathing room around the squircle, on all sides,
    /// so SwiftUI's drop shadow has room to render without being
    /// clipped by the NSPanel's outer rectangle. Same value for both
    /// sizes so the perceived gap stays constant.
    static let shadowMargin: CGFloat = 30

    @Published private(set) var isExpanded: Bool = false

    /// Latest measured `contentHeight` reported by the compact mode's
    /// `ComposerTextEditor`. Drives `compactVisibleSize`'s height so the
    /// closed HUD grows vertically as the user writes more lines, with
    /// a floor matching the historical 88pt footprint and a ceiling at
    /// `compactMaxVisibleHeight`. Updated via `setCompactPromptHeight`.
    @Published private(set) var compactPromptHeight: CGFloat = QuickAskController.compactBasePromptHeight

    @Published private(set) var activeChatId: UUID?

    /// Files / images the user has staged via the `+` menu, drag&drop,
    /// paste, or sniffers. Cleared on submit. The chips bar above the
    /// prompt input renders one chip per entry.
    @Published var pendingAttachments: [QuickAskAttachment] = []

    /// True while the QuickAsk session is in "Temporary chat" mode.
    /// Subsequent submits create chats with `isQuickAskTemporary = true`,
    /// which the sidebar hides and `hide()` deletes from
    /// `appState.chats`. Toggled by the incognito icon in the header
    /// and by `⌘⇧N`.
    @Published var isTemporary: Bool = false

    /// Web search toggle. When on, the next submit gets a `/search`
    /// prefix prepended to the prompt so the daemon routes the turn
    /// through the web-search tool. Persisted per session, cleared
    /// alongside other transient state in `startNewConversation`.
    @Published var webSearchEnabled: Bool = false

    /// Optional "Work with Apps" target. Bundle identifier of the app
    /// the user picked from the work-with-apps popover. When non-nil,
    /// the next submit gets a "Working with <App>" prelude so the
    /// agent knows the focal app.
    @Published var workWithBundleId: String?

    /// Snapshot of the text that was selected in the frontmost app
    /// the moment the QuickAsk hotkey fired. Surfaced to the view as
    /// a placeholder hint + "Use selection" affordance; cleared after
    /// the user accepts or declines, on `hide()`, and on
    /// `startNewConversation`.
    @Published var pendingSelection: QuickAskSelectionSniffer.Snapshot?

    /// Append an attachment to the pending list. No-op if a chip with
    /// the same URL already exists (avoid duplicates when the user
    /// drags or pastes the same file twice).
    func addAttachment(_ attachment: QuickAskAttachment) {
        guard !pendingAttachments.contains(where: { $0.url == attachment.url }) else { return }
        pendingAttachments.append(attachment)
    }

    /// Remove a chip by id (the `x` button on the chip).
    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll(where: { $0.id == id })
    }

    /// Drop everything. Called on submit and on `startNewConversation`.
    func clearAttachments() {
        pendingAttachments.removeAll()
    }

    /// Mirrors whether the compact prompt field is empty. The view
    /// pushes updates here via `noteDraftChanged(_:)` so the controller
    /// can decide, at resign-key time, whether the user has unsaved
    /// text it shouldn't blow away. Stays in sync with the SwiftUI
    /// `@State` in `QuickAskView`.
    private(set) var draftIsEmpty: Bool = true

    func noteDraftChanged(_ text: String) {
        draftIsEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Compact-mode visible footprint, sized from `compactPromptHeight`.
    /// Width is fixed; height = floor + (promptHeight - basePromptHeight)
    /// clamped between the closed-state floor and `compactMaxVisibleHeight`.
    /// Exposed so `QuickAskView` can mirror the same size in its `.frame`.
    var compactVisibleSize: NSSize {
        let extra = max(0, compactPromptHeight - Self.compactBasePromptHeight)
        let height = min(
            Self.compactMaxVisibleHeight,
            Self.compactMinVisibleSize.height + extra
        )
        return NSSize(width: Self.compactMinVisibleSize.width, height: height)
    }

    /// Resolved visible footprint for the current expansion state.
    private var visibleSize: NSSize {
        isExpanded ? Self.expandedVisibleSize : compactVisibleSize
    }

    /// Push the compact `ComposerTextEditor`'s measured content height
    /// into the controller. Triggers a panel resize while the HUD is in
    /// compact mode so the squircle grows / shrinks in lockstep with
    /// the prompt. No-op when expanded (the inputBox handles its own
    /// vertical growth inside the fixed expanded panel).
    func setCompactPromptHeight(_ height: CGFloat) {
        let clamped = max(Self.compactBasePromptHeight, height)
        guard abs(compactPromptHeight - clamped) > 0.5 else { return }
        compactPromptHeight = clamped
        if !isExpanded, panel?.isVisible == true {
            resizePanel(animated: false)
        }
    }

    /// NSPanel size = visible squircle + shadow margin on every side.
    private var panelSize: NSSize {
        NSSize(
            width: visibleSize.width + Self.shadowMargin * 2,
            height: visibleSize.height + Self.shadowMargin * 2
        )
    }

    private var isResizingProgrammatically: Bool = false

    /// Notification fired every time the panel becomes visible so the
    /// SwiftUI view can re-acquire keyboard focus on each open. With a
    /// `.nonactivatingPanel`, `onAppear` only runs the first time the
    /// host is mounted — subsequent toggles re-show the same view, so
    /// `@FocusState` needs an explicit nudge.
    static let didShowNotification = Notification.Name("QuickAskDidShow")

    private init() {
        if let raw = defaults.string(forKey: chatIdKey),
           let id = UUID(uuidString: raw) {
            self.activeChatId = id
        }
    }

    func attach(appState: AppState) {
        self.appState = appState
    }

    /// Wire the hotkey manager so a press toggles the panel. Called
    /// once from `AppDelegate.applicationDidFinishLaunching`.
    func install() {
        QuickAskHotkeyManager.shared.onTrigger = { [weak self] in
            self?.toggle()
        }
        QuickAskHotkeyManager.shared.install()
    }

    /// Toggle visibility. Pressing the hotkey while the panel is on
    /// screen dismisses it, mirroring launcher-style HUD behaviour.
    /// No-op when the experimental feature flag is off, so a stale
    /// hotkey configured before the user disabled the flag doesn't
    /// surprise them with a panel.
    func toggle() {
        guard FeatureFlags.shared.isVisible(.quickAsk) else { return }
        let visible = panel?.isVisible == true
        let onScreen = panel.flatMap { p -> String in
            guard let s = p.screen else { return "nil" }
            return "\(s.localizedName) frame=\(NSStringFromRect(s.frame))"
        } ?? "nil"
        QuickAskDiag.log("toggle() fired visible=\(visible) panelExists=\(panel != nil) panelScreen=\(onScreen)")
        if let panel, panel.isVisible {
            hide()
        } else {
            // Snapshot context BEFORE show() runs: once the panel
            // becomes key, the frontmost app is Clawix itself, so any
            // selection / clipboard read would point at our own
            // pasteboard handlers rather than the user's previous
            // task. Selection sniffer needs the AX permission and the
            // other-app focus; clipboard sniffer just needs to run
            // before the user pastes anything into our input.
            pendingSelection = QuickAskSelectionSniffer.capture()
            QuickAskClipboardSniffer.markSeenNow()
            if let payload = QuickAskClipboardSniffer.capture() {
                ingestClipboardPayload(payload)
            }
            show()
        }
    }

    private func ingestClipboardPayload(_ payload: QuickAskClipboardSniffer.Payload) {
        switch payload {
        case .text(let text):
            // Text payloads ride as a removable preview chip; we don't
            // write to disk for plain strings since the daemon can't
            // dereference a temp text file the same way it does an
            // attachment URL — the chip's previewText becomes a
            // "Clipboard:" prelude on submit.
            let preview = String(text.prefix(80))
            let placeholderURL = URL(fileURLWithPath: "/dev/null")
            addAttachment(QuickAskAttachment(
                url: placeholderURL,
                kind: .clipboard,
                previewText: preview
            ))
        case .image(let url), .file(let url), .pdf(let url):
            addAttachment(QuickAskAttachment(url: url, kind: .clipboard))
        }
    }

    func show() {
        guard FeatureFlags.shared.isVisible(.quickAsk) else { return }
        QuickAskDiag.log("show() begin activeChatId=\(activeChatId?.uuidString ?? "nil") chats=\(appState?.chats.count ?? -1) screens=\(NSScreen.screens.count) main=\(NSScreen.main?.localizedName ?? "nil")")
        // Apply the QuickAsk-scoped default model if the user has set
        // one in Settings. We rebind `appState.selectedModel` to that
        // value at every show() so the picker inside the HUD always
        // opens at the user's preferred QuickAsk model regardless of
        // what the main composer is currently using.
        if let preferred = quickAskDefaultModel,
           let appState,
           appState.selectedModel != preferred
        {
            appState.selectedAgentRuntime = preferred.contains("/") ? .opencode : .codex
            appState.selectedModel = preferred
        }
        if let id = activeChatId {
            if let chat = appState?.chats.first(where: { $0.id == id }), !chat.messages.isEmpty {
                isExpanded = true
            } else {
                clearActiveChat()
                isExpanded = false
            }
        } else {
            isExpanded = false
        }

        let panel = ensurePanel()
        positionForShow(panel)
        QuickAskDiag.log("show() positioned frame=\(NSStringFromRect(panel.frame)) screen=\(panel.screen?.localizedName ?? "nil") isExpanded=\(isExpanded) level=\(panel.level.rawValue)")
        // Bring forward but don't promote the app to frontmost; the
        // non-activating panel keeps the user's previous app in focus
        // until they click/type into the panel.
        panel.orderFrontRegardless()
        panel.makeKey()
        QuickAskDiag.log("show() ordered front isVisible=\(panel.isVisible) onActiveSpace=\(panel.isOnActiveSpace) frameAfter=\(NSStringFromRect(panel.frame))")
        // Tell SwiftUI to re-focus the text field. Defer one runloop
        // tick so the focus call lands after the panel is fully on
        // screen and SwiftUI has finished any pending layout.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didShowNotification,
                object: nil
            )
        }
    }

    func hide() {
        // Drop any chats that were spawned in Temporary mode during
        // this session so they never reach the sidebar's persistent
        // listing. The user opted into "incognito" precisely so these
        // throwaway prompts disappear with the panel.
        purgeTemporaryChats()
        // Selection / clipboard sniffer hints are scoped to one
        // panel-open; clear them so the next show() doesn't reopen
        // with stale context.
        pendingSelection = nil
        panel?.orderOut(nil)
    }

    /// Drop every QuickAsk-temporary chat from `appState.chats` and
    /// clear `activeChatId` if it pointed to one of them.
    private func purgeTemporaryChats() {
        guard let appState else { return }
        let temporaryIds = Set(
            appState.chats.filter(\.isQuickAskTemporary).map(\.id)
        )
        guard !temporaryIds.isEmpty else { return }
        appState.chats.removeAll { temporaryIds.contains($0.id) }
        if let active = activeChatId, temporaryIds.contains(active) {
            clearActiveChat()
        }
        // Coming back out of incognito on the next show() would otherwise
        // surprise the user with a Temporary toggle still on; reset it.
        isTemporary = false
    }

    /// Flip the Temporary toggle. UI handler for the incognito icon.
    func toggleTemporary() {
        isTemporary.toggle()
    }

    /// Switch the active chat to a specific id. Used by the recent
    /// chats picker (header title click) and the `⌘[ / ⌘]` cycle.
    /// Drops any pending attachments because they were staged for the
    /// previous conversation.
    func activateChat(_ id: UUID) {
        guard activeChatId != id else { return }
        clearAttachments()
        activeChatId = id
        persistActiveChat()
        if !isExpanded {
            isExpanded = true
            resizePanel(animated: true)
        }
    }

    /// `⌘[` (-1) / `⌘]` (+1) navigation: pick the next non-archived,
    /// non-temporary chat ordered by `createdAt` and activate it. Wraps
    /// around at both ends so the user can keep tapping without
    /// hitting a dead end.
    func cycleRecentChats(direction: Int) {
        guard let appState else { return }
        let ordered = appState.chats
            .filter { !$0.isArchived && !$0.isQuickAskTemporary }
            .sorted { $0.createdAt > $1.createdAt }
        guard !ordered.isEmpty else { return }
        let currentIndex = ordered.firstIndex(where: { $0.id == activeChatId }) ?? -1
        let count = ordered.count
        let nextIndex: Int = {
            if currentIndex < 0 { return direction > 0 ? 0 : count - 1 }
            return ((currentIndex + direction) % count + count) % count
        }()
        activateChat(ordered[nextIndex].id)
    }

    /// `⌘⇧N`: drop the current chat (whether temporary or not) and
    /// re-enter the panel in Temporary mode so the next submit creates
    /// a throwaway chat.
    func startTemporaryConversation() {
        clearActiveChat()
        clearAttachments()
        isTemporary = true
        // Prompt is about to be cleared by the view; pre-shrink the
        // compact size so the resize below animates straight to the
        // floor instead of landing on the stale "expanded draft" size
        // and snapping later when the editor remeasures.
        compactPromptHeight = Self.compactBasePromptHeight
        if isExpanded {
            isExpanded = false
            resizePanel(animated: true)
        }
    }

    // MARK: - Conversation lifecycle

    func submitPrompt(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard let appState else { return }

        var decorated = trimmed
        // Web search routing: a leading `/search ` survives through
        // the same path the user could have typed manually. If the
        // prompt already starts with a slash command, leave it alone.
        if webSearchEnabled, !decorated.hasPrefix("/") {
            decorated = "/search \(decorated)"
        }
        // App context: surface the app name as a prelude so the
        // agent knows the focal app without having to inspect the
        // working directory or environment.
        if let bundleId = workWithBundleId,
           let appName = NSWorkspace.shared.runningApplications
               .first(where: { $0.bundleIdentifier == bundleId })?.localizedName
        {
            decorated = "Working with: \(appName)\n\n\(decorated)"
        }

        let resolvedId = appState.submitQuickAsk(
            chatId: activeChatId,
            text: decorated,
            attachments: attachments,
            temporary: isTemporary
        )
        clearAttachments()
        pendingSelection = nil
        if activeChatId != resolvedId {
            activeChatId = resolvedId
            persistActiveChat()
        }
        if !isExpanded {
            isExpanded = true
            resizePanel(animated: true)
        }
    }

    /// Triggered by the `+` menu's "Take a photo" item. Posts a
    /// notification the SwiftUI view listens for; the view presents
    /// `QuickAskCameraSheet` as a sheet over the panel. Wiring it
    /// through a Notification (rather than a published flag) keeps the
    /// SwiftUI sheet from getting stuck open after a manual hide().
    static let presentCameraSheetNotification = Notification.Name("QuickAskPresentCameraSheet")

    func requestCameraSheet() {
        NotificationCenter.default.post(name: Self.presentCameraSheetNotification, object: nil)
    }

    func startNewConversation() {
        purgeTemporaryChats()
        clearActiveChat()
        clearAttachments()
        pendingSelection = nil
        isTemporary = false
        // Same rationale as `startTemporaryConversation`: prompt is
        // cleared by the view immediately after, so reset the compact
        // height now to avoid an animate-then-snap on the resize below.
        compactPromptHeight = Self.compactBasePromptHeight
        if isExpanded {
            isExpanded = false
            resizePanel(animated: true)
        }
    }

    func openInMainApp() {
        guard let id = activeChatId, let appState else {
            hide()
            return
        }
        appState.currentRoute = .chat(id)
        for window in NSApp.windows where window.identifier?.rawValue == FileMenuActions.mainWindowID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hide()
            return
        }
        // No main window currently around: nudge AppKit to reopen one.
        NSApp.activate(ignoringOtherApps: true)
        hide()
    }

    /// User's preferred default model for QuickAsk, persisted in
    /// `quickAsk.defaultModel`. nil means "follow whatever the main
    /// composer has", which is what the controller did before this
    /// setting existed.
    var quickAskDefaultModel: String? {
        get { defaults.string(forKey: defaultModelKey) }
        set {
            if let v = newValue, !v.isEmpty {
                defaults.set(v, forKey: defaultModelKey)
            } else {
                defaults.removeObject(forKey: defaultModelKey)
            }
        }
    }

    /// `⌘,` from inside the panel: jump to Settings → QuickAsk in the
    /// main window. Hides the HUD so focus transfers cleanly to
    /// Settings.
    func openSettings() {
        guard let appState else { return }
        appState.settingsCategory = .quickAsk
        appState.currentRoute = .settings
        for window in NSApp.windows where window.identifier?.rawValue == FileMenuActions.mainWindowID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hide()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        hide()
    }

    private func clearActiveChat() {
        activeChatId = nil
        persistActiveChat()
    }

    private func persistActiveChat() {
        if let id = activeChatId {
            defaults.set(id.uuidString, forKey: chatIdKey)
        } else {
            defaults.removeObject(forKey: chatIdKey)
        }
    }

    // MARK: - Panel construction

    private func ensurePanel() -> QuickAskPanel {
        if let panel { return panel }

        // The SwiftUI view observes AppState directly so streaming
        // deltas and freshly-appended assistant messages redraw the
        // transcript live; the controller's @Published surface alone
        // only fires once per submit (when `activeChatId`/`isExpanded`
        // flip), which is enough for the user's first chip to appear
        // but not for the assistant reply that arrives after.
        // `attach(appState:)` runs in `App.init()` before any hotkey
        // press can reach `show()`, so by the time we reach this point
        // the back-reference is always populated.
        guard let appState else {
            preconditionFailure("QuickAskController.ensurePanel called before attach(appState:)")
        }

        let initialFrame = NSRect(origin: .zero, size: panelSize)
        let panel = QuickAskPanel(contentRect: initialFrame)
        // `canJoinAllSpaces` makes the panel render on whichever Space
        // is active when it is shown; `fullScreenAuxiliary` lets it
        // appear on top of a fullscreen app. Note: `.canJoinAllSpaces`
        // and `.moveToActiveSpace` are mutually exclusive — AppKit
        // throws `NSInternalInconsistencyException` if both are set.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        let host = NSHostingView(
            rootView: QuickAskView(controller: self, appState: appState)
        )
        // Use the autoresize-mask path (instead of constraint-based
        // layout) so the host always fills the panel's contentView.
        // With `translatesAutoresizingMaskIntoConstraints = false` and
        // no explicit constraints, AppKit can leave the host detached
        // from the panel's frame and the resulting window ends up at
        // `NSHostingView`'s default intrinsic size.
        host.frame = NSRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setContentSize(panelSize)

        // Persist the user's drag every time the panel moves so we can
        // restore the same screen position on the next press — but ONLY
        // when expanded. Compact is always bottom-center on the active
        // screen on every invocation, so any drag while compact is
        // intentionally ephemeral; saving it would silently re-park the
        // expanded panel to that ephemeral spot the next time the user
        // reopens with an active conversation.
        positionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            // Programmatic resizes also fire didMoveNotification because
            // the origin changes; skip those so the saved anchor only
            // ever reflects an interactive drag.
            if self.isResizingProgrammatically { return }
            guard self.isExpanded else { return }
            guard let win = note.object as? NSWindow else { return }
            self.saveBottomCenter(from: win.frame)
        }

        // Launcher-style auto-dismiss: while the panel is compact AND
        // the prompt field is empty, any focus loss — clicking another
        // window, switching apps, the menu bar — hides it. If the user
        // has typed something, we keep the panel visible so the draft
        // isn't lost; clearing the prompt re-arms the auto-hide for the
        // next focus loss. Once a conversation exists the panel pins
        // itself open until the user explicitly closes (Esc / close
        // button / "New conversation"). NSMenus popped from the `+`
        // plus menu and the model picker run their own tracking loop
        // without resigning the panel's key status, so they don't trip
        // this.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard !self.isExpanded, self.draftIsEmpty else { return }
            // Defer one runloop tick so any transient resign-then-key
            // hop (e.g. AppKit briefly shifting key during NSMenu
            // dismissal) settles before we decide. If the panel is
            // back to key by then, we're not actually losing focus.
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel else { return }
                guard panel.isVisible, !panel.isKeyWindow else { return }
                guard !self.isExpanded, self.draftIsEmpty else { return }
                self.hide()
            }
        }

        self.panel = panel
        installPasteMonitor()
        return panel
    }

    /// Local NSEvent monitor that catches Cmd+V while the QuickAsk
    /// panel is key. If the clipboard carries a file URL, image, or
    /// PDF data, we stage it as a `paste` attachment and swallow the
    /// event so the prompt input doesn't end up with a string version
    /// of the file path. Plain text falls through and pastes normally.
    private func installPasteMonitor() {
        guard pasteEventMonitor == nil else { return }
        pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  panel.isKeyWindow,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "v"
            else { return event }
            if self.consumeAttachmentPaste() {
                return nil
            }
            return event
        }
    }

    /// Inspects `NSPasteboard.general` for non-text content and stages
    /// it as a `paste` attachment. Returns true when something was
    /// staged (caller swallows the event); false when the clipboard
    /// is plain text and the system paste should proceed.
    private func consumeAttachmentPaste() -> Bool {
        let pb = NSPasteboard.general
        var staged = false

        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls where url.isFileURL {
                addAttachment(QuickAskAttachment(url: url, kind: .paste))
                staged = true
            }
        }

        if !staged, let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            for image in images {
                if let url = persistImage(image) {
                    addAttachment(QuickAskAttachment(url: url, kind: .paste))
                    staged = true
                }
            }
        }

        if !staged,
           let pdfData = pb.data(forType: NSPasteboard.PasteboardType("com.adobe.pdf")),
           let url = persistData(pdfData, ext: "pdf") {
            addAttachment(QuickAskAttachment(url: url, kind: .paste))
            staged = true
        }

        return staged
    }

    private func persistImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return persistData(png, ext: "png")
    }

    private func persistData(_ data: Data, ext: String) -> URL? {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Clawix-Captures", isDirectory: true)
        guard let dir else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = dir.appendingPathComponent("paste-\(stamp).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Compact (no conversation) ALWAYS lands bottom-center of the
    /// screen the cursor is on, regardless of any prior drag: the user
    /// thinks of the empty HUD as a fresh prompt, not a draggable
    /// window, so each fresh invocation snaps back to the canonical
    /// "below, centered" anchor on whichever display they're working
    /// on. Expanded (active conversation) restores the last drag so
    /// the conversation reopens where the user parked it. `NSScreen.main`
    /// is the screen with the key window (not the cursor), so on
    /// multi-display setups we pick the pointer's screen explicitly to
    /// land near the user's attention. `visibleFrame.minY` already
    /// accounts for the dock, so adding a fixed offset keeps the gap
    /// consistent whether the dock is pinned or hidden.
    private func positionForShow(_ panel: QuickAskPanel) {
        let size = panelSize
        if isExpanded, let bottomCenter = restoreBottomCenter() {
            let frame = clampedFrame(forBottomCenter: bottomCenter, size: size)
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        let screen = screenContainingCursor() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let area = screen.visibleFrame
        // We want the *visible* bottom edge of the squircle (not the
        // panel's outer rectangle, which extends `shadowMargin` past
        // it on every side) to sit `bottomMargin` above the dock.
        // Subtract the shadow margin so the perceived gap matches.
        let bottomMargin: CGFloat = 36
        let x = area.midX - size.width / 2
        let y = area.minY + bottomMargin - Self.shadowMargin
        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true,
            animate: false
        )
    }

    /// Animate the panel between compact and expanded sizes while
    /// keeping the bottom-center of the visible squircle pinned. The
    /// input row sits near the bottom of the panel in both sizes, so
    /// anchoring by bottom-center means the prompt field stays under
    /// the user's cursor across the resize, only the conversation
    /// area appears (or disappears) above it.
    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let oldFrame = panel.frame
        let newSize = panelSize
        let visibleBottomCenter = NSPoint(
            x: oldFrame.midX,
            y: oldFrame.minY + Self.shadowMargin
        )
        let target = clampedFrame(
            forBottomCenter: visibleBottomCenter,
            size: newSize,
            screen: panel.screen
        )

        isResizingProgrammatically = true
        panel.setFrame(target, display: true, animate: animated)
        // Reset the guard after the animation kick-off so any user
        // drag that arrives while the animation is still in flight
        // is still treated as user input. AppKit's animated setFrame
        // is short (~0.15s) so a runloop hop is sufficient in practice.
        DispatchQueue.main.async { [weak self] in
            self?.isResizingProgrammatically = false
        }
    }

    private func clampedFrame(
        forBottomCenter bottomCenter: NSPoint,
        size: NSSize,
        screen explicitScreen: NSScreen? = nil
    ) -> NSRect {
        let x = bottomCenter.x - size.width / 2
        let y = bottomCenter.y - Self.shadowMargin
        var frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        let screen = explicitScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(bottomCenter) })
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // If growing past the top edge would bury the conversation
            // under the menu bar, push the panel down so it stays in
            // view. Same idea on the bottom edge for the dock.
            let topOverflow = frame.maxY - visible.maxY
            if topOverflow > 0 {
                frame.origin.y -= topOverflow
            }
            let bottomOverflow = visible.minY - frame.minY
            if bottomOverflow > 0 {
                frame.origin.y += bottomOverflow
            }
            // Same horizontal clamp in case a multi-monitor layout
            // changed since the last position was saved.
            let rightOverflow = frame.maxX - visible.maxX
            if rightOverflow > 0 {
                frame.origin.x -= rightOverflow
            }
            let leftOverflow = visible.minX - frame.minX
            if leftOverflow > 0 {
                frame.origin.x += leftOverflow
            }
        }
        return frame
    }

    private func screenContainingCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    // MARK: - Position persistence

    /// We persist only the bottom-center of the visible squircle, NOT
    /// the panel's full frame. The panel changes size between the
    /// compact (100pt tall) and expanded (~540pt tall) layouts, but the
    /// user thinks of the input row as the "anchor". Saving a
    /// frame-with-size means the panel would jump after every
    /// shrink/grow on subsequent reopens. Saving just the bottom-center
    /// lets `positionForShow` rebuild a frame that matches whatever
    /// size we are about to render at.
    private func saveBottomCenter(from frame: NSRect) {
        let bottomCenter = NSPoint(
            x: frame.midX,
            y: frame.minY + Self.shadowMargin
        )
        defaults.set(NSStringFromPoint(bottomCenter), forKey: bottomCenterKey)
    }

    private func restoreBottomCenter() -> NSPoint? {
        if let raw = defaults.string(forKey: bottomCenterKey) {
            let point = NSPointFromString(raw)
            if isPointOnAnyScreen(point) { return point }
            return nil
        }
        // One-shot migration from the old "full frame" key so users
        // who already dragged the compact HUD do not see it jump back
        // to default placement on the first launch after this change.
        if let legacy = defaults.string(forKey: legacyFrameKey) {
            let rect = NSRectFromString(legacy)
            if rect.width > 100, rect.height > 50 {
                let point = NSPoint(x: rect.midX, y: rect.minY + Self.shadowMargin)
                if isPointOnAnyScreen(point) { return point }
            }
        }
        return nil
    }

    private func isPointOnAnyScreen(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens where screen.visibleFrame.contains(point) {
            return true
        }
        return false
    }
}
