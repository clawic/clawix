import SwiftUI

struct CalendarSubSidebar: View {
    @ObservedObject var manager: CalendarManager

    var body: some View {
        VStack(spacing: 0) {
            sourcesList
            Spacer(minLength: 0)
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            MiniMonthView(manager: manager)
        }
        .frame(width: CalendarTokens.Geometry.subSidebarWidth)
        .background(CalendarTokens.Surface.subSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CalendarTokens.Divider.seam).frame(width: 1)
        }
    }

    private var sourcesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groupedSources(), id: \.id) { group in
                    sectionHeader(group.title)
                    ForEach(group.calendars) { source in
                        row(for: source)
                    }
                    Spacer().frame(height: 12)
                }
            }
            .padding(.horizontal, CalendarTokens.Spacing.subSidebarInset)
            .padding(.top, 12)
        }
        .thinScrollers()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: CalendarTokens.TypeSize.sourceHeader, weight: .medium))
            .tracking(0.5)
            .foregroundColor(CalendarTokens.Ink.secondary)
            .padding(.vertical, 4)
    }

    private func row(for source: CalendarSource) -> some View {
        let isVisible = manager.isVisible(source)
        return Button {
            manager.toggleSourceVisibility(source)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: CalendarTokens.Radius.calendarSwatch, style: .continuous)
                        .fill(isVisible ? source.color : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: CalendarTokens.Radius.calendarSwatch, style: .continuous)
                                .stroke(source.color, lineWidth: 1)
                        )
                        .frame(width: 11, height: 11)
                    if isVisible {
                        LucideIcon(.check, size: 7)
                            .foregroundColor(.white)
                    }
                }
                Text(source.title)
                    .font(.system(size: CalendarTokens.TypeSize.sourceRow))
                    .foregroundColor(CalendarTokens.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: CalendarTokens.Spacing.subSidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupedSources() -> [CalendarSourceGroup] {
        let grouped = Dictionary(grouping: manager.sources, by: { $0.sourceID })
        return grouped
            .map { key, value in
                CalendarSourceGroup(id: key, title: key.capitalized, calendars: value)
            }
            .sorted { $0.title < $1.title }
    }
}
