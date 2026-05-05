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

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            plusButton
            field
            trailingButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Capsule(style: .continuous))
        .padding(.horizontal, 14)
    }

    private var plusButton: some View {
        Button(action: {}) {
            Image(systemName: "plus")
                .font(BodyFont.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attachments")
    }

    private var field: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("Ask Clawix")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...6)
                .focused($focused)
                .tint(Color.white)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
            Button(action: {}) {
                MicIcon(lineWidth: 4)
                    .foregroundColor(Color.black)
                    .frame(width: 17, height: 17)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice")
        }
    }

    private func triggerSend() {
        guard canSend else { return }
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
