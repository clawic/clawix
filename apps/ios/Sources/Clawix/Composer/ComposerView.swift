import SwiftUI

// Floating Liquid Glass composer. Lives over the transcript: the
// chat content fades behind the glass capsule (real refraction on
// iOS 26 thanks to `glassEffect`) while the round white send button
// floats just inside the right edge of the pill. The pill is
// intentionally tall so the bar reads as a primary surface, not as
// a thin toolbar.

struct ComposerView: View {
    @Binding var text: String
    let onSend: () -> Void
    var autofocusOnAppear: Bool = false

    @FocusState private var focused: Bool
    @State private var didAutofocus: Bool = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            plusCircle
            mainPill
        }
        .padding(.horizontal, 14)
        // React to both `onAppear` and `onChange`: the parent flips
        // `isFreshChat` in its own `onAppear`, which runs after the
        // child's first appearance, so this view can initially see
        // `autofocusOnAppear: false`. The small delay lets the push
        // transition settle before the keyboard animates in.
        .onAppear { tryAutofocus() }
        .onChange(of: autofocusOnAppear) { _, _ in tryAutofocus() }
    }

    private func tryAutofocus() {
        guard autofocusOnAppear, !didAutofocus else { return }
        didAutofocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focused = true
        }
    }

    private var plusCircle: some View {
        Button(action: { Haptics.tap() }) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Circle())
                Image(systemName: "plus")
                    .font(BodyFont.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachments")
    }

    private var mainPill: some View {
        HStack(alignment: .center, spacing: 8) {
            field
                .padding(.leading, 14)
            trailingButton
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Capsule(style: .continuous))
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
                .lineLimit(1...6)
                .focused($focused)
                .tint(Color.white)
        }
        .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
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
        ComposerView(text: binding, onSend: {})
            .preferredColorScheme(.dark)
            .padding(.vertical, 40)
            .background(Palette.background)
    }
}

#Preview("Composer typing") {
    StatefulPreviewWrapper("Help me find the bug in the receive loop") { binding in
        ComposerView(text: binding, onSend: {})
            .preferredColorScheme(.dark)
            .padding(.vertical, 40)
            .background(Palette.background)
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
