import SwiftUI
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

// ChatGPT-iOS-styled chat surface, rebuilt on iOS 26 Liquid Glass.
// Architecture:
//   - pure black canvas filling the window
//   - transcript scrolls edge-to-edge underneath the floating chrome
//   - top bar: two glass clusters in `GlassEffectContainer`s so they
//     morph as a unit when system animations run (rotation, dynamic
//     type)
//   - composer: a tall floating glass capsule anchored to the bottom
//     safe area, with the transcript fading behind it
//   - user messages render as light squircle bubbles, assistant
//     responses as bare text directly on black, with a "Thinking"
//     shimmer at the tail while streaming (mirrors the Mac app)
// `glassEffect(in:)` is the iOS 26 API; the deployment target was
// bumped to 26.0 to use it without availability noise everywhere.

struct ChatDetailView: View {
    @Bindable var store: BridgeStore
    let chatId: String
    let onBack: () -> Void
    var onOpenFile: (String) -> Void = { _ in }
    var onOpenProject: (String) -> Void = { _ in }
    var onNewChat: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var composerText: String = ""
    @State private var composerAttachments: [ComposerAttachment] = []
    @State private var composerResetToken: Int = 0
    @State private var expandedReasoning: Set<String> = []
    @State private var showProjectPicker: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var renameDraft: String = ""
    // Ids that have already been laid out at least once. Initial
    // snapshot fills this on first hasLoaded; new messages appended
    // afterwards are NOT in here on creation, so they animate in.
    @State private var alreadySeenMessageIds: Set<String> = []
    // Flips to true once the initial snapshot has been processed.
    // Until then, every row renders without an entrance animation
    // so the snapshot doesn't slide in as if the user typed it.
    @State private var didCaptureInitialSnapshot: Bool = false
    // Drives the entrance fade of the transcript ScrollView only
    // (background and chrome render at full opacity from the first
    // frame). Stays false until `hasLoaded` flips and one layout tick
    // has elapsed, so the ForEach materializing and the ScrollView
    // reanchoring to the bottom both happen invisibly. Idempotent:
    // once true, never returns to false within this view instance,
    // so streamed messages don't trigger a re-fade.
    @State private var transcriptVisible: Bool = false
    // Captured on first render: true for a newly-created conversation
    // because the FAB seeds `messagesByChat[id] = []` before this view
    // mounts, so it is already loaded and empty. Existing chats start
    // with `hasLoaded == false`, keeping autofocus limited to fresh
    // conversations.
    @State private var isFreshChat: Bool? = nil
    // Declarative scroll model. `bottomId` is the id of the view
    // currently anchored to the viewport's `.bottom`; when the
    // transcript is at the tail, it equals `ChatScroll.tail`. Geometry
    // metrics decide whether there is real overflow at all — without
    // them, a chat that fits in the viewport could still report a
    // non-tail anchor during a layout in flight and surface a button
    // that the user has nothing to scroll to.
    @State private var bottomId: String? = ChatScroll.tail
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var verticalInsets: CGFloat = 0
    // New-message counter shown as a badge on the scroll-to-bottom
    // button while the user is reading history above. Resets to 0 the
    // moment the user is back at the tail.
    @State private var unreadCount: Int = 0
    // Last tail message id observed by the unread tracker. Lets us
    // distinguish "appended a new turn" (bump badge) from "prepended a
    // page of history" (do not). With pagination, a `messages.count`
    // increase can come from either direction; only changes to the
    // last id mean a new tail.
    @State private var unreadAnchorId: String? = nil
    // Measured height of the bottom chrome (composer + its padding) so
    // the floating bubble can sit just above it without depending on a
    // hardcoded offset that drifts when the composer grows multiline.
    @State private var bottomChromeHeight: CGFloat = 0
    // Recording state. nil = composer mode; non-nil = the recording
    // overlay is up. The phase distinguishes "live capture" from the
    // post-stop transcribing animation that the mic flow runs before
    // dropping the recognised text back into the composer.
    @State private var recording: ActiveRecording? = nil
    // Token to ignore stale transcribe completions if the user
    // cancels/restarts mid-flight.
    @State private var transcriptionToken: Int = 0
    // Drives the live audio capture + on-device transcription. Owned
    // by the chat so the levels survive across the recording/paused
    // transitions and we can stop/cancel from any of the overlay
    // callbacks without re-creating the recorder.
    @StateObject private var voiceRecorder = VoiceRecorder()
    #if canImport(UIKit)
    // Drives the fullscreen image viewer. Set when the user taps a
    // thumbnail above their bubble; cleared by the viewer's own dismiss.
    @State private var imageViewer: ImageViewerSelection?
    #endif

