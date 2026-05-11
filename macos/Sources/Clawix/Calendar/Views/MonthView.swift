import SwiftUI

struct MonthView: View {
    @ObservedObject var manager: CalendarManager

    private var calendar: Foundation.Calendar { manager.foundationCalendar }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            GeometryReader { geo in
                gridBody(in: geo.size)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: CalendarTokens.TypeSize.weekdayLegend, weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .frame(height: CalendarTokens.Geometry.weekdayHeader)
        .background(CalendarTokens.Surface.window)
    }

    private var weekdaySymbols: [String] {
        var symbols = calendar.shortWeekdaySymbols
        let rotation = calendar.firstWeekday - 1
        if rotation > 0 {
            symbols = Array(symbols[rotation...]) + Array(symbols[..<rotation])
        }
        return symbols.map { $0.uppercased() }
    }

    private func gridBody(in size: CGSize) -> some View {
        let weeks = weeksInVisibleMonth()
        let availableHeight: CGFloat = size.height
        let weekCount: CGFloat = CGFloat(weeks.count)
        let rawRowHeight: CGFloat = availableHeight / max(1, weekCount)
        let rowHeight: CGFloat = max(80, rawRowHeight)
        return VStack(spacing: 0) {
            ForEach(0..<weeks.count, id: \.self) { row in
                weekRow(weeks[row], height: rowHeight)
                if row < weeks.count - 1 {
                    Rectangle()
                        .fill(CalendarTokens.Divider.hairline)
                        .frame(height: 1)
                }
            }
        }
    }

    private func weekRow(_ days: [Date], height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<days.count, id: \.self) { col in
                cell(for: days[col], height: height)
                if col < days.count - 1 {
                    Rectangle()
                        .fill(CalendarTokens.Divider.hairline)
                        .frame(width: 1)
                }
            }
        }
        .frame(height: height)
    }

    private func cell(for date: Date, height: CGFloat) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: manager.selectedDate, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: manager.selectedDate)
        let events = manager.eventsForDay(date)
        let maxChips = max(1, Int((height - 26) / 20))
        let chips = Array(events.prefix(maxChips))
        let overflow = max(0, events.count - maxChips)

        return MonthCell(
            date: date,
            isToday: isToday,
            isCurrentMonth: isCurrentMonth,
            isSelected: isSelected,
            chips: chips,
            overflow: overflow,
            manager: manager
        )
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    private func weeksInVisibleMonth() -> [[Date]] {
        let (start, end) = manager.visibleRange(for: .month, anchor: manager.selectedDate)
        var weeks: [[Date]] = []
        var cursor = start
        while cursor < end {
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

private struct MonthCell: View {
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let isSelected: Bool
    let chips: [CalendarEvent]
    let overflow: Int
    @ObservedObject var manager: CalendarManager

    private var calendar: Foundation.Calendar { manager.foundationCalendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            dayNumber
            ForEach(chips) { ev in
                EventChip(event: ev,
                           color: manager.color(forCalendarID: ev.calendarID),
                           style: .monthRow)
            }
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.system(size: CalendarTokens.TypeSize.eventTime))
                    .foregroundColor(CalendarTokens.Ink.secondary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(CalendarTokens.Spacing.cellInset)
        .background(background)
        .overlay(selectionStroke)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            manager.goTo(date: date)
            manager.setViewMode(.day)
        }
        .onTapGesture {
            manager.selectedDate = date
        }
    }

    private var dayNumber: some View {
        HStack {
            ZStack {
                if isToday {
                    Circle()
                        .fill(CalendarTokens.Accent.todayFill)
                        .frame(width: 22, height: 22)
                }
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: CalendarTokens.TypeSize.cellDayNumber,
                                   weight: isToday ? .semibold : .regular))
                    .foregroundColor(numberColor)
                    .frame(width: 22, height: 22)
            }
            Spacer()
        }
    }

    private var numberColor: Color {
        if isToday { return .white }
        return isCurrentMonth ? CalendarTokens.Ink.primary : CalendarTokens.Ink.secondary
    }

    @ViewBuilder
    private var background: some View {
        if isToday {
            CalendarTokens.Accent.todayFaint
        } else if isSelected {
            CalendarTokens.Accent.todayFill.opacity(0.10)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var selectionStroke: some View {
        if isSelected && !isToday {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .stroke(CalendarTokens.Accent.todayFill.opacity(0.6), lineWidth: 1)
        }
    }
}
