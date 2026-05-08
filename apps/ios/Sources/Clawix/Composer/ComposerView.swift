import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Floating Liquid Glass composer. Lives over the transcript: the
// chat content fades behind the glass capsule (real refraction on
// iOS 26 thanks to `glassEffect`) while the round white send button
// floats just inside the right edge of the pill. The pill is
// intentionally tall so the bar reads as a primary surface, not as
// a thin toolbar.
//
// The "+" button opens the attachment sheet (camera, recent photos,
// "Todas las fotos" full library). Selected images render as chips
// above the pill until the user taps send.

struct ComposerView: View {
    @Binding var text: String
    @Binding var attachments: [ComposerAttachment]
    let onSend: () -> Void
    var onMicTap: () -> Void = {}
    var onVoiceTap: () -> Void = {}
    var onStop: () -> Void = {}
    /// `true` while the chat has an in-flight turn. The composer hides
    /// the mic / voice / send affordances and shows a single white
    /// circle with a black square instead, mirroring the macOS app.
    var hasActiveTurn: Bool = false
    var autofocusOnAppear: Bool = false
    /// `true` when the chat already has messages and the composer should
    /// shed its "first prompt" generosity (slightly tighter pill, smaller
    /// trailing controls). Currently a placeholder hook — the visuals
    /// stay in sync via the same metrics, but the parent toggles it on
    /// non-empty transcripts so we can fine-tune later without touching
    /// callers.
    var compact: Bool = false
    /// Bumped by the parent right after a send to force the underlying
    /// TextField to remount, so the soft keyboard cannot leak stale
    /// candidates / autocomplete state from the previous prompt into
    /// the next one.
    var resetToken: Int = 0