    private var chat: WireChat? { store.chat(chatId) }
    private var messages: [WireMessage] { store.messages(for: chatId) }
    /// Cached `DerivedProject.from(chats:)` result. The previous code
    /// recomputed it twice per body (once for `derivedProject`, once
    /// for the project picker sheet) which, with `@Observable`,
    /// happened on every state change in the chat detail. The cache
    /// is rebuilt only when `store.chats` actually changes (Equatable
    /// diff via `.onChange`); reads from `body` are O(1) lookup.
    @State private var cachedAllProjects: [DerivedProject] = []
    // Project for the open conversation, derived from the chat `cwd`.
    // nil means the title pill falls back to the chat title and does
    // not open the project picker.
    private var derivedProject: DerivedProject? {
        guard let cwd = chat?.cwd, !cwd.isEmpty else { return nil }
        return cachedAllProjects.first(where: { $0.cwd == cwd })
    }
    private var allProjects: [DerivedProject] { cachedAllProjects }
    private var hasLoaded: Bool { store.hasLoadedMessages(chatId) }
    /// Scroll-up trigger zone in points. While the user is within this
    /// many points of the top of the transcript AND the daemon has
    /// older history available, the store fires `loadOlderMessages`.
    /// Re-entrancy is gated by `loadingOlderByChat`, so the geometry
    /// callback can fire freely without burning round trips.
    private static let loadOlderThreshold: CGFloat = 200

    // Derived scroll predicates. Keeping them computed (vs. @State)
    // means a single source of truth and no risk of going stale.
    private var hasOverflow: Bool {
        // 1pt epsilon absorbs sub-pixel rounding when content and
        // viewport-minus-insets are visually identical.
        contentHeight > viewportHeight - verticalInsets + 1
    }
    private var isAtBottom: Bool {
        bottomId == ChatScroll.tail
    }
    private var showScrollToBottom: Bool {
        hasOverflow && !isAtBottom
    }

