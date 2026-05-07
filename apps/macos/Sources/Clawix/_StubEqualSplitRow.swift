import SwiftUI

struct EqualSplitRow<Leading: View, Trailing: View>: View {
    let spacing: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> TupleView<(Leading, Trailing)>
    ) {
        let tuple = content().value
        self.spacing = spacing
        self.leading = tuple.0
        self.trailing = tuple.1
    }

    var body: some View {
        HStack(spacing: spacing) {
            leading.frame(maxWidth: .infinity, alignment: .leading)
            trailing.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