    @FocusState private var focused: Bool
    @State private var didAutofocus: Bool = false
    @State private var showAttachmentSheet: Bool = false
    @State private var showCamera: Bool = false
    @State private var showLibraryPicker: Bool = false
    @State private var isExpanded: Bool = false
    /// Cached "should the expand affordance show?" derived from `text`.
    /// Computing it inside `body` was scanning the entire string on
    /// every keystroke even for short prompts; this drives the same
    /// affordance from a single `.onChange` so the body stays cheap.
    @State private var showExpandButton: Bool = false
    @Namespace private var glassNS

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                attachmentChips
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // The trailing controls (mic + white send circle) are
            // intentionally rendered as a SIBLING of the
            // `GlassEffectContainer`, not a child of the pill. iOS 26
            // Liquid Glass morphs every shape inside the container
            // when the pill grows leftward to swallow the "+", and
            // the white circle was getting visually "absorbed" into
            // that morph (translating left and deforming back). By
            // overlaying it from outside the container, the glass
            // can morph all it wants without dragging the circle
            // along.
            // Bottom-trailing so mic + send stay anchored to the floor
            // of the pill as it grows multi-line. The 5.5pt bottom pad
            // matches the (45 - 34) / 2 inset they had when centered, so
            // a single-line pill still reads as visually equidistant.
            ZStack(alignment: .bottomTrailing) {
                GlassEffectContainer(spacing: 0) {
                    HStack(alignment: .bottom, spacing: compact ? 0 : 8) {
                        if !compact {
                            plusCircle
                        }
                        mainPill
                    }
                }
                trailingButton
                    .padding(.trailing, 5)
                    .padding(.bottom, 5.5)
            }
        }
        .padding(.horizontal, 14)
        .animation(.easeOut(duration: 0.18), value: attachments)
        .animation(.easeOut(duration: 0.18), value: hasActiveTurn)
        .animation(.easeOut(duration: 0.18), value: canSend)
        // No implicit animation on `compact`: the previous `.smooth`
        // curve interpolated both the outer HStack layout (removing
        // `plusCircle`) and the pill's glass shape morph, which made
        // the trailing controls visually drift left and back during
        // the transition. Letting the layout snap keeps the white
        // circle / mic / placeholder anchored.
        // React to both `onAppear` and `onChange`: the parent flips
        // `isFreshChat` in its own `onAppear`, which runs after the
        // child's first appearance, so this view can initially see
        // `autofocusOnAppear: false`. The small delay lets the push
        // transition settle before the keyboard animates in.
        .onAppear {
            tryAutofocus()
            recomputeShowExpand(text)
        }
        .onChange(of: autofocusOnAppear) { _, _ in tryAutofocus() }
        .onChange(of: text) { _, newValue in recomputeShowExpand(newValue) }
        .onChange(of: resetToken) { _, _ in recomputeShowExpand(text) }
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheetView(
                onCamera: {
                    showAttachmentSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        showCamera = true
                    }
                },
                onAllPhotos: {
                    showAttachmentSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        showLibraryPicker = true
                    }
                },
                onSelect: { images in
                    appendImages(images)
                    showAttachmentSheet = false
                },
                onDismiss: {
                    showAttachmentSheet = false
                }
            )
            .presentationDetents([.height(260), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.surface)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                onCaptured: { image in
                    appendImages([image])
                    showCamera = false
                    Haptics.success()
                },
                onOpenLibrary: {
                    showCamera = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        showLibraryPicker = true
                    }
                },
                onCancel: { showCamera = false }
            )
        }
        .sheet(isPresented: $showLibraryPicker) {
            PhotoLibraryPicker(
                selectionLimit: 8,
                onPicked: { images in
                    appendImages(images)
                    showLibraryPicker = false
                },
                onCancel: { showLibraryPicker = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isExpanded) {
            ExpandedComposerSheet(
                text: $text,
                attachments: $attachments,
                canSend: canSend,
                onSend: {
                    isExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        triggerSend()
                    }
                },
                onCollapse: { isExpanded = false }
            )
            .presentationBackground(.clear)
        }
    }

    private func tryAutofocus() {
        guard autofocusOnAppear, !didAutofocus else { return }
        didAutofocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focused = true
        }
    }

    private var plusCircle: some View {
        Button(action: {
            Haptics.tap()
            showAttachmentSheet = true
        }) {
            LucideIcon(.plus, size: 17)
                .foregroundStyle(Color.white)
                .frame(width: 45, height: 45)
                .glassEffect(.regular.tint(Color.black.opacity(0.28)), in: Circle())
                .glassEffectID("composer-plus", in: glassNS)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachments")
    }

    private var inlinePlusButton: some View {
        Button(action: {
            Haptics.tap()
            showAttachmentSheet = true
        }) {
            LucideIcon(.plus, size: 17)
                .foregroundStyle(Color.white)
                .frame(width: 45, height: 37)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachments")
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    chip(for: attachment)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 76)
    }

    private func chip(for attachment: ComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: attachment.preview)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
            Button(action: { remove(attachment) }) {
                LucideIcon(.x, size: 9)
                    .foregroundStyle(Color.black)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .frame(width: 70, height: 70)
        .padding(.top, 4)
    }

    private func remove(_ attachment: ComposerAttachment) {
        Haptics.tap()
        attachments.removeAll { $0.id == attachment.id }
    }

    private func appendImages(_ images: [UIImage]) {
        let new = images.map { ComposerAttachment(preview: $0) }
        attachments.append(contentsOf: new)
        if !new.isEmpty { Haptics.selection() }
    }

    private var mainPill: some View {
        // Geometry choices keep the placeholder + plus icon centers
        // anchored across the `compact` flip, so the only visible
        // change at send-time is that the pill grows leftward to wrap
        // the "+":
        //   • inline plus is 45pt wide (matches the outer plusCircle).
        //   • mainPill leading pad is 0 in compact so the inline plus
        //     sits flush against the pill's leading curve at the same
        //     screen X the outer plus used to occupy.
        //   • field leading pad is 24 in compact (vs 14 non-compact)
        //     to compensate for the geometry shift so the placeholder
        //     text stays at the same screen X.
        //
        // The trailing controls are rendered OUTSIDE this view (as a
        // sibling of the GlassEffectContainer in the parent ZStack);
        // we just need to reserve trailing space in the field so text
        // doesn't slide under them.
        let trailingReserve: CGFloat = 70 /* mic + spacing + circle */
            + 8 /* breathing room */
            + (showExpandButton ? 28 : 0)

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 0) {
                if compact {
                    inlinePlusButton
                }
                field
                    .padding(.leading, compact ? 24 : 14)
                    .padding(.trailing, trailingReserve)
            }
            if showExpandButton {
                expandButton
                    .padding(.trailing, 4)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(minHeight: 37)
        .padding(.leading, compact ? 0 : 6)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .glassEffect(
            .regular.tint(Color.black.opacity(0.28)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .glassEffectID("composer-pill", in: glassNS)
        .animation(.easeOut(duration: 0.18), value: showExpandButton)
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("Ask Clawix")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textSecondary.opacity(0.65))
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...9)
                .focused($focused)
                .tint(Color.white)
                .id(resetToken)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
    }

    /// Recomputes the expand-affordance visibility from the current
    /// `text`. Called from `.onChange(of: text)` and once on appear so
    /// the pill is naturally tall enough (≥ 3 visual lines) before the
    /// icon shows. Cheap to compute, but cheap × every keystroke turns
    /// into measurable jank for long prompts; staying out of `body`
    /// means the keystroke path no longer scans the whole string.
    private func recomputeShowExpand(_ value: String) {
        let newShow: Bool
        if value.count > 90 {
            newShow = true
        } else {
            var newlines = 0
            for ch in value where ch == "\n" {
                newlines += 1
                if newlines >= 2 { break }
            }
            newShow = newlines >= 2
        }
        if newShow != showExpandButton {
            showExpandButton = newShow
        }
    }

    private var expandButton: some View {
        Button {
            Haptics.tap()
            focused = false
            isExpanded = true
        } label: {
            LucideIcon(.maximize2, size: 12)
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand composer")
    }

    /// Stable trailing layout: mic + white circle, always rendered.
    /// Only the glyph inside the white circle morphs (arrow / waveform
    /// / stop square) so the surrounding bubble never shifts when the
    /// chat enters or leaves an active turn.
    private var trailingButton: some View {
        HStack(spacing: 16) {
            Button(action: onMicTap) {
                MicIcon(lineWidth: 6)
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mic")

            Button(action: triggerPrimary) {
                ZStack {
                    Circle().fill(Color.white)
                    primaryGlyph
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryLabel)
        }
    }

    @ViewBuilder
    private var primaryGlyph: some View {
        if hasActiveTurn {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.black)
                .frame(width: 12, height: 12)
                .transition(.scale.combined(with: .opacity))
                .id("glyph-stop")
        } else if canSend {
            LucideIcon(.arrowUp, size: 15)
                .foregroundStyle(Color.black)
                .transition(.scale.combined(with: .opacity))
                .id("glyph-send")
        } else {
            VoiceWaveformIcon()
                .foregroundColor(Color.black)
                .frame(width: 19, height: 19)
                .transition(.scale.combined(with: .opacity))
                .id("glyph-voice")
        }
    }

    private var primaryLabel: String {
        if hasActiveTurn { return "Stop response" }
        if canSend { return "Send" }
        return "Voice"
    }

    private func triggerPrimary() {
        if hasActiveTurn {
            triggerStop()
        } else if canSend {
            triggerSend()
        } else {
            onVoiceTap()
        }
    }

    private func triggerStop() {
        Haptics.tap()
        onStop()
    }

    private func triggerSend() {
        guard canSend else { return }
        Haptics.send()
        onSend()
    }
}

#Preview("Composer empty") {
    StatefulPreviewWrapper("") { binding in
        ComposerView(text: binding, attachments: .constant([]), onSend: {})
            .preferredColorScheme(.dark)
            .padding(.vertical, 40)
            .background(Palette.background)
    }
}

#Preview("Composer typing") {
    StatefulPreviewWrapper("Help me find the bug in the receive loop") { binding in
        ComposerView(text: binding, attachments: .constant([]), onSend: {})
            .preferredColorScheme(.dark)
            .padding(.vertical, 40)
            .background(Palette.background)
    }
}

private struct ExpandedComposerSheet: View {
    @Binding var text: String
    @Binding var attachments: [ComposerAttachment]
    let canSend: Bool
    let onSend: () -> Void
    let onCollapse: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Surface
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    TextField("Ask Clawix", text: $text, axis: .vertical)
                        .font(Typography.bodyFont)
                        .foregroundStyle(Palette.textPrimary)
                        .tint(Color.white)
                        .focused($focused)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.trailing, 36)
                        .padding(.bottom, 80)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.78))
            )
            .overlay(alignment: .bottomTrailing) {
                if canSend {
                    Button(action: onSend) {
                        LucideIcon(.arrowUp, size: 15)
                            .foregroundStyle(Color.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }

            // Collapse icon
            Button(action: onCollapse) {
                LucideIcon(.minimize2, size: 12)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .accessibilityLabel("Collapse composer")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Color.black.opacity(0.35)
                .ignoresSafeArea()
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                focused = true
            }
        }
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder _ content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}