    var body: some View {
        // The transcript is fully declarative: `defaultScrollAnchor`
        // pins the first layout to the bottom and `scrollPosition`
        // exposes the current anchor id as state. The scroll-to-bottom
        // button mutates that binding instead of calling into a
        // ScrollViewProxy, which removes the imperative path that used
        // to race with layout-in-flight.
        ZStack(alignment: .bottom) {
            transcript
                .background(Palette.background.ignoresSafeArea())
                .onAppear {
                    if isFreshChat == nil {
                        isFreshChat = hasLoaded && messages.isEmpty
                    }
                    wireBridgeTranscription()
                }
                .topBarBlurFade(height: 135)
                .safeAreaInset(edge: .top, spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomChrome
                }

            // Sits above the composer without affecting its layout, so
            // appearing/disappearing animates only the bubble itself
            // (scale + opacity) and never nudges the composer.
            scrollToBottomButton
                .padding(.bottom, bottomChromeHeight + 10)
                .allowsHitTesting(showScrollToBottom)

            recordingLayer
        }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showProjectPicker) {
                ProjectPickerSheet(
                    projects: allProjects,
                    currentCwd: chat?.cwd ?? "",
                    store: store,
                    onSelect: { selected in
                        showProjectPicker = false
                        guard selected.cwd != chat?.cwd else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onOpenProject(selected.cwd)
                        }
                    },
                    onDismiss: { showProjectPicker = false }
                )
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.surface)
                .preferredColorScheme(.dark)
            }
            .onChange(of: store.chats, initial: true) { _, newChats in
                cachedAllProjects = DerivedProject.from(
                    chats: newChats.filter { !$0.isArchived }
                )
            }
            #if canImport(UIKit)
            .fullScreenCover(item: $imageViewer) { selection in
                ImageViewerView(
                    images: selection.images,
                    startIndex: selection.startIndex
                )
                .preferredColorScheme(.dark)
            }
            #endif
            .alert("Rename chat", isPresented: $showRenameAlert) {
                TextField("Chat title", text: $renameDraft)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Save", action: commitRename)
            } message: {
                Text("Choose a new name for this chat.")
            }
    }

    // MARK: Transcript

    private var transcript: some View {
        // Messaging-style scroll built on the iOS 18 split
        // `defaultScrollAnchor(_:for:)` API. Each role gets its own
        // anchor so the three concerns don't fight each other:
        //
        //   * `.alignment   = .top`    → when the transcript is shorter
        //                                than the viewport (fresh chat
        //                                with one or two bubbles), it
        //                                sits at the top edge instead
        //                                of being pinned to the bottom
        //                                with empty space above.
        //   * `.initialOffset = .bottom` → opening an existing chat
        //                                whose history overflows lands
        //                                directly at the latest message.
        //   * `.sizeChanges = .bottom` → while streaming, sending or
        //                                receiving new content, the
        //                                viewport stays glued to the
        //                                tail unless the user has
        //                                scrolled away.
        //
        // The 1pt `Color.clear` sentinel at the end of the stack is the
        // canonical "you are at the tail" marker for `scrollPosition`.
        //
        // Eager `VStack` (not `LazyVStack`) on purpose: tall assistant
        // rows (timeline + markdown + file pills) interact badly with
        // LazyVStack's just-in-time materialization here, where rows
        // that should be entering the viewport pop in suddenly
        // instead of sliding under the chrome. The transcript stays
        // bounded by pagination (`bridgeInitialPageLimit` on first
        // paint, page-by-page on scroll-up) instead of a hard cap.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Spinner that surfaces while a `loadOlderMessages`
                // round trip is in flight. Sits above the messages so
                // the user gets feedback the moment the scroll-up
                // sentinel fires; collapses to zero height when idle
                // so the layout doesn't reserve dead space.
                if store.loadingOlderByChat[chatId] == true {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .tint(Palette.textTertiary)
                        Spacer()
                    }
                    .frame(height: 28)
                    .transition(.opacity)
                }
                Color.clear.frame(height: 8)
                if hasLoaded {
                    ForEach(messages, id: \.id) { msg in
                        MessageView(
                            message: msg,
                            attachmentImages: store.attachmentImagesByMessageId[msg.id] ?? [],
                            isReasoningExpanded: expandedReasoning.contains(msg.id),
                            toggleReasoning: { toggleReasoning(messageId: msg.id) },
                            onOpenFile: onOpenFile,
                            onOpenImage: { startIndex, images in
                                #if canImport(UIKit)
                                imageViewer = ImageViewerSelection(
                                    images: images,
                                    startIndex: startIndex
                                )
                                #endif
                            },
                            shouldAnimateEntrance: shouldAnimateEntrance(for: msg),
                            store: store
                        )
                        .id(msg.id)
                        .onAppear { alreadySeenMessageIds.insert(msg.id) }
                    }
                }
                Color.clear.frame(height: 30)
                Color.clear.frame(height: 1).id(ChatScroll.tail)
            }
            .padding(.horizontal, 20)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition(id: $bottomId, anchor: .bottom)
        .simultaneousGesture(
            TapGesture().onEnded {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
                #endif
            }
        )
        // Geometry feeds `hasOverflow` AND the scroll-up trigger for
        // pagination. We collect content/container/insets/offset in
        // one Equatable struct so SwiftUI filters out the sub-pixel
        // updates that fire while the composer is animating its
        // height. `offsetY` becoming small (user near the top, with
        // overflow above the threshold) is the "load older" signal;
        // the store dedupes so the callback can fire freely.
        .onScrollGeometryChange(for: ScrollMetrics.self) { geom in
            ScrollMetrics(
                content: geom.contentSize.height,
                container: geom.containerSize.height,
                insets: geom.contentInsets.top + geom.contentInsets.bottom,
                offsetY: geom.contentOffset.y
            )
        } action: { _, m in
            contentHeight = m.content
            viewportHeight = m.container
            verticalInsets = m.insets
            // Threshold check: only fire when there is real overflow
            // (no point pulling more for a chat that fits in the
            // viewport) and the user is genuinely near the top.
            let nearTop = m.offsetY < Self.loadOlderThreshold
            let realOverflow = m.content > m.container - m.insets + 1
            if hasLoaded, nearTop, realOverflow {
                store.requestOlderIfNeeded(chatId: chatId)
            }
        }
        .onChange(of: hasLoaded, initial: true) { _, loaded in
            guard loaded, !didCaptureInitialSnapshot else { return }
            didCaptureInitialSnapshot = true
            alreadySeenMessageIds.formUnion(messages.map(\.id))
            unreadAnchorId = messages.last?.id
        }
        .onChange(of: hasLoaded, initial: true) { _, loaded in
            guard loaded, !transcriptVisible else { return }
            // Wait one frame so the ForEach materializes and the
            // ScrollView resolves its `.bottom` initialOffset before
            // we fade the transcript in. Without this pause the flip
            // races the first composition and the reanchor is visible.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 16_000_000)
                transcriptVisible = true
            }
        }
        .onChange(of: contentHeight) { _, h in
            // Safety net: in chats with little content the geometry
            // callback may settle in the same frame as the sleep
            // above; whichever fires first wins thanks to the guard.
            guard !transcriptVisible, hasLoaded, h > 0 else { return }
            transcriptVisible = true
        }
        .onChange(of: messages.count) { oldCount, newCount in
            guard newCount > oldCount, !isAtBottom else { return }
            // Only count new messages at the tail toward the unread
            // badge. Pages prepended at the head also grow `count`,
            // but they're history the user is intentionally pulling
            // and shouldn't bump the new-message indicator.
            let oldLastId = unreadAnchorId
            let newLastId = messages.last?.id
            if let newLastId, newLastId != oldLastId {
                unreadCount += 1
                unreadAnchorId = newLastId
            }
        }
        .onChange(of: isAtBottom) { _, atBottom in
            if atBottom { unreadCount = 0 }
        }
        .opacity(transcriptVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.14), value: transcriptVisible)
    }

    private struct ScrollMetrics: Equatable {
        let content: CGFloat
        let container: CGFloat
        let insets: CGFloat
        let offsetY: CGFloat
    }

    private enum ChatScroll {
        static let tail = "__chat_tail__"
    }

    private func shouldAnimateEntrance(for message: WireMessage) -> Bool {
        // Only user-sent messages slide in from below. Assistant
        // responses surface their content via streaming and don't
        // need a bubble-level entrance.
        guard message.role == .user else { return false }
        // Initial snapshot rows must NOT animate; only messages added
        // after the snapshot was captured (i.e. ones the user just
        // sent) get the slide-up + fade-in.
        guard didCaptureInitialSnapshot else { return false }
        return !alreadySeenMessageIds.contains(message.id)
    }

    // MARK: Top bar

    private var topBar: some View {
        // titlePill is 48pt tall on purpose (slightly bigger than the
        // 46pt side circles). Padding the back button and actionPill by
        // 1pt vertical keeps their visible glass circles at 46 while
        // letting the HStack settle at 48 so the chip actually grows.
        // Without the padding, HStack centering would absorb the
        // difference and the chip would visually look the same height.
        HStack(spacing: 8) {
            GlassIconButton(systemName: "chevron.left", size: 46, iconSize: 20, action: handleBack)
                .padding(.vertical, 1)
            titlePill

            Spacer()

            actionPill
                .padding(.vertical, 1)
        }
    }

    // Right-side double pill that mirrors the home `actionPill`: two
    // icon buttons share a single glass capsule so they read as one
    // floating affordance. Compose lives on the left as the primary
    // action (start a fresh conversation), ellipsis on the right.
    private var actionPill: some View {
        HStack(spacing: 0) {
            Button(action: {
                Haptics.send()
                onNewChat()
            }) {
                ComposeIcon(size: 20)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    handleRename()
                } label: {
                    if let img = MenuIconImage.pencil {
                        Label { Text("Rename") } icon: { Image(uiImage: img) }
                    } else {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                Button {
                    handleArchive()
                } label: {
                    if let img = MenuIconImage.archive {
                        Label { Text("Archive") } icon: { Image(uiImage: img) }
                    } else {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(BodyFont.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        }
        .glassCapsule()
    }

    private func handleRename() {
        renameDraft = chat?.title ?? ""
        // Defer one tick so the popover dismissal animation finishes
        // before the alert pops in. Without it, iOS sometimes drops
        // the alert request entirely while the popover is still
        // collapsing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showRenameAlert = true
        }
    }

    private func commitRename() {
        store.renameChat(chatId: chatId, newTitle: renameDraft)
    }

    private func handleArchive() {
        // Wire-up pending: BridgeClient does not yet expose archiveChat
        // outbound from iOS.
    }

    private func handleBack() {
        // Belt-and-braces: call the explicit pop callback first, then
        // ask SwiftUI's environment to dismiss as a fallback. Either
        // path works on iOS 26; calling both is harmless because the
        // second one is a no-op once the view is popping.
        onBack()
        dismiss()
    }

    @ViewBuilder
    private var titlePill: some View {
        if let project = derivedProject {
            Button {
                Haptics.tap()
                showProjectPicker = true
            } label: {
                HStack(spacing: 8) {
                    FolderClosedIcon(size: 20, weight: 1.4)
                        .foregroundStyle(Palette.textPrimary)
                    Text(store.projectDisplayName(cwd: project.cwd, fallback: project.name))
                        .font(BodyFont.manrope(size: 17, wght: 500))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(BodyFont.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .glassCapsule()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom chrome

    private var bottomChrome: some View {
        ComposerView(
            text: $composerText,
            attachments: $composerAttachments,
            onSend: send,
            onMicTap: { startRecording(.transcribeToText) },
            onVoiceTap: { startRecording(.sendAsAudio) },
            onStop: { store.interruptTurn(chatId: chatId) },
            hasActiveTurn: chat?.hasActiveTurn ?? false,
            autofocusOnAppear: isFreshChat ?? false,
            compact: !messages.isEmpty,
            resetToken: composerResetToken
        )
            .opacity(recording == nil ? 1 : 0)
            .allowsHitTesting(recording == nil)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { _, height in
                bottomChromeHeight = height
            }
    }

    @ViewBuilder
    private var recordingLayer: some View {
        if let active = recording {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { cancelRecording() }
                    .transition(.opacity)

                RecordingOverlay(
                    purpose: active.purpose,
                    phase: active.phase,
                    levels: voiceRecorder.levels,
                    onCancel: cancelRecording,
                    onStop: { stopRecording(active) },
                    onResume: resumeRecording,
                    onSend: { sendRecording(active) }
                )
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: active.phase)
        }
    }

    // Floating "scroll to bottom" pill. Same liquid-glass surface as the
    // top bar buttons so it reads as part of the same chrome family.
    // Hidden state collapses scale to 0.6 + opacity to 0; springs back
    // when the transcript has scrolled away from the tail.
    private var scrollToBottomButton: some View {
        Button {
            Haptics.tap()
            // Mutating the `scrollPosition` binding is the supported
            // way to programmatically anchor a view to the viewport
            // edge. The sentinel is a 1pt Color.clear at the end of
            // the LazyVStack, so its geometry is stable even while
            // the last message is still streaming and growing.
            withAnimation(.smooth(duration: 0.32)) {
                bottomId = ChatScroll.tail
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Circle())
                Image(systemName: "arrow.down")
                    .font(BodyFont.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(BodyFont.manrope(size: 11, wght: 700))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 14, y: -14)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(showScrollToBottom ? 1 : 0.6, anchor: .center)
        .opacity(showScrollToBottom ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: showScrollToBottom)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: unreadCount)
    }

    // MARK: Actions

    private func toggleReasoning(messageId: String) {
        Haptics.tap()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expandedReasoning.contains(messageId) {
                expandedReasoning.remove(messageId)
            } else {
                expandedReasoning.insert(messageId)
            }
        }
    }

    private func send() {
        let text = composerText
        let attachmentSnapshot = composerAttachments
        // Clear synchronously so a second tap immediately sees an empty
        // binding (canSend → false) and cannot fire a duplicate send.
        // The composer also remounts its TextField on `composerResetToken`
        // so the underlying UITextView never lingers with stale text.
        composerText = ""
        composerAttachments = []
        composerResetToken &+= 1
        // Flip the chat's `hasActiveTurn` synchronously, in the same
        // SwiftUI tick that `composerText = ""` makes `canSend` go
        // false. Without this, the trailing glyph would animate
        // arrow → waveform → stop because the network dispatch (and
        // the flag flip) only landed one tick later via the detached
        // task below. The attachment count flows in here too so the
        // optimistic preview matches the Mac echo and the bubble does
        // not duplicate when the round-trip lands.
        let optimisticId = store.beginPendingTurn(
            chatId: chatId,
            text: text,
            attachmentCount: attachmentSnapshot.count
        )
        if let optimisticId, !attachmentSnapshot.isEmpty {
            store.attachLocalImages(
                messageId: optimisticId,
                images: attachmentSnapshot.map(\.preview)
            )
        }
        // Encode JPEG bytes off-main; the bridge call back on the main
        // actor only fires once we have all the wire payloads ready.
        Task.detached(priority: .userInitiated) {
            let wire = attachmentSnapshot.compactMap { $0.wireAttachment() }
            await MainActor.run {
                store.dispatchPrompt(chatId: chatId, text: text, attachments: wire)
            }
        }
    }

    // MARK: Recording flow

    private func startRecording(_ purpose: RecordingOverlay.Purpose) {
        guard recording == nil else { return }
        Haptics.tap()
        voiceRecorder.start()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            recording = ActiveRecording(purpose: purpose, phase: .recording)
        }
    }

    /// Hook the recorder up to the Mac bridge so `voiceRecorder.stop`
    /// transcribes via Whisper on the daemon when the iPhone is paired.
    /// Falls back to on-device Apple Speech inside `VoiceRecorder` if
    /// the bridge throws. The recorder always writes m4a/AAC so the
    /// MIME type is fixed.
    private func wireBridgeTranscription() {
        let store = self.store
        // Forward the system language as a Whisper hint so Spanish
        // audio decodes as Spanish instead of falling through to the
        // model's English prefill default. The recorder owns the value
        // so the on-device Apple Speech fallback (a different code
        // path) keeps using the same locale.
        voiceRecorder.bridgeLanguage = Self.systemWhisperLanguage()
        voiceRecorder.bridgeTranscriber = { [weak store] url, language in
            guard let store else {
                throw BridgeStore.TranscriptionBridgeError.notConnected
            }
            let data = try Data(contentsOf: url)
            let requestId = UUID().uuidString
            return try await store.transcribeAudio(
                requestId: requestId,
                audioData: data,
                mimeType: "audio/m4a",
                language: language
            )
        }
    }

    /// Two-letter language code for the user's preferred system
    /// language, formatted for Whisper (lowercase, base code only:
    /// "es-ES" → "es"). Returns `nil` if we can't read it, in which
    /// case the daemon falls back to auto-detection.
    private static func systemWhisperLanguage() -> String? {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let code = Locale(identifier: preferred).language.languageCode?.identifier
        guard let code, !code.isEmpty else { return nil }
        return code.lowercased()
    }

    private func cancelRecording() {
        guard recording != nil else { return }
        Haptics.tap()
        transcriptionToken &+= 1
        voiceRecorder.cancel()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = nil
        }
    }

    // Square stop button. Mic flow runs the transcription animation
    // (text lands in the composer for editing). Voice flow pauses the
    // take so the user can keep talking when they hit play, send the
    // captured audio with the up-arrow, or discard with the cancel
    // pill above the capsule.
    private func stopRecording(_ active: ActiveRecording) {
        switch active.purpose {
        case .transcribeToText:
            beginTranscribing(autoSend: false)
        case .sendAsAudio:
            pauseRecording()
        }
    }

    // Up-arrow send button. Both flows go through on-device
    // transcription; the only difference is that mic mode hands the
    // text back to the composer for editing while voice mode submits
    // it as a chat prompt straight away.
    private func sendRecording(_ active: ActiveRecording) {
        switch active.purpose {
        case .transcribeToText:
            beginTranscribing(autoSend: true)
        case .sendAsAudio:
            beginTranscribing(autoSend: true)
        }
    }

    private func pauseRecording() {
        guard var current = recording, current.phase == .recording else { return }
        voiceRecorder.pause()
        current.phase = .paused
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
    }

    private func resumeRecording() {
        guard var current = recording, current.phase == .paused else { return }
        Haptics.tap()
        voiceRecorder.resume()
        current.phase = .recording
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
    }

    private func beginTranscribing(autoSend: Bool) {
        guard var current = recording else { return }
        guard current.phase == .recording || current.phase == .paused else { return }
        let purpose = current.purpose
        current.phase = .transcribing
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
        transcriptionToken &+= 1
        let token = transcriptionToken
        // sendAsAudio: keep the m4a around long enough to ship it as
        // an attachment alongside the transcript. The bridge dispatcher
        // is in charge of deleting the file after the encode is done.
        // Other purposes use the legacy stop(_:) which deletes inline.
        if purpose == .sendAsAudio && autoSend {
            voiceRecorder.stopAndKeep { transcript, audioURL in
                guard token == transcriptionToken else { return }
                guard recording?.phase == .transcribing else { return }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let urlForSend = audioURL
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    recording = nil
                }
                if let urlForSend {
                    sendVoiceNote(audioURL: urlForSend, transcript: trimmed)
                } else if !trimmed.isEmpty {
                    composerText = trimmed
                    send()
                }
            }
        } else {
            voiceRecorder.stop { transcript in
                guard token == transcriptionToken else { return }
                guard recording?.phase == .transcribing else { return }
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if autoSend && !trimmed.isEmpty {
                    composerText = trimmed
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        recording = nil
                    }
                    send()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        recording = nil
                        if !trimmed.isEmpty {
                            composerText = trimmed
                        }
                    }
                }
            }
        }
    }

    /// sendAsAudio submission: bundles the m4a bytes as a `kind=audio`
    /// attachment in the same `sendPrompt` the daemon receives, with
    /// the Whisper transcript as the prompt text. The daemon stores
    /// the bytes against the user message so the chat history shows a
    /// playable bubble on every surface; the transcript is what Codex
    /// actually consumes.
    private func sendVoiceNote(audioURL: URL, transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? Data(contentsOf: audioURL) else {
            try? FileManager.default.removeItem(at: audioURL)
            if !trimmedTranscript.isEmpty {
                composerText = trimmedTranscript
                send()
            }
            return
        }
        let attachment = WireAttachment(
            id: UUID().uuidString,
            kind: .audio,
            mimeType: "audio/m4a",
            filename: audioURL.lastPathComponent,
            dataBase64: data.base64EncodedString()
        )
        let chatId = self.chatId
        let store = self.store
        // Optimistic bubble appears immediately. The transcript is the
        // visible text; attachmentCount=0 keeps the bridge preview
        // formatter from prefixing "[image]" markers.
        store.beginPendingTurn(chatId: chatId, text: trimmedTranscript)
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                store.dispatchPrompt(
                    chatId: chatId,
                    text: trimmedTranscript,
                    attachments: [attachment]
                )
            }
            try? FileManager.default.removeItem(at: audioURL)
        }
    }
}

