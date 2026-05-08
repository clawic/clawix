import SwiftUI

// Collapsible "Razonando…" block that shows the assistant's reasoning
// stream (item/reasoning/textDelta) above the visible answer.
//
// Style aligned with the rest of the chat surface: subtle colour, small
// text, no heavy chrome — visible but not stealing attention from the
// final answer.

struct ReasoningBlock: View {
    let text: String
    let isStreaming: Bool

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon.auto(expanded ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundColor(Color(white: 0.50))
                    Text(headerLabel)
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(Color(white: 0.62))
                    if isStreaming {
                        ReasoningPulseDot()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
            }
        }
    }

    private var headerLabel: String {
        isStreaming
            ? String(localized: "Reasoning", bundle: AppLocale.bundle, locale: AppLocale.current)
            : String(localized: "Reasoning", bundle: AppLocale.bundle, locale: AppLocale.current)
    }
}

private struct ReasoningPulseDot: View {
    @State private var phase: CGFloat = 0.4

    var body: some View {
        Circle()
            .fill(Color(white: 0.6))
            .frame(width: 5, height: 5)
            .opacity(Double(phase))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    phase = 1.0
                }
            }
    }
}
