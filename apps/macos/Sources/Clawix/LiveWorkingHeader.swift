import SwiftUI

// "Working for Xm Ys" header rendered at the top of an in-flight
// assistant bubble while the timeline is auto-expanded. Sits in the
// same slot the collapsed "N previous messages" disclosure occupies
// once the turn finishes; the swap happens in MessageRow when the
// streaming flag flips.

struct LiveWorkingHeader: View {
    let summary: WorkSummary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
            Text(L10n.workingFor(seconds: summary.elapsedSeconds(asOf: ctx.date)))
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