// Recording overlay state owned by the chat. Equatable so the
// `.animation(_:value:)` modifier can detect transitions cleanly.
private struct ActiveRecording: Equatable {
    var purpose: RecordingOverlay.Purpose
    var phase: RecordingOverlay.Phase
}

// MARK: - Message rendering

private struct MessageView: View {
    let message: WireMessage
    var attachmentImages: [UIImage] = []
    let isReasoningExpanded: Bool
    let toggleReasoning: () -> Void
    var onOpenFile: (String) -> Void = { _ in }
    var onOpenImage: (Int, [UIImage]) -> Void = { _, _ in }
    var shouldAnimateEntrance: Bool = false
    var store: BridgeStore? = nil

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 6) {
                if let audioRef = message.audioRef, let store {
                    UserAudioBubble(audioRef: audioRef, store: store)
                }
                UserBubble(
                    text: message.content,
                    attachmentImages: attachmentImages,
                    animateEntrance: shouldAnimateEntrance,
                    onOpenImage: onOpenImage
                )
            }
        } else {
            assistantBlock
        }
    }

    private var assistantBlock: some View {
        // Inline images Codex generated for this turn. Two sources are
        // merged inside `paths(from:)`: workitem-level paths and
        // markdown links the model wrote into the body. The body is
        // stripped of the latter so the user doesn't see the raw
        // `![](file:/Users/.../*.png)` text on top of the rendered
        // tile. While the turn is still streaming, `strip` also hides
        // any unfinished `[…` / `![…` opener so the link materialises
        // in one go when the closing paren lands instead of being
        // typed character by character on screen.
        let isStreaming = !message.streamingFinished
        let inlinePaths = AssistantInlineImageSources.paths(from: message)
        let needsStrip = !inlinePaths.isEmpty || isStreaming
        let proseSource = needsStrip
            ? AssistantInlineImageSources.strip(
                message.content,
                isStreaming: isStreaming
            )
            : message.content
        return VStack(alignment: .leading, spacing: 12) {
            // Full-Mac parity: timeline interleaves reasoning chunks
            // with tool-group rows, plus the elapsed-time disclosure
            // header summarizing the whole turn. Skipped when neither
            // is present (short answers stay flat).
            if !message.timeline.isEmpty || message.workSummary != nil {
                AssistantTimelineView(
                    timeline: message.timeline,
                    workSummary: message.workSummary,
                    isStreaming: !message.streamingFinished
                )
            } else if !message.reasoningText.isEmpty {
                // Legacy path: rollouts that didn't carry a structured
                // timeline still surface their reasoning as a
                // collapsible block.
                ReasoningDisclosure(
                    text: message.reasoningText,
                    isExpanded: isReasoningExpanded,
                    toggle: toggleReasoning
                )
            }

            if !proseSource.isEmpty {
                AssistantMarkdownView(text: proseSource)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !inlinePaths.isEmpty, let store {
                AssistantInlineImagesView(
                    paths: inlinePaths,
                    store: store,
                    onOpen: onOpenImage
                )
            }

            ChangedFilePills(timeline: message.timeline, onOpen: onOpenFile)

            if !message.streamingFinished {
                ThinkingShimmer(text: "Thinking")
                    .padding(.top, 2)
                    .onAppear { Haptics.tap() }
            }
            if message.streamingFinished && !message.content.isEmpty {
                MessageActions(content: message.content)
                    .padding(.top, 2)
            }
        }
    }
}

