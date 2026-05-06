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
            GlassEffectContainer(spacing: 0) {
                HStack(alignment: .bottom, spacing: compact ? 0 : 8) {
                    if !compact {
                        plusCircle
                    }
                    mainPill
                }
            }
        }
        .padding(.horizontal, 14)
        .animation(.easeOut(duration: 0.18), value: attachments)
        .animation(.smooth(duration: 0.42), value: compact)
        // React to both `onAppear` and `onChange`: the parent flips
        // `isFreshChat` in its own `onAppear`, which runs after the
        // child's first appearance, so this view can initially see
        // `autofocusOnAppear: false`. The small delay lets the push
        // transition settle before the keyboard animates in.
        .onAppear { tryAutofocus() }
        .onChange(of: autofocusOnAppear) { _, _ in tryAutofocus() }
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
            .presentationDetents([.fraction(0.55), .large])
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
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
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
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 37)
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
                Image(systemName: "xmark")
                    .font(BodyFont.system(size: 9, weight: .bold))
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
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .bottom, spacing: 4) {
                if compact {
                    inlinePlusButton
                }
                field
                    .padding(.leading, compact ? 2 : 14)
                    .padding(.trailing, showExpandButton ? 28 : 0)
                trailingButton
            }
            if showExpandButton {
                expandButton
                    .padding(.trailing, 4)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(minHeight: 37)
        .padding(.leading, compact ? 10 : 6)
        .padding(.trailing, 7)
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
        }
        .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
    }

    private var showExpandButton: Bool {
        // Only surface the expand affordance once the pill is naturally
        // tall enough that the top-right icon doesn't collide with the
        // bottom-right send/mic cluster (≥ 3 visual lines).
        let newlines = text.filter { $0 == "\n" }.count
        return newlines >= 2 || text.count > 90
    }

    private var expandButton: some View {
        Button {
            Haptics.tap()
            focused = false
            isExpanded = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand composer")
    }

    @ViewBuilder
    private var trailingButton: some View {
        if canSend {
            Button(action: triggerSend) {
                Image(systemName: "arrow.up")
                    .font(BodyFont.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else {
            HStack(spacing: 16) {
                Button(action: { Haptics.tap() }) {
                    MicIcon(lineWidth: 5)
                        .foregroundColor(Color(white: 0.6))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mic")

                Button(action: { Haptics.tap() }) {
                    VoiceWaveformIcon()
                        .foregroundColor(Color.black)
                        .frame(width: 16, height: 16)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice")
            }
            .transition(.scale.combined(with: .opacity))
        }
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
                        Image(systemName: "arrow.up")
                            .font(BodyFont.system(size: 15, weight: .bold))
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
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
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
