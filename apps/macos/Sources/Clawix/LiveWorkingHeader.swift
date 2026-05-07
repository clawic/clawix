import SwiftUI

// Streaming-state header rendered at the top of an in-flight assistant
// bubble before the final reply has started arriving. Two visual states:
//
//   • "Working" (no seconds) while the timeline still holds only the
//     first reasoning chunk being typed.
//   • "Working for 6s" (live ticking) once a second action has begun
//     (the first item has finished and a tool/second reasoning chunk has
//     opened), so the user perceives the elapsed-time read.
//
// Once `content` becomes non-empty (final reply has started) the bubble
// swaps this header for `WorkSummaryHeader`, which carries the chevron
// affordance to expand the now-collapsed timeline.

struct LiveWorkingHeader: View {
    let summary: WorkSummary
    /// Number of entries currently in the assistant timeline. Drives the
    /// "Working" → "Working for Xs" handoff: while the very first
    /// reasoning chunk is the only thing in the timeline we don't show
    /// seconds, the moment a second entry opens we start ticking.
    let timelineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var label: some View {
        if timelineCount <= 1 {
            Text(L10n.working)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                Text(L10n.workingFor(seconds: summary.elapsedSeconds(asOf: ctx.date)))
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