// User-message bubble. Self-manages a two-track entrance animation:
// opacity ramps to 1 in ~0.18s while the offset
// translates from +50pt to 0 over ~0.42s (the visible "rises into
// place" motion). The fast opacity is intentional — by the time the
// bubble has finished translating, the fade is long since done, so
// the user only perceives a clean slide from below. Initial
// snapshot rows pass `animateEntrance: false`, which seeds the
// state to its final pose so they appear in place without motion.
private struct UserBubble: View {
    let text: String
    let attachmentImages: [UIImage]
    let animateEntrance: Bool
    let onOpenImage: (Int, [UIImage]) -> Void

    @State private var fadedIn: Bool
    @State private var translatedIn: Bool

    init(
        text: String,
        attachmentImages: [UIImage] = [],
        animateEntrance: Bool,
        onOpenImage: @escaping (Int, [UIImage]) -> Void = { _, _ in }
    ) {
        self.text = text
        self.attachmentImages = attachmentImages
        self.animateEntrance = animateEntrance
        self.onOpenImage = onOpenImage
        _fadedIn = State(initialValue: !animateEntrance)
        _translatedIn = State(initialValue: !animateEntrance)
    }

    /// Strips the `[image]` / `[N images]` preview prefix the bridge
    /// inserts to keep the chat-list lastMessage readable. The image
    /// thumbnails above the bubble already say "this turn carried
    /// photos"; repeating it as text inside the bubble looks like a
    /// stutter, so we render only the user's actual caption (or hide
    /// the bubble entirely when the message was attachment-only).
    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = ["[image]", "[images]"]
        for prefix in patterns where trimmed.hasPrefix(prefix) {
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rest
        }
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let label = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            if label.hasSuffix(" images") || label.hasSuffix(" image") {
                let rest = String(trimmed[trimmed.index(after: close)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return rest
            }
        }
        return text
    }

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !attachmentImages.isEmpty {
                    AttachmentThumbnails(
                        images: attachmentImages,
                        onTap: { idx in onOpenImage(idx, attachmentImages) }
                    )
                }
                let visible = displayText
                if !visible.isEmpty {
                    Text(visible)
                        .font(Typography.chatBodyFont)
                        .tracking(-0.2)
                        .foregroundStyle(Palette.userBubbleText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: AppLayout.userBubbleRadius, style: .continuous)
                                .fill(Palette.userBubbleFill)
                        )
                }
            }
        }
        .opacity(fadedIn ? 1 : 0)
        // Large offset so the bubble visually starts from the composer
        // area and rises into place, matching familiar chat apps.
        .offset(y: translatedIn ? 0 : 320)
        // `.animation(_:value:)` ties each property to its own value
        // trigger, avoiding cross-property transactions or run-loop hops.
        .animation(.easeOut(duration: 0.08), value: fadedIn)
        // Deterministic decelerating cubic curve: starts fast, eases
        // slightly at the end, and finishes exactly at `duration` with
        // no overshoot or settle.
        .animation(.timingCurve(0.0, 0.55, 0.45, 1.0, duration: 0.32), value: translatedIn)
        .onAppear {
            guard animateEntrance else { return }
            fadedIn = true
            translatedIn = true
        }
    }
}

