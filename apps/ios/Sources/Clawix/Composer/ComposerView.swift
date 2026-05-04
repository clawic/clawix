import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let onSend: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            field
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Send a message")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: Layout.composerCornerRadius, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.composerCornerRadius, style: .continuous)
                .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
    }

    private var sendButton: some View {
        Button(action: triggerSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canSend ? Palette.background : Palette.textTertiary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(canSend ? Color.white : Palette.cardFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
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
            .background(Palette.background)
    }
}

#Preview("Composer typing") {
    StatefulPreviewWrapper("Help me find the bug in the receive loop") { binding in
        ComposerView(text: binding, onSend: {})
            .preferredColorScheme(.dark)
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
