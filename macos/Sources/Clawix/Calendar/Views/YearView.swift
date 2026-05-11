import SwiftUI

private let YearTileSpacing: CGFloat = 24
private let YearOuterInset: CGFloat = 24
private let YearColumnsCount: Int = 3
private let YearRowsCount: Int = 4

struct YearView: View {
    @ObservedObject var manager: CalendarManager

    private var calendar: Foundation.Calendar { manager.foundationCalendar }

    var body: some View {
        GeometryReader { geo in
            grid(in: geo.size)
        }
        .background(CalendarTokens.Surface.window)
    }

    private func grid(in size: CGSize) -> some View {
        let interiorW: CGFloat = CGFloat(YearColumnsCount - 1) * YearTileSpacing
        let interiorH: CGFloat = CGFloat(YearRowsCount - 1) * YearTileSpacing
        let usableW: CGFloat = size.width - 2 * YearOuterInset - interiorW
        let usableH: CGFloat = size.height - 2 * YearOuterInset - interiorH
        let tileWidth: CGFloat = usableW / CGFloat(YearColumnsCount)
        let tileHeight: CGFloat = usableH / CGFloat(YearRowsCount)
        let tileSize = CGSize(width: tileWidth, height: tileHeight)
        let year = calendar.component(.year, from: manager.selectedDate)
        return VStack(spacing: YearTileSpacing) {
            ForEach(0..<YearRowsCount, id: \.self) { row in
                yearRow(row: row, year: year, tileSize: tileSize)
            }
        }
        .padding(YearOuterInset)
    }

    private func yearRow(row: Int, year: Int, tileSize: CGSize) -> some View {
        HStack(spacing: YearTileSpacing) {
            ForEach(0..<YearColumnsCount, id: \.self) { col in
                MiniMonthTile(monthIndex: row * YearColumnsCount + col,
                              year: year,
                              manager: manager,
                              size: tileSize)
            }
        }
    }
}

private struct MiniMonthTile: View {
    let monthIndex: Int
    let year: Int
    @ObservedObject var manager: CalendarManager
    let size: CGSize
    @State private var hovered: Bool = false

    private var calendar: Foundation.Calendar { manager.foundationCalendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CalendarTokens.Ink.primary)
            Rectangle().fill(CalendarTokens.Divider.hairline).frame(height: 1)
            weekdayRow
            ForEach(weeks(), id: \.first) { week in
                row(week)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: size.width, height: size.height)
        .background(hovered ? Color.white.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if let date = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: 1)) {
                manager.goTo(date: date)
                manager.setViewMode(.month)
            }
        }
        .animation(CalendarTokens.Motion.eventHover, value: hovered)
    }

    private var monthName: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMMM"
        if let d = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: 1)) {
            return f.string(from: d).capitalized
        }
        return ""
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

    private func row(_ week: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { date in
                cell(for: date)
            }
        }
    }

    private func cell(for date: Date) -> some View {
        let inMonth = calendar.component(.month, from: date) == monthIndex + 1
        let isToday = calendar.isDateInToday(date)
        return ZStack {
            if isToday {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CalendarTokens.Accent.todayFill)
                    .frame(width: 18, height: 18)
            }
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: CalendarTokens.TypeSize.miniMonthDay,
                               weight: isToday ? .semibold : .regular))
                .foregroundColor(numberColor(inMonth: inMonth, isToday: isToday))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
    }

    private func numberColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return .white }
        return inMonth ? CalendarTokens.Ink.primary : CalendarTokens.Ink.secondary.opacity(0.5)
    }

    private func weeks() -> [[Date]] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: 1)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }
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