/// Image previews stacked above the user bubble. Mirrors the composer's
/// chip aspect ratio so the photo "rises" into the conversation
/// without resizing — the chip the user picked in the composer becomes
/// the bubble thumbnail in place. Single image fills the trailing
/// edge; two or more lay out as a wrapping row capped at 220pt wide
/// each so they stay legible without dominating short captions.
private struct AttachmentThumbnails: View {
    let images: [UIImage]
    let onTap: (Int) -> Void

    var body: some View {
        if images.count == 1, let single = images.first {
            Button {
                Haptics.tap()
                onTap(0)
            } label: {
                Image(uiImage: single)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .center, spacing: 6) {
                ForEach(images.indices, id: \.self) { idx in
                    Button {
                        Haptics.tap()
                        onTap(idx)
                    } label: {
                        Image(uiImage: images[idx])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#if canImport(UIKit)
struct ImageViewerSelection: Identifiable {
    let id = UUID()
    let images: [UIImage]
    let startIndex: Int
}
#endif

private struct MessageActions: View {
    let content: String
    @State private var copied: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            copyButton
        }
    }

    private var copyButton: some View {
        Button(action: copy) {
            ZStack {
                if copied {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    CopyIconView(color: Palette.textTertiary, lineWidth: 1.55)
                        .frame(width: 14, height: 14)
                        .transition(.opacity)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
        Haptics.success()
        withAnimation(.easeOut(duration: 0.18)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
        }
    }
}

private struct ReasoningDisclosure: View {
    let text: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(BodyFont.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text("Reasoning")
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                Text(text)
                    .font(Typography.secondaryFont)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                            .fill(Palette.border)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview("Chat detail") {
    let store = BridgeStore.mock()
    return ChatDetailView(
        store: store,
        chatId: MockData.chats[0].id,
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
