import SwiftUI

struct MiniMonthView: View {
    @ObservedObject var manager: CalendarManager

    private var calendar: Foundation.Calendar { manager.foundationCalendar }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayRow
            ForEach(weeks(), id: \.first) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { date in
                        cell(for: date)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: CalendarTokens.Geometry.miniMonthHeight)
        .background(CalendarTokens.Surface.miniMonth)
    }

    private var header: some View {
        HStack {
            Button { withAnimation(CalendarTokens.Motion.miniMonthStep) { manager.stepMiniMonth(forward: false) } } label: {
                LucideIcon(.chevronLeft, size: 10)
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(headerLabel)
                .font(.system(size: CalendarTokens.TypeSize.miniMonthHeader, weight: .medium))
                .foregroundColor(CalendarTokens.Ink.primary)
            Spacer()
            Button { withAnimation(CalendarTokens.Motion.miniMonthStep) { manager.stepMiniMonth(forward: true) } } label: {
                LucideIcon(.chevronRight, size: 10)
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { d in
                Text(d.uppercased())
                    .font(.system(size: CalendarTokens.TypeSize.miniMonthWeekday, weight: .medium))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdays: [String] {
        var s = calendar.veryShortWeekdaySymbols
        let rot = calendar.firstWeekday - 1
        if rot > 0 { s = Array(s[rot...]) + Array(s[..<rot]) }
        return s
    }

    private var headerLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMMM yyyy"
        return f.string(from: manager.miniMonthAnchor).capitalized
    }

    private func cell(for date: Date) -> some View {
        let isInMonth = calendar.component(.month, from: date) == calendar.component(.month, from: manager.miniMonthAnchor)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: manager.selectedDate)
        return ZStack {
            if isToday {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CalendarTokens.Accent.todayFill)
                    .frame(width: 18, height: 18)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(CalendarTokens.Accent.todayFill, lineWidth: 1)
                    .frame(width: 18, height: 18)
            }
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: CalendarTokens.TypeSize.miniMonthDay,
                               weight: isToday ? .semibold : .regular))
                .foregroundColor(
                    isToday ? .white :
                    (isInMonth ? CalendarTokens.Ink.primary : CalendarTokens.Ink.secondary.opacity(0.5))
                )
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            manager.goTo(date: date)
        }
    }

    private func weeks() -> [[Date]] {
        let anchor = manager.miniMonthAnchor
        let monthStart = manager.startOfMonth(for: anchor)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthStart)
        guard let gridStart = calendar.date(from: comps) else { return [] }
        var weeks: [[Date]] = []
        var cursor = gridStart
        while cursor < monthEnd {
            var row: [Date] = []
            for _ in 0..<7 {
                row.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            weeks.append(row)
        }
        return weeks
    }
}
