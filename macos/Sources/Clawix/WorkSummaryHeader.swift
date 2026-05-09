import SwiftUI

// Elapsed-time disclosure shown above the assistant reply once the
// final answer has started arriving (or the turn has fully completed).
// Always reads "Worked for Xs" — the seconds tick live while the turn
// is still active and freeze on `turn/completed`. Tapping the chevron
// toggles the bound expansion state, which the surrounding bubble uses
// to reveal the upstream reasoning + tool timeline that was hidden the
// moment the final answer began.

struct WorkSummaryHeader: View {
    let summary: WorkSummary
    @Binding var expanded: Bool
    var onExpand: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosure
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclosure: some View {
        Button {
            let willExpand = !expanded
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
            if willExpand { onExpand() }
        } label: {
            // TimelineView re-renders once a second while the turn is
            // still active so the seconds counter is live; once
            // `endedAt` is set the period jumps to an hour and the value
            // freezes for free.
            TimelineView(.periodic(from: .now, by: summary.isActive ? 1.0 : 3600)) { ctx in
                HStack(spacing: 6) {
                    Text(L10n.workedFor(seconds: summary.elapsedSeconds(asOf: ctx.date)))
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                    LucideIcon(.chevronRight, size: 11)
                        .foregroundColor(Color(white: 0.42))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.16), value: expanded)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work summary")
    }
}
