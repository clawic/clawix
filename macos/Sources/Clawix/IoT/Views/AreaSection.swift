import SwiftUI

/// Grouper for `IoTThingsView`. Header with area label + count;
/// adaptive grid of `ThingCard`s underneath. Collapsible on header
/// tap (state stored in `@AppStorage` so the user's preference
/// survives relaunches).
struct AreaSection: View {
    let label: String
    let things: [ThingRecord]
    var onSelect: (ThingRecord) -> Void

    @AppStorage private var collapsed: Bool

    init(label: String, things: [ThingRecord], onSelect: @escaping (ThingRecord) -> Void) {
        self.label = label
        self.things = things
        self.onSelect = onSelect
        let key = "clawix.iot.area.collapsed.\(label.replacingOccurrences(of: " ", with: "_"))"
        self._collapsed = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.20)) {
                    collapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(verbatim: label)
                        .font(BodyFont.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    Text(verbatim: "\(things.count)")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                    spacing: 12,
                ) {
                    ForEach(things) { thing in
                        ThingCard(thing: thing, onTap: { onSelect(thing) })
                    }
                }
            }
        }
    }
}
